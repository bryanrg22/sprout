import Foundation

/// Thin async client for the OpenAI Chat Completions API, conforming to `LLMClient`.
/// Mirrors `AnthropicClient`'s shape: key pulled from the Keychain at init, a single
/// private `send`, `JSONSerialization` bodies, and graceful (never-crashing) error
/// handling that throws `AIConfig.AIError`.
///
/// Scope: the FULL cross-provider surface. Plain-text chat lives here; the
/// `ToolCapableClient` extension below adds function calling (the coach's tools),
/// vision + forced structured output (meal photos), and web-search research
/// (the plan) — all translated from the app's Anthropic-shaped wire vocabulary.
struct OpenAIClient: LLMClient {

    /// Chat Completions endpoint. Fixed host (OpenAI doesn't share Anthropic's
    /// `ai_base_url` proxy override, which targets the Anthropic Messages API).
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Responses API endpoint — OpenAI's server-side-tools surface. Only the
    /// web-search-grounded `research` call uses it; everything else stays on
    /// Chat Completions.
    private static let responsesEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    /// Model for the web-search research pass — same heavy tier as the plan build
    /// (gpt-5.6-sol; the `web_search` tool runs on gpt-5.x Responses models, not
    /// gpt-4.1). Research is best-effort everywhere it's called, so an account
    /// without access degrades to an un-grounded plan instead of failing.
    static let researchModel = "gpt-5.6-sol"

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
        if let effort = Self.reasoningEffort(for: model) { body["reasoning_effort"] = effort }

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
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
        ]
        // Reasoning models (gpt-5.x) think BEFORE they speak, and thinking counts
        // against max_completion_tokens — a 1-token cap fails with a max_tokens error
        // even when auth and model access are fine (caught live in the sim). Give a
        // small real budget there; any 2xx proves the key, which is all this checks.
        let budget = Self.reasoningEffort(for: model) == nil ? 1 : 128
        body[Self.tokenParam(for: model)] = budget
        if let effort = Self.reasoningEffort(for: model) { body["reasoning_effort"] = effort }
        _ = try await send(body)
    }

    /// OpenAI's reasoning models (o-series and the gpt-5 family) reject `max_tokens`
    /// and require `max_completion_tokens`; everything else (gpt-4o, gpt-4.1, …) takes
    /// `max_tokens`. Matched on prefixes so "gpt-4o" (which DOES take max_tokens) is
    /// excluded, while a user-typed override like "gpt-5.5" is handled correctly.
    static func tokenParam(for model: String) -> String {
        let m = model.lowercased()
        let isReasoning = ["o1", "o3", "o4", "o5", "gpt-5"].contains { m.hasPrefix($0) }
        return isReasoning ? "max_completion_tokens" : "max_tokens"
    }

    /// Reasoning effort for gpt-5-family models on Chat Completions, nil for
    /// non-reasoning models. Pinned LOW by design: hidden thinking tokens bill as
    /// output AND count against `max_completion_tokens`, so unbounded effort inside
    /// our tight per-feature budgets (80–2,200 tokens) could spend the whole budget
    /// before writing a word.
    ///
    /// `withTools`: the gpt-5.6 family REJECTS function tools combined with a
    /// reasoning effort on Chat Completions (live 400: "use /v1/responses or set
    /// reasoning_effort to 'none'") — so tool-carrying requests pin `none` there.
    /// That matches the doctrine anyway: a chat tool turn ("log my water") shouldn't
    /// deliberate, and the pass that deserves reasoning (plan research) runs on the
    /// Responses API where reasoning + tools coexist.
    static func reasoningEffort(for model: String, withTools: Bool = false) -> String? {
        let m = model.lowercased()
        guard m.hasPrefix("gpt-5") else { return nil }
        if withTools && m.hasPrefix("gpt-5.6") { return "none" }
        return "low"
    }

    // MARK: - Web-search-grounded research (the heavy plan build only)
    /// OpenAI counterpart of `AnthropicClient.research`: a Responses API call with the
    /// server-side `web_search` tool, returning a concise cited synthesis. Same contract —
    /// callers `try?` this and fall back to an un-grounded build on any failure.
    func research(system: String,
                  userContent: String,
                  model: String = OpenAIClient.researchModel,
                  maxTokens: Int = 1800) async throws -> (text: String, usedSearch: Bool) {
        let body: [String: Any] = [
            "model": model,
            "instructions": system,
            "input": userContent,
            "tools": [["type": "web_search"]],
            "max_output_tokens": maxTokens,
            // gpt-5.x reasoning draws from the output budget — keep the thinking light so
            // a search-and-synthesize task can't burn the whole budget before writing.
            "reasoning": ["effort": "low"],
        ]
        let json = try await send(body, to: Self.responsesEndpoint)
        let parsed = Self.parseResponsesOutput(json)
        guard !parsed.text.isEmpty else { throw AIConfig.AIError.decoding("empty research text") }
        return parsed
    }

    /// Responses API output → (assistant text, did a web search actually run). Pure and
    /// unit-tested: text lives in `output[].content[]` blocks of type `output_text`;
    /// a completed `web_search_call` item is the searched signal.
    static func parseResponsesOutput(_ json: [String: Any]) -> (text: String, usedSearch: Bool) {
        let output = (json["output"] as? [[String: Any]]) ?? []
        // Only a COMPLETED call counts as "actually searched" — a failed search item
        // would otherwise report grounding that never happened.
        let usedSearch = output.contains {
            ($0["type"] as? String) == "web_search_call" && ($0["status"] as? String) == "completed"
        }
        var text = output
            .filter { ($0["type"] as? String) == "message" }
            .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
            .compactMap { ($0["type"] as? String) == "output_text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
        if text.isEmpty { text = (json["output_text"] as? String) ?? "" }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), usedSearch)
    }

    // MARK: - Networking
    private func send(_ body: [String: Any], to url: URL = OpenAIClient.endpoint) async throws -> [String: Any] {
        let httpBody = try JSONSerialization.data(withJSONObject: body)

        // Mirror AnthropicClient: retry ONCE on a transient overload (429/503) with a short
        // backoff, and log token usage to the field diagnostics so cost stays answerable.
        for attempt in 0..<2 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = httpBody
            req.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw AIConfig.AIError.badResponse("no response")
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if (200..<300).contains(http.statusCode) {
                if let usage = json["usage"] as? [String: Any] {
                    // Chat Completions says prompt/completion_tokens; Responses says
                    // input/output_tokens — read whichever is present.
                    let input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int) ?? 0
                    let output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int) ?? 0
                    let cached = ((usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int)
                        ?? ((usage["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int) ?? 0
                    Diagnostics.shared.log("openai usage: in \(input) out \(output) cached \(cached)", .ai)
                }
                return json
            }

            // OpenAI errors come back as { "error": { "message": ... } }, same shape we
            // surface for Anthropic.
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            Diagnostics.shared.log("openai HTTP \(http.statusCode): \(msg)", .ai)

            if [429, 503].contains(http.statusCode), attempt == 0 {
                try? await Task.sleep(for: .milliseconds(700))
                continue
            }
            throw AIConfig.AIError.badResponse(msg)
        }
        throw AIConfig.AIError.badResponse("request failed after a retry")
    }
}

// MARK: - Tool-capable surface (OpenAI function calling + vision)
//
// The app speaks Anthropic's wire vocabulary internally — `AnthropicClient.Msg` content
// blocks (`text` / `image` / `tool_use` / `tool_result`), `{name, description,
// input_schema}` tool schemas, and `ChatTurn` results. This extension translates that
// vocabulary to OpenAI's Chat Completions format on the way out and back on the way in,
// so CoachView's tool loop (and every `structured` caller) runs on either vendor
// without branching:
//
//   Anthropic                      OpenAI
//   ─────────────────────────────  ─────────────────────────────────────────────
//   tools: {name, input_schema}    tools: {type: "function", function: {parameters}}
//   assistant tool_use block       assistant message tool_calls[] (arguments = JSON string)
//   user tool_result block         {"role": "tool", "tool_call_id": ..., "content": ...}
//   image source base64 block      {"type": "image_url", "image_url": {"url": "data:...;base64,..."}}
//   cachedSystemPrefix             prefix folded into the system message (OpenAI caches
//                                  long stable prefixes automatically — no marker needed)
extension OpenAIClient: ToolCapableClient {

    func chatWithTools(system: String,
                       messages: [AnthropicClient.Msg],
                       tools: [[String: Any]],
                       model: String,
                       maxTokens: Int,
                       cachedSystemPrefix: String?,
                       forbidToolUse: Bool) async throws -> AnthropicClient.ChatTurn {
        var wire: [[String: Any]] = []
        let sys = [cachedSystemPrefix ?? "", system].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !sys.isEmpty { wire.append(["role": "system", "content": sys]) }
        for msg in messages { wire.append(contentsOf: Self.openAIMessages(from: msg)) }

        var body: [String: Any] = ["model": model, "messages": wire]
        body[Self.tokenParam(for: model)] = maxTokens
        if let effort = Self.reasoningEffort(for: model, withTools: !tools.isEmpty) {
            body["reasoning_effort"] = effort
        }
        if !tools.isEmpty { body["tools"] = Self.openAITools(tools) }
        if forbidToolUse { body["tool_choice"] = "none" }   // depth cap — finalize in prose
        // Cache routing: OpenAI load-balances requests across backends, and each backend
        // has its own prompt cache — without a routing key, back-to-back coach turns land
        // on different shards and the ~6k-token stable prefix re-bills at full price every
        // time (we measured cached=0 live). A constant per-feature key makes requests with
        // the same prefix stick to the same shard. BYOK, so no cross-user collision risk.
        body["prompt_cache_key"] = "vita-coach"

        let json = try await send(body)
        return try Self.parseToolTurn(json)
    }

    func structured(system: String,
                    userContent: Any,
                    toolName: String,
                    toolDescription: String,
                    schema: [String: Any],
                    model: String,
                    maxTokens: Int) async throws -> [String: Any] {
        var wire: [[String: Any]] = []
        if !system.isEmpty { wire.append(["role": "system", "content": system]) }
        wire.append(["role": "user", "content": Self.openAIUserContent(userContent)])

        var body: [String: Any] = [
            "model": model,
            "messages": wire,
            "tools": Self.openAITools([["name": toolName,
                                        "description": toolDescription,
                                        "input_schema": schema]]),
            // Forced call — OpenAI's equivalent of Anthropic's tool_choice {type: "tool"}.
            "tool_choice": ["type": "function", "function": ["name": toolName]],
            // Same cache-shard routing as the coach: each structured feature has a stable
            // system+schema prefix that should stick to one backend's prompt cache.
            "prompt_cache_key": "structured-\(toolName)",
        ]
        body[Self.tokenParam(for: model)] = maxTokens
        // structured() always carries a (forced) function tool → tools-aware effort.
        if let effort = Self.reasoningEffort(for: model, withTools: true) {
            body["reasoning_effort"] = effort
        }

        let json = try await send(body)
        guard let input = try Self.parseToolTurn(json).toolUse?.input else {
            throw AIConfig.AIError.decoding("no tool call in response")
        }
        return input
    }

    // MARK: - Translation (pure + unit-tested)

    /// One Anthropic-shaped `Msg` → one or more OpenAI messages. A user turn carrying a
    /// `tool_result` becomes a `role:"tool"` message (OpenAI's required follow-up to a
    /// tool call); text/image blocks fold into a single content-parts message.
    static func openAIMessages(from msg: AnthropicClient.Msg) -> [[String: Any]] {
        if let plain = msg.content as? String {
            return [["role": msg.role, "content": plain]]
        }
        guard let blocks = msg.content as? [[String: Any]] else { return [] }

        if msg.role == "assistant" {
            let text = blocks
                .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
                .joined()
            let toolCalls: [[String: Any]] = blocks.compactMap { block in
                guard (block["type"] as? String) == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String else { return nil }
                let input = (block["input"] as? [String: Any]) ?? [:]
                let args = (try? JSONSerialization.data(withJSONObject: input))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                return ["id": id, "type": "function",
                        "function": ["name": name, "arguments": args]]
            }
            var message: [String: Any] = ["role": "assistant",
                                          "content": text.isEmpty ? NSNull() : text]
            if !toolCalls.isEmpty { message["tool_calls"] = toolCalls }
            return [message]
        }

        // User turn: tool_result blocks each become a role:"tool" message; anything
        // visual/textual folds into one user message with content parts.
        var out: [[String: Any]] = []
        var parts: [[String: Any]] = []
        for block in blocks {
            switch block["type"] as? String {
            case "tool_result":
                // OpenAI has no is_error flag — the result text itself carries the signal.
                out.append(["role": "tool",
                            "tool_call_id": (block["tool_use_id"] as? String) ?? "",
                            "content": (block["content"] as? String) ?? ""])
            case "text":
                if let t = block["text"] as? String { parts.append(["type": "text", "text": t]) }
            case "image":
                if let source = block["source"] as? [String: Any],
                   let data = source["data"] as? String {
                    let media = (source["media_type"] as? String) ?? "image/jpeg"
                    parts.append(["type": "image_url",
                                  "image_url": ["url": "data:\(media);base64,\(data)"]])
                }
            default:
                break
            }
        }
        if !parts.isEmpty { out.append(["role": "user", "content": parts]) }
        return out
    }

    /// `structured`'s user content: a plain string passes through; Anthropic-shaped
    /// text/image blocks become OpenAI content parts (this is the meal-photo path).
    static func openAIUserContent(_ content: Any) -> Any {
        guard let blocks = content as? [[String: Any]] else { return content }
        var parts: [[String: Any]] = []
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String { parts.append(["type": "text", "text": t]) }
            case "image":
                if let source = block["source"] as? [String: Any],
                   let data = source["data"] as? String {
                    let media = (source["media_type"] as? String) ?? "image/jpeg"
                    parts.append(["type": "image_url",
                                  "image_url": ["url": "data:\(media);base64,\(data)"]])
                }
            default:
                break
            }
        }
        return parts
    }

    /// Anthropic tool schemas → OpenAI function declarations.
    static func openAITools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let name = tool["name"] as? String else { return nil }
            var function: [String: Any] = ["name": name]
            if let description = tool["description"] as? String { function["description"] = description }
            if let schema = tool["input_schema"] { function["parameters"] = schema }
            return ["type": "function", "function": function]
        }
    }

    /// OpenAI response → the app's `ChatTurn`. The `assistantContent` echo is rebuilt in
    /// Anthropic block form so CoachView's continue-turn history round-trips through
    /// `openAIMessages` unchanged. Only the FIRST tool call is exposed (the coach
    /// proposes one change per turn), matching the Anthropic path's behavior.
    static func parseToolTurn(_ json: [String: Any]) throws -> AnthropicClient.ChatTurn {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIConfig.AIError.decoding("missing choices[0].message")
        }
        let text = ((message["content"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var toolUse: AnthropicClient.ToolUse?
        if let calls = message["tool_calls"] as? [[String: Any]],
           let call = calls.first,
           let id = call["id"] as? String,
           let function = call["function"] as? [String: Any],
           let name = function["name"] as? String {
            let argsString = function["arguments"] as? String ?? "{}"
            let input = ((try? JSONSerialization.jsonObject(with: Data(argsString.utf8)))
                as? [String: Any]) ?? [:]
            toolUse = AnthropicClient.ToolUse(id: id, name: name, input: input)
        }

        // Same guard as the Anthropic path: a turn truncated mid-call can carry mangled
        // arguments — surface the prose instead of acting on a half-formed request.
        if (first["finish_reason"] as? String) == "length", toolUse != nil {
            toolUse = nil
        }

        var assistantContent: [[String: Any]] = []
        if !text.isEmpty { assistantContent.append(["type": "text", "text": text]) }
        if let toolUse {
            assistantContent.append(["type": "tool_use", "id": toolUse.id,
                                     "name": toolUse.name, "input": toolUse.input])
        }
        return AnthropicClient.ChatTurn(text: text, toolUse: toolUse,
                                        assistantContent: assistantContent)
    }
}
