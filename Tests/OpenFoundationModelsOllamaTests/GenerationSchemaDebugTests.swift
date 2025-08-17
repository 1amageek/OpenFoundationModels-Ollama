import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
@testable import OpenFoundationModelsCore

@Suite("GenerationSchema Debug Tests")
struct GenerationSchemaDebugTests {
    
    @Test("Debug GenerationSchema JSON encoding")
    func testGenerationSchemaEncoding() throws {
        // Create a simple schema with properties
        // Note: This test is checking JSON encoding behavior
        // We'll use the actual GenerationSchema API available
        let schema = GenerationSchema(type: String.self, description: "Test schema", properties: [])
        
        // Try to encode it to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let jsonData = try encoder.encode(schema)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "Failed to convert to string"
            print("GenerationSchema JSON:")
            print(jsonString)
            
            // Also try to decode it back
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("\nParsed JSON structure:")
                print("Type: \(json["type"] ?? "missing")")
                print("Description: \(json["description"] ?? "missing")")
                print("Properties: \(json["properties"] ?? "missing")")
                print("Required: \(json["required"] ?? "missing")")
                
                // Check if properties exist
                if let properties = json["properties"] as? [String: Any] {
                    print("Properties found: \(properties.keys)")
                    for (key, value) in properties {
                        print("  \(key): \(value)")
                    }
                }
                
                // Check required fields
                if let required = json["required"] as? [String] {
                    print("Required fields: \(required)")
                } else {
                    print("No required fields found")
                }
            }
        } catch {
            print("Failed to encode GenerationSchema: \(error)")
            
            // Let's try a different approach - see what properties are available
            print("\nGenerationSchema structure analysis:")
            print("Type: \(schema.type)")
            print("Description: \(schema.description ?? "nil")")
            
            // Try to access properties through reflection
            let mirror = Mirror(reflecting: schema)
            print("Mirror children:")
            for child in mirror.children {
                print("  \(child.label ?? "unlabeled"): \(child.value)")
            }
        }
    }
    
    @Test("Debug TranscriptConverter.convertSchemaToParameters")
    func testSchemaToParametersConversion() throws {
        let schema = GenerationSchema(type: String.self, description: "Weather parameters", properties: [])
        
        // Use a simple mechanism to call the internal method
        // We'll create a tool definition and extract it to see the result
        let toolDef = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get weather info",
            parameters: schema
        )
        
        var transcript = Transcript()
        transcript.append(.instructions(Transcript.Instructions(
            id: "inst-1",
            segments: [],
            toolDefinitions: [toolDef]
        )))
        
        // Extract the tools and check the parameters conversion
        let tools = TranscriptConverter.extractTools(from: transcript)
        
        if let tool = tools?.first {
            let params = tool.function.parameters
            print("Converted parameters:")
            print("Type: \(params.type)")
            print("Properties count: \(params.properties.count)")
            print("Required count: \(params.required.count)")
            
            // Encode the final tool to see what we get
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let toolData = try encoder.encode(tool)
            let toolString = String(data: toolData, encoding: .utf8) ?? "Failed"
            print("\nFinal tool JSON:")
            print(toolString)
        }
    }
    
    @Test("Test if GenerationSchema properties are accessible")
    func testGenerationSchemaAccess() throws {
        let schema = GenerationSchema(type: String.self, description: "Test access", properties: [])
        
        // Check what we can access directly
        print("Direct access:")
        print("Type: \(schema.type)")
        print("Description: \(schema.description ?? "nil")")
        
        // The properties and required might be internal - let's see if we can access them
        // through any other means
        
        // Try to create a simple GenerationSchema and see what happens
        let simpleSchema = GenerationSchema(type: String.self, properties: [])
        print("Simple schema type: \(simpleSchema.type)")
        
        // Check if the initializers work as expected
        let objectSchema = GenerationSchema(type: String.self, properties: []) // Using String as placeholder
        print("Object schema type: \(objectSchema.type)")
    }
}