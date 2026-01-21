import Foundation

/// Strategy pattern for model-specific behavior
///
/// This enum centralizes model-specific logic that was previously scattered
/// across multiple locations in the codebase (e.g., gpt-oss detection).
enum ModelStrategy: Sendable {
    /// GPT-OSS models require special handling for thinking mode and response formats
    case gptOss
    /// Standard Ollama models
    case standard

    // MARK: - Detection

    /// Detect the appropriate strategy for a given model name
    /// - Parameter modelName: The name of the model (e.g., "gpt-oss:20b", "llama3.2")
    /// - Returns: The appropriate ModelStrategy
    static func detect(modelName: String) -> ModelStrategy {
        modelName.lowercased().hasPrefix("gpt-oss") ? .gptOss : .standard
    }

    // MARK: - Thinking Mode

    /// The thinking mode to use for this model strategy
    var thinkingMode: ThinkingMode? {
        switch self {
        case .gptOss:
            return .enabled
        case .standard:
            return nil
        }
    }

    // MARK: - Response Format Handling

    /// Whether this model uses Harmony-style response format in system messages
    var usesHarmonyFormat: Bool {
        switch self {
        case .gptOss:
            return true
        case .standard:
            return false
        }
    }

    /// Process response format according to the model's requirements
    /// - Parameters:
    ///   - format: The original response format (may be nil)
    ///   - messages: The messages array to potentially modify
    /// - Returns: The response format to use in the API request (may be nil for gpt-oss)
    func processResponseFormat(
        format: ResponseFormat?,
        messages: inout [Message]
    ) -> ResponseFormat? {
        guard let format = format else { return nil }

        switch self {
        case .gptOss:
            // For gpt-oss models, add Response Formats to system message instead of using format parameter
            addHarmonyResponseFormat(to: &messages, format: format)
            return nil
        case .standard:
            // For other models, use format parameter and add user instructions
            addFormatInstructions(to: &messages, format: format)
            return format
        }
    }

    // MARK: - Private Helper Methods

    /// Add harmony response format to system message for gpt-oss models
    private func addHarmonyResponseFormat(to messages: inout [Message], format: ResponseFormat) {
        // Find system message and add Response Formats section
        for i in 0..<messages.count {
            if messages[i].role == .system {
                let currentContent = messages[i].content
                let harmonyFormat = generateHarmonyResponseFormat(format: format)

                // Add Response Formats section to system message
                let newContent = currentContent + "\n\n" + harmonyFormat

                messages[i] = Message(
                    role: .system,
                    content: newContent,
                    toolCalls: messages[i].toolCalls,
                    thinking: messages[i].thinking,
                    toolName: messages[i].toolName
                )
                return
            }
        }

        // If no system message exists, create one with the harmony format
        let harmonyFormat = generateHarmonyResponseFormat(format: format)
        let systemMessage = Message(role: .system, content: harmonyFormat)
        messages.insert(systemMessage, at: 0)
    }

    /// Generate harmony response format string
    private func generateHarmonyResponseFormat(format: ResponseFormat) -> String {
        switch format {
        case .jsonSchema(let container):
            var harmonyFormat = "# Response Formats\n\n## StructuredResponse\n\n"

            if let jsonData = try? JSONSerialization.data(withJSONObject: container.schema, options: []),
               let schemaString = String(data: jsonData, encoding: .utf8) {
                harmonyFormat += schemaString
            } else {
                // Fallback schema
                harmonyFormat += #"{"type":"object","properties":{}}"#
            }

            // Add explicit instructions for JSON output
            harmonyFormat += """


            # Output Instructions

            - You MUST output valid JSON only. No markdown, no code fences, no prose.
            - Output the JSON directly in your response content, NOT in thinking.
            - The JSON must conform exactly to the StructuredResponse schema above.
            - Do not include any text before or after the JSON object.
            """

            return harmonyFormat

        case .json:
            // Simple JSON format for harmony
            return """
            # Response Formats

            ## JSONResponse

            {"type":"object","description":"JSON response format"}

            # Output Instructions

            - You MUST output valid JSON only. No markdown, no code fences, no prose.
            - Output the JSON directly in your response content, NOT in thinking.
            - Do not include any text before or after the JSON object.
            """

        case .text:
            return ""
        }
    }

    /// Add format instructions for standard models
    private func addFormatInstructions(to messages: inout [Message], format: ResponseFormat) {
        // Find the last user message and append format-specific instruction
        for i in (0..<messages.count).reversed() {
            if messages[i].role == .user {
                let content = messages[i].content

                // Check if instruction should be added
                let shouldAddInstruction = switch format {
                case .jsonSchema:
                    // Always add schema instruction for JSON Schema
                    !content.contains("You must respond with a JSON object that matches this exact schema")
                case .json:
                    // Only add simple instruction if JSON not already mentioned
                    !content.lowercased().contains("json")
                case .text:
                    false
                }

                if shouldAddInstruction {
                    let instruction: String

                    switch format {
                    case .jsonSchema(let container):
                        // For JSON Schema, provide explicit schema instruction
                        var schemaInstruction = "\n\nYou must respond with a JSON object that matches this exact schema:"

                        if let jsonData = try? JSONSerialization.data(withJSONObject: container.schema, options: .prettyPrinted),
                           let schemaString = String(data: jsonData, encoding: .utf8) {
                            schemaInstruction += "\n\n```json\n\(schemaString)\n```"
                        }

                        schemaInstruction += "\n\nProvide only the JSON response with no additional text or explanation."
                        instruction = schemaInstruction

                    case .json:
                        // For simple JSON mode
                        instruction = "\n\nPlease respond with valid JSON only, no additional text."

                    case .text:
                        // No special instruction for text format
                        instruction = ""
                    }

                    if !instruction.isEmpty {
                        messages[i] = Message(
                            role: .user,
                            content: content + instruction,
                            toolCalls: messages[i].toolCalls,
                            thinking: messages[i].thinking,
                            toolName: messages[i].toolName
                        )
                    }
                }
                break
            }
        }
    }
}
