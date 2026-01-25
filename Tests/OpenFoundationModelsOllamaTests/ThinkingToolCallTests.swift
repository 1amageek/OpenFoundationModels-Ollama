import Testing
import Foundation
@testable import OpenFoundationModelsOllama

@Suite("Thinking Field Tool Call Tests")
struct ThinkingToolCallTests {

    // MARK: - Problem Reproduction Tests

    @Test("Message with tool call in thinking field (GLM format)")
    func testToolCallInThinkingField() throws {
        // This is the actual response format from glm-4.7-flash
        let json = """
        {
            "role": "assistant",
            "content": "",
            "thinking": "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://kyoto.travel/en/</arg_value></tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        // Debug output
        print("=== DEBUG: testToolCallInThinkingField ===")
        print("Content: '\(message.content)'")
        print("Thinking: '\(message.thinking ?? "nil")'")
        print("ToolCalls: \(String(describing: message.toolCalls))")
        if let toolCalls = message.toolCalls {
            for (i, tc) in toolCalls.enumerated() {
                print("  ToolCall[\(i)]: name=\(tc.function.name), args=\(tc.function.arguments.dictionary)")
            }
        }
        print("==========================================")

        // This test documents the expected behavior after fix
        #expect(message.toolCalls != nil, "Tool calls should be extracted from thinking field")
        if let toolCalls = message.toolCalls {
            #expect(toolCalls.count == 1)
            #expect(toolCalls.first?.function.name == "WebFetch")
        }
    }

    @Test("Message with JSON tool call in thinking field")
    func testJSONToolCallInThinkingField() throws {
        // Some models might output JSON format in thinking
        let json = """
        {
            "role": "assistant",
            "content": "",
            "thinking": "Let me search for that. <tool_call>{\\"name\\": \\"WebSearch\\", \\"arguments\\": {\\"query\\": \\"Kyoto temples\\"}}</tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        print("=== DEBUG: testJSONToolCallInThinkingField ===")
        print("Thinking: '\(message.thinking ?? "nil")'")
        print("ToolCalls: \(String(describing: message.toolCalls))")
        print("==============================================")

        #expect(message.toolCalls != nil, "Tool calls should be extracted from thinking field")
        if let toolCalls = message.toolCalls {
            #expect(toolCalls.count == 1)
            #expect(toolCalls.first?.function.name == "WebSearch")
        }
    }

    @Test("Native tool_calls takes priority over thinking")
    func testNativeToolCallsPriority() throws {
        // When native tool_calls exist, don't parse thinking
        let json = """
        {
            "role": "assistant",
            "content": "",
            "thinking": "<tool_call>WebSearch<arg_key>query</arg_key><arg_value>wrong</arg_value></tool_call>",
            "tool_calls": [
                {
                    "function": {
                        "name": "WebFetch",
                        "arguments": {"url": "https://correct.com"}
                    }
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        print("=== DEBUG: testNativeToolCallsPriority ===")
        print("ToolCalls: \(String(describing: message.toolCalls))")
        print("==========================================")

        // Native tool_calls should take priority
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?.first?.function.name == "WebFetch")
    }

    // MARK: - GLM-style XML Format Tests (TextToolCallParser)

    @Test("Parse GLM-style tool call format")
    func testParseGLMStyleToolCall() throws {
        let content = "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://example.com</arg_value></tool_call>"

        print("=== DEBUG: testParseGLMStyleToolCall ===")
        print("Input content: '\(content)'")

        let result = TextToolCallParser.parse(content)

        print("Parsed toolCalls count: \(result.toolCalls.count)")
        print("Remaining content: '\(result.remainingContent)'")
        for (i, tc) in result.toolCalls.enumerated() {
            print("  ToolCall[\(i)]: name=\(tc.function.name), args=\(tc.function.arguments.dictionary)")
        }
        print("========================================")

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls.first?.function.name == "WebFetch")

        let args = result.toolCalls.first?.function.arguments.dictionary
        #expect(args?["url"] as? String == "https://example.com")
    }

    @Test("Parse GLM-style tool call with multiple arguments")
    func testParseGLMStyleToolCallMultipleArgs() throws {
        let content = """
        <tool_call>WebSearch<arg_key>query</arg_key><arg_value>Kyoto temples</arg_value><arg_key>limit</arg_key><arg_value>10</arg_value></tool_call>
        """

        print("=== DEBUG: testParseGLMStyleToolCallMultipleArgs ===")
        print("Input content: '\(content)'")

        let result = TextToolCallParser.parse(content)

        print("Parsed toolCalls count: \(result.toolCalls.count)")
        for (i, tc) in result.toolCalls.enumerated() {
            print("  ToolCall[\(i)]: name=\(tc.function.name), args=\(tc.function.arguments.dictionary)")
        }
        print("====================================================")

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls.first?.function.name == "WebSearch")

        let args = result.toolCalls.first?.function.arguments.dictionary
        #expect(args?["query"] as? String == "Kyoto temples")
        #expect(args?["limit"] as? String == "10")
    }

    @Test("Parse standard JSON tool call still works")
    func testParseStandardJSONToolCall() throws {
        let content = """
        <tool_call>{"name": "WebSearch", "arguments": {"query": "test"}}</tool_call>
        """

        print("=== DEBUG: testParseStandardJSONToolCall ===")
        print("Input content: '\(content)'")

        let result = TextToolCallParser.parse(content)

        print("Parsed toolCalls count: \(result.toolCalls.count)")
        for (i, tc) in result.toolCalls.enumerated() {
            print("  ToolCall[\(i)]: name=\(tc.function.name), args=\(tc.function.arguments.dictionary)")
        }
        print("=============================================")

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls.first?.function.name == "WebSearch")
    }

    // MARK: - ChatResponse Integration Tests

    @Test("ChatResponse with tool call in thinking (integration)")
    func testChatResponseWithThinkingToolCall() throws {
        // Simulates actual API response from glm-4.7-flash
        let json = """
        {
            "model": "glm-4.7-flash",
            "created_at": "2024-01-01T00:00:00Z",
            "message": {
                "role": "assistant",
                "content": "",
                "thinking": "The first page is cluttered. <tool_call>WebSearch<arg_key>query</arg_key><arg_value>Kyoto Japan temples</arg_value></tool_call>"
            },
            "done": true
        }
        """

        print("=== DEBUG: testChatResponseWithThinkingToolCall ===")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(ChatResponse.self, from: data)

        print("Message content: '\(response.message?.content ?? "nil")'")
        print("Message thinking: '\(response.message?.thinking ?? "nil")'")
        print("Message toolCalls: \(String(describing: response.message?.toolCalls))")
        print("===================================================")

        #expect(response.message?.toolCalls != nil, "Tool calls should be extracted from thinking")
        if let toolCalls = response.message?.toolCalls {
            #expect(toolCalls.count == 1)
            #expect(toolCalls.first?.function.name == "WebSearch")
        }
    }

    // MARK: - Edge Cases

    @Test("Empty thinking field")
    func testEmptyThinkingField() throws {
        let json = """
        {
            "role": "assistant",
            "content": "Hello",
            "thinking": ""
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.content == "Hello")
        #expect(message.toolCalls == nil)
    }

    @Test("Thinking field with no tool calls")
    func testThinkingFieldWithNoToolCalls() throws {
        let json = """
        {
            "role": "assistant",
            "content": "Here's the answer",
            "thinking": "Let me think about this... The user wants to know about Kyoto."
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.content == "Here's the answer")
        #expect(message.thinking == "Let me think about this... The user wants to know about Kyoto.")
        #expect(message.toolCalls == nil)
    }

    @Test("Tool call in content takes priority over thinking")
    func testToolCallInContentPriority() throws {
        // When tool call is in content, it should be used (thinking ignored for tool calls)
        let json = """
        {
            "role": "assistant",
            "content": "<tool_call>{\\"name\\": \\"ContentTool\\", \\"arguments\\": {}}</tool_call>",
            "thinking": "<tool_call>ThinkingTool<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        print("=== DEBUG: testToolCallInContentPriority ===")
        print("Content: '\(message.content)'")
        print("ToolCalls: \(String(describing: message.toolCalls))")
        print("============================================")

        // Content tool call should be used
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?.first?.function.name == "ContentTool")
    }

    // MARK: - containsToolCallPatterns Tests

    @Test("containsToolCallPatterns detects patterns")
    func testContainsToolCallPatterns() throws {
        print("=== DEBUG: testContainsToolCallPatterns ===")

        let testCases = [
            ("<tool_call>test</tool_call>", true),
            ("<function_call>test</function_call>", true),
            ("No tool calls here", false),
            ("<tool_call>WebFetch<arg_key>url</arg_key><arg_value>test</arg_value></tool_call>", true),
        ]

        for (content, expected) in testCases {
            let result = TextToolCallParser.containsToolCallPatterns(content)
            print("  '\(content.prefix(50))...' -> \(result) (expected: \(expected))")
            #expect(result == expected)
        }
        print("============================================")
    }

    // MARK: - Streaming Accumulation Logic Tests
    // These tests verify the logic used in OllamaLanguageModel.stream()

    @Test("Streaming: tool calls extracted from accumulated thinking")
    func testStreamingAccumulatedThinkingToolCalls() throws {
        // Simulate streaming accumulation scenario:
        // - nativeToolCalls is empty
        // - accumulatedContent is empty
        // - accumulatedThinking contains GLM-style tool call

        let nativeToolCalls: [ToolCall] = []
        let accumulatedContent = ""
        let accumulatedThinking = "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://example.com</arg_value></tool_call>"

        // This is the logic from OllamaLanguageModel.stream()
        let finalToolCalls: [ToolCall]
        let finalContent: String

        if !nativeToolCalls.isEmpty {
            finalToolCalls = nativeToolCalls
            finalContent = accumulatedContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedContent) {
            let parseResult = TextToolCallParser.parse(accumulatedContent)
            finalToolCalls = parseResult.toolCalls
            finalContent = parseResult.remainingContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedThinking) {
            // GLM models: tool calls in thinking field
            let parseResult = TextToolCallParser.parse(accumulatedThinking)
            finalToolCalls = parseResult.toolCalls
            finalContent = accumulatedContent
        } else {
            finalToolCalls = []
            finalContent = accumulatedContent
        }

        print("=== DEBUG: testStreamingAccumulatedThinkingToolCalls ===")
        print("finalToolCalls count: \(finalToolCalls.count)")
        print("finalContent: '\(finalContent)'")
        print("========================================================")

        #expect(finalToolCalls.count == 1, "Tool calls should be extracted from accumulated thinking")
        #expect(finalToolCalls.first?.function.name == "WebFetch")
        #expect(finalContent.isEmpty, "Content should remain empty")
    }

    @Test("Streaming: native tool calls take priority over thinking")
    func testStreamingNativeToolCallsPriority() throws {
        // Native tool calls should be used even if thinking also contains tool calls

        let nativeToolCalls = [
            ToolCall(function: ToolCall.FunctionCall(name: "NativeTool", arguments: ["key": "value"]))
        ]
        let accumulatedContent = ""
        let accumulatedThinking = "<tool_call>ThinkingTool<arg_key>url</arg_key><arg_value>test</arg_value></tool_call>"

        let finalToolCalls: [ToolCall]
        let finalContent: String

        if !nativeToolCalls.isEmpty {
            finalToolCalls = nativeToolCalls
            finalContent = accumulatedContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedContent) {
            let parseResult = TextToolCallParser.parse(accumulatedContent)
            finalToolCalls = parseResult.toolCalls
            finalContent = parseResult.remainingContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedThinking) {
            let parseResult = TextToolCallParser.parse(accumulatedThinking)
            finalToolCalls = parseResult.toolCalls
            finalContent = accumulatedContent
        } else {
            finalToolCalls = []
            finalContent = accumulatedContent
        }

        #expect(finalToolCalls.count == 1)
        #expect(finalToolCalls.first?.function.name == "NativeTool", "Native tool calls should take priority")
    }

    @Test("Streaming: content tool calls take priority over thinking")
    func testStreamingContentToolCallsPriority() throws {
        // Content tool calls should be used before checking thinking

        let nativeToolCalls: [ToolCall] = []
        let accumulatedContent = "<tool_call>{\"name\": \"ContentTool\", \"arguments\": {}}</tool_call>"
        let accumulatedThinking = "<tool_call>ThinkingTool<arg_key>url</arg_key><arg_value>test</arg_value></tool_call>"

        let finalToolCalls: [ToolCall]
        let finalContent: String

        if !nativeToolCalls.isEmpty {
            finalToolCalls = nativeToolCalls
            finalContent = accumulatedContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedContent) {
            let parseResult = TextToolCallParser.parse(accumulatedContent)
            finalToolCalls = parseResult.toolCalls
            finalContent = parseResult.remainingContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedThinking) {
            let parseResult = TextToolCallParser.parse(accumulatedThinking)
            finalToolCalls = parseResult.toolCalls
            finalContent = accumulatedContent
        } else {
            finalToolCalls = []
            finalContent = accumulatedContent
        }

        #expect(finalToolCalls.count == 1)
        #expect(finalToolCalls.first?.function.name == "ContentTool", "Content tool calls should take priority over thinking")
    }

    @Test("Streaming: no tool calls when all sources empty")
    func testStreamingNoToolCalls() throws {
        let nativeToolCalls: [ToolCall] = []
        let accumulatedContent = "Just regular text"
        let accumulatedThinking = "Just thinking, no tools"

        let finalToolCalls: [ToolCall]
        let finalContent: String

        if !nativeToolCalls.isEmpty {
            finalToolCalls = nativeToolCalls
            finalContent = accumulatedContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedContent) {
            let parseResult = TextToolCallParser.parse(accumulatedContent)
            finalToolCalls = parseResult.toolCalls
            finalContent = parseResult.remainingContent
        } else if TextToolCallParser.containsToolCallPatterns(accumulatedThinking) {
            let parseResult = TextToolCallParser.parse(accumulatedThinking)
            finalToolCalls = parseResult.toolCalls
            finalContent = accumulatedContent
        } else {
            finalToolCalls = []
            finalContent = accumulatedContent
        }

        #expect(finalToolCalls.isEmpty, "No tool calls should be found")
        #expect(finalContent == "Just regular text", "Content should be preserved")
    }
}
