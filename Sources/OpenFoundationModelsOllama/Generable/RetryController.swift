import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Actor that manages retry logic for Generable streaming
public actor RetryController<T: Generable & Sendable> {
    /// The retry policy being used
    private let policy: RetryPolicy

    /// Current attempt count
    private var attemptCount: Int = 0

    /// History of errors encountered
    private var errorHistory: [GenerableError] = []

    /// Accumulated content from failed attempts (for context)
    private var failedContentHistory: [String] = []

    /// Whether retrying is still possible
    public var canRetry: Bool {
        attemptCount < policy.maxAttempts
    }

    /// Remaining retry attempts
    public var remainingAttempts: Int {
        max(0, policy.maxAttempts - attemptCount)
    }

    /// Current attempt number (1-based)
    public var currentAttempt: Int {
        attemptCount + 1
    }

    /// Last recorded error (for retry context)
    public var lastError: GenerableError? {
        errorHistory.last
    }

    /// Last failed content (for retry context)
    public var lastFailedContent: String? {
        failedContentHistory.last
    }

    public init(policy: RetryPolicy) {
        self.policy = policy
    }

    // MARK: - Public Methods

    /// Record a successful completion (resets state)
    public func recordSuccess() {
        attemptCount = 0
        errorHistory.removeAll()
        failedContentHistory.removeAll()
    }

    /// Record a failure and determine if retry should occur
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - failedContent: Content accumulated before failure
    /// - Returns: RetryContext if retry should proceed, nil if retries exhausted
    public func recordFailure(error: GenerableError, failedContent: String) -> RetryContext? {
        attemptCount += 1
        errorHistory.append(error)
        failedContentHistory.append(failedContent)

        guard canRetry && error.isRetryable else {
            return nil
        }

        return RetryContext(
            attemptNumber: attemptCount,
            maxAttempts: policy.maxAttempts,
            error: error,
            failedContent: failedContent
        )
    }

    /// Get the final error after all retries exhausted
    public func getFinalError() -> GenerableError {
        let lastErrorDesc = errorHistory.last?.localizedDescription ?? "Unknown error"
        return .maxRetriesExceeded(attempts: attemptCount, lastError: lastErrorDesc)
    }

    /// Get the last retry context (for building retry prompts)
    /// Returns nil if no failures have been recorded
    public func getLastRetryContext() -> RetryContext? {
        guard let error = errorHistory.last else {
            return nil
        }
        return RetryContext(
            attemptNumber: attemptCount,
            maxAttempts: policy.maxAttempts,
            error: error,
            failedContent: failedContentHistory.last ?? ""
        )
    }

    /// Build a retry prompt with error context
    public func buildRetryPrompt(originalPrompt: String, context: RetryContext) -> String {
        guard policy.includeErrorContext else {
            return originalPrompt
        }

        var prompt = originalPrompt

        // Add error context to help the model correct
        switch context.error {
        case .jsonParsingFailed(_, let underlyingError):
            prompt += "\n\n[Retry attempt \(context.attemptNumber)/\(context.maxAttempts)]\n"
            prompt += "Previous response was invalid JSON. Error: \(underlyingError)\n"
            prompt += "Please ensure your response is valid JSON that exactly matches the schema."

        case .schemaValidationFailed(let field, let details):
            prompt += "\n\n[Retry attempt \(context.attemptNumber)/\(context.maxAttempts)]\n"
            prompt += "Previous response failed schema validation for field '\(field)': \(details)\n"
            prompt += "Please correct the response to match the expected schema."

        case .emptyResponse:
            prompt += "\n\n[Retry attempt \(context.attemptNumber)/\(context.maxAttempts)]\n"
            prompt += "Previous response was empty. Please provide a valid JSON response."

        default:
            prompt += "\n\n[Retry attempt \(context.attemptNumber)/\(context.maxAttempts)]\n"
            prompt += "Please try again with a valid JSON response matching the schema."
        }

        return prompt
    }

    /// Get delay before retry
    public func getRetryDelay() -> TimeInterval {
        // Exponential backoff with jitter
        let baseDelay = policy.retryDelay
        let exponentialFactor = pow(1.5, Double(attemptCount - 1))
        let jitter = Double.random(in: 0.8...1.2)
        return baseDelay * exponentialFactor * jitter
    }

    /// Reset the controller for a new operation
    public func reset() {
        attemptCount = 0
        errorHistory.removeAll()
        failedContentHistory.removeAll()
    }

    // MARK: - State Inspection

    /// Get summary of retry attempts
    public func getSummary() -> RetrySummary {
        RetrySummary(
            totalAttempts: attemptCount,
            maxAttempts: policy.maxAttempts,
            errors: errorHistory.map { $0.localizedDescription },
            isExhausted: !canRetry
        )
    }
}

// MARK: - Retry Summary

/// Summary of retry attempts for debugging/logging
public struct RetrySummary: Sendable {
    public let totalAttempts: Int
    public let maxAttempts: Int
    public let errors: [String]
    public let isExhausted: Bool

    public var description: String {
        var desc = "Retry Summary: \(totalAttempts)/\(maxAttempts) attempts"
        if isExhausted {
            desc += " (exhausted)"
        }
        if !errors.isEmpty {
            desc += "\nErrors:\n" + errors.enumerated().map { "  \($0 + 1). \($1)" }.joined(separator: "\n")
        }
        return desc
    }
}
