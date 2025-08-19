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
public final class OllamaLanguageModel: LanguageModel, @unchecked Sendable {
    
    // MARK: - Properties
    internal let httpClient: OllamaHTTPClient
    internal let modelName: String
    internal let configuration: OllamaConfiguration
    
    // MARK: - LanguageModel Protocol Compliance
    public var isAvailable: Bool {
        // For simplicity, return true - actual availability can be checked via /api/tags
        return true
    }
    
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
        let messages = TranscriptConverter.buildMessages(from: transcript)
        let toolDefinitions = TranscriptConverter.extractTools(from: transcript)
        
        // Try to extract response format with full schema first, fallback to simple format
        let responseFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
            ?? TranscriptConverter.extractResponseFormat(from: transcript)
        
        // Use the options from the transcript if not provided
        let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)
        
        // Always use /api/chat for consistency and tool support
        let request = ChatRequest(
            model: modelName,
            messages: messages,
            stream: false,
            options: finalOptions?.toOllamaOptions(),
            format: responseFormat,
            keepAlive: configuration.keepAlive,
            tools: toolDefinitions
        )
        
        let response: ChatResponse = try await httpClient.send(request, to: "/api/chat")
        
        // Check for tool calls
        if let toolCalls = response.message?.toolCalls,
           !toolCalls.isEmpty {
            // Return tool calls as Transcript.Entry
            return createToolCallsEntry(from: toolCalls)
        }
        
        // Convert response to Transcript.Entry
        return createResponseEntry(from: response)
    }
    
    public func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncStream<Transcript.Entry> {
        AsyncStream<Transcript.Entry> { continuation in
            Task {
                do {
                    // Convert Transcript to Ollama format
                    let messages = TranscriptConverter.buildMessages(from: transcript)
                    let tools = TranscriptConverter.extractTools(from: transcript)
                    
                    // Try to extract response format with full schema first, fallback to simple format
                    let responseFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
                        ?? TranscriptConverter.extractResponseFormat(from: transcript)
                    
                    // Use the options from the transcript if not provided
                    let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)
                    
                    let request = ChatRequest(
                        model: modelName,
                        messages: messages,
                        stream: true,
                        options: finalOptions?.toOllamaOptions(),
                        format: responseFormat,
                        keepAlive: configuration.keepAlive,
                        tools: tools
                    )
                    
                    let streamResponse: AsyncThrowingStream<ChatResponse, Error> = await httpClient.stream(request, to: "/api/chat")
                    
                    var accumulatedContent = ""
                    var accumulatedToolCalls: [ToolCall] = []
                    
                    for try await chunk in streamResponse {
                        // Accumulate content
                        if let content = chunk.message?.content, !content.isEmpty {
                            accumulatedContent += content
                        }
                        
                        // Accumulate tool calls
                        if let toolCalls = chunk.message?.toolCalls {
                            accumulatedToolCalls.append(contentsOf: toolCalls)
                        }
                        
                        // Check if streaming is complete
                        if chunk.done {
                            // If we have tool calls, return them
                            if !accumulatedToolCalls.isEmpty {
                                let entry = self.createToolCallsEntry(from: accumulatedToolCalls)
                                continuation.yield(entry)
                            } else {
                                // Return normal response
                                let entry = self.createResponseEntry(content: accumulatedContent)
                                continuation.yield(entry)
                            }
                            
                            continuation.finish()
                            return
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish()
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
        let content = response.message?.content ?? ""
        return createResponseEntry(content: content)
    }
    
    /// Create tool calls entry from Ollama tool calls
    internal func createToolCallsEntry(from toolCalls: [ToolCall]) -> Transcript.Entry {
        let transcriptToolCalls = toolCalls.map { toolCall in
            // Convert Ollama tool call to Transcript tool call
            let argumentsDict = toolCall.function.arguments.dictionary
            let jsonData = (try? JSONSerialization.data(withJSONObject: argumentsDict)) ?? Data()
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            // Create GeneratedContent from JSON string, or use null if parsing fails
            let argumentsContent: GeneratedContent
            if let content = try? GeneratedContent(json: jsonString) {
                argumentsContent = content
            } else {
                // Fallback to null GeneratedContent
                argumentsContent = GeneratedContent(properties: [:])
            }
            
            return Transcript.ToolCall(
                id: UUID().uuidString,
                toolName: toolCall.function.name,
                arguments: argumentsContent
            )
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
    
    // MARK: - Structured Output with GenerationSchema
    
    /// Generate with explicit JSON Schema for structured output
    /// - Parameters:
    ///   - transcript: The conversation transcript
    ///   - schema: The GenerationSchema to use for structured output
    ///   - options: Generation options
    /// - Returns: The generated transcript entry
    public func generate(
        transcript: Transcript,
        schema: GenerationSchema,
        options: GenerationOptions? = nil
    ) async throws -> Transcript.Entry {
        // Encode GenerationSchema to get JSON Schema
        let encoder = JSONEncoder()
        let schemaData = try encoder.encode(schema)
        
        // Convert to JSON dictionary
        guard let schemaJson = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            // Fallback to regular generation if schema extraction fails
            return try await generate(transcript: transcript, options: options)
        }
        
        // Create ResponseFormat with the extracted JSON Schema
        let responseFormat = ResponseFormat.jsonSchema(schemaJson)
        
        // Build messages and tools from transcript
        let messages = TranscriptConverter.buildMessages(from: transcript)
        let toolDefinitions = TranscriptConverter.extractTools(from: transcript)
        
        // Use the options from the transcript if not provided
        let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)
        
        // Create chat request with JSON Schema format
        let request = ChatRequest(
            model: modelName,
            messages: messages,
            stream: false,
            options: finalOptions?.toOllamaOptions(),
            format: responseFormat,
            keepAlive: configuration.keepAlive,
            tools: toolDefinitions
        )
        
        // Send request
        let response: ChatResponse = try await httpClient.send(request, to: "/api/chat")
        
        // Handle tool calls if present
        if let toolCalls = response.message?.toolCalls, !toolCalls.isEmpty {
            return createToolCallsEntry(from: toolCalls)
        }
        
        // Return normal response
        return createResponseEntry(from: response)
    }
    
    /// Generate with a Generable type for structured output
    /// - Parameters:
    ///   - transcript: The conversation transcript
    ///   - type: The Generable type to use for structured output
    ///   - options: Generation options
    /// - Returns: The generated transcript entry with structured content
    public func generate<T: Generable>(
        transcript: Transcript,
        generating type: T.Type,
        options: GenerationOptions? = nil
    ) async throws -> (entry: Transcript.Entry, content: T) {
        // Get the schema from the Generable type
        let schema = T.generationSchema
        
        // Generate with the schema
        let entry = try await generate(transcript: transcript, schema: schema, options: options)
        
        // Parse the response content
        guard case .response(let response) = entry else {
            throw OllamaLanguageModelError.unexpectedResponse("Expected response entry, got \(entry)")
        }
        
        // Extract the content and parse it
        let content = extractTextFromSegments(response.segments)
        let generatedContent = try GeneratedContent(json: content)
        let parsedContent = try T(generatedContent)
        
        return (entry, parsedContent)
    }
    
    private func extractTextFromSegments(_ segments: [Transcript.Segment]) -> String {
        var texts: [String] = []
        
        for segment in segments {
            switch segment {
            case .text(let textSegment):
                texts.append(textSegment.content)
                
            case .structure(let structuredSegment):
                // Convert structured content to string
                if let jsonData = try? JSONEncoder().encode(structuredSegment.content),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    texts.append(jsonString)
                } else {
                    texts.append("[GeneratedContent]")
                }
            }
        }
        
        return texts.joined(separator: " ")
    }
    
    // MARK: - Chat API with Tool Support
    
    /// Generate chat response with optional tool support
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - options: Generation options
    ///   - tools: Optional array of tools for function calling
    /// - Returns: Chat response with potential tool calls
    public func chat(
        messages: [Message],
        options: GenerationOptions? = nil,
        tools: [Tool]? = nil
    ) async throws -> ChatResponse {
        let request = ChatRequest(
            model: modelName,
            messages: messages,
            stream: false,
            options: options?.toOllamaOptions(),
            keepAlive: configuration.keepAlive,
            tools: tools
        )
        
        return try await httpClient.send(request, to: "/api/chat")
    }
    
    /// Stream chat response with optional tool support
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - options: Generation options
    ///   - tools: Optional array of tools for function calling
    /// - Returns: Async stream of chat responses
    public func streamChat(
        messages: [Message],
        options: GenerationOptions? = nil,
        tools: [Tool]? = nil
    ) -> AsyncThrowingStream<ChatResponse, Error> {
        AsyncThrowingStream<ChatResponse, Error> { continuation in
            Task {
                do {
                    let request = ChatRequest(
                        model: modelName,
                        messages: messages,
                        stream: true,
                        options: options?.toOllamaOptions(),
                        keepAlive: configuration.keepAlive,
                        tools: tools
                    )
                    
                    let streamResponse: AsyncThrowingStream<ChatResponse, Error> = await httpClient.stream(request, to: "/api/chat")
                    
                    for try await chunk in streamResponse {
                        continuation.yield(chunk)
                        
                        if chunk.done {
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
    
    // MARK: - Model Information
    
    /// Check if model is available locally
    public func isModelAvailable() async throws -> Bool {
        let models = try await listModels()
        return models.contains { $0.name == modelName || $0.name.hasPrefix("\(modelName):") }
    }
    
    /// List available models
    public func listModels() async throws -> [ModelInfo] {
        let response: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
        return response.models.map { model in
            ModelInfo(
                name: model.name,
                modifiedAt: model.modifiedAt,
                size: model.size
            )
        }
    }
}

// MARK: - Error Types
public enum OllamaLanguageModelError: Error, LocalizedError {
    case unexpectedResponse(String)
    
    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse(let message):
            return "Unexpected response: \(message)"
        }
    }
}

// MARK: - Model Info
public struct ModelInfo: Sendable {
    public let name: String
    public let modifiedAt: Date
    public let size: Int64
}

