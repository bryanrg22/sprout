import Foundation

/// The "expensive brain" half of the proactive-AI architecture (see RESEARCH_ai_native.md):
/// the free `DailyInsightEngine` already DECIDED what to say; this only makes the wording
/// feel human, using the cheap Haiku model. It is strictly a *rephraser*, never a detector.
///
/// Cost & safety design:
/// - One short Haiku call per day max (the caller gates it to once-daily). ~1–3¢/user/month.
/// - Hard guardrails: it may only reframe the insight it's given; it must NOT invent calorie
///   or macro numbers, give medical advice, or mention restriction/deficits/"good-bad" foods.
/// - ALWAYS falls back to the engine's template on any failure (no key, network, bad output),
///   so the dashboard never breaks or waits on the network to show something.
enum InsightPhraser {

    private static let system = """
    You are Vita, a warm, upbeat weight-loss buddy texting one short line to your friend. \
    You'll be given a factual observation about her day that has ALREADY been decided. Your \
    only job is to rephrase THAT observation in your own warm, encouraging voice.

    Hard rules:
    - Keep it to ONE short sentence (max ~22 words). Texting tone, not an essay.
    - Reframe ONLY the given observation. Do NOT add new facts, numbers, calorie/macro \
    targets, or any health/medical advice.
    - Never push restriction, so NEVER mention eating less, cutting, deficits, "burning off," \
    or label any food good/bad. Celebrate eating enough, protein, hydration, movement, and \
    showing up. Never shame.
    - At most one tasteful emoji. No hashtags. Output just the sentence, nothing else.
    """

    /// Rephrase a chosen insight. Returns a warm one-liner, or `fallback` (the engine's
    /// template) if anything goes wrong. `context` is a tiny factual hint, e.g.
    /// "28-day logging streak" — never numbers the model should parrot as advice.
    static func phrase(template fallback: String, factualHint: String) async -> String {
        guard KeychainStore.hasAPIKey(for: AIConfig.provider) else { return fallback }
        do {
            let client = try AIClient.make()
            let user = "Observation to rephrase: \(factualHint)\nHer current template line (match this meaning): \"\(fallback)\""
            let reply = try await client.chat(
                system: system,
                messages: [ChatTurnMsg(role: "user", text: user)],
                model: AIConfig.insightModel,
                maxTokens: 80
            )
            let cleaned = sanitize(reply)
            return cleaned.isEmpty ? fallback : cleaned
        } catch {
            return fallback   // never let the coach line depend on the network
        }
    }

    /// Trim quotes/whitespace and reject anything that slipped past the guardrails
    /// (a banned restriction word, or a suspiciously long/multi-line answer).
    private static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 {
            s = String(s.dropFirst().dropLast())
        }
        let lower = s.lowercased()
        let banned = ["eat less", "cut back", "cutting", "deficit", "too much",
                      "burn off", "burn it off", "cheat", "bad food", "good food", "guilt"]
        if banned.contains(where: lower.contains) { return "" }   // → caller uses fallback
        if s.count > 180 { return "" }                            // runaway → fallback
        return s
    }
}
