# OpenFoundationModels-Ollama

Ollama provider implementation for Apple's OpenFoundationModels framework, enabling seamless integration with locally-hosted Ollama models.

## Overview

OpenFoundationModels-Ollama provides a complete implementation of the `LanguageModel` protocol from Apple's OpenFoundationModels framework, allowing you to use Ollama's locally-hosted models through a unified API interface.

### 🆕 Transcript-Based Architecture (Updated 2025-08-13)

The library now fully supports the new Transcript-based LanguageModel protocol from OpenFoundationModels, providing:
- Complete conversation history management via Transcript
- Automatic tool extraction from Instructions
- Seamless context handling across multiple turns
- Full support for all Transcript.Entry types

## Features

- ✅ Full `LanguageModel` protocol compliance (Transcript-based)
- ✅ Automatic tool extraction and conversion
- ✅ Complete conversation history support
- ✅ Streaming and non-streaming text generation
- ✅ Tool calling support (model-dependent)
- ✅ Line-delimited JSON streaming
- ✅ Swift 6 concurrency compliance
- ✅ Comprehensive error handling
- ✅ Model availability checking

## Requirements

- Swift 6.0+
- macOS 15.0+ / iOS 18.0+ / tvOS 18.0+ / watchOS 11.0+ / visionOS 2.0+
- Ollama installed and running locally
- OpenFoundationModels (latest version with Transcript support)

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/OpenFoundationModels-Ollama.git", from: "2.0.0")
]
```

Then add the dependency to your target:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["OpenFoundationModelsOllama"]
    )
]
```

## Quick Start

### Basic Usage with Transcript

```swift
import OpenFoundationModelsOllama
import OpenFoundationModels

// Create a language model instance
let ollama = OllamaLanguageModel(modelName: "llama3.2")

// Create a transcript with conversation history
var transcript = Transcript()

// Add instructions (system message)
transcript.append(.instructions(Transcript.Instructions(
    id: "inst-1",
    segments: [.text(Transcript.TextSegment(
        id: "seg-1",
        content: "You are a helpful assistant"
    ))],
    toolDefinitions: []
)))

// Add user prompt
transcript.append(.prompt(Transcript.Prompt(
    id: "prompt-1",
    segments: [.text(Transcript.TextSegment(
        id: "seg-2",
        content: "Hello, how are you?"
    ))],
    options: GenerationOptions(temperature: 0.7),
    responseFormat: nil
)))

// Generate response
let response = try await ollama.generate(
    transcript: transcript,
    options: nil  // Uses options from transcript if available
)

print(response)
```

### Streaming with Transcript

```swift
// Stream responses with conversation history
let stream = ollama.stream(transcript: transcript, options: nil)

for await chunk in stream {
    print(chunk, terminator: "")
}
```

### Tool Calling with Transcript

```swift
// Define a tool in the transcript
let weatherTool = Transcript.ToolDefinition(
    name: "get_weather",
    description: "Get current weather for a location",
    parameters: weatherSchema  // GenerationSchema
)

// Add instructions with tools
transcript.append(.instructions(Transcript.Instructions(
    id: "inst-1",
    segments: [.text(Transcript.TextSegment(
        id: "seg-1",
        content: "You can check weather when asked"
    ))],
    toolDefinitions: [weatherTool]
)))

// Add user query
transcript.append(.prompt(Transcript.Prompt(
    id: "prompt-1",
    segments: [.text(Transcript.TextSegment(
        id: "seg-2",
        content: "What's the weather in Tokyo?"
    ))],
    options: GenerationOptions(temperature: 0.1),
    responseFormat: nil
)))

// Generate - tools are automatically extracted and sent to Ollama
let response = try await ollama.generate(transcript: transcript, options: nil)
```

### Conversation History

```swift
// Build a multi-turn conversation
var transcript = Transcript()

// First exchange
transcript.append(.prompt(Transcript.Prompt(
    id: "p1",
    segments: [.text(Transcript.TextSegment(id: "s1", content: "What is 2+2?"))],
    options: GenerationOptions(),
    responseFormat: nil
)))

transcript.append(.response(Transcript.Response(
    id: "r1",
    assetIDs: [],
    segments: [.text(Transcript.TextSegment(id: "s2", content: "2+2 equals 4."))]
)))

// Follow-up question - maintains context
transcript.append(.prompt(Transcript.Prompt(
    id: "p2",
    segments: [.text(Transcript.TextSegment(id: "s3", content: "What about 3+3?"))],
    options: GenerationOptions(),
    responseFormat: nil
)))

// Generate with full context
let response = try await ollama.generate(transcript: transcript, options: nil)
```

### Custom Configuration

```swift
// Configure with custom host and port
let config = OllamaConfiguration(
    host: "192.168.1.100",
    port: 8080,
    keepAlive: "10m"
)
let ollama = OllamaLanguageModel(configuration: config, modelName: "llama3.2")
```

### Check Model Availability

```swift
let ollama = OllamaLanguageModel(modelName: "llama3.2")

if try await ollama.isModelAvailable() {
    print("Model is ready!")
} else {
    print("Please run: ollama pull llama3.2")
}
```

## Supported Models

The library supports all Ollama models. Some popular ones include:

- **Language Models**: llama3.2, llama3.1, mistral, mixtral, phi3
- **Code Models**: codellama, deepseek-coder
- **Specialized Models**: deepseek-r1 (supports thinking/reasoning)
- **Vision Models**: llava

## Advanced Features

### Response Format

```swift
// Request JSON formatted output
transcript.append(.prompt(Transcript.Prompt(
    id: "prompt-1",
    segments: [.text(Transcript.TextSegment(
        id: "seg-1",
        content: "List 3 colors in JSON format"
    ))],
    options: GenerationOptions(),
    responseFormat: Transcript.ResponseFormat(
        name: "json",
        schema: nil  // Schema would go here for structured output
    )
)))
```

### Generation Options

```swift
let options = GenerationOptions(
    maximumResponseTokens: 500,  // Max tokens to generate
    temperature: 0.8,            // Randomness (0.0 - 1.0)
    samplingMode: .topK(40)      // Sampling strategy
)

let response = try await ollama.generate(
    transcript: transcript,
    options: options
)
```

### Error Handling

```swift
do {
    let response = try await ollama.generate(transcript: transcript, options: nil)
} catch {
    print("Error: \(error.localizedDescription)")
    // Handle specific errors as needed
}
```

## Prerequisites

1. **Install Ollama**: Download from [ollama.ai](https://ollama.ai)

2. **Start Ollama service**:
   ```bash
   ollama serve
   ```

3. **Pull a model**:
   ```bash
   ollama pull llama3.2
   ```

## Architecture

The library uses a Transcript-centric design:

- **TranscriptConverter**: Converts OpenFoundationModels Transcript to Ollama API format
- **OllamaLanguageModel**: Implements the LanguageModel protocol
- **OllamaHTTPClient**: Handles communication with Ollama API
- **Automatic Tool Extraction**: Tools are extracted from Transcript.Instructions

## API Documentation

For detailed API documentation and implementation details, see [CLAUDE.md](CLAUDE.md).

## Testing

Run the test suite:

```bash
swift test

# Run specific tests
swift test --filter "TranscriptTests"
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available under the MIT license. See the LICENSE file for more info.

## Acknowledgments

- Built on top of Apple's [OpenFoundationModels](https://github.com/1amageek/OpenFoundationModels) framework
- Powered by [Ollama](https://ollama.ai)