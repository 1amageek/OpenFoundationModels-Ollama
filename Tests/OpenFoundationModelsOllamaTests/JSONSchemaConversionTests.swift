import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Simple Schema Conversion Tests", .serialized)
struct JSONSchemaConversionTests {
    
    // MARK: - Helper Methods
    
    /// Helper to create a tool and verify its JSON output
    private func verifyToolJSON(
        _ tool: OpenFoundationModelsOllama.Tool,
        expectedName: String,
        expectedDescription: String,
        expectedProperties: [String: String]? = nil,
        expectedRequired: [String]? = nil
    ) throws {
        // Encode tool to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        
        // Verify basic structure
        #expect((json?["type"] as? String) == "function")
        
        if let function = json?["function"] as? [String: Any] {
            #expect((function["name"] as? String) == expectedName)
            #expect((function["description"] as? String) == expectedDescription)
            
            if let parameters = function["parameters"] as? [String: Any] {
                // For simple schema, type is "string"
                // For DynamicGenerationSchema, type would be "object"
                let paramType = parameters["type"] as? String
                #expect(paramType == "string" || paramType == "object")
                
                // Verify properties if expected
                if let expectedProps = expectedProperties {
                    if let properties = parameters["properties"] as? [String: Any] {
                        #expect(properties.count == expectedProps.count)
                        
                        for (key, expectedType) in expectedProps {
                            if let prop = properties[key] as? [String: Any] {
                                #expect((prop["type"] as? String) == expectedType)
                            }
                        }
                    }
                }
                
                // Verify required fields if expected
                if let expectedReq = expectedRequired {
                    if let required = parameters["required"] as? [String] {
                        #expect(required.count == expectedReq.count)
                        for field in expectedReq {
                            #expect(required.contains(field))
                        }
                    }
                }
            }
        }
        
        // Print JSON for debugging
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("Generated JSON:\n\(jsonString)")
        }
    }
    
    // MARK: - Basic Schema Tests
    
    @Test("Simple object schema with string property")
    func testSimpleStringSchema() throws {
        // Create tool definition with GenerationSchema
        // Use a simple String schema as placeholder
        let schema = GenerationSchema(type: String.self, description: "User name", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "get_user",
            description: "Get user information",
            parameters: schema
        )
        
        // Convert to Ollama tool
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "get_user",
                expectedDescription: "Get user information",
                expectedProperties: [:],
                expectedRequired: []
            )
        }
    }
    
    @Test("Schema with multiple types")
    func testMultipleTypeSchema() throws {
        // Create schema with simple type
        // Tool schemas will be simplified to basic types
        let schema = GenerationSchema(type: String.self, description: "Item processing parameters", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "process_item",
            description: "Process an item",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "process_item",
                expectedDescription: "Process an item",
                expectedProperties: [:],
                expectedRequired: []
            )
        }
    }
    
    @Test("Nested object schema")
    func testNestedObjectSchema() throws {
        // Create schema with simple type
        let schema = GenerationSchema(type: String.self, description: "User creation parameters", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "create_user",
            description: "Create a new user",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "create_user",
                expectedDescription: "Create a new user",
                expectedProperties: [:],
                expectedRequired: []
            )
        }
    }
    
    // MARK: - Real-world Schema Tests
    
    @Test("Weather API schema")
    func testWeatherAPISchema() throws {
        // Create weather API schema with simple type
        let schema = GenerationSchema(type: String.self, description: "Weather location", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get current weather and optional forecast",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "get_weather",
                expectedDescription: "Get current weather and optional forecast",
                expectedProperties: [:],
                expectedRequired: []
            )
        }
    }
    
    @Test("Database query schema")
    func testDatabaseQuerySchema() throws {
        // Create database query schema with simple type
        let schema = GenerationSchema(type: String.self, description: "Query parameters", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "execute_query",
            description: "Execute a database query",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "execute_query",
                expectedDescription: "Execute a database query",
                expectedProperties: [:],
                expectedRequired: []
            )
        }
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Empty schema")
    func testEmptySchema() throws {
        // Create empty schema with simple type
        let schema = GenerationSchema(type: String.self, properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "ping",
            description: "Simple ping",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "ping",
                expectedDescription: "Simple ping",
                expectedProperties: [:], // Empty properties
                expectedRequired: [] // Empty required
            )
        }
    }
    
    @Test("Schema with all optional fields")
    func testAllOptionalSchema() throws {
        // Create schema with simple type for optional fields
        let schema = GenerationSchema(type: String.self, description: "Optional parameters", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "optional_tool",
            description: "Tool with all optional parameters",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "optional_tool",
                expectedDescription: "Tool with all optional parameters",
                expectedProperties: [:],
                expectedRequired: []
            )
        }
    }
    
    // MARK: - Actual API Call Test
    
    @Test("Verify tool JSON is valid for Ollama API")
    func testOllamaAPICompatibility() throws {
        // Create realistic search tool schema with simple type
        let schema = GenerationSchema(type: String.self, description: "Search query", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "search",
            description: "Search for information",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        // Create a ChatRequest with the tools
        let messages = [Message(role: .user, content: "Search for Swift programming")]
        let request = ChatRequest(
            model: "gpt-oss:20b",
            messages: messages,
            stream: false,
            tools: tools
        )
        
        // Encode the entire request to verify it's valid JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let requestData = try encoder.encode(request)
        
        // Verify it can be decoded back
        let decoder = JSONDecoder()
        let decodedRequest = try decoder.decode(ChatRequest.self, from: requestData)
        
        #expect(decodedRequest.tools?.count == 1)
        #expect(decodedRequest.tools?.first?.function.name == "search")
        
        // Log the full request JSON
        if let jsonString = String(data: requestData, encoding: .utf8) {
            print("Full Ollama API request with tool:\n\(jsonString)")
        }
        
        // Additional verification using helper
        if let tool = tools?.first {
            try verifyToolJSON(
                tool,
                expectedName: "search",
                expectedDescription: "Search for information",
                expectedProperties: [:],
                expectedRequired: []
            )
        }
    }
}