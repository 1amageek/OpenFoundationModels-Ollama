import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Rich Schema Conversion Tests with DynamicGenerationSchema", .serialized)
struct RichSchemaConversionTests {
    
    // MARK: - Helper Methods
    
    private func verifyRichToolJSON(
        _ tool: OpenFoundationModelsOllama.Tool,
        expectedName: String,
        expectedDescription: String
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
                // DynamicGenerationSchema should produce object type
                #expect((parameters["type"] as? String) == "object")
            }
        }
        
        // Print JSON for debugging
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("Generated Rich Schema JSON:\n\(jsonString)")
        }
    }
    
    @Test("Weather API with rich schema")
    func testWeatherAPIWithRichSchema() throws {
        let weatherTool = try ToolSchemaHelper.createWeatherTool()
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [weatherTool]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyRichToolJSON(
                tool,
                expectedName: "get_weather",
                expectedDescription: "Get current weather and optional forecast"
            )
        }
    }
    
    @Test("Calculator with rich schema")
    func testCalculatorWithRichSchema() throws {
        let calcTool = try ToolSchemaHelper.createCalculatorTool()
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [calcTool]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyRichToolJSON(
                tool,
                expectedName: "calculate",
                expectedDescription: "Perform mathematical calculations"
            )
        }
    }
    
    @Test("Search tool with rich schema")
    func testSearchToolWithRichSchema() throws {
        // Create a search tool with DynamicGenerationSchema
        let searchTool = try ToolSchemaHelper.createToolWithDynamicSchema(
            name: "search",
            description: "Search for information",
            properties: [
                (name: "query", type: "string", description: "Search query", isOptional: false),
                (name: "max_results", type: "integer", description: "Maximum number of results", isOptional: true),
                (name: "filters", type: "string", description: "Search filters", isOptional: true)
            ],
            required: ["query"]
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [searchTool]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyRichToolJSON(
                tool,
                expectedName: "search",
                expectedDescription: "Search for information"
            )
            
            // Verify it can be encoded for Ollama API
            let messages = [Message(role: .user, content: "Search for Swift")]
            let request = ChatRequest(
                model: "gpt-oss:20b",
                messages: messages,
                stream: false,
                tools: tools
            )
            
            let requestData = try JSONEncoder().encode(request)
            #expect(requestData.count > 0)
        }
    }
    
    @Test("Database query with rich schema")
    func testDatabaseQueryWithRichSchema() throws {
        // Create a database query tool
        let dbTool = try ToolSchemaHelper.createToolWithDynamicSchema(
            name: "execute_query",
            description: "Execute a database query",
            properties: [
                (name: "table", type: "string", description: "Table name", isOptional: false),
                (name: "columns", type: "string", description: "Columns to select (comma-separated)", isOptional: true),
                (name: "conditions", type: "string", description: "WHERE conditions", isOptional: true),
                (name: "limit", type: "integer", description: "Maximum rows", isOptional: true)
            ],
            required: ["table"]
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [dbTool]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            try verifyRichToolJSON(
                tool,
                expectedName: "execute_query",
                expectedDescription: "Execute a database query"
            )
        }
    }
    
    @Test("User creation with nested schema")
    func testUserCreationWithNestedSchema() throws {
        // Create address schema
        let addressProperties = [
            DynamicGenerationSchema.Property(
                name: "street",
                description: "Street address",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "city",
                description: "City",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "zipcode",
                description: "ZIP code",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            )
        ]
        
        let addressSchema = DynamicGenerationSchema(
            name: "Address",
            description: "User address",
            properties: addressProperties
        )
        
        // Create user schema with nested address
        let userProperties = [
            DynamicGenerationSchema.Property(
                name: "name",
                description: "User's full name",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "email",
                description: "User's email",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "age",
                description: "User's age",
                schema: DynamicGenerationSchema(type: Int.self),
                isOptional: true
            ),
            DynamicGenerationSchema.Property(
                name: "address",
                description: "User's address",
                schema: addressSchema,
                isOptional: true
            )
        ]
        
        let userSchema = DynamicGenerationSchema(
            name: "UserParameters",
            description: "User creation parameters",
            properties: userProperties
        )
        
        let schema = try GenerationSchema(root: userSchema, dependencies: [addressSchema])
        
        let toolDef = Transcript.ToolDefinition(
            name: "create_user",
            description: "Create a new user account",
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
            try verifyRichToolJSON(
                tool,
                expectedName: "create_user",
                expectedDescription: "Create a new user account"
            )
        }
    }
    
    @Test("Blog post with array schema")
    func testBlogPostWithArraySchema() throws {
        // Create schema for tags array
        let tagSchema = DynamicGenerationSchema(type: String.self)
        let tagsArraySchema = DynamicGenerationSchema(
            arrayOf: tagSchema,
            minimumElements: 1,
            maximumElements: 10
        )
        
        // Create category enum schema
        let categorySchema = DynamicGenerationSchema(
            name: "Category",
            anyOf: ["Technology", "Science", "Business", "Health", "Entertainment"]
        )
        
        // Create blog post schema
        let postProperties = [
            DynamicGenerationSchema.Property(
                name: "title",
                description: "Post title",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "content",
                description: "Post content",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "category",
                description: "Post category",
                schema: categorySchema,
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "tags",
                description: "Post tags",
                schema: tagsArraySchema,
                isOptional: true
            ),
            DynamicGenerationSchema.Property(
                name: "published",
                description: "Is published",
                schema: DynamicGenerationSchema(type: Bool.self),
                isOptional: true
            )
        ]
        
        let postSchema = DynamicGenerationSchema(
            name: "BlogPostParameters",
            description: "Blog post creation parameters",
            properties: postProperties
        )
        
        let schema = try GenerationSchema(root: postSchema, dependencies: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "create_blog_post",
            description: "Create a new blog post",
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
            try verifyRichToolJSON(
                tool,
                expectedName: "create_blog_post",
                expectedDescription: "Create a new blog post"
            )
            
            print("Blog post tool demonstrates:")
            print("- String fields (title, content)")
            print("- Enum field (category)")
            print("- Array field (tags)")
            print("- Boolean field (published)")
            print("- Required and optional fields")
        }
    }
}