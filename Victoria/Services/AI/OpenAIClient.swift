import Foundation

/// What the client must know about an OpenAI model to build a request it will accept.
///
/// One place, decided from the model's family and version, instead of prefix checks
/// scattered through the request builders: a model released after this table was
/// written still resolves by its version number.
struct OpenAIModelProfile: Equatable {
    /// Thinks before answering: takes `max_completion_tokens`, and its hidden reasoning
    /// tokens are billed as output and count against the output cap.
    var isReasoning: Bool
    /// Runs on `/v1/responses`. From gpt-5.6 on, function tools with a reasoning effort
    /// and explicit prompt-cache breakpoints exist only there, and several 6.x models
    /// do not accept function calling on Chat Completions at all.
    var usesResponsesAPI: Bool
    /// Accepts `effort: "none"`. The Sol and Astra models of the 6.x line reject it.
    var acceptsEffortNone: Bool

    static let chatCompletionsPlain = OpenAIModelProfile(isReasoning: false, usesResponsesAPI: false,
                                                         acceptsEffortNone: false)

    static func resolve(_ model: String) -> OpenAIModelProfile {
        let m = model.lowercased()
        if ["o1", "o3", "o4", "o5"].contains(where: { m.hasPrefix($0) }) {
            return OpenAIModelProfile(isReasoning: true, usesResponsesAPI: false, acceptsEffortNone: false)
        }
        guard let version = gptVersion(m) else { return .chatCompletionsPlain }
        if version.major < 5 { return .chatCompletionsPlain }
        let fromFivePointSix = version.major > 5 || version.minor >= 6
        guard fromFivePointSix else {
            return OpenAIModelProfile(isReasoning: true, usesResponsesAPI: false, acceptsEffortNone: false)
        }
        let rejectsNone = version.major >= 6 && (m.contains("sol") || m.contains("astra"))
        return OpenAIModelProfile(isReasoning: true, usesResponsesAPI: true, acceptsEffortNone: !rejectsNone)
    }

    /// `gpt-5.6-terra` → (5, 6); `gpt-6-luna` → (6, 0); `gpt-4o-mini` → (4, 0); not a gpt model → nil.
    static func gptVersion(_ lowercased: String) -> (major: Int, minor: Int)? {
        guard lowercased.hasPrefix("gpt-") else { return nil }
        let rest = lowercased.dropFirst(4)
        let majorDigits = rest.prefix { $0.isNumber }
        guard let major = Int(majorDigits) else { return nil }
        var minor = 0
        let afterMajor = rest.dropFirst(majorDigits.count)
        if afterMajor.first == "." {
            minor = Int(afterMajor.dropFirst().prefix { $0.isNumber }) ?? 0
        }
        return (major, minor)
    }
}

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
        // A scoped override (tests / evals) supplies its own key; the app reads the Keychain.
        let k = AIRuntime.current?.apiKey ?? KeychainStore.apiKey(for: .openai)
        guard let k, !k.isEmpty else { throw AIConfig.AIError.missingKey }
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
        let model = AIRuntime.resolve(model: model)
        if Self.usesResponsesAPI(model) {
            let history = messages.map { AnthropicClient.Msg(role: $0.role, content: $0.text) }
            var body = Self.responsesBody(model: model, maxTokens: maxTokens, cacheKey: "plain-chat",
                                          input: Self.responsesInputItems(system: system, cachedPrefix: nil,
                                                                          messages: history))
            body["reasoning"] = ["effort": Self.plainChatEffort(for: model)]
            let json = try await send(body, to: Self.responsesEndpoint)
            let text = Self.parseResponsesOutput(json).text
            guard !text.isEmpty else {
                // A reply cut off by the output cap arrives as status "incomplete" with no text.
                let status = (json["status"] as? String) ?? "unknown"
                throw AIConfig.AIError.decoding("empty text (response status: \(status))")
            }
            return text
        }
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
        OpenAIModelProfile.resolve(model).isReasoning ? "max_completion_tokens" : "max_tokens"
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
        let profile = OpenAIModelProfile.resolve(model)
        // Only the gpt reasoning families take the parameter here; the o-series is left alone.
        guard profile.isReasoning, model.lowercased().hasPrefix("gpt-") else { return nil }
        // A scoped override (evals measuring effort levels) wins over the built-in choice.
        if let forced = AIRuntime.current?.reasoningEffort { return forced }
        if withTools && profile.usesResponsesAPI { return "none" }
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
        let model = AIRuntime.resolve(model: model)
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
        let transport = AIRuntime.transport
        let started = Date()
        for attempt in 0..<2 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = httpBody
            req.timeoutInterval = 60

            let (data, response) = try await transport.data(for: req)
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
                    // OpenAI's input count INCLUDES the cached part; it has no separate
                    // cache-write charge.
                    AIRuntime.report(AIUsage(
                        provider: .openai,
                        model: (json["model"] as? String) ?? (body["model"] as? String) ?? "",
                        endpoint: url.path,
                        uncachedInputTokens: max(0, input - cached), cacheReadTokens: cached,
                        cacheWriteTokens: 0, outputTokens: output,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                        attempts: attempt + 1))
                }
                return json
            }

            // OpenAI errors come back as { "error": { "message": ... } }, same shape we
            // surface for Anthropic.
            let failure = AIHTTPFailure(provider: .openai, response: http, json: json)
            let msg = failure.message
            Diagnostics.shared.log("openai HTTP \(http.statusCode): \(msg)", .ai)

            // Same rule as AnthropicClient: sit out a short `retry-after`, hand a long one
            // (and a quota or billing 429, which waiting cannot fix) to the caller.
            if attempt == 0,
               let delay = failure.automaticRetryDelay(retryableStatuses: [429, 503]) {
                try? await Task.sleep(for: .milliseconds(Int((delay * 1000).rounded())))
                continue
            }
            AIFailureRecorder.report(failure)
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
//   cachedSystemPrefix             gpt-5.6 → an input_text block carrying an EXPLICIT
//                                  prompt_cache_breakpoint on the Responses API;
//                                  older models → folded into the system message
//                                  (implicit caching, best-effort)
extension OpenAIClient: ToolCapableClient {

    /// Which API surface a model runs on. The gpt-5.6 family goes to `/v1/responses`:
    /// (1) explicit prompt-cache breakpoints exist ONLY there — Chat Completions
    /// implicit caching measured `cached 0` in our live logs even with a routing key;
    /// (2) reasoning effort and function tools coexist there (Chat Completions 400s
    /// on that combo for 5.6 — caught live). Older models stay on Chat Completions,
    /// which is well-proven for them.
    static func usesResponsesAPI(_ model: String) -> Bool {
        OpenAIModelProfile.resolve(model).usesResponsesAPI
    }

    /// Effort for a plain-text turn on the Responses API. These are the rewording tasks
    /// with output caps of 80–420 tokens, and reasoning tokens count against the cap, so
    /// the default is no reasoning wherever the model allows that.
    static func plainChatEffort(for model: String) -> String {
        if let forced = AIRuntime.current?.reasoningEffort { return forced }
        return OpenAIModelProfile.resolve(model).acceptsEffortNone ? "none" : "low"
    }

    func chatWithTools(system: String,
                       messages: [AnthropicClient.Msg],
                       tools: [[String: Any]],
                       model: String,
                       maxTokens: Int,
                       cachedSystemPrefix: String?,
                       forbidToolUse: Bool) async throws -> AnthropicClient.ChatTurn {
        let model = AIRuntime.resolve(model: model)
        if Self.usesResponsesAPI(model) {
            var body = Self.responsesBody(model: model, maxTokens: maxTokens,
                                          cacheKey: "vita-coach",
                                          input: Self.responsesInputItems(system: system,
                                                                          cachedPrefix: cachedSystemPrefix,
                                                                          messages: messages))
            if !tools.isEmpty { body["tools"] = Self.responsesTools(tools, strict: false) }
            if forbidToolUse { body["tool_choice"] = "none" }   // depth cap — finalize in prose
            let json = try await send(body, to: Self.responsesEndpoint)
            return try Self.parseResponsesToolTurn(json)
        }

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
        let model = AIRuntime.resolve(model: model)
        if Self.usesResponsesAPI(model) {
            // System + schema are byte-stable per feature → breakpoint the system so
            // repeat calls (meal photos, checklist mornings) read it from cache.
            let userMsg = AnthropicClient.Msg(role: "user", content: userContent)
            var body = Self.responsesBody(model: model, maxTokens: maxTokens,
                                          cacheKey: "structured-\(toolName)",
                                          input: Self.responsesInputItems(system: "",
                                                                          cachedPrefix: system,
                                                                          messages: [userMsg]))
            body["tools"] = Self.responsesTools([["name": toolName,
                                                  "description": toolDescription,
                                                  "input_schema": schema]])
            body["tool_choice"] = ["type": "function", "name": toolName]   // forced call
            let json = try await send(body, to: Self.responsesEndpoint)
            guard let input = try Self.parseResponsesToolTurn(json).toolUse?.input else {
                throw AIConfig.AIError.decoding("no tool call in response")
            }
            return input
        }

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
        var text = ((message["content"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A refusal arrives in its own field with `content` null. It is what the model
        // said, so it is the turn's text.
        let refusal = ((message["refusal"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, !refusal.isEmpty { text = refusal }
        let finishReason = first["finish_reason"] as? String
        let finish: AnthropicClient.ChatTurn.Finish =
            finishReason == "length" ? .cutOff
            : (finishReason == "content_filter" || !refusal.isEmpty) ? .refusal
            : .complete

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
                                        assistantContent: assistantContent, finish: finish)
    }

    // MARK: - Responses API translation (gpt-5.6 path; pure + unit-tested)
    //
    //   Anthropic (internal)         Responses API wire
    //   ───────────────────────────  ─────────────────────────────────────────────
    //   stable system prefix         input_text block + prompt_cache_breakpoint
    //   user/assistant text          message items (input_text / output_text)
    //   image source base64 block    {"type": "input_image", "image_url": "data:…"}
    //   assistant tool_use block     {"type": "function_call", call_id, name, arguments}
    //   user tool_result block       {"type": "function_call_output", call_id, output}
    //   tools {name, input_schema}   {"type": "function", name, parameters} (flat)

    /// Shared request scaffold for the Responses path: explicit cache mode (only OUR
    /// breakpoints define the reusable prefix), a 30-minute cache TTL, the shard-routing
    /// key, and LOW reasoning effort — on Responses, effort and tools legally coexist
    /// (unlike 5.6 on Chat Completions), and low keeps thinking from eating the tight
    /// output budgets while still helping tool-argument correctness.
    static func responsesBody(model: String, maxTokens: Int, cacheKey: String,
                              input: [[String: Any]]) -> [String: Any] {
        [
            "model": model,
            "input": input,
            "max_output_tokens": maxTokens,
            "prompt_cache_key": cacheKey,
            "prompt_cache_options": ["mode": "explicit", "ttl": "30m"],
            "reasoning": ["effort": AIRuntime.current?.reasoningEffort ?? "low"],
        ]
    }

    /// Build the `input` items array: a system message whose STABLE prefix block
    /// carries the explicit cache breakpoint (everything through that block becomes
    /// the cached prefix — tool schemas and the persona bill once per 30 minutes,
    /// not once per message), followed by the translated history.
    static func responsesInputItems(system: String,
                                    cachedPrefix: String?,
                                    messages: [AnthropicClient.Msg]) -> [[String: Any]] {
        var input: [[String: Any]] = []
        var sysBlocks: [[String: Any]] = []
        if let prefix = cachedPrefix, !prefix.isEmpty {
            sysBlocks.append(["type": "input_text", "text": prefix,
                              "prompt_cache_breakpoint": ["mode": "explicit"]])
        }
        if !system.isEmpty { sysBlocks.append(["type": "input_text", "text": system]) }
        if !sysBlocks.isEmpty {
            input.append(["type": "message", "role": "system", "content": sysBlocks])
        }
        for msg in messages { input.append(contentsOf: responsesItems(from: msg)) }
        return input
    }

    /// One Anthropic-shaped `Msg` → one or more Responses input items. Tool calls and
    /// results are TOP-LEVEL items (not message content) in this API.
    static func responsesItems(from msg: AnthropicClient.Msg) -> [[String: Any]] {
        let textType = msg.role == "assistant" ? "output_text" : "input_text"
        if let plain = msg.content as? String {
            return [["type": "message", "role": msg.role,
                     "content": [["type": textType, "text": plain]]]]
        }
        guard let blocks = msg.content as? [[String: Any]] else { return [] }

        var out: [[String: Any]] = []
        var parts: [[String: Any]] = []
        var calls: [[String: Any]] = []
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String { parts.append(["type": textType, "text": t]) }
            case "image":
                if let source = block["source"] as? [String: Any],
                   let data = source["data"] as? String {
                    let media = (source["media_type"] as? String) ?? "image/jpeg"
                    parts.append(["type": "input_image",
                                  "image_url": "data:\(media);base64,\(data)"])
                }
            case "tool_use":
                if let id = block["id"] as? String, let name = block["name"] as? String {
                    let args = (try? JSONSerialization.data(
                        withJSONObject: (block["input"] as? [String: Any]) ?? [:]))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    calls.append(["type": "function_call", "call_id": id,
                                  "name": name, "arguments": args])
                }
            case "tool_result":
                out.append(["type": "function_call_output",
                            "call_id": (block["tool_use_id"] as? String) ?? "",
                            "output": (block["content"] as? String) ?? ""])
            default:
                break
            }
        }
        if !parts.isEmpty {
            // Message before function_call items: prose narrates, then the call follows.
            out.insert(["type": "message", "role": msg.role, "content": parts], at: 0)
        }
        out.append(contentsOf: calls)
        return out
    }

    /// Anthropic tool schemas → Responses function tools (FLAT — no nested
    /// "function" object like Chat Completions).
    /// `strict`: nil leaves the API's default, which on Responses is to normalize the schema
    /// into strict mode, where EVERY property becomes required. That suits a forced call
    /// whose fields are all required anyway (`structured`). For the coach's tools it is
    /// wrong: their optional arguments then arrive filled with placeholders (a container
    /// count of 1 beside "20 oz", an empty date, zeroed macros on an edit), and the app
    /// acts on the placeholder. `false` keeps optional arguments optional (EVAL_REPORT 10).
    static func responsesTools(_ tools: [[String: Any]], strict: Bool? = nil) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let name = tool["name"] as? String else { return nil }
            var out: [String: Any] = ["type": "function", "name": name]
            if let description = tool["description"] as? String { out["description"] = description }
            if let schema = tool["input_schema"] { out["parameters"] = schema }
            if let strict { out["strict"] = strict }
            return out
        }
    }

    /// Responses output → the app's `ChatTurn`, same contract as `parseToolTurn`:
    /// first function_call only, Anthropic-shaped echo, truncation guard (an
    /// "incomplete" response may carry mangled arguments — surface prose instead).
    static func parseResponsesToolTurn(_ json: [String: Any]) throws -> AnthropicClient.ChatTurn {
        guard let output = json["output"] as? [[String: Any]] else {
            throw AIConfig.AIError.decoding("missing output")
        }
        let parts = output
            .filter { ($0["type"] as? String) == "message" }
            .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
        var text = parts
            .compactMap { ($0["type"] as? String) == "output_text" ? $0["text"] as? String : nil }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A refusal is a content part of its own type; it is what the model said.
        let refusal = parts
            .compactMap { ($0["type"] as? String) == "refusal" ? $0["refusal"] as? String : nil }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, !refusal.isEmpty { text = refusal }
        let incompleteReason = (json["status"] as? String) == "incomplete"
            ? ((json["incomplete_details"] as? [String: Any])?["reason"] as? String) : nil
        let finish: AnthropicClient.ChatTurn.Finish =
            incompleteReason == "max_output_tokens" ? .cutOff
            : (incompleteReason == "content_filter" || !refusal.isEmpty) ? .refusal
            : .complete

        var toolUse: AnthropicClient.ToolUse?
        if let call = output.first(where: { ($0["type"] as? String) == "function_call" }),
           let name = call["name"] as? String {
            let id = (call["call_id"] as? String) ?? (call["id"] as? String) ?? ""
            let argsString = call["arguments"] as? String ?? "{}"
            let input = ((try? JSONSerialization.jsonObject(with: Data(argsString.utf8)))
                as? [String: Any]) ?? [:]
            toolUse = AnthropicClient.ToolUse(id: id, name: name, input: input)
        }

        if (json["status"] as? String) == "incomplete",
           ((json["incomplete_details"] as? [String: Any])?["reason"] as? String) == "max_output_tokens",
           toolUse != nil {
            toolUse = nil
        }

        var assistantContent: [[String: Any]] = []
        if !text.isEmpty { assistantContent.append(["type": "text", "text": text]) }
        if let toolUse {
            assistantContent.append(["type": "tool_use", "id": toolUse.id,
                                     "name": toolUse.name, "input": toolUse.input])
        }
        return AnthropicClient.ChatTurn(text: text, toolUse: toolUse,
                                        assistantContent: assistantContent, finish: finish)
    }
}
