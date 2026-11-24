import Foundation

/// Which LLM vendor the app talks to. Persisted in `UserDefaults` (default
/// `.anthropic`, so existing installs keep their current behavior). The user picks
/// this in AI Provider settings; the rest of the app just asks `AIClient.make()` for
/// "the active client" and never branches on the vendor directly.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai

    var id: String { rawValue }

    /// Friendly name for the settings picker.
    var label: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai:    return "OpenAI"
        }
    }

    /// Where to get a key + the expected key shape (shown as the secure-field hint).
    var keyHint: String {
        switch self {
        case .anthropic: return "Anthropic API key (sk-ant-…)"
        case .openai:    return "OpenAI API key (sk-…)"
        }
    }

    /// Page the user gets their key from (shown in the warm explainer copy).
    var consoleName: String {
        switch self {
        case .anthropic: return "console.anthropic.com"
        case .openai:    return "platform.openai.com"
        }
    }

    // MARK: - Per-provider model defaults
    //
    // Two tiers per vendor: a STRONG model for the coach + meal-photo vision, and a
    // CHEAP/fast model for the short daily insight line. These are sensible defaults
    // for the 2026 lineup; the user may override the actual model string in settings.

    /// Strong model for the coach + food vision (`chatModel`/`foodModel` tier).
    /// Full decision record with rejected alternatives: docs/MODEL_CHOICES.md.
    var defaultCoachModel: String {
        switch self {
        // Sonnet 5: same list price as Sonnet 4.6 ($3/$15, intro $2/$10 through
        // 2026-08-31) but a generation newer — upgraded the day it hit price parity.
        case .anthropic: return "claude-sonnet-5"
        // gpt-5.6-terra: the $2.50/$15 workhorse of the newest family — same price
        // as gpt-5.4, a generation newer (adopted the day GA was confirmed on a real
        // personal key). Runs with LOW reasoning effort in our chat loop (see
        // OpenAIClient).
        case .openai:    return "gpt-5.6-terra"
        }
    }

    /// Heavy model for the rare plan build / review pass.
    var defaultPlanModel: String {
        switch self {
        case .anthropic: return "claude-opus-4-8"
        case .openai:    return "gpt-5.6-sol"
        }
    }

    /// Cheap/fast model for short routine phrasing (the daily insight line).
    var defaultInsightModel: String {
        switch self {
        case .anthropic: return "claude-haiku-4-5-20251001"
        // Deliberately a NON-reasoning mini: this tier re-warms precomputed facts
        // inside tight 80–420-token budgets. A reasoning mini would spend hidden
        // thinking tokens against those budgets and add latency for zero quality
        // gain on a rewording task.
        case .openai:    return "gpt-4.1-mini"
        }
    }
}

/// Central AI configuration. The base URL is overridable so a free proxy
/// (e.g. a Cloudflare Worker) can be added later without code changes.
enum AIConfig {
    /// Override via UserDefaults key "ai_base_url" to route through a proxy.
    /// (Anthropic only — OpenAI uses its own fixed base; see `OpenAIClient`.)
    static var baseURL: URL {
        if let s = UserDefaults.standard.string(forKey: "ai_base_url"),
           let u = URL(string: s) { return u }
        return URL(string: "https://api.anthropic.com")!
    }

    static let anthropicVersion = "2023-06-01"

    // MARK: - Provider, key and model: decided by the app, never by the person
    //
    // The app has no AI settings. Everyone uses the built-in AI (`AIGateway`), Claude for
    // every text task and OpenAI only for the character picture, with the model each task
    // was measured on (`AITask`, `docs/EVAL_REPORT.md`). There is no key field, provider
    // picker or model field anywhere, so nothing a person does can send a request the
    // gateway would refuse. Tests and evaluations still pick a provider, key and model
    // through a scoped `AIRuntime`.

    /// The vendor for text tasks: Anthropic, unless a scoped runtime (tests, evals) says
    /// otherwise.
    static var provider: AIProvider { AIRuntime.effective?.provider ?? .anthropic }

    enum ModelTier: String { case coach, insight, plan }

    /// The tier default for a provider (used by a task with no measured default).
    static func model(for provider: AIProvider, tier: ModelTier) -> String {
        switch tier {
        case .coach:   return provider.defaultCoachModel
        case .insight: return provider.defaultInsightModel
        case .plan:    return provider.defaultPlanModel
        }
    }

    /// The key a call to `provider` carries, or nil when AI is unavailable here.
    ///
    /// Order: a scoped runtime's key (tests, evals) → the built-in gateway's placeholder →
    /// in DEBUG builds only, a key in the Keychain. The last is for the Simulator, which
    /// cannot do App Attest; it is filled only by the `SPROUT_ANTHROPIC_KEY` launch variable
    /// (`VictoriaApp`), and a Release build never reads it, so a key someone saved in an
    /// older version is ignored and the built-in AI is used instead.
    static func key(for provider: AIProvider) -> String? {
        if let scoped = AIRuntime.effective?.apiKey { return scoped.isEmpty ? nil : scoped }
        if let gateway = AIGateway.placeholder(for: provider) { return gateway }
        #if DEBUG
        if let stored = KeychainStore.apiKey(for: provider), !stored.isEmpty { return stored }
        #endif
        return nil
    }

    /// Whether text AI works here: the gate every optional AI feature uses.
    static var hasActiveKey: Bool { key(for: provider) != nil }

    /// Strong coach/food model for the ACTIVE provider (override-aware).
    static var coachModel: String { model(for: provider, tier: .coach) }
    /// Cheap insight model for the ACTIVE provider (override-aware).
    static var insightModel: String { model(for: provider, tier: .insight) }

    // Back-compat aliases used as default arguments inside the clients. Kept so those
    // callers compile unchanged; they follow the active provider's strong/cheap model
    // via the resolvers above.
    static var foodModel: String { coachModel }
    static var chatModel: String { coachModel }
    /// Heavy model for the one-time adaptive-Plan build/review pass (rare, high-value,
    /// worth the tokens): Opus 4.8 on Anthropic, gpt-5.6-sol on OpenAI (same $5/$30 as
    /// gpt-5.5, a generation newer). Fable 5 was evaluated and rejected — 2× the price
    /// for a benchmark edge that doesn't transfer to authoring a structured plan from a
    /// small, well-curated context. See docs/MODEL_CHOICES.md.
    static var planModel: String { model(for: provider, tier: .plan) }

    // MARK: - Image generation (the custom pixel character)

    /// What an image request sends. One place, so the model, the quality and the
    /// output shape are never named at a call site.
    struct ImageSetting: Equatable, Sendable {
        var model: String
        /// `low` | `medium` | `high` (| `xhigh` | `max` on Sunburst and Flare) | `auto`.
        var quality: String
        /// `WIDTHxHEIGHT`.
        var size: String
        /// `transparent` | `opaque` | `auto`.
        var background: String
        /// `png` | `webp` | `jpeg`. A transparent background needs `png` or `webp`.
        var outputFormat: String
    }

    /// The custom character (`AvatarGenerator`). Image generation is OpenAI-only:
    /// Anthropic's models do not produce images, so this setting has no provider
    /// dimension and the call always uses the OpenAI key, whatever provider the user
    /// chose for chat.
    ///
    /// Chosen on 2026-11-23 (EVAL_REPORT 23, 27): every candidate made a usable character
    /// every time, so the owner's rule decided ("the cheapest, but looking like the style we
    /// want"). `sunburst` at `low` costs $0.035 a character, the same as the cheapest
    /// candidate and a third less than either at `medium`, and draws the coarse, flat pixels
    /// closest to the two built-in characters. Its cost is time: about 17 s against 7 s for
    /// `flare` at `low`. Change this only together with the EVAL_REPORT section that measured
    /// it. Decision made by the owner: version 1 makes ONE image per person.
    static let avatarImage = ImageSetting(model: "gpt-image-2.6-sunburst",
                                          quality: "low",
                                          size: "1024x1024",
                                          background: "transparent",
                                          outputFormat: "png")

    /// Whether the character picture works here. Not `hasActiveKey`: it always goes to
    /// OpenAI, whatever provider the text tasks use.
    static var hasImageKey: Bool { key(for: .openai) != nil }

    enum AIError: LocalizedError {
        case missingKey, badResponse(String), decoding(String)
        /// The model reached `max_tokens` before it wrote anything the caller can use.
        /// On the Claude models that think by default this is the thinking using the whole
        /// cap (EVAL_REPORT 25); `thinkingTokens` is nil when the provider did not say.
        case cutOffBeforeOutput(model: String, cap: Int, thinkingTokens: Int?)
        var errorDescription: String? {
            switch self {
            case .cutOffBeforeOutput(let model, let cap, let thinking):
                let spent = thinking.map { ", \($0) of them spent thinking" } ?? ""
                return "The AI ran out of room before answering (\(model) stopped at \(cap) tokens\(spent))."

            case .missingKey:
                return "No API key set. Add your \(provider.label) key in More → AI Provider."
            case .badResponse(let s): return "The AI service returned an error: \(s)"
            case .decoding(let s): return "Couldn't read the AI response: \(s)"
            }
        }
    }
}

/// The FULL cross-provider surface: plain chat (via `LLMClient`), forced-schema
/// structured output, and the coach's optional-tool chat turn. Both vendors implement
/// all three, so every AI feature in the app follows the provider picked in Settings.
///
/// The shared wire vocabulary is Anthropic's (`AnthropicClient.Msg` content blocks,
/// `{name, description, input_schema}` tool schemas, `ChatTurn` results):
/// `OpenAIClient` translates to/from OpenAI's function-calling format at its boundary,
/// so call sites never branch on the vendor.
protocol ToolCapableClient: LLMClient {
    /// `forbidToolUse` sends the provider's tool_choice "none" while STILL passing the
    /// tool schemas — required because a turn whose history contains tool blocks must
    /// carry the tools parameter (Anthropic rejects it otherwise), yet the coach's
    /// depth cap needs the model to stop chaining and finalize in prose.
    func chatWithTools(system: String,
                       messages: [AnthropicClient.Msg],
                       tools: [[String: Any]],
                       model: String,
                       maxTokens: Int,
                       cachedSystemPrefix: String?,
                       forbidToolUse: Bool) async throws -> AnthropicClient.ChatTurn

    func structured(system: String,
                    userContent: Any,
                    toolName: String,
                    toolDescription: String,
                    schema: [String: Any],
                    model: String,
                    maxTokens: Int) async throws -> [String: Any]
}

/// Factory for "the active provider's client," so switching providers in Settings
/// just works across every AI feature.
enum AIClient {
    /// Build the active provider's `LLMClient` (plain-text chat only). Throws
    /// `AIConfig.AIError.missingKey` when that provider has no key stored yet.
    static func make() throws -> LLMClient {
        switch AIConfig.provider {
        case .anthropic: return try AnthropicClient()
        case .openai:    return try OpenAIClient()
        }
    }

    /// Build the active provider's full client (chat + structured + tool use).
    static func makeFull() throws -> any ToolCapableClient {
        switch AIConfig.provider {
        case .anthropic: return try AnthropicClient()
        case .openai:    return try OpenAIClient()
        }
    }
}
