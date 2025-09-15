import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("DynamicGenerationSchema Tool Tests", .serialized)
struct DynamicGenerationSchemaTests {
    
    @Test("Create tool with DynamicGenerationSchema")
    func testCreateToolWithDynamicSchema() throws {
        // Create a tool using DynamicGenerationSchema
        let tool = try ToolSchemaHelper.createToolWithDynamicSchema(
            name: "search",
            description: "Search for information",
            properties: [
                (name: "query", type: "string", description: "Search query", isOptional: false),
                (name: "max_results", type: "integer", description: "Maximum number of results", isOptional: true),
                (name: "include_images", type: "boolean", description: "Include image results", isOptional: true)
            ],
            required: ["query"]
        )
        
        #expect(tool.name == "search")
        #expect(tool.description == "Search for information")
        
        // Create transcript and extract tools
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [tool]
            ))
        ])
        
        let tools = try TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let extractedTool = tools?.first {
            // The tool should have proper structure
            #expect(extractedTool.type == "function")
            #expect(extractedTool.function.name == "search")
            
            // Encode to JSON and verify structure
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(extractedTool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            print("DynamicGenerationSchema tool JSON:")
            print(jsonString)
            
            // Verify JSON structure
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            let function = json?["function"] as? [String: Any]
            let parameters = function?["parameters"] as? [String: Any]
            
            #expect(parameters?["type"] != nil)
        }
    }
    
    @Test("Weather tool with DynamicGenerationSchema")
    func testWeatherToolWithDynamicSchema() throws {
        let weatherTool = try ToolSchemaHelper.createWeatherTool()
        
        #expect(weatherTool.name == "get_weather")
        #expect(weatherTool.description == "Get current weather and optional forecast")
        
        // Create transcript and extract
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [weatherTool]
            ))
        ])
        
        let tools = try TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            print("Weather tool JSON with DynamicGenerationSchema:")
            print(jsonString)
            
            // Verify the tool has the expected structure
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            let function = json?["function"] as? [String: Any]
            
            #expect(function?["name"] as? String == "get_weather")
            #expect(function?["description"] as? String == "Get current weather and optional forecast")
        }
    }
    
    @Test("Calculator tool with DynamicGenerationSchema")
    func testCalculatorToolWithDynamicSchema() throws {
        let calcTool = try ToolSchemaHelper.createCalculatorTool()
        
        #expect(calcTool.name == "calculate")
        #expect(calcTool.description == "Perform mathematical calculations")
        
        // Create transcript and extract
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [calcTool]
            ))
        ])
        
        let tools = try TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            print("Calculator tool JSON with DynamicGenerationSchema:")
            print(jsonString)
            
            // Verify structure
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            let function = json?["function"] as? [String: Any]
            
            #expect(function?["name"] as? String == "calculate")
        }
    }
    
    @Test("Complex nested schema with DynamicGenerationSchema")
    func testComplexNestedSchema() throws {
        // Create a complex nested schema
        let addressSchema = DynamicGenerationSchema(
            name: "Address",
            properties: [
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
                    name: "postal_code",
                    description: "Postal code",
                    schema: DynamicGenerationSchema(type: String.self),
                    isOptional: true
                )
            ]
        )
        
        let userSchema = DynamicGenerationSchema(
            name: "UserParameters",
            description: "User information parameters",
            properties: [
                DynamicGenerationSchema.Property(
                    name: "name",
                    description: "User's full name",
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
        )
        
        let schema = try GenerationSchema(root: userSchema, dependencies: [addressSchema])
        
        let toolDef = Transcript.ToolDefinition(
            name: "create_user",
            description: "Create a new user",
            parameters: schema
        )
        
        // Create transcript and extract
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [toolDef]
            ))
        ])
        
        let tools = try TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            print("Complex nested tool JSON:")
            print(jsonString)
            
            #expect(tool.function.name == "create_user")
        }
    }
    
    @Test("Array schema with DynamicGenerationSchema")
    func testArraySchema() throws {
        // Create an array schema
        let tagSchema = DynamicGenerationSchema(type: String.self)
        let tagsArraySchema = DynamicGenerationSchema(
            arrayOf: tagSchema,
            minimumElements: 1,
            maximumElements: 10
        )
        
        let postSchema = DynamicGenerationSchema(
            name: "BlogPostParameters",
            description: "Blog post parameters",
            properties: [
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
                    name: "tags",
                    description: "Post tags",
                    schema: tagsArraySchema,
                    isOptional: true
                )
            ]
        )
        
        let schema = try GenerationSchema(root: postSchema, dependencies: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "create_blog_post",
            description: "Create a new blog post",
            parameters: schema
        )
        
        // Create transcript and extract
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [toolDef]
            ))
        ])
        
        let tools = try TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            #expect(tool.function.name == "create_blog_post")
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            print("Array schema tool JSON:")
            print(jsonString)
        }
    }
}