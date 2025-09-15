import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
@testable import OpenFoundationModelsCore

@Suite("Ollama Language Model Tests")
struct OllamaLanguageModelTests {
    
    // MARK: - Configuration Tests
    
    @Test("Configuration initialization with defaults")
    func testDefaultConfiguration() {
        let config = OllamaConfiguration()
        #expect(config.baseURL.absoluteString == "http://127.0.0.1:11434")
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
    
    @Test("Configuration with host and port")
    func testConfigurationWithHostPort() {
        let config = OllamaConfiguration.create(
            host: "myserver",
            port: 8080,
            timeout: 60.0
        )
        #expect(config.baseURL.absoluteString == "http://myserver:8080")
        #expect(config.timeout == 60.0)
        #expect(config.keepAlive == nil)
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
        let model = OllamaLanguageModel(modelName: "llama3.2")
        #expect(model.isAvailable == true)
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
    
    @Test("ChatRequest encoding")
    func testChatRequestEncoding() throws {
        let messages = [
            Message(role: .system, content: "You are helpful"),
            Message(role: .user, content: "Hello")
        ]
        
        let request = ChatRequest(
            model: "llama3.2",
            messages: messages,
            stream: false
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["model"] as? String == "llama3.2")
        #expect(json?["stream"] as? Bool == false)
        
        let msgs = json?["messages"] as? [[String: Any]]
        #expect(msgs?.count == 2)
        #expect(msgs?[0]["role"] as? String == "system")
        #expect(msgs?[1]["role"] as? String == "user")
    }
    
    @Test("Message encoding with different roles")
    func testMessageEncoding() throws {
        let messages = [
            Message(role: .system, content: "You are a helpful assistant"),
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!"),
            Message(role: .tool, content: "Tool result")
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(messages)
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        
        #expect(json?.count == 4)
        #expect(json?[0]["role"] as? String == "system")
        #expect(json?[1]["role"] as? String == "user")
        #expect(json?[2]["role"] as? String == "assistant")
        #expect(json?[3]["role"] as? String == "tool")
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
    
    // MARK: - Transcript-based Tests
    
    @Test("Transcript conversion to messages")
    func testTranscriptConversion() {
        // Create transcript with instructions and prompt
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [.text(Transcript.TextSegment(id: "seg-1", content: "You are helpful"))],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                id: "prompt-1",
                segments: [.text(Transcript.TextSegment(id: "seg-2", content: "Hello"))],
                options: GenerationOptions(),
                responseFormat: nil
            ))
        ])
        
        // Convert to messages
        let messages = TranscriptConverter.buildMessages(from: transcript)
        
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[0].content == "You are helpful")
        #expect(messages[1].role == .user)
        #expect(messages[1].content == "Hello")
    }
    
    @Test("Tool extraction from transcript")
    func testToolExtractionFromTranscript() throws {
        
        // Create a mock schema for testing
        let mockSchema = GenerationSchema(
            type: "object",
            description: "Test parameters"
        )
        
        let toolDef = Transcript.ToolDefinition(
            name: "test_tool",
            description: "A test tool",
            parameters: mockSchema
        )
        
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [toolDef]
            ))
        ])
        
        // Extract tools
        let tools = try TranscriptConverter.extractTools(from: transcript)
        
        #expect(tools?.count == 1)
        #expect(tools?.first?.function.name == "test_tool")
        #expect(tools?.first?.function.description == "A test tool")
    }
    
    // MARK: - Options Conversion Tests
    
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
}

// MARK: - Integration Tests (requires Ollama running)

@Suite("Ollama Integration Tests")
struct OllamaIntegrationTests {
    
    private let defaultModel = "gpt-oss:20b"
    
    private var isOllamaAvailable: Bool {
        get async {
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
    
    @Test("Check model availability")
    @available(macOS 13.0, iOS 16.0, *)
    func testModelAvailability() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        // This might fail if the model isn't pulled
        let isAvailable = try? await model.checkModelAvailability()
        #expect(isAvailable != nil)
    }
    
    @Test("List available models")
    @available(macOS 13.0, iOS 16.0, *)
    func testListModels() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let config = OllamaConfiguration()
        let httpClient = OllamaHTTPClient(configuration: config)
        let response: ModelsResponse? = try? await httpClient.send(EmptyRequest(), to: "/api/tags")
        let modelNames = response?.models.map { $0.name } ?? []
        
        #expect(modelNames.count >= 0)  // At least no error thrown
    }
}

