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

    /// Default Harmony format instructions for gpt-oss models
    ///
    /// Placeholders:
    /// - `{{schema}}`: JSON schema will be inserted here
    /// - `{{properties}}`: Property names will be inserted here
    public static let defaultHarmonyInstructions = """
        # Response Formats

        ## StructuredResponse

        {{schema}}

        # Output Instructions

        CRITICAL: Your response MUST be a valid JSON object (starting with '{' and ending with '}').
        - The response must be a JSON OBJECT, not an array. Arrays can only be values inside properties.
        - DO NOT output a bare array like [...]. Always output {"propertyName": [...]} instead.
        - The response must include these properties: {{properties}}
        - DO NOT include markdown, code fences, or any prose.
        - DO NOT include any text before or after the JSON object.
        - Output the JSON directly in your response content, NOT in thinking.
        - The JSON must conform exactly to the StructuredResponse schema above.
        """

    /// Base URL for Ollama API (default: http://127.0.0.1:11434)
    public let baseURL: URL

    /// Request timeout in seconds
    public let timeout: TimeInterval

    /// Keep alive duration for models in memory (nil uses Ollama default of 5 minutes)
    public let keepAlive: String?

    /// Harmony format instructions for gpt-oss models
    ///
    /// Use placeholders:
    /// - `{{schema}}`: JSON schema will be inserted here
    /// - `{{properties}}`: Property names will be inserted here
    ///
    /// Example:
    /// ```swift
    /// let config = OllamaConfiguration(
    ///     harmonyInstructions: """
    ///     # Response Format
    ///     {{schema}}
    ///
    ///     # Instructions
    ///     Output valid JSON with properties: {{properties}}
    ///     """
    /// )
    /// ```
    public let harmonyInstructions: String

    /// Initialize Ollama configuration
    /// - Parameters:
    ///   - baseURL: Base URL for Ollama API
    ///   - timeout: Request timeout in seconds
    ///   - keepAlive: Keep alive duration (e.g., "5m", "1h", "-1" for indefinite)
    ///   - harmonyInstructions: Harmony format instructions for gpt-oss models
    public init(
        baseURL: URL = OllamaConfiguration.defaultBaseURL,
        timeout: TimeInterval = 120.0,
        keepAlive: String? = nil,
        harmonyInstructions: String = OllamaConfiguration.defaultHarmonyInstructions
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.keepAlive = keepAlive
        self.harmonyInstructions = harmonyInstructions
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