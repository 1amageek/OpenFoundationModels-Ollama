import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
@testable import OpenFoundationModelsCore

@Suite("JSON Schema Conversion Tests")
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
        // Create a simple schema with one string property
        let schema = GenerationSchema(
            type: "object",
            description: "User information",
            properties: [
                "name": GenerationSchema(
                    type: "string",
                    description: "The user's name"
                )
            ],
            required: ["name"]
        )
        
        // Create tool definition
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
                expectedProperties: ["name": "string"],
                expectedRequired: ["name"]
            )
        }
    }
    
    @Test("Schema with multiple types")
    func testMultipleTypeSchema() throws {
        // Create schema with various property types
        let schema = GenerationSchema(
            type: "object",
            description: "Complex parameters",
            properties: [
                "count": GenerationSchema(type: "integer", description: "Item count"),
                "price": GenerationSchema(type: "number", description: "Item price"),
                "active": GenerationSchema(type: "boolean", description: "Is active"),
                "tags": GenerationSchema(type: "array", description: "Tags list")
            ],
            required: ["count", "price"]
        )
        
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
        // Create nested schema structure
        let addressSchema = GenerationSchema(
            type: "object",
            description: "Address",
            properties: [
                "street": GenerationSchema(type: "string", description: "Street address"),
                "city": GenerationSchema(type: "string", description: "City"),
                "zipcode": GenerationSchema(type: "string", description: "ZIP code")
            ],
            required: ["street", "city"]
        )
        
        let schema = GenerationSchema(
            type: "object",
            description: "User with address",
            properties: [
                "name": GenerationSchema(type: "string", description: "Name"),
                "age": GenerationSchema(type: "integer", description: "Age"),
                "address": addressSchema
            ],
            required: ["name", "address"]
        )
        
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
        
        // The conversion might flatten or simplify nested structures
        // We'll check what we can access
        if let tool = tools?.first {
            #expect(tool.function.name == "create_user")
            #expect(tool.function.parameters.type == "object")
            
            // Log the actual JSON for inspection
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Nested schema JSON:\n\(jsonString)")
            }
        }
    }
    
    // MARK: - Real-world Schema Tests
    
    @Test("Weather API schema")
    func testWeatherAPISchema() throws {
        let schema = GenerationSchema(
            type: "object",
            description: "Weather query parameters",
            properties: [
                "location": GenerationSchema(
                    type: "string",
                    description: "City, state, or coordinates"
                ),
                "unit": GenerationSchema(
                    type: "string",
                    description: "Temperature unit"
                ),
                "include_forecast": GenerationSchema(
                    type: "boolean",
                    description: "Include 5-day forecast"
                )
            ],
            required: ["location"]
        )
        
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
        let tool = tools?.first
        
        #expect(tool?.function.name == "get_weather")
        
        // Encode and verify the JSON structure
        if let tool = tool {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            
            // Check that it produces valid Ollama API format
            let function = json?["function"] as? [String: Any]
            let parameters = function?["parameters"] as? [String: Any]
            
            #expect(parameters?["type"] as? String == "object")
            
            // Log for manual verification
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Weather API tool JSON:\n\(jsonString)")
            }
        }
    }
    
    @Test("Database query schema")
    func testDatabaseQuerySchema() throws {
        let schema = GenerationSchema(
            type: "object",
            description: "Database query parameters",
            properties: [
                "table": GenerationSchema(
                    type: "string",
                    description: "Table name"
                ),
                "columns": GenerationSchema(
                    type: "array",
                    description: "Columns to select"
                ),
                "conditions": GenerationSchema(
                    type: "object",
                    description: "WHERE conditions",
                    properties: [
                        "field": GenerationSchema(type: "string"),
                        "operator": GenerationSchema(
                            type: "string"
                        ),
                        "value": GenerationSchema(type: "string")
                    ]
                ),
                "limit": GenerationSchema(
                    type: "integer",
                    description: "Maximum rows to return"
                )
            ],
            required: ["table"]
        )
        
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
        #expect(tools?.first?.function.name == "execute_query")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Empty schema")
    func testEmptySchema() throws {
        let schema = GenerationSchema(
            type: "object",
            description: "No parameters"
        )
        
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
        let tool = tools?.first
        
        #expect(tool?.function.name == "ping")
        #expect(tool?.function.parameters.type == "object")
        #expect(tool?.function.parameters.properties.isEmpty == true)
        #expect(tool?.function.parameters.required.isEmpty == true)
    }
    
    @Test("Schema with all optional fields")
    func testAllOptionalSchema() throws {
        let schema = GenerationSchema(
            type: "object",
            description: "All optional",
            properties: [
                "option1": GenerationSchema(type: "string"),
                "option2": GenerationSchema(type: "number"),
                "option3": GenerationSchema(type: "boolean")
            ]
            // No required fields
        )
        
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
        let tool = tools?.first
        
        #expect(tool?.function.parameters.required.isEmpty == true)
    }
    
    // MARK: - Actual API Call Test
    
    @Test("Verify tool JSON is valid for Ollama API")
    func testOllamaAPICompatibility() throws {
        // Create a realistic tool definition
        let schema = GenerationSchema(
            type: "object",
            description: "Search parameters",
            properties: [
                "query": GenerationSchema(
                    type: "string",
                    description: "Search query"
                ),
                "max_results": GenerationSchema(
                    type: "integer",
                    description: "Maximum number of results"
                ),
                "filters": GenerationSchema(
                    type: "object",
                    description: "Search filters",
                    properties: [
                        "category": GenerationSchema(type: "string"),
                        "date_from": GenerationSchema(type: "string"),
                        "date_to": GenerationSchema(type: "string")
                    ]
                )
            ],
            required: ["query"]
        )
        
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
    }
}