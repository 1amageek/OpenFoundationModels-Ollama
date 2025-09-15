import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore
import OpenFoundationModelsExtra

/// Converts OpenFoundationModels Transcript to Ollama API formats
internal struct TranscriptConverter {

    // MARK: - Message Building

    /// Build Ollama messages from Transcript
    static func buildMessages(from transcript: Transcript) -> [Message] {
        var messages: [Message] = []

        // Use _entries from OpenFoundationModelsExtra for direct access
        for entry in transcript._entries {
            switch entry {
            case .instructions(let instructions):
                // Convert instructions to system message
                let content = extractText(from: instructions.segments)
                if !content.isEmpty {
                    messages.append(Message(role: .system, content: content))
                }

            case .prompt(let prompt):
                // Convert prompt to user message
                let content = extractText(from: prompt.segments)
                messages.append(Message(role: .user, content: content))

            case .response(let response):
                // Convert response to assistant message
                let content = extractText(from: response.segments)
                messages.append(Message(role: .assistant, content: content))

            case .toolCalls(let toolCalls):
                // Convert tool calls to assistant message with tool calls
                let ollamaToolCalls = convertToolCalls(toolCalls)
                messages.append(Message(
                    role: .assistant,
                    content: "",
                    toolCalls: ollamaToolCalls
                ))

            case .toolOutput(let toolOutput):
                // Convert tool output to tool message
                let content = extractText(from: toolOutput.segments)
                messages.append(Message(
                    role: .tool,
                    content: content,
                    toolName: toolOutput.toolName
                ))
            }
        }

        return messages
    }

    // MARK: - Tool Extraction

    /// Extract tool definitions from Transcript
    static func extractTools(from transcript: Transcript) -> [Tool]? {
        // Use _entries from OpenFoundationModelsExtra for direct access
        for entry in transcript._entries {
            if case .instructions(let instructions) = entry,
               !instructions.toolDefinitions.isEmpty {
                return instructions.toolDefinitions.map { convertToolDefinition($0) }
            }
        }
        return nil
    }

    // MARK: - Response Format Extraction

    /// Extract response format with schema from the most recent prompt
    static func extractResponseFormatWithSchema(from transcript: Transcript) -> ResponseFormat? {
        // Look for the most recent prompt with responseFormat
        for entry in transcript._entries.reversed() {
            if case .prompt(let prompt) = entry,
               let responseFormat = prompt.responseFormat,
               let schema = responseFormat._schema {
                // Convert GenerationSchema to JSON for Ollama
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(schema)

                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        return .jsonSchema(json)
                    }
                } catch {
                    // If encoding fails, fall back to simple JSON format
                    return .json
                }
            } else if case .prompt(let prompt) = entry,
                      let _ = prompt.responseFormat {
                // ResponseFormat exists but no schema, use simple JSON format
                return .json
            }
        }
        return nil
    }

    /// Extract response format from the most recent prompt (simplified version)
    static func extractResponseFormat(from transcript: Transcript) -> ResponseFormat? {
        return extractResponseFormatWithSchema(from: transcript)
    }

    // MARK: - Generation Options Extraction

    /// Extract generation options from the most recent prompt
    static func extractOptions(from transcript: Transcript) -> GenerationOptions? {
        // Use _entries from OpenFoundationModelsExtra for direct access
        for entry in transcript._entries.reversed() {
            if case .prompt(let prompt) = entry {
                return prompt.options
            }
        }
        return nil
    }

    // MARK: - Private Helper Methods

    /// Extract text from segments
    private static func extractText(from segments: [Transcript.Segment]) -> String {
        var texts: [String] = []

        for segment in segments {
            switch segment {
            case .text(let textSegment):
                texts.append(textSegment.content)

            case .structure(let structuredSegment):
                // Convert structured content to string
                let content = structuredSegment.content
                texts.append(formatGeneratedContent(content))
            }
        }

        return texts.joined(separator: " ")
    }

    /// Format GeneratedContent as string
    private static func formatGeneratedContent(_ content: GeneratedContent) -> String {
        // Try to get JSON representation first
        if let jsonData = try? JSONEncoder().encode(content),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        // Fallback to string representation
        return "[GeneratedContent]"
    }

    /// Convert Transcript.ToolDefinition to Ollama Tool
    private static func convertToolDefinition(_ definition: Transcript.ToolDefinition) -> Tool {
        return Tool(
            type: "function",
            function: Tool.Function(
                name: definition.name,
                description: definition.description,
                parameters: convertSchemaToParameters(definition.parameters)
            )
        )
    }

    /// Convert GenerationSchema to Tool.Function.Parameters
    private static func convertSchemaToParameters(_ schema: GenerationSchema) -> Tool.Function.Parameters {
        // Encode GenerationSchema to JSON and extract properties
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(schema)

            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return parseSchemaJSON(json)
            }
        } catch {
            // If encoding fails, return empty schema
        }

        // Fallback: return empty object schema
        return Tool.Function.Parameters(
            type: "object",
            properties: [:],
            required: []
        )
    }

    /// Parse schema JSON to create Tool.Function.Parameters
    private static func parseSchemaJSON(_ json: [String: Any]) -> Tool.Function.Parameters {
        // Extract type (default to "object")
        let type = json["type"] as? String ?? "object"

        // Extract properties if available
        var toolProperties: [String: Tool.Function.Parameters.Property] = [:]
        if let properties = json["properties"] as? [String: [String: Any]] {
            for (key, propJson) in properties {
                let propType = propJson["type"] as? String ?? "string"
                let propDescription = propJson["description"] as? String ?? ""
                toolProperties[key] = Tool.Function.Parameters.Property(
                    type: propType,
                    description: propDescription
                )
            }
        }

        // Extract required fields
        let required = json["required"] as? [String] ?? []

        return Tool.Function.Parameters(
            type: type,
            properties: toolProperties,
            required: required
        )
    }

    /// Convert Transcript.ToolCalls to Ollama ToolCalls
    private static func convertToolCalls(_ toolCalls: Transcript.ToolCalls) -> [ToolCall] {
        // Use _calls from OpenFoundationModelsExtra for direct access
        var ollamaToolCalls: [ToolCall] = []

        for toolCall in toolCalls._calls {
            let argumentsDict = convertGeneratedContentToDict(toolCall.arguments)

            let ollamaToolCall = ToolCall(
                function: ToolCall.FunctionCall(
                    name: toolCall.toolName,
                    arguments: argumentsDict
                )
            )

            ollamaToolCalls.append(ollamaToolCall)
        }

        return ollamaToolCalls
    }

    /// Convert GeneratedContent to dictionary for tool arguments
    private static func convertGeneratedContentToDict(_ content: GeneratedContent) -> [String: Any] {
        switch content.kind {
        case .structure(let properties, _):
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                let converted = convertGeneratedContentToAny(value)
                dict[key] = converted
            }
            return dict

        default:
            // If not a structure, return empty dictionary
            return [:]
        }
    }

    /// Convert GeneratedContent to Any type
    private static func convertGeneratedContentToAny(_ content: GeneratedContent) -> Any {
        switch content.kind {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let elements):
            return elements.map { convertGeneratedContentToAny($0) }
        case .structure(let properties, _):
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                dict[key] = convertGeneratedContentToAny(value)
            }
            return dict
        }
    }
}