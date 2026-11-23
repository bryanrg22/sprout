import Foundation

/// The little catchphrases the companion blurts when you tap it — so the character
/// actually *sounds* like its person. One character's lines are a tester's own words (her
/// slang + inside-jokes), so tapping her companion feels like her talking back.
///
/// Keyed off `CompanionAvatar` so each person's companion has its own voice. Bryan's
/// list is a placeholder for now (he'll supply his own lines) — kept short + neutral
/// so his companion still talks, just not yet in his exact voice.
enum CompanionPhrases {

    /// The cute character's voice.
    static let victoria: [String] = [
        "Oh yeah", "Nice", "Hm",
        "Look at you",
        "Okay okay", "Yay",
    ]

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
        case .victoria: return victoria
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
