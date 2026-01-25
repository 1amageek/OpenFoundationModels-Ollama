import Testing
import Foundation
@testable import OpenFoundationModelsOllama

@Suite("Message Decoding Tests")
struct MessageDecodingTests {

    // MARK: - Basic Decoding Tests

    @Test("Message decodes basic fields correctly")
    func testBasicDecoding() throws {
        let json = """
        {
            "role": "assistant",
            "content": "Hello, world!"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.role == .assistant)
        #expect(message.content == "Hello, world!")
        #expect(message.toolCalls == nil)
        #expect(message.thinking == nil)
    }

    @Test("Message decodes empty content")
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

    // MARK: - Role Decoding Tests

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

    @Test("Message defaults to assistant for missing role")
    func testMissingRoleDefaultsToAssistant() throws {
        let json = """
        {
            "content": "test"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.role == .assistant)
    }

    // MARK: - Native Tool Calls Decoding Tests

    @Test("Message decodes native tool_calls")
    func testNativeToolCallsDecoding() throws {
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

    @Test("Message decodes multiple native tool_calls")
    func testMultipleNativeToolCallsDecoding() throws {
        let json = """
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {
                    "function": {
                        "name": "tool1",
                        "arguments": {}
                    }
                },
                {
                    "function": {
                        "name": "tool2",
                        "arguments": {"key": "value"}
                    }
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.toolCalls?.count == 2)
        #expect(message.toolCalls?[0].function.name == "tool1")
        #expect(message.toolCalls?[1].function.name == "tool2")
    }

    // MARK: - Thinking Content Decoding Tests

    @Test("Message decodes thinking content")
    func testThinkingContentDecoding() throws {
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

    @Test("Message with empty thinking")
    func testEmptyThinking() throws {
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
        #expect(message.thinking == "")
    }

    // MARK: - Tool Name Decoding Tests

    @Test("Message decodes tool_name for tool role")
    func testToolNameDecoding() throws {
        let json = """
        {
            "role": "tool",
            "content": "Result data",
            "tool_name": "get_weather"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        #expect(message.role == .tool)
        #expect(message.content == "Result data")
        #expect(message.toolName == "get_weather")
    }

    // MARK: - Pure Decoding Tests (No Normalization)
    // These tests verify that Message.init does NOT perform normalization
    // Normalization is handled by ResponseProcessor

    @Test("Message preserves text-based tool call content as-is")
    func testTextBasedToolCallsNotParsed() throws {
        let json = """
        {
            "role": "assistant",
            "content": "<tool_call>{\\"name\\": \\"WebSearch\\", \\"arguments\\": {\\"query\\": \\"test\\"}}</tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        // Content should be preserved as-is (no parsing)
        #expect(message.content.contains("<tool_call>"))
        // toolCalls should be nil (parsing happens in ResponseProcessor)
        #expect(message.toolCalls == nil)
    }

    @Test("Message preserves GLM-style tool calls in thinking as-is")
    func testGLMStyleToolCallsNotParsed() throws {
        let json = """
        {
            "role": "assistant",
            "content": "",
            "thinking": "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://example.com</arg_value></tool_call>"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)

        // Thinking should be preserved as-is
        #expect(message.thinking?.contains("<tool_call>") == true)
        // toolCalls should be nil
        #expect(message.toolCalls == nil)
    }

    // MARK: - ChatResponse Integration Tests

    @Test("ChatResponse message decoding")
    func testChatResponseMessageDecoding() throws {
        let json = """
        {
            "model": "llama3.2",
            "created_at": "2024-01-01T00:00:00Z",
            "message": {
                "role": "assistant",
                "content": "Hello"
            },
            "done": true
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(ChatResponse.self, from: data)

        #expect(response.model == "llama3.2")
        #expect(response.done == true)
        #expect(response.message?.content == "Hello")
    }

    @Test("ChatResponse with native tool_calls")
    func testChatResponseWithNativeToolCalls() throws {
        let json = """
        {
            "model": "llama3.2",
            "created_at": "2024-01-01T00:00:00Z",
            "message": {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "function": {
                            "name": "get_time",
                            "arguments": {}
                        }
                    }
                ]
            },
            "done": true
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(ChatResponse.self, from: data)

        #expect(response.message?.toolCalls?.count == 1)
        #expect(response.message?.toolCalls?[0].function.name == "get_time")
    }
}
