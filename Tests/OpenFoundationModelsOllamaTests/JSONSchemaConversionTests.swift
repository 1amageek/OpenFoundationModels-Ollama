import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
@testable import OpenFoundationModelsCore

@Suite("JSON Schema Conversion Tests", .serialized)
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
                #expect((parameters["type"] as? String) == "object")
                
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
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder instead of GenerationSchema directly
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "get_user",
            description: "Get user information",
            properties: [
                "name": .string("The user's name")
            ],
            required: ["name"]
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
                expectedProperties: ["name": "string"],
                expectedRequired: ["name"]
            )
        }
    }
    
    @Test("Schema with multiple types")
    func testMultipleTypeSchema() throws {
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder with various property types
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "process_item",
            description: "Process an item",
            properties: [
                "count": .integer("Item count"),
                "price": .number("Item price"),
                "active": .boolean("Is active"),
                "tags": .array("Tags list")
            ],
            required: ["count", "price"]
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
                expectedProperties: [
                    "count": "integer",
                    "price": "number",
                    "active": "boolean",
                    "tags": "array"
                ],
                expectedRequired: ["count", "price"]
            )
        }
    }
    
    @Test("Nested object schema")
    func testNestedObjectSchema() throws {
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder for nested object structure
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "create_user",
            description: "Create a new user",
            properties: [
                "name": .string("User's full name"),
                "age": .integer("User's age"),
                "address": .string("User's address (as JSON string)") // Simplified for now
            ],
            required: ["name", "address"]
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
                expectedProperties: [
                    "name": "string",
                    "age": "integer",
                    "address": "string"
                ],
                expectedRequired: ["name", "address"]
            )
        }
    }
    
    // MARK: - Real-world Schema Tests
    
    @Test("Weather API schema")
    func testWeatherAPISchema() throws {
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder for weather API
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "get_weather",
            description: "Get current weather and optional forecast",
            properties: [
                "location": .string("City, state, or coordinates"),
                "unit": .enumeration("Temperature unit", values: ["celsius", "fahrenheit"]),
                "include_forecast": .boolean("Include 5-day forecast")
            ],
            required: ["location"]
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
                expectedProperties: [
                    "location": "string",
                    "unit": "string",
                    "include_forecast": "boolean"
                ],
                expectedRequired: ["location"]
            )
        }
    }
    
    @Test("Database query schema")
    func testDatabaseQuerySchema() throws {
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder for database query
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "execute_query",
            description: "Execute a database query",
            properties: [
                "table": .string("Table name"),
                "columns": .array("Columns to select"),
                "conditions": .string("WHERE conditions as JSON string"), // Simplified nested object
                "limit": .integer("Maximum rows to return")
            ],
            required: ["table"]
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
                expectedProperties: [
                    "table": "string",
                    "columns": "array",
                    "conditions": "string",
                    "limit": "integer"
                ],
                expectedRequired: ["table"]
            )
        }
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Empty schema")
    func testEmptySchema() throws {
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder with no properties
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "ping",
            description: "Simple ping"
            // No properties or required fields
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
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder with all optional fields (no required array)
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "optional_tool",
            description: "Tool with all optional parameters",
            properties: [
                "option1": .string("Optional string parameter"),
                "option2": .number("Optional number parameter"),
                "option3": .boolean("Optional boolean parameter")
            ]
            // No required fields specified
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
                expectedProperties: [
                    "option1": "string",
                    "option2": "number",
                    "option3": "boolean"
                ],
                expectedRequired: [] // No required fields
            )
        }
    }
    
    // MARK: - Actual API Call Test
    
    @Test("Verify tool JSON is valid for Ollama API")
    func testOllamaAPICompatibility() throws {
        // Clear registry for clean test
        ToolSchemaRegistry.shared.clear()
        
        // Use ToolDefinitionBuilder for realistic search tool
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "search",
            description: "Search for information",
            properties: [
                "query": .string("Search query"),
                "max_results": .integer("Maximum number of results"),
                "filters": .string("Search filters as JSON string") // Simplified nested object
            ],
            required: ["query"]
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
                expectedProperties: [
                    "query": "string",
                    "max_results": "integer",
                    "filters": "string"
                ],
                expectedRequired: ["query"]
            )
        }
    }
}