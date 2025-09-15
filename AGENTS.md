# Repository Guidelines

## Project Structure & Module Organization
- `Sources/OpenFoundationModelsOllama/`: Library source.
  - `API/`: Request/response types for Ollama endpoints.
  - `HTTP/`: Lightweight HTTP client and errors.
  - `Internal/`: Streaming and internal helpers.
  - `Helpers/`: Utilities (e.g., tool schema helpers).
- `Tests/OpenFoundationModelsOllamaTests/`: Primary test suite using Swift Testing.
- `Tests/OpenFoundationModels-OllamaTests/`: Additional integration/perf tests.
- `Package.swift`: SwiftPM manifest (library product `OpenFoundationModelsOllama`).

## Build, Test, and Development Commands
- `swift build`: Build the package (use `-c release` for optimized builds).
- `swift test`: Run all tests; skips Ollama-dependent tests if the server is not running.
- `swift package resolve`: Resolve dependencies (run after manifest changes).
Example: `swift build -c release && swift test`.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines; 4-space indentation, 120-col soft wrap.
- Types: UpperCamelCase; methods/properties/locals: lowerCamelCase.
- File names match primary type (e.g., `OllamaHTTPClient.swift`).
- Use `///` doc comments and `// MARK:` for logical sections.
- Prefer pure `public` surface in `Sources/…` and keep implementation details `internal`.

## Testing Guidelines
- Framework: Swift Testing (`import Testing`, `@Suite`, `@Test`).
- Naming: `<Feature>Tests.swift` with focused suites (e.g., `TranscriptTests.swift`).
- Coverage focus: API models encoding/decoding, transcript conversion, streaming.
- Run: `swift test`; integration tests require an Ollama server at `http://127.0.0.1:11434`.

## Commit & Pull Request Guidelines
- Commits: Imperative, concise summaries (e.g., "Improve JSON handling in ArgumentsContainer").
- PRs include: clear description, motivation, screenshots/logs when relevant, linked issues, and checklists for `swift build`/`swift test` passing.
- Keep changes minimal and scoped; refactors in separate commits.

## Security & Configuration Tips
- Do not commit secrets. Configuration is code-based via `OllamaConfiguration`:
  - Example: `let config = OllamaConfiguration.create(host: "myhost", port: 11434)`
- Integration tests talk to a local Ollama instance; ensure it’s running or tests will skip.

## Architecture Overview (Brief)
- The library adapts OpenFoundationModels to Ollama:
  - `OllamaLanguageModel` orchestrates requests.
  - `TranscriptConverter` builds chat messages and tools.
  - `OllamaHTTPClient` handles JSON and streaming responses.

