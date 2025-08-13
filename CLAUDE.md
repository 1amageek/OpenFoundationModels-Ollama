# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenFoundationModels-Ollama is a Swift package that provides an Ollama implementation of the LanguageModel protocol from the OpenFoundationModels framework. It enables the use of Ollama's locally-hosted models through Apple's Foundation Models API interface.

## Current Implementation Status (2025-08-13)

### ✅ Transcript-Based Architecture
The implementation has been updated to support the new Transcript-based LanguageModel protocol from OpenFoundationModels:

- **Protocol Compliance**: Fully implements `generate(transcript:options:)` and `stream(transcript:options:)` methods
- **TranscriptConverter**: Converts OpenFoundationModels Transcript to Ollama API formats
- **Tool Support**: Automatically extracts and converts ToolDefinitions from Transcript.Instructions
- **Complete History**: Handles all Transcript.Entry types (instructions, prompt, response, toolCalls, toolOutput)

### Key Components Updated

1. **OllamaLanguageModel**
   - Now implements Transcript-based LanguageModel protocol
   - Uses `/api/chat` endpoint primarily for better feature support
   - Automatic tool extraction from Transcript

2. **TranscriptConverter** (New)
   - `buildMessages(from: Transcript)` → Ollama Messages
   - `extractTools(from: Transcript)` → Ollama Tools
   - `extractResponseFormat(from: Transcript)` → Response format
   - `extractOptions(from: Transcript)` → Generation options

3. **API Usage**
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

## Future Improvements

1. **Enhanced Schema Conversion**: Better mapping between GenerationSchema and Ollama parameters
2. **Think Support**: Add support for reasoning/thinking messages when Transcript supports it
3. **Response Format**: Full implementation of structured output formatting
4. **Tool Execution**: Automatic tool execution and result handling
5. **Model Capabilities**: Dynamic detection of model features (tools, thinking, etc.)