import Foundation

/// Maintains the coach's long-term memory (`CoachMemory`) so Vita feels like one
/// continuous conversation. This is the "consolidation on overflow" half of the
/// architecture: when chat messages scroll past the verbatim recent window, we fold them
/// into the durable notes + rolling summary via ONE background LLM call (off the user's
/// turn), so they can leave the window without anything being lost.
///
/// Cost & safety design (mirrors `InsightPhraser`):
/// - ONE call on the cheap "insight"-tier model — this is background summarization, not the
///   live coach reply, so it doesn't need the strong model.
/// - Provider-aware: uses `AIClient.make()` so it follows the user's chosen vendor, and
///   `AIConfig.insightModel` for that vendor's cheap tier.
/// - No key → no-op (returns `nil`). It also never throws to the caller and never blocks the
///   user-visible reply; the caller runs it in a detached/background `Task`.
/// - Numbers stay code-owned: the system prompt forbids storing weights, calories, macros,
///   or targets in memory. Those are computed live and authoritatively by `CoachContext`.
enum CoachMemoryService {

    /// The result of a consolidation pass: the new durable notes + rolling summary to persist.
    struct Result: Sendable {
        let profileNotes: String
        let conversationSummary: String
    }

    /// A minimal, `Sendable` snapshot of a chat message for the background call. We copy the
    /// fields we need off the `@Model` on the main actor before hopping to the network, so we
    /// never touch SwiftData objects across actors.
    struct MessageSnapshot: Sendable {
        let role: String          // "user" or "assistant"
        let content: String
        let createdAt: Date

        init(role: String, content: String, createdAt: Date) {
            self.role = role
            self.content = content
            self.createdAt = createdAt
        }
    }

    // Soft bounds we ask the model to respect, and clamp to as a backstop so memory can
    // never grow without limit (which would slowly inflate every coach turn's cost).
    static let notesCharBudget = 1500
    static let summaryCharBudget = 1000

    // MARK: - Pure selection helper (testable)

    /// The un-folded older messages that should be consolidated, given the full transcript.
    ///
    /// "Older" = NOT in the most recent `windowSize` non-seed messages (those still travel
    /// verbatim with every turn, so folding them would be redundant). "Un-folded" = strictly
    /// newer than `summarizedThrough` (the high-water mark of what's already in memory), so we
    /// never re-summarize the same message twice.
    ///
    /// This is a pure function of its inputs (no SwiftData, no clock) so the overflow logic is
    /// unit-testable in isolation.
    ///
    /// - Parameters:
    ///   - messages: the full conversation, oldest-first. Seed messages are filtered out here.
    ///   - windowSize: how many recent non-seed messages stay in the verbatim window
    ///     (must match `CoachView.maxHistoryMessages`).
    ///   - summarizedThrough: `createdAt` of the newest already-folded message, or `nil`.
    /// - Returns: the messages to fold, oldest-first (possibly empty).
    static func messagesToConsolidate(messages: [ChatMessage],
                                      windowSize: Int,
                                      summarizedThrough: Date?) -> [ChatMessage] {
        // Only real conversation turns are eligible — the canned welcome seed is persona, not
        // history, and is never sent to the API, so it must never enter memory either.
        let real = messages.filter { !$0.isSystemSeed }
        guard real.count > windowSize else { return [] }   // nothing has left the window yet

        // Everything before the recent window is "older".
        let older = real.dropLast(windowSize)

        // Of those, keep only the ones we haven't folded in yet.
        let unfolded: [ChatMessage]
        if let cutoff = summarizedThrough {
            unfolded = older.filter { $0.createdAt > cutoff }
        } else {
            unfolded = Array(older)
        }
        return unfolded
    }

    /// Convenience: are there any un-folded older messages? (Same inputs as
    /// `messagesToConsolidate`.) Lets the caller decide whether to even spin up a `Task`.
    static func hasWorkToDo(messages: [ChatMessage],
                            windowSize: Int,
                            summarizedThrough: Date?) -> Bool {
        !messagesToConsolidate(messages: messages,
                               windowSize: windowSize,
                               summarizedThrough: summarizedThrough).isEmpty
    }

    // MARK: - Consolidation (the background LLM call)

    private static let system = """
    You maintain the long-term memory for a friendly, knowledgeable weight-loss coach named \
    Vita, so she can feel like she's having one continuous conversation with her friend across \
    many sessions. You'll be given Vita's CURRENT durable notes, her CURRENT rolling summary, \
    and a batch of OLDER chat messages that are about to scroll out of her short-term window. \
    Fold the new information from those messages into the two memory blocks and return the \
    UPDATED versions.

    Maintain two things:

    1. DURABLE NOTES — a compact, curated list of qualitative facts about her that stay true \
    over time: her preferences, life context and routine, foods she likes and dislikes, what \
    motivates her, obstacles she runs into, and real wins. Update it: add genuinely new facts, \
    refine ones that changed, drop anything stale or trivial. Keep it tight (about \
    \(notesCharBudget) characters max). Markdown bullets are fine.

    2. ROLLING SUMMARY — a concise prose recap of what's been going on in the conversation \
    lately (themes, what she's working on, where things stand), so continuity survives after \
    the older messages disappear. Rewrite it to absorb the new batch; keep it about \
    \(summaryCharBudget) characters max. It should read as a brief catch-up, not a transcript.

    CRITICAL RULES:
    - NEVER store numbers that the app owns: no body weights, no calorie counts, no macro \
    grams, no calorie/step/water targets, no goal weight, no dates of weigh-ins. Those are \
    computed live from her real data and are the single source of truth — duplicating them in \
    memory would let them go stale and mislead her. Keep memory PURELY qualitative.
    - Tone for the notes: warm but direct and results-focused. She is a capable adult pursuing \
    a goal, NOT fragile and NOT someone with an eating disorder. Do not add therapy-speak, \
    body-image hedging, or any moralizing about food. Just record useful facts plainly.
    - Don't invent facts. Only record what the messages actually support.
    - Output STRICT JSON ONLY, no prose, no code fences, exactly this shape:
    {"notes": "<updated durable notes>", "summary": "<updated rolling summary>"}
    """

    /// Fold a batch of older messages into the memory's notes + rolling summary via one
    /// background LLM call. Persisting the result is the caller's job (so it stays on the main
    /// actor / its `ModelContext`). Returns `nil` on any failure or when there's no key — the
    /// caller then simply leaves memory unchanged (and should NOT advance the high-water mark).
    ///
    /// - Parameters:
    ///   - currentNotes: the existing `CoachMemory.profileNotes`.
    ///   - currentSummary: the existing `CoachMemory.conversationSummary`.
    ///   - olderMessages: the batch leaving the window, oldest-first (from
    ///     `messagesToConsolidate`, snapshotted off SwiftData).
    ///   - profileName: the user's display name, for nicer notes ("She/your friend" if empty).
    static func consolidate(currentNotes: String,
                            currentSummary: String,
                            olderMessages: [MessageSnapshot],
                            profileName: String) async -> Result? {
        // Nothing to fold → nothing to do.
        guard !olderMessages.isEmpty else { return nil }
        // No key for the active provider → skip silently (matches InsightPhraser's gate).
        guard KeychainStore.hasAPIKey(for: AIConfig.provider) else { return nil }

        let transcript = olderMessages.map { snap in
            let who = snap.role == "user" ? (profileName.isEmpty ? "Friend" : profileName) : "Vita"
            return "\(who): \(snap.content)"
        }.joined(separator: "\n")

        let user = """
        CURRENT DURABLE NOTES:
        \(currentNotes.isEmpty ? "(none yet)" : currentNotes)

        CURRENT ROLLING SUMMARY:
        \(currentSummary.isEmpty ? "(none yet)" : currentSummary)

        OLDER MESSAGES NOW LEAVING THE WINDOW (oldest first):
        \(transcript)

        Return the updated {"notes", "summary"} JSON now.
        """

        do {
            let client = try AIClient.make()
            let reply = try await client.chat(
                system: system,
                messages: [ChatTurnMsg(role: "user", text: user)],
                model: AIConfig.insightModel,   // cheap tier — this is background summarization
                maxTokens: 1200
            )
            return parse(reply, fallbackNotes: currentNotes, fallbackSummary: currentSummary)
        } catch {
            // Never surface an error or block anything — but DO leave a trace: if this keeps
            // failing, the high-water mark never advances and unfolded messages quietly pile
            // into every future prompt (a slow token leak, invisible without this line).
            Diagnostics.shared.log("memory consolidation failed (\(olderMessages.count) msgs pending): \(error.localizedDescription)", .coach)
            return nil
        }
    }

    // MARK: - Parsing

    /// Parse the model's strict-JSON reply into a `Result`, clamping each field to its budget.
    /// Tolerant of stray code fences. On a missing field we keep the existing value (passed as
    /// the fallback) so a partial answer can't wipe good memory. Returns `nil` only if the
    /// reply has neither field at all.
    static func parse(_ raw: String, fallbackNotes: String, fallbackSummary: String) -> Result? {
        let cleaned = stripCodeFences(raw)
        guard let data = cleaned.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        // Treat an empty-after-trim field as "not provided" so the model can never accidentally
        // wipe good durable memory by returning "" — we keep the prior value in that case.
        let notes = nonEmpty((obj["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
        let summary = nonEmpty((obj["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
        // If the model returned neither usable field, treat as a failure (don't clobber memory).
        guard notes != nil || summary != nil else { return nil }

        return Result(
            profileNotes: clamp(notes ?? fallbackNotes, to: notesCharBudget),
            conversationSummary: clamp(summary ?? fallbackSummary, to: summaryCharBudget)
        )
    }

    /// `nil` for nil/empty input, otherwise the string — so empty fields fall back to prior memory.
    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// Drop a leading/trailing ```json … ``` fence if the model added one despite instructions.
    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        // Remove the first line (``` or ```json) and a trailing ``` line.
        if let firstNewline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: firstNewline)...])
        }
        if let fence = t.range(of: "```", options: .backwards) {
            t = String(t[..<fence.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hard backstop on length so memory can't grow unbounded (the model is also asked to keep
    /// it tight). Trims on a word boundary when possible so we don't cut mid-word.
    private static func clamp(_ s: String, to maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        let hardCut = String(s.prefix(maxChars))
        if let lastSpace = hardCut.lastIndex(of: " "), lastSpace > hardCut.startIndex {
            return String(hardCut[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return hardCut + "…"
    }
}
