import Foundation

/// The wording every prompt shares about whoever is using the app.
///
/// The prompts were first written for one person: they said "she" and assumed a goal of
/// losing weight. A prompt now names the user or says "the user", addresses them as
/// "you" in anything they will read, and takes the goal direction from the profile.
/// The protective intent is unchanged and is stated for any user: for someone losing,
/// never push eating less; for someone gaining, never frame eating as excess; for
/// everyone, no shame and no moralising. The product's stance stays "educate, celebrate
/// results, never shame"; nothing here is clinical screening.
///
/// The sentences deliberately avoid the exact phrases the output guardrails reject
/// ("eat less", "too much", "make up for", "guilt"…): a model echoes its prompt, and an
/// echoed banned phrase throws the reply away (EVAL_REPORT 10, defect 4).
enum GoalFraming {

    /// The rule about food a prompt carries for a goal direction. `nil` is for a prompt
    /// that is not told the direction (a rephraser handed only a finished sentence): it
    /// carries both halves and tells the model not to assume one.
    static func protectiveRule(_ direction: GoalPace.Direction?) -> String {
        let rule: String
        switch direction {
        case .lose?:
            rule = "The user's goal is to lose weight. Never suggest eating less, restricting, "
                + "skipping food or compensating for it with exercise; eating enough is part of "
                + "how this goal is reached."
        case .gain?:
            rule = "The user's goal is to gain weight. Never describe eating as excessive, as "
                + "overdoing it, or as something to compensate for; eating enough is the work "
                + "this goal asks for."
        case .maintain?:
            rule = "The user's goal is to hold a steady weight. Never suggest eating less or "
                + "restricting, and never describe eating as excessive."
        case nil:
            rule = "You are not told whether the user's goal is to lose, hold or gain weight, so "
                + "assume none of them: never suggest eating less or restricting, and never "
                + "describe eating as excessive."
        }
        return rule + " " + noShame
    }

    /// The half of the rule that does not depend on direction.
    static let noShame = "Never shame, never moralise about food, and never call a food good or bad."

    /// How a prompt refers to the user when it has a name, and when it does not.
    static func subject(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "the user" : trimmed
    }
}
