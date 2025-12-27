import Foundation
import OpenFoundationModels

/// Helper for creating tool schemas in a simplified way
public struct ToolSchemaHelper {
    
    /// Create a tool definition with a simple empty schema
    public static func createSimpleTool(
        name: String,
        description: String
    ) -> Transcript.ToolDefinition {
        // Use a minimal GenerationSchema with empty properties
        let schema = GenerationSchema(type: String.self, description: description, properties: [])
        
        return Transcript.ToolDefinition(
            name: name,
            description: description,
            parameters: schema
        )
    }
    
    /// Create a tool definition using DynamicGenerationSchema
    /// - Parameters:
    ///   - name: Tool name
    ///   - description: Tool description
    ///   - properties: Array of property definitions. Use `isOptional: false` to mark a field as required.
    /// - Note: Required fields are determined by `isOptional` flag in each property tuple.
    public static func createToolWithDynamicSchema(
        name: String,
        description: String,
        properties: [(name: String, type: String, description: String, isOptional: Bool)]
    ) throws -> Transcript.ToolDefinition {
        // Build DynamicGenerationSchema properties
        let dynamicProperties = properties.map { prop in
            let propSchema: DynamicGenerationSchema
            
            switch prop.type {
            case "string":
                propSchema = DynamicGenerationSchema(type: String.self)
            case "integer":
                propSchema = DynamicGenerationSchema(type: Int.self)
            case "boolean":
                propSchema = DynamicGenerationSchema(type: Bool.self)
            case "number":
                propSchema = DynamicGenerationSchema(type: Double.self)
            default:
                // Default to string for unknown types
                propSchema = DynamicGenerationSchema(type: String.self)
            }
            
            return DynamicGenerationSchema.Property(
                name: prop.name,
                description: prop.description,
                schema: propSchema,
                isOptional: prop.isOptional
            )
        }
        
        // Create the root DynamicGenerationSchema
        let dynamicSchema = DynamicGenerationSchema(
            name: "\(name)Parameters",
            description: description,
            properties: dynamicProperties
        )
        
        // Convert to GenerationSchema
        let schema = try GenerationSchema(root: dynamicSchema, dependencies: [])
        
        return Transcript.ToolDefinition(
            name: name,
            description: description,
            parameters: schema
        )
    }
    
    /// Create a weather tool with proper schema
    public static func createWeatherTool() throws -> Transcript.ToolDefinition {
        let locationSchema = DynamicGenerationSchema(type: String.self)
        let unitSchema = DynamicGenerationSchema(
            name: "TemperatureUnit",
            anyOf: ["celsius", "fahrenheit", "kelvin"]
        )
        let forecastSchema = DynamicGenerationSchema(type: Bool.self)
        
        let properties = [
            DynamicGenerationSchema.Property(
                name: "location",
                description: "City name or coordinates",
                schema: locationSchema,
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "unit",
                description: "Temperature unit",
                schema: unitSchema,
                isOptional: true
            ),
            DynamicGenerationSchema.Property(
                name: "include_forecast",
                description: "Include 5-day forecast",
                schema: forecastSchema,
                isOptional: true
            )
        ]
        
        let dynamicSchema = DynamicGenerationSchema(
            name: "WeatherParameters",
            description: "Parameters for weather information",
            properties: properties
        )
        
        let schema = try GenerationSchema(root: dynamicSchema, dependencies: [])
        
        return Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get current weather and optional forecast",
            parameters: schema
        )
    }
    
    /// Create a calculator tool with proper schema
    public static func createCalculatorTool() throws -> Transcript.ToolDefinition {
        let expressionSchema = DynamicGenerationSchema(type: String.self)
        let operationSchema = DynamicGenerationSchema(
            name: "OperationType",
            anyOf: ["add", "subtract", "multiply", "divide", "power", "sqrt", "complex"]
        )
        
        let properties = [
            DynamicGenerationSchema.Property(
                name: "expression",
                description: "Mathematical expression to evaluate",
                schema: expressionSchema,
                isOptional: false
            ),
            DynamicGenerationSchema.Property(
                name: "operation_type",
                description: "Type of mathematical operation",
                schema: operationSchema,
                isOptional: true
            )
        ]
        
        let dynamicSchema = DynamicGenerationSchema(
            name: "CalculatorParameters",
            description: "Parameters for mathematical calculations",
            properties: properties
        )
        
        let schema = try GenerationSchema(root: dynamicSchema, dependencies: [])
        
        return Transcript.ToolDefinition(
            name: "calculate",
            description: "Perform mathematical calculations",
            parameters: schema
        )
    }
}