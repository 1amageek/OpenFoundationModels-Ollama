import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

// MARK: - Test Configuration

public struct TestConfiguration {
    // Default test model (lightweight, fast)
    public static let defaultModel = "lfm2.5-thinking:latest"

    // Alternative models for testing
    public static let alternativeModels = [
        "gpt-oss:20b",
        "gpt-oss:120b",
        "gemma3n:latest"
    ]

    // Models with thinking capability
    public static let thinkingModels = [
        "lfm2.5-thinking:latest",
        "glm-4.7-flash:latest"
    ]
    
    // Timeout configurations
    public static let quickTimeout: TimeInterval = 10.0
    public static let standardTimeout: TimeInterval = 30.0
    public static let extendedTimeout: TimeInterval = 60.0
    
    // Test prompts
    public static let simplePrompt = "Answer in one word: What color is the sky?"
    public static let mathPrompt = "What is 2 + 2? Answer with just the number."
    public static let listPrompt = "List three colors:"
    public static let longPrompt = """
        Write a brief paragraph (about 50 words) explaining what Swift programming language is \
        and what it's used for.
        """
    
    // Default generation options
    public static let deterministicOptions = GenerationOptions(
        temperature: 0.1,
        maximumResponseTokens: 20
    )
    
    public static let creativeOptions = GenerationOptions(
        sampling: .random(probabilityThreshold: 0.9),
        temperature: 0.8,
        maximumResponseTokens: 100
    )
    
    public static let quickOptions = GenerationOptions(
        temperature: 0.5,
        maximumResponseTokens: 10
    )
}

// MARK: - Test Utilities

public struct TestUtilities {
    
    /// Check if Ollama is running and available
    public static func isOllamaRunning() async -> Bool {
        do {
            let config = OllamaConfiguration()
            let httpClient = OllamaHTTPClient(configuration: config)
            let _: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
            return true
        } catch {
            return false
        }
    }
    
    /// Check if Ollama and a specific model are available
    public static func checkPreconditions(modelName: String) async throws {
        guard await isOllamaRunning() else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        guard await isModelAvailable(modelName) else {
            throw TestSkip(reason: "Model \(modelName) not available")
        }
    }
    
    /// Check if a specific model is available
    public static func isModelAvailable(_ modelName: String) async -> Bool {
        guard await isOllamaRunning() else { return false }
        
        do {
            let config = OllamaConfiguration()
            let httpClient = OllamaHTTPClient(configuration: config)
            let response: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
            return response.models.contains { $0.name == modelName || $0.name.hasPrefix("\(modelName):") }
        } catch {
            return false
        }
    }
    
    /// Get list of available models
    public static func getAvailableModels() async -> [String] {
        guard await isOllamaRunning() else { return [] }
        
        do {
            let config = OllamaConfiguration()
            let httpClient = OllamaHTTPClient(configuration: config)
            let response: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
            return response.models.map { $0.name }
        } catch {
            return []
        }
    }
    
    /// Create a test model with default configuration
    public static func createTestModel(
        modelName: String = TestConfiguration.defaultModel
    ) -> OllamaLanguageModel {
        return OllamaLanguageModel(modelName: modelName)
    }
    
    /// Create a test model with custom configuration
    public static func createTestModel(
        modelName: String = TestConfiguration.defaultModel,
        host: String = "localhost",
        port: Int = 11434,
        timeout: TimeInterval = 120.0,
        keepAlive: String? = nil
    ) -> OllamaLanguageModel {
        let config = OllamaConfiguration(
            baseURL: URL(string: "http://\(host):\(port)")!,
            timeout: timeout,
            keepAlive: keepAlive
        )
        return OllamaLanguageModel(configuration: config, modelName: modelName)
    }
}

// MARK: - Test Assertions

public struct TestAssertions {
    
    /// Assert that a response contains expected content
    public static func assertResponseContains(
        _ response: String,
        expectedContent: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        for content in expectedContent {
            if !response.lowercased().contains(content.lowercased()) {
                return false
            }
        }
        return true
    }
    
    /// Assert that a response is within expected length
    public static func assertResponseLength(
        _ response: String,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        if let min = minLength, response.count < min {
            return false
        }
        if let max = maxLength, response.count > max {
            return false
        }
        return true
    }
    
    /// Assert that streaming produces expected number of chunks
    public static func assertStreamChunkCount(
        _ chunks: [String],
        minChunks: Int? = nil,
        maxChunks: Int? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        if let min = minChunks, chunks.count < min {
            return false
        }
        if let max = maxChunks, chunks.count > max {
            return false
        }
        return true
    }
}

// MARK: - Performance Metrics

public struct PerformanceMetrics {
    public let operation: String
    public let startTime: Date
    public var endTime: Date?
    public var additionalInfo: [String: Any] = [:]
    
    public init(operation: String) {
        self.operation = operation
        self.startTime = Date()
    }
    
    public mutating func complete() {
        self.endTime = Date()
    }
    
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    public var summary: String {
        var result = "Performance: \(operation)"
        if let duration = duration {
            result += " - Duration: \(String(format: "%.3f", duration))s"
        }
        for (key, value) in additionalInfo {
            result += " - \(key): \(value)"
        }
        return result
    }
}

// MARK: - Mock Responses

public struct MockResponses {
    public static let simpleResponse = "The sky is blue."
    public static let mathResponse = "4"
    public static let listResponse = "1. Red\n2. Blue\n3. Green"
    public static let errorResponse = ErrorResponse(error: "Model not found")
}

// MARK: - Test Skip Error

/// Error used to skip tests when preconditions are not met
public struct TestSkip: Error, CustomStringConvertible {
    public let reason: String
    
    public init(reason: String) {
        self.reason = reason
    }
    
    public var description: String { reason }
}

// MARK: - Environment Checks

public struct EnvironmentChecks {
    
    /// Check if running in CI environment
    public static var isCI: Bool {
        return ProcessInfo.processInfo.environment["CI"] != nil
    }
    
    /// Check if integration tests should be skipped
    public static var shouldSkipIntegrationTests: Bool {
        return ProcessInfo.processInfo.environment["SKIP_INTEGRATION_TESTS"] == "true"
    }
    
    /// Check if performance tests should be skipped
    public static var shouldSkipPerformanceTests: Bool {
        return ProcessInfo.processInfo.environment["SKIP_PERFORMANCE_TESTS"] == "true"
    }
    
    /// Get Ollama host from environment or use default
    public static var ollamaHost: String {
        return ProcessInfo.processInfo.environment["OLLAMA_HOST"] ?? "localhost"
    }
    
    /// Get Ollama port from environment or use default
    public static var ollamaPort: Int {
        if let portStr = ProcessInfo.processInfo.environment["OLLAMA_PORT"],
           let port = Int(portStr) {
            return port
        }
        return 11434
    }
}