import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

// MARK: - Test Skip Error

struct TestSkip: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

@Suite("Ollama Integration Tests", .tags(.integration))
struct OllamaIntegrationTests {
    
    // MARK: - Test Configuration
    
    private let defaultModel = "gpt-oss:20b"
    private let testTimeout: TimeInterval = 30.0
    
    private var isOllamaAvailable: Bool {
        get async {
            // Check if Ollama is running by trying to connect
            do {
                let config = OllamaConfiguration()
                let httpClient = OllamaHTTPClient(configuration: config)
                let _: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
                return true
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Basic Generation Tests
    
    @Test("Basic text generation with gpt-oss:20b")
    @available(macOS 13.0, iOS 16.0, *)
    func testBasicGeneration() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running. Please start Ollama with 'ollama serve'")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        // Check if model is available
        let isAvailable = try await model.isModelAvailable()
        #expect(isAvailable == true, "Model \(defaultModel) should be available. Run 'ollama pull \(defaultModel)' to download it.")
        
        // Generate text
        let prompt = "Complete this sentence in 10 words or less: The weather today is"
        let response = try await model.generate(
            prompt: prompt,
            options: GenerationOptions(
                temperature: 0.5,
                maximumResponseTokens: 20
            )
        )
        
        #expect(!response.isEmpty)
        #expect(response.count > 0)
        #expect(response.count < 200) // Should be short due to token limit
    }
    
    @Test("Generation with Prompt object")
    @available(macOS 13.0, iOS 16.0, *)
    func testPromptObjectGeneration() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = Prompt("What is 2 + 2? Answer with just the number.")
        let response = try await model.generate(
            prompt: prompt,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 10)
        )
        
        #expect(!response.isEmpty)
        #expect(response.contains("4") || response.contains("four"))
    }
    
    @Test("Generation with different temperatures")
    @available(macOS 13.0, iOS 16.0, *)
    func testTemperatureVariations() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = "Say 'Hello' in exactly one word:"
        
        // Low temperature (more deterministic)
        let response1 = try await model.generate(
            prompt: prompt,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 10)
        )
        
        // High temperature (more creative)
        let response2 = try await model.generate(
            prompt: prompt,
            options: GenerationOptions(temperature: 0.9, maximumResponseTokens: 10)
        )
        
        #expect(!response1.isEmpty)
        #expect(!response2.isEmpty)
    }
    
    // MARK: - Streaming Tests
    
    @Test("Streaming text generation")
    @available(macOS 13.0, iOS 16.0, *)
    func testStreamingGeneration() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = "Count from 1 to 5:"
        var chunks: [String] = []
        
        let stream = model.stream(
            prompt: prompt,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 50)
        )
        
        for await chunk in stream {
            chunks.append(chunk)
        }
        
        #expect(chunks.count > 0)
        let fullResponse = chunks.joined()
        #expect(!fullResponse.isEmpty)
        #expect(fullResponse.contains("1") || fullResponse.contains("one"))
    }
    
    @Test("Streaming with Prompt object")
    @available(macOS 13.0, iOS 16.0, *)
    func testStreamingWithPromptObject() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = Prompt("Say 'test' and nothing else:")
        var receivedChunks = 0
        
        let stream = model.stream(
            prompt: prompt,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 10)
        )
        
        for await _ in stream {
            receivedChunks += 1
            if receivedChunks > 100 { // Safety limit
                break
            }
        }
        
        #expect(receivedChunks > 0)
    }
    
    // MARK: - Model Availability Tests
    
    @Test("Check model availability")
    @available(macOS 13.0, iOS 16.0, *)
    func testModelAvailability() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        let isAvailable = try await model.isModelAvailable()
        
        #expect(isAvailable == true, "Model \(defaultModel) should be available")
    }
    
    @Test("List available models")
    @available(macOS 13.0, iOS 16.0, *)
    func testListModels() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        let models = try await model.listModels()
        
        #expect(models.count > 0, "Should have at least one model available")
        
        // Check if our default model is in the list
        let hasDefaultModel = models.contains { modelInfo in
            modelInfo.name == defaultModel || modelInfo.name.hasPrefix("gpt-oss:")
        }
        #expect(hasDefaultModel == true, "Default model should be in the list")
        
        // Verify model info structure
        if let firstModel = models.first {
            #expect(firstModel.size > 0)
            #expect(!firstModel.name.isEmpty)
        }
    }
    
    @Test("Check unavailable model")
    @available(macOS 13.0, iOS 16.0, *)
    func testUnavailableModel() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: "nonexistent-model-xyz")
        let isAvailable = try await model.isModelAvailable()
        
        #expect(isAvailable == false)
    }
    
    // MARK: - Options Tests
    
    @Test("Generation with custom options")
    @available(macOS 13.0, iOS 16.0, *)
    func testCustomOptions() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let options = GenerationOptions(
            sampling: .random(probabilityThreshold: 0.9),
            temperature: 0.3,
            maximumResponseTokens: 15
        )
        
        let response = try await model.generate(
            prompt: "Answer yes or no: Is the sky blue?",
            options: options
        )
        
        #expect(!response.isEmpty)
        #expect(response.count < 100) // Should be short due to token limit
    }
    
    @Test("Generation with token limits")
    @available(macOS 13.0, iOS 16.0, *)
    func testTokenLimits() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: 5
        )
        
        let response = try await model.generate(
            prompt: "List all numbers from 1 to 100:",
            options: options
        )
        
        #expect(!response.isEmpty)
        // Response should be very short due to token limit
        #expect(response.count < 50)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Handle model not found error")
    @available(macOS 13.0, iOS 16.0, *)
    func testModelNotFoundError() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: "definitely-not-a-real-model-xyz123")
        
        do {
            _ = try await model.generate(
                prompt: "Hello",
                options: GenerationOptions(temperature: 0.7)
            )
            Issue.record("Expected error for non-existent model")
        } catch {
            // Expected error
            #expect(error.localizedDescription.contains("not found") || 
                   error.localizedDescription.contains("model"))
        }
    }
    
    @Test("Handle connection error")
    @available(macOS 13.0, iOS 16.0, *)
    func testConnectionError() async throws {
        // Create model with invalid port
        let config = OllamaConfiguration.create(host: "localhost", port: 99999)
        let model = OllamaLanguageModel(configuration: config, modelName: defaultModel)
        
        do {
            _ = try await model.generate(
                prompt: "Hello",
                options: nil
            )
            Issue.record("Expected connection error")
        } catch {
            // Expected error
            #expect(error.localizedDescription.contains("connect") || 
                   error.localizedDescription.contains("refused") ||
                   error.localizedDescription.contains("Connection"))
        }
    }
    
    // MARK: - Locale Support Tests
    
    @Test("Check locale support")
    func testLocaleSupport() {
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        // Ollama models generally support multiple languages
        #expect(model.supports(locale: Locale(identifier: "en_US")) == true)
        #expect(model.supports(locale: Locale(identifier: "ja_JP")) == true)
        #expect(model.supports(locale: Locale(identifier: "zh_CN")) == true)
        #expect(model.supports(locale: Locale(identifier: "es_ES")) == true)
    }
    
    // MARK: - Configuration Tests
    
    @Test("Custom configuration with keep-alive")
    @available(macOS 13.0, iOS 16.0, *)
    func testCustomConfigurationWithKeepAlive() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let config = OllamaConfiguration(
            baseURL: URL(string: "http://localhost:11434")!,
            timeout: 60.0,
            keepAlive: "5m"
        )
        
        let model = OllamaLanguageModel(configuration: config, modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let response = try await model.generate(
            prompt: "Say 'OK':",
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 10)
        )
        
        #expect(!response.isEmpty)
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}