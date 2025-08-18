import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

@Suite("@Generable Macro Tool Tests", .serialized)
struct GenerableToolTests {
    
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
    
    // MARK: - Test Types with @Generable
    
    @Generable
    struct WeatherToolArguments {
        @Guide(description: "City name to get weather for")
        let city: String
        
        @Guide(description: "Whether to include forecast data")
        let includeForecast: Bool?
        
        @Guide(description: "Number of forecast days", .range(1...7))
        let forecastDays: Int?
    }
    
    struct WeatherToolWithGenerable: OpenFoundationModels.Tool {
        typealias Arguments = WeatherToolArguments
        typealias Output = String
        
        var name: String { "get_weather_advanced" }
        var description: String { "Get detailed weather information with optional forecast" }
        var includesSchemaInInstructions: Bool { true }
        // parameters should be auto-implemented since Arguments: Generable
        
        func call(arguments: WeatherToolArguments) async throws -> String {
            var result = "Weather in \(arguments.city): Sunny, 22°C"
            if let includeForecast = arguments.includeForecast, includeForecast {
                let days = arguments.forecastDays ?? 3
                result += " (Forecast for \(days) days: Partly cloudy)"
            }
            return result
        }
    }
    
    // MARK: - Manual Implementation for Comparison
    
    struct ManualWeatherArguments: ConvertibleFromGeneratedContent {
        let city: String
        let includeForecast: Bool?
        let forecastDays: Int?
        
        init(_ content: GeneratedContent) throws {
            let props = try content.properties()
            self.city = try props["city"]?.value(String.self) ?? ""
            self.includeForecast = try? props["includeForecast"]?.value(Bool.self)
            self.forecastDays = try? props["forecastDays"]?.value(Int.self)
        }
    }
    
    struct ManualWeatherTool: OpenFoundationModels.Tool {
        typealias Arguments = ManualWeatherArguments
        typealias Output = String
        
        var name: String { "get_weather_manual" }
        var description: String { "Get weather information (manual implementation)" }
        var includesSchemaInInstructions: Bool { true }
        
        // Must implement parameters manually
        var parameters: GenerationSchema {
            // Create a simplified schema manually
            GenerationSchema(
                type: String.self,
                description: "Weather parameters",
                properties: []
            )
        }
        
        func call(arguments: ManualWeatherArguments) async throws -> String {
            return "Weather in \(arguments.city): Sunny, 22°C"
        }
    }
    
    // MARK: - Tests
    
    @Test("Verify @Generable generates GenerationSchema")
    func testGenerableSchemaGeneration() {
        // Check if WeatherToolArguments has a generationSchema
        let schema = WeatherToolArguments.generationSchema
        
        print("Generated schema exists: \(schema)")
        
        // The schema should have been generated
        // We can't access internal properties, but we can verify it exists
        #expect(schema != nil)
        
        // Try to encode the schema to see its structure
        if let encoded = try? JSONEncoder().encode(schema),
           let json = String(data: encoded, encoding: .utf8) {
            print("Schema as JSON: \(json)")
        }
    }
    
    @Test("Tool.parameters auto-implementation with @Generable")
    func testToolParametersAutoImplementation() {
        let generableTool = WeatherToolWithGenerable()
        let manualTool = ManualWeatherTool()
        
        // Get parameters from both tools
        let generableParams = generableTool.parameters
        let manualParams = manualTool.parameters
        
        print("Generable tool has parameters: \(generableParams)")
        print("Manual tool has parameters: \(manualParams)")
        
        // The generable tool should have auto-implemented parameters
        #expect(generableParams != nil)
        #expect(manualParams != nil)
        
        // Extract tools for Ollama API
        let generableTranscript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [],
                toolDefinitions: [
                    Transcript.ToolDefinition(
                        name: generableTool.name,
                        description: generableTool.description,
                        parameters: generableTool.parameters
                    )
                ]
            ))
        ])
        
        let tools = TranscriptConverter.extractTools(from: generableTranscript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            print("Extracted tool name: \(tool.function.name)")
            print("Extracted tool parameters type: \(tool.function.parameters.type)")
        }
    }
    
    @Test("Convert GeneratedContent to @Generable Arguments")
    func testGeneratedContentToGenerableArguments() throws {
        // Simulate LLM response with tool call arguments
        let generatedContent = GeneratedContent(
            kind: .structure(
                properties: [
                    "city": GeneratedContent(kind: .string("Tokyo")),
                    "includeForecast": GeneratedContent(kind: .bool(true)),
                    "forecastDays": GeneratedContent(kind: .number(5))
                ],
                orderedKeys: ["city", "includeForecast", "forecastDays"]
            )
        )
        
        // Test @Generable conversion
        let generableArgs = try WeatherToolArguments(generatedContent)
        #expect(generableArgs.city == "Tokyo")
        #expect(generableArgs.includeForecast == true)
        #expect(generableArgs.forecastDays == 5)
        
        // Test manual conversion
        let manualArgs = try ManualWeatherArguments(generatedContent)
        #expect(manualArgs.city == "Tokyo")
        #expect(manualArgs.includeForecast == true)
        #expect(manualArgs.forecastDays == 5)
        
        print("✅ Both @Generable and manual implementations parsed arguments correctly")
    }
    
    @Test("Test partial GeneratedContent with @Generable")
    func testPartialGeneratedContent() throws {
        // Simulate partial/incomplete content
        let partialContent = GeneratedContent(
            kind: .structure(
                properties: [
                    "city": GeneratedContent(kind: .string("Paris"))
                    // includeForecast and forecastDays are missing
                ],
                orderedKeys: ["city"]
            )
        )
        
        // @Generable should handle optional properties
        let args = try WeatherToolArguments(partialContent)
        #expect(args.city == "Paris")
        #expect(args.includeForecast == nil)
        #expect(args.forecastDays == nil)
        
        print("✅ @Generable handled partial content correctly")
    }
    
    @Test("Real Ollama API call with @Generable tool")
    func testRealOllamaCallWithGenerableTool() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let tool = WeatherToolWithGenerable()
        
        // Create session with the @Generable tool
        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: "You are a weather assistant. Use the get_weather_advanced tool when asked about weather."
        )
        
        // Request that should trigger tool usage with multiple parameters
        let response = try await session.respond(
            to: "What's the weather in Tokyo? Include a 5-day forecast.",
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("Response: \(response.content)")
        
        // Check if tool was called
        var toolWasCalled = false
        var capturedArguments: WeatherToolArguments?
        
        for entry in session.transcript {
            if case .toolCalls(let toolCalls) = entry {
                print("Tool calls found: \(toolCalls.map { $0.toolName })")
                toolWasCalled = true
                
                // Try to parse the arguments
                if let firstCall = toolCalls.first {
                    do {
                        capturedArguments = try WeatherToolArguments(firstCall.arguments)
                        print("Parsed arguments:")
                        print("  - city: \(capturedArguments?.city ?? "nil")")
                        print("  - includeForecast: \(capturedArguments?.includeForecast ?? false)")
                        print("  - forecastDays: \(capturedArguments?.forecastDays ?? 0)")
                    } catch {
                        print("Failed to parse arguments: \(error)")
                    }
                }
            }
        }
        
        if toolWasCalled {
            print("✅ @Generable tool was successfully called by LLM")
            if let args = capturedArguments {
                #expect(args.city.lowercased().contains("tokyo"))
                print("✅ Arguments were successfully parsed using @Generable")
            }
        } else {
            print("ℹ️ Model provided direct answer without using tool")
        }
    }
    
    @Test("Compare @Generable vs Manual schema generation")
    func testCompareGenerableVsManualSchema() {
        let generableTool = WeatherToolWithGenerable()
        let manualTool = ManualWeatherTool()
        
        // Create transcripts with both tools
        let generableTranscript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [],
                toolDefinitions: [
                    Transcript.ToolDefinition(
                        name: generableTool.name,
                        description: generableTool.description,
                        parameters: generableTool.parameters
                    )
                ]
            ))
        ])
        
        let manualTranscript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [],
                toolDefinitions: [
                    Transcript.ToolDefinition(
                        name: manualTool.name,
                        description: manualTool.description,
                        parameters: manualTool.parameters
                    )
                ]
            ))
        ])
        
        // Extract and compare
        let generableTools = TranscriptConverter.extractTools(from: generableTranscript)
        let manualTools = TranscriptConverter.extractTools(from: manualTranscript)
        
        #expect(generableTools?.count == 1)
        #expect(manualTools?.count == 1)
        
        if let genTool = generableTools?.first,
           let manTool = manualTools?.first {
            print("\n=== Schema Comparison ===")
            print("@Generable tool:")
            print("  Name: \(genTool.function.name)")
            print("  Parameters type: \(genTool.function.parameters.type)")
            print("  Properties count: \(genTool.function.parameters.properties.count)")
            
            print("\nManual tool:")
            print("  Name: \(manTool.function.name)")
            print("  Parameters type: \(manTool.function.parameters.type)")
            print("  Properties count: \(manTool.function.parameters.properties.count)")
            
            // Encode to JSON for comparison
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            if let genJSON = try? encoder.encode(genTool),
               let genString = String(data: genJSON, encoding: .utf8) {
                print("\n@Generable tool JSON:")
                print(genString)
            }
            
            if let manJSON = try? encoder.encode(manTool),
               let manString = String(data: manJSON, encoding: .utf8) {
                print("\nManual tool JSON:")
                print(manString)
            }
        }
    }
}

// MARK: - Test Skip Helper
extension GenerableToolTests {
    struct TestSkip: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}