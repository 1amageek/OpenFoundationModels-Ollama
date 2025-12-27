import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore
import OpenFoundationModelsExtra

/// Errors that can occur during transcript conversion
internal enum TranscriptConverterError: Error {
    case invalidSchemaFormat
}

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
    /// Uses the most recent instructions with toolDefinitions (consistent with extractOptions and extractResponseFormat)
    static func extractTools(from transcript: Transcript) throws -> [Tool]? {
        // Use _entries from OpenFoundationModelsExtra for direct access
        // Search in reverse to get the most recent instructions (like extractOptions and extractResponseFormat)
        for entry in transcript._entries.reversed() {
            if case .instructions(let instructions) = entry,
               !instructions.toolDefinitions.isEmpty {
                return try instructions.toolDefinitions.map { try convertToolDefinition($0) }
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
    private static func convertToolDefinition(_ definition: Transcript.ToolDefinition) throws -> Tool {
        return Tool(
            type: "function",
            function: Tool.Function(
                name: definition.name,
                description: definition.description,
                parameters: try convertSchemaToParameters(definition.parameters)
            )
        )
    }

    /// Convert GenerationSchema to Tool.Function.Parameters
    private static func convertSchemaToParameters(_ schema: GenerationSchema) throws -> Tool.Function.Parameters {
        // Encode GenerationSchema to JSON and extract properties
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(schema)

        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw TranscriptConverterError.invalidSchemaFormat
        }

        return parseSchemaJSON(json)
    }

    /// Parse schema JSON to create Tool.Function.Parameters
    private static func parseSchemaJSON(_ json: [String: Any]) -> Tool.Function.Parameters {
        // Extract type (default to "object")
        let type = json["type"] as? String ?? "object"

        // Extract properties if available
        var toolProperties: [String: Tool.Function.Parameters.Property] = [:]
        if let properties = json["properties"] as? [String: [String: Any]] {
            for (key, propJson) in properties {
                toolProperties[key] = parsePropertyJSON(propJson)
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

    /// Parse a single property JSON to create Tool.Function.Parameters.Property
    private static func parsePropertyJSON(_ propJson: [String: Any]) -> Tool.Function.Parameters.Property {
        let propType = propJson["type"] as? String ?? "string"
        let propDescription = propJson["description"] as? String ?? ""

        // Extract enum values (from "enum" or "anyOf")
        var enumValues: [String]? = nil
        if let enumArray = propJson["enum"] as? [String] {
            enumValues = enumArray
        } else if let anyOfArray = propJson["anyOf"] as? [[String: Any]] {
            // Extract string values from anyOf array
            enumValues = anyOfArray.compactMap { item -> String? in
                if let constValue = item["const"] as? String {
                    return constValue
                }
                return item["enum"] as? String
            }
            if enumValues?.isEmpty == true {
                enumValues = nil
            }
        }

        // Extract items for array types
        var items: Tool.Function.Parameters.Property? = nil
        if propType == "array", let itemsJson = propJson["items"] as? [String: Any] {
            items = parsePropertyJSON(itemsJson)
        }

        // Extract nested properties for object types
        var nestedProperties: [String: Tool.Function.Parameters.Property]? = nil
        var nestedRequired: [String]? = nil
        if propType == "object", let propsJson = propJson["properties"] as? [String: [String: Any]] {
            nestedProperties = [:]
            for (key, nestedPropJson) in propsJson {
                nestedProperties?[key] = parsePropertyJSON(nestedPropJson)
            }
            nestedRequired = propJson["required"] as? [String]
        }

        return Tool.Function.Parameters.Property(
            type: propType,
            description: propDescription,
            enum: enumValues,
            items: items,
            properties: nestedProperties,
            required: nestedRequired
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