import Foundation

// MARK: - Generate API Types

/// Request for /api/generate endpoint
public struct GenerateRequest: Codable, Sendable {
    public let model: String
    public let prompt: String
    public let stream: Bool
    public let options: OllamaOptions?
    public let system: String?
    public let template: String?
    public let context: [Int]?
    public let raw: Bool?
    public let format: ResponseFormat?
    public let keepAlive: String?
    
    public init(
        model: String,
        prompt: String,
        stream: Bool = true,
        options: OllamaOptions? = nil,
        system: String? = nil,
        template: String? = nil,
        context: [Int]? = nil,
        raw: Bool? = nil,
        format: ResponseFormat? = nil,
        keepAlive: String? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.stream = stream
        self.options = options
        self.system = system
        self.template = template
        self.context = context
        self.raw = raw
        self.format = format
        self.keepAlive = keepAlive
    }
    
    enum CodingKeys: String, CodingKey {
        case model, prompt, stream, options, system, template, context, raw, format
        case keepAlive = "keep_alive"
    }
}

/// Response from /api/generate endpoint
public struct GenerateResponse: Codable, Sendable {
    public let model: String
    public let createdAt: Date
    public let response: String
    public let done: Bool
    public let context: [Int]?
    public let totalDuration: Int64?
    public let loadDuration: Int64?
    public let promptEvalCount: Int?
    public let promptEvalDuration: Int64?
    public let evalCount: Int?
    public let evalDuration: Int64?
    
    enum CodingKeys: String, CodingKey {
        case model, response, done, context
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

// MARK: - Chat API Types

/// Request for /api/chat endpoint
public struct ChatRequest: Codable, Sendable {
    public let model: String
    public let messages: [Message]
    public let stream: Bool
    public let options: OllamaOptions?
    public let format: ResponseFormat?
    public let keepAlive: String?
    public let tools: [Tool]?
    
    public init(
        model: String,
        messages: [Message],
        stream: Bool = true,
        options: OllamaOptions? = nil,
        format: ResponseFormat? = nil,
        keepAlive: String? = nil,
        tools: [Tool]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
        self.format = format
        self.keepAlive = keepAlive
        self.tools = tools
    }
    
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, options, format, tools
        case keepAlive = "keep_alive"
    }
}

/// Response from /api/chat endpoint
public struct ChatResponse: Codable, Sendable {
    public let model: String
    public let createdAt: Date
    public let message: Message?
    public let done: Bool
    public let totalDuration: Int64?
    public let loadDuration: Int64?
    public let promptEvalCount: Int?
    public let promptEvalDuration: Int64?
    public let evalCount: Int?
    public let evalDuration: Int64?
    
    enum CodingKeys: String, CodingKey {
        case model, message, done
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

/// Chat message
public struct Message: Codable, Sendable {
    public let role: Role
    public let content: String
    public let toolCalls: [ToolCall]?
    public let thinking: String?  // Add thinking field for models that support it
    public let toolName: String?  // Tool name for tool role messages
    
    public init(
        role: Role,
        content: String,
        toolCalls: [ToolCall]? = nil,
        thinking: String? = nil,
        toolName: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.thinking = thinking
        self.toolName = toolName
    }
    
    enum CodingKeys: String, CodingKey {
        case role, content, thinking
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }
}

/// Message role
public enum Role: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
    case think
}

// MARK: - Tool Types

/// Tool definition
public struct Tool: Codable, Sendable {
    public let type: String
    public let function: Function
    
    public init(type: String = "function", function: Function) {
        self.type = type
        self.function = function
    }
    
    public struct Function: Codable, Sendable {
        public let name: String
        public let description: String
        public let parameters: Parameters
        
        public init(
            name: String,
            description: String,
            parameters: Parameters
        ) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
        
        public struct Parameters: Codable, Sendable {
            public let type: String
            public let properties: [String: Property]
            public let required: [String]
            
            public init(
                type: String = "object",
                properties: [String: Property],
                required: [String]
            ) {
                self.type = type
                self.properties = properties
                self.required = required
            }
            
            public struct Property: Codable, Sendable {
                public let type: String
                public let description: String
                
                public init(type: String, description: String) {
                    self.type = type
                    self.description = description
                }
            }
        }
    }
}

/// Tool call
public struct ToolCall: Codable, Sendable {
    public let function: FunctionCall
    
    public init(function: FunctionCall) {
        self.function = function
    }
    
    public struct FunctionCall: Codable, Sendable {
        public let name: String
        public let arguments: ArgumentsContainer
        
        public init(name: String, arguments: [String: Any]) {
            self.name = name
            self.arguments = ArgumentsContainer(arguments)
        }
        
        public init(name: String, arguments: ArgumentsContainer) {
            self.name = name
            self.arguments = arguments
        }
        
        enum CodingKeys: String, CodingKey {
            case name, arguments
        }
    }
}

/// Container for function arguments that is Sendable
public struct ArgumentsContainer: Codable, Sendable {
    private let data: Data
    
    public init(_ dictionary: [String: Any]) {
        // Convert dictionary to JSON data
        if let jsonData = try? JSONSerialization.data(withJSONObject: dictionary) {
            self.data = jsonData
        } else {
            self.data = Data()
        }
    }
    
    public var dictionary: [String: Any] {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return [:]
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as dictionary first
        if let dict = try? container.decode([String: AnyCodable].self) {
            let convertedDict = dict.mapValues { $0.value }
            if let jsonData = try? JSONSerialization.data(withJSONObject: convertedDict) {
                self.data = jsonData
            } else {
                self.data = Data()
            }
        } else {
            // Fallback to empty data
            self.data = Data()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let json = try? JSONSerialization.jsonObject(with: data),
           let dict = json as? [String: Any] {
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        } else {
            try container.encode([String: AnyCodable]())
        }
    }
}

/// Helper type for encoding/decoding Any values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Model Management Types

/// Response from /api/tags endpoint
public struct ModelsResponse: Codable, Sendable {
    public let models: [Model]
    
    public struct Model: Codable, Sendable {
        public let name: String
        public let model: String
        public let modifiedAt: Date
        public let size: Int64
        public let digest: String
        public let details: Details?
        
        enum CodingKeys: String, CodingKey {
            case name, model, size, digest, details
            case modifiedAt = "modified_at"
        }
        
        public struct Details: Codable, Sendable {
            public let parentModel: String?
            public let format: String?
            public let family: String?
            public let families: [String]?
            public let parameterSize: String?
            public let quantizationLevel: String?
            
            enum CodingKeys: String, CodingKey {
                case parentModel = "parent_model"
                case format, family, families
                case parameterSize = "parameter_size"
                case quantizationLevel = "quantization_level"
            }
        }
    }
}

/// Request for /api/show endpoint
public struct ShowRequest: Codable, Sendable {
    public let name: String
    public let verbose: Bool?
    
    public init(name: String, verbose: Bool? = nil) {
        self.name = name
        self.verbose = verbose
    }
}

/// Response from /api/show endpoint
public struct ShowResponse: Codable, Sendable {
    public let license: String?
    public let modelfile: String?
    public let parameters: String?
    public let template: String?
    public let details: ModelsResponse.Model.Details?
    public let messages: [Message]?
}

// MARK: - Options

/// Ollama generation options
public struct OllamaOptions: Codable, Sendable {
    // Generation parameters
    public let numPredict: Int?
    public let temperature: Double?
    public let topK: Int?
    public let topP: Double?
    public let minP: Double?
    public let seed: Int?
    public let stop: [String]?
    
    // Penalties
    public let repeatPenalty: Double?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?
    
    // Context management
    public let numCtx: Int?
    public let numBatch: Int?
    public let numKeep: Int?
    
    // Model behavior
    public let typicalP: Double?
    public let tfsZ: Double?
    public let penalizeNewline: Bool?
    public let mirostat: Int?
    public let mirostatTau: Double?
    public let mirostatEta: Double?
    
    public init(
        numPredict: Int? = nil,
        temperature: Double? = nil,
        topK: Int? = nil,
        topP: Double? = nil,
        minP: Double? = nil,
        seed: Int? = nil,
        stop: [String]? = nil,
        repeatPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        numCtx: Int? = nil,
        numBatch: Int? = nil,
        numKeep: Int? = nil,
        typicalP: Double? = nil,
        tfsZ: Double? = nil,
        penalizeNewline: Bool? = nil,
        mirostat: Int? = nil,
        mirostatTau: Double? = nil,
        mirostatEta: Double? = nil
    ) {
        self.numPredict = numPredict
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.seed = seed
        self.stop = stop
        self.repeatPenalty = repeatPenalty
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.numCtx = numCtx
        self.numBatch = numBatch
        self.numKeep = numKeep
        self.typicalP = typicalP
        self.tfsZ = tfsZ
        self.penalizeNewline = penalizeNewline
        self.mirostat = mirostat
        self.mirostatTau = mirostatTau
        self.mirostatEta = mirostatEta
    }
    
    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
        case temperature
        case topK = "top_k"
        case topP = "top_p"
        case minP = "min_p"
        case seed, stop
        case repeatPenalty = "repeat_penalty"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case numCtx = "num_ctx"
        case numBatch = "num_batch"
        case numKeep = "num_keep"
        case typicalP = "typical_p"
        case tfsZ = "tfs_z"
        case penalizeNewline = "penalize_newline"
        case mirostat
        case mirostatTau = "mirostat_tau"
        case mirostatEta = "mirostat_eta"
    }
}

// MARK: - Response Format

/// Response format specification
public enum ResponseFormat: Codable, @unchecked Sendable {
    case text
    case json
    case jsonSchema([String: Any])
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as string first
        if let value = try? container.decode(String.self) {
            switch value {
            case "json":
                self = .json
            case "text":
                self = .text
            default:
                self = .text
            }
        } else if let dict = try? container.decode(AnyCodable.self),
                  let schemaDict = dict.value as? [String: Any] {
            // Decode as JSON Schema object
            self = .jsonSchema(schemaDict)
        } else {
            self = .text
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text:
            try container.encode("text")
        case .json:
            try container.encode("json")
        case .jsonSchema(let schema):
            // Encode JSON Schema object directly
            let anyCodable = AnyCodable(schema)
            try container.encode(anyCodable)
        }
    }
}

// MARK: - Error Response

/// Error response from Ollama API
public struct ErrorResponse: Codable, Error, LocalizedError, Sendable {
    public let error: String
    
    public var errorDescription: String? {
        return error
    }
}

// MARK: - Empty Request

/// Empty request for endpoints that don't require body
public struct EmptyRequest: Codable, Sendable {}