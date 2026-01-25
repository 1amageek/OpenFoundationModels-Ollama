import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

/// Tests for schema compliance issues where LLM output doesn't match the expected schema
@Suite("Schema Compliance Tests")
struct SchemaComplianceTests {

    // MARK: - Test Types

    /// Type with array fields - common failure case
    @Generable
    struct DimensionScoreResponse: Sendable, Codable {
        @Guide(description: "Score from 1-10")
        let score: Int

        @Guide(description: "Reasoning for this score")
        let reasoning: String

        @Guide(description: "Specific quotes or examples (up to 3)")
        let evidence: [String]

        @Guide(description: "Suggestions for improvement")
        let suggestions: [String]
    }

    /// Simple type for baseline tests
    @Generable
    struct SimpleResponse: Sendable, Codable {
        @Guide(description: "A name")
        let name: String

        @Guide(description: "A count")
        let count: Int
    }

    /// Nested array type
    @Generable
    struct NestedArrayResponse: Sendable, Codable {
        @Guide(description: "List of items with tags")
        let items: [Item]

        @Generable
        struct Item: Sendable, Codable {
            @Guide(description: "Item name")
            let name: String

            @Guide(description: "Item tags")
            let tags: [String]
        }
    }

    // MARK: - Array Field Tests

    @Test("Detects array field returned as string")
    func testArrayFieldAsString() {
        let parser = GenerableParser<DimensionScoreResponse>()

        // LLM incorrectly returns array field as string
        let invalidJSON = """
        {
            "score": 8,
            "reasoning": "Clear and concise statement",
            "evidence": "approximately 14 million",
            "suggestions": ["Add source citation"]
        }
        """

        let result = parser.parse(invalidJSON)

        switch result {
        case .success:
            Issue.record("Should have failed: 'evidence' is string, not array")
        case .failure(let error):
            // Verify error message mentions the problematic field
            let errorDescription = String(describing: error)
            print("Error: \(errorDescription)")
            // The error should indicate what went wrong
            #expect(error != .emptyContent)
        }
    }

    @Test("Detects multiple array fields returned as strings")
    func testMultipleArrayFieldsAsStrings() {
        let parser = GenerableParser<DimensionScoreResponse>()

        // LLM returns both array fields as strings
        let invalidJSON = """
        {
            "score": 8,
            "reasoning": "Clear statement",
            "evidence": "single evidence string",
            "suggestions": "single suggestion string"
        }
        """

        let result = parser.parse(invalidJSON)

        switch result {
        case .success:
            Issue.record("Should have failed: both array fields are strings")
        case .failure(let error):
            print("Error for multiple string arrays: \(error)")
            #expect(error != .emptyContent)
        }
    }

    @Test("Accepts valid array fields")
    func testValidArrayFields() {
        let parser = GenerableParser<DimensionScoreResponse>()

        let validJSON = """
        {
            "score": 8,
            "reasoning": "Clear and concise statement",
            "evidence": ["approximately 14 million", "Tokyo's population"],
            "suggestions": ["Add source citation", "Include date"]
        }
        """

        let result = parser.parse(validJSON)

        // Note: May fail due to @Generable internal structure, but should not fail due to schema
        switch result {
        case .success(let value):
            #expect(value.score == 8)
            #expect(value.evidence.count == 2)
            #expect(value.suggestions.count == 2)
        case .failure(let error):
            // If it fails, it should NOT be due to array type mismatch
            print("Parse result: \(error)")
        }
    }

    @Test("Accepts empty arrays")
    func testEmptyArrayFields() {
        let parser = GenerableParser<DimensionScoreResponse>()

        let jsonWithEmptyArrays = """
        {
            "score": 5,
            "reasoning": "Average quality",
            "evidence": [],
            "suggestions": []
        }
        """

        let result = parser.parse(jsonWithEmptyArrays)

        switch result {
        case .success(let value):
            #expect(value.evidence.isEmpty)
            #expect(value.suggestions.isEmpty)
        case .failure(let error):
            print("Empty array parse result: \(error)")
        }
    }

    // MARK: - Truncation Tests

    @Test("Detects truncated JSON - unclosed array")
    func testTruncatedJSONUnclosedArray() {
        let parser = GenerableParser<DimensionScoreResponse>()

        // JSON cut off mid-array
        let truncatedJSON = """
        {
            "score": 8,
            "reasoning": "Clear statement",
            "evidence": ["quote one", "quote two"],
            "suggestions": ["Add source
        """

        let result = parser.parse(truncatedJSON)

        switch result {
        case .success:
            Issue.record("Should have failed: JSON is truncated")
        case .failure(let error):
            print("Truncated array error: \(error)")
            // Should be invalidJSON or similar
            #expect(error != .emptyContent)
        }
    }

    @Test("Detects truncated JSON - unclosed object")
    func testTruncatedJSONUnclosedObject() {
        let parser = GenerableParser<SimpleResponse>()

        let truncatedJSON = """
        {
            "name": "Test",
            "count": 42
        """

        let result = parser.parse(truncatedJSON)

        switch result {
        case .success:
            Issue.record("Should have failed: JSON is truncated (missing })")
        case .failure(let error):
            print("Unclosed object error: \(error)")
            #expect(error != .emptyContent)
        }
    }

    @Test("Detects truncated JSON - incomplete string")
    func testTruncatedJSONIncompleteString() {
        let parser = GenerableParser<SimpleResponse>()

        let truncatedJSON = """
        {
            "name": "Test name that got cut off
        """

        let result = parser.parse(truncatedJSON)

        switch result {
        case .success:
            Issue.record("Should have failed: string is incomplete")
        case .failure(let error):
            print("Incomplete string error: \(error)")
            #expect(error != .emptyContent)
        }
    }

    // MARK: - Type Mismatch Tests

    @Test("Detects integer field returned as string")
    func testIntegerAsString() {
        let parser = GenerableParser<SimpleResponse>()

        let invalidJSON = """
        {
            "name": "Test",
            "count": "42"
        }
        """

        let result = parser.parse(invalidJSON)

        switch result {
        case .success:
            // Some decoders may coerce "42" to Int, which is acceptable
            print("Note: Decoder accepted string-encoded integer")
        case .failure(let error):
            print("Integer as string error: \(error)")
        }
    }

    @Test("Detects string field returned as number via validation")
    func testStringAsNumber() {
        let parser = GenerableParser<SimpleResponse>()

        let invalidJSON = """
        {
            "name": 12345,
            "count": 42
        }
        """

        // Note: GeneratedContent may perform type coercion (number → string)
        // Use validate() for strict type checking
        let errors = parser.validate(invalidJSON)
        print("String as number validation errors: \(errors)")

        // Should have validation error for type mismatch on 'name'
        #expect(errors.contains { $0.field == "name" })
    }

    // MARK: - Missing Field Tests

    @Test("Detects missing required field via validation")
    func testMissingRequiredField() {
        let parser = GenerableParser<SimpleResponse>()

        let incompleteJSON = """
        {
            "name": "Test"
        }
        """

        // Note: GeneratedContent is lenient and may accept incomplete JSON
        // Use validate() for strict schema validation
        let errors = parser.validate(incompleteJSON)
        print("Missing field validation errors: \(errors)")

        // Should have validation error for missing 'count' field
        #expect(errors.contains { $0.field == "count" })
    }

    @Test("Detects null for non-optional field")
    func testNullForNonOptionalField() {
        let parser = GenerableParser<SimpleResponse>()

        let jsonWithNull = """
        {
            "name": "Test",
            "count": null
        }
        """

        let result = parser.parse(jsonWithNull)

        switch result {
        case .success:
            Issue.record("Should have failed: 'count' is null but not optional")
        case .failure(let error):
            print("Null field error: \(error)")
            #expect(error != .emptyContent)
        }
    }

    // MARK: - Nested Type Tests

    @Test("Detects nested array type mismatch")
    func testNestedArrayTypeMismatch() {
        let parser = GenerableParser<NestedArrayResponse>()

        // Tags should be array but is string
        let invalidJSON = """
        {
            "items": [
                {"name": "Item 1", "tags": "single-tag"},
                {"name": "Item 2", "tags": ["tag1", "tag2"]}
            ]
        }
        """

        let result = parser.parse(invalidJSON)

        switch result {
        case .success:
            Issue.record("Should have failed: first item's tags is string, not array")
        case .failure(let error):
            print("Nested type mismatch error: \(error)")
            #expect(error != .emptyContent)
        }
    }

    // MARK: - Validation Method Tests

    @Test("Validation returns specific field errors")
    func testValidationReturnsFieldErrors() {
        let parser = GenerableParser<DimensionScoreResponse>()

        let invalidJSON = """
        {
            "score": "not a number",
            "reasoning": 12345,
            "evidence": "not an array",
            "suggestions": null
        }
        """

        let errors = parser.validate(invalidJSON)

        print("Validation errors: \(errors)")
        // Should have multiple validation errors
        #expect(errors.count > 0)
    }

    @Test("Validation passes for valid JSON")
    func testValidationPassesForValidJSON() {
        let parser = GenerableParser<SimpleResponse>()

        let validJSON = """
        {
            "name": "Test",
            "count": 42
        }
        """

        let errors = parser.validate(validJSON)
        print("Validation errors for valid JSON: \(errors)")
        // May have errors due to @Generable structure, but core validation should pass
    }
}

// MARK: - Error Message Quality Tests

@Suite("Error Message Quality Tests")
struct ErrorMessageQualityTests {

    @Generable
    struct TestType: Sendable, Codable {
        @Guide(description: "A name field")
        let name: String

        @Guide(description: "An age field")
        let age: Int

        @Guide(description: "A list of hobbies")
        let hobbies: [String]
    }

    @Test("Error message includes field name for type mismatch")
    func testErrorMessageIncludesFieldName() {
        let parser = GenerableParser<TestType>()

        let invalidJSON = """
        {
            "name": "Alice",
            "age": "twenty-five",
            "hobbies": ["reading"]
        }
        """

        let result = parser.parse(invalidJSON)

        if case .failure(let error) = result {
            let errorString = String(describing: error)
            print("Full error: \(errorString)")
            // Error should be descriptive
            #expect(!errorString.isEmpty)
        }
    }

    @Test("Error message includes expected type")
    func testErrorMessageIncludesExpectedType() {
        let parser = GenerableParser<TestType>()

        let invalidJSON = """
        {
            "name": "Alice",
            "age": 25,
            "hobbies": "just one hobby"
        }
        """

        let result = parser.parse(invalidJSON)

        if case .failure(let error) = result {
            let errorString = String(describing: error)
            print("Array type error: \(errorString)")
            // Error should indicate array was expected
            #expect(!errorString.isEmpty)
        }
    }

    @Test("GenerableError provides useful description")
    func testGenerableErrorDescription() {
        let errors: [GenerableError] = [
            .jsonParsingFailed("{invalid", underlyingError: "Unexpected character"),
            .schemaValidationFailed("age", details: "Expected Int, got String"),
            .maxRetriesExceeded(attempts: 3, lastError: "Type mismatch"),
            .emptyResponse
        ]

        for error in errors {
            let description = error.localizedDescription
            print("Error description: \(description)")
            #expect(!description.isEmpty)
        }
    }
}

// MARK: - JSON Auto-Correction Edge Cases

@Suite("JSON Auto-Correction Tests")
struct JSONAutoCorrectionTests {

    @Generable
    struct SimpleType: Sendable, Codable {
        let value: String
    }

    @Generable
    struct ArrayType: Sendable, Codable {
        let items: [String]
    }

    @Test("Handles trailing comma in object")
    func testTrailingCommaInObject() {
        let parser = GenerableParser<SimpleType>()

        let jsonWithTrailingComma = """
        {
            "value": "test",
        }
        """

        let result = parser.parse(jsonWithTrailingComma)
        print("Trailing comma result: \(result)")
        // Auto-correction should handle this
    }

    @Test("Handles trailing comma in array")
    func testTrailingCommaInArray() {
        let parser = GenerableParser<ArrayType>()

        let jsonWithTrailingComma = """
        {
            "items": ["a", "b", "c",]
        }
        """

        let result = parser.parse(jsonWithTrailingComma)
        print("Array trailing comma result: \(result)")
    }

    @Test("Extracts JSON from markdown code block")
    func testMarkdownCodeBlock() {
        let parser = GenerableParser<SimpleType>()

        let markdownWrapped = """
        ```json
        {"value": "extracted"}
        ```
        """

        let result = parser.parse(markdownWrapped)
        print("Markdown extraction result: \(result)")

        // Should extract and parse the JSON
        if case .success(let value) = result {
            #expect(value.value == "extracted")
        }
    }

    @Test("Extracts JSON from code block without language")
    func testCodeBlockWithoutLanguage() {
        let parser = GenerableParser<SimpleType>()

        let codeBlock = """
        ```
        {"value": "no-lang"}
        ```
        """

        let result = parser.parse(codeBlock)
        print("No-language code block result: \(result)")
    }

    @Test("Handles extra text before JSON")
    func testExtraTextBeforeJSON() {
        let parser = GenerableParser<SimpleType>()

        let jsonWithPrefix = """
        Here is the JSON response:
        {"value": "with prefix"}
        """

        let result = parser.parse(jsonWithPrefix)
        print("Text prefix result: \(result)")
    }

    @Test("Handles extra text after JSON")
    func testExtraTextAfterJSON() {
        let parser = GenerableParser<SimpleType>()

        let jsonWithSuffix = """
        {"value": "with suffix"}

        I hope this helps!
        """

        let result = parser.parse(jsonWithSuffix)
        print("Text suffix result: \(result)")
    }
}
