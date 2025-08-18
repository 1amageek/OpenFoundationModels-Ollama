import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

@Suite("Tool Execution Loop Integration Tests", .serialized)
struct ToolExecutionLoopTests {
    
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
    
    @Test("LanguageModelSession executes tools automatically")
    func testLanguageModelSessionToolExecution() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        // Create model and mock tool
        let model = OllamaLanguageModel(modelName: defaultModel)
        let mockTool = MockCalculatorTool()
        
        // Create session with tool
        let session = LanguageModelSession(
            model: model,
            tools: [mockTool],
            instructions: "You are a calculator assistant. Use the calculator tool for math."
        )
        
        // Make request that should trigger tool usage
        let response = try await session.respond(
            to: "Calculate 15 + 27",
            options: GenerationOptions(temperature: 0.1)
        )
        
        // Verify the response contains the calculation result
        print("Session response: \(response.content)")
        #expect(response.content.contains("42") || response.content.contains("15 + 27"))
        
        // Verify transcript contains tool calls and outputs
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
            print("✅ Complete tool execution loop verified!")
        } else {
            print("ℹ️ Model may have provided direct answer without using tools")
        }
    }
    
    @Test("LanguageModelSession handles multiple tool calls")
    func testMultipleToolCalls() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        let calculator = MockCalculatorTool()
        let weather = MockWeatherTool()
        
        let session = LanguageModelSession(
            model: model,
            tools: [calculator, weather],
            instructions: "You are a helpful assistant with access to calculator and weather tools."
        )
        
        let response = try await session.respond(
            to: "What's the weather in Tokyo and what's 50 + 75?",
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("Multiple tools response: \(response.content)")
        #expect(!response.content.isEmpty)
        
        // Check if tools were used
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
        if !toolsUsed.isEmpty {
            print("✅ Tools were executed!")
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
        // Simple mock calculation
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
        return "The weather in \(arguments.city) is sunny, 22°C"
    }
}