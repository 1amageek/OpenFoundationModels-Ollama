import Foundation

// MARK: - Response Handler Protocol
internal protocol ResponseHandler: Sendable {
    func extractContent(from response: GenerateResponse) -> String
    func extractContent(from response: ChatResponse) -> String?
    func extractStreamContent(from response: GenerateResponse) -> String?
    func extractStreamContent(from response: ChatResponse) -> String?
    func handleError(_ error: Error) -> Error
}

// MARK: - Default Response Handler
internal struct DefaultResponseHandler: ResponseHandler {
    
    func extractContent(from response: GenerateResponse) -> String {
        return response.response
    }
    
    func extractContent(from response: ChatResponse) -> String? {
        return response.message?.content
    }
    
    func extractStreamContent(from response: GenerateResponse) -> String? {
        // For streaming, only return content if not done
        return response.done ? nil : response.response
    }
    
    func extractStreamContent(from response: ChatResponse) -> String? {
        // For streaming, return message content
        return response.message?.content
    }
    
    func handleError(_ error: Error) -> Error {
        // Map errors to more user-friendly messages
        if let httpError = error as? OllamaHTTPError {
            return mapHTTPError(httpError)
        }
        
        if let errorResponse = error as? ErrorResponse {
            return mapErrorResponse(errorResponse)
        }
        
        return error
    }
    
    private func mapHTTPError(_ error: OllamaHTTPError) -> Error {
        switch error {
        case .connectionError(let message):
            return OllamaError.connectionFailed(message)
        case .statusError(404, _):
            return OllamaError.modelNotFound
        case .statusError(let code, _):
            return OllamaError.httpError(code)
        default:
            return error
        }
    }
    
    private func mapErrorResponse(_ error: ErrorResponse) -> Error {
        let errorMessage = error.error.lowercased()
        
        if errorMessage.contains("not found") || errorMessage.contains("pull") {
            return OllamaError.modelNotFound
        }
        
        if errorMessage.contains("context length") || errorMessage.contains("too long") {
            return OllamaError.contextLengthExceeded
        }
        
        return OllamaError.apiError(error.error)
    }
}

// MARK: - Ollama-specific Errors
public enum OllamaError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case modelNotFound
    case contextLengthExceeded
    case httpError(Int)
    case apiError(String)
    case streamingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return message
        case .modelNotFound:
            return "Model not found. Please run 'ollama pull <model-name>' first."
        case .contextLengthExceeded:
            return "Context length exceeded. Try reducing the prompt size."
        case .httpError(let code):
            return "HTTP error with status code: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Make sure Ollama is running with 'ollama serve'"
        case .modelNotFound:
            return "Pull the model with 'ollama pull <model-name>'"
        case .contextLengthExceeded:
            return "Use a smaller prompt or increase num_ctx in options"
        default:
            return nil
        }
    }
}

// MARK: - Response Statistics
internal struct ResponseStatistics: Sendable {
    let totalDuration: TimeInterval?
    let loadDuration: TimeInterval?
    let promptEvalDuration: TimeInterval?
    let evalDuration: TimeInterval?
    let promptTokenCount: Int?
    let responseTokenCount: Int?
    
    init(from response: GenerateResponse) {
        self.totalDuration = response.totalDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.loadDuration = response.loadDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.promptEvalDuration = response.promptEvalDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.evalDuration = response.evalDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.promptTokenCount = response.promptEvalCount
        self.responseTokenCount = response.evalCount
    }
    
    init(from response: ChatResponse) {
        self.totalDuration = response.totalDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.loadDuration = response.loadDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.promptEvalDuration = response.promptEvalDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.evalDuration = response.evalDuration.map { TimeInterval($0) / 1_000_000_000 }
        self.promptTokenCount = response.promptEvalCount
        self.responseTokenCount = response.evalCount
    }
}