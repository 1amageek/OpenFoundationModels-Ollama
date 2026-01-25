import Testing
import Foundation
@testable import OpenFoundationModelsOllama

@Suite("Thinking Field Tool Call Tests")
struct ThinkingToolCallTests {

    let processor = ResponseProcessor()

    // MARK: - ResponseProcessor Tests for Thinking Field

    @Test("ResponseProcessor extracts tool call from thinking field (GLM format)")
    func testToolCallInThinkingField() throws {
        // Simulates glm-4.7-flash response format
        let message = Message(
            role: .assistant,
            content: "",
            thinking: "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://kyoto.travel/en/</arg_value></tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebFetch")
            let args = toolCalls[0].function.arguments.dictionary
            #expect(args["url"] as? String == "https://kyoto.travel/en/")
        } else {
            Issue.record("Expected toolCalls result from thinking field")
        }
    }

    @Test("ResponseProcessor extracts JSON tool call from thinking field")
    func testJSONToolCallInThinkingField() throws {
        let message = Message(
            role: .assistant,
            content: "",
            thinking: "Let me search for that. <tool_call>{\"name\": \"WebSearch\", \"arguments\": {\"query\": \"Kyoto temples\"}}</tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebSearch")
        } else {
            Issue.record("Expected toolCalls result from thinking field")
        }
    }

    @Test("Native tool_calls take priority over thinking")
    func testNativeToolCallsPriority() throws {
        let message = Message(
            role: .assistant,
            content: "",
            toolCalls: [
                ToolCall(function: ToolCall.FunctionCall(name: "WebFetch", arguments: ["url": "https://correct.com"]))
            ],
            thinking: "<tool_call>WebSearch<arg_key>query</arg_key><arg_value>wrong</arg_value></tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebFetch")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    // MARK: - GLM-style XML Format Tests (TextToolCallParser)

    @Test("Parse GLM-style tool call format")
    func testParseGLMStyleToolCall() throws {
        let content = "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://example.com</arg_value></tool_call>"

        let result = TextToolCallParser.parse(content)

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

        let result = TextToolCallParser.parse(content)

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

        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls.first?.function.name == "WebSearch")
    }

    // MARK: - ChatResponse with ResponseProcessor Tests

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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(ChatResponse.self, from: data)

        // Message decoding should preserve raw data
        #expect(response.message?.thinking?.contains("<tool_call>") == true)
        #expect(response.message?.toolCalls == nil) // Pure decoding

        // ResponseProcessor should extract tool calls
        if let message = response.message {
            let result = processor.process(message)
            if case .toolCalls(let toolCalls) = result {
                #expect(toolCalls.count == 1)
                #expect(toolCalls[0].function.name == "WebSearch")
            } else {
                Issue.record("Expected toolCalls from ResponseProcessor")
            }
        }
    }

    // MARK: - Edge Cases

    @Test("Empty thinking field")
    func testEmptyThinkingField() throws {
        let message = Message(
            role: .assistant,
            content: "Hello",
            thinking: ""
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == "Hello")
        } else {
            Issue.record("Expected content result")
        }
    }

    @Test("Thinking field with no tool calls")
    func testThinkingFieldWithNoToolCalls() throws {
        let message = Message(
            role: .assistant,
            content: "Here's the answer",
            thinking: "Let me think about this... The user wants to know about Kyoto."
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == "Here's the answer")
        } else {
            Issue.record("Expected content result")
        }
    }

    @Test("Tool call in content takes priority over thinking")
    func testToolCallInContentPriority() throws {
        let message = Message(
            role: .assistant,
            content: "<tool_call>{\"name\": \"ContentTool\", \"arguments\": {}}</tool_call>",
            thinking: "<tool_call>ThinkingTool<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "ContentTool")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    // MARK: - containsToolCallPatterns Tests

    @Test("containsToolCallPatterns detects patterns")
    func testContainsToolCallPatterns() throws {
        let testCases = [
            ("<tool_call>test</tool_call>", true),
            ("<function_call>test</function_call>", true),
            ("No tool calls here", false),
            ("<tool_call>WebFetch<arg_key>url</arg_key><arg_value>test</arg_value></tool_call>", true),
        ]

        for (content, expected) in testCases {
            let result = TextToolCallParser.containsToolCallPatterns(content)
            #expect(result == expected, "Pattern detection failed for: \(content)")
        }
    }

    // MARK: - Streaming Accumulation Logic Tests
    // These tests verify the logic used in OllamaLanguageModel.stream()
    // Using ResponseProcessor for consistency

    @Test("Streaming: tool calls extracted from accumulated thinking")
    func testStreamingAccumulatedThinkingToolCalls() throws {
        // Simulate streaming accumulation scenario
        let accumulatedMessage = Message(
            role: .assistant,
            content: "",
            toolCalls: nil,
            thinking: "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://example.com</arg_value></tool_call>"
        )

        let result = processor.process(accumulatedMessage)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebFetch")
        } else {
            Issue.record("Expected toolCalls from accumulated thinking")
        }
    }

    @Test("Streaming: native tool calls take priority over thinking")
    func testStreamingNativeToolCallsPriority() throws {
        let accumulatedMessage = Message(
            role: .assistant,
            content: "",
            toolCalls: [
                ToolCall(function: ToolCall.FunctionCall(name: "NativeTool", arguments: ["key": "value"]))
            ],
            thinking: "<tool_call>ThinkingTool<arg_key>url</arg_key><arg_value>test</arg_value></tool_call>"
        )

        let result = processor.process(accumulatedMessage)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "NativeTool")
        } else {
            Issue.record("Expected native toolCalls")
        }
    }

    @Test("Streaming: content tool calls take priority over thinking")
    func testStreamingContentToolCallsPriority() throws {
        let accumulatedMessage = Message(
            role: .assistant,
            content: "<tool_call>{\"name\": \"ContentTool\", \"arguments\": {}}</tool_call>",
            thinking: "<tool_call>ThinkingTool<arg_key>url</arg_key><arg_value>test</arg_value></tool_call>"
        )

        let result = processor.process(accumulatedMessage)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "ContentTool")
        } else {
            Issue.record("Expected content toolCalls")
        }
    }

    @Test("Streaming: no tool calls when all sources empty")
    func testStreamingNoToolCalls() throws {
        let accumulatedMessage = Message(
            role: .assistant,
            content: "Just regular text",
            thinking: "Just thinking, no tools"
        )

        let result = processor.process(accumulatedMessage)

        if case .content(let content) = result {
            #expect(content == "Just regular text")
        } else {
            Issue.record("Expected content result")
        }
    }
}
