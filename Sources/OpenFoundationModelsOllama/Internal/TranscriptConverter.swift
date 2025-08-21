import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Converts OpenFoundationModels Transcript to Ollama API formats
internal struct TranscriptConverter {
    
    // MARK: - Message Building
    
    /// Build Ollama messages from Transcript
    static func buildMessages(from transcript: Transcript) -> [Message] {
        // Try JSON-based extraction first for more complete information
        if let messagesFromJSON = buildMessagesFromJSON(transcript), !messagesFromJSON.isEmpty {
            return messagesFromJSON
        }
        
        // Fallback to entry-based extraction if JSON fails
        return buildMessagesFromEntries(transcript)
    }
    
    /// Build messages by encoding Transcript to JSON
    private static func buildMessagesFromJSON(_ transcript: Transcript) -> [Message]? {
        do {
            // Encode transcript to JSON
            let encoder = JSONEncoder()
            let data = try encoder.encode(transcript)
            
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [[String: Any]] else {
                return nil
            }
            
            var messages: [Message] = []
            
            for entry in entries {
                guard let type = entry["type"] as? String else { continue }
                
                switch type {
                case "instructions":
                    if let segments = entry["segments"] as? [[String: Any]] {
                        let content = extractTextFromSegments(segments)
                        if !content.isEmpty {
                            messages.append(Message(role: .system, content: content))
                        }
                    }
                    
                case "prompt":
                    if let segments = entry["segments"] as? [[String: Any]] {
                        let content = extractTextFromSegments(segments)
                        messages.append(Message(role: .user, content: content))
                    }
                    
                case "response":
                    if let segments = entry["segments"] as? [[String: Any]] {
                        let content = extractTextFromSegments(segments)
                        messages.append(Message(role: .assistant, content: content))
                    }
                    
                case "toolCalls":
                    // Handle different possible JSON structures for toolCalls
                    var toolCallsArray: [[String: Any]]? = nil
                    
                    // Try different key names
                    if let directArray = entry["toolCalls"] as? [[String: Any]] {
                        toolCallsArray = directArray
                    } else if let callsArray = entry["calls"] as? [[String: Any]] {
                        // Actual key name in Transcript.ToolCalls is "calls"
                        toolCallsArray = callsArray
                    }
                    // Try as nested structure (look for any array field)
                    else {
                        // Iterate through entry to find array of tool calls
                        for (key, value) in entry {
                            if key != "type" && key != "id", // Skip metadata fields
                               let array = value as? [[String: Any]] {
                                toolCallsArray = array
                                break
                            }
                        }
                    }
                    
                    if let toolCalls = toolCallsArray, !toolCalls.isEmpty {
                        let ollamaToolCalls = extractToolCallsFromJSON(toolCalls)
                        if !ollamaToolCalls.isEmpty {
                            messages.append(Message(
                                role: .assistant,
                                content: "",
                                toolCalls: ollamaToolCalls
                            ))
                        }
                    }
                    
                case "toolOutput":
                    if let segments = entry["segments"] as? [[String: Any]],
                       let toolName = entry["toolName"] as? String {
                        let content = extractTextFromSegments(segments)
                        messages.append(Message(
                            role: .tool,
                            content: content,
                            toolName: toolName
                        ))
                    }
                    
                default:
                    break
                }
            }
            
            return messages.isEmpty ? nil : messages
        } catch {
            return nil
        }
    }
    
    /// Extract text from JSON segments
    private static func extractTextFromSegments(_ segments: [[String: Any]]) -> String {
        var texts: [String] = []
        
        for segment in segments {
            if let type = segment["type"] as? String, type == "text",
               let content = segment["content"] as? String {
                texts.append(content)
            } else if let type = segment["type"] as? String, type == "structure",
                      let content = segment["content"] {
                // Handle structured content
                if let jsonData = try? JSONSerialization.data(withJSONObject: content),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    texts.append(jsonString)
                }
            }
        }
        
        return texts.joined(separator: " ")
    }
    
    /// Extract tool calls from JSON
    private static func extractToolCallsFromJSON(_ toolCalls: [[String: Any]]) -> [ToolCall] {
        print("\n📋 ===== EXTRACT TOOL CALLS FROM JSON START =====")
        print("Number of tool calls: \(toolCalls.count)")
        print("Tool calls JSON: \(toolCalls)")
        var ollamaToolCalls: [ToolCall] = []
        
        for (index, toolCall) in toolCalls.enumerated() {
            print("\n--- Processing tool call \(index + 1) ---")
            print("Tool call data: \(toolCall)")
            print("Tool call keys: \(toolCall.keys)")
            
            guard let toolName = toolCall["toolName"] as? String else {
                print("❌ No toolName found in tool call")
                continue
            }
            print("Tool name: \(toolName)")
            
            // Extract arguments using GeneratedContent(json:)
            let extractedArguments: [String: Any]
            
            print("\n🔍 Extracting arguments...")
            print("Arguments raw value: \(String(describing: toolCall["arguments"]))")
            print("Arguments type: \(type(of: toolCall["arguments"]))")
            
            // Convert arguments to GeneratedContent, then to dictionary
            if let argumentsData = toolCall["arguments"] {
                do {
                    // Convert to JSON string
                    print("Converting arguments to JSON string...")
                    let jsonData = try JSONSerialization.data(withJSONObject: argumentsData, options: [.sortedKeys])
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                    print("JSON string: \(jsonString)")
                    
                    // Create GeneratedContent from JSON
                    print("Creating GeneratedContent from JSON...")
                    let argumentsContent = try GeneratedContent(json: jsonString)
                    print("✅ GeneratedContent created: \(argumentsContent.debugDescription)")
                    
                    // Print internal structure
                    debugPrintGeneratedContent(argumentsContent, indent: "    ")
                    
                    // Convert GeneratedContent to dictionary for Ollama
                    extractedArguments = convertGeneratedContentToDict(argumentsContent)
                    print("Extracted arguments dictionary: \(extractedArguments)")
                    
                } catch {
                    print("❌ Failed to process arguments: \(error)")
                    extractedArguments = [:]
                }
            } else if let directArgs = toolCall["arguments"] as? [String: Any] {
                // Fallback: Direct arguments structure
                print("Using direct arguments (fallback)")
                extractedArguments = directArgs
            } else if let argumentsWrapper = toolCall["arguments"] as? [String: Any] {
                // Try to extract from GeneratedContent structure (legacy path)
                print("Attempting legacy extraction from wrapper")
                if let kind = argumentsWrapper["kind"] as? [String: Any] {
                    if let structure = kind["structure"] as? [String: Any],
                       let properties = structure["properties"] as? [String: Any] {
                        // Extract properties from structure
                        extractedArguments = extractArgumentsFromProperties(properties)
                    } else if let properties = kind["properties"] as? [String: Any] {
                        // Direct properties in kind
                        extractedArguments = extractArgumentsFromProperties(properties)
                    } else {
                        extractedArguments = [:]
                    }
                } else {
                    extractedArguments = [:]
                }
            } else {
                print("❌ No arguments found")
                extractedArguments = [:]
            }
            
            // Create tool call even if arguments are empty (some tools don't require arguments)
            print("\n📦 Creating ToolCall:")
            print("  Name: \(toolName)")
            print("  Final arguments: \(extractedArguments)")
            print("  Arguments count: \(extractedArguments.count)")
            
            let toolCall = ToolCall(
                function: ToolCall.FunctionCall(
                    name: toolName,
                    arguments: extractedArguments
                )
            )
            
            ollamaToolCalls.append(toolCall)
            print("✅ ToolCall created")
        }
        
        print("\n===== EXTRACT TOOL CALLS FROM JSON END =====")
        print("Total Ollama tool calls created: \(ollamaToolCalls.count)\n")
        
        return ollamaToolCalls
    }
    
    /// Extract arguments from GeneratedContent properties structure
    private static func extractArgumentsFromProperties(_ properties: [String: Any]) -> [String: Any] {
        print("\n🔍 Extracting arguments from properties (legacy)...")
        print("Properties: \(properties)")
        print("Properties count: \(properties.count)")
        var arguments: [String: Any] = [:]
        
        for (key, value) in properties {
            print("\nProcessing property: \(key)")
            print("Value: \(value)")
            print("Value type: \(type(of: value))")
            if let contentWrapper = value as? [String: Any] {
                print("Found content wrapper for key '\(key)': \(contentWrapper)")
                
                // Try to extract the actual value from GeneratedContent structure
                if let kind = contentWrapper["kind"] as? [String: Any] {
                    print("Found kind dict: \(kind)")
                    if let stringValue = kind["string"] as? String {
                        print("✅ Extracted string: \(stringValue)")
                        arguments[key] = stringValue
                    } else if let numberValue = kind["number"] as? Double {
                        print("✅ Extracted number: \(numberValue)")
                        arguments[key] = numberValue
                    } else if let boolValue = kind["boolean"] as? Bool {
                        print("✅ Extracted boolean: \(boolValue)")
                        arguments[key] = boolValue
                    } else if let structure = kind["structure"] as? [String: Any] {
                        print("✅ Extracted structure: \(structure)")
                        arguments[key] = structure
                    } else {
                        print("⚠️ Unknown kind structure: \(kind)")
                    }
                } else if let kind = contentWrapper["kind"] as? String {
                    print("Found kind string: \(kind)")
                    // Simple kind string
                    arguments[key] = kind
                    print("✅ Using kind string as value")
                } else {
                    print("⚠️ No kind found, using value as-is")
                    // Use as-is if we can't parse it
                    arguments[key] = value
                }
            } else {
                print("Direct value (not wrapped): \(value)")
                // Direct value
                arguments[key] = value
            }
        }
        
        print("\nFinal extracted arguments: \(arguments)")
        print("Arguments count: \(arguments.count)")
        
        return arguments
    }
    
    /// Fallback: Build messages from entries directly
    private static func buildMessagesFromEntries(_ transcript: Transcript) -> [Message] {
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
        // Try JSON-based extraction first
        if let toolsFromJSON = extractToolsFromJSON(transcript) {
            return toolsFromJSON
        }
        
        // Fallback to entry-based extraction
        for entry in transcript {
            if case .instructions(let instructions) = entry,
               !instructions.toolDefinitions.isEmpty {
                return instructions.toolDefinitions.map { convertToolDefinition($0) }
            }
        }
        return nil
    }
    
    /// Extract tools by encoding Transcript to JSON
    private static func extractToolsFromJSON(_ transcript: Transcript) -> [Tool]? {
        do {
            // Encode transcript to JSON
            let encoder = JSONEncoder()
            let data = try encoder.encode(transcript)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [[String: Any]] else {
                return nil
            }
            
            // Look for instructions with toolDefinitions
            for entry in entries {
                if entry["type"] as? String == "instructions",
                   let toolDefs = entry["toolDefinitions"] as? [[String: Any]],
                   !toolDefs.isEmpty {
                    
                    var tools: [Tool] = []
                    for toolDef in toolDefs {
                        if let tool = extractToolFromJSON(toolDef) {
                            tools.append(tool)
                        }
                    }
                    return tools.isEmpty ? nil : tools
                }
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    /// Extract a single tool from JSON
    private static func extractToolFromJSON(_ json: [String: Any]) -> Tool? {
        guard let name = json["name"] as? String,
              let description = json["description"] as? String else {
            return nil
        }
        
        // Extract parameters if available
        let parameters: Tool.Function.Parameters
        if let paramsJSON = json["parameters"] as? [String: Any] {
            parameters = parseSchemaJSON(paramsJSON)
        } else {
            parameters = Tool.Function.Parameters(type: "object", properties: [:], required: [])
        }
        
        return Tool(
            type: "function",
            function: Tool.Function(
                name: name,
                description: description,
                parameters: parameters
            )
        )
    }
    
    // MARK: - Response Format Extraction
    
    /// Extract response format from the most recent prompt
    static func extractResponseFormat(from transcript: Transcript) -> ResponseFormat? {
        return extractResponseFormatFromJSON(transcript)
    }
    
    /// Extract response format with full JSON Schema from the most recent prompt
    static func extractResponseFormatWithSchema(from transcript: Transcript) -> ResponseFormat? {
        return extractResponseFormatFromJSON(transcript)
    }
    
    /// Extract response format by encoding Transcript to JSON
    private static func extractResponseFormatFromJSON(_ transcript: Transcript) -> ResponseFormat? {
        do {
            // Encode transcript to JSON
            let encoder = JSONEncoder()
            let data = try encoder.encode(transcript)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [[String: Any]] else {
                return nil
            }
            
            // Look for the most recent prompt with responseFormat
            for entry in entries.reversed() {
                if entry["type"] as? String == "prompt",
                   let responseFormat = entry["responseFormat"] as? [String: Any] {
                    
                    // Check if there's a schema (now available with updated OpenFoundationModels)
                    if let schema = responseFormat["schema"] as? [String: Any] {
                        return .jsonSchema(schema)
                    }
                    
                    // If there's a name or type field, we know JSON is expected
                    if responseFormat["name"] != nil || responseFormat["type"] != nil {
                        return .json
                    }
                }
            }
            
            return nil
        } catch {
            return nil
        }
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
    
    /// Debug print GeneratedContent structure recursively
    private static func debugPrintGeneratedContent(_ content: GeneratedContent, indent: String = "") {
        print("\(indent)📊 GeneratedContent Debug:")
        print("\(indent)  debugDescription: \(content.debugDescription)")
        
        switch content.kind {
        case .structure(let properties, let orderedKeys):
            print("\(indent)  Type: structure")
            print("\(indent)  Properties count: \(properties.count)")
            print("\(indent)  Ordered keys: \(orderedKeys)")
            for (key, value) in properties {
                print("\(indent)  Property '\(key)':")
                switch value.kind {
                case .string(let s):
                    print("\(indent)    → String: '\(s)'")
                case .number(let n):
                    print("\(indent)    → Number: \(n)")
                case .bool(let b):
                    print("\(indent)    → Bool: \(b)")
                case .structure(_, _):
                    print("\(indent)    → Nested structure:")
                    debugPrintGeneratedContent(value, indent: indent + "      ")
                case .array(let arr):
                    print("\(indent)    → Array with \(arr.count) elements")
                case .null:
                    print("\(indent)    → Null")
                }
            }
        case .string(let s):
            print("\(indent)  Type: string")
            print("\(indent)  Value: '\(s)'")
        case .number(let n):
            print("\(indent)  Type: number")
            print("\(indent)  Value: \(n)")
        case .bool(let b):
            print("\(indent)  Type: bool")
            print("\(indent)  Value: \(b)")
        case .array(let arr):
            print("\(indent)  Type: array")
            print("\(indent)  Elements: \(arr.count)")
            for (i, elem) in arr.enumerated() {
                print("\(indent)  Element \(i):")
                debugPrintGeneratedContent(elem, indent: indent + "    ")
            }
        case .null:
            print("\(indent)  Type: null")
        }
    }
    
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
            print("Warning: Failed to encode GenerationSchema to JSON: \(error)")
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
        print("\n🔄 ===== CONVERT TOOL CALLS START =====")
        print("Converting Transcript.ToolCalls to Ollama ToolCalls")
        
        // Access the calls through the Collection protocol
        var ollamaToolCalls: [ToolCall] = []
        
        for (index, toolCall) in toolCalls.enumerated() {
            print("\nProcessing tool call \(index + 1)")
            print("Tool name: \(toolCall.toolName)")
            print("Tool arguments: \(toolCall.arguments)")
            print("Arguments debugDescription: \(toolCall.arguments.debugDescription)")
            
            let argumentsDict = convertGeneratedContentToDict(toolCall.arguments)
            print("Converted arguments to dict: \(argumentsDict)")
            
            let ollamaToolCall = ToolCall(
                function: ToolCall.FunctionCall(
                    name: toolCall.toolName,
                    arguments: argumentsDict
                )
            )
            
            print("Created Ollama ToolCall")
            ollamaToolCalls.append(ollamaToolCall)
        }
        
        print("\n===== CONVERT TOOL CALLS END =====")
        print("Total converted: \(ollamaToolCalls.count)\n")
        
        return ollamaToolCalls
    }
    
    /// Convert GeneratedContent to dictionary for tool arguments
    private static func convertGeneratedContentToDict(_ content: GeneratedContent) -> [String: Any] {
        print("\n📦 Converting GeneratedContent to dictionary...")
        print("GeneratedContent: \(content.debugDescription)")
        print("Content kind: \(content.kind)")
        
        switch content.kind {
        case .structure(let properties, let orderedKeys):
            print("Found structure with \(properties.count) properties")
            print("Ordered keys: \(orderedKeys)")
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                print("  Converting property '\(key)'...")
                print("    Value: \(value.debugDescription)")
                let converted = convertGeneratedContentToAny(value)
                print("    Converted to: \(converted) (type: \(type(of: converted)))")
                dict[key] = converted
            }
            print("Final dictionary: \(dict)")
            return dict
            
        default:
            print("⚠️ Content is not a structure, returning empty dictionary")
            print("Content kind was: \(content.kind)")
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