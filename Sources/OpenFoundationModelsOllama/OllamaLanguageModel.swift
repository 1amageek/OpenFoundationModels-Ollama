import Foundation
import OpenFoundationModels

// MARK: - GenerationOptions Extension
internal extension GenerationOptions {
    func toOllamaOptions() -> OllamaOptions {
        return OllamaOptions(
            numPredict: maximumResponseTokens,
            temperature: temperature,
            topP: nil  // SamplingMode probabilityThreshold cannot be extracted
        )
    }
}

/// Ollama Language Model Provider for OpenFoundationModels
public final class OllamaLanguageModel: LanguageModel, Sendable {
    
    // MARK: - Properties
    internal let httpClient: OllamaHTTPClient
    internal let modelName: String
    internal let configuration: OllamaConfiguration
    
    // MARK: - LanguageModel Protocol Compliance
    public var isAvailable: Bool { true }
    
    // MARK: - Initialization
    
    /// Initialize with configuration and model name
    /// - Parameters:
    ///   - configuration: Ollama configuration
    ///   - modelName: Name of the model (e.g., "llama3.2", "mistral")
    public init(
        configuration: OllamaConfiguration,
        modelName: String
    ) {
        self.configuration = configuration
        self.modelName = modelName
        self.httpClient = OllamaHTTPClient(configuration: configuration)
    }
    
    /// Convenience initializer with just model name
    /// - Parameter modelName: Name of the model
    public convenience init(modelName: String) {
        self.init(configuration: OllamaConfiguration(), modelName: modelName)
    }
    
    // MARK: - LanguageModel Protocol Implementation
    
    public func generate(transcript: Transcript, options: GenerationOptions?) async throws -> Transcript.Entry {
        // Convert Transcript to Ollama format
        var messages = TranscriptConverter.buildMessages(from: transcript)
        let toolDefinitions = try TranscriptConverter.extractTools(from: transcript)
        
        // Try to extract response format with full schema first, fallback to simple format
        let responseFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
            ?? TranscriptConverter.extractResponseFormat(from: transcript)
        
        // Check if this is a gpt-oss model that requires harmony format
        let isGptOssModel = modelName.lowercased().hasPrefix("gpt-oss")
        
        // Handle response format based on model type
        var finalResponseFormat: ResponseFormat? = nil
        
        if let format = responseFormat {
            if isGptOssModel {
                // For gpt-oss models, add Response Formats to system message instead of using format parameter
                addHarmonyResponseFormat(to: &messages, format: format)
                // Don't use format parameter for gpt-oss models
                finalResponseFormat = nil
            } else {
                // For other models, use format parameter and add user instructions
                finalResponseFormat = format
                addFormatInstructions(to: &messages, format: format)
            }
        }
        
        
        // Use the options from the transcript if not provided
        let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)
        
        // Always use /api/chat for consistency and tool support
        let request = ChatRequest(
            model: modelName,
            messages: messages,
            stream: false,
            options: finalOptions?.toOllamaOptions(),
            format: finalResponseFormat,
            keepAlive: configuration.keepAlive,
            tools: toolDefinitions
        )
        
        let response: ChatResponse = try await httpClient.send(request, to: "/api/chat")
        
        // Check for tool calls
        if let toolCalls = response.message?.toolCalls,
           !toolCalls.isEmpty {
            return createToolCallsEntry(from: toolCalls)
        }
        
        // Convert response to Transcript.Entry
        return createResponseEntry(from: response)
    }
    
    public func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Convert Transcript to Ollama format
                    var messages = TranscriptConverter.buildMessages(from: transcript)
                    let tools = try TranscriptConverter.extractTools(from: transcript)
                    
                    
                    // Try to extract response format with full schema first, fallback to simple format
                    let responseFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
                        ?? TranscriptConverter.extractResponseFormat(from: transcript)
                    
                    // Check if this is a gpt-oss model that requires harmony format
                    let isGptOssModel = modelName.lowercased().hasPrefix("gpt-oss")
                    
                    // Handle response format based on model type
                    var finalResponseFormat: ResponseFormat? = nil
                    
                    if let format = responseFormat {
                        if isGptOssModel {
                            // For gpt-oss models, add Response Formats to system message instead of using format parameter
                            addHarmonyResponseFormat(to: &messages, format: format)
                            // Don't use format parameter for gpt-oss models
                            finalResponseFormat = nil
                        } else {
                            // For other models, use format parameter and add user instructions
                            finalResponseFormat = format
                            addFormatInstructions(to: &messages, format: format)
                        }
                    }
                    
                    // Use the options from the transcript if not provided
                    let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)
                    
                    let request = ChatRequest(
                        model: modelName,
                        messages: messages,
                        stream: true,
                        options: finalOptions?.toOllamaOptions(),
                        format: finalResponseFormat,
                        keepAlive: configuration.keepAlive,
                        tools: tools
                    )
                    
                    let streamResponse: AsyncThrowingStream<ChatResponse, Error> = await httpClient.stream(request, to: "/api/chat")
                    
                    var accumulatedToolCalls: [ToolCall] = []
                    var hasYieldedContent = false
                    var accumulatedThinking = ""  // Track thinking content for gpt-oss
                    var accumulatedContent = ""   // Track actual content
                    
                    for try await chunk in streamResponse {
                        // Process content field (this is what should be shown to user)
                        if let content = chunk.message?.content, !content.isEmpty {
                            accumulatedContent += content
                            let entry = self.createResponseEntry(content: content)
                            continuation.yield(entry)
                            hasYieldedContent = true
                        }
                        
                        // Track thinking field (for gpt-oss models) but don't yield it
                        if let thinking = chunk.message?.thinking, !thinking.isEmpty {
                            accumulatedThinking += thinking
                        }
                        
                        // Accumulate tool calls (these typically come all at once)
                        if let toolCalls = chunk.message?.toolCalls {
                            accumulatedToolCalls.append(contentsOf: toolCalls)
                        }
                        
                        // Check if streaming is complete
                        if chunk.done {
                            
                            // For gpt-oss models, we don't show thinking to users
                            // Only use it if no content is available at the end
                            #if DEBUG
                            if isGptOssModel {
                                print("[thinking]: \(accumulatedThinking)")
                            }
                            #endif
                            // If we accumulated tool calls, yield them
                            if !accumulatedToolCalls.isEmpty {
                                let entry = self.createToolCallsEntry(from: accumulatedToolCalls)
                                continuation.yield(entry)
                            }
                            
                            // Handle gpt-oss case where content is empty but thinking has content
                            if !hasYieldedContent && accumulatedToolCalls.isEmpty {
                                if isGptOssModel && !accumulatedThinking.isEmpty && accumulatedContent.isEmpty {
                                    // For gpt-oss with ResponseFormat, generate default JSON
                                    if let format = finalResponseFormat ?? responseFormat {
                                        let defaultJSON = self.generateDefaultJSON(for: format)
                                        let entry = self.createResponseEntry(content: defaultJSON)
                                        continuation.yield(entry)
                                    } else {
                                        // No format specified, yield empty to avoid hanging
                                        let entry = self.createResponseEntry(content: "")
                                        continuation.yield(entry)
                                    }
                                } else {
                                    // Regular empty response case
                                    let entry = self.createResponseEntry(content: "")
                                    continuation.yield(entry)
                                }
                            }
                            
                            continuation.finish()
                            return
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func supports(locale: Locale) -> Bool {
        // Ollama models generally support multiple languages
        return true
    }
    
    // MARK: - Private Helper Methods
    
    /// Create response entry from ChatResponse
    internal func createResponseEntry(from response: ChatResponse) -> Transcript.Entry {
        // Check both content and thinking fields (some models use thinking instead of content)
        let content = response.message?.content ?? response.message?.thinking ?? ""
        return createResponseEntry(content: content)
    }
    
    /// Create tool calls entry from Ollama tool calls
    internal func createToolCallsEntry(from toolCalls: [ToolCall]) -> Transcript.Entry {
        let transcriptToolCalls = toolCalls.map { toolCall in
            // Convert Ollama tool call to Transcript tool call
            let argumentsDict = toolCall.function.arguments.dictionary
            
            // Create GeneratedContent from arguments dictionary
            let argumentsContent: GeneratedContent
            
            // Create GeneratedContent from arguments dictionary
            do {
                // Convert dictionary to JSON string
                let jsonData = try JSONSerialization.data(withJSONObject: argumentsDict, options: [.sortedKeys])
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                
                // Create GeneratedContent from JSON
                argumentsContent = try GeneratedContent(json: jsonString)
                
                
            } catch {
                // Fallback to empty content
                argumentsContent = try! GeneratedContent(json: "{}")
            }
            
            let toolCall = Transcript.ToolCall(
                id: UUID().uuidString,
                toolName: toolCall.function.name,
                arguments: argumentsContent
            )
            
            return toolCall
        }
        
        return .toolCalls(
            Transcript.ToolCalls(
                id: UUID().uuidString,
                transcriptToolCalls
            )
        )
    }
    
    /// Create response entry from content string
    private func createResponseEntry(content: String) -> Transcript.Entry {
        return .response(
            Transcript.Response(
                id: UUID().uuidString,
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(
                    id: UUID().uuidString,
                    content: content
                ))]
            )
        )
    }
    
    
    // MARK: - Internal Helper Methods for Testing
    
    /// Check if model is available (for testing only)
    internal func checkModelAvailability() async throws -> Bool {
        let response: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
        return response.models.contains { $0.name == modelName || $0.name.hasPrefix("\(modelName):") }
    }
    
    // MARK: - Private Helper Methods for Response Format
    
    /// Generate default JSON response for gpt-oss models when content is empty
    private func generateDefaultJSON(for format: ResponseFormat) -> String {
        switch format {
        case .jsonSchema(let schema):
            // Create a minimal valid JSON based on schema
            if let properties = schema["properties"] as? [String: Any] {
                var defaultObject: [String: Any] = [:]
                
                for (key, value) in properties {
                    if let prop = value as? [String: Any],
                       let type = prop["type"] as? String {
                        switch type {
                        case "string":
                            defaultObject[key] = ""
                        case "integer", "number":
                            defaultObject[key] = 0
                        case "boolean":
                            defaultObject[key] = false
                        case "array":
                            defaultObject[key] = []
                        case "object":
                            defaultObject[key] = [:]
                        default:
                            defaultObject[key] = nil
                        }
                    }
                }
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: defaultObject, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return jsonString
                }
            }
            return "{}"
            
        case .json:
            return "{}"
            
        case .text:
            return ""
        }
    }
    
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
        case .jsonSchema(let schema):
            var harmonyFormat = "# Response Formats\n\n## StructuredResponse\n\n"

            if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: []),
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
    
    /// Add format instructions for non-gpt-oss models
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
                    case .jsonSchema(let schema):
                        // For JSON Schema, provide explicit schema instruction
                        var schemaInstruction = "\n\nYou must respond with a JSON object that matches this exact schema:"
                        
                        if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: .prettyPrinted),
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
