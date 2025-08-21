import Testing
import Foundation
import OpenFoundationModels
@testable import OpenFoundationModelsOllama

@Suite("Tool Arguments Conversion Tests")
struct ToolArgumentsConversionTests {
    
    @Test("Convert empty arguments to GeneratedContent")
    func testEmptyArguments() throws {
        let model = OllamaLanguageModel(modelName: "test")
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "test_tool",
                arguments: [:]
            )
        )
        
        let entry = model.createToolCallsEntry(from: [toolCall])
        
        if case .toolCalls(let calls) = entry {
            #expect(calls.count == 1)
            #expect(calls.first?.toolName == "test_tool")
            let properties = try calls.first?.arguments.properties()
            #expect(properties?.isEmpty == true)
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }
    
    @Test("Convert simple arguments to GeneratedContent")
    func testSimpleArguments() throws {
        let model = OllamaLanguageModel(modelName: "test")
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "get_weather",
                arguments: [
                    "location": "Tokyo",
                    "unit": "celsius"
                ]
            )
        )
        
        let entry = model.createToolCallsEntry(from: [toolCall])
        
        if case .toolCalls(let calls) = entry {
            #expect(calls.count == 1)
            #expect(calls.first?.toolName == "get_weather")
            
            let properties = try calls.first?.arguments.properties()
            #expect(properties?["location"]?.text == "Tokyo")
            #expect(properties?["unit"]?.text == "celsius")
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }
    
    @Test("Convert complex nested arguments to GeneratedContent")
    func testComplexArguments() throws {
        let model = OllamaLanguageModel(modelName: "test")
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "memory.session.list",
                arguments: [
                    "filters": [
                        "status": "active",
                        "limit": 10
                    ],
                    "sort": ["field": "created_at", "order": "desc"],
                    "include_metadata": true
                ]
            )
        )
        
        let entry = model.createToolCallsEntry(from: [toolCall])
        
        if case .toolCalls(let calls) = entry {
            #expect(calls.count == 1)
            #expect(calls.first?.toolName == "memory.session.list")
            
            let properties = try calls.first?.arguments.properties()
            
            // Check nested filters
            let filters = try properties?["filters"]?.properties()
            #expect(filters?["status"]?.text == "active")
            
            if case .number(let limit) = filters?["limit"]?.kind {
                #expect(limit == 10.0)
            } else {
                Issue.record("Expected limit to be a number")
            }
            
            // Check nested sort
            let sort = try properties?["sort"]?.properties()
            #expect(sort?["field"]?.text == "created_at")
            #expect(sort?["order"]?.text == "desc")
            
            // Check boolean
            if case .bool(let includeMeta) = properties?["include_metadata"]?.kind {
                #expect(includeMeta == true)
            } else {
                Issue.record("Expected include_metadata to be a boolean")
            }
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }
    
    @Test("Convert array arguments to GeneratedContent")
    func testArrayArguments() throws {
        let model = OllamaLanguageModel(modelName: "test")
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "batch_process",
                arguments: [
                    "items": ["item1", "item2", "item3"],
                    "options": [
                        ["name": "opt1", "value": 1],
                        ["name": "opt2", "value": 2]
                    ]
                ]
            )
        )
        
        let entry = model.createToolCallsEntry(from: [toolCall])
        
        if case .toolCalls(let calls) = entry {
            #expect(calls.count == 1)
            #expect(calls.first?.toolName == "batch_process")
            
            let properties = try calls.first?.arguments.properties()
            
            // Check string array
            let items = try properties?["items"]?.elements()
            #expect(items?.count == 3)
            #expect(items?[0].text == "item1")
            #expect(items?[1].text == "item2")
            #expect(items?[2].text == "item3")
            
            // Check array of objects
            let options = try properties?["options"]?.elements()
            #expect(options?.count == 2)
            
            let opt1 = try options?[0].properties()
            #expect(opt1?["name"]?.text == "opt1")
            if case .number(let value) = opt1?["value"]?.kind {
                #expect(value == 1.0)
            }
            
            let opt2 = try options?[1].properties()
            #expect(opt2?["name"]?.text == "opt2")
            if case .number(let value) = opt2?["value"]?.kind {
                #expect(value == 2.0)
            }
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }
    
    @Test("Handle null values in arguments")
    func testNullArguments() throws {
        let model = OllamaLanguageModel(modelName: "test")
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "update_record",
                arguments: [
                    "id": "123",
                    "field1": NSNull(),
                    "field2": "value"
                ]
            )
        )
        
        let entry = model.createToolCallsEntry(from: [toolCall])
        
        if case .toolCalls(let calls) = entry {
            #expect(calls.count == 1)
            #expect(calls.first?.toolName == "update_record")
            
            let properties = try calls.first?.arguments.properties()
            #expect(properties?["id"]?.text == "123")
            
            if case .null = properties?["field1"]?.kind {
                // Expected null
            } else {
                Issue.record("Expected field1 to be null")
            }
            
            #expect(properties?["field2"]?.text == "value")
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }
    
    @Test("Handle various number types")
    func testNumberTypeArguments() throws {
        let model = OllamaLanguageModel(modelName: "test")
        let toolCall = ToolCall(
            function: ToolCall.FunctionCall(
                name: "calculate",
                arguments: [
                    "int_value": 42,
                    "double_value": 3.14159,
                    "float_value": Float(2.718),
                    "negative": -100,
                    "zero": 0
                ]
            )
        )
        
        let entry = model.createToolCallsEntry(from: [toolCall])
        
        if case .toolCalls(let calls) = entry {
            #expect(calls.count == 1)
            #expect(calls.first?.toolName == "calculate")
            
            let properties = try calls.first?.arguments.properties()
            
            if case .number(let intVal) = properties?["int_value"]?.kind {
                #expect(intVal == 42.0)
            }
            
            if case .number(let doubleVal) = properties?["double_value"]?.kind {
                #expect(abs(doubleVal - 3.14159) < 0.00001)
            }
            
            if case .number(let floatVal) = properties?["float_value"]?.kind {
                #expect(abs(floatVal - 2.718) < 0.001)
            }
            
            if case .number(let negVal) = properties?["negative"]?.kind {
                #expect(negVal == -100.0)
            }
            
            if case .number(let zeroVal) = properties?["zero"]?.kind {
                #expect(zeroVal == 0.0)
            }
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }
}