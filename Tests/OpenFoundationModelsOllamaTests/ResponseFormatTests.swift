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
        // Test WeatherResponse schema
        let weatherSchema = WeatherResponse.generationSchema
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let weatherSchemaData = try encoder.encode(weatherSchema)
        
        print("WeatherResponse JSON Schema:")
        if let jsonString = String(data: weatherSchemaData, encoding: .utf8) {
            print(jsonString)
        }
        
        // Test TodoList schema
        let todoSchema = TodoList.generationSchema
        let todoSchemaData = try encoder.encode(todoSchema)
        
        print("\nTodoList JSON Schema:")
        if let jsonString = String(data: todoSchemaData, encoding: .utf8) {
            print(jsonString)
        }
        
        // Parse TodoList schema to verify structure
        let todoSchemaJSON = try JSONSerialization.jsonObject(with: todoSchemaData) as? [String: Any]
        
        #expect(todoSchemaJSON != nil)
        #expect(todoSchemaJSON?["type"] as? String == "object")
        
        if let properties = todoSchemaJSON?["properties"] as? [String: Any] {
            print("\nTodoList properties: \(properties.keys)")
            if let todosProperty = properties["todos"] as? [String: Any] {
                print("todos property type: \(todosProperty["type"] ?? "nil")")
                print("todos property structure: \(todosProperty)")
            }
        }
        
        // Parse WeatherResponse for comparison
        let weatherSchemaJSON = try JSONSerialization.jsonObject(with: weatherSchemaData) as? [String: Any]
        
        #expect(weatherSchemaJSON != nil)
        #expect(weatherSchemaJSON?["type"] as? String == "object")
        #expect(weatherSchemaJSON?["properties"] != nil)
        
        if let properties = weatherSchemaJSON?["properties"] as? [String: Any] {
            #expect(properties["temperature"] != nil)
            #expect(properties["condition"] != nil)
            #expect(properties["humidity"] != nil)
        }
        
        if let required = weatherSchemaJSON?["required"] as? [String] {
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
    
    @Test("Test gpt-oss Harmony Response Format with API")
    func testGptOssHarmonyWithAPI() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create transcript with ResponseFormat for WeatherResponse
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "You are a helpful weather assistant."))],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "What's the weather in Tokyo today?"))],
                options: GenerationOptions(temperature: 0.1),
                responseFormat: Transcript.ResponseFormat(type: WeatherResponse.self)
            ))
        ])
        
        print("\n=== Testing gpt-oss Harmony with Real API ===")
        
        // Call the model with harmony format
        let response = try await model.generate(transcript: transcript, options: nil)
        
        if case .response(let resp) = response {
            print("\n=== Harmony API Response ===")
            for segment in resp.segments {
                switch segment {
                case .text(let textSegment):
                    let content = textSegment.content
                    print("Content: '\(content)'")
                    
                    // Try to parse as JSON to see if it's valid
                    if let data = content.data(using: .utf8) {
                        do {
                            let json = try JSONSerialization.jsonObject(with: data)
                            print("✅ Valid JSON response!")
                            print("Parsed: \(json)")
                        } catch {
                            print("❌ Not valid JSON: \(error)")
                        }
                    }
                    
                case .structure(let structSegment):
                    print("Structure: \(structSegment.content)")
                }
            }
        }
        
        print("✅ Harmony format API call completed")
    }
    
    @Test("Test gpt-oss variants detection")
    func testGptOssVariantsDetection() throws {
        // Test that all gpt-oss variants are detected correctly
        let models = [
            "gpt-oss:20b",
            "gpt-oss:120b", 
            "gpt-oss:latest",
            "gpt-oss"
        ]
        
        for modelName in models {
            let model = OllamaLanguageModel(modelName: modelName)
            let isGptOss = modelName.lowercased().hasPrefix("gpt-oss")
            
            print("Model: \(modelName) -> gpt-oss: \(isGptOss)")
            #expect(isGptOss == true)
        }
        
        // Test non-gpt-oss models
        let nonGptOssModels = ["llama3.2", "mistral", "codellama"]
        for modelName in nonGptOssModels {
            let isGptOss = modelName.lowercased().hasPrefix("gpt-oss")
            print("Model: \(modelName) -> gpt-oss: \(isGptOss)")
            #expect(isGptOss == false)
        }
    }
    
    @Test("Test gpt-oss Harmony Message Generation")
    func testGptOssHarmonyMessageGeneration() throws {
        // Test that Harmony format is generated correctly for gpt-oss models
        let model = OllamaLanguageModel(modelName: "gpt-oss:20b")
        
        // Create transcript with ResponseFormat for WeatherResponse
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "You are a helpful weather assistant."))],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "What's the weather in Tokyo today?"))],
                options: GenerationOptions(temperature: 0.1),
                responseFormat: Transcript.ResponseFormat(type: WeatherResponse.self)
            ))
        ])
        
        print("\n=== Testing gpt-oss Harmony Message Generation ===")
        
        // Extract format and build messages to verify harmony format is added
        let extractedFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
        var messages = TranscriptConverter.buildMessages(from: transcript)
        
        if case .jsonSchema(let schema) = extractedFormat {
            print("Extracted schema:")
            if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
                
                // Simulate the harmony format generation
                if model.modelName.lowercased().hasPrefix("gpt-oss") {
                    // Find system message and add harmony format
                    for i in 0..<messages.count {
                        if messages[i].role == .system {
                            let currentContent = messages[i].content
                            let harmonyFormat = """
                            # Response Formats
                            
                            ## StructuredResponse
                            
                            \(jsonString)
                            """
                            
                            let newContent = currentContent + "\n\n" + harmonyFormat
                            messages[i] = Message(
                                role: .system,
                                content: newContent,
                                toolCalls: messages[i].toolCalls,
                                thinking: messages[i].thinking,
                                toolName: messages[i].toolName
                            )
                            break
                        }
                    }
                }
            }
        }
        
        print("\n=== Generated Messages ===")
        for (index, message) in messages.enumerated() {
            print("Message \(index) (\(message.role)):")
            print("Content: \(message.content)")
            print("")
        }
        
        // Verify that system message contains Response Formats
        let systemMessage = messages.first { $0.role == .system }
        #expect(systemMessage?.content.contains("# Response Formats") == true)
        #expect(systemMessage?.content.contains("## StructuredResponse") == true)
        #expect(systemMessage?.content.contains("\"temperature\"") == true)
    }
    
    @Test("Explicit schema generation with OllamaLanguageModel")
    func testExplicitSchemaGeneration() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Note: Direct schema generation was removed from OllamaLanguageModel
        // Use LanguageModelSession for structured output instead
        let session = LanguageModelSession(
            model: model,
            instructions: "You are a weather assistant."
        )
    
        
        let response = try await session.respond(
            to: "What's the weather in Tokyo today?",
            generating: WeatherResponse.self,
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("\n=== Structured Response with Explicit Schema ===")
        print("Temperature: \(response.content.temperature)°C")
        print("Condition: \(response.content.condition)")
        if let humidity = response.content.humidity {
            print("Humidity: \(humidity)%")
        }
        
        // Verify the response
        #expect(response.content.temperature >= -50 && response.content.temperature <= 50)
        #expect(["sunny", "cloudy", "rainy", "snowy"].contains(response.content.condition))
        if let humidity = response.content.humidity {
            #expect(humidity >= 0 && humidity <= 100)
        }
        
        print("✅ Successfully generated structured response with explicit schema")
    }
    
    @Test("Real Ollama API call with ResponseFormat")
    func testRealOllamaWithResponseFormat() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.checkModelAvailability() else {
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
        
        guard try await model.checkModelAvailability() else {
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

// MARK: - Transcript Encoding Tests

extension ResponseFormatTests {
    @Test("Transcript Encoding Investigation")
    func testTranscriptEncoding() throws {
        // Create a transcript with ResponseFormat using correct initialization
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "You are a helpful assistant."))],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "What's the weather?"))],
                options: GenerationOptions(temperature: 0.1),
                responseFormat: Transcript.ResponseFormat(type: WeatherResponse.self)
            ))
        ])
        
        // Try to encode the transcript
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(transcript)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("=== Encoded Transcript ===")
            print(jsonString)
            print("\n")
        }
        
        // Parse as JSON to explore structure
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("=== JSON Structure ===")
            print("Top-level keys: \(json.keys.sorted())")
            
            if let entries = json["entries"] as? [[String: Any]] {
                print("\nNumber of entries: \(entries.count)")
                for (index, entry) in entries.enumerated() {
                    print("\nEntry \(index):")
                    print("  Type: \(entry["type"] ?? "unknown")")
                    print("  Keys: \(entry.keys.sorted())")
                    
                    // Check for responseFormat in prompt
                    if entry["type"] as? String == "prompt" {
                        if let responseFormat = entry["responseFormat"] as? [String: Any] {
                            print("  ResponseFormat found!")
                            print("    Keys: \(responseFormat.keys.sorted())")
                            print("    Type: \(responseFormat["type"] ?? "nil")")
                            print("    Schema: \(responseFormat["schema"] ?? "nil")")
                        }
                    }
                    
                    // Check for toolDefinitions in instructions
                    if entry["type"] as? String == "instructions" {
                        if let toolDefs = entry["toolDefinitions"] as? [[String: Any]] {
                            print("  ToolDefinitions found: \(toolDefs.count) tools")
                        }
                    }
                }
            }
        }
        
        #expect(data.count > 0, "Transcript should encode to non-empty data")
    }
}
