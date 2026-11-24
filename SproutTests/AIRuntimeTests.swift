import XCTest
@testable import Sprout

/// The seam tests and evals use to run the real AI clients against scripted or
/// recorded provider responses: a scoped key, provider, model, transport and usage
/// sink. Every test here runs the shipped request-build and parse code end to end
/// with no network and no stored key.
final class AIRuntimeTests: XCTestCase {

    private func runtime(_ provider: AIProvider, _ transport: ScriptedTransport,
                         model: String? = nil, usage: UsageRecorder? = nil,
                         effort: String? = nil) -> AIRuntime {
        AIRuntime(provider: provider, apiKey: "test-key-not-real", model: model,
                  reasoningEffort: effort, transport: transport,
                  onUsage: usage.map { recorder in { @Sendable reported in recorder.record(reported) } })
    }

    private let anthropicText: [String: Any] = [
        "model": "claude-haiku-4-5-20251001",
        "content": [["type": "text", "text": "Nice work today."]],
        "stop_reason": "end_turn",
        "usage": ["input_tokens": 120, "output_tokens": 9,
                  "cache_read_input_tokens": 800, "cache_creation_input_tokens": 40],
    ]

    // MARK: - Nothing scoped means nothing changes

    func testNoScopedRuntimeOutsideWithValue() {
        XCTAssertNil(AIRuntime.current)
        XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "m-1")
    }

    func testScopeEndsWithTheBlock() {
        AIRuntime.$current.withValue(AIRuntime(model: "scoped")) {
            XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "scoped")
        }
        XCTAssertNil(AIRuntime.current)
    }

    // MARK: - Provider, key and model

    func testScopedProviderSelectsTheClient() throws {
        try AIRuntime.$current.withValue(AIRuntime(provider: .openai, apiKey: "k")) {
            XCTAssertEqual(AIConfig.provider, .openai)
            XCTAssertTrue(try AIClient.makeFull() is OpenAIClient)
            XCTAssertTrue(AIConfig.hasActiveKey)
        }
        try AIRuntime.$current.withValue(AIRuntime(provider: .anthropic, apiKey: "k")) {
            XCTAssertEqual(AIConfig.provider, .anthropic)
            XCTAssertTrue(try AIClient.makeFull() is AnthropicClient)
        }
    }

    func testEmptyScopedKeyIsAMissingKey() throws {
        try AIRuntime.$current.withValue(AIRuntime(provider: .anthropic, apiKey: "")) {
            XCTAssertFalse(AIConfig.hasActiveKey)
            XCTAssertThrowsError(try AnthropicClient()) { error in
                guard case AIConfig.AIError.missingKey = error else {
                    return XCTFail("expected missingKey, got \(error)")
                }
            }
            XCTAssertThrowsError(try OpenAIClient())
        }
    }

    func testAnthropicRequestCarriesScopedKeyAndModel() async throws {
        let transport = ScriptedTransport([.json(200, anthropicText)])
        let text = try await AIRuntime.$current.withValue(runtime(.anthropic, transport, model: "claude-x")) {
            try await AIClient.make().chat(system: "sys",
                                           messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "claude-call-site", maxTokens: 50)
        }
        XCTAssertEqual(text, "Nice work today.")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key-not-real")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), AIConfig.anthropicVersion)
        XCTAssertEqual(transport.body()["model"] as? String, "claude-x",
                       "a scoped model overrides the call-site argument")
        XCTAssertEqual(transport.body()["max_tokens"] as? Int, 50)
    }

    func testWithoutScopedModelTheCallSiteModelIsSent() async throws {
        let transport = ScriptedTransport([.json(200, anthropicText)])
        _ = try await AIRuntime.$current.withValue(runtime(.anthropic, transport)) {
            try await AIClient.make().chat(system: "sys",
                                           messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "claude-call-site", maxTokens: 50)
        }
        XCTAssertEqual(transport.body()["model"] as? String, "claude-call-site")
    }

    // MARK: - Usage accounting, normalized across providers

    func testAnthropicUsageKeepsCachedTokensSeparate() async throws {
        let transport = ScriptedTransport([.json(200, anthropicText)])
        let usage = UsageRecorder()
        _ = try await AIRuntime.$current.withValue(runtime(.anthropic, transport, usage: usage)) {
            try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "m", maxTokens: 10)
        }
        let u = try XCTUnwrap(usage.all.first)
        XCTAssertEqual(usage.all.count, 1)
        XCTAssertEqual(u.provider, .anthropic)
        XCTAssertEqual(u.model, "claude-haiku-4-5-20251001", "the model the provider says answered")
        XCTAssertEqual(u.endpoint, "/v1/messages")
        XCTAssertEqual(u.uncachedInputTokens, 120)
        XCTAssertEqual(u.cacheReadTokens, 800)
        XCTAssertEqual(u.cacheWriteTokens, 40)
        XCTAssertEqual(u.outputTokens, 9)
        XCTAssertEqual(u.totalInputTokens, 960)
        XCTAssertEqual(u.attempts, 1)
    }

    func testOpenAIChatCompletionsUsageSubtractsCachedFromInput() async throws {
        let transport = ScriptedTransport([.json(200, [
            "model": "gpt-4.1-mini-2025-04-14",
            "choices": [["message": ["role": "assistant", "content": "Hello."]]],
            "usage": ["prompt_tokens": 1000, "completion_tokens": 12,
                      "prompt_tokens_details": ["cached_tokens": 600]],
        ])])
        let usage = UsageRecorder()
        let text = try await AIRuntime.$current.withValue(runtime(.openai, transport, usage: usage)) {
            try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "gpt-4.1-mini", maxTokens: 10)
        }
        XCTAssertEqual(text, "Hello.")
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/chat/completions")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer test-key-not-real")
        let u = try XCTUnwrap(usage.all.first)
        XCTAssertEqual(u.provider, .openai)
        XCTAssertEqual(u.uncachedInputTokens, 400, "OpenAI's input count includes the cached part")
        XCTAssertEqual(u.cacheReadTokens, 600)
        XCTAssertEqual(u.cacheWriteTokens, 0)
        XCTAssertEqual(u.outputTokens, 12)
        XCTAssertEqual(u.totalInputTokens, 1000)
    }

    func testOpenAIResponsesStructuredCallParsesAndReportsUsage() async throws {
        let transport = ScriptedTransport([.json(200, [
            "model": "gpt-5.6-terra",
            "status": "completed",
            "output": [[
                "type": "function_call", "call_id": "call_1", "name": "log_food",
                "arguments": "{\"total_calories\": 520}",
            ]],
            "usage": ["input_tokens": 700, "output_tokens": 55,
                      "input_tokens_details": ["cached_tokens": 512]],
        ])])
        let usage = UsageRecorder()
        let out = try await AIRuntime.$current.withValue(runtime(.openai, transport, usage: usage)) {
            try await AIClient.makeFull().structured(
                system: "sys", userContent: "a burrito", toolName: "log_food",
                toolDescription: "d", schema: ["type": "object"], model: "gpt-5.6-terra", maxTokens: 200)
        }
        XCTAssertEqual(out["total_calories"] as? Int, 520)
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/responses")
        let u = try XCTUnwrap(usage.all.first)
        XCTAssertEqual(u.endpoint, "/v1/responses")
        XCTAssertEqual(u.uncachedInputTokens, 188)
        XCTAssertEqual(u.cacheReadTokens, 512)
        XCTAssertEqual(u.outputTokens, 55)
    }

    func testScopedReasoningEffortReplacesTheBuiltInChoice() async throws {
        let reply: ScriptedTransport.Reply = .json(200, [
            "status": "completed",
            "output": [["type": "function_call", "call_id": "c", "name": "t", "arguments": "{}"]],
        ])
        let builtIn = ScriptedTransport([reply])
        _ = try await AIRuntime.$current.withValue(runtime(.openai, builtIn)) {
            try await AIClient.makeFull().structured(system: "s", userContent: "u", toolName: "t",
                                                     toolDescription: "d", schema: ["type": "object"],
                                                     model: "gpt-5.6-terra", maxTokens: 100)
        }
        XCTAssertEqual((builtIn.body()["reasoning"] as? [String: Any])?["effort"] as? String, "low")

        let forced = ScriptedTransport([reply])
        _ = try await AIRuntime.$current.withValue(runtime(.openai, forced, effort: "medium")) {
            try await AIClient.makeFull().structured(system: "s", userContent: "u", toolName: "t",
                                                     toolDescription: "d", schema: ["type": "object"],
                                                     model: "gpt-5.6-terra", maxTokens: 100)
        }
        XCTAssertEqual((forced.body()["reasoning"] as? [String: Any])?["effort"] as? String, "medium")
    }

    // MARK: - Errors and the one retry

    func testTransientOverloadIsRetriedOnceThenSucceeds() async throws {
        let transport = ScriptedTransport([
            .json(529, ["error": ["message": "Overloaded"]]),
            .json(200, anthropicText),
        ])
        let usage = UsageRecorder()
        let text = try await AIRuntime.$current.withValue(runtime(.anthropic, transport, usage: usage)) {
            try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "m", maxTokens: 10)
        }
        XCTAssertEqual(text, "Nice work today.")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(usage.all.first?.attempts, 2)
    }

    func testSecondOverloadSurfacesTheProviderMessage() async {
        let transport = ScriptedTransport([
            .json(529, ["error": ["message": "Overloaded"]]),
            .json(529, ["error": ["message": "Overloaded"]]),
        ])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(.anthropic, transport)) {
                try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                               model: "m", maxTokens: 10)
            }
            XCTFail("expected an error")
        } catch AIConfig.AIError.badResponse(let message) {
            XCTAssertEqual(message, "Overloaded")
            XCTAssertEqual(transport.requests.count, 2, "exactly one retry")
        } catch {
            XCTFail("expected badResponse, got \(error)")
        }
    }

    func testAuthFailureIsNotRetried() async {
        let transport = ScriptedTransport([.json(401, ["error": ["message": "invalid x-api-key"]])])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(.anthropic, transport)) {
                try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                               model: "m", maxTokens: 10)
            }
            XCTFail("expected an error")
        } catch AIConfig.AIError.badResponse(let message) {
            XCTAssertEqual(message, "invalid x-api-key")
            XCTAssertEqual(transport.requests.count, 1)
        } catch {
            XCTFail("expected badResponse, got \(error)")
        }
    }

    func testOpenAIRateLimitIsRetriedOnce() async throws {
        let transport = ScriptedTransport([
            .json(429, ["error": ["message": "Rate limit"]]),
            .json(200, ["choices": [["message": ["role": "assistant", "content": "ok"]]]]),
        ])
        let text = try await AIRuntime.$current.withValue(runtime(.openai, transport)) {
            try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "gpt-4.1-mini", maxTokens: 10)
        }
        XCTAssertEqual(text, "ok")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testEmptyModelTextIsADecodingErrorNotAnEmptyString() async {
        let transport = ScriptedTransport([.json(200, ["content": [["type": "text", "text": ""]]])])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(.anthropic, transport)) {
                try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                               model: "m", maxTokens: 10)
            }
            XCTFail("expected an error")
        } catch AIConfig.AIError.decoding {
            // expected
        } catch {
            XCTFail("expected decoding, got \(error)")
        }
    }

    // MARK: - A real feature through the seam

    func testMealDescriptionRunsEndToEndOnScriptedAnthropic() async throws {
        let estimate: [String: Any] = [
            "items": [["name": "banana", "estimated_grams": 118, "calories": 105, "protein_g": 1.3,
                       "carbs_g": 27, "fat_g": 0.4, "assumptions": "medium"]],
            "total_calories": 105, "calories_low": 90, "calories_high": 120,
            "total_protein_g": 1.3, "total_carbs_g": 27, "total_fat_g": 0.4,
            "confidence": "high", "notes": "One medium banana.",
        ]
        let transport = ScriptedTransport([.json(200, [
            "content": [["type": "tool_use", "id": "tu_1", "name": "log_food", "input": estimate]],
            "usage": ["input_tokens": 300, "output_tokens": 90],
        ])])
        let result = try await AIRuntime.$current.withValue(runtime(.anthropic, transport)) {
            try await FoodPhotoAnalyzer.analyze(description: "a medium banana")
        }
        XCTAssertEqual(result.total_calories, 105)
        XCTAssertEqual(result.items.first?.name, "banana")
        XCTAssertEqual(result.confidenceLevel, .high)
        let body = transport.body()
        XCTAssertEqual(body["model"] as? String, AIConfig.model(for: .mealDescribe, provider: .anthropic))
        XCTAssertEqual((body["tool_choice"] as? [String: Any])?["name"] as? String, "log_food",
                       "the estimate is a forced tool call")
    }

    func testMealDescriptionWithMissingFieldIsADecodingError() async {
        let transport = ScriptedTransport([.json(200, [
            "content": [["type": "tool_use", "id": "tu_1", "name": "log_food",
                         "input": ["total_calories": 105]]],
        ])])
        do {
            _ = try await AIRuntime.$current.withValue(runtime(.anthropic, transport)) {
                try await FoodPhotoAnalyzer.analyze(description: "a medium banana")
            }
            XCTFail("expected an error")
        } catch AIConfig.AIError.decoding {
            // expected: a partial estimate is never logged as a meal
        } catch {
            XCTFail("expected decoding, got \(error)")
        }
    }
}
