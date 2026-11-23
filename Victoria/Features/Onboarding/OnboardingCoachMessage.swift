import Foundation

/// Generates Vita's short, punchy closing note at the end of onboarding — the
/// "you're in, here's the vibe, let's go" beat.
///
/// - Optional: only calls the LLM when an API key exists; otherwise returns a warm,
///   direction-aware TEMPLATED message. The flow NEVER waits on or depends on the
///   network, and never errors out — there is always a message to show.
/// - Cheap: one short Haiku call (`AIConfig.insightModel`), low token cap.
/// - Numbers stay code-owned: this note is qualitative/motivational; the real targets
///   live in her plan. The model is never handed (and must never invent) a calorie/macro
///   number — the sanitizer falls back to the template if any digit slips in.
///
/// Tone: warm, sharp, encouraging, and DIRECT — like a friend who knows fitness and
/// wants her to win. No clinical hedging, no preciousness, no treating her as fragile.
enum OnboardingCoachMessage {

    /// Safe, pre-computed facts the view hands in (no raw calorie/macro numbers).
    struct Inputs {
        var name: String                 // "" → "friend"
        var direction: GoalPace.Direction
        var paceLabel: String            // e.g. "Relaxed", "Lean gain"
        var activityLabel: String        // e.g. "Lightly active"
        var note: String                 // her optional free-text (may be empty)
    }

    // MARK: - Public

    /// The closing message. Tries the LLM when a key exists; always falls back to a warm
    /// template on no-key / network / sanitizer failure. Safe to call from a `Task`.
    static func make(_ inputs: Inputs) async -> String {
        let fallback = template(for: inputs)
        guard AIConfig.hasActiveKey else { return fallback }
        return await written(inputs) ?? fallback
    }

    /// The model's note, or nil when the call failed or the sanitizer rejected the reply.
    /// Either way `make` shows the template, so both mean "not used".
    static func written(_ inputs: Inputs) async -> String? {
        do {
            let client = try AIClient.make()
            let reply = try await client.chat(
                system: system,
                messages: [ChatTurnMsg(role: "user", text: userPrompt(inputs))],
                model: AIConfig.model(for: .onboardingNote),   // cheap tier — short, warm phrasing
                maxTokens: 320
            )
            let cleaned = sanitize(reply)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil   // never let onboarding depend on the network
        }
    }

    // MARK: - System prompt

    static let system = """
    You are Vita, a warm, sharp, encouraging coach welcoming a new friend at the end of \
    onboarding. Write a short closing note — 2 to 4 sentences — that reflects what your new \
    friend just shared and sets a confident, motivating tone for getting started. Speak \
    directly to your friend as "you" throughout (never in the third person), use the name \
    once if given, and sound like a real friend who knows fitness — encouraging and direct, \
    never clinical, never precious, never treating anyone as fragile.

    What to do:
    - Name the goal you are told plainly (losing weight, maintaining, or building muscle — \
    whichever it is, and only that one) and frame it around real results and how good it \
    will feel — strong, energized, capable.
    - If there is a note, reflect ONE thing from it so your friend feels heard. If it's \
    empty, just give an energetic welcome.
    - End on momentum — you're in this together, starting now.

    Rules:
    - Don't invent specific calorie, macro, weight, or rate numbers — those live in the \
    plan. Keep this qualitative and motivating.
    - Be honest and encouraging: you can talk naturally about protein, training, steps, \
    consistency, a sensible deficit or surplus. Don't moralize about food, don't shame, \
    don't hedge. Follow the goal rule you are given.
    - At most one emoji. Output only the note — no headers, no lists, no disclaimer.
    """

    /// The user turn: just the safe, pre-computed facts + the user's note. No numbers.
    static func userPrompt(_ i: Inputs) -> String {
        let name = displayName(i.name)
        let goal: String
        switch i.direction {
        case .lose:     goal = "To lose weight — drop fat, feel leaner and stronger."
        case .maintain: goal = "To maintain — hold steady and lock in strong habits."
        case .gain:     goal = "To build muscle — a steady, lean gain."
        }
        let trimmedNote = i.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let notePart = trimmedNote.isEmpty
            ? "No extra context was shared — just give an energetic welcome."
            : "In \(name)'s own words: \"\(trimmedNote)\""
        return """
        Name: \(name)
        Goal: \(goal)
        Goal rule: \(GoalFraming.protectiveRule(i.direction))
        Chosen pace: \(i.paceLabel)
        Typical activity: \(i.activityLabel)
        \(notePart)

        Write the closing note now, to \(name) as "you", following every rule.
        """
    }

    // MARK: - Templated fallback (no key / any failure)

    /// A warm, direct, direction-aware message that needs no network. Reflects that she
    /// left a note when she did. Confident and results-focused — no hedging.
    static func template(for i: Inputs) -> String {
        let name = displayName(i.name)
        let opener: String
        switch i.direction {
        case .lose:
            opener = "\(name), you're in — let's go. Your plan's built to get real results: enough protein, smart choices, and consistency that actually sticks."
        case .maintain:
            opener = "\(name), you're in — let's go. We'll lock in the habits that keep you strong and steady, and make them feel easy."
        case .gain:
            opener = "\(name), let's build. A steady, protein-forward surplus — we'll add real muscle, not just weight."
        }
        let trimmedNote = i.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let close = trimmedNote.isEmpty
            ? "Show up, trust the process, and the results follow. I've got you 💪"
            : "Thanks for telling me what's going on — I'll keep it in mind and build this around your real life. I've got you 💪"
        return [opener, close].joined(separator: " ")
    }

    // MARK: - Sanitizer

    /// Keep the note qualitative: if the model invents any number (calories, macros,
    /// weight, rate), fall back to the template — numbers belong in her plan, not in prose.
    /// Also guards runaway length. Tone is handled by the system prompt, not a banlist.
    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 {
            s = String(s.dropFirst().dropLast())
        }
        guard !s.isEmpty else { return "" }
        // Numbers belong in the plan, not in this prose — fall back if any digit appears.
        if s.rangeOfCharacter(from: .decimalDigits) != nil { return "" }
        if s.count > 700 { return "" }
        return s
    }

    // MARK: - Helpers

    private static func displayName(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "friend" : t
    }
}
