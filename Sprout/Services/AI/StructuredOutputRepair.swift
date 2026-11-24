import Foundation

/// Undoes one specific, recorded way a model gets a forced structured answer wrong:
/// JSON inside a *string* where the schema asks for an array or an object.
///
/// Both shapes below were recorded from Claude models answering a forced tool call
/// (EVAL_REPORT 22); the app's decoder threw on them and the feature fell back to its
/// template without telling anyone:
///  - the container itself as a string: `"highlights": "[\"a\", \"b\"]"`;
///  - an object wrapping the same key, as a string, once per key:
///    `"chips": "{\"chips\": [...]}", "tasks": "{\"tasks\": [...]}"`
///    (claude-sonnet-5 on the checklist, 14 of 48 calls).
///
/// The repair is driven by the schema: only a property declared as an array or an object
/// is looked at, so a string property is never touched however much it looks like JSON,
/// and anything that does not parse to the declared kind is left for the decoder to reject.
enum StructuredOutputRepair {

    static func repair(_ input: [String: Any], schema: [String: Any]) -> [String: Any] {
        guard let properties = schema["properties"] as? [String: Any] else { return input }
        var repaired = input
        for (key, value) in input {
            guard let declared = properties[key] as? [String: Any],
                  let kind = declared["type"] as? String, kind == "array" || kind == "object",
                  let text = value as? String, let parsed = parse(text) else { continue }
            if matches(parsed, kind: kind), !isSelfWrapper(parsed, key: key, kind: kind) {
                repaired[key] = parsed
            } else if let wrapper = parsed as? [String: Any], let inner = wrapper[key], matches(inner, kind: kind) {
                repaired[key] = inner
            }
        }
        return repaired
    }

    private static func matches(_ value: Any, kind: String) -> Bool {
        kind == "array" ? value is [Any] : value is [String: Any]
    }

    /// An object property whose string holds `{key: {...}}` is the wrapper shape, not the value.
    private static func isSelfWrapper(_ parsed: Any, key: String, kind: String) -> Bool {
        guard kind == "object", let object = parsed as? [String: Any] else { return false }
        return object.count == 1 && object[key] is [String: Any]
    }

    private static func parse(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
