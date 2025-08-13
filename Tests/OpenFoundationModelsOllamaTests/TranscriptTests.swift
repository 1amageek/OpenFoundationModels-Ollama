import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
@testable import OpenFoundationModelsCore

@Suite("Transcript-based Ollama Tests")
struct TranscriptTests {
    
    // MARK: - Test Configuration
    
    private let defaultModel = "gpt-oss:20b"
    private let testTimeout: TimeInterval = 30.0
    
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
    
    // MARK: - TranscriptConverter Tests
    
    @Test("Convert simple transcript to messages")
    func testSimpleTranscriptConversion() throws {
        // Create a simple transcript
        var transcript = Transcript()
        
        // Add instructions
        let instructions = Transcript.Instructions(
            id: "inst-1",
            segments: [
                .text(Transcript.TextSegment(id: "seg-1", content: "You are a helpful assistant."))
            ],
            toolDefinitions: []
        )
        transcript.append(.instructions(instructions))
        
        // Add user prompt
        let prompt = Transcript.Prompt(
            id: "prompt-1",
            segments: [
                .text(Transcript.TextSegment(id: "seg-2", content: "Hello, how are you?"))
            ],
            options: GenerationOptions(),
            responseFormat: nil
        )
        transcript.append(.prompt(prompt))
        
        // Convert to Ollama messages
        let messages = TranscriptConverter.buildMessages(from: transcript)
        
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[0].content == "You are a helpful assistant.")
        #expect(messages[1].role == .user)
        #expect(messages[1].content == "Hello, how are you?")
    }
    
    @Test("Extract tools from transcript")
    func testToolExtraction() throws {
        // Create transcript with tools
        var transcript = Transcript()
        
        // Create a mock GenerationSchema for tool parameters
        // Since we can't easily create a proper GenerationSchema,
        // we'll use the internal initializer for testing
        let mockSchema = GenerationSchema(
            type: "object",
            description: "Weather parameters",
            properties: nil,
            required: nil
        )
        
        let toolDef = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get the current weather",
            parameters: mockSchema
        )
        
        let instructions = Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )
        transcript.append(.instructions(instructions))
        
        // Extract tools
        let tools = TranscriptConverter.extractTools(from: transcript)
        
        #expect(tools?.count == 1)
        #expect(tools?.first?.function.name == "get_weather")
        #expect(tools?.first?.function.description == "Get the current weather")
    }
    
    @Test("Handle conversation history")
    func testConversationHistory() throws {
        var transcript = Transcript()
        
        // Add multiple exchanges
        transcript.append(.prompt(Transcript.Prompt(
            id: "p1",
            segments: [.text(Transcript.TextSegment(id: "s1", content: "What is 2+2?"))],
            options: GenerationOptions(),
            responseFormat: nil
        )))
        
        transcript.append(.response(Transcript.Response(
            id: "r1",
            assetIDs: [],
            segments: [.text(Transcript.TextSegment(id: "s2", content: "2+2 equals 4."))]
        )))
        
        transcript.append(.prompt(Transcript.Prompt(
            id: "p2",
            segments: [.text(Transcript.TextSegment(id: "s3", content: "What about 3+3?"))],
            options: GenerationOptions(),
            responseFormat: nil
        )))
        
        // Convert to messages
        let messages = TranscriptConverter.buildMessages(from: transcript)
        
        #expect(messages.count == 3)
        #expect(messages[0].role == .user)
        #expect(messages[0].content == "What is 2+2?")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].content == "2+2 equals 4.")
        #expect(messages[2].role == .user)
        #expect(messages[2].content == "What about 3+3?")
    }
    
    // MARK: - Integration Tests (requires Ollama running)
    
    @Test("Generate with transcript")
    @available(macOS 13.0, iOS 16.0, *)
    func testGenerateWithTranscript() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create a transcript
        var transcript = Transcript()
        transcript.append(.prompt(Transcript.Prompt(
            id: "test-prompt",
            segments: [.text(Transcript.TextSegment(id: "seg-1", content: "Say 'Hello, World!' and nothing else."))],
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100),
            responseFormat: nil
        )))
        
        // Generate response
        let response = try await model.generate(transcript: transcript, options: nil)
        
        
        #expect(!response.isEmpty)
        #expect(response.lowercased().contains("hello") || response.contains("world"))
    }
    
    @Test("Stream with transcript")
    @available(macOS 13.0, iOS 16.0, *)
    func testStreamWithTranscript() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create a transcript
        var transcript = Transcript()
        transcript.append(.prompt(Transcript.Prompt(
            id: "test-prompt",
            segments: [.text(Transcript.TextSegment(id: "seg-1", content: "Count from 1 to 3."))],
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100),
            responseFormat: nil
        )))
        
        // Stream response
        var chunks: [String] = []
        let stream = model.stream(transcript: transcript, options: nil)
        
        for await chunk in stream {
            chunks.append(chunk)
        }
        
        #expect(chunks.count > 0)
        
        let fullResponse = chunks.joined()
        #expect(!fullResponse.isEmpty)
    }
    
    @Test("Generate with tools in transcript")
    @available(macOS 13.0, iOS 16.0, *)
    func testGenerateWithToolsInTranscript() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: "gpt-oss:20b") // Use a model that supports tools
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model not available")
        }
        
        // Create transcript with tools
        var transcript = Transcript()
        
        let mockSchema = GenerationSchema(
            type: "object",
            description: "Time parameters",
            properties: nil,
            required: nil
        )
        
        let toolDef = Transcript.ToolDefinition(
            name: "get_time",
            description: "Get the current time",
            parameters: mockSchema
        )
        
        let instructions = Transcript.Instructions(
            id: "inst-1",
            segments: [.text(Transcript.TextSegment(id: "seg-1", content: "You can use tools when needed."))],
            toolDefinitions: [toolDef]
        )
        transcript.append(.instructions(instructions))
        
        transcript.append(.prompt(Transcript.Prompt(
            id: "prompt-1",
            segments: [.text(Transcript.TextSegment(id: "seg-2", content: "What time is it?"))],
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100),
            responseFormat: nil
        )))
        
        // Generate response
        let response = try await model.generate(transcript: transcript, options: nil)
        
        #expect(!response.isEmpty)
        // The model might either call the tool or provide a direct response
    }
}

// TestSkip is already defined in OllamaToolTests.swift