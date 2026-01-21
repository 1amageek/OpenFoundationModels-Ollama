import Foundation
import OpenFoundationModels

/// Result of building a chat request
struct ChatRequestBuildResult: Sendable {
    let request: ChatRequest
    let modelStrategy: ModelStrategy
}

/// Builder for creating ChatRequest from Transcript
///
/// This struct consolidates the request building logic that was previously
/// duplicated between `generate()` and `stream()` methods.
struct ChatRequestBuilder: Sendable {
    let configuration: OllamaConfiguration
    let modelName: String

    /// The model strategy determined from the model name
    var modelStrategy: ModelStrategy {
        ModelStrategy.detect(modelName: modelName)
    }

    /// Build a ChatRequest from a Transcript
    /// - Parameters:
    ///   - transcript: The conversation transcript
    ///   - options: Optional generation options (uses transcript options if nil)
    ///   - streaming: Whether to enable streaming
    /// - Returns: A ChatRequestBuildResult containing the request and model strategy
    /// - Throws: TranscriptConverterError if tool extraction fails
    func build(
        transcript: Transcript,
        options: GenerationOptions?,
        streaming: Bool
    ) throws -> ChatRequestBuildResult {
        // Convert Transcript to Ollama messages
        var messages = TranscriptConverter.buildMessages(from: transcript)

        // Extract tools from transcript
        let tools = try TranscriptConverter.extractTools(from: transcript)

        // Extract response format (try full schema first, fallback to simple format)
        let responseFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
            ?? TranscriptConverter.extractResponseFormat(from: transcript)

        // Process response format according to model strategy
        let finalResponseFormat = modelStrategy.processResponseFormat(
            format: responseFormat,
            messages: &messages,
            harmonyInstructions: configuration.harmonyInstructions
        )

        // Use transcript options if not provided
        let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)

        // Build the request
        let request = ChatRequest(
            model: modelName,
            messages: messages,
            stream: streaming,
            options: finalOptions?.toOllamaOptions(),
            format: finalResponseFormat,
            keepAlive: configuration.keepAlive,
            tools: tools,
            think: modelStrategy.thinkingMode
        )

        return ChatRequestBuildResult(
            request: request,
            modelStrategy: modelStrategy
        )
    }

    /// Generate default JSON response for gpt-oss models when content is empty
    /// - Parameter format: The response format
    /// - Returns: A minimal valid JSON string based on the format
    func generateDefaultJSON(for format: ResponseFormat) -> String {
        switch format {
        case .jsonSchema(let container):
            // Create a minimal valid JSON based on schema
            let schemaDict = container.schema
            if let properties = schemaDict["properties"] as? [String: Any] {
                var defaultObject: [String: Any] = [:]

                for (key, value) in properties {
                    if let prop = value as? [String: Any],
                       let type = prop["type"] as? String {
                        switch type {
                        case "string":
                            defaultObject[key] = ""
                        case "integer", "number":
                            defaultObject[key] = 0
                        case "boolean":
                            defaultObject[key] = false
                        case "array":
                            defaultObject[key] = [] as [Any]
                        case "object":
                            defaultObject[key] = [:] as [String: Any]
                        default:
                            defaultObject[key] = NSNull()
                        }
                    }
                }

                if let jsonData = try? JSONSerialization.data(withJSONObject: defaultObject, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return jsonString
                }
            }
            return "{}"

        case .json:
            return "{}"

        case .text:
            return ""
        }
    }
}
