import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

// MARK: - Retry Policy

/// Defines the retry behavior for Generable streaming
public struct RetryPolicy: Sendable {
    /// Maximum number of retry attempts
    public let maxAttempts: Int

    /// Whether to include error context in retry prompts
    public let includeErrorContext: Bool

    /// Delay between retries in seconds
    public let retryDelay: TimeInterval

    /// No retry (fail immediately)
    public static let none = RetryPolicy(maxAttempts: 0, includeErrorContext: false, retryDelay: 0)

    /// Default retry policy (3 attempts)
    public static let `default` = RetryPolicy(maxAttempts: 3, includeErrorContext: true, retryDelay: 0.5)

    /// Aggressive retry policy (5 attempts)
    public static let aggressive = RetryPolicy(maxAttempts: 5, includeErrorContext: true, retryDelay: 0.3)

    public init(maxAttempts: Int, includeErrorContext: Bool = true, retryDelay: TimeInterval = 0.5) {
        self.maxAttempts = maxAttempts
        self.includeErrorContext = includeErrorContext
        self.retryDelay = retryDelay
    }
}

// MARK: - Partial State

/// Represents the current state of partial generation
public struct PartialState<T: Generable & Sendable & Decodable>: Sendable {
    /// Accumulated raw content
    public let accumulatedContent: String

    /// Partially decoded value (if available)
    public let partialValue: T?

    /// Whether this is a complete, valid state
    public let isComplete: Bool

    /// Progress percentage (0.0 to 1.0) if determinable
    public let progress: Double?

    public init(
        accumulatedContent: String,
        partialValue: T? = nil,
        isComplete: Bool = false,
        progress: Double? = nil
    ) {
        self.accumulatedContent = accumulatedContent
        self.partialValue = partialValue
        self.isComplete = isComplete
        self.progress = progress
    }
}

// MARK: - Retry Context

/// Context information about a retry attempt
public struct RetryContext: Sendable {
    /// Current attempt number (1-based)
    public let attemptNumber: Int

    /// Maximum attempts allowed
    public let maxAttempts: Int

    /// Remaining attempts
    public var remainingAttempts: Int {
        max(0, maxAttempts - attemptNumber)
    }

    /// Error that triggered the retry
    public let error: GenerableError

    /// Content that was accumulated before failure
    public let failedContent: String

    public init(
        attemptNumber: Int,
        maxAttempts: Int,
        error: GenerableError,
        failedContent: String
    ) {
        self.attemptNumber = attemptNumber
        self.maxAttempts = maxAttempts
        self.error = error
        self.failedContent = failedContent
    }
}

// MARK: - Generable Error

/// Errors that can occur during Generable streaming
public enum GenerableError: Error, Sendable {
    /// JSON parsing failed
    case jsonParsingFailed(String, underlyingError: String)

    /// Schema validation failed
    case schemaValidationFailed(String, details: String)

    /// Stream was interrupted
    case streamInterrupted(String)

    /// Maximum retries exceeded
    case maxRetriesExceeded(attempts: Int, lastError: String)

    /// Connection or network error
    case connectionError(String)

    /// Model returned empty response
    case emptyResponse

    /// Generic error
    case unknown(String)

    public var localizedDescription: String {
        switch self {
        case .jsonParsingFailed(let content, let error):
            return "JSON parsing failed: \(error). Content: \(content.prefix(100))..."
        case .schemaValidationFailed(let field, let details):
            return "Schema validation failed for field '\(field)': \(details)"
        case .streamInterrupted(let reason):
            return "Stream interrupted: \(reason)"
        case .maxRetriesExceeded(let attempts, let lastError):
            return "Maximum retries exceeded (\(attempts) attempts). Last error: \(lastError)"
        case .connectionError(let message):
            return "Connection error: \(message)"
        case .emptyResponse:
            return "Model returned empty response"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }

    /// Whether this error is retryable
    public var isRetryable: Bool {
        switch self {
        case .jsonParsingFailed, .schemaValidationFailed, .emptyResponse:
            return true
        case .streamInterrupted, .connectionError:
            return true
        case .maxRetriesExceeded, .unknown:
            return false
        }
    }
}

// MARK: - Stream Result

/// Result type for Generable streaming operations
public enum GenerableStreamResult<T: Generable & Sendable & Decodable>: Sendable {
    /// Partial content received
    case partial(PartialState<T>)

    /// Retry is in progress
    case retrying(RetryContext)

    /// Successfully completed with full value
    case complete(T)

    /// Failed after all retries exhausted
    case failed(GenerableError)
}

// MARK: - Stream Options

/// Options for Generable streaming
public struct GenerableStreamOptions: Sendable {
    /// Retry policy to use
    public let retryPolicy: RetryPolicy

    /// Whether to yield partial values
    public let yieldPartialValues: Bool

    /// Minimum content length before attempting parse
    public let minContentForParse: Int

    /// Generation options
    public let generationOptions: GenerationOptions?

    /// Default options
    public static let `default` = GenerableStreamOptions(
        retryPolicy: .default,
        yieldPartialValues: true,
        minContentForParse: 10,
        generationOptions: nil
    )

    public init(
        retryPolicy: RetryPolicy = .default,
        yieldPartialValues: Bool = true,
        minContentForParse: Int = 10,
        generationOptions: GenerationOptions? = nil
    ) {
        self.retryPolicy = retryPolicy
        self.yieldPartialValues = yieldPartialValues
        self.minContentForParse = minContentForParse
        self.generationOptions = generationOptions
    }
}
