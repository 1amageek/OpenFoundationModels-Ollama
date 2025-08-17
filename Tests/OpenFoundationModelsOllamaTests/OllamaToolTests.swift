import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

// TestSkip is defined in OllamaLanguageModelTests.swift

@Suite("Ollama Tool Calling Tests")
struct OllamaToolTests {
    
    // MARK: - Test Configuration
    
    private let defaultModel = "gpt-oss:20b"
    private let testTimeout: TimeInterval = 30.0
    
    private var isOllamaAvailable: Bool {
        get async {
            do {
                let config = OllamaConfiguration()
                let httpClient = OllamaHTTPClient(configuration: config)
                let _: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
                return true
            } catch let error as OllamaHTTPError {
                print("Ollama connection check failed: \(error.localizedDescription)")
                return false
            } catch {
                print("Unexpected error checking Ollama: \(error)")
                return false
            }
        }
    }
    
    // MARK: - Tool Definition Tests
    
    @Test("Tool structure creation")
    func testToolCreation() {
        let tool = Tool(
            type: "function",
            function: Tool.Function(
                name: "get_weather",
                description: "Get the current weather for a location",
                parameters: Tool.Function.Parameters(
                    type: "object",
                    properties: [
                        "location": Tool.Function.Parameters.Property(
                            type: "string",
                            description: "The city name"
                        ),
                        "unit": Tool.Function.Parameters.Property(
                            type: "string",
                            description: "Temperature unit (celsius or fahrenheit)"
                        )
                    ],
                    required: ["location"]
                )
            )
        )
        
        #expect(tool.type == "function")
        #expect(tool.function.name == "get_weather")
        #expect(tool.function.description == "Get the current weather for a location")
        #expect(tool.function.parameters.properties.count == 2)
        #expect(tool.function.parameters.required.contains("location"))
    }
    
    @Test("Message with toolName encoding")
    func testMessageWithToolName() throws {
        let message = Message(
            role: .tool,
            content: "The weather in Tokyo is 11 degrees celsius",
            toolName: "get_weather"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["role"] as? String == "tool")
        #expect(json?["content"] as? String == "The weather in Tokyo is 11 degrees celsius")
        #expect(json?["tool_name"] as? String == "get_weather")
    }
    
    @Test("Tool encoding to JSON")
    func testToolEncoding() throws {
        let tool = Tool(
            type: "function",
            function: Tool.Function(
                name: "calculate",
                description: "Perform basic math operations",
                parameters: Tool.Function.Parameters(
                    type: "object",
                    properties: [
                        "operation": Tool.Function.Parameters.Property(
                            type: "string",
                            description: "The operation to perform (add, subtract, multiply, divide)"
                        ),
                        "a": Tool.Function.Parameters.Property(
                            type: "number",
                            description: "First number"
                        ),
                        "b": Tool.Function.Parameters.Property(
                            type: "number",
                            description: "Second number"
                        )
                    ],
                    required: ["operation", "a", "b"]
                )
            )
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["type"] as? String == "function")
        
        let function = json?["function"] as? [String: Any]
        #expect(function?["name"] as? String == "calculate")
        #expect(function?["description"] as? String == "Perform basic math operations")
        
        let parameters = function?["parameters"] as? [String: Any]
        #expect(parameters?["type"] as? String == "object")
        
        let properties = parameters?["properties"] as? [String: Any]
        #expect(properties?.count == 3)
        
        let required = parameters?["required"] as? [String]
        #expect(required?.count == 3)
        #expect(required?.contains("operation") == true)
    }
    
    // MARK: - Tool Call Tests
    
    @Test("ToolCall creation and encoding")
    func testToolCallCreation() throws {
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "get_weather",
                arguments: [
                    "location": "Tokyo",
                    "unit": "celsius"
                ]
            )
        )
        
        #expect(toolCall.function.name == "get_weather")
        #expect(toolCall.function.arguments.dictionary["location"] as? String == "Tokyo")
        #expect(toolCall.function.arguments.dictionary["unit"] as? String == "celsius")
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(toolCall)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let function = json?["function"] as? [String: Any]
        #expect(function?["name"] as? String == "get_weather")
        
        let arguments = function?["arguments"] as? [String: Any]
        #expect(arguments?["location"] as? String == "Tokyo")
        #expect(arguments?["unit"] as? String == "celsius")
    }
    
    @Test("Message with tool calls")
    func testMessageWithToolCalls() throws {
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "calculate",
                arguments: [
                    "operation": "add",
                    "a": 5,
                    "b": 3
                ]
            )
        )
        
        let message = Message(
            role: .assistant,
            content: "",
            toolCalls: [toolCall]
        )
        
        #expect(message.role == .assistant)
        #expect(message.content.isEmpty)
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?.first?.function.name == "calculate")
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["role"] as? String == "assistant")
        #expect(json?["content"] as? String == "")
        
        let toolCalls = json?["tool_calls"] as? [[String: Any]]
        #expect(toolCalls?.count == 1)
    }
    
    @Test("Tool call response parsing")
    func testToolCallResponseParsing() throws {
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "get_weather",
                arguments: ["city": "Tokyo", "unit": "celsius"]
            )
        )
        
        let message = Message(
            role: .assistant,
            content: "",
            toolCalls: [toolCall]
        )
        
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?.first?.function.name == "get_weather")
        #expect(message.toolCalls?.first?.function.arguments.dictionary["city"] as? String == "Tokyo")
    }
    
    @Test("Tool message round-trip encoding")
    func testToolMessageRoundTrip() throws {
        // Create tool result message
        let toolMessage = Message(
            role: .tool,
            content: "11 degrees celsius, partly cloudy",
            toolName: "get_weather"
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(toolMessage)
        
        // Decode back
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Message.self, from: data)
        
        #expect(decoded.role == .tool)
        #expect(decoded.content == "11 degrees celsius, partly cloudy")
        #expect(decoded.toolName == "get_weather")
    }
    
    // MARK: - Chat Request with Tools Tests
    
    @Test("ChatRequest with tools")
    func testChatRequestWithTools() throws {
        let tool = Tool(
            type: "function",
            function: Tool.Function(
                name: "search",
                description: "Search for information",
                parameters: Tool.Function.Parameters(
                    type: "object",
                    properties: [
                        "query": Tool.Function.Parameters.Property(
                            type: "string",
                            description: "Search query"
                        )
                    ],
                    required: ["query"]
                )
            )
        )
        
        let messages = [
            Message(role: .user, content: "Search for information about Swift programming")
        ]
        
        let request = ChatRequest(
            model: defaultModel,
            messages: messages,
            stream: false,
            tools: [tool]
        )
        
        #expect(request.model == defaultModel)
        #expect(request.messages.count == 1)
        #expect(request.tools?.count == 1)
        #expect(request.tools?.first?.function.name == "search")
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["model"] as? String == defaultModel)
        #expect(json?["stream"] as? Bool == false)
        
        let tools = json?["tools"] as? [[String: Any]]
        #expect(tools?.count == 1)
    }
    
    // MARK: - Integration Tests (requires Ollama running)
    
    @Test("Chat with tools integration")
    @available(macOS 13.0, iOS 16.0, *)
    func testChatWithTools() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create a simple tool
        let weatherTool = Tool(
            type: "function",
            function: Tool.Function(
                name: "get_weather",
                description: "Get weather information for a city",
                parameters: Tool.Function.Parameters(
                    type: "object",
                    properties: [
                        "city": Tool.Function.Parameters.Property(
                            type: "string",
                            description: "The city name"
                        )
                    ],
                    required: ["city"]
                )
            )
        )
        
        let messages = [
            Message(role: .user, content: "What's the weather in Tokyo?")
        ]
        
        let response = try await model.chat(
            messages: messages,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100),
            tools: [weatherTool]
        )
        
        #expect(response.model == defaultModel)
        
        // The model might either:
        // 1. Call the tool (if it recognizes the need)
        // 2. Respond directly (if it doesn't support tools or doesn't recognize the need)
        if let toolCalls = response.message?.toolCalls, !toolCalls.isEmpty {
            // Tool was called
            #expect(toolCalls.first?.function.name == "get_weather")
            let args = toolCalls.first?.function.arguments.dictionary
            #expect(args?["city"] as? String != nil)
        } else {
            // Direct response
            #expect(response.message?.content != nil)
        }
    }
    
    @Test("Stream chat with tools")
    @available(macOS 13.0, iOS 16.0, *)
    func testStreamChatWithTools() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let calculateTool = Tool(
            type: "function",
            function: Tool.Function(
                name: "calculate",
                description: "Perform calculations",
                parameters: Tool.Function.Parameters(
                    type: "object",
                    properties: [
                        "expression": Tool.Function.Parameters.Property(
                            type: "string",
                            description: "Math expression to evaluate"
                        )
                    ],
                    required: ["expression"]
                )
            )
        )
        
        let messages = [
            Message(role: .user, content: "Calculate 25 * 4")
        ]
        
        var responses: [ChatResponse] = []
        let stream = model.streamChat(
            messages: messages,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 50),
            tools: [calculateTool]
        )
        
        for try await response in stream {
            responses.append(response)
            if response.done {
                break
            }
        }
        
        #expect(responses.count > 0)
        
        // Check if we got a complete response
        if let lastResponse = responses.last {
            #expect(lastResponse.done == true)
            #expect(lastResponse.model == defaultModel)
        }
    }
    
    // MARK: - Tool Response Handling Tests
    
    @Test("Tool response message creation")
    func testToolResponseMessage() {
        let toolResponseMessage = Message(
            role: .tool,
            content: "72°F and sunny"
        )
        
        #expect(toolResponseMessage.role == .tool)
        #expect(toolResponseMessage.content == "72°F and sunny")
        #expect(toolResponseMessage.toolCalls == nil)
    }
    
    @Test("Complete tool interaction flow")
    @available(macOS 13.0, iOS 16.0, *)
    func testCompleteToolFlow() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Define a simple tool
        let tool = Tool(
            type: "function",
            function: Tool.Function(
                name: "get_time",
                description: "Get the current time",
                parameters: Tool.Function.Parameters(
                    type: "object",
                    properties: [:],
                    required: []
                )
            )
        )
        
        // Initial user message
        var messages = [
            Message(role: .user, content: "What time is it?")
        ]
        
        // First call - might trigger tool call
        let response1 = try await model.chat(
            messages: messages,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100),
            tools: [tool]
        )
        
        if let assistantMessage = response1.message {
            messages.append(assistantMessage)
            
            // If tool was called, add tool response
            if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty {
                // Simulate tool execution
                let toolResponse = Message(
                    role: .tool,
                    content: "The current time is 3:30 PM"
                )
                messages.append(toolResponse)
                
                // Get final response
                let response2 = try await model.chat(
                    messages: messages,
                    options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 100)
                )
                
                #expect(response2.message?.content != nil)
            }
        }
        
        #expect(messages.count >= 2)
    }
}