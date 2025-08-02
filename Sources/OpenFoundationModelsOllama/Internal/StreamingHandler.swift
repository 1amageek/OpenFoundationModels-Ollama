import Foundation

/// Handler for Ollama's line-delimited JSON streaming format
internal struct StreamingHandler: Sendable {
    
    /// Process streaming data and extract response objects
    func processStreamData<T: Decodable>(_ data: Data, decoder: JSONDecoder) throws -> T? {
        // Skip empty data
        guard !data.isEmpty else {
            return nil
        }
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log the error for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Failed to decode JSON: \(jsonString)")
            }
            throw StreamingError.decodingError(error)
        }
    }
}

/// Advanced streaming handler with buffering support
internal actor AdvancedStreamingHandler {
    private var buffer: Data = Data()
    private let decoder: JSONDecoder
    
    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }
    
    /// Process a chunk of data and return complete JSON objects
    func processChunk<T: Decodable>(_ chunk: Data) throws -> [T] {
        buffer.append(chunk)
        var results: [T] = []
        
        // Process complete lines
        while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)
            
            // Skip empty lines
            if lineData.isEmpty {
                continue
            }
            
            do {
                let object = try decoder.decode(T.self, from: lineData)
                results.append(object)
            } catch {
                // Log but don't fail on individual line errors
                if let jsonString = String(data: lineData, encoding: .utf8) {
                    print("Failed to decode line: \(jsonString), error: \(error)")
                }
            }
        }
        
        return results
    }
    
    /// Get any remaining buffered data
    func getRemainingData() -> Data {
        return buffer
    }
    
    /// Reset the buffer
    func reset() {
        buffer = Data()
    }
}

// MARK: - Streaming Errors

internal enum StreamingError: Error, LocalizedError, Sendable {
    case decodingError(Error)
    case invalidFormat(String)
    case connectionLost
    
    var errorDescription: String? {
        switch self {
        case .decodingError(let error):
            return "Failed to decode streaming response: \(error.localizedDescription)"
        case .invalidFormat(let message):
            return "Invalid streaming format: \(message)"
        case .connectionLost:
            return "Connection lost during streaming"
        }
    }
}

// MARK: - Stream Collection Helpers

internal extension AsyncThrowingStream where Element == Data {
    /// Collect all data from the stream
    func collectAll() async throws -> Data {
        var result = Data()
        for try await chunk in self {
            result.append(chunk)
        }
        return result
    }
}

internal extension AsyncStream where Element == String {
    /// Collect all text from the stream
    func collectAll() async -> String {
        var result = ""
        for await chunk in self {
            result += chunk
        }
        return result
    }
}