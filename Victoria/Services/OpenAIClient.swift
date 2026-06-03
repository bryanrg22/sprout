import Foundation

/// Thin async client for the OpenAI Chat Completions API, conforming to `LLMClient`.
/// Mirrors `AnthropicClient`'s shape: key pulled from the Keychain at init, a single
/// private `send`, `JSONSerialization` bodies, and graceful (never-crashing) error
/// handling that throws `AIConfig.AIError`.
///
/// Scope: plain-text chat only (the coach + the insight/onboarding phrasers). Meal-photo
/// vision and tool-use remain Anthropic-specific and live on `AnthropicClient`.
struct OpenAIClient: LLMClient {

    /// Chat Completions endpoint. Fixed host (OpenAI doesn't share Anthropic's
    /// `ai_base_url` proxy override, which targets the Anthropic Messages API).
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private let key: String

    init() throws {
        guard let k = KeychainStore.apiKey(for: .openai), !k.isEmpty else {
            throw AIConfig.AIError.missingKey
        }
        key = k
    }

    // MARK: - Plain text chat (LLMClient)
    //
    // Maps `system` + the neutral `[ChatTurnMsg]` onto OpenAI's flat message list:
    // the system prompt becomes the first message with role "system", then each turn's
    // role passes through ("user"/"assistant"). Returns `choices[0].message.content`.
    func chat(system: String,
              messages: [ChatTurnMsg],
              model: String,
              maxTokens: Int) async throws -> String {
        var wire: [[String: Any]] = []
        if !system.isEmpty {
            wire.append(["role": "system", "content": system])
        }
        wire.append(contentsOf: messages.map { ["role": $0.role, "content": $0.text] })

        var body: [String: Any] = [
            "model": model,
            "messages": wire,
        ]
        // o-series/reasoning models reject `max_tokens` and require `max_completion_tokens`.
        body[Self.tokenParam(for: model)] = maxTokens

        let json = try await send(body)
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIConfig.AIError.decoding("missing choices[0].message.content")
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIConfig.AIError.decoding("empty text") }
        return text
    }

    // MARK: - Key validation
    /// Mirror of `AnthropicClient.validate` for the OpenAI key (Settings → "Verify key").
    /// A 1-token request whose only purpose is to confirm the key authenticates; routes through
    /// `send` so a clamped reply can't read as a failure. Throws `.badResponse` carrying
    /// OpenAI's own message (e.g. "Incorrect API key provided") on a bad key.
    func validate() async throws {
        let model = AIProvider.openai.defaultCoachModel
        _ = try await send([
            "model": model,
            Self.tokenParam(for: model): 1,
            "messages": [["role": "user", "content": "ping"]],
        ])
    }

    /// OpenAI's reasoning models (o1/o3/o4…) reject `max_tokens` and require
    /// `max_completion_tokens`; everything else (gpt-4o, gpt-4.1, …) takes `max_tokens`.
    /// Matched on the leading "o<digit>" so "gpt-4o" (which DOES take max_tokens) is excluded.
    static func tokenParam(for model: String) -> String {
        let m = model.lowercased()
        let isReasoning = ["o1", "o3", "o4", "o5"].contains { m.hasPrefix($0) }
        return isReasoning ? "max_completion_tokens" : "max_tokens"
    }

    // MARK: - Networking
    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIConfig.AIError.badResponse("no response")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            // OpenAI errors come back as { "error": { "message": ... } }, same shape we
            // surface for Anthropic.
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            throw AIConfig.AIError.badResponse(msg)
        }
        return json
    }
}
