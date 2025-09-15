import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

@Suite("Ollama Session Generable Tests", .serialized)
struct OllamaSessionGenerableTests {

    // MARK: - Env & Defaults

    private let env = ProcessInfo.processInfo.environment
    private var baseURL: URL {
        let urlString = env["OLLAMA_BASE_URL"] ?? "http://127.0.0.1:11434"
        return URL(string: urlString) ?? URL(string: "http://127.0.0.1:11434")!
    }
    private var modelName: String { env["OLLAMA_MODEL"] ?? "gpt-oss:20b" }
    private var minSuccess: Int { Int(env["OLLAMA_MIN_SUCCESS"] ?? "3") ?? 3 }

    // MARK: - Availability Check

    private var isOllamaAvailable: Bool {
        get async {
            do {
                let config = OllamaConfiguration(baseURL: baseURL)
                let httpClient = OllamaHTTPClient(configuration: config)
                let _: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: - Generable Target Type

    @Generable
    struct Product {
        @Guide(description: "Product name")
        let name: String

        @Guide(description: "Integer price (no decimals)")
        let price: Int

        @Guide(description: "Availability flag (true/false or Yes/No)")
        let available: Bool

        @Guide(description: "Creation time (ISO-8601 or UNIX timestamp)")
        let addedAt: Date
    }

    // MARK: - Helpers

    private var jsonOnlyInstructions: String {
        """
        You are a structured output assistant.
        - Output only JSON (no markdown, no prose, no code fences).
        - Conform strictly to the provided schema and field names.
        - Coerce types when reasonable:
          - price: integer only (convert numeric strings to integer; no decimals).
          - available: interpret true/false, yes/no, 1/0.
          - addedAt: accept ISO-8601 strings or UNIX epoch seconds.
        - Return exactly one JSON object.
        """
    }

    private func promptText(_ i: Int) -> String {
        """
        Output JSON only (no markdown, no prose).
        Follow this schema exactly:
        - name: string
        - price: integer (no decimals)
        - available: boolean (true/false or Yes/No)
        - addedAt: ISO-8601 timestamp or UNIX epoch seconds
        Return a single JSON object for a realistic product #\(i).
        Example: {"name":"Widget","price":199,"available":true,"addedAt":"2024-01-02T03:04:05Z"}
        """
    }

    // MARK: - Tests

    @Test("Session.respond(generating:) with Ollama x20")
    @available(macOS 13.0, iOS 16.0, *)
    func testGenerableRespondFiveTrials() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running at \(baseURL)")
        }

        // Create model and ensure tag exists
        let model = OllamaLanguageModel(configuration: OllamaConfiguration(baseURL: baseURL), modelName: modelName)
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(modelName) not available on server")
        }

        var successes = 0
        var failures = 0

        for i in 0..<50 {
            // Fresh session each iteration to avoid transcript contamination
            let session = LanguageModelSession(
                model: model,
                tools: [],
                instructions: jsonOnlyInstructions
            )
            do {
                let response = try await session.respond(
                    to: promptText(i),
                    generating: Product.self,
                    options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 200)
                )
                let product = response.content
                // Light sanity checks (types already validated by decoding)
                #expect(!product.name.isEmpty)
                #expect(product.price >= 0)
                successes += 1
            } catch {
                print("❌ Trial #\(i + 1) failed: \(error)")
                failures += 1
            }
        }

        print("✅ Successes: \(successes), ❌ Failures: \(failures), MinSuccess: \(minSuccess)")
        #expect(successes + failures == 20)
        #expect(successes >= minSuccess)
    }

    // Optional: Direct provider call to measure structured decoding without Session
    @Test("Direct generate(transcript:) JSON → Product conversion (x20)")
    @available(macOS 13.0, iOS 16.0, *)
    func testDirectGenerateFiveTrials() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running at \(baseURL)")
        }
        let model = OllamaLanguageModel(configuration: OllamaConfiguration(baseURL: baseURL), modelName: modelName)
        guard try await model.checkModelAvailability() else {
            throw TestSkip(reason: "Model \(modelName) not available on server")
        }

        var successes = 0
        var failures = 0

        for i in 0..<20 {
            var transcript = Transcript()
            transcript = Transcript(entries: [
                .instructions(Transcript.Instructions(
                    id: UUID().uuidString,
                    segments: [
                        .text(Transcript.TextSegment(
                            id: UUID().uuidString,
                            content: jsonOnlyInstructions
                        ))
                    ],
                    toolDefinitions: []
                )),
                .prompt(Transcript.Prompt(
                    segments: [
                        .text(Transcript.TextSegment(content: promptText(i)))
                    ],
                    options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 200),
                    // Ask for structured output using the Generable type
                    responseFormat: Transcript.ResponseFormat(type: Product.self)
                ))
            ])

            do {
                let entry = try await model.generate(transcript: transcript, options: nil)
                guard case .response(let response) = entry else {
                    throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response entry"])
                }

                // Extract text content (model currently returns text segments)
                let text = response.segments.compactMap { segment -> String? in
                    switch segment {
                    case .text(let t): return t.content
                    default: return nil
                    }
                }.joined(separator: "\n")

                // Try to parse JSON to Product via GeneratedContent
                let content = try GeneratedContent(json: text)
                let product = try Product(content)
                #expect(!product.name.isEmpty)
                successes += 1
            } catch {
                print("❌ Direct trial #\(i + 1) failed: \(error)")
                failures += 1
            }
        }

        print("(Direct) ✅ Successes: \(successes), ❌ Failures: \(failures), MinSuccess: \(minSuccess)")
        #expect(successes + failures == 20)
        #expect(successes >= minSuccess)
    }
}
