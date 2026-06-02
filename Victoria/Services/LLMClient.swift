import Foundation

/// One turn of a plain-text conversation, provider-agnostic. This is the *common
/// denominator* the app needs across vendors: a role plus plain text. (Anthropic's
/// richer `AnthropicClient.Msg` carries `Any` content for images/tool blocks — those
/// vision/tool features stay Anthropic-specific and are NOT part of this protocol.)
///
/// `Sendable` so it can cross actor boundaries (the coach/insight calls hop to a
/// background `Task` and back to the main actor).
struct ChatTurnMsg: Sendable {
    /// "user" or "assistant" (mirrors both vendors' role strings).
    let role: String
    let text: String

    init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

/// The minimal LLM capability the app shares across providers: a single plain-text
/// chat turn. A concrete client (Anthropic or OpenAI) maps `system` + `messages`
/// onto its own wire format and returns the assistant's text.
///
/// Implementations MUST:
/// - throw `AIConfig.AIError.missingKey` when no key is configured (callers such as
///   `CoachView` catch this case specifically), and
/// - never crash — surface failures as a thrown `AIConfig.AIError` instead.
protocol LLMClient {
    func chat(system: String,
              messages: [ChatTurnMsg],
              model: String,
              maxTokens: Int) async throws -> String
}
