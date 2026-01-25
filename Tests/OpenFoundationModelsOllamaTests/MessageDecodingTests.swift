import Testing
import Foundation
@testable import OpenFoundationModelsOllama

@Suite("Message Self-Normalization Tests")
struct MessageDecodingTests {

    // MARK: - Native Tool Calls Tests

    @Test("Message with native tool_calls uses them directly")
    func testNativeToolCalls() throws {
        let json = """
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {
                    "function": {
                        "name": "get_weather",
                        "arguments": {"city": "Tokyo"}
                    }
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.role == .assistant)
        #expect(message.content == "")
        #expect(message.toolCalls != nil)
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?[0].function.name == "get_weather")
    }

    // MARK: - Text-Based Tool Call Extraction Tests

    @Test("Message extracts tool calls from text content")
    func testTextBasedToolCallExtraction() throws {
        let json = """
        {
            "role": "assistant",
            "content": "<tool_call>{\\"name\\": \\"WebSearch\\", \\"arguments\\": {\\"query\\": \\"weather Tokyo\\"}}</tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.role == .assistant)
        #expect(message.toolCalls != nil)
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?[0].function.name == "WebSearch")
        #expect(message.content.isEmpty || !message.content.contains("<tool_call>"))
    }

    @Test("Message extracts multiple tool calls from text content")
    func testMultipleTextBasedToolCalls() throws {
        let json = """
        {
            "role": "assistant",
            "content": "<tool_call>{\\"name\\": \\"search\\", \\"arguments\\": {\\"q\\": \\"test1\\"}}</tool_call>\\n<tool_call>{\\"name\\": \\"fetch\\", \\"arguments\\": {\\"url\\": \\"http://example.com\\"}}</tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.toolCalls != nil)
        #expect(message.toolCalls?.count == 2)
        #expect(message.toolCalls?[0].function.name == "search")
        #expect(message.toolCalls?[1].function.name == "fetch")
    }

    @Test("Message removes tool call tags from content")
    func testContentCleanup() throws {
        let json = """
        {
            "role": "assistant",
            "content": "I will search for that.\\n<tool_call>{\\"name\\": \\"WebSearch\\", \\"arguments\\": {\\"query\\": \\"test\\"}}</tool_call>\\nHere are the results."
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.toolCalls != nil)
        #expect(message.toolCalls?.count == 1)
        #expect(message.content.contains("I will search"))
        #expect(message.content.contains("Here are the results"))
        #expect(!message.content.contains("<tool_call>"))
        #expect(!message.content.contains("</tool_call>"))
    }

    // MARK: - No Tool Calls Tests

    @Test("Message without tool calls keeps content as-is")
    func testPlainTextContent() throws {
        let json = """
        {
            "role": "assistant",
            "content": "Hello, how can I help you today?"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.role == .assistant)
        #expect(message.content == "Hello, how can I help you today?")
        #expect(message.toolCalls == nil)
    }

    @Test("Message with empty content has no tool calls")
    func testEmptyContent() throws {
        let json = """
        {
            "role": "assistant",
            "content": ""
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.content == "")
        #expect(message.toolCalls == nil)
    }

    // MARK: - Native Tool Calls Priority Tests

    @Test("Native tool_calls take priority over text-based")
    func testNativeToolCallsPriority() throws {
        // If native tool_calls exist, don't parse content for text-based ones
        let json = """
        {
            "role": "assistant",
            "content": "<tool_call>{\\"name\\": \\"TextTool\\", \\"arguments\\": {}}</tool_call>",
            "tool_calls": [
                {
                    "function": {
                        "name": "NativeTool",
                        "arguments": {}
                    }
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?[0].function.name == "NativeTool")
        // Content should be preserved as-is when native tool_calls exist
        #expect(message.content.contains("<tool_call>"))
    }

    // MARK: - Thinking Content Tests

    @Test("Message preserves thinking content")
    func testThinkingContent() throws {
        let json = """
        {
            "role": "assistant",
            "content": "Final answer",
            "thinking": "Let me think about this..."
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.content == "Final answer")
        #expect(message.thinking == "Let me think about this...")
    }

    // MARK: - Role Tests

    @Test("Message decodes various roles correctly")
    func testRoleDecoding() throws {
        let roles = ["system", "user", "assistant", "tool"]

        for roleString in roles {
            let json = """
            {
                "role": "\(roleString)",
                "content": "test"
            }
            """

            let data = json.data(using: .utf8)!
            let message = try JSONDecoder().decode(Message.self, from: data)

            #expect(message.role.rawValue == roleString)
        }
    }

    @Test("Message defaults to assistant for unknown role")
    func testUnknownRoleDefaultsToAssistant() throws {
        let json = """
        {
            "role": "unknown_role",
            "content": "test"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.role == .assistant)
    }

    // MARK: - Function Call Format Tests

    @Test("Message extracts OpenAI-style function format from text")
    func testOpenAIStyleFunctionFormat() throws {
        let json = """
        {
            "role": "assistant",
            "content": "<tool_call>{\\"function\\": {\\"name\\": \\"test_tool\\", \\"arguments\\": {\\"param\\": \\"value\\"}}}</tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.toolCalls != nil)
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?[0].function.name == "test_tool")
    }

    @Test("Message extracts function_call tags")
    func testFunctionCallTags() throws {
        let json = """
        {
            "role": "assistant",
            "content": "<function_call>{\\"name\\": \\"calculate\\", \\"arguments\\": {\\"a\\": 1, \\"b\\": 2}}</function_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.toolCalls != nil)
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?[0].function.name == "calculate")
    }

    // MARK: - ChatResponse Integration Tests

    @Test("ChatResponse message is self-normalized")
    func testChatResponseMessageNormalization() throws {
        let json = """
        {
            "model": "llama3.2",
            "created_at": "2024-01-01T00:00:00Z",
            "message": {
                "role": "assistant",
                "content": "<tool_call>{\\"name\\": \\"get_time\\", \\"arguments\\": {}}</tool_call>"
            },
            "done": true
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(ChatResponse.self, from: data)

        #expect(response.message?.toolCalls != nil)
        #expect(response.message?.toolCalls?.count == 1)
        #expect(response.message?.toolCalls?[0].function.name == "get_time")
        #expect(response.message?.content.isEmpty == true || response.message?.content.contains("<tool_call>") == false)
    }
}
