import XCTest
@testable import Sprout

/// How the client treats each OpenAI model family: which endpoint, which token
/// parameter, which reasoning effort. Decided from the model's version so a model
/// newer than this file still gets a request the API accepts.
final class OpenAIModelProfileTests: XCTestCase {

    func testVersionParsing() {
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-5.6-terra")?.major, 5)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-5.6-terra")?.minor, 6)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-6-luna")?.major, 6)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-6-luna")?.minor, 0)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-6.2-astra")?.minor, 2)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-4o-mini")?.major, 4)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-4.1-mini")?.minor, 1)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-10.12-sol")?.major, 10)
        XCTAssertEqual(OpenAIModelProfile.gptVersion("gpt-10.12-sol")?.minor, 12)
        XCTAssertNil(OpenAIModelProfile.gptVersion("o3"))
        XCTAssertNil(OpenAIModelProfile.gptVersion("gpt-"))
        XCTAssertNil(OpenAIModelProfile.gptVersion("claude-sonnet-5"))
    }

    func testFamiliesResolveToTheRightSurface() {
        let table: [(String, reasoning: Bool, responses: Bool, none: Bool)] = [
            ("gpt-4.1-mini", false, false, false),
            ("gpt-4o", false, false, false),
            ("gpt-4o-mini-2024-07-18", false, false, false),
            ("o3", true, false, false),
            ("o4-mini", true, false, false),
            ("gpt-5", true, false, false),
            ("gpt-5.4", true, false, false),
            ("gpt-5.4-mini", true, false, false),
            ("gpt-5.5", true, false, false),
            ("gpt-5.6-luna", true, true, true),
            ("gpt-5.6-terra", true, true, true),
            ("gpt-5.6-sol", true, true, true),
            ("gpt-6-luna", true, true, true),
            ("gpt-6.1-terra", true, true, true),
            ("gpt-6-sol", true, true, false),
            ("gpt-6.1-sol", true, true, false),
            ("gpt-6.2-sol", true, true, false),
            ("gpt-6-astra", true, true, false),
            ("gpt-6.2-astra", true, true, false),
            ("GPT-6.2-SOL", true, true, false),
            ("gpt-7-luna", true, true, true),          // a model newer than this table
            ("my-fine-tune", false, false, false),      // unknown: the conservative surface
        ]
        for row in table {
            let p = OpenAIModelProfile.resolve(row.0)
            XCTAssertEqual(p.isReasoning, row.reasoning, "\(row.0) reasoning")
            XCTAssertEqual(p.usesResponsesAPI, row.responses, "\(row.0) responses")
            XCTAssertEqual(p.acceptsEffortNone, row.none, "\(row.0) effort none")
        }
    }

    func testTokenParameterFollowsTheProfile() {
        XCTAssertEqual(OpenAIClient.tokenParam(for: "gpt-4.1-mini"), "max_tokens")
        XCTAssertEqual(OpenAIClient.tokenParam(for: "gpt-4o"), "max_tokens")
        XCTAssertEqual(OpenAIClient.tokenParam(for: "o3"), "max_completion_tokens")
        XCTAssertEqual(OpenAIClient.tokenParam(for: "gpt-5.5"), "max_completion_tokens")
        XCTAssertEqual(OpenAIClient.tokenParam(for: "gpt-6-luna"), "max_completion_tokens")
    }

    func testChatCompletionsEffort() {
        XCTAssertNil(OpenAIClient.reasoningEffort(for: "gpt-4.1-mini"))
        XCTAssertNil(OpenAIClient.reasoningEffort(for: "o3"), "the o-series is sent no effort, as before")
        XCTAssertEqual(OpenAIClient.reasoningEffort(for: "gpt-5.4"), "low")
        XCTAssertEqual(OpenAIClient.reasoningEffort(for: "gpt-5.4", withTools: true), "low")
        XCTAssertEqual(OpenAIClient.reasoningEffort(for: "gpt-5.6-terra", withTools: true), "none")
        XCTAssertEqual(OpenAIClient.reasoningEffort(for: "gpt-6-luna", withTools: true), "none")
    }

    func testPlainChatEffortIsNoneWhereAllowed() {
        XCTAssertEqual(OpenAIClient.plainChatEffort(for: "gpt-6-luna"), "none")
        XCTAssertEqual(OpenAIClient.plainChatEffort(for: "gpt-5.6-luna"), "none")
        XCTAssertEqual(OpenAIClient.plainChatEffort(for: "gpt-6.2-sol"), "low", "Sol 6.x rejects none")
        AIRuntime.$current.withValue(AIRuntime(reasoningEffort: "medium")) {
            XCTAssertEqual(OpenAIClient.plainChatEffort(for: "gpt-6-luna"), "medium")
        }
    }

    // MARK: - Plain chat goes to the surface the model needs

    private func runtime(_ transport: ScriptedTransport) -> AIRuntime {
        AIRuntime(provider: .openai, apiKey: "test-key-not-real", transport: transport)
    }

    func testPlainChatOnAResponsesModelUsesTheResponsesAPI() async throws {
        let transport = ScriptedTransport([.json(200, [
            "status": "completed",
            "output": [["type": "message", "role": "assistant",
                        "content": [["type": "output_text", "text": "Fourteen days. Keep going."]]]],
            "usage": ["input_tokens": 90, "output_tokens": 8],
        ])])
        let text = try await AIRuntime.$current.withValue(runtime(transport)) {
            try await AIClient.make().chat(system: "be warm", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "gpt-6-luna", maxTokens: 80)
        }
        XCTAssertEqual(text, "Fourteen days. Keep going.")
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/responses")
        let body = transport.body()
        XCTAssertEqual(body["max_output_tokens"] as? Int, 80)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "none")
        XCTAssertNil(body["max_tokens"]); XCTAssertNil(body["messages"])
    }

    func testPlainChatOnAnOlderModelStaysOnChatCompletions() async throws {
        let transport = ScriptedTransport([.json(200, [
            "choices": [["message": ["role": "assistant", "content": "ok"]]],
        ])])
        _ = try await AIRuntime.$current.withValue(runtime(transport)) {
            try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "gpt-4.1-mini", maxTokens: 80)
        }
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/chat/completions")
        XCTAssertEqual(transport.body()["max_tokens"] as? Int, 80)
        XCTAssertNil(transport.body()["reasoning_effort"])
    }

    func testAResponseCutOffByTheCapIsAnErrorThatSaysSo() async {
        let transport = ScriptedTransport([.json(200, [
            "status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"], "output": [],
        ])])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(transport)) {
                try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                               model: "gpt-6.2-sol", maxTokens: 80)
            }
            XCTFail("expected an error")
        } catch AIConfig.AIError.decoding(let message) {
            XCTAssertTrue(message.contains("incomplete"), message)
        } catch {
            XCTFail("expected decoding, got \(error)")
        }
    }

    func testToolTurnOnA6xModelGoesToResponses() async throws {
        let transport = ScriptedTransport([.json(200, [
            "status": "completed",
            "output": [["type": "function_call", "call_id": "c1", "name": "log_water",
                        "arguments": "{\"containers\": 2}"]],
        ])])
        let turn = try await AIRuntime.$current.withValue(runtime(transport)) {
            try await AIClient.makeFull().chatWithTools(
                system: "volatile", messages: [AnthropicClient.Msg(role: "user", content: "2 bottles")],
                tools: [["name": "log_water", "description": "d", "input_schema": ["type": "object"]]],
                model: "gpt-6.1-terra", maxTokens: 1500, cachedSystemPrefix: "stable", forbidToolUse: false)
        }
        XCTAssertEqual(turn.toolUse?.name, "log_water")
        XCTAssertEqual(turn.toolUse?.input["containers"] as? Int, 2)
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/responses")
    }

    /// Left to the API's default, Responses makes every tool property required and the
    /// model fills the optional ones with placeholders ("20 oz" arrived with a container
    /// count of 1, and the app logged one bottle). The coach's tools opt out.
    func testCoachToolsAreSentNonStrictOnResponses() async throws {
        let transport = ScriptedTransport([.json(200, [
            "status": "completed",
            "output": [["type": "function_call", "call_id": "c1", "name": "log_water", "arguments": "{\"oz\": 20}"]],
        ])])
        _ = try await AIRuntime.$current.withValue(runtime(transport)) {
            try await AIClient.makeFull().chatWithTools(
                system: "v", messages: [AnthropicClient.Msg(role: "user", content: "log 20 oz of water")],
                tools: [["name": "log_water", "description": "d", "input_schema": ["type": "object"]]],
                model: "gpt-5.6-terra", maxTokens: 1500, cachedSystemPrefix: "s", forbidToolUse: false)
        }
        let tools = try XCTUnwrap(transport.body()["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["strict"] as? Bool, false)
    }

    func testForcedStructuredCallKeepsTheDefaultStrictness() async throws {
        let transport = ScriptedTransport([.json(200, [
            "status": "completed",
            "output": [["type": "function_call", "call_id": "c", "name": "t", "arguments": "{}"]],
        ])])
        _ = try await AIRuntime.$current.withValue(runtime(transport)) {
            try await AIClient.makeFull().structured(system: "s", userContent: "u", toolName: "t",
                                                     toolDescription: "d", schema: ["type": "object"],
                                                     model: "gpt-5.6-terra", maxTokens: 100)
        }
        let tools = try XCTUnwrap(transport.body()["tools"] as? [[String: Any]])
        XCTAssertNil(tools.first?["strict"], "a forced call with all-required fields is left to normalize")
    }
}
