# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenFoundationModels-Ollama is a Swift package that provides an Ollama implementation of the LanguageModel protocol from the OpenFoundationModels framework. It enables the use of Ollama's locally-hosted models through Apple's Foundation Models API interface.

## Build and Test Commands

```bash
# Build the package
swift build

# Run all tests
swift test

# Run tests with verbose output
swift test --verbose

# Run a specific test
swift test --filter "TestClassName/testMethodName"

# Clean build artifacts
swift package clean

# Update dependencies
swift package update
```

## Architecture Overview

The implementation follows the same architectural pattern as OpenFoundationModels-OpenAI with these key components:

### Core Components
- **OllamaLanguageModel**: Main class implementing the LanguageModel protocol
- **OllamaConfiguration**: Configuration for API endpoint (default: http://localhost:11434)
- **Model Selection**: Models are specified as strings (e.g., "llama2", "mistral", "llama3.2:latest")

### API Layer
- **OllamaHTTPClient**: Handles HTTP communication with Ollama API
- **OllamaAPITypes**: Request/response type definitions matching Ollama's API format

### Internal Processing
- **RequestBuilders**: Constructs `/api/generate` and `/api/chat` requests
- **ResponseHandlers**: Processes Ollama's streaming JSON responses
- **StreamingHandler**: Handles line-delimited JSON streaming format

## Ollama API Specifics

### Key Differences from OpenAI:
1. **No Authentication**: Ollama runs locally, no API keys required
2. **Different Endpoints**: 
   - `/api/generate` for text completion
   - `/api/chat` for chat format (supports tool calling and think)
   - `/api/tags` to list available models
   - `/api/show` to get model information
3. **Response Format**: Line-delimited JSON instead of Server-Sent Events
4. **Model Names**: Format is `model:tag` (e.g., "llama3.2:latest", default tag is "latest")

### API Endpoints

#### 1. Generate Endpoint `/api/generate`
Used for simple text generation.

Request:
```json
{
  "model": "llama3.2",
  "prompt": "Why is the sky blue?",
  "stream": true,
  "options": {
    "temperature": 0.8,
    "top_k": 40,
    "top_p": 0.9,
    "num_predict": 100
  }
}
```

Non-streaming Response:
```json
{
  "model": "llama3.2",
  "created_at": "2024-01-01T00:00:00Z",
  "response": "The sky appears blue because...",
  "done": true,
  "context": [1, 2, 3],
  "total_duration": 5043500667,
  "load_duration": 5025959,
  "prompt_eval_count": 26,
  "prompt_eval_duration": 325953000,
  "eval_count": 290,
  "eval_duration": 4709213000
}
```

#### 2. Chat Endpoint `/api/chat`
Supports conversations, tool calling, and thinking.

Basic Chat Request:
```json
{
  "model": "llama3.2",
  "messages": [
    {
      "role": "user",
      "content": "Why is the sky blue?"
    }
  ],
  "stream": true
}
```

Chat with Tools Request:
```json
{
  "model": "llama3.2",
  "messages": [
    {
      "role": "user",
      "content": "What's the weather in New York?"
    }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather for a location",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "The city name"
            }
          },
          "required": ["location"]
        }
      }
    }
  ],
  "stream": true
}
```

Tool Call Response:
```json
{
  "model": "llama3.2",
  "created_at": "2024-01-01T00:00:00Z",
  "message": {
    "role": "assistant",
    "content": "",
    "tool_calls": [
      {
        "function": {
          "name": "get_weather",
          "arguments": {
            "location": "New York"
          }
        }
      }
    ]
  },
  "done": false
}
```

#### 3. Tags Endpoint `/api/tags`
Lists locally available models.

Response:
```json
{
  "models": [
    {
      "name": "llama3.2:latest",
      "model": "llama3.2:latest",
      "modified_at": "2024-01-01T00:00:00Z",
      "size": 3825819519,
      "digest": "sha256:..."
    }
  ]
}
```

### Streaming Response Format:
Each line is a complete JSON object:
```json
{"model":"llama3.2","created_at":"2024-01-01T00:00:00Z","message":{"role":"assistant","content":"The"},"done":false}
{"model":"llama3.2","created_at":"2024-01-01T00:00:01Z","message":{"role":"assistant","content":" sky"},"done":false}
{"model":"llama3.2","created_at":"2024-01-01T00:00:02Z","message":{"role":"assistant","content":" appears"},"done":false}
{"model":"llama3.2","created_at":"2024-01-01T00:00:03Z","message":{"role":"assistant","content":" blue"},"done":true,"total_duration":1000000000,"eval_count":4}
```

### Tool Calling Feature

Tool calling allows models to interact with external functions. This feature requires models that support tool calling (e.g., llama3.2, mistral).

#### Tool Response Handling
After receiving a tool call, send the result back:

```json
{
  "model": "llama3.2",
  "messages": [
    {
      "role": "user",
      "content": "What's the weather in New York?"
    },
    {
      "role": "assistant",
      "content": "",
      "tool_calls": [
        {
          "function": {
            "name": "get_weather",
            "arguments": {
              "location": "New York"
            }
          }
        }
      ]
    },
    {
      "role": "tool",
      "content": "72°F and sunny"
    }
  ]
}
```

#### Streaming with Tool Calls
Tool calls in streaming mode arrive as separate JSON objects:

```json
{"model":"llama3.2","created_at":"2024-01-01T00:00:00Z","message":{"role":"assistant","content":""},"done":false}
{"model":"llama3.2","created_at":"2024-01-01T00:00:01Z","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"get_weather","arguments":{"location":"New York"}}}]},"done":false}
{"model":"llama3.2","created_at":"2024-01-01T00:00:02Z","message":{"role":"assistant","content":"The weather in New York is"},"done":false}
{"model":"llama3.2","created_at":"2024-01-01T00:00:03Z","message":{"role":"assistant","content":" 72°F and sunny."},"done":true}
```

### Think Feature

The think feature allows models to show their reasoning process. This is supported by specific models (e.g., deepseek-r1).

#### Using Think Role
Include reasoning steps in the conversation:

```json
{
  "model": "deepseek-r1:latest",
  "messages": [
    {
      "role": "user",
      "content": "What is 25 * 4 + 10?"
    },
    {
      "role": "think",
      "content": "Let me calculate: 25 * 4 = 100, then 100 + 10 = 110"
    },
    {
      "role": "assistant",
      "content": "The answer is 110."
    }
  ]
}
```

#### Think in Streaming
Think content appears in streaming responses:

```json
{"model":"deepseek-r1","created_at":"2024-01-01T00:00:00Z","message":{"role":"think","content":"Let me"},"done":false}
{"model":"deepseek-r1","created_at":"2024-01-01T00:00:01Z","message":{"role":"think","content":" calculate"},"done":false}
{"model":"deepseek-r1","created_at":"2024-01-01T00:00:02Z","message":{"role":"assistant","content":"The answer"},"done":false}
```

### Options Parameters

Complete list of available options for `/api/generate` and `/api/chat`:

```json
{
  "options": {
    // Generation Parameters
    "num_predict": 128,        // Maximum tokens to generate (-1 = infinite)
    "temperature": 0.8,        // Randomness (0.0 - 1.0)
    "top_k": 40,              // Limit token selection pool
    "top_p": 0.9,             // Nucleus sampling threshold
    "min_p": 0.0,             // Minimum probability threshold
    "seed": 42,               // Random seed for reproducibility
    "stop": ["\\n", "User:"], // Stop sequences
    
    // Penalties
    "repeat_penalty": 1.1,     // Penalize repeated tokens
    "presence_penalty": 0.0,   // Penalize tokens based on presence
    "frequency_penalty": 0.0,  // Penalize tokens based on frequency
    
    // Context Management
    "num_ctx": 2048,          // Context window size
    "num_batch": 512,         // Batch size for prompt processing
    "num_keep": 0,            // Tokens to keep from initial prompt
    
    // Model Behavior
    "typical_p": 1.0,         // Typical sampling threshold
    "tfs_z": 1.0,             // Tail-free sampling
    "penalize_newline": true, // Penalize newline tokens
    "mirostat": 0,            // Mirostat sampling (0, 1, or 2)
    "mirostat_tau": 5.0,      // Mirostat target entropy
    "mirostat_eta": 0.1       // Mirostat learning rate
  }
}
```

### Error Responses

Ollama returns errors in JSON format:

```json
{
  "error": "model 'unknown' not found, try pulling it first"
}
```

Common errors:
- Model not found (need to `ollama pull model-name`)
- Connection refused (Ollama not running)
- Context length exceeded
- Invalid parameters

## Development Notes

### Testing with Ollama:
1. Ensure Ollama is running locally: `ollama serve`
2. Pull required models: `ollama pull llama3.2` or `ollama pull mistral`
3. Check available models: `ollama list`
4. Test connection: `curl http://localhost:11434/api/tags`

### Model Availability:
The implementation should gracefully handle cases where requested models aren't available locally. Check model availability using the `/api/tags` endpoint before making generation requests.

### Parameter Mapping:
- OpenFoundationModels `maxTokens` → Ollama `num_predict`
- OpenFoundationModels `temperature` → Ollama `temperature` (same)
- OpenFoundationModels `topP` → Ollama `top_p` (same)

### Implementation Considerations:

1. **Streaming Format**: Ollama uses line-delimited JSON, not Server-Sent Events
   - Each line is a complete JSON object
   - Parse each line separately
   - Handle `done: true` to detect stream end

2. **Model Loading**: 
   - First request to a model may be slow (model loading)
   - Use `keep_alive` parameter to control model memory retention
   - Default is 5 minutes, set to -1 to keep indefinitely

3. **Error Handling**:
   - Connection errors when Ollama isn't running
   - Model not found errors (need to pull first)
   - Parse errors for malformed streaming responses

4. **Context Management**:
   - Ollama doesn't maintain conversation state
   - Include full message history in each request
   - Be aware of context window limits (`num_ctx`)

5. **Tool/Think Support**:
   - Not all models support tool calling or thinking
   - Check model capabilities before using these features
   - Handle gracefully when features aren't supported

6. **Performance**:
   - Local inference speed depends on hardware
   - GPU acceleration significantly improves performance
   - Consider implementing request timeouts for slow hardware