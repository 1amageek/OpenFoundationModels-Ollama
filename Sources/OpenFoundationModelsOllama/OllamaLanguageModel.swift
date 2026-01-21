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

        let response: ChatResponse = try await httpClient.send(buildResult.request, to: "/api/chat")

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
                    // Build request using shared builder
                    let buildResult = try self.requestBuilder.build(
                        transcript: transcript,
                        options: options,
                        streaming: true
                    )

                    let modelStrategy = buildResult.modelStrategy

                    // Extract response format for fallback handling
                    let responseFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
                        ?? TranscriptConverter.extractResponseFormat(from: transcript)

                    let streamResponse: AsyncThrowingStream<ChatResponse, Error> = await self.httpClient.stream(
                        buildResult.request,
                        to: "/api/chat"
                    )

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
                            if modelStrategy.usesHarmonyFormat && !accumulatedThinking.isEmpty {
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
                                if modelStrategy.usesHarmonyFormat && !accumulatedThinking.isEmpty && accumulatedContent.isEmpty {
                                    // For gpt-oss with ResponseFormat, generate default JSON
                                    if let format = responseFormat {
                                        let defaultJSON = self.requestBuilder.generateDefaultJSON(for: format)
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
                // The json initializer should always succeed for "{}"
                if let emptyContent = try? GeneratedContent(json: "{}") {
                    argumentsContent = emptyContent
                } else {
                    // This should never happen, but provide a safe fallback
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
