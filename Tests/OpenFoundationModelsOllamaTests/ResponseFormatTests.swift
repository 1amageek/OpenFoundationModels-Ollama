import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

@Suite("Response Format Tests", .serialized)
struct ResponseFormatTests {
    
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
    struct WeatherResponse {
        @Guide(description: "Temperature in celsius")
        let temperature: Int
        
        @Guide(description: "Weather condition", .anyOf(["sunny", "cloudy", "rainy", "snowy"]))
        let condition: String
        
        @Guide(description: "Humidity percentage", .range(0...100))
        let humidity: Int?
    }
    
    @Generable
    struct TodoItem {
        let id: GenerationID
        
        @Guide(description: "Todo task description")
        let task: String
        
        @Guide(description: "Priority level", .anyOf(["low", "medium", "high"]))
        let priority: String
        
        @Guide(description: "Due date in ISO format")
        let dueDate: String?
    }
    
    @Generable
    struct TodoList {
        @Guide(description: "List of todo items", .count(3))
        let todos: [TodoItem]
    }
    
    // MARK: - Tests
    
    @Test("Extract JSON Schema from Transcript.ResponseFormat - Limited")
    func testExtractResponseFormatSchema() throws {
        // Create a transcript with ResponseFormat
        var transcript = Transcript()
        transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "What's the weather?"))],
                responseFormat: Transcript.ResponseFormat(type: WeatherResponse.self)
            ))
        ])
        
        // Test schema extraction
        // Note: Due to private schema property, we can only detect that a ResponseFormat exists
        let format = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
        
        #expect(format != nil)
        
        // We get .json because the schema is private in Transcript.ResponseFormat
        if case .json = format {
            // Expected
        } else {
            Issue.record("Expected .json format, got \(String(describing: format))")
        }
        
        print("Note: Full schema extraction from Transcript.ResponseFormat is limited due to private properties.")
        print("Use the explicit schema methods for full structured output support.")
    }
    
    @Test("Direct JSON Schema from GenerationSchema")
    func testDirectSchemaFromGenerationSchema() throws {
        // Get the schema directly from the Generable type
        let schema = WeatherResponse.generationSchema
        
        // Encode it to get JSON Schema
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let schemaData = try encoder.encode(schema)
        
        print("Direct JSON Schema from GenerationSchema:")
        if let jsonString = String(data: schemaData, encoding: .utf8) {
            print(jsonString)
        }
        
        // Parse as JSON to verify structure
        let schemaJSON = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any]
        
        #expect(schemaJSON != nil)
        #expect(schemaJSON?["type"] as? String == "object")
        #expect(schemaJSON?["properties"] != nil)
        
        if let properties = schemaJSON?["properties"] as? [String: Any] {
            #expect(properties["temperature"] != nil)
            #expect(properties["condition"] != nil)
            #expect(properties["humidity"] != nil)
        }
        
        if let required = schemaJSON?["required"] as? [String] {
            #expect(required.contains("temperature"))
            #expect(required.contains("condition"))
            #expect(!required.contains("humidity")) // Optional field
        }
    }
    
    @Test("ResponseFormat encoding/decoding with JSON Schema")
    func testResponseFormatCodable() throws {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Person's name"],
                "age": ["type": "integer", "minimum": 0, "maximum": 120]
            ],
            "required": ["name", "age"]
        ]
        
        let format = ResponseFormat.jsonSchema(schema)
        
        // Test encoding
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let encoded = try encoder.encode(format)
        
        print("Encoded ResponseFormat:")
        if let jsonString = String(data: encoded, encoding: .utf8) {
            print(jsonString)
        }
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ResponseFormat.self, from: encoded)
        
        if case .jsonSchema(let decodedSchema) = decoded {
            #expect(decodedSchema["type"] as? String == "object")
            #expect(decodedSchema["properties"] != nil)
            #expect(decodedSchema["required"] != nil)
        } else {
            Issue.record("Failed to decode as jsonSchema")
        }
    }
    
    @Test("Transcript with ResponseFormat full round-trip")
    func testTranscriptResponseFormatRoundTrip() throws {
        // Create transcript with ResponseFormat
        var transcript = Transcript()
        transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "You are a helpful assistant."))],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Create a todo list with 3 items."))],
                options: GenerationOptions(temperature: 0.1),
                responseFormat: Transcript.ResponseFormat(type: TodoList.self)
            ))
        ])
        
        // Extract schema using our method
        let format = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
        
        #expect(format != nil)
        
        if case .jsonSchema(let schema) = format {
            print("\n=== Extracted Schema for TodoList ===")
            if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
            
            // Verify TodoList schema structure
            #expect(schema["type"] as? String == "object")
            
            if let properties = schema["properties"] as? [String: Any] {
                #expect(properties["todos"] != nil)
                
                if let todosProperty = properties["todos"] as? [String: Any] {
                    #expect(todosProperty["type"] as? String == "array")
                    #expect(todosProperty["minItems"] as? Int == 3)
                    #expect(todosProperty["maxItems"] as? Int == 3)
                }
            }
        }
    }
    
    @Test("Explicit schema generation with OllamaLanguageModel")
    func testExplicitSchemaGeneration() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create a basic transcript
        var transcript = Transcript()
        transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "What's the weather in Tokyo today?"))]
            ))
        ])
        
        // Generate with explicit schema
        let (entry, weather) = try await model.generate(
            transcript: transcript,
            generating: WeatherResponse.self,
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("\n=== Structured Response with Explicit Schema ===")
        print("Temperature: \(weather.temperature)°C")
        print("Condition: \(weather.condition)")
        if let humidity = weather.humidity {
            print("Humidity: \(humidity)%")
        }
        
        // Verify the response
        #expect(weather.temperature >= -50 && weather.temperature <= 50)
        #expect(["sunny", "cloudy", "rainy", "snowy"].contains(weather.condition))
        if let humidity = weather.humidity {
            #expect(humidity >= 0 && humidity <= 100)
        }
        
        // Verify we got a response entry
        if case .response = entry {
            print("✅ Successfully generated structured response with explicit schema")
        } else {
            Issue.record("Expected response entry")
        }
    }
    
    @Test("Real Ollama API call with ResponseFormat")
    func testRealOllamaWithResponseFormat() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create session
        let session = LanguageModelSession(
            model: model,
            instructions: "You are a weather assistant. Always provide accurate weather information in the requested format."
        )
        
        // Request with structured output
        let response = try await session.respond(
            to: "What's the weather like today in Tokyo?",
            generating: WeatherResponse.self,
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("\n=== Structured Response ===")
        print("Temperature: \(response.content.temperature)°C")
        print("Condition: \(response.content.condition)")
        if let humidity = response.content.humidity {
            print("Humidity: \(humidity)%")
        }
        
        // Verify response matches schema constraints
        #expect(response.content.temperature >= -50 && response.content.temperature <= 50)
        #expect(["sunny", "cloudy", "rainy", "snowy"].contains(response.content.condition))
        if let humidity = response.content.humidity {
            #expect(humidity >= 0 && humidity <= 100)
        }
    }
    
    @Test("Complex nested structure with ResponseFormat")
    func testComplexNestedStructure() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Use the TodoList type which has nested TodoItem
        // Create transcript with complex schema
        var transcript = Transcript()
        transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Create a todo list with 3 tasks for building a website."))],
                responseFormat: Transcript.ResponseFormat(type: TodoList.self)
            ))
        ])
        
        // Extract and verify schema
        let format = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
        
        if case .jsonSchema(let schema) = format {
            print("\n=== Complex Nested Schema (TodoList) ===")
            if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
            
            // Verify nested structure
            #expect(schema["type"] as? String == "object")
            if let properties = schema["properties"] as? [String: Any],
               let todosProperty = properties["todos"] as? [String: Any] {
                #expect(todosProperty["type"] as? String == "array")
                // Check if items schema is present (nested TodoItem structure)
                #expect(todosProperty["items"] != nil)
            }
        }
        
        // Test with actual API
        let response = try await model.generate(transcript: transcript, options: nil)
        
        if case .response(let resp) = response {
            print("\n=== Generated Complex Structure ===")
            print("Response: \(resp.segments.map { $0.description }.joined())")
        }
    }
    
    @Test("Fallback behavior when no ResponseFormat")
    func testFallbackWithoutResponseFormat() throws {
        // Create transcript without ResponseFormat
        var transcript = Transcript()
        transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Hello"))],
                options: GenerationOptions()
                // No responseFormat
            ))
        ])
        
        // Should return nil for both methods
        let schemaFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
        let simpleFormat = TranscriptConverter.extractResponseFormat(from: transcript)
        
        #expect(schemaFormat == nil)
        #expect(simpleFormat == nil)
    }
}

// MARK: - Test Skip Helper
extension ResponseFormatTests {
    struct TestSkip: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}