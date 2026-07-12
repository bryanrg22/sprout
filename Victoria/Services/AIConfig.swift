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
    var defaultCoachModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-6"
        case .openai:    return "gpt-4.1"
        }
    }

    /// Cheap/fast model for short routine phrasing (the daily insight line).
    var defaultInsightModel: String {
        switch self {
        case .anthropic: return "claude-haiku-4-5-20251001"
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

    // MARK: - Active provider (persisted)

    private static let providerKey = "ai_provider"

    /// The vendor the app currently uses. Defaults to `.anthropic` for existing
    /// installs / first launch. Writes through to `UserDefaults`.
    static var provider: AIProvider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey),
                  let p = AIProvider(rawValue: raw) else { return .anthropic }
            return p
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    // MARK: - Resolved model ids for the ACTIVE provider
    //
    // Resolution order: a user-typed override (per provider) → the provider's default.
    // An empty/blank override falls back to the default so a cleared field can't brick
    // requests.

    private static func modelOverrideKey(_ provider: AIProvider, tier: String) -> String {
        "ai_model_\(provider.rawValue)_\(tier)"   // e.g. "ai_model_openai_coach"
    }

    /// Read a per-provider model override (or nil/blank → use default).
    static func modelOverride(for provider: AIProvider, tier: ModelTier) -> String? {
        let raw = UserDefaults.standard.string(forKey: modelOverrideKey(provider, tier: tier.rawValue))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// Persist (or clear, when blank) a per-provider model override.
    static func setModelOverride(_ value: String?, for provider: AIProvider, tier: ModelTier) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = modelOverrideKey(provider, tier: tier.rawValue)
        if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
        else { UserDefaults.standard.set(trimmed, forKey: key) }
    }

    enum ModelTier: String { case coach, insight }

    /// The resolved model name for a tier on a given provider (override → default).
    static func model(for provider: AIProvider, tier: ModelTier) -> String {
        if let override = modelOverride(for: provider, tier: tier) { return override }
        switch tier {
        case .coach:   return provider.defaultCoachModel
        case .insight: return provider.defaultInsightModel
        }
    }

    /// Whether the ACTIVE provider has an API key stored — the gate every optional AI
    /// feature should use (checking only the Anthropic slot would wrongly disable
    /// features for an OpenAI user, and vice versa).
    static var hasActiveKey: Bool { KeychainStore.hasAPIKey(for: provider) }

    /// Strong coach/food model for the ACTIVE provider (override-aware).
    static var coachModel: String { model(for: provider, tier: .coach) }
    /// Cheap insight model for the ACTIVE provider (override-aware).
    static var insightModel: String { model(for: provider, tier: .insight) }

    // Back-compat aliases used as default arguments inside `AnthropicClient` and by a
    // couple of Anthropic-only call sites. Kept so those callers compile unchanged;
    // they now follow the active provider's strong/cheap model via the resolvers above.
    static var foodModel: String { coachModel }
    static var chatModel: String { coachModel }
    /// Heavy reasoning model for the one-time adaptive-Plan build/review pass (rare,
    /// high-value, worth the tokens): Opus on Anthropic, the strong GPT tier on OpenAI.
    static var planModel: String {
        switch provider {
        case .anthropic: return "claude-opus-4-8"
        case .openai:    return AIProvider.openai.defaultCoachModel
        }
    }

    enum AIError: LocalizedError {
        case missingKey, badResponse(String), decoding(String)
        var errorDescription: String? {
            switch self {
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
    func chatWithTools(system: String,
                       messages: [AnthropicClient.Msg],
                       tools: [[String: Any]],
                       model: String,
                       maxTokens: Int,
                       cachedSystemPrefix: String?) async throws -> AnthropicClient.ChatTurn

    func structured(system: String,
                    userContent: Any,
                    toolName: String,
                    toolDescription: String,
                    schema: [String: Any],
                    model: String,
                    maxTokens: Int) async throws -> [String: Any]
}

// Protocol requirements can't carry default arguments — these overloads restore the
// call shapes the app already uses (model defaults to the active provider's tier).
extension ToolCapableClient {
    func chatWithTools(system: String,
                       messages: [AnthropicClient.Msg],
                       tools: [[String: Any]],
                       maxTokens: Int = 1500,
                       cachedSystemPrefix: String? = nil) async throws -> AnthropicClient.ChatTurn {
        try await chatWithTools(system: system, messages: messages, tools: tools,
                                model: AIConfig.chatModel, maxTokens: maxTokens,
                                cachedSystemPrefix: cachedSystemPrefix)
    }

    func structured(system: String,
                    userContent: Any,
                    toolName: String,
                    toolDescription: String,
                    schema: [String: Any],
                    maxTokens: Int = 1300) async throws -> [String: Any] {
        try await structured(system: system, userContent: userContent, toolName: toolName,
                             toolDescription: toolDescription, schema: schema,
                             model: AIConfig.foodModel, maxTokens: maxTokens)
    }
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
