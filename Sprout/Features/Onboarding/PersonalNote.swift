import Foundation

/// A personal note shown in onboarding to one person only.
///
/// The text is not in the repository. It lives in `Private/PersonalNote.json` on the machine
/// that builds the app (git-ignored), and a build phase copies it into the app only when the
/// file exists. A build without it (CI, anyone else's clone) has no note and no page for it.
/// With it, the page appears only after the person types the name it is addressed to.
///
///     { "recipient": "<first name>", "from": "<who wrote it>", "text": "<the note>" }
struct PersonalNote: Decodable, Equatable {
    let recipient: String
    let from: String
    let text: String

    static let resourceName = "PersonalNote"

    /// The note bundled with this build, or nil when there is none or it is incomplete.
    static func load(bundle: Bundle = .main) -> PersonalNote? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> PersonalNote? {
        guard let note = try? JSONDecoder().decode(PersonalNote.self, from: data) else { return nil }
        let fields = [note.recipient, note.from, note.text].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return fields.contains(where: \.isEmpty) ? nil : note
    }

    /// Whether a typed name is the person the note is addressed to: the whole name or its
    /// first word, ignoring case, accents and surrounding spaces. "Al" is not "Alex".
    func isFor(name: String) -> Bool {
        func fold(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        let typed = fold(name)
        let wanted = fold(recipient)
        guard !typed.isEmpty, !wanted.isEmpty else { return false }
        let firstWord = typed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? typed
        return typed == wanted || firstWord == wanted
    }
}
