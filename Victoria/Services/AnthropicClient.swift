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
    ///
    /// **Prompt caching.** Pass `cachedSystemPrefix` with the STABLE part of the system prompt
    /// (persona/rules — byte-identical across turns) and `system` with the volatile part (live
    /// data). The prefix gets a `cache_control` breakpoint, so the API renders
    /// tools → cached prefix → volatile system → messages and serves everything up to the
    /// breakpoint from cache (~10% of input price) on every turn after the first. When
    /// `cachedSystemPrefix` is nil, behavior is exactly as before (plain string system).
    func chatWithTools(system: String,
                       messages: [Msg],
                       tools: [[String: Any]],
                       model: String = AIConfig.chatModel,
                       maxTokens: Int = 1500,
                       cachedSystemPrefix: String? = nil) async throws -> ChatTurn {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": Self.systemValue(system, cachedPrefix: cachedSystemPrefix),
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

        // Sanitize the content we echo back when continuing the turn. We only ever expose and
        // answer ONE tool_use, but the API requires a tool_result for EVERY tool_use block we send
        // back. So keep all text, and include ONLY the single tool_use we're handling (matched by
        // id) — dropping any extra tool calls the model emitted in the same turn. Without this, a
        // turn with two tool_use blocks 400s the follow-up request (surfacing as "Something went
        // wrong" right after the change was already applied). When there's no tool_use to answer,
        // strip them all so a stray/partial block can't break a later continuation either.
        let assistantContent: [[String: Any]]
        if let toolUse {
            assistantContent = content.filter { block in
                if (block["type"] as? String) == "tool_use" { return (block["id"] as? String) == toolUse.id }
                return true
            }
        } else {
            assistantContent = content.filter { ($0["type"] as? String) != "tool_use" }
        }

        return ChatTurn(text: text, toolUse: toolUse, assistantContent: assistantContent)
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

    // MARK: - Web-search-grounded research (the heavy plan build only)
    /// A research turn that searches the LIVE web — Anthropic's `web_search` server tool runs the
    /// search loop server-side — and returns a concise, CITED synthesis. Used to ground the one-time
    /// plan build in current evidence rather than the model's training alone (the review pass stays
    /// web-free by design). Returns the assistant's prose, with citations riding inline.
    ///
    /// Best-effort by contract: callers should `try?` this and fall back to an un-grounded build, so
    /// a key whose plan doesn't allow web search (or a transient failure) can never block plan
    /// creation. `usedSearch` reports whether the model actually ran a search, for diagnostics.
    func research(system: String,
                  userContent: String,
                  model: String = AIConfig.planModel,
                  maxUses: Int = 5,
                  maxTokens: Int = 1800) async throws -> (text: String, usedSearch: Bool) {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "tools": [["type": "web_search_20250305", "name": "web_search", "max_uses": maxUses]],
            "messages": [["role": "user", "content": userContent]],
        ]
        let json = try await send(body)
        guard let content = json["content"] as? [[String: Any]] else {
            throw AIConfig.AIError.decoding("missing content")
        }
        let text = content
            .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
        // The API emits `server_tool_use` blocks when it actually searches — surface that for logging.
        let usedSearch = content.contains { ($0["type"] as? String) == "server_tool_use" }
        return (text, usedSearch)
    }

    /// The `system` field for a request: a plain string (no caching), or — when a stable
    /// prefix is provided — an array of text blocks with a `cache_control` breakpoint on the
    /// prefix. The breakpoint caches everything rendered before it (tool schemas included).
    static func systemValue(_ system: String, cachedPrefix: String?) -> Any {
        guard let cachedPrefix, !cachedPrefix.isEmpty else { return system }
        return [
            ["type": "text", "text": cachedPrefix, "cache_control": ["type": "ephemeral"]],
            ["type": "text", "text": system],
        ]
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
        let httpBody = try JSONSerialization.data(withJSONObject: body)

        // Retry ONCE on a transient overload before giving up: the Anthropic API occasionally
        // returns 429 (rate limit) / 503 / 529 (overloaded) under load — exactly the "try again in
        // a moment" case. A single short backoff recovers it automatically instead of surfacing an
        // error. Everything else (4xx auth/validation, network) throws straight away.
        for attempt in 0..<2 {
            var req = URLRequest(url: AIConfig.baseURL.appendingPathComponent("v1/messages"))
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue(AIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = httpBody
            req.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw AIConfig.AIError.badResponse("no response")
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if (200..<300).contains(http.statusCode) {
                // Token/cache accounting → field log, so "is prompt caching actually working"
                // and "what does a day of AI cost" are answerable from a device.
                if let usage = json["usage"] as? [String: Any] {
                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                    let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
                    Diagnostics.shared.log(
                        "anthropic usage: in \(input) out \(output) cacheRead \(cacheRead) cacheWrite \(cacheWrite)",
                        .ai)
                }
                return json
            }

            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            Diagnostics.shared.log("anthropic HTTP \(http.statusCode): \(msg)", .ai)

            if [429, 503, 529].contains(http.statusCode), attempt == 0 {
                try? await Task.sleep(for: .milliseconds(700))
                continue
            }
            throw AIConfig.AIError.badResponse(msg)
        }
        throw AIConfig.AIError.badResponse("request failed after a retry")
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

// The native implementation of the cross-provider tool surface — `chatWithTools` and
// `structured` above already match the protocol signatures exactly.
extension AnthropicClient: ToolCapableClient {}
