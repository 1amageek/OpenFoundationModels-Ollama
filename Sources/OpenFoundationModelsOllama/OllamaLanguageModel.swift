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
    
    public func generate(prompt: String, options: GenerationOptions?) async throws -> String {
        let request = GenerateRequest(
            model: modelName,
            prompt: prompt,
            stream: false,
            options: options?.toOllamaOptions(),
            keepAlive: configuration.keepAlive
        )
        
        let response: GenerateResponse = try await httpClient.send(request, to: "/api/generate")
        return response.response
    }
    
    public func stream(prompt: String, options: GenerationOptions?) -> AsyncStream<String> {
        AsyncStream<String> { continuation in
            Task {
                do {
                    let request = GenerateRequest(
                        model: modelName,
                        prompt: prompt,
                        stream: true,
                        options: options?.toOllamaOptions(),
                        keepAlive: configuration.keepAlive
                    )
                    
                    let streamResponse: AsyncThrowingStream<GenerateResponse, Error> = await httpClient.stream(request, to: "/api/generate")
                    
                    for try await chunk in streamResponse {
                        // Yield the response text
                        continuation.yield(chunk.response)
                        
                        // Check if streaming is complete
                        if chunk.done {
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
    
    // MARK: - Enhanced API with Prompt Support
    
    /// Generate with Prompt object support
    public func generate(prompt: Prompt, options: GenerationOptions?) async throws -> String {
        // Convert Prompt to string (combine segments)
        let promptText = prompt.segments.map { $0.text }.joined(separator: "\n")
        return try await generate(prompt: promptText, options: options)
    }
    
    /// Stream with Prompt object support
    public func stream(prompt: Prompt, options: GenerationOptions?) -> AsyncStream<String> {
        let promptText = prompt.segments.map { $0.text }.joined(separator: "\n")
        return stream(prompt: promptText, options: options)
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

