import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Tool Definition Builder Tests")
struct ToolDefinitionBuilderTests {
    
    // Clean up registry before each test
    init() {
        ToolSchemaRegistry.shared.clear()
    }
    
    @Test("Create tool with explicit properties")
    func testCreateToolWithProperties() throws {
        // Clear registry to start clean
        ToolSchemaRegistry.shared.clear()
        // Create a tool using the builder
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "get_weather",
            description: "Get weather information for a location",
            properties: [
                "location": .string("The city name"),
                "unit": .enumeration("Temperature unit", values: ["celsius", "fahrenheit"]),
                "include_forecast": .boolean("Include 5-day forecast")
            ],
            required: ["location"]
        )
        
        // Verify tool definition
        #expect(toolDef.name == "get_weather")
        #expect(toolDef.description == "Get weather information for a location")
        
        // Create a transcript and extract tools
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        
        if let tool = tools?.first {
            let params = tool.function.parameters
            #expect(params.type == "object")
            #expect(params.properties.count == 3)
            #expect(params.required.count == 1)
            #expect(params.required.contains("location"))
            
            // Verify properties
            #expect(params.properties["location"]?.type == "string")
            #expect(params.properties["unit"]?.type == "string") 
            #expect(params.properties["include_forecast"]?.type == "boolean")
            
            // Encode and verify JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            print("Weather tool JSON:")
            print(jsonString)
            
            // Verify JSON structure
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            let function = json?["function"] as? [String: Any]
            let parameters = function?["parameters"] as? [String: Any]
            let properties = parameters?["properties"] as? [String: Any]
            
            #expect(properties?.count == 3)
            #expect((parameters?["required"] as? [String])?.contains("location") == true)
        }
    }
    
    @Test("Create simple tool with no parameters")
    func testCreateSimpleTool() throws {
        ToolSchemaRegistry.shared.clear()
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "ping",
            description: "Simple ping tool"
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
            #expect(tool.function.name == "ping")
            #expect(tool.function.parameters.properties.isEmpty)
            #expect(tool.function.parameters.required.isEmpty)
        }
    }
    
    @Test("Multiple tools with different schemas")
    func testMultipleToolsWithSchemas() throws {
        // Clear registry to avoid interference from other tests
        ToolSchemaRegistry.shared.clear()
        let weatherTool = ToolDefinitionBuilder.createTool(
            name: "get_weather",
            description: "Get weather info",
            properties: [
                "city": .string("City name")
            ],
            required: ["city"]
        )
        
        let searchTool = ToolDefinitionBuilder.createTool(
            name: "search_web",
            description: "Search the web",
            properties: [
                "query": .string("Search query"),
                "max_results": .integer("Maximum results"),
                "safe_search": .boolean("Enable safe search")
            ],
            required: ["query"]
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [weatherTool, searchTool]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 2)
        
        // Find weather tool
        let weatherOllamaTool = tools?.first { $0.function.name == "get_weather" }
        #expect(weatherOllamaTool?.function.parameters.properties.count == 1)
        #expect(weatherOllamaTool?.function.parameters.required.contains("city") == true)
        
        // Find search tool
        let searchOllamaTool = tools?.first { $0.function.name == "search_web" }
        #expect(searchOllamaTool?.function.parameters.properties.count == 3)
        #expect(searchOllamaTool?.function.parameters.required.contains("query") == true)
    }
    
    @Test("Property definition convenience methods")
    func testPropertyDefinitionMethods() {
        let stringProp = ToolDefinitionBuilder.PropertyDefinition.string("A string property")
        #expect(stringProp.type == "string")
        #expect(stringProp.description == "A string property")
        #expect(stringProp.enumValues == nil)
        
        let enumProp = ToolDefinitionBuilder.PropertyDefinition.enumeration("Status", values: ["active", "inactive"])
        #expect(enumProp.type == "string")
        #expect(enumProp.enumValues?.count == 2)
        
        let intProp = ToolDefinitionBuilder.PropertyDefinition.integer("An integer")
        #expect(intProp.type == "integer")
        
        let boolProp = ToolDefinitionBuilder.PropertyDefinition.boolean("A boolean")
        #expect(boolProp.type == "boolean")
    }
    
    @Test("Registry isolation between tests")
    func testRegistryIsolation() throws {
        // This test should not see tools from other tests
        ToolSchemaRegistry.shared.clear()
        
        let toolDef = ToolDefinitionBuilder.createTool(
            name: "isolated_tool",
            description: "Test tool",
            properties: ["param": .string("Test param")],
            required: ["param"]
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        #expect(tools?.first?.function.parameters.properties.count == 1)
    }
}