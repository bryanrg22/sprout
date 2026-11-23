import Foundation

/// "Ask about this": a passage the user picked out of the conversation, carried into their
/// next message.
///
/// The quote travels inside the message text as a Markdown block quote followed by the
/// question:
///
///     > the passage, one `>` per line
///
///     the user's question
///
/// That is one stored string (no new field on `ChatMessage`), it is what the model reads
/// (models are trained on exactly this form of quoting), and the chat bubble can split it
/// back into a quoted reference and the question.
enum ChatQuote {

    /// The longest passage carried along. A longer selection is cut at a word boundary and
    /// ends in an ellipsis: the quote is a pointer to what was said, not a second copy of it.
    static let maxLength = 600

    /// Asked when the user sends a quote with no question of their own.
    static let defaultQuestion = "Can you tell me more about this?"

    /// A selection as it is shown in the composer and stored: trimmed, blank lines dropped,
    /// Markdown quote and list markers at the start of a line left alone, length-capped.
    static func normalized(_ passage: String) -> String {
        let lines = passage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        guard joined.count > maxLength else { return joined }
        let cut = String(joined.prefix(maxLength))
        let trimmed: String
        if let lastSpace = cut.lastIndex(where: { $0 == " " || $0 == "\n" }),
           cut.distance(from: cut.startIndex, to: lastSpace) > maxLength / 2 {
            trimmed = String(cut[..<lastSpace])
        } else {
            trimmed = cut
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// The message text for a quote and a question. With no quote it is just the question;
    /// with no question the default one is asked.
    static func compose(quote: String?, question: String) -> String {
        let body = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quote, !normalized(quote).isEmpty else { return body }
        let quoted = normalized(quote)
            .components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")
        return quoted + "\n\n" + (body.isEmpty ? defaultQuestion : body)
    }

    /// Splits a stored message back into its quoted reference and the rest. A message is a
    /// quote message only when it OPENS with one or more `>` lines followed by a blank line
    /// and some text; anything else (including a `>` further down) is returned whole.
    static func split(_ content: String) -> (quote: String?, body: String) {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var quoted: [String] = []
        var index = 0
        while index < lines.count, lines[index].hasPrefix(">") {
            var line = lines[index].dropFirst()
            if line.first == " " { line = line.dropFirst() }
            quoted.append(String(line))
            index += 1
        }
        guard !quoted.isEmpty, index < lines.count,
              lines[index].trimmingCharacters(in: .whitespaces).isEmpty else { return (nil, content) }
        let body = lines[(index + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return (nil, content) }
        return (quoted.joined(separator: "\n"), body)
    }
}
