import Foundation

/// Parses text-based tool calls from model responses.
/// Some models output tool calls as XML-style tags instead of using Ollama's native tool_calls field.
/// This parser detects and extracts tool calls from text content as a fallback mechanism.
internal struct TextToolCallParser: Sendable {

    /// Result of parsing tool calls from text
    struct ParseResult: Sendable {
        /// Successfully parsed tool calls
        let toolCalls: [ToolCall]
        /// Remaining text content after removing tool call tags
        let remainingContent: String
    }

    // MARK: - Main Parsing Entry Point

    /// Parse tool calls from text content
    /// - Parameter content: The text content that may contain tool calls
    /// - Returns: ParseResult with extracted tool calls and remaining content
    static func parse(_ content: String) -> ParseResult {
        guard !content.isEmpty else {
            return ParseResult(toolCalls: [], remainingContent: "")
        }

        // Try XML-style tool_call tags first (most common for Qwen/GLM)
        let xmlResult = parseXMLStyleToolCalls(content)
        if !xmlResult.toolCalls.isEmpty {
            return xmlResult
        }

        // Try function_call tags
        let funcResult = parseFunctionCallTags(content)
        if !funcResult.toolCalls.isEmpty {
            return funcResult
        }

        // No tool calls found
        return ParseResult(toolCalls: [], remainingContent: content)
    }

    // MARK: - XML-Style Parsing (<tool_call>...</tool_call>)

    /// Parse tool calls from XML-style tags
    /// Supports multiple formats:
    /// - JSON: `<tool_call>{"name": "tool_name", "arguments": {...}}</tool_call>`
    /// - GLM-style: `<tool_call>ToolName<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>`
    private static func parseXMLStyleToolCalls(_ content: String) -> ParseResult {
        var toolCalls: [ToolCall] = []
        var remainingContent = content

        // Pattern matches <tool_call>...</tool_call> (non-greedy)
        let pattern = #"<tool_call>\s*([\s\S]*?)\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ParseResult(toolCalls: [], remainingContent: content)
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        for match in matches {
            guard let innerRange = Range(match.range(at: 1), in: content) else { continue }
            let innerContent = String(content[innerRange])

            // Try JSON format first
            if let toolCall = parseToolCallJSON(innerContent) {
                toolCalls.append(toolCall)
            }
            // Try GLM-style XML format: ToolName<arg_key>key</arg_key><arg_value>value</arg_value>
            else if let toolCall = parseGLMStyleToolCall(innerContent) {
                toolCalls.append(toolCall)
            }
        }

        // Remove matched tool_call tags from content
        if !toolCalls.isEmpty {
            remainingContent = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: nsRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParseResult(toolCalls: toolCalls, remainingContent: remainingContent)
    }

    // MARK: - GLM-Style XML Parsing

    /// Parse GLM-style tool call format
    /// Format: `ToolName<arg_key>key1</arg_key><arg_value>value1</arg_value><arg_key>key2</arg_key><arg_value>value2</arg_value>`
    private static func parseGLMStyleToolCall(_ content: String) -> ToolCall? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it contains arg_key/arg_value pattern
        guard trimmed.contains("<arg_key>") && trimmed.contains("<arg_value>") else {
            return nil
        }

        // Extract tool name (everything before first <arg_key>)
        guard let firstArgKeyIndex = trimmed.range(of: "<arg_key>")?.lowerBound else {
            return nil
        }

        let toolName = String(trimmed[..<firstArgKeyIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return nil
        }

        // Extract all key-value pairs
        var arguments: [String: Any] = [:]

        // Pattern for <arg_key>key</arg_key><arg_value>value</arg_value>
        let argPattern = #"<arg_key>\s*(.*?)\s*</arg_key>\s*<arg_value>\s*([\s\S]*?)\s*</arg_value>"#
        guard let argRegex = try? NSRegularExpression(pattern: argPattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = argRegex.matches(in: trimmed, options: [], range: nsRange)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: trimmed),
                  let valueRange = Range(match.range(at: 2), in: trimmed) else {
                continue
            }

            let key = String(trimmed[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            arguments[key] = value
        }

        guard !arguments.isEmpty else {
            return nil
        }

        return createToolCall(name: toolName, arguments: arguments)
    }

    // MARK: - Function Call Tags Parsing (<function_call>...</function_call>)

    /// Parse tool calls from function_call tags
    private static func parseFunctionCallTags(_ content: String) -> ParseResult {
        var toolCalls: [ToolCall] = []
        var remainingContent = content

        let pattern = #"<function_call>\s*([\s\S]*?)\s*</function_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ParseResult(toolCalls: [], remainingContent: content)
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        for match in matches {
            guard let innerRange = Range(match.range(at: 1), in: content) else { continue }
            let innerContent = String(content[innerRange])

            if let toolCall = parseToolCallJSON(innerContent) {
                toolCalls.append(toolCall)
            }
        }

        if !toolCalls.isEmpty {
            remainingContent = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: nsRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParseResult(toolCalls: toolCalls, remainingContent: remainingContent)
    }

    // MARK: - JSON Parsing Helpers

    /// Parse a single tool call from JSON content
    /// Supports formats:
    /// - `{"name": "tool_name", "arguments": {...}}`
    /// - `{"function": {"name": "tool_name", "arguments": {...}}}`
    private static func parseToolCallJSON(_ jsonString: String) -> ToolCall? {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Format 1: {"name": "...", "arguments": {...}}
        if let name = json["name"] as? String {
            let arguments = json["arguments"] as? [String: Any] ?? [:]
            return createToolCall(name: name, arguments: arguments)
        }

        // Format 2: {"function": {"name": "...", "arguments": {...}}}
        if let function = json["function"] as? [String: Any],
           let name = function["name"] as? String {
            let arguments = function["arguments"] as? [String: Any] ?? [:]
            return createToolCall(name: name, arguments: arguments)
        }

        // Format 3: {"type": "function", "function": {...}}
        if json["type"] as? String == "function",
           let function = json["function"] as? [String: Any],
           let name = function["name"] as? String {
            let arguments = function["arguments"] as? [String: Any] ?? [:]
            return createToolCall(name: name, arguments: arguments)
        }

        return nil
    }

    /// Create a ToolCall from name and arguments
    private static func createToolCall(name: String, arguments: [String: Any]) -> ToolCall {
        return ToolCall(
            function: ToolCall.FunctionCall(
                name: name,
                arguments: arguments
            )
        )
    }

    // MARK: - Utility Methods

    /// Check if content appears to contain text-based tool calls
    /// This can be used for quick detection without full parsing
    static func containsToolCallPatterns(_ content: String) -> Bool {
        let patterns = [
            #"<tool_call>"#,
            #"<function_call>"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
                return true
            }
        }

        return false
    }
}
