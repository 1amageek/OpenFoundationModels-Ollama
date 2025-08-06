import Foundation
import OpenFoundationModels

// MARK: - Request Builder Protocol
internal protocol RequestBuilder: Sendable {
    func buildGenerateRequest(
        model: String,
        prompt: String,
        options: GenerationOptions?,
        stream: Bool,
        keepAlive: String?
    ) -> GenerateRequest
    
    func buildChatRequest(
        model: String,
        messages: [Message],
        options: GenerationOptions?,
        stream: Bool,
        keepAlive: String?,
        tools: [Tool]?
    ) -> ChatRequest
}

// MARK: - Default Request Builder
internal struct DefaultRequestBuilder: RequestBuilder {
    
    func buildGenerateRequest(
        model: String,
        prompt: String,
        options: GenerationOptions?,
        stream: Bool,
        keepAlive: String?
    ) -> GenerateRequest {
        return GenerateRequest(
            model: model,
            prompt: prompt,
            stream: stream,
            options: options?.toOllamaOptions(),
            keepAlive: keepAlive
        )
    }
    
    func buildChatRequest(
        model: String,
        messages: [Message],
        options: GenerationOptions?,
        stream: Bool,
        keepAlive: String?,
        tools: [Tool]?
    ) -> ChatRequest {
        return ChatRequest(
            model: model,
            messages: messages,
            stream: stream,
            options: options?.toOllamaOptions(),
            keepAlive: keepAlive,
            tools: tools
        )
    }
}

// MARK: - GenerationOptions Conversion
internal extension GenerationOptions {
    func toOllamaOptions() -> OllamaOptions {
        // Note: topP (top_p) is embedded in GenerationOptions.SamplingMode
        // but the mode structure is opaque, so we can't extract it directly.
        // Ollama will use its default topP value.
        
        return OllamaOptions(
            numPredict: maximumResponseTokens,
            temperature: temperature,
            topP: nil  // SamplingMode probabilityThreshold cannot be extracted
        )
    }
}

// MARK: - Message Conversion
internal extension Array where Element == Message {
    /// Convert from simple prompt to messages
    static func from(prompt: String) -> [Message] {
        return [Message(role: .user, content: prompt)]
    }
    
    /// Convert from Prompt object to messages
    static func from(prompt: Prompt) -> [Message] {
        let combinedText = prompt.description
        return [Message(role: .user, content: combinedText)]
    }
}

// MARK: - Chat Message Builder
internal struct ChatMessageBuilder {
    
    /// Build a system message
    static func system(_ content: String) -> Message {
        return Message(role: .system, content: content)
    }
    
    /// Build a user message
    static func user(_ content: String) -> Message {
        return Message(role: .user, content: content)
    }
    
    /// Build an assistant message
    static func assistant(_ content: String, toolCalls: [ToolCall]? = nil) -> Message {
        return Message(role: .assistant, content: content, toolCalls: toolCalls)
    }
    
    /// Build a tool response message
    static func tool(_ content: String) -> Message {
        return Message(role: .tool, content: content)
    }
    
    /// Build a think message (for reasoning models)
    static func think(_ content: String) -> Message {
        return Message(role: .think, content: content)
    }
}