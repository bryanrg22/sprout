import Foundation

/// Thin async client for the Anthropic Messages API. Supports plain chat,
/// "structured output" via forced tool use, and a tool-enabled chat turn where the
/// model may *optionally* request a function call (`chatWithTools`). Uses
/// JSONSerialization so the polymorphic content (text + images + tools) stays simple.
struct AnthropicClient {

    struct Msg { let role: String; let content: Any }   // content: String or [[String:Any]]

    private let key: String

    init() throws {
        guard let k = KeychainStore.apiKey(), !k.isEmpty else { throw AIConfig.AIError.missingKey }
        key = k
    }

    // MARK: - Plain text chat (the coach)
    func chat(system: String, messages: [Msg], model: String = AIConfig.chatModel, maxTokens: Int = 1024) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        let json = try await send(body)
        guard let content = json["content"] as? [[String: Any]] else {
            throw AIConfig.AIError.decoding("missing content")
        }
        let text = content.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw AIConfig.AIError.decoding("empty text") }
        return text
    }

    // MARK: - Chat with optional tools (the coach, with function calling)
    //
    // Same Messages API as `chat`, but advertises a set of `tools` so the model may
    // ask to call one. We DON'T force a tool (`tool_choice` is left at the default
    // "auto"), so a normal conversational reply still comes back as plain text — the
    // model only emits a tool_use block when the user actually asks for a change.
    //
    // The result is the full assistant turn, decomposed so the caller can decide what
    // to do (show text, and/or surface a tool request for one-tap confirmation):
    //  - `text`: any assistant prose in the turn (may be empty on a pure tool call).
    //  - `toolUse`: the first tool_use block, if the model requested one.
    //  - `assistantContent`: the raw `content` array, to be echoed back verbatim as the
    //    assistant message when continuing the turn with a tool_result (the API requires
    //    the original tool_use block to be present in history).
    struct ToolUse {
        let id: String          // tool_use id — must be echoed back as tool_result.tool_use_id
        let name: String        // which tool the model wants to run
        let input: [String: Any] // validated/parsed by the caller against the tool's schema
    }
    struct ChatTurn {
        let text: String
        let toolUse: ToolUse?
        /// The assistant turn's `content` blocks, verbatim — pass back as the assistant
        /// message (via `assistantMessage`) when continuing after a tool_result.
        let assistantContent: [[String: Any]]
    }

    /// One turn of a tool-enabled conversation. `tools` is an array of Anthropic tool
    /// schemas (`{name, description, input_schema}`). Returns the assistant turn.
    func chatWithTools(system: String,
                       messages: [Msg],
                       tools: [[String: Any]],
                       model: String = AIConfig.chatModel,
                       maxTokens: Int = 1500) async throws -> ChatTurn {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if !tools.isEmpty { body["tools"] = tools }   // omit `tool_choice` → defaults to "auto"

        let json = try await send(body)
        guard let content = json["content"] as? [[String: Any]] else {
            throw AIConfig.AIError.decoding("missing content")
        }

        let text = content
            .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            .joined()

        // First tool_use block, if any. (We expose one at a time — the coach proposes a
        // single change per turn, which also keeps the confirm UI unambiguous.)
        var toolUse: ToolUse?
        if let block = content.first(where: { ($0["type"] as? String) == "tool_use" }),
           let id = block["id"] as? String,
           let name = block["name"] as? String {
            let input = (block["input"] as? [String: Any]) ?? [:]
            toolUse = ToolUse(id: id, name: name, input: input)
        }

        // If the turn was cut off at max_tokens MID-tool-use, the tool_use block can be
        // incomplete — echoing it back in `continueTurn` would 400 the next request. Drop it
        // so we surface the prose instead; she can re-ask and it'll come through whole.
        if (json["stop_reason"] as? String) == "max_tokens", toolUse != nil {
            toolUse = nil
        }

        return ChatTurn(text: text, toolUse: toolUse, assistantContent: content)
    }

    /// Build the `assistant` message that echoes a prior turn's content back into history.
    /// Required before sending a `tool_result`: the API rejects a tool_result whose
    /// matching tool_use block isn't present in the preceding assistant turn.
    static func assistantMessage(content: [[String: Any]]) -> Msg {
        Msg(role: "assistant", content: content)
    }

    /// Build the `user` message carrying a tool_result for a given tool_use id. Send this
    /// after `assistantMessage(...)` to continue the turn so the model can respond to the
    /// outcome (success or decline). `isError` flags a failed/declined run.
    static func toolResultMessage(toolUseId: String, resultText: String, isError: Bool = false) -> Msg {
        var block: [String: Any] = [
            "type": "tool_result",
            "tool_use_id": toolUseId,
            "content": resultText,
        ]
        if isError { block["is_error"] = true }
        return Msg(role: "user", content: [block])
    }

    // MARK: - Structured output via forced tool use
    /// Returns the validated tool-input dictionary the model produced.
    func structured(system: String,
                    userContent: Any,
                    toolName: String,
                    toolDescription: String,
                    schema: [String: Any],
                    model: String = AIConfig.foodModel,
                    maxTokens: Int = 1300) async throws -> [String: Any] {
        let tool: [String: Any] = [
            "name": toolName,
            "description": toolDescription,
            "input_schema": schema,
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [["role": "user", "content": userContent]],
        ]
        let json = try await send(body)
        guard let content = json["content"] as? [[String: Any]] else {
            throw AIConfig.AIError.decoding("missing content")
        }
        for block in content where (block["type"] as? String) == "tool_use" {
            if let input = block["input"] as? [String: Any] { return input }
        }
        throw AIConfig.AIError.decoding("no tool_use block")
    }

    /// Build an image content block from JPEG/PNG data.
    static func imageBlock(_ data: Data, mediaType: String = "image/jpeg") -> [String: Any] {
        ["type": "image",
         "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]]
    }

    static func textBlock(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    // MARK: - Key validation
    /// Lightweight key check for Settings → "Verify key". Sends a 1-token request whose only
    /// purpose is to confirm the stored key authenticates with Anthropic. Throws
    /// `.badResponse` carrying Anthropic's own message (e.g. "invalid x-api-key") on a bad key,
    /// and `.missingKey` (from `init`) if none is stored. Goes through `send` directly so a
    /// clamped/empty reply can never read as a failure — we only care that auth succeeded.
    func validate() async throws {
        _ = try await send([
            "model": AIProvider.anthropic.defaultCoachModel,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]],
        ])
    }

    // MARK: - Networking
    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: AIConfig.baseURL.appendingPathComponent("v1/messages"))
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue(AIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIConfig.AIError.badResponse("no response")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            Diagnostics.shared.log("anthropic HTTP \(http.statusCode): \(msg)", .ai)
            throw AIConfig.AIError.badResponse(msg)
        }
        return json
    }
}

// MARK: - LLMClient conformance (additive)
//
// Cross-provider plain-text chat. This is a NEW overload that takes the vendor-neutral
// `[ChatTurnMsg]`; it maps each turn to the existing `Msg` (String content) and calls
// the original `chat(system:messages:model:maxTokens:)` above. The existing `Msg`-based
// API, `structured`, `chatWithTools`, and all their signatures are untouched, so current
// callers (InsightPhraser, FoodPhotoAnalyzer, CoachView, OnboardingCoachMessage) compile
// and behave exactly as before.
extension AnthropicClient: LLMClient {
    func chat(system: String,
              messages: [ChatTurnMsg],
              model: String,
              maxTokens: Int) async throws -> String {
        let mapped = messages.map { Msg(role: $0.role, content: $0.text) }
        return try await chat(system: system, messages: mapped, model: model, maxTokens: maxTokens)
    }
}
