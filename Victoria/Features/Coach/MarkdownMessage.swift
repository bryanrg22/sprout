import SwiftUI

/// Renders an assistant chat message as lightweight, chat-appropriate markdown.
///
/// Why this exists: SwiftUI's `Text(AttributedString(markdown:))` only styles INLINE markup
/// (bold, italic, code, links) — it ignores every block-level element, so a heading, a bullet
/// list, or a horizontal rule would render as literal `##`, `- `, and `---` characters. (This
/// is a documented SwiftUI limitation — `AttributedString` markdown is inline-only.) So we split
/// the message into blocks ourselves and lay each one out as a real view — a bulleted row, a
/// modest heading, a thin divider — using `AttributedString` only for the inline styling WITHIN a
/// block.
///
/// Deliberately minimal: paragraphs, bullet & numbered lists, modest headings, and thematic
/// breaks — no tables, code blocks, or images. This is a warm phone chat, not a document, and
/// Vita is told in the system prompt to format sparingly, so the common case is one or two short
/// paragraphs. This just makes the occasional list or emphasis look right instead of leaking raw
/// markup. User messages stay plain (they don't author markdown).
struct MarkdownMessage: View {
    private let blocks: [Block]
    private let color: Color

    init(_ text: String, color: Color = Theme.textPrimary) {
        self.color = color
        self.blocks = Self.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(for: block)
            }
        }
        .font(.body)   // cascades to every Text below unless a block overrides it (headings)
    }

    @ViewBuilder
    private func row(for block: Block) -> some View {
        switch block {
        case .paragraph(let s):
            Text(Self.inline(s)).foregroundStyle(color)

        case .heading(let s):
            // Modest on purpose — weight, not size. A big heading reads clinical in a chat bubble.
            Text(Self.inline(s))
                .font(.headline)
                .foregroundStyle(color)
                .padding(.top, 1)

        case .bullet(let indent, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(.body.weight(.bold)).foregroundStyle(Theme.brand)
                Text(Self.inline(s)).foregroundStyle(color)
            }
            .padding(.leading, CGFloat(indent) * 14)

        case .numbered(let indent, let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.brand)
                Text(Self.inline(s)).foregroundStyle(color)
            }
            .padding(.leading, CGFloat(indent) * 14)

        case .rule:
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    // MARK: - Block model

    private enum Block {
        case paragraph(String)        // one or more soft-wrapped lines (inline markup preserved)
        case heading(String)
        case bullet(Int, String)      // indent level, content
        case numbered(Int, Int, String) // indent level, displayed number, content
        case rule
    }

    // MARK: - Parsing

    /// Split the raw message into ordered blocks. Consecutive plain lines fold into one
    /// paragraph (keeping their soft line breaks); a blank line ends a paragraph; list/heading/
    /// rule lines each become their own block.
    private static func parse(_ raw: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flush(); continue }
            if isRule(trimmed) { flush(); blocks.append(.rule); continue }
            if let h = heading(trimmed) { flush(); blocks.append(.heading(h)); continue }
            if let (indent, content) = bullet(line) { flush(); blocks.append(.bullet(indent, content)); continue }
            if let (indent, n, content) = numbered(line) { flush(); blocks.append(.numbered(indent, n, content)); continue }

            paragraph.append(trimmed)
        }
        flush()
        return blocks
    }

    /// A thematic break: a line of only `-`, `*`, or `_` (3 or more), e.g. `---` / `***`.
    private static func isRule(_ s: String) -> Bool {
        guard s.count >= 3 else { return false }
        let chars = Set(s.filter { $0 != " " })
        return chars == ["-"] || chars == ["*"] || chars == ["_"]
    }

    /// `# …` through `###### …` → the heading text (requires a space after the hashes, so a
    /// bare `#hashtag` stays a paragraph).
    private static func heading(_ s: String) -> String? {
        guard s.first == "#" else { return nil }
        let hashes = s.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = s.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return String(rest.drop { $0 == " " })
    }

    /// Two leading spaces per indent level, capped so deep nesting can't run off the bubble.
    private static func indentLevel(_ line: String) -> Int {
        min(line.prefix { $0 == " " }.count / 2, 3)
    }

    /// `- `, `* `, or `+ ` (any indent) → (indent, content). Requires the trailing space so a
    /// stray `*emphasis*` isn't mistaken for a bullet.
    private static func bullet(_ line: String) -> (Int, String)? {
        let trimmed = line.drop { $0 == " " }
        guard let first = trimmed.first, "-*+".contains(first) else { return nil }
        let after = trimmed.dropFirst()
        guard after.first == " " else { return nil }
        return (indentLevel(line), String(after.drop { $0 == " " }))
    }

    /// `1. ` / `2) ` (any indent) → (indent, number, content). Requires the trailing space so a
    /// decimal like `1.5 cups` stays a paragraph.
    private static func numbered(_ line: String) -> (Int, Int, String)? {
        let trimmed = line.drop { $0 == " " }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        let after = trimmed.dropFirst(digits.count)
        guard let sep = after.first, sep == "." || sep == ")" else { return nil }
        let rest = after.dropFirst()
        guard rest.first == " " else { return nil }
        return (indentLevel(line), n, String(rest.drop { $0 == " " }))
    }

    // MARK: - Inline styling

    /// Inline-only markdown (bold / italic / code / links) within a single block, preserving the
    /// block's whitespace. Falls back to plain text if parsing fails.
    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(allowsExtendedAttributes: true,
                           interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(s)
    }
}

/// Reveals an assistant reply progressively — a gentle "typing it out" effect, like the big chat
/// apps. It's a VIEW-only animation over text that's already fully received and persisted: it just
/// animates how the freshest reply first appears, by feeding `MarkdownMessage` a growing prefix of
/// the source (so the markdown stays formatted the whole way, not plain-then-reformatted). Reveals
/// the whole message in ~1.1s regardless of length, and respects Reduce Motion (shows it at once).
struct TypewriterMarkdown: View {
    let fullText: String
    var color: Color = Theme.textPrimary
    var onComplete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0
    @State private var started = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        let total = fullText.count
        let shown = revealed >= total ? fullText : String(fullText.prefix(revealed))
        MarkdownMessage(shown, color: color)
            .onAppear { start(total: total) }
            .onDisappear { task?.cancel() }
    }

    private func start(total: Int) {
        guard !started else { return }
        started = true
        guard !reduceMotion, total > 0 else { revealed = total; onComplete(); return }
        let frames = 70                                    // ~70 × 16ms ≈ 1.1s end-to-end
        let step = max(1, Int((Double(total) / Double(frames)).rounded(.up)))
        task = Task { @MainActor in
            while revealed < total {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                revealed = min(total, revealed + step)
            }
            onComplete()
        }
    }
}

#if DEBUG
extension MarkdownMessage {
    /// Test-only: a compact, comparable description of the parsed blocks, e.g.
    /// `["h:Today", "b:0:Protein", "n:0:1:Yogurt", "rule", "p:Keep going"]`. Lets the parser's
    /// block detection (and its edge cases) be pinned by unit tests without exposing the private
    /// `Block` type. DEBUG-only, so it never ships.
    static func debugParse(_ s: String) -> [String] {
        parse(s).map { block in
            switch block {
            case .paragraph(let t):       return "p:\(t)"
            case .heading(let t):         return "h:\(t)"
            case .bullet(let i, let t):   return "b:\(i):\(t)"
            case .numbered(let i, let n, let t): return "n:\(i):\(n):\(t)"
            case .rule:                   return "rule"
            }
        }
    }
}
#endif
