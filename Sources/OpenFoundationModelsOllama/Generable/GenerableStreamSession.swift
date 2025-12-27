import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Session for streaming Generable responses with automatic retry
public final class GenerableStreamSession<T: Generable & Sendable & Decodable>: @unchecked Sendable {
    /// The language model to use
    private let model: OllamaLanguageModel

    /// Stream options
    private let options: GenerableStreamOptions

    /// Parser for the Generable type
    private let parser: GenerableParser<T>

    /// Base transcript (instructions + conversation history)
    private let baseTranscript: Transcript

    /// Original prompt text
    private let originalPrompt: String

    public init(
        model: OllamaLanguageModel,
        transcript: Transcript,
        prompt: String,
        options: GenerableStreamOptions = .default
    ) {
        self.model = model
        self.options = options
        self.parser = GenerableParser<T>()
        self.baseTranscript = transcript
        self.originalPrompt = prompt
    }

    // MARK: - Public Streaming Methods

    /// Stream generation with automatic retry on failure
    /// - Returns: AsyncThrowingStream of GenerableStreamResult
    public func stream() -> AsyncThrowingStream<GenerableStreamResult<T>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.executeStream(continuation: continuation)
            }
        }
    }

    /// Generate with retry (non-streaming, returns final result)
    /// - Returns: Generated value or throws error
    public func generate() async throws -> T {
        let retryController = RetryController<T>(policy: options.retryPolicy)

        while true {
            do {
                let (result, _) = try await executeGenerationWithContent(
                    retryController: retryController,
                    attempt: await retryController.currentAttempt
                )
                await retryController.recordSuccess()
                return result
            } catch let error as GenerationErrorWithContent {
                // Parse error with content - record the content for retry context
                if await retryController.recordFailure(
                    error: error.underlyingError,
                    failedContent: error.content
                ) != nil {
                    let delay = await retryController.getRetryDelay()
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw await retryController.getFinalError()
                }
            } catch let error as GenerableError {
                // Errors without content (e.g., emptyResponse, connectionError)
                if await retryController.recordFailure(
                    error: error,
                    failedContent: ""
                ) != nil {
                    let delay = await retryController.getRetryDelay()
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw await retryController.getFinalError()
                }
            } catch {
                throw GenerableError.unknown(error.localizedDescription)
            }
        }
    }

    /// Internal error type to carry content with error
    private struct GenerationErrorWithContent: Error {
        let underlyingError: GenerableError
        let content: String
    }

    // MARK: - Private Implementation

    /// Execute the streaming with retry logic
    private func executeStream(
        continuation: AsyncThrowingStream<GenerableStreamResult<T>, Error>.Continuation
    ) async {
        let retryController = RetryController<T>(policy: options.retryPolicy)

        // Use a flag-based loop to avoid await in while condition
        var shouldContinue = true
        while shouldContinue {
            let canRetry = await retryController.canRetry
            let currentAttempt = await retryController.currentAttempt

            // Check if we should continue (first attempt or can retry)
            guard canRetry || currentAttempt == 1 else {
                shouldContinue = false
                break
            }

            let attempt = currentAttempt
            var accumulatedContent = ""
            var lastError: GenerableError?

            do {
                // Build transcript for this attempt
                let transcript = await buildTranscript(
                    retryController: retryController,
                    attempt: attempt
                )

                // Stream from model
                let stream = model.stream(transcript: transcript, options: options.generationOptions)

                for try await entry in stream {
                    if case .response(let response) = entry {
                        for segment in response.segments {
                            if case .text(let textSegment) = segment {
                                accumulatedContent += textSegment.content

                                // Yield partial state if enabled
                                if options.yieldPartialValues &&
                                   accumulatedContent.count >= options.minContentForParse {
                                    let partialValue = parser.parsePartial(accumulatedContent)
                                    let partialState = PartialState<T>(
                                        accumulatedContent: accumulatedContent,
                                        partialValue: partialValue,
                                        isComplete: false,
                                        progress: nil
                                    )
                                    continuation.yield(.partial(partialState))
                                }
                            }
                        }
                    }
                }

                // Stream complete - try to parse final content
                let parseResult = parser.parse(accumulatedContent)

                switch parseResult {
                case .success(let value):
                    // Success! Yield complete and finish
                    await retryController.recordSuccess()
                    continuation.yield(.complete(value))
                    continuation.finish()
                    return

                case .failure(let parseError):
                    lastError = parseError.toGenerableError()
                }
            } catch {
                // Network or stream error
                lastError = mapError(error)
            }

            // Handle error and retry
            guard let error = lastError else {
                continuation.finish(throwing: GenerableError.unknown("Unknown error occurred"))
                return
            }

            if let retryContext = await retryController.recordFailure(
                error: error,
                failedContent: accumulatedContent
            ) {
                // Yield retry notification
                continuation.yield(.retrying(retryContext))

                // Wait before retry
                let delay = await retryController.getRetryDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else {
                // Retries exhausted
                let finalError = await retryController.getFinalError()
                continuation.yield(.failed(finalError))
                continuation.finish()
                return
            }
        }

        // Should not reach here, but handle gracefully
        let finalError = await retryController.getFinalError()
        continuation.finish(throwing: finalError)
    }

    /// Execute a single generation attempt, returning both result and raw content
    private func executeGenerationWithContent(
        retryController: RetryController<T>,
        attempt: Int
    ) async throws -> (T, String) {
        let transcript = await buildTranscript(
            retryController: retryController,
            attempt: attempt
        )

        let response = try await model.generate(transcript: transcript, options: options.generationOptions)

        guard case .response(let resp) = response else {
            throw GenerableError.emptyResponse
        }

        // Extract content
        var content = ""
        for segment in resp.segments {
            if case .text(let textSegment) = segment {
                content += textSegment.content
            }
        }

        guard !content.isEmpty else {
            throw GenerableError.emptyResponse
        }

        // Parse content
        let parseResult = parser.parse(content)

        switch parseResult {
        case .success(let value):
            return (value, content)
        case .failure(let parseError):
            // Throw error with content for retry context
            throw GenerationErrorWithContent(
                underlyingError: parseError.toGenerableError(),
                content: content
            )
        }
    }

    /// Build transcript for a retry attempt
    private func buildTranscript(
        retryController: RetryController<T>,
        attempt: Int
    ) async -> Transcript {
        var entries = baseTranscript._entries

        // Modify prompt based on retry context
        var promptText = originalPrompt

        if attempt > 1 {
            // This is a retry - get actual error context from controller
            if let context = await retryController.getLastRetryContext() {
                promptText = await retryController.buildRetryPrompt(
                    originalPrompt: originalPrompt,
                    context: context
                )
            }
        }

        // Add prompt with response format
        entries.append(.prompt(Transcript.Prompt(
            segments: [.text(Transcript.TextSegment(content: promptText))],
            options: options.generationOptions ?? GenerationOptions(),
            responseFormat: Transcript.ResponseFormat(type: T.self)
        )))

        return Transcript(entries: entries)
    }

    /// Map errors to GenerableError
    private func mapError(_ error: Error) -> GenerableError {
        if let ollamaError = error as? OllamaHTTPError {
            switch ollamaError {
            case .connectionError(let message):
                return .connectionError(message)
            case .invalidResponse:
                return .streamInterrupted("Invalid response")
            case .statusError(let code, _):
                return .connectionError("HTTP \(code)")
            case .networkError(let underlyingError):
                return .connectionError(underlyingError.localizedDescription)
            case .decodingError(let underlyingError):
                return .jsonParsingFailed("", underlyingError: underlyingError.localizedDescription)
            }
        }

        if let generableError = error as? GenerableError {
            return generableError
        }

        return .unknown(error.localizedDescription)
    }
}

// MARK: - Convenience Extension for OllamaLanguageModel

extension OllamaLanguageModel {
    /// Create a Generable streaming session
    /// - Parameters:
    ///   - transcript: Base transcript with instructions
    ///   - prompt: User prompt
    ///   - type: Generable type to generate
    ///   - options: Stream options
    /// - Returns: GenerableStreamSession for streaming
    public func streamGenerable<T: Generable & Sendable & Decodable>(
        transcript: Transcript,
        prompt: String,
        generating type: T.Type,
        options: GenerableStreamOptions = .default
    ) -> GenerableStreamSession<T> {
        GenerableStreamSession<T>(
            model: self,
            transcript: transcript,
            prompt: prompt,
            options: options
        )
    }

    /// Generate a Generable type with retry
    /// - Parameters:
    ///   - transcript: Base transcript with instructions
    ///   - prompt: User prompt
    ///   - type: Generable type to generate
    ///   - options: Stream options
    /// - Returns: Generated value
    public func generateWithRetry<T: Generable & Sendable & Decodable>(
        transcript: Transcript,
        prompt: String,
        generating type: T.Type,
        options: GenerableStreamOptions = .default
    ) async throws -> T {
        let session = GenerableStreamSession<T>(
            model: self,
            transcript: transcript,
            prompt: prompt,
            options: options
        )
        return try await session.generate()
    }

    /// Stream Generable generation with retry
    /// - Parameters:
    ///   - transcript: Base transcript with instructions
    ///   - prompt: User prompt
    ///   - type: Generable type to generate
    ///   - options: Stream options
    /// - Returns: AsyncThrowingStream of results
    public func streamWithRetry<T: Generable & Sendable & Decodable>(
        transcript: Transcript,
        prompt: String,
        generating type: T.Type,
        options: GenerableStreamOptions = .default
    ) -> AsyncThrowingStream<GenerableStreamResult<T>, Error> {
        let session = GenerableStreamSession<T>(
            model: self,
            transcript: transcript,
            prompt: prompt,
            options: options
        )
        return session.stream()
    }
}
