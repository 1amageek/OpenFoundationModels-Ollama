# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenFoundationModels-Ollama is a Swift package that provides an Ollama implementation of the LanguageModel protocol from the OpenFoundationModels framework. It enables the use of Ollama's locally-hosted models through Apple's Foundation Models API interface.

## Current Implementation Status (2025-12-27)

### ✅ Transcript-Based Architecture
The implementation has been updated to support the new Transcript-based LanguageModel protocol from OpenFoundationModels:

- **Protocol Compliance**: Fully implements `generate(transcript:options:)` and `stream(transcript:options:)` methods
- **TranscriptConverter**: Converts OpenFoundationModels Transcript to Ollama API formats
- **Tool Support**: Automatically extracts and converts ToolDefinitions from Transcript.Instructions
- **Complete History**: Handles all Transcript.Entry types (instructions, prompt, response, toolCalls, toolOutput)

### ✅ Generable Streaming with Retry
Robust support for `@Generable` types with automatic retry on parse failures:

- **RetryPolicy**: Configurable retry behavior (maxAttempts, delay, error context)
- **Error Context in Retry**: Failed content and error details are included in retry prompts
- **Partial State Tracking**: Monitor generation progress with `PartialState<T>`
- **JSON Auto-Correction**: Automatic fix for common JSON issues (markdown blocks, trailing commas)

### Key Components

1. **OllamaLanguageModel**
   - Implements Transcript-based LanguageModel protocol
   - Uses `/api/chat` endpoint primarily for better feature support
   - Automatic tool extraction from Transcript
   - Extension methods for Generable streaming with retry

2. **TranscriptConverter**
   - `buildMessages(from: Transcript)` → Ollama Messages
   - `extractTools(from: Transcript)` → Ollama Tools
   - `extractResponseFormat(from: Transcript)` → Response format (with full schema)
   - `extractOptions(from: Transcript)` → Generation options

3. **Generable Components** (Sources/OpenFoundationModelsOllama/Generable/)
   - `GenerableTypes.swift`: Core types (RetryPolicy, PartialState, RetryContext, GenerableError)
   - `RetryController.swift`: Actor-based retry management with error history
   - `GenerableParser.swift`: JSON parsing with auto-correction and schema validation
   - `GenerableStreamSession.swift`: Streaming session with automatic retry

4. **API Usage**
   - Primary endpoint: `/api/chat` (supports tools, better context handling)
   - Fallback: `/api/generate` (simple completions, rarely used now)

## Build and Test Commands

```bash
# Build the package
swift build

# Run all tests
swift test

# Run specific test suite
swift test --filter "TranscriptTests"

# Run tests with verbose output
swift test --verbose

# Clean build artifacts
swift package clean

# Update dependencies
swift package update
```

## Architecture Overview

### Core Components
- **OllamaLanguageModel**: Main class implementing the LanguageModel protocol (Transcript-based)
- **OllamaConfiguration**: Configuration for API endpoint (default: http://localhost:11434)
- **TranscriptConverter**: Converts Transcript to Ollama API formats

### API Layer
- **OllamaHTTPClient**: Handles HTTP communication with Ollama API
- **OllamaAPITypes**: Request/response type definitions matching Ollama's API format

### Internal Processing
- **RequestBuilders**: Legacy support for message building (mostly deprecated)
- **ResponseHandlers**: Processes Ollama's streaming JSON responses
- **StreamingHandler**: Handles line-delimited JSON streaming format

## Transcript Processing

### Transcript.Entry Mapping

| Transcript Entry | Ollama Message | Notes |
|-----------------|----------------|-------|
| `.instructions(Instructions)` | `role: "system"` | Extracts text from segments, tools from toolDefinitions |
| `.prompt(Prompt)` | `role: "user"` | Includes options and responseFormat |
| `.response(Response)` | `role: "assistant"` | Extracts text from segments |
| `.toolCalls(ToolCalls)` | `role: "assistant"` with tool_calls | Converts to Ollama tool call format |
| `.toolOutput(ToolOutput)` | `role: "tool"` | Tool execution results |

### Example Transcript Processing

```swift
// Input Transcript
var transcript = Transcript()
transcript.append(.instructions(Instructions(
    segments: [.text("You are a helpful assistant")],
    toolDefinitions: [weatherTool]
)))
transcript.append(.prompt(Prompt(
    segments: [.text("What's the weather?")],
    options: GenerationOptions(temperature: 0.7)
)))

// Converted to Ollama Messages
[
    Message(role: .system, content: "You are a helpful assistant"),
    Message(role: .user, content: "What's the weather?")
]
// Plus extracted tools array
```

## Ollama API Specifics

### Key Differences from OpenAI:
1. **No Authentication**: Ollama runs locally, no API keys required
2. **Different Endpoints**: 
   - `/api/chat` for conversations with tool support (PRIMARY)
   - `/api/generate` for simple completions (LEGACY)
   - `/api/tags` to list available models
3. **Response Format**: Line-delimited JSON instead of Server-Sent Events
4. **Model Names**: Format is `model:tag` (e.g., "llama3.2:latest")

### API Endpoints

#### 1. Chat Endpoint `/api/chat` (PRIMARY)
Now the main endpoint used for all generation requests.

Request:
```json
{
  "model": "llama3.2",
  "messages": [
    {"role": "system", "content": "You are helpful"},
    {"role": "user", "content": "Hello"}
  ],
  "tools": [...],  // Optional, extracted from Transcript
  "stream": true,
  "options": {...}
}
```

#### 2. Generate Endpoint `/api/generate` (LEGACY)
Rarely used now, only for backwards compatibility.

### Tool Calling with Transcript

Tools are automatically extracted from `Transcript.Instructions.toolDefinitions`:

```swift
// In Transcript
let toolDef = Transcript.ToolDefinition(
    name: "get_weather",
    description: "Get weather",
    parameters: schema
)

// Automatically converted to Ollama format
{
  "type": "function",
  "function": {
    "name": "get_weather",
    "description": "Get weather",
    "parameters": {...}
  }
}
```

### Streaming Response Format
Each line is a complete JSON object:
```json
{"model":"llama3.2","message":{"role":"assistant","content":"Hello"},"done":false}
{"model":"llama3.2","message":{"role":"assistant","content":" there"},"done":false}
{"model":"llama3.2","message":{"role":"assistant","content":"!"},"done":true}
```

## Development Notes

### Testing with Ollama:
1. Ensure Ollama is running: `ollama serve`
2. Pull required models: `ollama pull llama3.2`
3. Check available models: `ollama list`
4. Test connection: `curl http://localhost:11434/api/tags`

### Current Limitations:

1. **GenerationSchema Parameters**: 
   - GenerationSchema's internal structure is not fully accessible
   - Tool parameters are simplified to basic object schema
   - Future improvement needed for full schema conversion

2. **Response Format**:
   - ResponseFormat from Transcript is simplified to JSON/text
   - Full schema-based formatting not yet implemented

3. **Think Feature**:
   - Think role messages not yet extracted from Transcript
   - Would require Transcript extension to support

### Implementation Considerations:

1. **Transcript Processing**:
   - Complete conversation history is built from Transcript
   - Tools are extracted once from Instructions
   - Options can come from Prompt or method parameter

2. **Error Handling**:
   - Connection errors when Ollama isn't running
   - Model not found errors (need to pull first)
   - Graceful degradation when tools aren't supported

3. **Performance**:
   - Local inference speed depends on hardware
   - First request may be slow (model loading)
   - Use `keep_alive` parameter to control model retention

4. **isAvailable Property**:
   - Always returns `true` by design
   - The `LanguageModel` protocol requires a synchronous `Bool` property
   - Ollama runs locally, so async availability checks would block or require complex caching
   - Actual availability is validated when `generate` or `stream` is called
   - If Ollama is not running, these methods throw appropriate errors

## Tool Calling Support

### Overview
The implementation fully supports Ollama's tool calling (function calling) feature, enabling models to request execution of specific functions during conversations.

### Tool Definition
Tools are automatically extracted from `Transcript.Instructions.toolDefinitions`:

```swift
// Define a tool in Transcript
let weatherTool = Transcript.ToolDefinition(
    name: "get_weather",
    description: "Get current weather for a location",
    parameters: weatherSchema
)

// Add to instructions
var transcript = Transcript()
transcript.append(.instructions(Instructions(
    segments: [.text("You are a helpful assistant")],
    toolDefinitions: [weatherTool]
)))
```

### Tool Call Handling
When the model decides to use a tool, it returns tool calls in the response:

```swift
// The model returns tool calls as JSON
let response = try await model.generate(transcript: transcript)
// Response format: {"tool_calls": [{"type": "tool_call", "name": "get_weather", "arguments": {...}}]}
```

### Sending Tool Results
Tool execution results are sent back through the Transcript:

```swift
// Add tool output to transcript
transcript.append(.toolOutput(ToolOutput(
    toolName: "get_weather",
    segments: [.text("11 degrees celsius, partly cloudy")]
)))

// Continue conversation with tool result
let finalResponse = try await model.generate(transcript: transcript)
```

### Message Format
The implementation correctly handles Ollama's tool message format:
- Tool calls: Assistant messages with `tool_calls` array
- Tool results: Tool role messages with `tool_name` field

### Testing
Comprehensive tests are included for:
- Tool definition encoding/decoding
- Tool call response parsing
- Tool message round-trip encoding
- Integration tests with actual Ollama API

## Generable Streaming with Retry

### Overview
The implementation provides robust support for `@Generable` types with automatic retry when JSON parsing or schema validation fails. This is essential for reliable structured output generation.

### Core Types

```swift
// RetryPolicy - Configure retry behavior
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int           // Maximum retry attempts
    public let includeErrorContext: Bool  // Include error details in retry prompt
    public let retryDelay: TimeInterval   // Delay between retries

    public static let none = RetryPolicy(maxAttempts: 0)
    public static let `default` = RetryPolicy(maxAttempts: 3)
    public static let aggressive = RetryPolicy(maxAttempts: 5)
}

// GenerableStreamResult - Stream output types
public enum GenerableStreamResult<T: Generable & Sendable & Decodable>: Sendable {
    case partial(PartialState<T>)   // Partial content received
    case retrying(RetryContext)     // Retry in progress
    case complete(T)                // Successfully completed
    case failed(GenerableError)     // Failed after all retries
}
```

### Usage Examples

#### Non-Streaming Generation with Retry
```swift
@Generable
struct WeatherResponse: Sendable, Codable {
    let temperature: Int
    let condition: String
}

let model = OllamaLanguageModel(modelName: "gpt-oss:20b")
let transcript = Transcript(entries: [
    .instructions(Transcript.Instructions(
        segments: [.text("You are a weather assistant.")],
        toolDefinitions: []
    ))
])

let result = try await model.generateWithRetry(
    transcript: transcript,
    prompt: "What's the weather in Tokyo?",
    generating: WeatherResponse.self,
    options: GenerableStreamOptions(
        retryPolicy: RetryPolicy(maxAttempts: 3),
        generationOptions: GenerationOptions(temperature: 0.1)
    )
)
print("Temperature: \(result.temperature)°C")
```

#### Streaming Generation with Retry
```swift
let stream = model.streamWithRetry(
    transcript: transcript,
    prompt: "What's the weather in Tokyo?",
    generating: WeatherResponse.self,
    options: GenerableStreamOptions(
        retryPolicy: .default,
        yieldPartialValues: true
    )
)

for try await result in stream {
    switch result {
    case .partial(let state):
        print("Partial: \(state.accumulatedContent)")
    case .retrying(let context):
        print("Retry \(context.attemptNumber)/\(context.maxAttempts)")
        print("Error: \(context.error)")
    case .complete(let value):
        print("Complete: \(value)")
    case .failed(let error):
        print("Failed: \(error)")
    }
}
```

### Error Context Flow

When a retry occurs, the error context is automatically included in the retry prompt:

```
Original: "What's the weather in Tokyo?"

Retry prompt (after schema validation failure):
"What's the weather in Tokyo?

[Retry attempt 1/3]
Previous response failed schema validation for field 'temperature': expected int
Please correct the response to match the expected schema."
```

### Retry Controller

The `RetryController` actor manages retry state:

```swift
public actor RetryController<T: Generable & Sendable> {
    // State
    public var canRetry: Bool
    public var remainingAttempts: Int
    public var currentAttempt: Int
    public var lastError: GenerableError?
    public var lastFailedContent: String?

    // Methods
    public func recordFailure(error: GenerableError, failedContent: String) -> RetryContext?
    public func recordSuccess()
    public func getLastRetryContext() -> RetryContext?
    public func buildRetryPrompt(originalPrompt: String, context: RetryContext) -> String
}
```

### JSON Auto-Correction

The `GenerableParser` automatically corrects common JSON issues:

1. **Markdown blocks**: Removes ```json and ``` wrappers
2. **Trailing commas**: Removes trailing commas before `}` or `]`
3. **Single quotes**: Converts single quotes to double quotes
4. **Unquoted keys**: Adds quotes to unquoted object keys
5. **Incomplete JSON**: Attempts to close unclosed brackets/braces

### GenerableError Types

```swift
public enum GenerableError: Error, Sendable {
    case jsonParsingFailed(String, underlyingError: String)
    case schemaValidationFailed(String, details: String)
    case streamInterrupted(String)
    case maxRetriesExceeded(attempts: Int, lastError: String)
    case connectionError(String)
    case emptyResponse
    case unknown(String)

    public var isRetryable: Bool  // Determines if error allows retry
}
```

## Future Improvements

1. **Enhanced Schema Conversion**: Better mapping between GenerationSchema and Ollama parameters
2. **Think Support**: Add support for reasoning/thinking messages when Transcript supports it
3. **Response Format**: Full implementation of structured output formatting
4. **Tool Execution**: Automatic tool execution and result handling
5. **Model Capabilities**: Dynamic detection of model features (tools, thinking, etc.)