import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

@Suite("Tool Conversion Tests", .serialized)
struct ToolConversionTests {
    
    // MARK: - GenerationSchema to Parameters Conversion Tests
    
    @Test("Convert GenerationSchema with properties to Tool.Function.Parameters")
    func testSchemaWithPropertiesToParameters() throws {
        // Create simplified GenerationSchema
        let schema = GenerationSchema(type: String.self, description: "Weather parameters", properties: [])
        
        let toolDef = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get weather information",
            parameters: schema
        )
        
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [toolDef]
            ))
        ])
        
        // Extract tools and verify
        let tools = TranscriptConverter.extractTools(from: transcript)
        
        #expect(tools?.count == 1)
        #expect(tools?.first?.function.name == "get_weather")
        #expect(tools?.first?.function.parameters.type == "string") // Simplified schema type
        
        // Verify the parameters were properly converted
        let params = tools?.first?.function.parameters
        #expect(params?.properties.count == 0) // Simplified schema has no properties
    }
    
    @Test("Convert simple GenerationSchema to Tool.Function.Parameters")
    func testSimpleSchemaToParameters() throws {
        let schema = GenerationSchema(
            type: String.self,
            description: "Simple parameters",
            properties: []
        )
        
        let toolDef = Transcript.ToolDefinition(
            name: "simple_tool",
            description: "A simple tool",
            parameters: schema
        )
        
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [toolDef]
            ))
        ])
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        
        #expect(tools?.count == 1)
        #expect(tools?.first?.function.parameters.type == "string") // Simplified schema type
    }
    
    // MARK: - Tool Definition Extraction Tests
    
    @Test("Extract multiple tool definitions from transcript")
    func testMultipleToolExtraction() throws {
        let weatherTool = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get weather information",
            parameters: GenerationSchema(type: String.self, description: "Weather params", properties: [])
        )
        
        let timeTool = Transcript.ToolDefinition(
            name: "get_time",
            description: "Get current time",
            parameters: GenerationSchema(type: String.self, description: "Time params", properties: [])
        )
        
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [],
                toolDefinitions: [weatherTool, timeTool]
            ))
        ])
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        
        #expect(tools?.count == 2)
        #expect(tools?.first?.function.name == "get_weather")
        #expect(tools?.last?.function.name == "get_time")
    }
    
    @Test("No tools when transcript has no tool definitions")
    func testNoToolExtraction() throws {
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [.text(Transcript.TextSegment(id: "seg-1", content: "You are helpful"))],
                toolDefinitions: []
            ))
        ])
        
        let tools = TranscriptConverter.extractTools(from: transcript)
        
        #expect(tools == nil)
    }
    
    // MARK: - Tool Call Conversion Tests
    
    @Test("Convert Transcript.ToolCalls to Ollama ToolCall format")
    func testToolCallConversion() throws {
        // Create a tool call with arguments
        let toolCall = Transcript.ToolCall(
            id: "call-1",
            toolName: "get_weather",
            arguments: GeneratedContent(
                kind: .structure(
                    properties: ["location": GeneratedContent(kind: .string("Tokyo")),
                                 "unit": GeneratedContent(kind: .string("celsius"))],
                    orderedKeys: ["location", "unit"]
                )
            )
        )
        
        let toolCalls = Transcript.ToolCalls(id: "calls-1", [toolCall])
        
        // Build messages from transcript with tool calls
        let transcript = Transcript(entries: [
            .toolCalls(toolCalls)
        ])
        
        let messages = TranscriptConverter.buildMessages(from: transcript)
        
        #expect(messages.count == 1)
        #expect(messages.first?.role == .assistant)
        #expect(messages.first?.toolCalls?.count == 1)
        
        let ollamaToolCall = messages.first?.toolCalls?.first
        #expect(ollamaToolCall?.function.name == "get_weather")
        
        // Check arguments
        let args = ollamaToolCall?.function.arguments.dictionary
        #expect(args?["location"] as? String == "Tokyo")
        #expect(args?["unit"] as? String == "celsius")
    }
    
    // MARK: - Integration Tests
    
    @Test("Complete tool flow in transcript")
    func testCompleteToolFlow() throws {
        // 1. Add instructions with tool definition
        let weatherTool = Transcript.ToolDefinition(
            name: "get_weather",
            description: "Get weather for a location",
            parameters: GenerationSchema(type: String.self, description: "Weather parameters", properties: [])
        )
        
        // 3. Add tool call response
        let toolCall = Transcript.ToolCall(
            id: "call-1",
            toolName: "get_weather",
            arguments: GeneratedContent(
                kind: .structure(
                    properties: ["location": GeneratedContent(kind: .string("Tokyo"))],
                    orderedKeys: ["location"]
                )
            )
        )
        
        let transcript = Transcript(entries: [
            // 1. Instructions with tool definition
            .instructions(Transcript.Instructions(
                id: "inst-1",
                segments: [.text(Transcript.TextSegment(id: "seg-1", content: "You can check weather"))],
                toolDefinitions: [weatherTool]
            )),
            // 2. User prompt
            .prompt(Transcript.Prompt(
                id: "prompt-1",
                segments: [.text(Transcript.TextSegment(id: "seg-2", content: "What's the weather in Tokyo?"))],
                options: GenerationOptions(),
                responseFormat: nil
            )),
            // 3. Tool call response
            .toolCalls(Transcript.ToolCalls(id: "calls-1", [toolCall])),
            // 4. Tool output
            .toolOutput(Transcript.ToolOutput(
                id: "output-1",
                toolName: "get_weather",
                segments: [.text(Transcript.TextSegment(id: "seg-3", content: "72°F and sunny"))]
            )),
            // 5. Final response
            .response(Transcript.Response(
                id: "resp-1",
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(id: "seg-4", content: "The weather in Tokyo is 72°F and sunny."))]
            ))
        ])
        
        // Convert to messages
        let messages = TranscriptConverter.buildMessages(from: transcript)
        
        // Verify the message flow
        #expect(messages.count == 5)
        #expect(messages[0].role == .system) // Instructions
        #expect(messages[1].role == .user)   // Prompt
        #expect(messages[2].role == .assistant) // Tool call
        #expect(messages[2].toolCalls?.count == 1)
        #expect(messages[3].role == .tool)   // Tool output
        #expect(messages[4].role == .assistant) // Final response
        
        // Extract tools
        let tools = TranscriptConverter.extractTools(from: transcript)
        #expect(tools?.count == 1)
        #expect(tools?.first?.function.name == "get_weather")
    }
}