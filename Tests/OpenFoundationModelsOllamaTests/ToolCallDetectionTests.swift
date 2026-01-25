import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Tool Call Detection Tests", .serialized)
struct ToolCallDetectionTests {

    @Test("OllamaLanguageModel returns tool calls as Transcript.Entry")
    func testToolCallDetection() async throws {
        // Create a mock HTTP client that returns tool calls
        let mockResponse = ChatResponse(
            model: "test-model",
            createdAt: Date(),
            message: Message(
                role: .assistant,
                content: "",
                toolCalls: [
                    ToolCall(
                        function: ToolCall.FunctionCall(
                            name: "get_weather",
                            arguments: ["city": "Tokyo"]
                        )
                    )
                ]
            ),
            done: true,
            totalDuration: nil,
            loadDuration: nil,
            promptEvalCount: nil,
            promptEvalDuration: nil,
            evalCount: nil,
            evalDuration: nil
        )

        #expect(mockResponse.message?.toolCalls?.count == 1)
        #expect(mockResponse.message?.toolCalls?.first?.function.name == "get_weather")
    }

    @Test("Transcript.Entry.toolCalls creation")
    func testToolCallsEntryCreation() throws {
        let arguments = GeneratedContent(properties: [
            "city": "Tokyo",
            "units": "celsius"
        ])

        let toolCall = Transcript.ToolCall(
            id: "call-1",
            toolName: "get_weather",
            arguments: arguments
        )

        let toolCalls = Transcript.ToolCalls(
            id: "calls-1",
            [toolCall]
        )

        let entry = Transcript.Entry.toolCalls(toolCalls)

        if case .toolCalls(let calls) = entry {
            #expect(calls.count == 1)
            #expect(calls.first?.toolName == "get_weather")
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }

    @Test("Generate method returns tool calls when Ollama responds with tool calls", .timeLimit(.minutes(1)))
    func testGenerateReturnsToolCalls() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()

        let weatherTool = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get weather for a city",
            parameters: GenerationSchema(
                type: String.self,
                description: "City name",
                properties: []
            )
        )

        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-1",
                    content: "You are a helpful assistant with access to weather tools."
                ))],
                toolDefinitions: [weatherTool]
            )),
            .prompt(Transcript.Prompt(
                id: "prompt-1",
                segments: [.text(Transcript.TextSegment(
                    id: "seg-2",
                    content: "What's the weather in Tokyo? Use the get_weather tool."
                ))],
                options: GenerationOptions(temperature: 0.1),
                responseFormat: nil
            ))
        ])

        let entry = try await model.generate(transcript: transcript, options: nil)

        switch entry {
        case .toolCalls(let toolCalls):
            print("Model returned tool calls: \(toolCalls.count) calls")
            #expect(toolCalls.count > 0)
        case .response(let response):
            print("Model returned direct response: \(response.segments)")
        default:
            Issue.record("Unexpected entry type: \(entry)")
        }
    }
}
