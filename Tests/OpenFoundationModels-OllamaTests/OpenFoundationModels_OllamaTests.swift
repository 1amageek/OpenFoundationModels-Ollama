import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Ollama Language Model Tests")
struct OllamaLanguageModelTests {
    
    // MARK: - Configuration Tests
    
    @Test("Configuration initialization with defaults")
    func testDefaultConfiguration() {
        let config = OllamaConfiguration()
        #expect(config.baseURL.absoluteString == "http://localhost:11434")
        #expect(config.timeout == 120.0)
        #expect(config.keepAlive == nil)
    }
    
    @Test("Configuration initialization with custom values")
    func testCustomConfiguration() {
        let config = OllamaConfiguration(
            baseURL: URL(string: "http://192.168.1.100:11434")!,
            timeout: 60.0,
            keepAlive: "10m"
        )
        #expect(config.baseURL.absoluteString == "http://192.168.1.100:11434")
        #expect(config.timeout == 60.0)
        #expect(config.keepAlive == "10m")
    }
    
    @Test("Configuration convenience factory")
    func testConvenienceConfiguration() {
        let config = OllamaConfiguration.create(host: "myserver", port: 8080)
        #expect(config.baseURL.absoluteString == "http://myserver:8080")
    }
    
    // MARK: - Model Initialization Tests
    
    @Test("Model initialization with configuration")
    func testModelInitialization() {
        let config = OllamaConfiguration()
        let model = OllamaLanguageModel(configuration: config, modelName: "llama3.2")
        #expect(model.isAvailable == true)
    }
    
    @Test("Model convenience initializer")
    func testModelConvenienceInit() {
        let model = OllamaLanguageModel(modelName: "mistral")
        #expect(model.isAvailable == true)
    }
    
    @Test("Model static factory methods")
    func testModelFactoryMethods() {
        let model1 = OllamaLanguageModel.create(model: "llama3.2")
        #expect(model1.isAvailable == true)
        
        let model2 = OllamaLanguageModel.create(model: "mistral", host: "localhost", port: 11434)
        #expect(model2.isAvailable == true)
    }
    
    // MARK: - API Types Tests
    
    @Test("GenerateRequest encoding")
    func testGenerateRequestEncoding() throws {
        let request = GenerateRequest(
            model: "llama3.2",
            prompt: "Hello",
            stream: false,
            options: OllamaOptions(temperature: 0.7, topP: 0.9)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["model"] as? String == "llama3.2")
        #expect(json?["prompt"] as? String == "Hello")
        #expect(json?["stream"] as? Bool == false)
        
        let options = json?["options"] as? [String: Any]
        #expect(options?["temperature"] as? Double == 0.7)
        #expect(options?["top_p"] as? Double == 0.9)
    }
    
    @Test("Message encoding with different roles")
    func testMessageEncoding() throws {
        let messages = [
            Message(role: .system, content: "You are a helpful assistant"),
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!")
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(messages)
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        
        #expect(json?.count == 3)
        #expect(json?[0]["role"] as? String == "system")
        #expect(json?[1]["role"] as? String == "user")
        #expect(json?[2]["role"] as? String == "assistant")
    }
    
    // MARK: - Model Support Tests
    
    @Test("Model constants are defined correctly")
    func testModelConstants() {
        #expect(OllamaModels.llama3_2 == "llama3.2")
        #expect(OllamaModels.mistral == "mistral")
        #expect(OllamaModels.codellama == "codellama")
        #expect(OllamaModels.deepseekR1 == "deepseek-r1")
    }
    
    @Test("Model capability detection")
    func testModelCapabilities() {
        #expect(OllamaModels.supportsTools("llama3.2") == true)
        #expect(OllamaModels.supportsTools("llama3.2:latest") == true)
        #expect(OllamaModels.supportsTools("llama2") == false)
        
        #expect(OllamaModels.supportsThinking("deepseek-r1") == true)
        #expect(OllamaModels.supportsThinking("deepseek-r1:latest") == true)
        #expect(OllamaModels.supportsThinking("llama3.2") == false)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Error response decoding")
    func testErrorResponseDecoding() throws {
        let errorJSON = #"{"error": "model 'unknown' not found, try pulling it first"}"#
        let data = errorJSON.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let error = try decoder.decode(ErrorResponse.self, from: data)
        
        #expect(error.error == "model 'unknown' not found, try pulling it first")
        #expect(error.localizedDescription.contains("model 'unknown' not found"))
    }
    
    @Test("Ollama error types have correct descriptions")
    func testOllamaErrorDescriptions() {
        let connectionError = OllamaError.connectionFailed("Cannot connect to localhost:11434")
        #expect(connectionError.localizedDescription == "Cannot connect to localhost:11434")
        #expect(connectionError.recoverySuggestion == "Make sure Ollama is running with 'ollama serve'")
        
        let modelError = OllamaError.modelNotFound
        #expect(modelError.localizedDescription.contains("Please run 'ollama pull") == true)
        #expect(modelError.recoverySuggestion?.contains("ollama pull") == true)
    }
    
    // MARK: - Framework Info Tests
    
    @Test("Framework version information")
    func testFrameworkInfo() {
        #expect(OpenFoundationModelsOllama.version == "1.0.0")
        #expect(!OpenFoundationModelsOllama.capabilities.isEmpty)
        #expect(OpenFoundationModelsOllama.frameworkInfo.contains("OpenFoundationModels-Ollama"))
    }
}

// MARK: - Mock Tests (without actual Ollama connection)

@Suite("Mock Ollama Tests")
struct MockOllamaTests {
    
    @Test("GenerationOptions conversion")
    func testGenerationOptionsConversion() {
        let options = GenerationOptions(
            temperature: 0.8,
            maximumResponseTokens: 100
        )
        
        let ollamaOptions = options.toOllamaOptions()
        #expect(ollamaOptions.numPredict == 100)
        #expect(ollamaOptions.temperature == 0.8)
        #expect(ollamaOptions.topP == nil)  // topP is in SamplingMode, not directly accessible
    }
    
    @Test("Prompt to message conversion")
    func testPromptConversion() {
        // Prompt now takes a simple string, not segments
        let prompt = Prompt("Hello world")
        
        let messages = [Message].from(prompt: prompt)
        #expect(messages.count == 1)
        #expect(messages[0].role == .user)
        #expect(messages[0].content == "Hello world")
    }
}
