import Foundation

/// HTTP client for Ollama API
public actor OllamaHTTPClient {
    private let session: URLSession
    private let configuration: OllamaConfiguration
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    public init(configuration: OllamaConfiguration) {
        self.configuration = configuration
        
        // Configure URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        self.session = URLSession(configuration: config)
        
        // Configure JSON decoder with date strategy
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // Fallback to standard ISO8601
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        
        self.encoder = JSONEncoder()
    }
    
    // MARK: - Public Methods
    
    /// Send a request and decode the response
    public func send<Request: Encodable, Response: Decodable>(
        _ request: Request,
        to endpoint: String
    ) async throws -> Response {
        let url = configuration.baseURL.appendingPathComponent(endpoint)
        
        var urlRequest = URLRequest(url: url)
        
        // Use GET for /api/tags endpoint, POST for others
        if endpoint == "/api/tags" && request is EmptyRequest {
            urlRequest.httpMethod = "GET"
        } else {
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if !(request is EmptyRequest) {
                urlRequest.httpBody = try encoder.encode(request)
                #if DEBUG
                // Debug: print the request body to verify think parameter is included
                if endpoint == "/api/chat",
                   let jsonData = urlRequest.httpBody,
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    // Only print first 500 chars to avoid log spam
                    let preview = jsonString.prefix(500)
                    print("[OllamaHTTPClient] Request body preview: \(preview)...")
                }
                #endif
            }
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaHTTPError.invalidResponse
            }
            
            if httpResponse.statusCode >= 400 {
                do {
                    let errorResponse = try decoder.decode(ErrorResponse.self, from: data)
                    throw errorResponse
                } catch is DecodingError {
                    #if DEBUG
                    if let responseText = String(data: data, encoding: .utf8) {
                        print("[OllamaHTTPClient] Failed to decode error response: \(responseText)")
                    }
                    #endif
                    throw OllamaHTTPError.statusError(httpResponse.statusCode, data)
                }
            }
            

            #if DEBUG
            // Debug: print response to see if thinking is separated
            if endpoint == "/api/chat",
               let jsonString = String(data: data, encoding: .utf8) {
                let preview = jsonString.prefix(500)
                print("[OllamaHTTPClient] Response preview: \(preview)...")
            }
            #endif
            return try decoder.decode(Response.self, from: data)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .cannotConnectToHost {
                throw OllamaHTTPError.connectionError("Ollama is not running at \(configuration.baseURL)")
            }
            throw OllamaHTTPError.networkError(error)
        } catch {
            throw error
        }
    }
    
    /// Stream a request and decode line-delimited JSON responses
    public func stream<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ request: Request,
        to endpoint: String
    ) -> AsyncThrowingStream<Response, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = configuration.baseURL.appendingPathComponent(endpoint)
                    
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    // Encode request body if it's not empty
                    let isEmptyRequest = type(of: request) == EmptyRequest.self
                    if !isEmptyRequest {
                        urlRequest.httpBody = try encoder.encode(request)
                    }
                    
                    let (asyncBytes, response) = try await session.bytes(for: urlRequest)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OllamaHTTPError.invalidResponse)
                        return
                    }
                    
                    if httpResponse.statusCode >= 400 {
                        // Collect error data
                        var errorData = Data()
                        for try await byte in asyncBytes {
                            errorData.append(byte)
                        }

                        do {
                            let errorResponse = try decoder.decode(ErrorResponse.self, from: errorData)
                            continuation.finish(throwing: errorResponse)
                        } catch is DecodingError {
                            #if DEBUG
                            if let responseText = String(data: errorData, encoding: .utf8) {
                                print("[OllamaHTTPClient] Failed to decode streaming error response: \(responseText)")
                            }
                            #endif
                            continuation.finish(throwing: OllamaHTTPError.statusError(httpResponse.statusCode, errorData))
                        }
                        return
                    }
                    
                    // Process streaming response
                    var buffer = Data()
                    
                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        
                        // Look for newline to process complete JSON objects
                        while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
                            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                            buffer.removeSubrange(0..<newlineRange.upperBound)
                            
                            // Skip empty lines
                            if lineData.isEmpty {
                                continue
                            }
                            
                            let response = try decoder.decode(Response.self, from: lineData)
                            continuation.yield(response)
                        }
                    }
                    
                    // Process any remaining data
                    if !buffer.isEmpty {
                        let response = try decoder.decode(Response.self, from: buffer)
                        continuation.yield(response)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - HTTP Errors

public enum OllamaHTTPError: Error, LocalizedError, Sendable {
    case invalidResponse
    case statusError(Int, Data?)
    case networkError(Error)
    case connectionError(String)
    case decodingError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response received from Ollama"
        case .statusError(let code, _):
            return "HTTP error with status code: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .connectionError(let message):
            return message
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}