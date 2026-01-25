import Testing
import Foundation
@testable import OpenFoundationModelsOllama

@Suite("TextToolCallParser Tests")
struct TextToolCallParserTests {

    // MARK: - Single Tool Call Tests

    @Test("Parse single tool_call tag with JSON")
    func testSingleToolCallTag() {
        let content = """
        <tool_call>{"name": "WebSearch", "arguments": {"query": "weather Tokyo"}}</tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "WebSearch")

        let args = result.toolCalls[0].function.arguments.dictionary
        #expect(args["query"] as? String == "weather Tokyo")
        #expect(result.remainingContent.isEmpty)
    }

    @Test("Parse tool_call with whitespace")
    func testToolCallWithWhitespace() {
        let content = """
        <tool_call>
            {"name": "GetWeather", "arguments": {"city": "London"}}
        </tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "GetWeather")
    }

    @Test("Parse function_call tag")
    func testFunctionCallTag() {
        let content = """
        <function_call>{"name": "calculate", "arguments": {"a": 1, "b": 2}}</function_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "calculate")
    }

    // MARK: - Multiple Tool Calls Tests

    @Test("Parse multiple tool_call tags")
    func testMultipleToolCalls() {
        let content = """
        <tool_call>{"name": "WebSearch", "arguments": {"query": "test1"}}</tool_call>
        <tool_call>{"name": "WebFetch", "arguments": {"url": "http://example.com"}}</tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 2)
        #expect(result.toolCalls[0].function.name == "WebSearch")
        #expect(result.toolCalls[1].function.name == "WebFetch")
    }

    // MARK: - Mixed Content Tests

    @Test("Parse tool_call with surrounding text")
    func testToolCallWithSurroundingText() {
        let content = """
        I will search for the information.
        <tool_call>{"name": "WebSearch", "arguments": {"query": "test"}}</tool_call>
        Let me process the results.
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "WebSearch")
        #expect(result.remainingContent.contains("I will search"))
        #expect(result.remainingContent.contains("Let me process"))
    }

    // MARK: - JSON Format Variations

    @Test("Parse OpenAI-style function format")
    func testOpenAIStyleFormat() {
        let content = """
        <tool_call>{"function": {"name": "test_tool", "arguments": {"param": "value"}}}</tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "test_tool")
    }

    @Test("Parse with type field")
    func testWithTypeField() {
        let content = """
        <tool_call>{"type": "function", "function": {"name": "typed_tool", "arguments": {}}}</tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "typed_tool")
    }

    // MARK: - No Tool Calls Tests

    @Test("Plain text without tool calls")
    func testPlainText() {
        let content = "This is a normal response without any tool calls."
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.isEmpty)
        #expect(result.remainingContent == content)
    }

    @Test("Empty content")
    func testEmptyContent() {
        let result = TextToolCallParser.parse("")

        #expect(result.toolCalls.isEmpty)
        #expect(result.remainingContent.isEmpty)
    }

    @Test("Invalid JSON in tool_call tag")
    func testInvalidJSON() {
        let content = "<tool_call>not valid json</tool_call>"
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.isEmpty)
    }

    @Test("Incomplete tool_call tag")
    func testIncompleteTag() {
        let content = "<tool_call>{'name': 'test'}"  // Missing closing tag
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.isEmpty)
    }

    // MARK: - Utility Method Tests

    @Test("containsToolCallPatterns detects patterns")
    func testContainsToolCallPatterns() {
        #expect(TextToolCallParser.containsToolCallPatterns("<tool_call>") == true)
        #expect(TextToolCallParser.containsToolCallPatterns("<function_call>") == true)
        #expect(TextToolCallParser.containsToolCallPatterns("plain text") == false)
        #expect(TextToolCallParser.containsToolCallPatterns("") == false)
    }

    // MARK: - Complex Arguments Tests

    @Test("Parse tool call with nested arguments")
    func testNestedArguments() {
        let content = """
        <tool_call>{"name": "ComplexTool", "arguments": {"config": {"nested": "value"}, "items": [1, 2, 3]}}</tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "ComplexTool")

        let args = result.toolCalls[0].function.arguments.dictionary
        #expect(args["config"] != nil)
        #expect(args["items"] != nil)
    }

    @Test("Parse tool call with empty arguments")
    func testEmptyArguments() {
        let content = """
        <tool_call>{"name": "NoArgsTask", "arguments": {}}</tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "NoArgsTask")
        #expect(result.toolCalls[0].function.arguments.dictionary.isEmpty)
    }

    @Test("Parse tool call without arguments field")
    func testMissingArgumentsField() {
        let content = """
        <tool_call>{"name": "SimpleTask"}</tool_call>
        """
        let result = TextToolCallParser.parse(content)

        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "SimpleTask")
        #expect(result.toolCalls[0].function.arguments.dictionary.isEmpty)
    }
}
