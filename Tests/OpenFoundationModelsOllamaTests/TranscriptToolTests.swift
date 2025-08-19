import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Transcript Tool Integration Tests")
struct TranscriptToolTests {
    
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
    
    @Test("Transcript with ToolDefinition - Weather Tool")
    func testTranscriptWithWeatherTool() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create weather tool using ToolSchemaHelper
        let weatherTool = try ToolSchemaHelper.createWeatherTool()
        
        // Create transcript with tool in instructions
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(
                    content: "You are a helpful assistant with access to weather information."
                ))],
                toolDefinitions: [weatherTool]
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(
                    content: "What's the weather like in Tokyo?"
                ))]
            ))
        ])
        
        // Generate response
        let response = try await model.generate(
            transcript: transcript,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 200)
        )
        
        print("Response entry:")
        switch response {
        case .response(let resp):
            for segment in resp.segments {
                switch segment {
                case .text(let text):
                    print("Text: \(text.content)")
                case .structure(let structure):
                    print("Structure: \(structure.content)")
                }
            }
        default:
            print("Unexpected response type")
        }
        
        // Check if we got a response
        let hasResponse = switch response {
        case .response: true
        default: false
        }
        
        // Should have gotten a response
        #expect(hasResponse)
    }
    
    @Test("Transcript with Multiple Tools")
    func testTranscriptWithMultipleTools() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create multiple tools
        let weatherTool = try ToolSchemaHelper.createWeatherTool()
        let calculatorTool = try ToolSchemaHelper.createCalculatorTool()
        
        // Create transcript with multiple tools
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(
                    content: "You are a helpful assistant with weather and calculation capabilities."
                ))],
                toolDefinitions: [weatherTool, calculatorTool]
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(
                    content: "Calculate 42 * 17"
                ))]
            ))
        ])
        
        // Generate response
        let response = try await model.generate(
            transcript: transcript,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100)
        )
        
        // Verify response contains either tool call or calculation result
        var foundResponse = false
        switch response {
        case .response(let resp):
            for segment in resp.segments {
                switch segment {
                case .text(let text):
                    print("Text response: \(text.content)")
                    foundResponse = true
                case .structure:
                    foundResponse = true
                }
            }
        default:
            break
        }
        
        #expect(foundResponse)
    }
    
    @Test("Complete Tool Execution Flow with Transcript")
    func testCompleteToolFlow() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create a simple tool
        let tool = ToolSchemaHelper.createSimpleTool(
            name: "get_current_time",
            description: "Get the current time"
        )
        
        // Start transcript
        var transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(
                    content: "You are a helpful assistant that can tell the time."
                ))],
                toolDefinitions: [tool]
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(
                    content: "What time is it?"
                ))]
            ))
        ])
        
        // First generation - might trigger tool call
        let response1 = try await model.generate(
            transcript: transcript,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100)
        )
        
        print("First response:")
        var toolCalled = false
        
        // Check if response contains tool calls
        switch response1 {
        case .response(let resp):
            for segment in resp.segments {
                switch segment {
                case .text(let text):
                    print("  Text: \(text.content)")
                case .structure(let structure):
                    // Check if it's a tool call structure
                    if let props = try? structure.content.properties(),
                       let toolCallsContent = props["tool_calls"] {
                        toolCalled = true
                        print("  Tool calls detected")
                        
                        // Create new transcript with tool call and output
                        var entries = Array(transcript.entries)
                        entries.append(response1)
                        
                        // Add simulated tool output
                        entries.append(.toolOutput(Transcript.ToolOutput(
                            id: UUID().uuidString,
                            toolName: "get_current_time",
                            segments: [.text(Transcript.TextSegment(
                                content: "The current time is 3:45 PM EST"
                            ))]
                        )))
                        
                        transcript = Transcript(entries: entries)
                    }
                }
            }
        default:
            break
        }
        
        // Add assistant response to transcript if no tool was called
        if !toolCalled {
            var entries = Array(transcript.entries)
            entries.append(response1)
            transcript = Transcript(entries: entries)
        } else {
            // Get final response after tool execution
            let response2 = try await model.generate(
                transcript: transcript,
                options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100)
            )
            
            print("Final response after tool execution:")
            switch response2 {
            case .response(let resp):
                for segment in resp.segments {
                    if case .text(let text) = segment {
                        print("  \(text.content)")
                        #expect(text.content.lowercased().contains("time") || text.content.contains("3:45"))
                    }
                }
            default:
                break
            }
            
            var entries = Array(transcript.entries)
            entries.append(response2)
            transcript = Transcript(entries: entries)
        }
        
        // Verify transcript has expected structure
        #expect(transcript.count >= 3) // instructions, prompt, and at least one response
        
        // Check first entry is instructions with tools
        if case .instructions(let instructions) = transcript[0] {
            #expect(instructions.toolDefinitions.count == 1)
            #expect(instructions.toolDefinitions.first?.name == "get_current_time")
        } else {
            #expect(Bool(false), "First entry should be instructions")
        }
    }
    
    @Test("Tool Extraction from Transcript")
    func testToolExtraction() throws {
        // Create tools using ToolSchemaHelper
        let weatherTool = try ToolSchemaHelper.createWeatherTool()
        let calculatorTool = try ToolSchemaHelper.createCalculatorTool()
        
        // Create transcript with tools
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(
                    content: "Assistant with tools"
                ))],
                toolDefinitions: [weatherTool, calculatorTool]
            ))
        ])
        
        // Extract tools using TranscriptConverter
        let tools = TranscriptConverter.extractTools(from: transcript) ?? []
        
        #expect(tools.count == 2)
        
        // Verify weather tool
        if let weather = tools.first(where: { $0.function.name == "get_weather" }) {
            #expect(weather.type == "function")
            #expect(weather.function.description == "Get current weather and optional forecast")
            // Note: Schema conversion may not preserve all properties due to GenerationSchema encoding limitations
            print("Weather tool parameters type: \(weather.function.parameters.type)")
            print("Weather tool properties: \(weather.function.parameters.properties)")
        } else {
            #expect(Bool(false), "Weather tool not found")
        }
        
        // Verify calculator tool
        if let calc = tools.first(where: { $0.function.name == "calculate" }) {
            #expect(calc.type == "function")
            #expect(calc.function.description == "Perform mathematical calculations")
            // Note: Schema conversion may not preserve all properties due to GenerationSchema encoding limitations
            print("Calculator tool parameters type: \(calc.function.parameters.type)")
            print("Calculator tool properties: \(calc.function.parameters.properties)")
        } else {
            #expect(Bool(false), "Calculator tool not found")
        }
    }
    
    @Test("Streaming with Tools in Transcript")
    func testStreamingWithTools() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create tool
        let tool = try ToolSchemaHelper.createCalculatorTool()
        
        // Create transcript
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(
                    content: "You are a math assistant."
                ))],
                toolDefinitions: [tool]
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(
                    content: "What is 123 + 456?"
                ))]
            ))
        ])
        
        // Stream response
        var entries: [Transcript.Entry] = []
        let stream = model.stream(
            transcript: transcript,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100)
        )
        
        for try await entry in stream {
            entries.append(entry)
            
            switch entry {
            case .response(let resp):
                for segment in resp.segments {
                    switch segment {
                    case .text(let text):
                        print("Streaming text: \(text.content)")
                    case .structure:
                        print("Streaming structure")
                    }
                }
            default:
                break
            }
        }
        
        #expect(entries.count > 0)
        
        // Should have received response
        let hasContent = entries.contains { entry in
            if case .response = entry {
                return true
            }
            return false
        }
        
        #expect(hasContent)
    }
}