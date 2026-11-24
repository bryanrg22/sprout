import Foundation

/// Structured output for the Claude models that refuse a forced tool call.
///
/// The app asks for structured answers by forcing a tool call (`tool_choice` of type
/// `tool`). `claude-sonnet-5-5`, `claude-opus-5-5` and `claude-fable-5-2` answer that with a
/// 400 ("tool_choice: type "tool" and "any" are not supported for this model", checked
/// against the API on 2026-11-23, EVAL_REPORT 30). Anthropic's documented replacement is a
/// JSON-schema response format (`output_config.format`), whose answer is the text of the
/// reply. That format needs every object to say `additionalProperties: false` (a 400
/// otherwise, also checked) and does not accept limits on array length beyond 0 or 1, on
/// numbers or on string length; those limits move into the field's description, where the
/// model still reads them.
enum AnthropicStructuredFormat {

    /// Known to refuse a forced tool call. Any other model that refuses is caught by the
    /// error text instead (`isForcedToolRefusal`), so a new model costs one failed request,
    /// not a broken feature.
    static func refusesForcedToolChoice(_ model: String) -> Bool {
        ["claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-2"]
            .contains { AnthropicModelProfile.isModel(model, $0) }
    }

    /// The 400 that means "this model does not take a forced tool call".
    static func isForcedToolRefusal(_ error: Error) -> Bool {
        guard case AIConfig.AIError.badResponse(let message) = error else { return false }
        let m = message.lowercased()
        return m.contains("tool_choice") && m.contains("not supported")
    }

    /// Keywords the format rejects, and how each is said in words instead.
    private static let movedToDescription: [String: (Any) -> String?] = [
        "minItems": { v in (v as? Int).flatMap { $0 > 1 ? "at least \($0) items" : nil } },
        "maxItems": { v in (v as? Int).map { "at most \($0) items" } },
        "minimum": { v in number(v).map { "at least \($0)" } },
        "maximum": { v in number(v).map { "at most \($0)" } },
        "exclusiveMinimum": { v in number(v).map { "more than \($0)" } },
        "exclusiveMaximum": { v in number(v).map { "less than \($0)" } },
        "minLength": { v in (v as? Int).map { "at least \($0) characters" } },
        "maxLength": { v in (v as? Int).map { "at most \($0) characters" } },
        "multipleOf": { v in number(v).map { "a multiple of \($0)" } },
    ]

    private static let noteOrder = ["minItems", "maxItems", "minimum", "exclusiveMinimum", "maximum",
                                    "exclusiveMaximum", "minLength", "maxLength", "multipleOf"]

    private static func number(_ v: Any) -> String? {
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return d == d.rounded() ? String(Int(d)) : String(d) }
        return nil
    }

    /// The schema as the format accepts it. Pure: the tool schema itself is not changed.
    static func schema(_ schema: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        // In a fixed order, so the same schema always gives the same words (and request).
        var notes: [String] = []
        for key in noteOrder {
            guard let value = schema[key], let say = movedToDescription[key] else { continue }
            if key == "minItems", let n = value as? Int, n <= 1 { continue }
            if let words = say(value) { notes.append(words) }
        }
        for (key, value) in schema {
            if movedToDescription[key] != nil {
                // A minItems of 0 or 1 is accepted and kept; everything else became words above.
                if key == "minItems", let n = value as? Int, n <= 1 { out[key] = n }
                continue
            }
            switch key {
            case "properties":
                if let props = value as? [String: Any] {
                    out[key] = props.mapValues { ($0 as? [String: Any]).map(Self.schema) ?? $0 }
                } else { out[key] = value }
            case "items":
                out[key] = (value as? [String: Any]).map(Self.schema) ?? value
            case "anyOf", "allOf":
                out[key] = (value as? [[String: Any]])?.map(Self.schema) ?? value
            default:
                out[key] = value
            }
        }
        let isObject = (schema["type"] as? String) == "object"
            || ((schema["type"] as? [String])?.contains("object") ?? false)
            || schema["properties"] != nil
        if isObject { out["additionalProperties"] = false }
        if !notes.isEmpty {
            let existing = (schema["description"] as? String).map { $0.hasSuffix(".") ? $0 + " " : $0 + ". " } ?? ""
            out["description"] = existing + notes.joined(separator: ", ").prefix(1).uppercased()
                + notes.joined(separator: ", ").dropFirst() + "."
        }
        return out
    }

    /// The limits `schema(_:)` took out of the request, checked on the answer: what the
    /// format no longer enforces, the app does. Seen on the first live run: one suggestion
    /// where the schema asks for 2 to 3, filled with the word "placeholder" (EVAL_REPORT 30).
    /// Returns one line per broken limit, empty when the answer keeps them all.
    static func violations(_ value: Any?, against schema: [String: Any], path: String = "answer") -> [String] {
        guard let value, !(value is NSNull) else { return [] }
        var found: [String] = []
        if let list = value as? [Any] {
            if let min = schema["minItems"] as? Int, list.count < min { found.append("\(path): \(list.count) items, at least \(min)") }
            if let max = schema["maxItems"] as? Int, list.count > max { found.append("\(path): \(list.count) items, at most \(max)") }
            if let items = schema["items"] as? [String: Any] {
                for (i, element) in list.enumerated() { found += violations(element, against: items, path: "\(path)[\(i)]") }
            }
        } else if let dict = value as? [String: Any], let props = schema["properties"] as? [String: Any] {
            for (key, sub) in props {
                guard let subSchema = sub as? [String: Any] else { continue }
                found += violations(dict[key], against: subSchema, path: "\(path).\(key)")
            }
        } else if let text = value as? String {
            if let min = schema["minLength"] as? Int, text.count < min { found.append("\(path): \(text.count) characters, at least \(min)") }
            if let max = schema["maxLength"] as? Int, text.count > max { found.append("\(path): \(text.count) characters, at most \(max)") }
        } else if let n = (value as? NSNumber)?.doubleValue, !(value is Bool) {
            if let min = (schema["minimum"] as? NSNumber)?.doubleValue, n < min { found.append("\(path): \(n), at least \(min)") }
            if let max = (schema["maximum"] as? NSNumber)?.doubleValue, n > max { found.append("\(path): \(n), at most \(max)") }
        }
        return found
    }

    /// The JSON object in a format answer's text. Tolerates a code fence around it.
    static func object(fromText text: String) -> [String: Any]? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
            if let end = t.range(of: "```", options: .backwards) { t = String(t[..<end.lowerBound]) }
        }
        guard let data = t.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
