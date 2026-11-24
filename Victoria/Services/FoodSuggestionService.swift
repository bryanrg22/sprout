import Foundation

/// A single smart food suggestion: a short, specific, ADDITIVE/upgrade-oriented pick.
///
/// `Codable` so the UI can cache the last set in `UserDefaults`; `Identifiable` so it
/// drops straight into `ForEach`. The id is synthesized (not from the model) so cached
/// suggestions stay stable across decodes.
struct Suggestion: Codable, Identifiable, Equatable {
    /// What kind of move this is — drives the little tag + icon on the card.
    enum Kind: String, Codable {
        case swap     // upgrade a food she already eats to a better version
        case add      // add something (usually protein/fiber) to hit satiety/targets
        case idea     // a fresh meal/snack idea that fits the slot + her patterns
        case nearby   // references a real nearby place (only when location is on)

        /// SF Symbol for the card's icon chip.
        var systemImage: String {
            switch self {
            case .swap:   return "arrow.triangle.2.circlepath"
            case .add:    return "plus.circle.fill"
            case .idea:   return "lightbulb.fill"
            case .nearby: return "mappin.and.ellipse"
            }
        }

        /// Short uppercase tag shown above the title ("UPGRADE" / "ADD" / "IDEA" / "NEARBY").
        var tag: String {
            switch self {
            case .swap:   return "Upgrade"
            case .add:    return "Add"
            case .idea:   return "Idea"
            case .nearby: return "Nearby"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    /// A short, punchy headline (≈2–5 words).
    var title: String
    /// One specific sentence — the actual suggestion, concrete and doable.
    var detail: String
    /// A single relevant emoji for warmth.
    var emoji: String

    // Decode kind leniently (unknown strings fall back to `.idea`) and tolerate a missing
    // id in cached/legacy payloads by synthesizing one. Encoding stays standard.
    enum CodingKeys: String, CodingKey { case id, kind, title, detail, emoji }
    init(id: UUID = UUID(), kind: Kind, title: String, detail: String, emoji: String) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.emoji = emoji
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        let rawKind = (try? c.decode(String.self, forKey: .kind)) ?? "idea"
        kind = Kind(rawValue: rawKind) ?? .idea
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? "🍽️"
    }
}

/// Calls the configured LLM to turn the engine's factual `Context` into 2–3 phrased
/// suggestions. Mirrors `FoodPhotoAnalyzer`: a tight system prompt + forced tool use for
/// strict JSON, decoded into our model. NO numbers are decided here — the engine owns the
/// facts; the model only writes the words.
///
/// Tone (the load-bearing constraint): a sharp, encouraging friend who knows nutrition and
/// wants the user to WIN. Direct, specific, confident. Celebrate progress. Suggestions ADD or
/// UPGRADE — never restrict. And explicitly NO fragile therapy-speak / body-positivity
/// hedging / moralizing — the prompt bans that vocabulary outright.
struct FoodSuggestionService {

    /// The persona + hard tone rules. Kept separate from the per-call context so it's easy
    /// to read and reason about against the tone constraint.
    static let system = """
    You are the nutrition brain inside a results-focused nutrition app. Given a factual \
    snapshot of what the user has eaten today, the user's targets and goal, the current meal, \
    and the foods the user actually logs, produce 2–3 specific food suggestions by calling \
    the `suggest_foods` tool. Return ONLY the tool call — no other text. Write every \
    suggestion to the user directly, as "you".

    WHO THE USER IS: motivated and capable, and after RESULTS, not reassurance. Talk like a \
    sharp, encouraging friend who knows food and wants the user to win.

    WHAT GOOD SUGGESTIONS LOOK LIKE:
    - ADDITIVE or UPGRADE-oriented: add protein/fiber to hit satiety and the day's targets, or \
      swap something the user already eats for a better version of the SAME thing. Build on the \
      user's real foods (reference them by name when given) — don't invent unfamiliar meals.
    - Specific and doable RIGHT NOW for the current meal — name an actual food and roughly \
      how much ("add 1 cup egg whites, +25g protein"), not vague "eat more protein".
    - Grounded in the numbers given: if there is protein left to hit today, aim a pick at \
      closing that gap. Frame calories as fuel toward the stated goal, never as a budget being \
      spent, and follow the goal rule in the data you are given.
    - Use judgment about the foods AND the time of day. Anchor the pick on protein + whole \
      foods. Do NOT build a meal — especially breakfast — around a sometimes-treat or candy \
      that happens to be logged (gummies, soda, chips); a small treat as a finish is fine, but \
      it is never the foundation. And don't re-pitch something ALREADY eaten today (you're \
      given that list) — move on to the next useful thing. Match the meal: a breakfast pick \
      should read like breakfast.

    TONE — DIRECT AND CONFIDENT. Warm, but never precious. Celebrate progress plainly.
    HARD BANS (never use this vocabulary or framing):
    - No therapy-speak or body-positivity hedging: never "no food is bad", "be kind to \
      yourself", "no rush", "listen to your body", "this is about eating enough not less", \
      "honor your hunger", "all foods fit".
    - No guilt, shame, or restriction framing either: never "cheat", "guilty", "bad food", \
      "burn it off", "earn it", "cut back", "too much".
    - Don't moralize, don't hedge, don't pad. Just give the sharp, useful move.

    FORMAT (per suggestion): a short punchy `title` (about 2–5 words), exactly ONE specific \
    `detail` sentence, a single relevant `emoji`, and a `kind`: "swap" (upgrade a food the \
    user eats), "add" (add to hit satiety/targets), "idea" (a fresh pick that fits), or "nearby" \
    (ONLY if a nearby place is provided and it fits — at most one). Keep it tight.
    """

    /// The user turn around the engine's factual block. Pure.
    static func userTurn(for context: FoodSuggestionEngine.Context) -> String {
        "Here is the user's current data:\n\n"
            + FoodSuggestionEngine.renderPrompt(context)
            + "\n\nReturn 2–3 suggestions via the tool."
    }

    /// Strict JSON schema for the forced tool call. Bounds output to 2–3 items and a fixed
    /// `kind` enum so decoding is reliable.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "suggestions": [
                "type": "array",
                "minItems": 2,
                "maxItems": 3,
                "items": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": ["swap", "add", "idea", "nearby"]],
                        "title": ["type": "string"],
                        "detail": ["type": "string"],
                        "emoji": ["type": "string"],
                    ],
                    "required": ["kind", "title", "detail", "emoji"],
                ],
            ],
        ],
        "required": ["suggestions"],
    ]

    /// Decode envelope matching the tool schema.
    private struct Payload: Codable { var suggestions: [Suggestion] }

    /// Generate suggestions for the given factual context.
    ///
    /// Throws `AIConfig.AIError.missingKey` when no key is configured (the caller gates on
    /// `AIConfig.hasActiveKey` first, but we surface it cleanly anyway), and
    /// `AIConfig.AIError.badResponse` / `.decoding` on transport / parse failures.
    ///
    static func suggestions(for context: FoodSuggestionEngine.Context) async throws -> [Suggestion] {
        let client = try AIClient.makeFull()
        let prompt = userTurn(for: context)

        let content: [[String: Any]] = [AnthropicClient.textBlock(prompt)]

        let dict = try await client.structured(
            system: system,
            userContent: content,
            toolName: "suggest_foods",
            toolDescription: "Return 2–3 specific, additive food suggestions for the user.",
            schema: schema,
            model: AIConfig.model(for: .foodSuggestions),
            maxTokens: 700        // bounded: 3 short suggestions is well under this
        )

        let data = try JSONSerialization.data(withJSONObject: dict)
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw AIConfig.AIError.decoding(String(describing: error)) }

        // Defensive bound + drop any empty rows the model might emit.
        let cleaned = payload.suggestions
            .filter { !$0.title.isEmpty && !$0.detail.isEmpty }
            .prefix(3)
        guard !cleaned.isEmpty else { throw AIConfig.AIError.decoding("no suggestions") }
        return Array(cleaned)
    }
}
