import Testing
import Foundation
@testable import OpenFoundationModelsOllama

/// Tests for JSONExtractor utility
@Suite("JSONExtractor Tests")
struct JSONExtractorTests {

    // MARK: - Code Block Extraction Tests

    @Test("Extracts JSON from markdown code block with json tag")
    func testCodeBlockWithJsonTag() {
        let content = """
        Here is the response:
        ```json
        {"name": "Alice", "age": 30}
        ```
        I hope this helps!
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"name": "Alice", "age": 30}"#)
    }

    @Test("Extracts JSON from code block without language tag")
    func testCodeBlockWithoutLanguageTag() {
        let content = """
        ```
        {"key": "value"}
        ```
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"key": "value"}"#)
    }

    @Test("Extracts JSON from code block with JSON tag (uppercase)")
    func testCodeBlockWithUppercaseJsonTag() {
        let content = """
        ```JSON
        {"uppercase": true}
        ```
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"uppercase": true}"#)
    }

    @Test("Handles code block with extra whitespace")
    func testCodeBlockWithWhitespace() {
        let content = """
        ```json

        {"key": "value"}

        ```
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"key": "value"}"#)
    }

    // MARK: - Raw JSON Extraction Tests

    @Test("Extracts JSON with prefix text")
    func testJSONWithPrefixText() {
        let content = """
        Here is the response:
        {"result": "success"}
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"result": "success"}"#)
    }

    @Test("Extracts JSON with suffix text")
    func testJSONWithSuffixText() {
        let content = """
        {"result": "success"}

        I hope this helps!
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"result": "success"}"#)
    }

    @Test("Extracts JSON surrounded by text")
    func testJSONSurroundedByText() {
        let content = """
        Let me analyze this for you:
        {"analysis": "complete", "score": 85}
        Feel free to ask if you have questions!
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"analysis": "complete", "score": 85}"#)
    }

    @Test("Extracts nested JSON object")
    func testNestedJSONObject() {
        let content = """
        Response:
        {"outer": {"inner": {"deep": "value"}}}
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result?.contains("outer") == true)
        #expect(result?.contains("deep") == true)
    }

    // MARK: - Priority Tests (Code Block > Raw JSON)

    @Test("Prefers code block over raw JSON")
    func testCodeBlockPriority() {
        let content = """
        Some context {"ignore": "this"}
        ```json
        {"use": "this"}
        ```
        More text {"also": "ignore"}
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result == #"{"use": "this"}"#)
    }

    // MARK: - Invalid JSON Tests

    @Test("Returns nil for invalid JSON in code block")
    func testInvalidJSONInCodeBlock() {
        let content = """
        ```json
        {invalid json here}
        ```
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result == nil)
    }

    @Test("Returns nil for no JSON content")
    func testNoJSONContent() {
        let content = "This is just plain text without any JSON."

        let result = JSONExtractor.extract(from: content)

        #expect(result == nil)
    }

    @Test("Returns nil for empty code block")
    func testEmptyCodeBlock() {
        let content = """
        ```json
        ```
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result == nil)
    }

    @Test("Returns nil for truncated JSON")
    func testTruncatedJSON() {
        let content = """
        {"key": "value",
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result == nil)
    }

    // MARK: - Edge Cases

    @Test("Handles JSON with arrays")
    func testJSONWithArrays() {
        let content = """
        ```json
        {"items": ["a", "b", "c"], "count": 3}
        ```
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result?.contains("[") == true)
        #expect(result?.contains("]") == true)
    }

    @Test("Handles JSON with special characters in strings")
    func testJSONWithSpecialCharacters() {
        let content = """
        {"message": "Hello\\nWorld", "path": "C:\\\\Users"}
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
    }

    @Test("Handles JSON with unicode")
    func testJSONWithUnicode() {
        let content = """
        {"greeting": "こんにちは", "emoji": "😀"}
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(result?.contains("こんにちは") == true)
    }

    @Test("Handles multiline JSON")
    func testMultilineJSON() {
        let content = """
        {
            "name": "Test",
            "details": {
                "id": 123,
                "active": true
            },
            "tags": [
                "one",
                "two"
            ]
        }
        """

        let result = JSONExtractor.extract(from: content)

        #expect(result != nil)
        #expect(JSONExtractor.isValidJSON(result!) == true)
    }

    // MARK: - isValidJSON Tests

    @Test("isValidJSON returns true for valid object")
    func testIsValidJSONObject() {
        #expect(JSONExtractor.isValidJSON(#"{"key": "value"}"#) == true)
    }

    @Test("isValidJSON returns true for valid array")
    func testIsValidJSONArray() {
        #expect(JSONExtractor.isValidJSON(#"[1, 2, 3]"#) == true)
    }

    @Test("isValidJSON returns false for invalid JSON")
    func testIsValidJSONInvalid() {
        #expect(JSONExtractor.isValidJSON("{invalid}") == false)
        #expect(JSONExtractor.isValidJSON("not json") == false)
        #expect(JSONExtractor.isValidJSON("") == false)
    }

    // MARK: - Individual Method Tests

    @Test("extractFromCodeBlock returns nil when no code block")
    func testExtractFromCodeBlockNoMatch() {
        let content = #"{"direct": "json"}"#

        let result = JSONExtractor.extractFromCodeBlock(content)

        #expect(result == nil)
    }

    @Test("extractRawJSON returns nil for non-JSON content")
    func testExtractRawJSONNoMatch() {
        let content = "Plain text without JSON"

        let result = JSONExtractor.extractRawJSON(content)

        #expect(result == nil)
    }
}
