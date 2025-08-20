import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

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
    
    // MARK: - OllamaTool for Tags
    
    @Generable
    struct OllamaTagsArguments {
        @Guide(description: "Whether to include detailed model information")
        let includeDetails: Bool?
        
        @Guide(description: "Filter models by name pattern")
        let filter: String?
    }
    
    struct OllamaTagsTool: OpenFoundationModels.Tool {
        typealias Arguments = OllamaTagsArguments
        typealias Output = String
        
        private let configuration: OllamaConfiguration
        
        init(configuration: OllamaConfiguration = OllamaConfiguration()) {
            self.configuration = configuration
        }
        
        var name: String { "get_ollama_models" }
        var description: String { "Get list of available Ollama models installed on the system" }
        var includesSchemaInInstructions: Bool { true }
        
        func call(arguments: OllamaTagsArguments) async throws -> String {
            let httpClient = OllamaHTTPClient(configuration: configuration)
            let response: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
            
            var models = response.models
            
            // Apply filter if provided
            if let filter = arguments.filter, !filter.isEmpty {
                models = models.filter { $0.name.lowercased().contains(filter.lowercased()) }
            }
            
            if models.isEmpty {
                return "No Ollama models found" + (arguments.filter != nil ? " matching filter '\(arguments.filter!)'." : ".")
            }
            
            var result = "Available Ollama models:\n\n"
            
            for model in models {
                result += "• \(model.name)"
                
                if arguments.includeDetails == true {
                    // Add size information
                    let sizeInMB = Double(model.size) / (1024 * 1024)
                    let sizeInGB = sizeInMB / 1024
                    let sizeStr = sizeInGB > 1.0 ? 
                        String(format: "%.1fGB", sizeInGB) : 
                        String(format: "%.0fMB", sizeInMB)
                    result += " (\(sizeStr))"
                    
                    // Add details if available
                    if let details = model.details {
                        if let paramSize = details.parameterSize {
                            result += "\n  - Parameters: \(paramSize)"
                        }
                        if let quantization = details.quantizationLevel {
                            result += "\n  - Quantization: \(quantization)"
                        }
                        if let family = details.family {
                            result += "\n  - Family: \(family)"
                        }
                    }
                    
                    // Add modified date
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    result += "\n  - Modified: \(formatter.string(from: model.modifiedAt))"
                }
                
                result += "\n"
            }
            
            result += "\nTotal: \(models.count) model(s)"
            
            return result
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
    
    @Test("Basic generate test")
    @available(macOS 13.0, iOS 16.0, *)
    func testBasicGenerate() async throws {
        try await TestUtilities.checkPreconditions(modelName: defaultModel)
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Say hello"))]
            ))
        ])
        
        let responseEntry = try await model.generate(
            transcript: transcript,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 50)
        )
        
        // Verify we got a response
        if case .response(let response) = responseEntry {
            #expect(!response.segments.isEmpty)
        } else {
            Issue.record("Expected response entry")
        }
    }
    
    @Test("Basic stream test")
    @available(macOS 13.0, iOS 16.0, *)
    func testBasicStream() async throws {
        try await TestUtilities.checkPreconditions(modelName: defaultModel)
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Say hello"))]
            ))
        ])
        
        var responseCount = 0
        let stream = model.stream(
            transcript: transcript,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 20)
        )
        
        for await entry in stream {
            responseCount += 1
            if case .response(let response) = entry {
                #expect(!response.segments.isEmpty)
            }
        }
        
        #expect(responseCount > 0)
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
    
    
    // MARK: - OllamaTool Session Tests
    
    @Test("Natural language request for Ollama models")
    func testNaturalLanguageModelList() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let tool = OllamaTagsTool()
        
        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: "You are an assistant that helps users understand available Ollama models. When asked about available models, use the get_ollama_models tool."
        )
        
        let response = try await session.respond(
            to: "What Ollama models are available on my system?",
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("Response: \(response.content)")
        
        // Check if tool was called
        var toolWasCalled = false
        for entry in session.transcript {
            if case .toolCalls(let toolCalls) = entry {
                toolWasCalled = toolCalls.contains { $0.toolName == "get_ollama_models" }
                if toolWasCalled {
                    print("✅ Tool was called successfully")
                    break
                }
            }
        }
        
        if !toolWasCalled {
            print("ℹ️ Model provided direct answer without using tool")
        }
        
        // Response should contain model information either way
        #expect(!response.content.isEmpty)
    }
    
    @Test("Request models with details")
    func testModelsWithDetails() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let tool = OllamaTagsTool()
        
        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: "You are an assistant that helps users understand available Ollama models. When asked about models, use the get_ollama_models tool with includeDetails set to true when the user wants detailed information."
        )
        
        let response = try await session.respond(
            to: "Show me all Ollama models with their detailed information including size and parameters.",
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("Response with details: \(response.content)")
        
        // Check if tool was called with includeDetails
        var toolCalledWithDetails = false
        for entry in session.transcript {
            if case .toolCalls(let toolCalls) = entry {
                for toolCall in toolCalls {
                    if toolCall.toolName == "get_ollama_models" {
                        do {
                            let args = try OllamaTagsArguments(toolCall.arguments)
                            if args.includeDetails == true {
                                toolCalledWithDetails = true
                                print("✅ Tool was called with includeDetails=true")
                            }
                        } catch {
                            print("Failed to parse arguments: \(error)")
                        }
                    }
                }
            }
        }
        
        #expect(!response.content.isEmpty)
    }
    
    @Test("Verify tool call in transcript")
    func testToolCallInTranscript() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let tool = OllamaTagsTool()
        
        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: "You are an assistant. Always use the get_ollama_models tool when asked about available models."
        )
        
        let _ = try await session.respond(
            to: "List the Ollama models.",
            options: GenerationOptions(temperature: 0.1)
        )
        
        // Analyze transcript
        var hasInstructions = false
        var hasPrompt = false
        var hasToolCalls = false
        var hasToolOutput = false
        var hasResponse = false
        
        for entry in session.transcript {
            switch entry {
            case .instructions(let instructions):
                hasInstructions = true
                // Check if tool definitions are present
                let toolDefs = instructions.toolDefinitions
                #expect(toolDefs.count == 1)
                #expect(toolDefs.first?.name == "get_ollama_models")
                print("✅ Instructions with tool definitions found")
                
            case .prompt:
                hasPrompt = true
                print("✅ User prompt found")
                
            case .toolCalls(let toolCalls):
                hasToolCalls = true
                #expect(toolCalls.count > 0)
                print("✅ Tool calls found: \(toolCalls.map { $0.toolName })")
                
            case .toolOutput(let output):
                hasToolOutput = true
                print("✅ Tool output found for: \(output.toolName)")
                
            case .response:
                hasResponse = true
                print("✅ Model response found")
            }
        }
        
        #expect(hasInstructions)
        #expect(hasPrompt)
        #expect(hasResponse)
        
        // Tool calls and output may or may not be present depending on model behavior
        if hasToolCalls {
            print("Model used the tool")
            #expect(hasToolOutput, "If tool was called, output should be present")
        } else {
            print("Model provided direct answer without tool")
        }
    }
    
    @Test("Filter models by name")
    func testFilterModelsByName() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let tool = OllamaTagsTool()
        
        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: "You are an assistant. Use the get_ollama_models tool with appropriate filter when users ask about specific models."
        )
        
        let response = try await session.respond(
            to: "Show me only the llama models available.",
            options: GenerationOptions(temperature: 0.1)
        )
        
        print("Filtered response: \(response.content)")
        
        // Check if filter was used
        for entry in session.transcript {
            if case .toolCalls(let toolCalls) = entry {
                for toolCall in toolCalls {
                    if toolCall.toolName == "get_ollama_models" {
                        do {
                            let args = try OllamaTagsArguments(toolCall.arguments)
                            if let filter = args.filter {
                                print("✅ Tool was called with filter: '\(filter)'")
                            }
                        } catch {
                            print("Failed to parse arguments: \(error)")
                        }
                    }
                }
            }
        }
        
        #expect(!response.content.isEmpty)
    }
}
