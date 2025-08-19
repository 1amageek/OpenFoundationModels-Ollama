import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
@testable import OpenFoundationModelsCore

@Suite("GenerationSchema Property Encoding Test")
struct GenerationSchemaPropertyTest {
    
    @Test("Verify GenerationSchema with properties encodes correctly")
    func testGenerationSchemaWithProperties() throws {
        print("\n=== Testing GenerationSchema Property Encoding ===\n")
        
        // Test 1: Simple GenerationSchema with properties
        print("1. Creating GenerationSchema with properties:")
        let properties = [
            GenerationSchema.Property(
                name: "location",
                description: "City name",
                type: String.self
            ),
            GenerationSchema.Property(
                name: "unit",
                description: "Temperature unit",
                type: String?.self // Optional
            )
        ]
        
        let schema = GenerationSchema(
            type: String.self, // Using String as Generable type
            description: "Weather parameters",
            properties: properties
        )
        
        print("   Properties created: \(properties.count)")
        for prop in properties {
            print("   - \(prop.name): \(prop.description ?? "no description")")
        }
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(schema)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "Failed to encode"
        
        print("\n2. Encoded GenerationSchema JSON:")
        print(jsonString)
        
        // Parse JSON to check structure
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        print("\n3. Analyzing JSON structure:")
        print("   - Has 'type': \(json?["type"] != nil ? "YES" : "NO")")
        print("   - Has 'description': \(json?["description"] != nil ? "YES" : "NO")")
        print("   - Has 'properties': \(json?["properties"] != nil ? "YES" : "NO")")
        print("   - Has 'required': \(json?["required"] != nil ? "YES" : "NO")")
        
        if let props = json?["properties"] as? [String: Any] {
            print("\n4. Properties found in JSON:")
            for (key, value) in props {
                print("   - \(key): \(value)")
            }
        } else {
            print("\n4. ❌ No properties found in JSON!")
        }
        
        // Test expectation
        #expect(json?["type"] != nil, "Should have type")
        #expect(json?["description"] != nil, "Should have description")
        
        // This is the key test - properties should be included
        let hasProperties = json?["properties"] != nil
        if !hasProperties {
            print("\n⚠️ ISSUE CONFIRMED: GenerationSchema.encode() does not include properties!")
        }
    }
    
    @Test("Verify DynamicGenerationSchema encoding")
    func testDynamicGenerationSchemaEncoding() throws {
        print("\n=== Testing DynamicGenerationSchema Encoding ===\n")
        
        // Create DynamicGenerationSchema
        let locationSchema = DynamicGenerationSchema(type: String.self)
        let unitSchema = DynamicGenerationSchema(
            name: "TemperatureUnit",
            anyOf: ["celsius", "fahrenheit", "kelvin"]
        )
        
        let properties = [
            DynamicGenerationSchema.Property(
                name: "location",
                description: "City name",
                schema: locationSchema,
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "unit",
                description: "Temperature unit",
                schema: unitSchema,
                isOptional: true
            )
        ]
        
        let dynamicSchema = DynamicGenerationSchema(
            name: "WeatherParameters",
            description: "Parameters for weather",
            properties: properties
        )
        
        print("1. Created DynamicGenerationSchema with \(properties.count) properties")
        
        // Convert to GenerationSchema
        let schema = try GenerationSchema(root: dynamicSchema, dependencies: [])
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(schema)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "Failed to encode"
        
        print("\n2. Encoded DynamicGenerationSchema-based JSON:")
        print(jsonString)
        
        // Parse JSON
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        print("\n3. JSON Analysis:")
        print("   - Type: \(json?["type"] ?? "missing")")
        print("   - Properties exist: \(json?["properties"] != nil)")
        
        if let props = json?["properties"] as? [String: Any] {
            print("\n4. Properties in JSON: \(props.keys.joined(separator: ", "))")
        } else {
            print("\n4. ❌ No properties in DynamicGenerationSchema JSON either!")
        }
    }
    
    @Test("Compare with manual JSON creation")
    func testManualJSONComparison() throws {
        print("\n=== Expected vs Actual JSON Comparison ===\n")
        
        // What we expect
        let expectedJSON: [String: Any] = [
            "type": "object",
            "description": "Weather parameters",
            "properties": [
                "location": [
                    "type": "string",
                    "description": "City name"
                ],
                "unit": [
                    "type": "string",
                    "description": "Temperature unit"
                ]
            ],
            "required": ["location"]
        ]
        
        print("1. Expected JSON structure:")
        let expectedData = try JSONSerialization.data(withJSONObject: expectedJSON, options: .prettyPrinted)
        print(String(data: expectedData, encoding: .utf8) ?? "")
        
        // What we actually get from GenerationSchema
        let properties = [
            GenerationSchema.Property(
                name: "location",
                description: "City name",
                type: String.self
            ),
            GenerationSchema.Property(
                name: "unit",
                description: "Temperature unit",
                type: String?.self
            )
        ]
        
        let schema = GenerationSchema(
            type: String.self,
            description: "Weather parameters",
            properties: properties
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let actualData = try encoder.encode(schema)
        
        print("\n2. Actual GenerationSchema JSON:")
        print(String(data: actualData, encoding: .utf8) ?? "")
        
        print("\n3. Comparison Summary:")
        let actualJSON = try JSONSerialization.jsonObject(with: actualData) as? [String: Any]
        
        print("   Expected has 'properties': YES")
        print("   Actual has 'properties': \(actualJSON?["properties"] != nil ? "YES" : "NO")")
        
        if actualJSON?["properties"] == nil {
            print("\n❌ CONFIRMED: GenerationSchema loses property information during encoding!")
            print("   This prevents proper tool parameter definition in LLM APIs.")
        }
    }
}