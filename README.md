# OpenFoundationModels-Ollama

Ollama provider implementation for Apple's OpenFoundationModels framework, enabling seamless integration with locally-hosted Ollama models.

## Overview

OpenFoundationModels-Ollama provides a complete implementation of the `LanguageModel` protocol from Apple's OpenFoundationModels framework, allowing you to use Ollama's locally-hosted models through a unified API interface.

## Features

- ✅ Full `LanguageModel` protocol compliance
- ✅ Streaming and non-streaming text generation
- ✅ Tool calling support (model-dependent)
- ✅ Thinking/reasoning support (model-dependent)
- ✅ Line-delimited JSON streaming
- ✅ Swift 6 concurrency compliance
- ✅ Comprehensive error handling
- ✅ Model availability checking

## Requirements

- Swift 6.0+
- macOS 15.0+ / iOS 18.0+ / tvOS 18.0+ / watchOS 11.0+ / visionOS 2.0+
- Ollama installed and running locally

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/OpenFoundationModels-Ollama.git", from: "1.0.0")
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

### Basic Usage

```swift
import OpenFoundationModelsOllama

// Create a language model instance
let ollama = OllamaLanguageModel(modelName: "llama3.2")

// Generate text
let response = try await ollama.generate(
    prompt: "Hello, how are you?",
    options: GenerationOptions(temperature: 0.7)
)

print(response)
```

### Streaming

```swift
// Stream responses
let ollama = OllamaLanguageModel(modelName: "mistral")

for await chunk in ollama.stream(prompt: "Tell me a story") {
    print(chunk, terminator: "")
}
```

### Custom Configuration

```swift
// Configure with custom host and port
let config = OllamaConfiguration.create(host: "192.168.1.100", port: 8080)
let ollama = OllamaLanguageModel(configuration: config, modelName: "llama3.2")

// Or use convenience factory method
let ollama = OllamaLanguageModel.create(
    model: "llama3.2",
    host: "myserver",
    port: 11434
)
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

```swift
// Base models
OllamaModels.llama3_2    // "llama3.2"
OllamaModels.llama3_1    // "llama3.1"
OllamaModels.mistral     // "mistral"
OllamaModels.mixtral     // "mixtral"
OllamaModels.phi3        // "phi3"

// Code models
OllamaModels.codellama   // "codellama"
OllamaModels.deepseekCoder // "deepseek-coder"

// Specialized models
OllamaModels.deepseekR1  // "deepseek-r1" (supports thinking)

// Vision models
OllamaModels.llava       // "llava"
```

### Model Capabilities

Check if a model supports specific features:

```swift
// Check tool calling support
if OllamaModels.supportsTools("llama3.2") {
    // Model supports tool calling
}

// Check thinking/reasoning support
if OllamaModels.supportsThinking("deepseek-r1") {
    // Model supports thinking feature
}
```

## Advanced Usage

### Using with Prompts

```swift
import OpenFoundationModels

// Create a structured prompt
let prompt = Prompt(segments: [
    Prompt.Segment(text: "You are a helpful assistant", id: "system"),
    Prompt.Segment(text: "What is the capital of France?", id: "user")
])

let response = try await ollama.generate(
    prompt: prompt,
    options: GenerationOptions(maxTokens: 100)
)
```

### Generation Options

```swift
let options = GenerationOptions(
    maxTokens: 500,        // Maximum tokens to generate
    temperature: 0.8,      // Randomness (0.0 - 1.0)
    topP: 0.95,           // Nucleus sampling
    topK: 40,             // Top-k sampling
    seed: 42              // For reproducible outputs
)

let response = try await ollama.generate(
    prompt: "Write a haiku",
    options: options
)
```

### Error Handling

```swift
do {
    let response = try await ollama.generate(prompt: "Hello")
} catch let error as OllamaError {
    switch error {
    case .connectionFailed(let message):
        print("Connection failed: \(message)")
        print("Make sure Ollama is running with 'ollama serve'")
    case .modelNotFound:
        print("Model not found. Run: ollama pull <model-name>")
    case .timeout:
        print("Request timed out")
    default:
        print("Error: \(error.localizedDescription)")
    }
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

## API Documentation

For detailed API documentation and implementation details, see [CLAUDE.md](CLAUDE.md).

## Testing

Run the test suite:

```bash
swift test
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available under the MIT license. See the LICENSE file for more info.

## Acknowledgments

- Built on top of Apple's [OpenFoundationModels](https://github.com/apple/swift-openai) framework
- Powered by [Ollama](https://ollama.ai)