import Testing
import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore
@testable import OpenFoundationModelsOllama

@Test("Debug memory.session.list schema")
func testMemorySessionListSchema() async throws {
    // Create a simple schema with string parameters (to see how Date parameters appear)
    let dynamicSchema = DynamicGenerationSchema(
        name: "MemorySessionListParameters",
        description: "Parameters for listing memory sessions",
        properties: [
            DynamicGenerationSchema.Property(
                name: "startedAfter",
                description: "Filter sessions started after this date (ISO 8601 format)",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            DynamicGenerationSchema.Property(
                name: "startedBefore",
                description: "Filter sessions started before this date (ISO 8601 format)",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            )
        ]
    )
    
    let schema = try GenerationSchema(root: dynamicSchema, dependencies: [])
    
    let toolDef = Transcript.ToolDefinition(
        name: "memory.session.list",
        description: "List memory sessions with optional date filters",
        parameters: schema
    )
    
    // Create instructions with this tool
    let instructions = Transcript.Instructions(
        segments: [.text(Transcript.TextSegment(content: "You are a helpful assistant"))],
        toolDefinitions: [toolDef]
    )
    
    // Create transcript
    let transcript = Transcript(entries: [
        .instructions(instructions),
        .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: "List sessions"))]))
    ])
    
    // This will trigger the debug prints
    let tools = TranscriptConverter.extractTools(from: transcript)
    
    // Print the actual tools that would be sent to Ollama
    if let tools = tools {
        print("\n===== FINAL TOOLS TO OLLAMA =====")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(tools),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
        print("==================================\n")
    }
}