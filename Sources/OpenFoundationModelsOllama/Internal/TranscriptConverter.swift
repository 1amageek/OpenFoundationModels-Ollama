import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Converts OpenFoundationModels Transcript to Ollama API formats
internal struct TranscriptConverter {
    
    // MARK: - Message Building
    
    /// Build Ollama messages from Transcript
    static func buildMessages(from transcript: Transcript) -> [Message] {
        var messages: [Message] = []
        
        for entry in transcript {
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
        for entry in transcript {
            if case .instructions(let instructions) = entry,
               !instructions.toolDefinitions.isEmpty {
                return instructions.toolDefinitions.map { convertToolDefinition($0) }
            }
        }
        return nil
    }
    
    // MARK: - Response Format Extraction
    
    /// Extract response format from the most recent prompt
    static func extractResponseFormat(from transcript: Transcript) -> ResponseFormat? {
        // Look for the most recent prompt with a response format
        for entry in transcript.reversed() {
            if case .prompt(let prompt) = entry,
               let _ = prompt.responseFormat {
                // For now, we'll default to JSON format when a response format is specified
                // In the future, we could parse the GenerationSchema to determine the format
                return .json
            }
        }
        return nil
    }
    
    // MARK: - Generation Options Extraction
    
    /// Extract generation options from the most recent prompt
    static func extractOptions(from transcript: Transcript) -> GenerationOptions? {
        for entry in transcript.reversed() {
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
        // Check if we have explicit schema information in our registry
        if let explicitSchema = ToolSchemaRegistry.shared.getToolSchema(name: definition.name) {
            let parameters = convertExplicitSchemaToParameters(explicitSchema)
            return Tool(
                type: "function",
                function: Tool.Function(
                    name: definition.name,
                    description: definition.description,
                    parameters: parameters
                )
            )
        }
        
        // Fallback to GenerationSchema conversion
        return Tool(
            type: "function",
            function: Tool.Function(
                name: definition.name,
                description: definition.description,
                parameters: convertSchemaToParameters(definition.parameters)
            )
        )
    }
    
    /// Convert explicit schema to Tool.Function.Parameters
    private static func convertExplicitSchemaToParameters(
        _ schema: ToolSchemaRegistry.ToolSchema
    ) -> Tool.Function.Parameters {
        var properties: [String: Tool.Function.Parameters.Property] = [:]
        
        for (key, propertyDef) in schema.properties {
            properties[key] = Tool.Function.Parameters.Property(
                type: propertyDef.type,
                description: propertyDef.description
            )
        }
        
        return Tool.Function.Parameters(
            type: "object",
            properties: properties,
            required: schema.required
        )
    }
    
    /// Convert GenerationSchema to Tool.Function.Parameters
    private static func convertSchemaToParameters(_ schema: GenerationSchema) -> Tool.Function.Parameters {
        // Since GenerationSchema properties are not accessible due to internal implementation,
        // we provide a pragmatic solution for real-world usage.
        // 
        // For now, we create a flexible object schema that allows any properties.
        // This enables tool calling to work correctly with Ollama API.
        // In production, developers should provide complete tool schemas in their API calls.
        
        // Try to encode GenerationSchema to JSON first
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(schema)
            
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let converted = parseSchemaJSON(json)
                
                // If we got some properties from JSON, use them
                if !converted.properties.isEmpty || !converted.required.isEmpty {
                    return converted
                }
            }
        } catch {
            // Continue with fallback approach
        }
        
        // Fallback: Create a flexible schema that accepts common tool parameters
        // This allows tools to work in practice while maintaining type safety
        return Tool.Function.Parameters(
            type: "object",
            properties: createFlexibleToolProperties(),
            required: []
        )
    }
    
    /// Create flexible tool properties for common use cases
    private static func createFlexibleToolProperties() -> [String: Tool.Function.Parameters.Property] {
        // Return empty properties for now - this allows Ollama to infer the schema
        // from the tool description and model behavior
        return [:]
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
    
    /// Convert GeneratedContent parameters to Tool.Function.Parameters (legacy)
    private static func convertParameters(_ content: GeneratedContent?) -> Tool.Function.Parameters {
        guard let content = content else {
            return Tool.Function.Parameters(
                type: "object",
                properties: [:],
                required: []
            )
        }
        
        var properties: [String: Tool.Function.Parameters.Property] = [:]
        var required: [String] = []
        
        // Try to extract properties from GeneratedContent
        if case .structure(let props, _) = content.kind {
            for (key, value) in props {
                let type = inferType(from: value)
                properties[key] = Tool.Function.Parameters.Property(
                    type: type,
                    description: ""
                )
                
                // Simple heuristic: non-null values are required
                if case .null = value.kind {
                    // Optional field
                } else {
                    required.append(key)
                }
            }
        }
        
        return Tool.Function.Parameters(
            type: "object",
            properties: properties,
            required: required
        )
    }
    
    /// Infer JSON type from GeneratedContent
    private static func inferType(from content: GeneratedContent) -> String {
        switch content.kind {
        case .null:
            return "null"
        case .bool:
            return "boolean"
        case .number:
            return "number"
        case .string:
            return "string"
        case .array:
            return "array"
        case .structure:
            return "object"
        // Note: 'partial' case was removed from GeneratedContent.Kind in latest version
        }
    }
    
    /// Convert Transcript.ToolCalls to Ollama ToolCalls
    private static func convertToolCalls(_ toolCalls: Transcript.ToolCalls) -> [ToolCall] {
        // Access the calls through the Collection protocol
        var ollamaToolCalls: [ToolCall] = []
        
        for toolCall in toolCalls {
            let argumentsDict = convertGeneratedContentToDict(toolCall.arguments)
            ollamaToolCalls.append(
                ToolCall(
                    function: ToolCall.FunctionCall(
                        name: toolCall.toolName,
                        arguments: argumentsDict
                    )
                )
            )
        }
        
        return ollamaToolCalls
    }
    
    /// Convert GeneratedContent to dictionary for tool arguments
    private static func convertGeneratedContentToDict(_ content: GeneratedContent) -> [String: Any] {
        switch content.kind {
        case .structure(let properties, _):
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                dict[key] = convertGeneratedContentToAny(value)
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
        // Note: 'partial' case was removed from GeneratedContent.Kind
        }
    }
}