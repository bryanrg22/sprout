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
        guard KeychainStore.hasAPIKey else { return fallback }
        do {
            let client = try AnthropicClient()
            let reply = try await client.chat(
                system: system,
                messages: [AnthropicClient.Msg(role: "user", content: userPrompt(inputs))],
                model: AIConfig.insightModel,   // cheap Haiku — short, warm phrasing
                maxTokens: 320
            )
            let cleaned = sanitize(reply)
            return cleaned.isEmpty ? fallback : cleaned
        } catch {
            return fallback   // never let onboarding depend on the network
        }
    }

    // MARK: - System prompt

    static let system = """
    You are Vita, a warm, sharp, encouraging coach welcoming a new friend at the end of \
    onboarding. Write a short closing note — 2 to 4 sentences — that reflects what she just \
    shared and sets a confident, motivating tone for getting started. Speak directly to her \
    ("you"), use her name once if given, and sound like a real friend who knows fitness — \
    encouraging and direct, never clinical, never precious, never treating her as fragile.

    What to do:
    - Name her goal plainly (losing weight, maintaining, building muscle) and frame it \
    around real results and how good she'll feel — strong, energized, capable.
    - If she shared a note, reflect ONE thing from it so she feels heard. If it's empty, \
    just welcome her with energy.
    - End on momentum — you're in this with her, starting now.

    Rules:
    - Don't invent specific calorie, macro, weight, or rate numbers — those live in her \
    plan. Keep this qualitative and motivating.
    - Be honest and encouraging: you can talk naturally about protein, training, steps, \
    consistency, a sensible deficit or surplus. Don't moralize about food, don't shame, \
    don't hedge.
    - At most one emoji. Output only the note — no headers, no lists, no disclaimer.
    """

    /// The user turn: just the safe, pre-computed facts + her note. No numbers.
    static func userPrompt(_ i: Inputs) -> String {
        let name = displayName(i.name)
        let goal: String
        switch i.direction {
        case .lose:     goal = "She wants to lose weight — drop fat, feel leaner and stronger."
        case .maintain: goal = "She wants to maintain — hold steady and lock in strong habits."
        case .gain:     goal = "She wants to build muscle — a steady, lean gain."
        }
        let trimmedNote = i.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let notePart = trimmedNote.isEmpty
            ? "She didn't share extra context — just welcome her with energy."
            : "In her own words, she shared: \"\(trimmedNote)\""
        return """
        Her name: \(name)
        Her goal: \(goal)
        Her chosen pace: \(i.paceLabel)
        Her typical activity: \(i.activityLabel)
        \(notePart)

        Write her closing note now, following every rule.
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
