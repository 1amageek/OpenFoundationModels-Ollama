import Foundation

/// JSON抽出ユーティリティ
///
/// 混合コンテンツからJSONを抽出する共通ロジック。
/// ResponseProcessor と GenerableParser の両方で使用される。
///
/// ## 抽出優先順位
/// 1. マークダウンコードブロック (```json ... ``` or ``` ... ```)
/// 2. 生JSONオブジェクト
///
/// ## 使用例
/// ```swift
/// let content = "Here is the response:\n```json\n{\"key\": \"value\"}\n```"
/// if let json = JSONExtractor.extract(from: content) {
///     print(json)  // {"key": "value"}
/// }
/// ```
struct JSONExtractor: Sendable {

    // MARK: - Patterns

    /// マークダウンコードブロックパターン
    /// ```json ... ``` または ``` ... ``` にマッチ
    /// キャプチャグループ1: コードブロック内のコンテンツ
    private static let codeBlockPattern = try! NSRegularExpression(
        pattern: #"```(?:json)?\s*\n?([\s\S]*?)```"#,
        options: [.caseInsensitive]
    )

    /// JSONオブジェクトパターン
    /// { で始まり } で終わる最大のマッチを取得（greedy）
    private static let jsonObjectPattern = try! NSRegularExpression(
        pattern: #"\{[\s\S]*\}"#,
        options: []
    )

    // MARK: - Public Methods

    /// コンテンツからJSONを抽出
    ///
    /// 優先順位:
    /// 1. マークダウンコードブロックから抽出
    /// 2. 生JSONオブジェクトを抽出
    ///
    /// - Parameter content: 抽出元のコンテンツ
    /// - Returns: 抽出されたJSON文字列、見つからない場合はnil
    static func extract(from content: String) -> String? {
        // 優先順位1: コードブロックから抽出
        if let json = extractFromCodeBlock(content) {
            return json
        }

        // 優先順位2: 生JSONを抽出
        if let json = extractRawJSON(content) {
            return json
        }

        return nil
    }

    /// マークダウンコードブロックからJSON抽出
    ///
    /// ```json
    /// {"key": "value"}
    /// ```
    /// または
    /// ```
    /// {"key": "value"}
    /// ```
    /// 形式からJSONを抽出
    ///
    /// - Parameter content: 抽出元のコンテンツ
    /// - Returns: 抽出されたJSON文字列、見つからない場合はnil
    static func extractFromCodeBlock(_ content: String) -> String? {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        guard let match = codeBlockPattern.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        let extracted = String(content[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        // 空のコードブロックは無視
        guard !extracted.isEmpty else {
            return nil
        }

        // JSONとして有効か検証
        guard isValidJSON(extracted) else {
            return nil
        }

        return extracted
    }

    /// 生JSONオブジェクトを抽出
    ///
    /// テキストに埋め込まれたJSONオブジェクトを抽出:
    /// "Here is the data: {"key": "value"} hope this helps"
    /// → {"key": "value"}
    ///
    /// - Parameter content: 抽出元のコンテンツ
    /// - Returns: 抽出されたJSON文字列、見つからない場合はnil
    static func extractRawJSON(_ content: String) -> String? {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        guard let match = jsonObjectPattern.firstMatch(in: content, options: [], range: range),
              let swiftRange = Range(match.range, in: content) else {
            return nil
        }

        let jsonString = String(content[swiftRange])

        // JSONとして有効か検証
        guard isValidJSON(jsonString) else {
            return nil
        }

        return jsonString
    }

    /// 文字列が有効なJSONかどうかを検証
    ///
    /// - Parameter string: 検証対象の文字列
    /// - Returns: 有効なJSONの場合true
    static func isValidJSON(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
