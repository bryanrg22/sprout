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
///  - a list of strings written as tagged lines in one string:
///    `"highlights": "\n<item>a</item>\n<item>b</item>\n"` (also `<li>`)
///    (claude-sonnet-5 on the progress recap, 3 of 75 calls, EVAL_REPORT 35).
///  - a list of objects written as tool-call parameters in one string, one JSON object each:
///    `"insights": "\n<parameter name=\"item\">{\"title\": …}</parameter>…"`
///    (claude-sonnet-5 on the plan, EVAL_REPORT 39). Only when every chunk is a JSON object
///    and the string holds nothing else; a fragment such as `<parameter name="tone">watch`
///    has nothing to recover and is left for the decoder to reject.
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
                  let text = value as? String else { continue }
            let itemKind = (declared["items"] as? [String: Any])?["type"] as? String
            if kind == "array", itemKind == "string", let lines = taggedLines(text) {
                repaired[key] = lines
                continue
            }
            if kind == "array", itemKind == "object", let objects = parameterObjects(text) {
                repaired[key] = objects
                continue
            }
            guard let parsed = parse(text) else { continue }
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

    /// The contents of every `<item>…</item>` or `<li>…</li>` in `text`, trimmed, when the
    /// text is nothing but such elements (and whitespace); nil otherwise, so prose that merely
    /// mentions a tag is never split.
    static func taggedLines(_ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"<(item|li)>(.*?)</\1>"#,
                                                   options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }
        let leftover = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        guard leftover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return matches.compactMap { match in
            Range(match.range(at: 2), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    /// The objects of a string made of nothing but `<parameter name="item">{…}` chunks (each
    /// optionally closed by `</parameter>`), when every chunk is one JSON object; nil otherwise.
    static func parameterObjects(_ text: String) -> [[String: Any]]? {
        let marker = "<parameter name=\"item\">"
        let parts = text.components(separatedBy: marker)
        guard parts.count > 1, parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var objects: [[String: Any]] = []
        for part in parts.dropFirst() {
            var chunk = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if chunk.hasSuffix("</parameter>") {
                chunk = String(chunk.dropLast("</parameter>".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard chunk.hasPrefix("{"), let data = chunk.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            objects.append(object)
        }
        return objects
    }

    private static func parse(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
