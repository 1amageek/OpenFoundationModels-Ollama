import Foundation

/// Errors that can occur during configuration creation
public enum OllamaConfigurationError: Error, Sendable {
    case invalidURL(String)
}

/// Configuration for Ollama API
public struct OllamaConfiguration: Sendable {
    /// Default Ollama base URL
    /// - Note: This is a compile-time constant literal, guaranteed to be valid
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!

    /// Base URL for Ollama API (default: http://127.0.0.1:11434)
    public let baseURL: URL

    /// Request timeout in seconds
    public let timeout: TimeInterval

    /// Keep alive duration for models in memory (nil uses Ollama default of 5 minutes)
    public let keepAlive: String?

    /// Initialize Ollama configuration
    /// - Parameters:
    ///   - baseURL: Base URL for Ollama API
    ///   - timeout: Request timeout in seconds
    ///   - keepAlive: Keep alive duration (e.g., "5m", "1h", "-1" for indefinite)
    public init(
        baseURL: URL = OllamaConfiguration.defaultBaseURL,
        timeout: TimeInterval = 120.0,
        keepAlive: String? = nil
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.keepAlive = keepAlive
    }
}

// MARK: - Convenience Initializers
extension OllamaConfiguration {
    /// Initialize with custom host and port
    /// - Parameters:
    ///   - host: Hostname or IP address (default: "127.0.0.1")
    ///   - port: Port number (default: 11434)
    ///   - timeout: Request timeout in seconds (default: 120.0)
    /// - Returns: Configuration instance
    /// - Throws: OllamaConfigurationError.invalidURL if URL cannot be constructed
    public static func create(
        host: String = "127.0.0.1",
        port: Int = 11434,
        timeout: TimeInterval = 120.0
    ) throws -> OllamaConfiguration {
        let urlString = "http://\(host):\(port)"
        guard let url = URL(string: urlString) else {
            throw OllamaConfigurationError.invalidURL(urlString)
        }
        return OllamaConfiguration(baseURL: url, timeout: timeout)
    }
}
