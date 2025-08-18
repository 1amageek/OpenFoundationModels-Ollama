import Foundation
import OpenFoundationModels

/// Ollama Language Model Provider for OpenFoundationModels
public final class OllamaLanguageModel: LanguageModel, @unchecked Sendable {
    
    // MARK: - Properties
    private let httpClient: OllamaHTTPClient
    private let modelName: String
    private let configuration: OllamaConfiguration
    
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
        let responseFormat = TranscriptConverter.extractResponseFormat(from: transcript)
        
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
                    let responseFormat = TranscriptConverter.extractResponseFormat(from: transcript)
                    
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
    private func createResponseEntry(from response: ChatResponse) -> Transcript.Entry {
        let content = response.message?.content ?? ""
        return createResponseEntry(content: content)
    }
    
    /// Create tool calls entry from Ollama tool calls
    private func createToolCallsEntry(from toolCalls: [ToolCall]) -> Transcript.Entry {
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
    
    /// Format tool calls as JSON string for client processing
    private func formatToolCallsAsJSON(_ toolCalls: [ToolCall]) -> String {
        var toolCallsArray: [[String: Any]] = []
        
        for toolCall in toolCalls {
            let callDict: [String: Any] = [
                "type": "tool_call",
                "name": toolCall.function.name,
                "arguments": toolCall.function.arguments.dictionary
            ]
            toolCallsArray.append(callDict)
        }
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: ["tool_calls": toolCallsArray]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // Fallback to simple string representation
        return "Tool calls: \(toolCalls.map { $0.function.name }.joined(separator: ", "))"
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

// MARK: - Model Info
public struct ModelInfo: Sendable {
    public let name: String
    public let modifiedAt: Date
    public let size: Int64
}

