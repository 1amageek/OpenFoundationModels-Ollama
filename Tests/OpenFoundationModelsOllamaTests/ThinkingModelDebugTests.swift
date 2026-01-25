import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels
import OpenFoundationModelsCore

@Suite("Thinking Model Debug Tests", .serialized)
struct ThinkingModelDebugTests {

    @Generable
    struct SimpleProduct {
        @Guide(description: "Product name")
        let name: String

        @Guide(description: "Price as integer")
        let price: Int
    }

    @Test("Debug: Analyze thinking model response structure", .timeLimit(.minutes(2)))
    func testAnalyzeThinkingModelResponse() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()

        print("\n" + String(repeating: "=", count: 80))
        print("DEBUG: Thinking Model Response Analysis")
        print("Model: \(model.modelName)")
        print(String(repeating: "=", count: 80))

        // Create transcript with ResponseFormat
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                id: UUID().uuidString,
                segments: [
                    .text(Transcript.TextSegment(
                        id: UUID().uuidString,
                        content: """
                        You are a JSON output assistant.
                        Output only valid JSON. No markdown, no prose, no code fences.
                        """
                    ))
                ],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                segments: [
                    .text(Transcript.TextSegment(content: """
                        Return a JSON object with these exact fields:
                        - name: string (product name)
                        - price: integer (price in dollars)

                        Example: {"name": "Widget", "price": 99}

                        Generate a product JSON now.
                        """))
                ],
                options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 500),
                responseFormat: Transcript.ResponseFormat(type: SimpleProduct.self)
            ))
        ])

        // Check what format was extracted
        let extractedFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
        print("\n--- Extracted ResponseFormat ---")
        if let format = extractedFormat {
            switch format {
            case .jsonSchema(let container):
                print("Type: jsonSchema")
                if let jsonData = try? JSONSerialization.data(withJSONObject: container.schema, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("Schema:\n\(jsonString)")
                }
            case .json:
                print("Type: json")
            case .text:
                print("Type: text")
            }
        } else {
            print("No format extracted!")
        }

        // Build request to see what's being sent
        let builder = ChatRequestBuilder(
            configuration: OllamaConfiguration(),
            modelName: model.modelName
        )
        let buildResult = try builder.build(transcript: transcript, options: nil, streaming: false)

        print("\n--- ChatRequest being sent ---")
        print("Model: \(buildResult.request.model)")
        print("Stream: \(buildResult.request.stream)")
        print("Think: \(String(describing: buildResult.request.think))")
        print("Format: \(String(describing: buildResult.request.format))")
        print("\nMessages:")
        for (i, msg) in buildResult.request.messages.enumerated() {
            print("  [\(i)] \(msg.role): \(msg.content.prefix(200))...")
        }

        // Make the actual API call
        print("\n--- Making API call ---")
        let response = try await model.generate(transcript: transcript, options: nil)

        print("\n--- Response Entry ---")
        switch response {
        case .response(let resp):
            print("Type: .response")
            for (i, segment) in resp.segments.enumerated() {
                switch segment {
                case .text(let textSeg):
                    print("  Segment[\(i)] (text): '\(textSeg.content)'")
                case .structure(let structSeg):
                    print("  Segment[\(i)] (structure): \(structSeg)")
                }
            }

            // Try to parse as JSON
            let content = resp.segments.compactMap { seg -> String? in
                if case .text(let t) = seg { return t.content }
                return nil
            }.joined()

            print("\n--- Content Analysis ---")
            print("Raw content: '\(content)'")
            print("Content length: \(content.count)")
            print("Is empty: \(content.isEmpty)")

            if !content.isEmpty {
                if let data = content.data(using: .utf8) {
                    do {
                        let json = try JSONSerialization.jsonObject(with: data)
                        print("✅ Valid JSON: \(json)")
                    } catch {
                        print("❌ Invalid JSON: \(error)")
                    }
                }
            }

        case .toolCalls(let toolCalls):
            print("Type: .toolCalls")
            print("  Tool calls: \(toolCalls.map { $0.toolName })")

        default:
            print("Type: other - \(response)")
        }

        print("\n" + String(repeating: "=", count: 80))
    }

    @Test("Debug: Stream response analysis", .timeLimit(.minutes(2)))
    func testStreamResponseAnalysis() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        let model = OllamaTestCoordinator.shared.createModel()

        print("\n" + String(repeating: "=", count: 80))
        print("DEBUG: Stream Response Analysis")
        print("Model: \(model.modelName)")
        print(String(repeating: "=", count: 80))

        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [
                    .text(Transcript.TextSegment(content: "Say hello in one word."))
                ],
                options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 20),
                responseFormat: nil
            ))
        ])

        print("\n--- Streaming ---")
        var entries: [Transcript.Entry] = []
        let stream = model.stream(transcript: transcript, options: nil)

        for try await entry in stream {
            entries.append(entry)
            switch entry {
            case .response(let resp):
                let content = resp.segments.compactMap { seg -> String? in
                    if case .text(let t) = seg { return t.content }
                    return nil
                }.joined()
                print("  [response] content='\(content)'")
            case .toolCalls(let tc):
                print("  [toolCalls] \(tc.map { $0.toolName })")
            default:
                print("  [other] \(entry)")
            }
        }

        print("\n--- Summary ---")
        print("Total entries received: \(entries.count)")

        let allContent = entries.compactMap { entry -> String? in
            if case .response(let resp) = entry {
                return resp.segments.compactMap { seg -> String? in
                    if case .text(let t) = seg { return t.content }
                    return nil
                }.joined()
            }
            return nil
        }.joined()

        print("Combined content: '\(allContent)'")
        print(String(repeating: "=", count: 80))

        #expect(!allContent.isEmpty, "Should have received content")
    }

    @Test("Debug: Raw HTTP response inspection", .timeLimit(.minutes(2)))
    func testRawHTTPResponseInspection() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        print("\n" + String(repeating: "=", count: 80))
        print("DEBUG: Raw HTTP Response Inspection")
        print(String(repeating: "=", count: 80))

        let config = OllamaConfiguration()
        let httpClient = OllamaHTTPClient(configuration: config)
        let modelName = TestConfiguration.defaultModel

        // Build a simple request
        let request = ChatRequest(
            model: modelName,
            messages: [
                Message(role: .user, content: "Return JSON: {\"hello\": \"world\"}")
            ],
            stream: false,
            options: OllamaOptions(numPredict: 50, temperature: 0.1),
            format: .json,
            keepAlive: nil,
            tools: nil,
            think: nil
        )

        print("\n--- Request ---")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let requestData = try? encoder.encode(request),
           let requestString = String(data: requestData, encoding: .utf8) {
            print(requestString)
        }

        print("\n--- Response ---")
        let response: ChatResponse = try await httpClient.send(request, to: "/api/chat")

        print("Model: \(response.model)")
        print("Done: \(response.done)")

        if let message = response.message {
            print("\nMessage:")
            print("  Role: \(message.role)")
            print("  Content: '\(message.content)'")
            print("  Content length: \(message.content.count)")
            print("  Thinking: '\(message.thinking ?? "nil")'")
            print("  Thinking length: \(message.thinking?.count ?? 0)")
            print("  ToolCalls: \(String(describing: message.toolCalls))")
        }

        print(String(repeating: "=", count: 80))
    }

    @Test("Debug: Think parameter combinations", .timeLimit(.minutes(2)))
    func testThinkParameterCombinations() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        print("\n" + String(repeating: "=", count: 80))
        print("DEBUG: Think Parameter Combinations")
        print(String(repeating: "=", count: 80))

        let config = OllamaConfiguration()
        let httpClient = OllamaHTTPClient(configuration: config)
        let modelName = TestConfiguration.defaultModel

        let testCases: [(think: ThinkingMode?, format: ResponseFormat?, description: String)] = [
            (nil, nil, "No think, No format"),
            (nil, .json, "No think, format=json"),
            (.enabled, nil, "think=true, No format"),
            (.enabled, .json, "think=true, format=json"),
            (.disabled, .json, "think=false, format=json"),
        ]

        for testCase in testCases {
            print("\n--- Test: \(testCase.description) ---")

            let request = ChatRequest(
                model: modelName,
                messages: [
                    Message(role: .user, content: "Return exactly: {\"result\": 42}")
                ],
                stream: false,
                options: OllamaOptions(numPredict: 100, temperature: 0.1),
                format: testCase.format,
                keepAlive: nil,
                tools: nil,
                think: testCase.think
            )

            do {
                let response: ChatResponse = try await httpClient.send(request, to: "/api/chat")

                if let message = response.message {
                    print("  Content: '\(message.content.prefix(100))'")
                    print("  Content length: \(message.content.count)")
                    print("  Thinking: '\((message.thinking ?? "").prefix(100))'")
                    print("  Thinking length: \(message.thinking?.count ?? 0)")

                    // Check if content is valid JSON
                    if !message.content.isEmpty {
                        if let data = message.content.data(using: .utf8) {
                            do {
                                let json = try JSONSerialization.jsonObject(with: data)
                                print("  ✅ Content is valid JSON: \(json)")
                            } catch {
                                print("  ❌ Content is NOT valid JSON")
                            }
                        }
                    } else {
                        print("  ⚠️ Content is empty")
                    }
                }
            } catch {
                print("  ❌ Error: \(error)")
            }
        }

        print("\n" + String(repeating: "=", count: 80))
    }

    @Test("Debug: ResponseProcessor behavior", .timeLimit(.minutes(1)))
    func testResponseProcessorBehavior() async throws {
        try await OllamaTestCoordinator.shared.checkPreconditions()

        print("\n" + String(repeating: "=", count: 80))
        print("DEBUG: ResponseProcessor Behavior Analysis")
        print(String(repeating: "=", count: 80))

        let config = OllamaConfiguration()
        let httpClient = OllamaHTTPClient(configuration: config)
        let modelName = TestConfiguration.defaultModel
        let processor = ResponseProcessor()

        // Request with format: json
        let request = ChatRequest(
            model: modelName,
            messages: [
                Message(role: .system, content: "You are a JSON assistant. Output only JSON."),
                Message(role: .user, content: "Return: {\"name\": \"test\", \"value\": 42}")
            ],
            stream: false,
            options: OllamaOptions(numPredict: 100, temperature: 0.1),
            format: .json,
            keepAlive: nil,
            tools: nil,
            think: nil
        )

        print("\n--- API Call ---")
        let response: ChatResponse = try await httpClient.send(request, to: "/api/chat")

        guard let message = response.message else {
            print("❌ No message in response!")
            return
        }

        print("\n--- Raw Message ---")
        print("Content: '\(message.content)'")
        print("Thinking: '\(message.thinking ?? "nil")'")
        print("ToolCalls: \(String(describing: message.toolCalls))")

        print("\n--- ResponseProcessor Result ---")
        let result = processor.process(message)

        switch result {
        case .toolCalls(let calls):
            print("Result: .toolCalls(\(calls.map { $0.function.name }))")
        case .content(let content):
            print("Result: .content('\(content)')")
            print("Content source: \(message.content.isEmpty ? "thinking" : "content")")
        case .empty:
            print("Result: .empty")
            print("⚠️ Both content and thinking are empty!")
        }

        print(String(repeating: "=", count: 80))
    }
}
