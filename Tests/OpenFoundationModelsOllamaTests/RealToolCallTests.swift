import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Real Tool Call Integration Tests", .serialized)
struct RealToolCallTests {
    
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
    
    @Test("Real weather tool call with ToolDefinitionBuilder")
    @available(macOS 13.0, iOS 16.0, *)
    func testRealWeatherToolCall() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Clear registry and create a weather tool using ToolDefinitionBuilder
        ToolSchemaRegistry.shared.clear()
        
        let weatherTool = ToolDefinitionBuilder.createTool(
            name: "get_weather",
            description: "Get current weather information for a city",
            properties: [
                "location": .string("The city name (e.g., 'Tokyo', 'New York')"),
                "unit": .enumeration("Temperature unit", values: ["celsius", "fahrenheit"])
            ],
            required: ["location"]
        )
        
        // Create transcript with the tool
        var transcript = Transcript()
        
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [.text(Transcript.TextSegment(
                id: "seg-1",
                content: "You are a helpful assistant. When asked about weather, use the get_weather tool."
            ))],
            toolDefinitions: [weatherTool]
        )))
        
        transcript.append(.prompt(Transcript.Prompt(
            id: "prompt-1",
            segments: [.text(Transcript.TextSegment(
                id: "seg-2",
                content: "What's the weather in Tokyo?"
            ))],
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 150),
            responseFormat: nil
        )))
        
        // Generate response
        print("Testing weather tool call with real Ollama API...")
        let response = try await model.generate(transcript: transcript, options: nil)
        
        print("Response: \(response)")
        
        // The response should either contain tool call information or a regular response
        #expect(!response.isEmpty)
        
        // If it contains "get_weather" or tool call format, the tool was recognized
        if response.contains("get_weather") || response.contains("Tool calls:") {
            print("✅ Tool was called successfully!")
        } else {
            print("ℹ️ Model provided direct response: \(response)")
        }
    }
    
    @Test("Real calculation tool call")
    @available(macOS 13.0, iOS 16.0, *)
    func testRealCalculationToolCall() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Clear registry
        ToolSchemaRegistry.shared.clear()
        
        let calcTool = ToolDefinitionBuilder.createTool(
            name: "calculate",
            description: "Perform mathematical calculations",
            properties: [
                "expression": .string("Mathematical expression to evaluate (e.g., '2+2', '10*5')"),
                "operation": .enumeration("Operation type", values: ["add", "subtract", "multiply", "divide", "complex"])
            ],
            required: ["expression"]
        )
        
        var transcript = Transcript()
        
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [.text(Transcript.TextSegment(
                id: "seg-1", 
                content: "You are a math assistant. Use the calculate tool when asked to perform calculations."
            ))],
            toolDefinitions: [calcTool]
        )))
        
        transcript.append(.prompt(Transcript.Prompt(
            id: "prompt-1",
            segments: [.text(Transcript.TextSegment(
                id: "seg-2",
                content: "Calculate 25 * 4 + 10"
            ))],
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100),
            responseFormat: nil
        )))
        
        print("Testing calculation tool call...")
        let response = try await model.generate(transcript: transcript, options: nil)
        
        print("Response: \(response)")
        #expect(!response.isEmpty)
        
        if response.contains("calculate") || response.contains("Tool calls:") {
            print("✅ Calculation tool was called!")
        } else {
            print("ℹ️ Model provided direct calculation: \(response)")
        }
    }
    
    @Test("Direct Ollama API tool call verification")
    func testDirectOllamaAPICall() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        // Clear registry and create a tool
        ToolSchemaRegistry.shared.clear()
        
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "get_time",
            description: "Get the current time",
            properties: [
                "timezone": .string("Timezone (e.g., 'UTC', 'America/New_York')")
            ],
            required: []
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        // Extract tools using our converter
        let tools = TranscriptConverter.extractTools(from: transcript)
        
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            print("Generated tool definition:")
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            print(jsonString)
            
            // Test that the JSON is valid for Ollama
            let messages = [Message(role: .user, content: "What time is it?")]
            let request = ChatRequest(
                model: defaultModel,
                messages: messages,
                stream: false,
                tools: tools
            )
            
            // This should encode successfully
            let requestData = try encoder.encode(request)
            let requestString = String(data: requestData, encoding: .utf8) ?? ""
            print("Full Ollama request:")
            print(requestString)
            
            // Verify structure
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            let function = json?["function"] as? [String: Any]
            let parameters = function?["parameters"] as? [String: Any]
            
            #expect(parameters?["type"] as? String == "object")
            print("✅ Tool definition is valid for Ollama API")
        }
    }
    
    @Test("Multiple tools real test")
    @available(macOS 13.0, iOS 16.0, *)
    func testMultipleToolsReal() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Clear registry
        ToolSchemaRegistry.shared.clear()
        
        // Create multiple tools
        let weatherTool = ToolDefinitionBuilder.createTool(
            name: "get_weather",
            description: "Get weather information",
            properties: ["city": .string("City name")],
            required: ["city"]
        )
        
        let timeTool = ToolDefinitionBuilder.createTool(
            name: "get_time", 
            description: "Get current time",
            properties: ["timezone": .string("Timezone")],
            required: []
        )
        
        var transcript = Transcript()
        
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [.text(Transcript.TextSegment(
                id: "seg-1",
                content: "You can check weather and time when asked."
            ))],
            toolDefinitions: [weatherTool, timeTool]
        )))
        
        transcript.append(.prompt(Transcript.Prompt(
            id: "prompt-1",
            segments: [.text(Transcript.TextSegment(
                id: "seg-2", 
                content: "What's the weather in London and what time is it?"
            ))],
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 200),
            responseFormat: nil
        )))
        
        print("Testing multiple tools...")
        let response = try await model.generate(transcript: transcript, options: nil)
        
        print("Response: \(response)")
        #expect(!response.isEmpty)
        
        print("✅ Multiple tools test completed")
    }
}

// TestSkip is defined in other test files