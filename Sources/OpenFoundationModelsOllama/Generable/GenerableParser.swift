import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Parser for Generable types with auto-correction capabilities
public struct GenerableParser<T: Generable & Sendable & Decodable>: Sendable {
    /// Decoder used for parsing
    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
    }

    // MARK: - Public Parsing Methods

    /// Attempt to parse content as Generable type
    /// - Parameter content: Raw JSON string content
    /// - Returns: Parsed result with success or error details
    public func parse(_ content: String) -> ParseResult<T> {
        // Skip empty content
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyContent)
        }

        // First, try to fix common JSON issues
        let correctedContent = autoCorrectJSON(content)

        // Validate JSON structure
        guard let data = correctedContent.data(using: .utf8) else {
            return .failure(.encodingError)
        }

        // First check if it's valid JSON
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .failure(.invalidJSON(content, error.localizedDescription))
        }

        // Try to decode as Generable type
        do {
            let value = try decoder.decode(T.self, from: data)
            return .success(value)
        } catch let error as DecodingError {
            return .failure(mapDecodingError(error, content: content))
        } catch {
            return .failure(.decodingFailed(error.localizedDescription))
        }
    }

    /// Attempt to parse partial content (best effort)
    /// - Parameter content: Partial JSON string
    /// - Returns: Partial value if parseable, nil otherwise
    public func parsePartial(_ content: String) -> T? {
        // Try to complete partial JSON and parse
        let completedContent = attemptJSONCompletion(content)

        guard let data = completedContent.data(using: .utf8) else {
            return nil
        }

        return try? decoder.decode(T.self, from: data)
    }

    /// Validate content against the Generable schema
    /// - Parameter content: JSON content to validate
    /// - Returns: List of validation errors (empty if valid)
    public func validate(_ content: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errors.append(ValidationError(field: "root", message: "Invalid JSON structure"))
            return errors
        }

        // Get expected schema from Generable type
        let schema = T.generationSchema

        // Validate against schema
        errors.append(contentsOf: validateAgainstSchema(json: json, schema: schema))

        return errors
    }

    // MARK: - Private Helper Methods

    /// Auto-correct common JSON issues
    private func autoCorrectJSON(_ content: String) -> String {
        var corrected = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if corrected.hasPrefix("```json") {
            corrected = String(corrected.dropFirst(7))
        } else if corrected.hasPrefix("```") {
            corrected = String(corrected.dropFirst(3))
        }
        if corrected.hasSuffix("```") {
            corrected = String(corrected.dropLast(3))
        }

        corrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fix trailing commas in objects and arrays
        corrected = removeTrailingCommas(corrected)

        // Fix single quotes to double quotes
        corrected = fixQuotes(corrected)

        // Fix unquoted keys
        corrected = fixUnquotedKeys(corrected)

        return corrected
    }

    /// Remove trailing commas from JSON
    private func removeTrailingCommas(_ content: String) -> String {
        // Pattern: comma followed by } or ]
        var result = content
        let patterns = [
            (pattern: ",\\s*\\}", replacement: "}"),
            (pattern: ",\\s*\\]", replacement: "]")
        ]

        for (pattern, replacement) in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            } catch {
                #if DEBUG
                print("[GenerableParser] Failed to compile regex pattern '\(pattern)': \(error)")
                #endif
            }
        }

        return result
    }

    /// Fix single quotes to double quotes
    private func fixQuotes(_ content: String) -> String {
        var result = ""
        var inDoubleQuote = false
        var previousChar: Character = "\0"

        for char in content {
            if char == "\"" && previousChar != "\\" {
                inDoubleQuote.toggle()
                result.append(char)
            } else if char == "'" && !inDoubleQuote && previousChar != "\\" {
                result.append("\"")
            } else {
                result.append(char)
            }
            previousChar = char
        }

        return result
    }

    /// Fix unquoted keys in JSON objects
    private func fixUnquotedKeys(_ content: String) -> String {
        // Pattern: unquoted word followed by colon
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: "([{,]\\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\\s*:)")
        } catch {
            #if DEBUG
            print("[GenerableParser] Failed to compile unquoted keys regex: \(error)")
            #endif
            return content
        }

        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, range: range, withTemplate: "$1\"$2\"$3")
    }

    /// Attempt to complete partial JSON
    private func attemptJSONCompletion(_ content: String) -> String {
        var result = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Count brackets to determine what needs closing
        var braceCount = 0
        var bracketCount = 0
        var inString = false
        var previousChar: Character = "\0"

        for char in result {
            if char == "\"" && previousChar != "\\" {
                inString.toggle()
            }
            if !inString {
                switch char {
                case "{": braceCount += 1
                case "}": braceCount -= 1
                case "[": bracketCount += 1
                case "]": bracketCount -= 1
                default: break
                }
            }
            previousChar = char
        }

        // Close any incomplete strings (if in string)
        if inString {
            result += "\""
        }

        // Remove trailing comma if present
        result = result.trimmingCharacters(in: .whitespaces)
        if result.hasSuffix(",") {
            result = String(result.dropLast())
        }

        // Close any unclosed brackets
        result += String(repeating: "]", count: max(0, bracketCount))
        result += String(repeating: "}", count: max(0, braceCount))

        return result
    }

    /// Map DecodingError to ParseError
    private func mapDecodingError(_ error: DecodingError, content: String) -> ParseError {
        switch error {
        case .keyNotFound(let key, let context):
            return .missingRequiredField(key.stringValue, context.debugDescription)
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return .typeMismatch(path, expected: String(describing: type), got: context.debugDescription)
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return .nullValue(path, expected: String(describing: type))
        case .dataCorrupted(let context):
            return .dataCorrupted(context.debugDescription)
        @unknown default:
            return .decodingFailed(error.localizedDescription)
        }
    }

    /// Validate JSON against GenerationSchema
    private func validateAgainstSchema(json: [String: Any], schema: GenerationSchema) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Encode schema to get its structure
        let schemaData: Data
        let schemaDict: [String: Any]
        do {
            schemaData = try JSONEncoder().encode(schema)
            guard let dict = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
                #if DEBUG
                print("[GenerableParser] Schema JSON is not a dictionary")
                #endif
                return errors
            }
            schemaDict = dict
        } catch {
            #if DEBUG
            print("[GenerableParser] Failed to encode schema: \(error)")
            #endif
            return errors
        }

        // Check required fields
        if let required = schemaDict["required"] as? [String] {
            for field in required {
                if json[field] == nil {
                    errors.append(ValidationError(field: field, message: "Required field is missing"))
                }
            }
        }

        // Check property types
        if let properties = schemaDict["properties"] as? [String: [String: Any]] {
            for (key, propSchema) in properties {
                if let value = json[key] {
                    if let expectedType = propSchema["type"] as? String {
                        let actualType = getJSONType(value)
                        if !typesMatch(expected: expectedType, actual: actualType) {
                            errors.append(ValidationError(
                                field: key,
                                message: "Expected \(expectedType) but got \(actualType)"
                            ))
                        }
                    }
                }
            }
        }

        return errors
    }

    /// Get JSON type of a value
    private func getJSONType(_ value: Any) -> String {
        switch value {
        case is String:
            return "string"
        case is Int, is Double, is Float:
            return "number"
        case is Bool:
            return "boolean"
        case is [Any]:
            return "array"
        case is [String: Any]:
            return "object"
        case is NSNull:
            return "null"
        default:
            return "unknown"
        }
    }

    /// Check if JSON types match
    private func typesMatch(expected: String, actual: String) -> Bool {
        if expected == actual { return true }
        if expected == "integer" && actual == "number" { return true }
        if expected == "number" && actual == "integer" { return true }
        return false
    }
}

// MARK: - Parse Result

/// Result of a parse operation
public enum ParseResult<T: Generable & Sendable & Decodable>: Sendable {
    case success(T)
    case failure(ParseError)

    public var value: T? {
        if case .success(let value) = self {
            return value
        }
        return nil
    }

    public var error: ParseError? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }

    /// Convert to GenerableError
    public func toGenerableError() -> GenerableError? {
        guard let error = error else { return nil }
        return error.toGenerableError()
    }
}

// MARK: - Parse Error

/// Errors that can occur during parsing
public enum ParseError: Error, Sendable, Equatable {
    case emptyContent
    case encodingError
    case invalidJSON(String, String)
    case missingRequiredField(String, String)
    case typeMismatch(String, expected: String, got: String)
    case nullValue(String, expected: String)
    case dataCorrupted(String)
    case decodingFailed(String)

    public var localizedDescription: String {
        switch self {
        case .emptyContent:
            return "Content is empty"
        case .encodingError:
            return "Failed to encode content as UTF-8"
        case .invalidJSON(_, let error):
            return "Invalid JSON: \(error)"
        case .missingRequiredField(let field, let context):
            return "Missing required field '\(field)': \(context)"
        case .typeMismatch(let path, let expected, let got):
            return "Type mismatch at '\(path)': expected \(expected), got \(got)"
        case .nullValue(let path, let expected):
            return "Null value at '\(path)': expected \(expected)"
        case .dataCorrupted(let message):
            return "Data corrupted: \(message)"
        case .decodingFailed(let message):
            return "Decoding failed: \(message)"
        }
    }

    /// Convert to GenerableError
    public func toGenerableError() -> GenerableError {
        switch self {
        case .emptyContent:
            return .emptyResponse
        case .encodingError:
            return .jsonParsingFailed("", underlyingError: "UTF-8 encoding error")
        case .invalidJSON(let content, let errorMessage):
            return .jsonParsingFailed(content, underlyingError: errorMessage)
        case .missingRequiredField(let field, let details):
            return .schemaValidationFailed(field, details: details)
        case .typeMismatch(let path, let expected, let got):
            return .schemaValidationFailed(path, details: "Expected \(expected), got \(got)")
        case .nullValue(let path, let expected):
            return .schemaValidationFailed(path, details: "Null value, expected \(expected)")
        case .dataCorrupted(let message):
            return .jsonParsingFailed("", underlyingError: message)
        case .decodingFailed(let message):
            return .unknown(message)
        }
    }
}

// MARK: - Validation Error

/// A single validation error
public struct ValidationError: Sendable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}
