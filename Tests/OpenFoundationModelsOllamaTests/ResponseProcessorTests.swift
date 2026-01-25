import Testing
import Foundation
@testable import OpenFoundationModelsOllama

@Suite("ResponseProcessor Tests")
struct ResponseProcessorTests {

    let processor = ResponseProcessor()

    // MARK: - Native Tool Calls Tests

    @Test("Native tool_calls take highest priority")
    func testNativeToolCallsPriority() {
        let message = Message(
            role: .assistant,
            content: "<tool_call>{\"name\": \"ContentTool\", \"arguments\": {}}</tool_call>",
            toolCalls: [
                ToolCall(function: ToolCall.FunctionCall(name: "NativeTool", arguments: ["key": "value"]))
            ],
            thinking: "<tool_call>ThinkingTool<arg_key>k</arg_key><arg_value>v</arg_value></tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "NativeTool")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    // MARK: - Text-Based Tool Calls in Content

    @Test("Tool calls extracted from content")
    func testToolCallsFromContent() {
        let message = Message(
            role: .assistant,
            content: "<tool_call>{\"name\": \"WebSearch\", \"arguments\": {\"query\": \"test\"}}</tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebSearch")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    @Test("Multiple tool calls extracted from content")
    func testMultipleToolCallsFromContent() {
        let message = Message(
            role: .assistant,
            content: "<tool_call>{\"name\": \"search\", \"arguments\": {}}</tool_call>\n<tool_call>{\"name\": \"fetch\", \"arguments\": {}}</tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 2)
            #expect(toolCalls[0].function.name == "search")
            #expect(toolCalls[1].function.name == "fetch")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    // MARK: - Text-Based Tool Calls in Thinking

    @Test("Tool calls extracted from thinking field")
    func testToolCallsFromThinking() {
        let message = Message(
            role: .assistant,
            content: "",
            thinking: "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://example.com</arg_value></tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebFetch")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    @Test("Content tool calls take priority over thinking")
    func testContentPriorityOverThinking() {
        let message = Message(
            role: .assistant,
            content: "<tool_call>{\"name\": \"ContentTool\", \"arguments\": {}}</tool_call>",
            thinking: "<tool_call>ThinkingTool<arg_key>k</arg_key><arg_value>v</arg_value></tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "ContentTool")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    // MARK: - Content Fallback Tests

    @Test("Returns content when no tool calls")
    func testContentFallback() {
        let message = Message(
            role: .assistant,
            content: "Hello, world!"
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == "Hello, world!")
        } else {
            Issue.record("Expected content result")
        }
    }

    @Test("Returns thinking when content is empty")
    func testThinkingFallback() {
        let message = Message(
            role: .assistant,
            content: "",
            thinking: "Let me think about this..."
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == "Let me think about this...")
        } else {
            Issue.record("Expected content result from thinking fallback")
        }
    }

    @Test("Returns empty when nothing present")
    func testEmptyResult() {
        let message = Message(
            role: .assistant,
            content: ""
        )

        let result = processor.process(message)

        if case .empty = result {
            // Success
        } else {
            Issue.record("Expected empty result")
        }
    }

    // MARK: - GLM-Style Tool Call Format

    @Test("GLM-style XML tool call format in thinking")
    func testGLMStyleToolCallInThinking() {
        let message = Message(
            role: .assistant,
            content: "",
            thinking: "The page is cluttered. <tool_call>WebSearch<arg_key>query</arg_key><arg_value>Kyoto temples</arg_value></tool_call>"
        )

        let result = processor.process(message)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebSearch")
            let args = toolCalls[0].function.arguments.dictionary
            #expect(args["query"] as? String == "Kyoto temples")
        } else {
            Issue.record("Expected toolCalls result")
        }
    }

    // MARK: - Integration with Streaming Logic

    @Test("Simulates streaming accumulation scenario")
    func testStreamingScenario() {
        // Simulate the accumulated message at stream completion
        let accumulatedMessage = Message(
            role: .assistant,
            content: "",
            toolCalls: nil,
            thinking: "<tool_call>WebFetch<arg_key>url</arg_key><arg_value>https://kyoto.travel</arg_value></tool_call>"
        )

        let result = processor.process(accumulatedMessage)

        if case .toolCalls(let toolCalls) = result {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0].function.name == "WebFetch")
        } else {
            Issue.record("Expected toolCalls from thinking in streaming scenario")
        }
    }

    @Test("Thinking models output content in thinking field")
    func testThinkingModelContentInThinkingField() {
        // lfm2.5-thinking outputs to thinking field, not content
        let message = Message(
            role: .assistant,
            content: "",
            thinking: "Here is the response to your question about counting: 1, 2, 3"
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content.contains("1, 2, 3"))
        } else {
            Issue.record("Expected content from thinking field for thinking models")
        }
    }

    // MARK: - Think Tag Stripping Tests

    @Test("Strips <think> tags from content and returns remaining content")
    func testStripThinkTagsWithRemainingContent() {
        let message = Message(
            role: .assistant,
            content: "<think>Let me think about this...</think>{\"name\": \"Widget\", \"price\": 99}"
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == #"{"name": "Widget", "price": 99}"#)
        } else {
            Issue.record("Expected content result after stripping think tags")
        }
    }

    @Test("Extracts JSON from content that is all thinking")
    func testExtractJSONFromThinkingOnlyContent() {
        let message = Message(
            role: .assistant,
            content: "<think>I need to generate a product. Let me create {\"name\": \"Gadget\", \"price\": 199} as the output.</think>"
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == #"{"name": "Gadget", "price": 199}"#)
        } else {
            Issue.record("Expected JSON extracted from thinking content")
        }
    }

    @Test("Handles unclosed <think> tag")
    func testUnclosedThinkTag() {
        let message = Message(
            role: .assistant,
            content: "<think>I'm still thinking and the response was cut off"
        )

        let result = processor.process(message)

        // With unclosed think tag and no JSON, should return empty
        if case .empty = result {
            // Expected
        } else {
            Issue.record("Expected empty result for content that is just unclosed think tag")
        }
    }

    @Test("Content without think tags is returned as-is")
    func testContentWithoutThinkTags() {
        let message = Message(
            role: .assistant,
            content: #"{"name": "Product", "price": 50}"#
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == #"{"name": "Product", "price": 50}"#)
        } else {
            Issue.record("Expected content returned as-is")
        }
    }

    @Test("Mixed think tags and JSON - returns content after stripping")
    func testMixedThinkTagsAndJSON() {
        let message = Message(
            role: .assistant,
            content: """
                <think>The user wants a product JSON. I'll generate one now.</think>
                {"name": "Super Widget", "price": 299}
                """
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content.contains("Super Widget"))
            #expect(content.contains("299"))
            #expect(!content.contains("<think>"))
        } else {
            Issue.record("Expected content with think tags stripped")
        }
    }

    @Test("Thinking field with think tags stripped")
    func testThinkingFieldWithThinkTags() {
        let message = Message(
            role: .assistant,
            content: "",
            thinking: "<think>Processing...</think>The actual response is: Hello!"
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == "The actual response is: Hello!")
        } else {
            Issue.record("Expected content from thinking field with tags stripped")
        }
    }

    // MARK: - Orphaned </think> Tag Tests (Thinking Models)

    @Test("Extracts content after orphaned </think> tag")
    func testOrphanedThinkCloseTag() {
        // Pattern from lfm2.5-thinking when think: false is set
        let message = Message(
            role: .assistant,
            content: """
                Okay, the user wants me to generate a JSON object. Let me think about this...
                </think>
                {"name": "Widget", "price": 99}
                """
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == #"{"name": "Widget", "price": 99}"#)
        } else {
            Issue.record("Expected JSON after orphaned </think> tag")
        }
    }

    @Test("Strips <content> tags from response")
    func testStripContentTags() {
        // Pattern from models echoing prompts in <content> tags
        let message = Message(
            role: .assistant,
            content: "<content>User request here</content>{\"result\": \"success\"}"
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == #"{"result": "success"}"#)
        } else {
            Issue.record("Expected content with <content> tags stripped")
        }
    }

    @Test("Handles combined <content> and </think> patterns")
    func testCombinedContentAndThinkPatterns() {
        // Complex pattern from thinking models
        let message = Message(
            role: .assistant,
            content: """
                <content>Generate a product JSON now.</content>
                Okay, let me create the JSON...
                </think>
                {"name": "Gadget", "price": 199}
                """
        )

        let result = processor.process(message)

        if case .content(let content) = result {
            #expect(content == #"{"name": "Gadget", "price": 199}"#)
        } else {
            Issue.record("Expected JSON after complex pattern")
        }
    }
}
