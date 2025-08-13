import Foundation
import OpenFoundationModels

/// Helper for building tool definitions with explicit schemas
/// This works around GenerationSchema limitations by allowing direct schema specification
public struct ToolDefinitionBuilder {
    
    /// Create a tool definition with explicit schema properties
    /// - Parameters:
    ///   - name: Tool name
    ///   - description: Tool description
    ///   - properties: Tool properties as [String: PropertyDefinition]
    ///   - required: Required property names
    /// - Returns: A Transcript.ToolDefinition with proper schema
    public static func createTool(
        name: String,
        description: String,
        properties: [String: PropertyDefinition] = [:],
        required: [String] = []
    ) -> Transcript.ToolDefinition {
        // Store the schema information in our registry first
        ToolSchemaRegistry.shared.registerTool(
            name: name,
            properties: properties,
            required: required
        )
        
        // Create a simple GenerationSchema (properties will be handled by our registry)
        // Using a simple structure since we can't access internal initializer
        let emptyProperties: [GenerationSchema.Property] = []
        let schema = GenerationSchema(
            type: String.self,  // Use String.self as placeholder
            description: description,
            properties: emptyProperties
        )
        
        let toolDefinition = Transcript.ToolDefinition(
            name: name,
            description: description,
            parameters: schema
        )
        
        return toolDefinition
    }
    
    /// Property definition for tool parameters
    public struct PropertyDefinition {
        public let type: String
        public let description: String
        public let enumValues: [String]?
        
        public init(type: String, description: String, enumValues: [String]? = nil) {
            self.type = type
            self.description = description
            self.enumValues = enumValues
        }
        
        // Convenience initializers
        public static func string(_ description: String) -> PropertyDefinition {
            PropertyDefinition(type: "string", description: description)
        }
        
        public static func integer(_ description: String) -> PropertyDefinition {
            PropertyDefinition(type: "integer", description: description)
        }
        
        public static func number(_ description: String) -> PropertyDefinition {
            PropertyDefinition(type: "number", description: description)
        }
        
        public static func boolean(_ description: String) -> PropertyDefinition {
            PropertyDefinition(type: "boolean", description: description)
        }
        
        public static func array(_ description: String) -> PropertyDefinition {
            PropertyDefinition(type: "array", description: description)
        }
        
        public static func enumeration(_ description: String, values: [String]) -> PropertyDefinition {
            PropertyDefinition(type: "string", description: description, enumValues: values)
        }
    }
}

/// Internal registry for tool schemas
/// This allows us to store and retrieve actual schema information
internal final class ToolSchemaRegistry: @unchecked Sendable {
    static let shared = ToolSchemaRegistry()
    
    private var toolSchemas: [String: ToolSchema] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    struct ToolSchema {
        let properties: [String: ToolDefinitionBuilder.PropertyDefinition]
        let required: [String]
    }
    
    func registerTool(
        name: String,
        properties: [String: ToolDefinitionBuilder.PropertyDefinition],
        required: [String]
    ) {
        lock.withLock {
            toolSchemas[name] = ToolSchema(properties: properties, required: required)
        }
    }
    
    func getToolSchema(name: String) -> ToolSchema? {
        lock.withLock {
            return toolSchemas[name]
        }
    }
    
    func clear() {
        lock.withLock {
            toolSchemas.removeAll()
        }
    }
}