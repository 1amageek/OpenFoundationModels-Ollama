import Testing
import Foundation
@testable import OpenFoundationModelsOllama
@testable import OpenFoundationModels

// MARK: - Test Skip Error

struct TestSkip: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

@Suite("Ollama Performance Tests", .tags(.performance))
struct OllamaPerformanceTests {
    
    // MARK: - Test Configuration
    
    private let defaultModel = "gpt-oss:20b"
    private let performanceTimeout: TimeInterval = 60.0
    
    private var isOllamaAvailable: Bool {
        get async {
            do {
                let config = OllamaConfiguration()
                let httpClient = OllamaHTTPClient(configuration: config)
                let _: ModelsResponse = try await httpClient.send(EmptyRequest(), to: "/api/tags")
                return true
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Response Time Tests
    
    @Test("Measure generation latency")
    @available(macOS 13.0, iOS 16.0, *)
    func testGenerationLatency() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = "Answer in one word: What color is the sky?"
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: 10
        )
        
        let startTime = Date()
        let response = try await model.generate(prompt: prompt, options: options)
        let endTime = Date()
        
        let latency = endTime.timeIntervalSince(startTime)
        
        #expect(!response.isEmpty)
        #expect(latency < performanceTimeout, "Generation took \(latency) seconds")
        
        // Log performance metric
        print("Generation latency: \(String(format: "%.3f", latency)) seconds")
    }
    
    @Test("Measure first token latency in streaming")
    @available(macOS 13.0, iOS 16.0, *)
    func testFirstTokenLatency() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = "Count from 1 to 10:"
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: 50
        )
        
        let startTime = Date()
        var firstTokenTime: Date?
        var tokenCount = 0
        
        let stream = model.stream(prompt: prompt, options: options)
        
        for await chunk in stream {
            if firstTokenTime == nil && !chunk.isEmpty {
                firstTokenTime = Date()
            }
            tokenCount += 1
            if tokenCount > 100 { // Safety limit
                break
            }
        }
        
        if let firstTokenTime = firstTokenTime {
            let latency = firstTokenTime.timeIntervalSince(startTime)
            print("First token latency: \(String(format: "%.3f", latency)) seconds")
            #expect(latency < 10.0, "First token should arrive within 10 seconds")
        }
        
        #expect(tokenCount > 0)
    }
    
    // MARK: - Streaming Performance Tests
    
    @Test("Measure streaming throughput")
    @available(macOS 13.0, iOS 16.0, *)
    func testStreamingThroughput() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = "Write a short paragraph about Swift programming (about 50 words):"
        let options = GenerationOptions(
            temperature: 0.7,
            maximumResponseTokens: 100
        )
        
        let startTime = Date()
        var totalChunks = 0
        var totalCharacters = 0
        
        let stream = model.stream(prompt: prompt, options: options)
        
        for await chunk in stream {
            totalChunks += 1
            totalCharacters += chunk.count
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        let chunksPerSecond = Double(totalChunks) / duration
        let charactersPerSecond = Double(totalCharacters) / duration
        
        print("Streaming performance:")
        print("  - Total chunks: \(totalChunks)")
        print("  - Total characters: \(totalCharacters)")
        print("  - Duration: \(String(format: "%.3f", duration)) seconds")
        print("  - Chunks/second: \(String(format: "%.1f", chunksPerSecond))")
        print("  - Characters/second: \(String(format: "%.1f", charactersPerSecond))")
        
        #expect(totalChunks > 0)
        #expect(totalCharacters > 0)
        #expect(duration < performanceTimeout)
    }
    
    // MARK: - Large Context Tests
    
    @Test("Performance with large prompt")
    @available(macOS 13.0, iOS 16.0, *)
    func testLargePromptPerformance() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        // Create a large prompt
        let contextText = """
        The Swift programming language was developed by Apple Inc. as a replacement for Objective-C.
        It was first announced at WWDC 2014 and has since become one of the most popular languages
        for iOS, macOS, watchOS, and tvOS development. Swift is designed to be safe, fast, and
        expressive, with modern features like optionals, generics, and protocol-oriented programming.
        """
        
        let prompt = """
        Context: \(contextText)
        
        Based on the context above, answer in one sentence: What company developed Swift?
        """
        
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: 30
        )
        
        let startTime = Date()
        let response = try await model.generate(prompt: prompt, options: options)
        let endTime = Date()
        
        let latency = endTime.timeIntervalSince(startTime)
        
        print("Large prompt performance:")
        print("  - Prompt length: \(prompt.count) characters")
        print("  - Response length: \(response.count) characters")
        print("  - Latency: \(String(format: "%.3f", latency)) seconds")
        
        #expect(!response.isEmpty)
        #expect(response.lowercased().contains("apple"))
        #expect(latency < performanceTimeout)
    }
    
    // MARK: - Concurrent Request Tests
    
    @Test("Performance with concurrent requests")
    @available(macOS 13.0, iOS 16.0, *)
    func testConcurrentRequests() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompts = [
            "What is 2 + 2?",
            "What color is the sky?",
            "Name a fruit:"
        ]
        
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: 10
        )
        
        let startTime = Date()
        
        // Run requests concurrently
        let responses = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, prompt) in prompts.enumerated() {
                group.addTask {
                    do {
                        let response = try await model.generate(prompt: prompt, options: options)
                        return (index, response)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            
            var results = [(Int, String?)]()
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        print("Concurrent requests performance:")
        print("  - Number of requests: \(prompts.count)")
        print("  - Total duration: \(String(format: "%.3f", duration)) seconds")
        print("  - Average per request: \(String(format: "%.3f", duration / Double(prompts.count))) seconds")
        
        #expect(responses.count == prompts.count)
        for response in responses {
            #expect(response != nil)
            if let response = response {
                #expect(!response.isEmpty)
            }
        }
    }
    
    // MARK: - Memory Tests
    
    @Test("Memory usage with multiple generations")
    @available(macOS 13.0, iOS 16.0, *)
    func testMemoryUsage() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: 10
        )
        
        let iterations = 5
        var durations: [TimeInterval] = []
        
        for i in 1...iterations {
            let prompt = "Count to \(i):"
            
            let startTime = Date()
            _ = try await model.generate(prompt: prompt, options: options)
            let endTime = Date()
            
            durations.append(endTime.timeIntervalSince(startTime))
        }
        
        // Check if performance degrades over time (potential memory issue)
        let firstHalf = durations.prefix(iterations / 2).reduce(0, +) / Double(iterations / 2)
        let secondHalf = durations.suffix(iterations / 2).reduce(0, +) / Double(iterations / 2)
        
        print("Memory test results:")
        print("  - First half average: \(String(format: "%.3f", firstHalf)) seconds")
        print("  - Second half average: \(String(format: "%.3f", secondHalf)) seconds")
        print("  - Degradation: \(String(format: "%.1f", (secondHalf - firstHalf) / firstHalf * 100))%")
        
        // Performance shouldn't degrade significantly
        #expect(secondHalf < firstHalf * 2.0, "Performance degraded significantly")
    }
    
    // MARK: - Token Generation Rate
    
    @Test("Measure token generation rate")
    @available(macOS 13.0, iOS 16.0, *)
    func testTokenGenerationRate() async throws {
        guard await isOllamaAvailable else {
            throw TestSkip(reason: "Ollama is not running")
        }
        
        let model = OllamaLanguageModel(modelName: defaultModel)
        
        guard try await model.isModelAvailable() else {
            throw TestSkip(reason: "Model \(defaultModel) not available")
        }
        
        let prompt = "Write a list of 10 programming languages:"
        let options = GenerationOptions(
            temperature: 0.3,
            maximumResponseTokens: 150
        )
        
        let startTime = Date()
        let response = try await model.generate(prompt: prompt, options: options)
        let endTime = Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        
        // Rough token estimation (1 token ≈ 4 characters)
        let estimatedTokens = response.count / 4
        let tokensPerSecond = Double(estimatedTokens) / duration
        
        print("Token generation rate:")
        print("  - Response length: \(response.count) characters")
        print("  - Estimated tokens: \(estimatedTokens)")
        print("  - Duration: \(String(format: "%.3f", duration)) seconds")
        print("  - Tokens/second: \(String(format: "%.1f", tokensPerSecond))")
        
        #expect(!response.isEmpty)
        #expect(tokensPerSecond > 0)
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var performance: Self
}