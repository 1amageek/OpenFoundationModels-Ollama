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

    /// Response processor for unified response handling
    private let responseProcessor = ResponseProcessor()

    /// Request builder for creating ChatRequests from Transcripts
    private var requestBuilder: ChatRequestBuilder {
        ChatRequestBuilder(configuration: configuration, modelName: modelName)
    }

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
        // Build request using shared builder
        let buildResult = try requestBuilder.build(
            transcript: transcript,
            options: options,
            streaming: false
        )

        #if DEBUG
        // Log request details
        if let tools = buildResult.request.tools {
            print("[Ollama] Request tools: \(tools.map { $0.function.name })")
        } else {
            print("[Ollama] Request tools: none")
        }
        #endif

        // Send request
        let response: ChatResponse = try await httpClient.send(buildResult.request, to: "/api/chat")

        guard let message = response.message else {
            return createResponseEntry(content: "")
        }

        #if DEBUG
        // Log response details
        if let thinking = message.thinking, !thinking.isEmpty {
            print("[Ollama] Thinking: \(thinking.prefix(500))...")
        }
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            print("[Ollama] Native tool_calls: \(toolCalls.map { $0.function.name })")
        }
        print("[Ollama] Content: \(message.content.prefix(200))...")
        #endif

        // Use ResponseProcessor for unified handling
        switch responseProcessor.process(message) {
        case .toolCalls(let toolCalls):
            #if DEBUG
            print("[Ollama] Processed as: toolCalls (\(toolCalls.count))")
            #endif
            return createToolCallsEntry(from: toolCalls)
        case .content(let content):
            #if DEBUG
            print("[Ollama] Processed as: content")
            #endif
            return createResponseEntry(content: content)
        case .empty:
            #if DEBUG
            print("[Ollama] Processed as: empty")
            #endif
            return createResponseEntry(content: "")
        }
    }

    public func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Build request using shared builder
                    let buildResult = try self.requestBuilder.build(
                        transcript: transcript,
                        options: options,
                        streaming: true
                    )

                    // Stream raw responses
                    let rawStream: AsyncThrowingStream<ChatResponse, Error> = await self.httpClient.stream(
                        buildResult.request,
                        to: "/api/chat"
                    )

                    var hasYieldedContent = false
                    var accumulatedContent = ""
                    var accumulatedThinking = ""
                    var nativeToolCalls: [ToolCall] = []

                    for try await chunk in rawStream {
                        // Accumulate content
                        if let content = chunk.message?.content, !content.isEmpty {
                            accumulatedContent += content

                            // Yield content incrementally (only if no tool call patterns detected yet)
                            if !chunk.done && !TextToolCallParser.containsToolCallPatterns(accumulatedContent) {
                                let entry = self.createResponseEntry(content: content)
                                continuation.yield(entry)
                                hasYieldedContent = true
                            }
                        }

                        // Accumulate thinking content
                        if let thinking = chunk.message?.thinking, !thinking.isEmpty {
                            accumulatedThinking += thinking
                        }

                        // Accumulate native tool calls
                        if let toolCalls = chunk.message?.toolCalls {
                            nativeToolCalls.append(contentsOf: toolCalls)
                        }

                        // On stream completion
                        if chunk.done {
                            // Create a virtual Message from accumulated data
                            let finalMessage = Message(
                                role: .assistant,
                                content: accumulatedContent,
                                toolCalls: nativeToolCalls.isEmpty ? nil : nativeToolCalls,
                                thinking: accumulatedThinking.isEmpty ? nil : accumulatedThinking
                            )

                            // Use ResponseProcessor for unified handling
                            switch self.responseProcessor.process(finalMessage) {
                            case .toolCalls(let toolCalls):
                                continuation.yield(self.createToolCallsEntry(from: toolCalls))

                            case .content(let content):
                                if !hasYieldedContent {
                                    continuation.yield(self.createResponseEntry(content: content))
                                }

                            case .empty:
                                if !hasYieldedContent {
                                    continuation.yield(self.createResponseEntry(content: ""))
                                }
                            }
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

    /// Create tool calls entry from Ollama tool calls
    internal func createToolCallsEntry(from toolCalls: [ToolCall]) -> Transcript.Entry {
        let transcriptToolCalls = toolCalls.map { toolCall in
            // Convert Ollama tool call to Transcript tool call
            let argumentsDict = toolCall.function.arguments.dictionary

            // Create GeneratedContent from arguments dictionary
            let argumentsContent: GeneratedContent

            do {
                // Convert dictionary to JSON string
                let jsonData = try JSONSerialization.data(withJSONObject: argumentsDict, options: [.sortedKeys])
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                // Create GeneratedContent from JSON
                argumentsContent = try GeneratedContent(json: jsonString)
            } catch {
                // Fallback to empty content - use a safer approach
                #if DEBUG
                print("[OllamaLanguageModel] Failed to create GeneratedContent from tool arguments: \(error)")
                #endif
                // Create empty GeneratedContent without force unwrap
                if let emptyContent = try? GeneratedContent(json: "{}") {
                    argumentsContent = emptyContent
                } else {
                    let emptyKeyValuePairs: KeyValuePairs<String, any ConvertibleToGeneratedContent> = [:]
                    argumentsContent = GeneratedContent(properties: emptyKeyValuePairs)
                }
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
}
