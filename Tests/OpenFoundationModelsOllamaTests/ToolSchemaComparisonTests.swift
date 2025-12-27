import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Tool Schema Comparison Tests", .serialized)
struct ToolSchemaComparisonTests {
    
    @Test("Compare simple vs DynamicGenerationSchema approaches")
    func testCompareApproaches() throws {
        print("\n=== Comparing Tool Schema Approaches ===\n")
        
        // Approach 1: Simple GenerationSchema with String type
        print("1. Simple Approach (for prototyping):")
        let simpleTool = ToolSchemaHelper.createSimpleTool(
            name: "get_data",
            description: "Get some data"
        )
        
        let transcript1 = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [simpleTool]
            ))
        ])
        
        let simpleTools = try TranscriptConverter.extractTools(from: transcript1)
        if let tool = simpleTools?.first {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            print(jsonString)
            print("\nCharacteristics:")
            print("- Quick to implement")
            print("- No property definitions")
            print("- Parameters type: \(tool.function.parameters.type)")
            print("- Good for: Prototyping, simple tools")
        }
        
        // Approach 2: DynamicGenerationSchema
        print("\n2. DynamicGenerationSchema Approach (for production):")
        let dynamicTool = try ToolSchemaHelper.createToolWithDynamicSchema(
            name: "get_data",
            description: "Get some data",
            properties: [
                (name: "id", type: "string", description: "Data ID", isOptional: false),
                (name: "format", type: "string", description: "Response format", isOptional: true),
                (name: "include_metadata", type: "boolean", description: "Include metadata", isOptional: true)
            ]
        )
        
        let transcript2 = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-2",
                segments: [],
                toolDefinitions: [dynamicTool]
            ))
        ])
        
        let dynamicTools = try TranscriptConverter.extractTools(from: transcript2)
        if let tool = dynamicTools?.first {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            print(jsonString)
            print("\nCharacteristics:")
            print("- Rich property definitions")
            print("- Type safety")
            print("- Parameters type: \(tool.function.parameters.type)")
            print("- Good for: Production, complex tools, strict validation")
        }
        
        print("\n=== End Comparison ===\n")
    }
    
    @Test("Weather tool comparison")
    func testWeatherToolComparison() throws {
        print("\n=== Weather Tool Comparison ===\n")
        
        // Simple version
        print("1. Simple Weather Tool:")
        let simpleWeather = ToolSchemaHelper.createSimpleTool(
            name: "get_weather",
            description: "Get weather information"
        )
        
        let transcript1 = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [simpleWeather]
            ))
        ])
        
        let simpleTools = try TranscriptConverter.extractTools(from: transcript1)
        if let tool = simpleTools?.first {
            print("- Name: \(tool.function.name)")
            print("- Parameters type: \(tool.function.parameters.type)")
            print("- Properties count: \(tool.function.parameters.properties.count)")
        }
        
        // DynamicGenerationSchema version
        print("\n2. Dynamic Weather Tool:")
        let dynamicWeather = try ToolSchemaHelper.createWeatherTool()
        
        let transcript2 = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-2",
                segments: [],
                toolDefinitions: [dynamicWeather]
            ))
        ])
        
        let dynamicTools = try TranscriptConverter.extractTools(from: transcript2)
        if let tool = dynamicTools?.first {
            print("- Name: \(tool.function.name)")
            print("- Parameters type: \(tool.function.parameters.type)")
            print("- Properties count: \(tool.function.parameters.properties.count)")
            
            // Show the full JSON for comparison
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(tool)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            print("\nFull Dynamic Tool JSON:")
            print(jsonString)
        }
        
        print("\n=== End Weather Tool Comparison ===\n")
    }
    
    @Test("Performance characteristics")
    func testPerformanceCharacteristics() throws {
        print("\n=== Performance Characteristics ===\n")
        
        print("Simple GenerationSchema:")
        print("- Creation time: Minimal")
        print("- Memory footprint: Small")
        print("- JSON encoding: Fast")
        print("- Flexibility: Limited")
        print("- Type information: Minimal")
        
        print("\nDynamicGenerationSchema:")
        print("- Creation time: Slightly higher")
        print("- Memory footprint: Larger (stores full schema)")
        print("- JSON encoding: More complex")
        print("- Flexibility: High")
        print("- Type information: Complete")
        
        print("\nRecommendations:")
        print("- Use Simple for: Quick prototypes, testing, simple tools")
        print("- Use Dynamic for: Production, complex tools, when type safety matters")
        print("- Use Dynamic for: Tools with nested objects, arrays, enums")
        print("- Use Simple for: Tools with basic string parameters")
        
        print("\n=== End Performance Characteristics ===\n")
    }
    
    @Test("Migration path example")
    func testMigrationPath() throws {
        print("\n=== Migration Path Example ===\n")
        
        // Start with simple
        print("Step 1: Start with simple schema for prototyping")
        let v1Tool = ToolSchemaHelper.createSimpleTool(
            name: "search",
            description: "Search for items"
        )
        print("- Created simple tool: \(v1Tool.name)")
        
        // Migrate to dynamic
        print("\nStep 2: Migrate to DynamicGenerationSchema for production")
        let v2Tool = try ToolSchemaHelper.createToolWithDynamicSchema(
            name: "search",
            description: "Search for items",
            properties: [
                (name: "query", type: "string", description: "Search query", isOptional: false),
                (name: "category", type: "string", description: "Category filter", isOptional: true),
                (name: "max_results", type: "integer", description: "Maximum results", isOptional: true),
                (name: "sort_by", type: "string", description: "Sort order", isOptional: true)
            ]
        )
        print("- Created dynamic tool: \(v2Tool.name)")
        print("- Added property definitions")
        print("- Added type information")
        print("- Added optional/required constraints")
        
        print("\nBenefits of migration:")
        print("- Better documentation")
        print("- Type safety")
        print("- Validation")
        print("- Better LLM understanding")
        
        print("\n=== End Migration Path ===\n")
    }
}