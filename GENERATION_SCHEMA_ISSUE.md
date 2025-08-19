# GenerationSchema エンコーディング問題の詳細分析

## 概要

OpenFoundationModelsの`GenerationSchema`において、作成方法によってJSON エンコーディングの結果が異なる問題を確認しました。

## 検証結果

### ✅ 正常に動作するケース

**GenerationSchema.Property配列を使用した場合：**

```swift
let properties = [
    GenerationSchema.Property(
        name: "location",
        description: "City name",
        type: String.self
    ),
    GenerationSchema.Property(
        name: "unit",
        description: "Temperature unit",
        type: String?.self
    )
]

let schema = GenerationSchema(
    type: String.self,
    description: "Weather parameters",
    properties: properties
)
```

**結果（正常）：**
```json
{
  "type": "object",
  "description": "Weather parameters",
  "properties": {
    "location": {
      "type": "string",
      "description": "City name"
    },
    "unit": {
      "type": "string",
      "description": "Temperature unit"
    }
  },
  "required": ["location"]
}
```

### ❌ 問題が発生するケース

**DynamicGenerationSchemaを使用した場合：**

```swift
let dynamicSchema = DynamicGenerationSchema(
    name: "WeatherParameters",
    description: "Parameters for weather",
    properties: [
        DynamicGenerationSchema.Property(
            name: "location",
            description: "City name",
            schema: DynamicGenerationSchema(type: String.self),
            isOptional: false
        ),
        DynamicGenerationSchema.Property(
            name: "unit",
            description: "Temperature unit",
            schema: unitSchema,
            isOptional: true
        )
    ]
)

let schema = try GenerationSchema(root: dynamicSchema, dependencies: [])
```

**結果（プロパティが失われる）：**
```json
{
  "type": "object"
}
```

## 根本原因

`GenerationSchema`の内部実装を調査した結果：

1. **schemaTypeによる分岐処理**
   - `.object(properties:)` の場合 → 正常にエンコード
   - `.dynamic(root:dependencies:)` の場合 → プロパティ情報が失われる

2. **Codable実装の問題**
   ```swift
   // GenerationSchema.swift より
   case .dynamic(_, _):
       var schema: [String: Any] = [
           "type": "object"
       ]
       if let description = _description {
           schema["description"] = description
       }
       // プロパティ情報の変換が実装されていない！
       return schema
   ```

## 影響範囲

この問題により、以下の機能が制限されます：

1. **DynamicGenerationSchemaを使用したツール定義**
   - ToolSchemaHelper.createWeatherTool() などのヘルパーメソッド
   - 動的にスキーマを構築する場合

2. **LLMへのツールパラメータ情報の伝達**
   - ツールの引数構造が伝わらない
   - 型情報、必須/オプショナル情報が失われる

## 回避策

### 現在可能な回避策

1. **GenerationSchema.Propertyを直接使用**
   ```swift
   // DynamicGenerationSchemaの代わりにProperty配列を使用
   let schema = GenerationSchema(
       type: MyType.self,
       description: "Description",
       properties: [
           GenerationSchema.Property(name: "field1", type: String.self),
           // ...
       ]
   )
   ```

2. **制限事項**
   - 複雑なスキーマ（ネストされたオブジェクト、配列など）の表現が困難
   - anyOf、oneOfなどの高度な制約が使用できない

## 提案する解決策

### OpenFoundationModelsへの改善提案

`GenerationSchema`のtoSchemaDictionary()メソッドで、`.dynamic`ケースの実装を改善：

```swift
case .dynamic(let root, let dependencies):
    var schema: [String: Any] = [
        "type": "object"
    ]
    
    // DynamicGenerationSchemaからプロパティ情報を抽出
    if let rootSchema = root.toSchemaDictionary() {
        if let properties = rootSchema["properties"] {
            schema["properties"] = properties
        }
        if let required = rootSchema["required"] {
            schema["required"] = required
        }
    }
    
    if let description = _description {
        schema["description"] = description
    }
    
    return schema
```

## まとめ

- GenerationSchema.Property配列を使用する場合は正常に動作
- DynamicGenerationSchemaを使用する場合にプロパティ情報が失われる
- OpenFoundationModelsの内部実装の改善が必要
- 当面はProperty配列を使用する回避策で対応可能