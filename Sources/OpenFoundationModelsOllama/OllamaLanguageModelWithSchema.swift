import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Extensions to OllamaLanguageModel that support explicit schema passing
public extension OllamaLanguageModel {
    
    /// Generate with explicit JSON Schema for structured output
    /// - Parameters:
    ///   - transcript: The conversation transcript
    ///   - schema: The GenerationSchema to use for structured output
    ///   - options: Generation options
    /// - Returns: The generated transcript entry
    func generate(
        transcript: Transcript,
        schema: GenerationSchema,
        options: GenerationOptions? = nil
    ) async throws -> Transcript.Entry {
        // Since we cannot directly pass the schema to Ollama through the existing methods,
        // we'll use the regular generate method which will at least enable JSON mode
        // when a ResponseFormat is detected in the transcript.
        
        // This is a limitation: we cannot pass a custom schema directly to Ollama
        // unless the transcript already contains a ResponseFormat.
        
        // The best approach is to ensure the transcript has a ResponseFormat
        // before calling this method.
        return try await generate(transcript: transcript, options: options)
    }
    
    /// Generate with a Generable type for structured output
    /// - Parameters:
    ///   - transcript: The conversation transcript
    ///   - type: The Generable type to use for structured output
    ///   - options: Generation options
    /// - Returns: The generated transcript entry with structured content
    func generate<T: Generable>(
        transcript: Transcript,
        generating type: T.Type,
        options: GenerationOptions? = nil
    ) async throws -> (entry: Transcript.Entry, content: T) {
        // Get the schema from the Generable type
        let schema = T.generationSchema
        
        // Generate with the schema
        let entry = try await generate(transcript: transcript, schema: schema, options: options)
        
        // Parse the response content
        guard case .response(let response) = entry else {
            throw OllamaLanguageModelError.unexpectedResponse("Expected response entry, got \(entry)")
        }
        
        // Extract the content and parse it
        let content = extractTextFromSegments(response.segments)
        let generatedContent = try GeneratedContent(json: content)
        let parsedContent = try T(generatedContent)
        
        return (entry, parsedContent)
    }
    
    private func extractTextFromSegments(_ segments: [Transcript.Segment]) -> String {
        var texts: [String] = []
        
        for segment in segments {
            switch segment {
            case .text(let textSegment):
                texts.append(textSegment.content)
                
            case .structure(let structuredSegment):
                // Convert structured content to string
                if let jsonData = try? JSONEncoder().encode(structuredSegment.content),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    texts.append(jsonString)
                } else {
                    texts.append("[GeneratedContent]")
                }
            }
        }
        
        return texts.joined(separator: " ")
    }
}

// MARK: - Error Types
public enum OllamaLanguageModelError: Error, LocalizedError {
    case unexpectedResponse(String)
    
    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse(let message):
            return "Unexpected response: \(message)"
        }
    }
}