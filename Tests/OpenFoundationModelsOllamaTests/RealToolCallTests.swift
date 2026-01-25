import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Real Tool Call Integration Tests", .serialized)
struct RealToolCallTests {

    @Test("Real weather tool call with GenerationSchema", .timeLimit(.minutes(1)))
    func testRealWeatherToolCall() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()

        let schema = GenerationSchema(type: String.self, description: "Weather location", properties: [])

        let weatherTool = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get current weather information for a city",
            parameters: schema
        )

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

        print("Testing weather tool call with real Ollama API...")
        let response = try await model.generate(transcript: transcript, options: nil)

        print("Response: \(response)")

        switch response {
        case .toolCalls(let toolCalls):
            print("Tool was called successfully! Tools: \(toolCalls.map { $0.toolName })")
            #expect(toolCalls.count > 0)
        case .response(let responseData):
            print("Model provided direct response: \(responseData.segments)")
            #expect(responseData.segments.count > 0)
        default:
            print("Unexpected response type: \(response)")
        }
    }

    @Test("Real calculation tool call", .timeLimit(.minutes(1)))
    func testRealCalculationToolCall() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()

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

        switch response {
        case .toolCalls(let toolCalls):
            print("Calculation tool was called! Tools: \(toolCalls.map { $0.toolName })")
            #expect(toolCalls.count > 0)
        case .response(let responseData):
            print("Model provided direct calculation: \(responseData.segments)")
            #expect(responseData.segments.count > 0)
        default:
            print("Unexpected response type: \(response)")
        }
    }

    @Test("Direct Ollama API tool call verification", .timeLimit(.minutes(1)))
    func testDirectOllamaAPICall() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

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

        let tools = try TranscriptConverter.extractTools(from: transcript)

        #expect(tools?.count == 1)

        if let tool = tools?.first {
            print("Generated tool definition:")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            print(jsonString)

            let messages = [Message(role: .user, content: "What time is it?")]
            let request = ChatRequest(
                model: TestConfiguration.defaultModel,
                messages: messages,
                stream: false,
                tools: tools
            )

            let requestData = try encoder.encode(request)
            let requestString = String(data: requestData, encoding: .utf8) ?? ""
            print("Full Ollama request:")
            print(requestString)

            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            let function = json?["function"] as? [String: Any]
            let parameters = function?["parameters"] as? [String: Any]

            #expect(parameters?["type"] as? String == "string")
            print("Tool definition is valid for Ollama API")
        }
    }

    @Test("Multiple tools real test", .timeLimit(.minutes(1)))
    func testMultipleToolsReal() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()

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

        switch response {
        case .toolCalls(let toolCalls):
            print("Tools were called! Tools: \(toolCalls.map { $0.toolName })")
            #expect(toolCalls.count > 0)
        case .response(let responseData):
            print("Model provided direct response: \(responseData.segments)")
            #expect(responseData.segments.count > 0)
        default:
            print("Unexpected response type: \(response)")
        }

        print("Multiple tools test completed")
    }
}
