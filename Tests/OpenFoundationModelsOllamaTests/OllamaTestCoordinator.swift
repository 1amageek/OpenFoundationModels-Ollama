import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

/// Coordinates access to Ollama server across all test suites.
/// This actor ensures that only one test accesses Ollama at a time,
/// preventing race conditions and connection issues during parallel test execution.
///
/// Usage:
/// ```swift
/// try await OllamaTestCoordinator.shared.withOllamaAccess {
///     // Your Ollama test code here
/// }
/// ```
public actor OllamaTestCoordinator {

    public static let shared = OllamaTestCoordinator()

    private var isAvailable: Bool?
    private var modelAvailability: [String: Bool] = [:]
    private let httpClient: OllamaHTTPClient

    private init() {
        self.httpClient = OllamaHTTPClient(configuration: OllamaConfiguration())
    }

    // MARK: - Availability Checks

    /// Check if Ollama server is running (cached)
    public func isOllamaRunning() async -> Bool {
        if let cached = isAvailable {
            return cached
        }

        do {
            let _: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
            isAvailable = true
            return true
        } catch {
            isAvailable = false
            return false
        }
    }

    /// Check if a specific model is available (cached)
    public func isModelAvailable(_ modelName: String) async -> Bool {
        if let cached = modelAvailability[modelName] {
            return cached
        }

        guard await isOllamaRunning() else {
            modelAvailability[modelName] = false
            return false
        }

        do {
            let response: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
            let available = response.models.contains {
                $0.name == modelName || $0.name.hasPrefix("\(modelName):")
            }
            modelAvailability[modelName] = available
            return available
        } catch {
            modelAvailability[modelName] = false
            return false
        }
    }

    /// Check preconditions and throw TestSkip if not met
    public func checkPreconditions(modelName: String = TestConfiguration.defaultModel) async throws {
        guard await isOllamaRunning() else {
            throw TestSkip(reason: "Ollama is not running")
        }

        guard await isModelAvailable(modelName) else {
            throw TestSkip(reason: "Model \(modelName) not available")
        }
    }

    // MARK: - Exclusive Access

    /// Execute a test with exclusive access to Ollama.
    /// This prevents multiple tests from hitting the server simultaneously.
    public func withOllamaAccess<T: Sendable>(
        modelName: String = TestConfiguration.defaultModel,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        // Check preconditions first
        try await checkPreconditions(modelName: modelName)

        // Execute with exclusive access (actor isolation ensures serialization)
        return try await operation()
    }

    /// Execute a test that may skip if Ollama is not available
    public func withOptionalOllamaAccess<T: Sendable>(
        modelName: String = TestConfiguration.defaultModel,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T? {
        guard await isOllamaRunning() else {
            return nil
        }

        guard await isModelAvailable(modelName) else {
            return nil
        }

        return try await operation()
    }

    // MARK: - Model Creation

    /// Create a test model
    public nonisolated func createModel(
        modelName: String = TestConfiguration.defaultModel
    ) -> OllamaLanguageModel {
        OllamaLanguageModel(modelName: modelName)
    }

    // MARK: - Cache Management

    /// Clear cached availability information
    public func clearCache() {
        isAvailable = nil
        modelAvailability.removeAll()
    }
}

// MARK: - Test Suite Markers

/// Marker trait for tests that require Ollama access.
/// Tests with this trait should use OllamaTestCoordinator for exclusive access.
public struct OllamaIntegrationTest {}
