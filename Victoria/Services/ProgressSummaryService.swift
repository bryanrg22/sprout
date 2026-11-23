import Foundation

/// A short, personal progress recap written by the LLM from a FACTUAL snapshot of the
/// user's whole journey — weight trend, nutrition, activity, and consistency. The numbers
/// are computed in code (`ProgressSummaryCard`); the model only writes the words.
struct ProgressSummary: Codable, Equatable {
    /// A short, warm headline (≈3–6 words), e.g. "Steady and on track".
    var headline: String
    /// One short paragraph (2–4 sentences) — what's going well + the trend, honestly.
    var body: String
    /// 2–4 punchy bullet wins / focus points (each ≈3–8 words, may start with an emoji).
    var highlights: [String]
}

/// Turns a factual progress snapshot into a `ProgressSummary`. Mirrors
/// `FoodSuggestionService`: a tight system prompt + forced tool use for strict JSON. Same
/// load-bearing tone contract — celebrate real results, be direct, NO therapy-speak / shame.
struct ProgressSummaryService {

    private static let system = """
    You are the coach inside a results-focused weight + nutrition app, writing a short \
    PROGRESS RECAP for the user from a factual snapshot of their journey. Report it by \
    calling the `write_summary` tool — return ONLY the tool call, no other text.

    WHO THEY ARE: motivated and capable; they want RESULTS and honest feedback, not \
    reassurance. Read ALL the data given — weight trend + rate, calories vs target, protein, \
    steps, and how consistently they log — and tell them the real story: what's genuinely \
    working, where the trend is heading, and ONE concrete thing to lean into next.

    HOW TO WRITE IT:
    - Be specific and grounded in their numbers (name the real figures — "down 1.2 lb/wk", \
      "protein hit 5 of 7 days", "9-day logging streak"). Never invent numbers not given.
    - Celebrate real progress plainly and confidently. If the trend is flat or off, say so \
      kindly and point at the lever that helps — don't sugar-coat, don't catastrophize.
    - Frame calories as FUEL toward the goal, never a budget being spent or a limit.

    TONE — direct, warm, confident. HARD BANS (never use this vocabulary or framing):
    - No therapy-speak / body-positivity hedging: never "be kind to yourself", "no rush", \
      "listen to your body", "all foods fit", "this is about more than a number".
    - No guilt / shame / restriction: never "cheat", "guilty", "bad", "burn it off", \
      "earn it", "cut back", "too much", "should".
    - Don't moralize, don't pad, don't hedge. Give them the real read + the next move.

    FORMAT: a short `headline` (3–6 words), a `body` of 2–4 sentences, and 2–4 `highlights` \
    (each 3–8 words; a leading emoji is welcome). Keep all of it tight.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "headline": ["type": "string"],
            "body": ["type": "string"],
            "highlights": [
                "type": "array",
                "minItems": 2,
                "maxItems": 4,
                "items": ["type": "string"],
            ],
        ],
        "required": ["headline", "body", "highlights"],
    ]

    /// Generate a recap from a pre-rendered factual snapshot string.
    static func summary(snapshot: String) async throws -> ProgressSummary {
        let client = try AIClient.makeFull()
        let content: [[String: Any]] = [
            AnthropicClient.textBlock("Here is the user's progress data:\n\n" + snapshot
                + "\n\nWrite the recap via the tool."),
        ]
        let dict = try await client.structured(
            system: system,
            userContent: content,
            toolName: "write_summary",
            toolDescription: "Write a short, honest, encouraging progress recap from the data.",
            schema: schema,
            model: AIConfig.model(for: .progressSummary),
            maxTokens: 600)

        let data = try JSONSerialization.data(withJSONObject: dict)
        let summary: ProgressSummary
        do { summary = try JSONDecoder().decode(ProgressSummary.self, from: data) }
        catch { throw AIConfig.AIError.decoding(String(describing: error)) }

        guard !summary.headline.isEmpty, !summary.body.isEmpty else {
            throw AIConfig.AIError.decoding("empty summary")
        }
        return summary
    }
}
