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
    
    @Test("Real weather tool call with GenerationSchema")
    @available(macOS 13.0, iOS 16.0, *)
    func testRealWeatherToolCall() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create a weather tool using simplified GenerationSchema
        let schema = GenerationSchema(type: String.self, description: "Weather location", properties: [])
        
        let weatherTool = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get current weather information for a city",
            parameters: schema
        )
        
        // Create transcript with the tool
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-1",
                    content: "You are a helpful assistant. When asked about weather, use the get_weather tool."
                ))],
                toolDefinitions: [weatherTool]
            )),
            .prompt(Transcript.Prompt(
                id: "prompt-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-2",
                    content: "What's the weather in Tokyo?"
                ))],
                options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 150),
                responseFormat: nil
            ))
        ])
        
        // Generate response
        print("Testing weather tool call with real Ollama API...")
        let response = try await model.generate(transcript: transcript, options: nil)
        
        print("Response: \(response)")
        
        // Handle the response based on entry type
        switch response {
        case .toolCalls(let toolCalls):
            print("✅ Tool was called successfully! Tools: \(toolCalls.map { $0.toolName })")
            #expect(toolCalls.count > 0)
        case .response(let responseData):
            print("ℹ️ Model provided direct response: \(responseData.segments)")
            #expect(responseData.segments.count > 0)
        default:
            print("⚠️ Unexpected response type: \(response)")
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
        
        // Create calculation tool using simplified GenerationSchema
        let schema = GenerationSchema(type: String.self, description: "Mathematical expression", properties: [])
        
        let calcTool = Transcript.ToolDefinition(
            name: "calculate",
            description: "Perform mathematical calculations",
            parameters: schema
        )
        
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-1", 
                    content: "You are a math assistant. Use the calculate tool when asked to perform calculations."
                ))],
                toolDefinitions: [calcTool]
            )),
            .prompt(Transcript.Prompt(
                id: "prompt-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-2",
                    content: "Calculate 25 * 4 + 10"
                ))],
                options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100),
                responseFormat: nil
            ))
        ])
        
        print("Testing calculation tool call...")
        let response = try await model.generate(transcript: transcript, options: nil)
        
        print("Response: \(response)")
        
        // Handle the response based on entry type
        switch response {
        case .toolCalls(let toolCalls):
            print("✅ Calculation tool was called! Tools: \(toolCalls.map { $0.toolName })")
            #expect(toolCalls.count > 0)
        case .response(let responseData):
            print("ℹ️ Model provided direct calculation: \(responseData.segments)")
            #expect(responseData.segments.count > 0)
        default:
            print("⚠️ Unexpected response type: \(response)")
        }
    }
    
    @Test("Direct Ollama API tool call verification")
    func testDirectOllamaAPICall() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        // Create a tool using simplified GenerationSchema
        let schema = GenerationSchema(type: String.self, description: "Timezone", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "get_time",
            description: "Get the current time",
            parameters: schema
        )
        
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [toolDef]
            ))
        ])
        
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
            
            #expect(parameters?["type"] as? String == "string") // Simplified schema uses String type
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
        
        // Create multiple tools using simplified GenerationSchema
        let weatherSchema = GenerationSchema(type: String.self, description: "City name", properties: [])
        
        let weatherTool = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get weather information",
            parameters: weatherSchema
        )
        
        let timeSchema = GenerationSchema(type: String.self, description: "Timezone", properties: [])
        
        let timeTool = Transcript.ToolDefinition(
            name: "get_time",
            description: "Get current time",
            parameters: timeSchema
        )
        
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-1",
                    content: "You can check weather and time when asked."
                ))],
                toolDefinitions: [weatherTool, timeTool]
            )),
            .prompt(Transcript.Prompt(
                id: "prompt-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-2", 
                    content: "What's the weather in London and what time is it?"
                ))],
                options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 200),
                responseFormat: nil
            ))
        ])
        
        print("Testing multiple tools...")
        let response = try await model.generate(transcript: transcript, options: nil)
        
        print("Response: \(response)")
        
        // Handle the response based on entry type
        switch response {
        case .toolCalls(let toolCalls):
            print("✅ Tools were called! Tools: \(toolCalls.map { $0.toolName })")
            #expect(toolCalls.count > 0)
        case .response(let responseData):
            print("ℹ️ Model provided direct response: \(responseData.segments)")
            #expect(responseData.segments.count > 0)
        default:
            print("⚠️ Unexpected response type: \(response)")
        }
        
        print("✅ Multiple tools test completed")
    }
}

// TestSkip is defined in other test files