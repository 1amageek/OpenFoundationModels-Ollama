import Testing
import Foundation
@testable import OpenFoundationModelsOllama

/// Tests for ThinkingMode encoding and decoding
@Suite("ThinkingMode Tests")
struct ThinkingModeTests {

    // MARK: - Encoding Tests

    @Test("ThinkingMode.enabled encodes to true")
    func testEnabledEncodesToTrue() throws {
        let mode = ThinkingMode.enabled
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "true")
    }

    @Test("ThinkingMode.disabled encodes to false")
    func testDisabledEncodesToFalse() throws {
        let mode = ThinkingMode.disabled
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "false")
    }

    @Test("ThinkingMode.effort(.high) encodes to 'high'")
    func testEffortHighEncodesToString() throws {
        let mode = ThinkingMode.effort(.high)
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "\"high\"")
    }

    @Test("ThinkingMode.effort(.medium) encodes to 'medium'")
    func testEffortMediumEncodesToString() throws {
        let mode = ThinkingMode.effort(.medium)
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "\"medium\"")
    }

    @Test("ThinkingMode.effort(.low) encodes to 'low'")
    func testEffortLowEncodesToString() throws {
        let mode = ThinkingMode.effort(.low)
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "\"low\"")
    }

    // MARK: - Decoding Tests

    @Test("true decodes to ThinkingMode.enabled")
    func testTrueDecodesToEnabled() throws {
        let json = "true".data(using: .utf8)!
        let decoder = JSONDecoder()
        let mode = try decoder.decode(ThinkingMode.self, from: json)
        #expect(mode == .enabled)
    }

    @Test("false decodes to ThinkingMode.disabled")
    func testFalseDecodesToDisabled() throws {
        let json = "false".data(using: .utf8)!
        let decoder = JSONDecoder()
        let mode = try decoder.decode(ThinkingMode.self, from: json)
        #expect(mode == .disabled)
    }

    @Test("'high' decodes to ThinkingMode.effort(.high)")
    func testHighDecodesToEffort() throws {
        let json = "\"high\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let mode = try decoder.decode(ThinkingMode.self, from: json)
        #expect(mode == .effort(.high))
    }

    @Test("'medium' decodes to ThinkingMode.effort(.medium)")
    func testMediumDecodesToEffort() throws {
        let json = "\"medium\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let mode = try decoder.decode(ThinkingMode.self, from: json)
        #expect(mode == .effort(.medium))
    }

    @Test("'low' decodes to ThinkingMode.effort(.low)")
    func testLowDecodesToEffort() throws {
        let json = "\"low\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let mode = try decoder.decode(ThinkingMode.self, from: json)
        #expect(mode == .effort(.low))
    }

    @Test("'true' string decodes to ThinkingMode.enabled")
    func testTrueStringDecodesToEnabled() throws {
        let json = "\"true\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let mode = try decoder.decode(ThinkingMode.self, from: json)
        #expect(mode == .enabled)
    }

    @Test("unknown string decodes to ThinkingMode.disabled")
    func testUnknownStringDecodesToDisabled() throws {
        let json = "\"unknown\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let mode = try decoder.decode(ThinkingMode.self, from: json)
        #expect(mode == .disabled)
    }

    // MARK: - ChatRequest Integration Tests

    @Test("ChatRequest with think parameter serializes correctly")
    func testChatRequestWithThink() throws {
        let request = ChatRequest(
            model: "gpt-oss:20b",
            messages: [Message(role: .user, content: "Hello")],
            stream: false,
            think: .enabled
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["model"] as? String == "gpt-oss:20b")
        #expect(json?["stream"] as? Bool == false)
        #expect(json?["think"] as? Bool == true)
    }

    @Test("ChatRequest without think parameter omits field")
    func testChatRequestWithoutThink() throws {
        let request = ChatRequest(
            model: "llama3.2",
            messages: [Message(role: .user, content: "Hello")],
            stream: false,
            think: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["model"] as? String == "llama3.2")
        #expect(json?["think"] == nil)
    }

    @Test("ChatRequest with effort level serializes correctly")
    func testChatRequestWithEffortLevel() throws {
        let request = ChatRequest(
            model: "gpt-oss:20b",
            messages: [Message(role: .user, content: "Hello")],
            stream: false,
            think: .effort(.high)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["think"] as? String == "high")
    }

    // MARK: - Equatable Tests

    @Test("ThinkingMode Equatable works correctly")
    func testEquatable() {
        #expect(ThinkingMode.enabled == ThinkingMode.enabled)
        #expect(ThinkingMode.disabled == ThinkingMode.disabled)
        #expect(ThinkingMode.effort(.high) == ThinkingMode.effort(.high))
        #expect(ThinkingMode.enabled != ThinkingMode.disabled)
        #expect(ThinkingMode.effort(.high) != ThinkingMode.effort(.low))
    }
}
