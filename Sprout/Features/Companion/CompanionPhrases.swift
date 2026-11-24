import Foundation

/// The little catchphrases the companion blurts when you tap it, so the character
/// sounds like its person.
///
/// The cute character's real lines are one person's own words, so they are not in the
/// repository: like the personal note (`PersonalNote`), they live in
/// `Private/CompanionPhrases.json` on the machine that builds the app (git-ignored) and a
/// build phase copies them in when present:
///
///     { "cute": ["<line>", "<line>"] }
///
/// A build without that file (CI, anyone else's clone) uses the neutral lines below.
enum CompanionPhrases {

    /// The cute character's voice: the private lines when this build has them.
    static let cute: [String] = privateLines(for: "cute", bundle: .main) ?? [
        "Oh yeah", "Nice", "Hm", "Look at you", "Okay okay", "Yay",
    ]

    static let resourceName = "CompanionPhrases"

    /// The lines for `key` in the bundled private file, or nil when there is none.
    static func privateLines(for key: String, bundle: Bundle) -> [String]? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return lines(for: key, in: data)
    }

    /// The non-empty lines for `key` in the file's JSON, or nil when it has none.
    static func lines(for key: String, in data: Data) -> [String]? {
        guard let table = try? JSONDecoder().decode([String: [String]].self, from: data),
              let lines = table[key]?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                  .filter({ !$0.isEmpty }),
              !lines.isEmpty else { return nil }
        return lines
    }

    /// Bryan's voice — placeholder hype lines until he hands over his real list.
    static let bryan: [String] = [
        "Let's go", "Locked in", "Easy", "Dialed", "Sheesh", "We up",
    ]

    /// A custom character's voice: short, neutral lines that are nobody's catchphrases,
    /// since the person it was made from has not given it any.
    static let custom: [String] = [
        "Here we go", "Nice one", "One step at a time", "Feeling good", "We got this", "Onward",
    ]

    /// The phrase list for a given companion character.
    static func phrases(for avatar: CompanionAvatar) -> [String] {
        switch avatar {
        case .cute:     return cute
        case .bryan:    return bryan
        case .custom:   return custom
        }
    }

    /// A random line for this companion, avoiding an immediate repeat of `last` so
    /// two taps in a row never say the same thing (when there's more than one line).
    static func random(for avatar: CompanionAvatar, excluding last: String? = nil) -> String {
        let all = phrases(for: avatar)
        guard !all.isEmpty else { return "" }
        let pool = all.count > 1 ? all.filter { $0 != last } : all
        return pool.randomElement() ?? all[0]
    }
}
