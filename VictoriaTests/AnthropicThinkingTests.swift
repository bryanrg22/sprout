import XCTest
@testable import Victoria

/// A short piece of writing is never lost to a model thinking its whole output cap away
/// (EVAL_REPORT 25).
///
/// Measured before this file existed: on one insight case `claude-haiku-5-5` and
/// `claude-sonnet-5-5` spent 80 of 80 output tokens thinking, three times in three, and
/// returned no text; the app showed its template and logged nothing. Each model takes a
/// different "do not think" value and rejects the others with a 400, which was checked
/// against the API one request per model and value. These tests pin that table, that the
/// plain-text path sends it and no other path does, and that a reply lost to its cap is
/// reported by name with the thinking count the response gave.
final class AnthropicThinkingTests: XCTestCase {

    private func runtime(_ transport: ScriptedTransport, model: String? = nil,
                         usage: UsageRecorder? = nil) -> AIRuntime {
        AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", model: model, transport: transport,
                  onUsage: usage.map { recorder in { @Sendable reported in recorder.record(reported) } })
    }

    private func text(_ words: String = "Nice work today.", model: String = "claude-haiku-5-5",
                      thinking: Int? = 0) -> [String: Any] {
        var usage: [String: Any] = ["input_tokens": 400, "output_tokens": 31]
        if let thinking { usage["output_tokens_details"] = ["thinking_tokens": thinking] }
        return ["model": model, "content": [["type": "text", "text": words]],
                "stop_reason": "end_turn", "usage": usage]
    }

    /// What the API returned for the measured failure: a thinking block with an empty
    /// `thinking` field, no text, `max_tokens`, and every output token counted as thinking.
    private func lostToThinking(model: String, cap: Int) -> [String: Any] {
        ["model": model,
         "content": [["type": "thinking", "thinking": "", "signature": "sig"]],
         "stop_reason": "max_tokens",
         "usage": ["input_tokens": 416, "output_tokens": cap,
                   "output_tokens_details": ["thinking_tokens": cap]]]
    }

    // MARK: - The table

    func testEachModelGetsTheValueItAccepts() {
        func off(_ model: String) -> String? { AnthropicModelProfile.thinkingOff(for: model)?["type"] as? String }
        XCTAssertEqual(off("claude-sonnet-5-5"), "between_tools")
        XCTAssertEqual(off("claude-haiku-5-5"), "disabled")
        XCTAssertEqual(off("claude-sonnet-5"), "disabled")
        XCTAssertNil(off("claude-haiku-4-5-20251001"), "does not think unless asked: nothing is sent")
        XCTAssertNil(off("claude-haiku-4-5"))
        // Dated snapshots of the same models.
        XCTAssertEqual(off("claude-sonnet-5-5-20261001"), "between_tools")
        XCTAssertEqual(off("claude-haiku-5-5-20261001"), "disabled")
        XCTAssertEqual(off("claude-sonnet-5-20260601"), "disabled")
        // Not in the table: left at the model's own default, never guessed.
        for unknown in ["claude-opus-5-5", "claude-fable-5-2", "claude-sonnet-5-6", "claude-sonnet-6",
                        "claude-haiku-5-5-preview", "claude-sonnet-5-5-latest", "gpt-6-luna", ""] {
            XCTAssertNil(off(unknown), unknown)
        }
        XCTAssertEqual(AnthropicModelProfile.thinkingOff(for: "claude-haiku-5-5")?.count, 1, "one key, no budget")
    }

    func testAModelIsNotMistakenForTheOneItsNameStartsWith() {
        XCTAssertTrue(AnthropicModelProfile.isModel("claude-sonnet-5", "claude-sonnet-5"))
        XCTAssertTrue(AnthropicModelProfile.isModel("claude-sonnet-5-20260601", "claude-sonnet-5"))
        XCTAssertFalse(AnthropicModelProfile.isModel("claude-sonnet-5-5", "claude-sonnet-5"))
        XCTAssertFalse(AnthropicModelProfile.isModel("claude-sonnet-5-5-20261001", "claude-sonnet-5"))
        XCTAssertFalse(AnthropicModelProfile.isModel("claude-sonnet-5-2026060", "claude-sonnet-5"), "seven digits")
        XCTAssertFalse(AnthropicModelProfile.isModel("claude-sonnet-5-2026060a", "claude-sonnet-5"))
        XCTAssertFalse(AnthropicModelProfile.isModel("claude-sonnet-50", "claude-sonnet-5"))
    }

    // MARK: - What is sent

    func testThePlainTextPathSendsTheValueForTheModelInForce() async throws {
        let expected: [(model: String, type: String?)] = [
            ("claude-haiku-5-5", "disabled"), ("claude-sonnet-5-5", "between_tools"),
            ("claude-sonnet-5", "disabled"), ("claude-haiku-4-5-20251001", nil), ("claude-opus-5-5", nil),
        ]
        for row in expected {
            let transport = ScriptedTransport([.json(200, text(model: row.model))])
            let reply = try await AIRuntime.$current.withValue(runtime(transport)) {
                try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                                 model: row.model, maxTokens: 80)
            }
            XCTAssertEqual(reply, "Nice work today.")
            let body = transport.body()
            XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, row.type, row.model)
            XCTAssertEqual(body["thinking"] == nil, row.type == nil, row.model)
            XCTAssertEqual(body["max_tokens"] as? Int, 80, "the cap is the caller's, unchanged")
            XCTAssertNil(body["output_config"], "no effort is sent: haiku-4-5 has none")
        }
    }

    func testAScopedModelDecidesTheValueNotTheCallSiteModel() async throws {
        // An evaluation pins the model for a call site written for another one.
        let transport = ScriptedTransport([.json(200, text(model: "claude-sonnet-5-5"))])
        _ = try await AIRuntime.$current.withValue(runtime(transport, model: "claude-sonnet-5-5")) {
            try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                             model: "claude-haiku-4-5-20251001", maxTokens: 80)
        }
        XCTAssertEqual(transport.body()["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual((transport.body()["thinking"] as? [String: Any])?["type"] as? String, "between_tools")
    }

    func testAScopedDefaultLeavesTheModelToDecide() async throws {
        // What an evaluation uses to measure the two side by side.
        let transport = ScriptedTransport([.json(200, text())])
        let scoped = AIRuntime(provider: .anthropic, apiKey: "test-key-not-real",
                               reasoningEffort: AnthropicModelProfile.keepModelDefault, transport: transport)
        _ = try await AIRuntime.$current.withValue(scoped) {
            try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                             model: "claude-haiku-5-5", maxTokens: 80)
        }
        XCTAssertNil(transport.body()["thinking"])
        XCTAssertNil(transport.body()["output_config"], "the scoped value is not sent as an effort")
    }

    func testTheStructuredAndToolPathsAreLeftAsTheyWere() async throws {
        // Only the short-writing path was measured; these two keep the model's default.
        let toolReply: [String: Any] = [
            "model": "claude-haiku-5-5",
            "content": [["type": "tool_use", "id": "t1", "name": "emit", "input": ["line": "x"]]],
            "stop_reason": "tool_use", "usage": ["input_tokens": 10, "output_tokens": 5],
        ]
        let schema: [String: Any] = ["type": "object", "properties": ["line": ["type": "string"]]]
        let structured = ScriptedTransport([.json(200, toolReply)])
        _ = try await AIRuntime.$current.withValue(runtime(structured)) {
            try await AnthropicClient().structured(system: "s", userContent: "u", toolName: "emit",
                                                   toolDescription: "d", schema: schema,
                                                   model: "claude-haiku-5-5", maxTokens: 300)
        }
        XCTAssertNil(structured.body()["thinking"])

        let tools = ScriptedTransport([.json(200, text())])
        _ = try await AIRuntime.$current.withValue(runtime(tools)) {
            try await AnthropicClient().chatWithTools(
                system: "s", messages: [AnthropicClient.Msg(role: "user", content: "u")],
                tools: [["name": "emit", "description": "d", "input_schema": schema]],
                model: "claude-haiku-5-5", maxTokens: 300)
        }
        XCTAssertNil(tools.body()["thinking"])
    }

    // MARK: - A reply lost to its cap is named

    func testNoTextAtTheCapIsReportedWithItsThinkingCount() async {
        let transport = ScriptedTransport([.json(200, lostToThinking(model: "claude-opus-5-5", cap: 80))])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(transport)) {
                try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                                 model: "claude-opus-5-5", maxTokens: 80)
            }
            XCTFail("a reply with no text must throw")
        } catch AIConfig.AIError.cutOffBeforeOutput(let model, let cap, let thinking) {
            XCTAssertEqual(model, "claude-opus-5-5")
            XCTAssertEqual(cap, 80)
            XCTAssertEqual(thinking, 80)
        } catch {
            XCTFail("expected cutOffBeforeOutput, got \(error)")
        }
        XCTAssertEqual(transport.requests.count, 1, "not retried: the same request would end the same way")
    }

    func testTheSameWithoutAThinkingCountSaysSoRatherThanZero() async {
        var reply = lostToThinking(model: "claude-opus-5-5", cap: 80)
        reply["usage"] = ["input_tokens": 416, "output_tokens": 80]
        let transport = ScriptedTransport([.json(200, reply)])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(transport)) {
                try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                                 model: "claude-opus-5-5", maxTokens: 80)
            }
            XCTFail("must throw")
        } catch AIConfig.AIError.cutOffBeforeOutput(_, _, let thinking) {
            XCTAssertNil(thinking)
        } catch {
            XCTFail("expected cutOffBeforeOutput, got \(error)")
        }
    }

    func testAnEmptyReplyThatWasNotCutOffIsStillADecodingError() async {
        var reply = text("")
        reply["stop_reason"] = "end_turn"
        let transport = ScriptedTransport([.json(200, reply)])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(transport)) {
                try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                                 model: "claude-haiku-5-5", maxTokens: 80)
            }
            XCTFail("must throw")
        } catch AIConfig.AIError.decoding(let what) {
            XCTAssertEqual(what, "empty text")
        } catch {
            XCTFail("expected decoding, got \(error)")
        }
    }

    func testAStructuredCallCutOffBeforeItsToolCallIsNamedToo() async {
        let transport = ScriptedTransport([.json(200, lostToThinking(model: "claude-sonnet-5", cap: 300))])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(transport)) {
                try await AnthropicClient().structured(
                    system: "s", userContent: "u", toolName: "emit", toolDescription: "d",
                    schema: ["type": "object", "properties": ["line": ["type": "string"]]],
                    model: "claude-sonnet-5", maxTokens: 300)
            }
            XCTFail("must throw")
        } catch AIConfig.AIError.cutOffBeforeOutput(let model, let cap, let thinking) {
            XCTAssertEqual(model, "claude-sonnet-5")
            XCTAssertEqual(cap, 300)
            XCTAssertEqual(thinking, 300)
        } catch {
            XCTFail("expected cutOffBeforeOutput, got \(error)")
        }
    }

    func testTextThatReachedTheCapIsStillReturned() async throws {
        // Truncated writing is the caller's to judge (each has a sanitiser); only nothing at all throws.
        var reply = text("Nine days in a row and")
        reply["stop_reason"] = "max_tokens"
        let transport = ScriptedTransport([.json(200, reply)])
        let got = try await AIRuntime.$current.withValue(runtime(transport)) {
            try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                             model: "claude-haiku-5-5", maxTokens: 80)
        }
        XCTAssertEqual(got, "Nine days in a row and")
    }

    func testTheMessageSaysWhatHappened() {
        XCTAssertEqual(AIConfig.AIError.cutOffBeforeOutput(model: "m", cap: 80, thinkingTokens: 80).errorDescription,
                       "The AI ran out of room before answering (m stopped at 80 tokens, 80 of them spent thinking).")
        XCTAssertEqual(AIConfig.AIError.cutOffBeforeOutput(model: "m", cap: 80, thinkingTokens: nil).errorDescription,
                       "The AI ran out of room before answering (m stopped at 80 tokens).")
    }

    // MARK: - Usage

    func testUsageCarriesThinkingTokensAndTheStopReason() async throws {
        let recorder = UsageRecorder()
        let transport = ScriptedTransport([.json(200, text(thinking: 12)), .json(200, text(thinking: nil))])
        try await AIRuntime.$current.withValue(runtime(transport, usage: recorder)) {
            for _ in 0..<2 {
                _ = try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                                     model: "claude-haiku-5-5", maxTokens: 80)
            }
        }
        XCTAssertEqual(recorder.all.map(\.thinkingTokens), [12, nil], "not reported is nil, never zero")
        XCTAssertEqual(recorder.all.map(\.stopReason), ["end_turn", "end_turn"])
        XCTAssertEqual(recorder.all.map(\.outputTokens), [31, 31], "thinking is part of output, not added to it")
    }

    func testAReplyLostToItsCapStillReportsItsUsage() async {
        let recorder = UsageRecorder()
        let transport = ScriptedTransport([.json(200, lostToThinking(model: "claude-opus-5-5", cap: 80))])
        _ = try? await AIRuntime.$current.withValue(runtime(transport, usage: recorder)) {
            try await AnthropicClient().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "u")],
                                             model: "claude-opus-5-5", maxTokens: 80)
        }
        XCTAssertEqual(recorder.all.count, 1, "the tokens were billed whether or not anything was written")
        XCTAssertEqual(recorder.all.first?.thinkingTokens, 80)
        XCTAssertEqual(recorder.all.first?.stopReason, "max_tokens")
    }
}
