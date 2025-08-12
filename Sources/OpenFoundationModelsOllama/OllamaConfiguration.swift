import Foundation

/// Configuration for Ollama API
public struct OllamaConfiguration: Sendable {
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
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
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
    public static func create(host: String = "127.0.0.1", port: Int = 11434, timeout: TimeInterval = 120.0) -> OllamaConfiguration {
        return OllamaConfiguration(
            baseURL: URL(string: "http://\(host):\(port)")!,
            timeout: timeout
        )
    }
}