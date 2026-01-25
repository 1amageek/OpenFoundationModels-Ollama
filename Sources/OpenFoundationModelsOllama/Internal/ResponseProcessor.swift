import Foundation

/// Result of processing a Message
enum ProcessedResponse: Sendable {
    case toolCalls([ToolCall])
    case content(String)
    case empty
}

/// Unified response processor for generate() and stream()
///
/// This struct centralizes all response normalization logic:
/// - Native tool_calls extraction
/// - Text-based tool call parsing from content
/// - Text-based tool call parsing from thinking field
/// - Thinking tag stripping (for models that output <think> tags in content)
/// - JSON extraction from mixed content
/// - Content/thinking fallback handling
struct ResponseProcessor: Sendable {

    // MARK: - Patterns

    /// Pattern to match <think>...</think> tags (including unclosed ones)
    private static let thinkTagPattern = try! NSRegularExpression(
        pattern: #"<think>[\s\S]*?</think>|<think>[\s\S]*$"#,
        options: [.caseInsensitive]
    )

    /// Pattern to match orphaned </think> tag and everything before it
    /// This handles cases where the model outputs thinking without opening <think> tag
    /// Example: "Okay, let me think... </think>\n{\"key\": \"value\"}"
    private static let orphanedThinkClosePattern = try! NSRegularExpression(
        pattern: #"^[\s\S]*</think>"#,
        options: [.caseInsensitive]
    )

    /// Pattern to match <content>...</content> tags
    private static let contentTagPattern = try! NSRegularExpression(
        pattern: #"<content>[\s\S]*?</content>"#,
        options: [.caseInsensitive]
    )

    /// Pattern to match markdown code blocks (```json ... ``` or ``` ... ```)
    /// Captures the content inside the code block
    private static let markdownCodeBlockPattern = try! NSRegularExpression(
        pattern: #"```(?:json)?\s*\n?([\s\S]*?)```"#,
        options: [.caseInsensitive]
    )

    /// Pattern to match JSON objects
    private static let jsonObjectPattern = try! NSRegularExpression(
        pattern: #"\{[\s\S]*\}"#,
        options: []
    )

    // MARK: - Process

    /// Process a Message and extract the appropriate response
    ///
    /// Priority order:
    /// 1. Native tool_calls (highest priority)
    /// 2. Text-based tool calls in content
    /// 3. Text-based tool calls in thinking field
    /// 4. Content with <think> tags stripped (for thinking models with think: false)
    /// 5. JSON extracted from content (fallback for mixed content)
    /// 6. Content (if non-empty)
    /// 7. Thinking (fallback for thinking models)
    ///
    /// - Parameter message: The Message from Ollama API
    /// - Returns: ProcessedResponse indicating what type of content was found
    func process(_ message: Message) -> ProcessedResponse {
        // 1. Native tool_calls (highest priority)
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            return .toolCalls(toolCalls)
        }

        // 2. Text-based tool calls in content
        if TextToolCallParser.containsToolCallPatterns(message.content) {
            let result = TextToolCallParser.parse(message.content)
            if !result.toolCalls.isEmpty {
                return .toolCalls(result.toolCalls)
            }
        }

        // 3. Text-based tool calls in thinking field
        if let thinking = message.thinking,
           TextToolCallParser.containsToolCallPatterns(thinking) {
            let result = TextToolCallParser.parse(thinking)
            if !result.toolCalls.isEmpty {
                return .toolCalls(result.toolCalls)
            }
        }

        // 4. Process content - strip <think> tags and extract clean content
        let processedContent = processContent(message.content)
        if !processedContent.isEmpty {
            return .content(processedContent)
        }

        // 5. Thinking (fallback for thinking models like lfm2.5-thinking)
        if let thinking = message.thinking, !thinking.isEmpty {
            // Also process thinking field to strip any <think> tags
            let processedThinking = processContent(thinking)
            if !processedThinking.isEmpty {
                return .content(processedThinking)
            }
            // If processing strips everything, use original
            return .content(thinking)
        }

        return .empty
    }

    // MARK: - Private Helpers

    /// Process content to extract clean response
    /// Step 1: Strip think tags to get actual content
    /// Step 2: Extract JSON from the content
    private func processContent(_ content: String) -> String {
        guard !content.isEmpty else { return "" }

        // Step 1: Strip think-related tags
        let strippedContent = stripThinkTags(from: content)

        // Step 2: Extract JSON from the stripped content
        if let json = extractJSONFromContent(from: strippedContent) {
            return json
        }

        // If no JSON found in stripped content, try original content
        if let json = extractJSONFromContent(from: content) {
            return json
        }

        // Return stripped content as-is (for non-JSON responses)
        return strippedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Think Tag Stripping

    /// Strip all think-related tags from content
    private func stripThinkTags(from content: String) -> String {
        var processed = content

        // Strip <content>...</content> tags
        if processed.contains("<content>") {
            processed = stripPattern(Self.contentTagPattern, from: processed)
        }

        // Strip orphaned </think> and everything before it
        if processed.contains("</think>") && !processed.contains("<think") {
            processed = stripPattern(Self.orphanedThinkClosePattern, from: processed)
        }

        // Strip <think>...</think> tags
        if processed.contains("<think") {
            processed = stripPattern(Self.thinkTagPattern, from: processed)
        }

        return processed
    }

    /// Strip pattern from content
    private func stripPattern(_ pattern: NSRegularExpression, from content: String) -> String {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return pattern.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }

    // MARK: - JSON Extraction

    /// Extract JSON from content (tries code block first, then raw JSON)
    private func extractJSONFromContent(from content: String) -> String? {
        // Priority 1: Extract from markdown code block
        if let json = extractJSONFromCodeBlock(from: content) {
            return json
        }

        // Priority 2: Extract raw JSON object
        if let json = extractJSON(from: content) {
            return json
        }

        return nil
    }

    /// Extract JSON from markdown code block (```json ... ``` or ``` ... ```)
    private func extractJSONFromCodeBlock(from content: String) -> String? {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        guard let match = Self.markdownCodeBlockPattern.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        let extracted = String(content[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's parseable JSON
        guard let data = extracted.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }

        return extracted
    }

    /// Extract raw JSON object from content
    private func extractJSON(from content: String) -> String? {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        guard let match = Self.jsonObjectPattern.firstMatch(in: content, options: [], range: range),
              let swiftRange = Range(match.range, in: content) else {
            return nil
        }

        let jsonString = String(content[swiftRange])

        // Validate it's actually parseable JSON
        guard let data = jsonString.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }

        return jsonString
    }
}
