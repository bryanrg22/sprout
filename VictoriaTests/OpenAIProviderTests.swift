import XCTest
@testable import Victoria

/// Pins the OpenAI side of the cross-provider tool surface: the pure translators that
/// map the app's Anthropic-shaped wire vocabulary (Msg content blocks, tool schemas,
/// ChatTurn echoes) to OpenAI's function-calling format and back. If these hold, the
/// coach's tool loop runs identically on either vendor.
final class OpenAIProviderTests: XCTestCase {

    private func json(_ s: String) -> [String: Any] {
        // swiftlint:disable:next force_try force_cast
        try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
    }

    // MARK: - Tool schema translation

    func testToolSchemaBecomesFunctionDeclaration() throws {
        let anthropic: [[String: Any]] = [[
            "name": "log_water",
            "description": "Log bottles of water.",
            "input_schema": ["type": "object", "properties": ["bottles": ["type": "integer"]]],
        ]]
        let out = OpenAIClient.openAITools(anthropic)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0]["type"] as? String, "function")
        let fn = try XCTUnwrap(out[0]["function"] as? [String: Any])
        XCTAssertEqual(fn["name"] as? String, "log_water")
        XCTAssertEqual(fn["description"] as? String, "Log bottles of water.")
        XCTAssertNotNil(fn["parameters"], "input_schema must carry over as parameters")
    }

    // MARK: - Message translation (out)

    func testPlainStringMessagesPassThrough() {
        let out = OpenAIClient.openAIMessages(from: .init(role: "user", content: "hi"))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0]["role"] as? String, "user")
        XCTAssertEqual(out[0]["content"] as? String, "hi")
    }

    func testAssistantToolUseBecomesToolCallsWithJSONStringArguments() throws {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "Logging that now."],
            ["type": "tool_use", "id": "call_1", "name": "log_water",
             "input": ["bottles": 2]],
        ]
        let out = OpenAIClient.openAIMessages(from: .init(role: "assistant", content: blocks))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0]["content"] as? String, "Logging that now.")
        let calls = try XCTUnwrap(out[0]["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0]["id"] as? String, "call_1")
        let fn = try XCTUnwrap(calls[0]["function"] as? [String: Any])
        XCTAssertEqual(fn["name"] as? String, "log_water")
        // Arguments must be a JSON STRING (OpenAI wire rule), decodable back to the input.
        let args = try XCTUnwrap(fn["arguments"] as? String)
        let decoded = json(args)
        XCTAssertEqual(decoded["bottles"] as? Int, 2)
    }

    func testToolResultBecomesRoleToolMessage() {
        let blocks: [[String: Any]] = [
            ["type": "tool_result", "tool_use_id": "call_1", "content": "Applied. Logged 2 bottles."],
        ]
        let out = OpenAIClient.openAIMessages(from: .init(role: "user", content: blocks))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0]["role"] as? String, "tool")
        XCTAssertEqual(out[0]["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(out[0]["content"] as? String, "Applied. Logged 2 bottles.")
    }

    func testImageBlockBecomesDataURLPart() throws {
        let data = Data([0xFF, 0xD8, 0xFF])   // JPEG magic bytes are plenty for the mapping
        let blocks: [[String: Any]] = [
            AnthropicClient.imageBlock(data),
            AnthropicClient.textBlock("What's in this meal?"),
        ]
        let out = OpenAIClient.openAIMessages(from: .init(role: "user", content: blocks))
        XCTAssertEqual(out.count, 1)
        let parts = try XCTUnwrap(out[0]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        let image = try XCTUnwrap(parts.first { ($0["type"] as? String) == "image_url" })
        let url = try XCTUnwrap((image["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertTrue(url.hasSuffix(data.base64EncodedString()))
        // structured()'s user-content path maps the same way.
        let structured = OpenAIClient.openAIUserContent(blocks) as? [[String: Any]]
        XCTAssertEqual(structured?.count, 2)
    }

    // MARK: - Response parsing (in)

    private let toolCallResponse = """
    {"choices": [{"finish_reason": "tool_calls",
                  "message": {"role": "assistant",
                              "content": "On it!",
                              "tool_calls": [{"id": "call_9", "type": "function",
                                              "function": {"name": "log_water",
                                                           "arguments": "{\\"bottles\\": 3}"}}]}}]}
    """

    func testParsesToolCallTurn() throws {
        let turn = try OpenAIClient.parseToolTurn(json(toolCallResponse))
        XCTAssertEqual(turn.text, "On it!")
        let tool = try XCTUnwrap(turn.toolUse)
        XCTAssertEqual(tool.id, "call_9")
        XCTAssertEqual(tool.name, "log_water")
        XCTAssertEqual(tool.input["bottles"] as? Int, 3)
        // Echo blocks are Anthropic-shaped so continueTurn history round-trips.
        XCTAssertEqual(turn.assistantContent.count, 2)
        XCTAssertEqual(turn.assistantContent[1]["type"] as? String, "tool_use")
    }

    func testTruncatedTurnDropsToolCall() throws {
        let truncated = toolCallResponse.replacingOccurrences(of: "tool_calls\"", with: "length\"")
        let turn = try OpenAIClient.parseToolTurn(json(truncated))
        XCTAssertNil(turn.toolUse, "a length-cut turn must not act on possibly-mangled arguments")
        XCTAssertEqual(turn.text, "On it!")
    }

    func testPlainReplyParsesWithNoTool() throws {
        let plain = """
        {"choices": [{"finish_reason": "stop",
                      "message": {"role": "assistant", "content": "You're doing great 💚"}}]}
        """
        let turn = try OpenAIClient.parseToolTurn(json(plain))
        XCTAssertNil(turn.toolUse)
        XCTAssertEqual(turn.text, "You're doing great 💚")
    }

    /// The full loop the coach runs: response → ChatTurn → echo the assistantContent back
    /// through the translator → OpenAI sees the identical tool call it produced.
    func testAssistantEchoRoundTrips() throws {
        let turn = try OpenAIClient.parseToolTurn(json(toolCallResponse))
        let echoed = OpenAIClient.openAIMessages(
            from: AnthropicClient.assistantMessage(content: turn.assistantContent))
        XCTAssertEqual(echoed.count, 1)
        let calls = try XCTUnwrap(echoed[0]["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls[0]["id"] as? String, "call_9")
        let fn = try XCTUnwrap(calls[0]["function"] as? [String: Any])
        XCTAssertEqual(json(try XCTUnwrap(fn["arguments"] as? String))["bottles"] as? Int, 3)
    }

    // MARK: - Responses API (web-search research)

    func testParsesResponsesOutputWithSearch() {
        let response = json("""
        {"output": [
            {"type": "web_search_call", "id": "ws_1", "status": "completed",
             "action": {"type": "search", "query": "protein needs"}},
            {"type": "message", "role": "assistant", "status": "completed",
             "content": [{"type": "output_text",
                          "text": "Aim for 1.6 g/kg (examine.com).",
                          "annotations": [{"type": "url_citation", "url": "https://examine.com"}]}]}
        ]}
        """)
        let out = OpenAIClient.parseResponsesOutput(response)
        XCTAssertEqual(out.text, "Aim for 1.6 g/kg (examine.com).")
        XCTAssertTrue(out.usedSearch)
    }

    func testResponsesOutputWithoutSearchFallsBackToConvenienceField() {
        let out = OpenAIClient.parseResponsesOutput(json("""
        {"output": [], "output_text": "From general knowledge."}
        """))
        XCTAssertEqual(out.text, "From general knowledge.")
        XCTAssertFalse(out.usedSearch)
    }

    // MARK: - Provider routing

    func testPlanModelFollowsProvider() {
        let original = AIConfig.provider
        defer { AIConfig.provider = original }
        AIConfig.provider = .anthropic
        XCTAssertEqual(AIConfig.planModel, "claude-opus-4-8")
        // The heavy tier is deliberately a step ABOVE the coach tier on OpenAI.
        AIConfig.provider = .openai
        XCTAssertEqual(AIConfig.planModel, "gpt-5.5")
        XCTAssertNotEqual(AIConfig.planModel, AIProvider.openai.defaultCoachModel)
    }

    /// Reasoning effort is pinned LOW on gpt-5-family models (thinking tokens bill as
    /// output and count against our tight max_completion_tokens budgets) and absent on
    /// non-reasoning models (the param would be rejected).
    func testReasoningEffortOnlyForGPT5Family() {
        XCTAssertEqual(OpenAIClient.reasoningEffort(for: "gpt-5.4"), "low")
        XCTAssertEqual(OpenAIClient.reasoningEffort(for: "gpt-5.5"), "low")
        XCTAssertNil(OpenAIClient.reasoningEffort(for: "gpt-4.1"))
        XCTAssertNil(OpenAIClient.reasoningEffort(for: "gpt-4.1-mini"))
    }

    func testReasoningModelsUseMaxCompletionTokens() {
        XCTAssertEqual(OpenAIClient.tokenParam(for: "gpt-4.1"), "max_tokens")
        XCTAssertEqual(OpenAIClient.tokenParam(for: "gpt-4o"), "max_tokens")
        XCTAssertEqual(OpenAIClient.tokenParam(for: "o3-mini"), "max_completion_tokens")
        // The gpt-5 family are reasoning models too — a user-typed override must not 400.
        XCTAssertEqual(OpenAIClient.tokenParam(for: "gpt-5.5"), "max_completion_tokens")
    }

    /// A FAILED web_search_call must not report grounding that never happened.
    func testFailedSearchCallDoesNotCountAsUsedSearch() {
        let out = OpenAIClient.parseResponsesOutput(json("""
        {"output": [
            {"type": "web_search_call", "id": "ws_1", "status": "failed"},
            {"type": "message", "role": "assistant", "status": "completed",
             "content": [{"type": "output_text", "text": "From general knowledge."}]}
        ]}
        """))
        XCTAssertEqual(out.text, "From general knowledge.")
        XCTAssertFalse(out.usedSearch)
    }
}
