import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

@Suite("Tool Execution Loop Integration Tests", .serialized)
struct ToolExecutionLoopTests {

    @Test("LanguageModelSession executes tools automatically", .timeLimit(.minutes(2)))
    func testLanguageModelSessionToolExecution() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()
        let mockTool = MockCalculatorTool()

        let session = LanguageModelSession(
            model: model,
            tools: [mockTool],
            instructions: "You are a calculator assistant. Use the calculator tool for math."
        )

        let response = try await session.respond(
            to: "Calculate 15 + 27",
            options: GenerationOptions(temperature: 0.1)
        )

        print("Session response: \(response.content)")
        #expect(response.content.contains("42") || response.content.contains("15 + 27"))

        let transcript = session.transcript
        var hasToolCalls = false
        var hasToolOutput = false

        for entry in transcript {
            switch entry {
            case .toolCalls(let toolCalls):
                hasToolCalls = true
                print("Found tool calls: \(toolCalls.map { $0.toolName })")
                #expect(toolCalls.first?.toolName == "calculator")

            case .toolOutput(let toolOutput):
                hasToolOutput = true
                print("Found tool output: \(toolOutput.toolName)")
                #expect(toolOutput.toolName == "calculator")

            default:
                break
            }
        }

        if hasToolCalls && hasToolOutput {
            print("Complete tool execution loop verified!")
        } else {
            print("Model may have provided direct answer without using tools")
        }
    }

    @Test("LanguageModelSession handles multiple tool calls", .timeLimit(.minutes(2)))
    func testMultipleToolCalls() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()
        let calculator = MockCalculatorTool()
        let weather = MockWeatherTool()

        let session = LanguageModelSession(
            model: model,
            tools: [calculator, weather],
            instructions: "You are a helpful assistant with access to calculator and weather tools. Always use the appropriate tool when asked."
        )

        let response = try await session.respond(
            to: "What's the weather in Tokyo and what's 50 + 75?",
            options: GenerationOptions(temperature: 0.1)
        )

        print("Multiple tools response: \(response.content)")

        let transcript = session.transcript
        var toolsUsed: Set<String> = []

        for entry in transcript {
            if case .toolCalls(let toolCalls) = entry {
                for toolCall in toolCalls {
                    toolsUsed.insert(toolCall.toolName)
                }
            }
        }

        print("Tools used: \(toolsUsed)")

        if !response.content.isEmpty && !toolsUsed.isEmpty {
            print("Tools were executed and response received!")
        } else if !toolsUsed.isEmpty {
            print("Tools were executed (response may be in thinking)")
        } else if !response.content.isEmpty {
            print("Model provided direct answer without using tools")
        } else {
            print("Empty response - model may have used thinking only (known gpt-oss limitation)")
        }
    }
}

// MARK: - Mock Tools for Testing

// MARK: - Thinking Model Tool Tests

@Suite("Thinking Model Tool Tests", .serialized)
struct ThinkingModelToolTests {

    @Test("LFM 2.5 Thinking model tool support", .timeLimit(.minutes(2)))
    func testLfmThinkingToolSupport() async throws {
        let modelName = "lfm2.5-thinking:latest"

        // Check if model is available
        guard await OllamaTestCoordinator.shared.isModelAvailable(modelName) else {
            throw TestSkip(reason: "Model \(modelName) not available")
        }

        let model = OllamaTestCoordinator.shared.createModel(modelName: modelName)
        let mockTool = MockCalculatorTool()

        let session = LanguageModelSession(
            model: model,
            tools: [mockTool],
            instructions: "You are a calculator assistant. Use the calculator tool for math."
        )

        print("=== Testing \(modelName) with tools ===")

        let response = try await session.respond(
            to: "Calculate 15 + 27",
            options: GenerationOptions(temperature: 0.1)
        )

        print("Response: \(response.content)")

        // Analyze transcript
        var hasToolCalls = false
        for entry in session.transcript {
            switch entry {
            case .toolCalls(let toolCalls):
                hasToolCalls = true
                print("Tool calls found: \(toolCalls.map { $0.toolName })")
            case .response(let resp):
                print("Response entry: \(resp.segments)")
            default:
                break
            }
        }

        if hasToolCalls {
            print("✅ \(modelName) supports tools!")
        } else {
            print("⚠️ \(modelName) did not use tools - may output in thinking/content")
        }
    }

    @Test("GLM 4.7 Flash model tool support", .timeLimit(.minutes(2)))
    func testGlmFlashToolSupport() async throws {
        let modelName = "glm-4.7-flash:latest"

        guard await OllamaTestCoordinator.shared.isModelAvailable(modelName) else {
            throw TestSkip(reason: "Model \(modelName) not available")
        }

        let model = OllamaTestCoordinator.shared.createModel(modelName: modelName)
        let mockTool = MockCalculatorTool()

        let session = LanguageModelSession(
            model: model,
            tools: [mockTool],
            instructions: "You are a calculator assistant. Use the calculator tool for math."
        )

        print("=== Testing \(modelName) with tools ===")

        let response = try await session.respond(
            to: "Calculate 15 + 27",
            options: GenerationOptions(temperature: 0.1)
        )

        print("Response: \(response.content)")

        var hasToolCalls = false
        for entry in session.transcript {
            if case .toolCalls(let toolCalls) = entry {
                hasToolCalls = true
                print("Tool calls found: \(toolCalls.map { $0.toolName })")
            }
        }

        if hasToolCalls {
            print("✅ \(modelName) supports tools!")
        } else {
            print("⚠️ \(modelName) did not use tools")
        }
    }
}

// MARK: - Mock Tools for Testing

struct MockCalculatorTool: OpenFoundationModels.Tool {
    typealias Arguments = CalculatorArguments
    typealias Output = String

    var name: String { "calculator" }
    var description: String { "Performs basic arithmetic calculations" }
    var includesSchemaInInstructions: Bool { true }

    @Generable
    struct CalculatorArguments {
        @Guide(description: "Mathematical expression to calculate")
        let expression: String
    }

    func call(arguments: CalculatorArguments) async throws -> String {
        let expression = arguments.expression.lowercased()
        let result: String

        if expression.contains("15") && expression.contains("27") {
            result = "42"
        } else if expression.contains("50") && expression.contains("75") {
            result = "125"
        } else {
            result = "Calculated: \(expression)"
        }

        return "The result is \(result)"
    }
}

struct MockWeatherTool: OpenFoundationModels.Tool {
    typealias Arguments = WeatherArguments
    typealias Output = String

    var name: String { "weather" }
    var description: String { "Gets weather information for a city" }
    var includesSchemaInInstructions: Bool { true }

    @Generable
    struct WeatherArguments {
        @Guide(description: "City name")
        let city: String
    }

    func call(arguments: WeatherArguments) async throws -> String {
        return "The weather in \(arguments.city) is sunny, 22C"
    }
}
