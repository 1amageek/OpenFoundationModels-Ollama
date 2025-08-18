# Transcript.ResponseFormat JSON Schema Support

## Overview

This document describes the implementation of JSON Schema support for `Transcript.ResponseFormat` in OpenFoundationModels-Ollama, enabling structured output generation with Ollama's API.

## Key Findings

### 1. Transcript.ResponseFormat Limitation

The `Transcript.ResponseFormat` type in Apple's Foundation Models framework has a **private `schema` property** that cannot be accessed directly. When encoding a Transcript to JSON, the schema information is not included:

```json
{
  "responseFormat": {
    "name": "WeatherResponse"
    // schema is private and not included
  }
}
```

### 2. GenerationSchema JSON Encoding

The `GenerationSchema` type has a built-in `encode` method that produces proper JSON Schema format:

```swift
let schema = WeatherResponse.generationSchema
let encoder = JSONEncoder()
let schemaData = try encoder.encode(schema)
// Produces valid JSON Schema
```

Example output:
```json
{
  "type": "object",
  "description": "Generated WeatherResponse",
  "properties": {
    "temperature": {
      "type": "integer",
      "description": "Temperature in celsius"
    },
    "condition": {
      "type": "string",
      "description": "Weather condition"
    }
  },
  "required": ["temperature", "condition"]
}
```

## Implementation

### 1. ResponseFormat Extension

Added support for JSON Schema in `ResponseFormat` enum:

```swift
public enum ResponseFormat: Codable, @unchecked Sendable {
    case text
    case json
    case jsonSchema([String: Any])  // New case for structured output
}
```

### 2. Schema Extraction

Due to the private schema property, full schema extraction from Transcript is limited:

```swift
static func extractResponseFormatWithSchema(from transcript: Transcript) -> ResponseFormat? {
    // Can only detect that a ResponseFormat exists
    // Returns .json, not the full schema
    for entry in transcript.reversed() {
        if case .prompt(let prompt) = entry,
           let _ = prompt.responseFormat {
            return .json  // Limited to JSON mode
        }
    }
    return nil
}
```

### 3. Workarounds for Full Schema Support

Since we cannot extract the schema from Transcript.ResponseFormat, there are two approaches:

#### Option 1: Direct Schema Usage (Recommended)

When you have access to the Generable type, use its schema directly:

```swift
let schema = WeatherResponse.generationSchema
let encoder = JSONEncoder()
let schemaData = try encoder.encode(schema)
let schemaJSON = try JSONSerialization.jsonObject(with: schemaData)
// Pass schemaJSON to Ollama API
```

#### Option 2: LanguageModelSession with Generable

Use LanguageModelSession's `respond(generating:)` method which handles schema internally:

```swift
let session = LanguageModelSession(model: ollamaModel)
let response = try await session.respond(
    to: "What's the weather?",
    generating: WeatherResponse.self
)
// response.content is typed as WeatherResponse
```

## Ollama API Integration

Ollama supports structured output via the `format` parameter in `/api/chat`:

```json
{
  "model": "llama3.2",
  "messages": [...],
  "format": {
    "type": "object",
    "properties": {
      "temperature": {"type": "integer"},
      "condition": {"type": "string"}
    },
    "required": ["temperature", "condition"]
  }
}
```

## Current Status

### ✅ Working
- JSON mode detection from Transcript.ResponseFormat
- Direct GenerationSchema to JSON Schema conversion
- ResponseFormat enum supports JSON Schema objects
- Basic structured output with Ollama

### ⚠️ Limitations
- Cannot extract full schema from Transcript.ResponseFormat (private property)
- Requires workarounds for full structured output support
- Schema must be passed separately or accessed from Generable type

### 🔄 Future Improvements
- If Apple makes the schema property public, full extraction would be possible
- Could maintain a schema registry for common types
- Could extend Transcript with custom encoding that includes schema

## Testing

Tests are provided in `ResponseFormatTests.swift`:

1. **testExtractResponseFormatSchema** - Shows limitation of Transcript extraction
2. **testDirectSchemaFromGenerationSchema** - Demonstrates direct schema extraction
3. **testResponseFormatCodable** - Tests ResponseFormat with JSON Schema
4. **testExplicitSchemaGeneration** - Shows usage with Generable types

## Conclusion

While full schema extraction from Transcript.ResponseFormat is limited due to private properties in Apple's implementation, we can still achieve structured output with Ollama by:

1. Using JSON mode when ResponseFormat is detected
2. Extracting schema directly from Generable types
3. Passing schema information separately when available

This provides a functional workaround while maintaining compatibility with the OpenFoundationModels framework.