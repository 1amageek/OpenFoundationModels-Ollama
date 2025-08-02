import Foundation

// MARK: - OpenFoundationModels-Ollama
// Ollama Provider for OpenFoundationModels Framework

/// OpenFoundationModels-Ollama provides an Ollama implementation of the LanguageModel protocol
/// from the OpenFoundationModels framework, enabling the use of locally-hosted Ollama models
/// through Apple's Foundation Models API interface.

// MARK: - Public Exports

// Core Components
@_exported import OpenFoundationModels

// MARK: - Type Aliases for User Convenience
public typealias OllamaProvider = OllamaLanguageModel
public typealias OllamaConfig = OllamaConfiguration

// MARK: - Convenience Initializers
extension OllamaLanguageModel {
    /// Initialize with just a model name using default configuration
    /// - Parameter model: Model name (e.g., "llama3.2", "mistral")
    public static func create(model: String) -> OllamaLanguageModel {
        return OllamaLanguageModel(modelName: model)
    }
    
    /// Initialize with model and custom host/port
    /// - Parameters:
    ///   - model: Model name
    ///   - host: Ollama host (default: localhost)
    ///   - port: Ollama port (default: 11434)
    public static func create(
        model: String,
        host: String = "localhost",
        port: Int = 11434
    ) -> OllamaLanguageModel {
        let config = OllamaConfiguration.create(host: host, port: port)
        return OllamaLanguageModel(configuration: config, modelName: model)
    }
}

// MARK: - Popular Model Constants
public struct OllamaModels {
    // Base models
    public static let llama3_2 = "llama3.2"
    public static let llama3_1 = "llama3.1"
    public static let llama2 = "llama2"
    public static let mistral = "mistral"
    public static let mixtral = "mixtral"
    public static let phi3 = "phi3"
    public static let qwen2 = "qwen2"
    public static let gemma2 = "gemma2"
    
    // Code models
    public static let codellama = "codellama"
    public static let deepseekCoder = "deepseek-coder"
    public static let starcoder2 = "starcoder2"
    
    // Specialized models
    public static let deepseekR1 = "deepseek-r1" // Reasoning model with think support
    public static let sqlcoder = "sqlcoder"
    public static let dolphinMixtral = "dolphin-mixtral"
    
    // Vision models
    public static let llava = "llava"
    public static let bakllava = "bakllava"
    
    /// Check if a model supports tool calling
    public static func supportsTools(_ model: String) -> Bool {
        let toolModels = [llama3_2, llama3_1, mistral, mixtral, qwen2]
        return toolModels.contains { model.hasPrefix($0) }
    }
    
    /// Check if a model supports thinking/reasoning
    public static func supportsThinking(_ model: String) -> Bool {
        return model.hasPrefix(deepseekR1)
    }
}

// MARK: - Version Information
public struct OpenFoundationModelsOllama {
    public static let version = "1.0.0"
    public static let buildDate = "2024-01-15"
    
    public static var frameworkInfo: String {
        return """
        OpenFoundationModels-Ollama v\(version)
        Built: \(buildDate)
        Architecture: Local HTTP client for Ollama
        Dependencies: OpenFoundationModels only
        """
    }
    
    public static var capabilities: [String] {
        return [
            "Local model execution",
            "Streaming support",
            "Tool calling (model-dependent)",
            "Thinking/reasoning (model-dependent)",
            "No authentication required",
            "Custom model support",
            "Model management (list available models)"
        ]
    }
}

// MARK: - Quick Start Examples
public enum OllamaExamples {
    /// Basic usage example
    public static let basicUsage = """
    // Create a language model
    let ollama = OllamaLanguageModel(modelName: "llama3.2")
    
    // Generate text
    let response = try await ollama.generate(
        prompt: "Hello, how are you?",
        options: GenerationOptions(temperature: 0.7)
    )
    
    print(response)
    """
    
    /// Streaming example
    public static let streamingUsage = """
    // Stream responses
    let ollama = OllamaLanguageModel(modelName: "mistral")
    
    for await chunk in ollama.stream(prompt: "Tell me a story") {
        print(chunk, terminator: "")
    }
    """
    
    /// Check model availability
    public static let checkModel = """
    // Check if model is available
    let ollama = OllamaLanguageModel(modelName: "llama3.2")
    
    if try await ollama.isModelAvailable() {
        print("Model is ready!")
    } else {
        print("Please run: ollama pull llama3.2")
    }
    """
}