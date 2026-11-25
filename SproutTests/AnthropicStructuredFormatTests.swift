import XCTest
@testable import Sprout

/// Structured answers from the Claude models that refuse a forced tool call (EVAL_REPORT 30).
/// The shapes below were checked against the API on 2026-11-23: the refusal's text, the 400
/// for an object without `additionalProperties: false`, and a format answer as text.
final class AnthropicStructuredFormatTests: XCTestCase {

    private let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "chips": ["type": "array", "minItems": 2, "maxItems": 4, "description": "Quick-add chips",
                      "items": ["type": "object",
                                "properties": ["label": ["type": "string", "maxLength": 30],
                                               "calories": ["type": ["number", "null"], "minimum": 0],
                                               "kind": ["type": "string", "enum": ["add", "swap"]]],
                                "required": ["label"]]],
            "note": ["type": "string"],
            "tags": ["type": "array", "minItems": 1, "items": ["type": "string"]],
        ],
        "required": ["chips"],
    ]

    // MARK: - The schema the format accepts

    func testEveryObjectClosesAndTheRejectedLimitsBecomeWords() throws {
        let out = AnthropicStructuredFormat.schema(schema)
        XCTAssertEqual(out["additionalProperties"] as? Bool, false)
        let props = try XCTUnwrap(out["properties"] as? [String: Any])
        let chips = try XCTUnwrap(props["chips"] as? [String: Any])
        XCTAssertNil(chips["minItems"]); XCTAssertNil(chips["maxItems"])
        XCTAssertEqual(chips["description"] as? String, "Quick-add chips. At least 2 items, at most 4 items.")
        let item = try XCTUnwrap(chips["items"] as? [String: Any])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false, "nested objects close too")
        let itemProps = try XCTUnwrap(item["properties"] as? [String: Any])
        let label = try XCTUnwrap(itemProps["label"] as? [String: Any])
        XCTAssertNil(label["maxLength"]); XCTAssertEqual(label["description"] as? String, "At most 30 characters.")
        let calories = try XCTUnwrap(itemProps["calories"] as? [String: Any])
        XCTAssertNil(calories["minimum"]); XCTAssertEqual(calories["description"] as? String, "At least 0.")
        XCTAssertEqual(calories["type"] as? [String], ["number", "null"], "unions are accepted and kept")
        XCTAssertEqual((itemProps["kind"] as? [String: Any])?["enum"] as? [String], ["add", "swap"])
        XCTAssertEqual(item["required"] as? [String], ["label"])
        XCTAssertEqual(((props["tags"] as? [String: Any])?["minItems"]) as? Int, 1, "a minItems of 1 is accepted")
        XCTAssertNil((props["note"] as? [String: Any])?["additionalProperties"], "only objects close")
        XCTAssertEqual(out["required"] as? [String], ["chips"])
    }

    func testTheToolSchemaItselfIsNotChanged() {
        _ = AnthropicStructuredFormat.schema(schema)
        let chips = (schema["properties"] as? [String: Any])?["chips"] as? [String: Any]
        XCTAssertEqual(chips?["minItems"] as? Int, 2)
        XCTAssertNil(schema["additionalProperties"])
    }

    func testNoRejectedKeywordSurvivesAtAnyDepth() throws {
        // The keywords the format rejected, or that the API documents as unsupported.
        let rejected: Set<String> = ["maxItems", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
                                     "minLength", "maxLength", "multipleOf"]
        func check(_ node: Any, _ path: String) {
            if let dict = node as? [String: Any] {
                for key in dict.keys where rejected.contains(key) { XCTFail("\(path).\(key) survived") }
                if let min = dict["minItems"] as? Int, min > 1 { XCTFail("\(path).minItems \(min) survived") }
                if dict["properties"] != nil || (dict["type"] as? String) == "object" {
                    XCTAssertEqual(dict["additionalProperties"] as? Bool, false, "\(path) is closed")
                }
                for (k, v) in dict { check(v, path + "." + k) }
            } else if let list = node as? [Any] {
                for (i, v) in list.enumerated() { check(v, path + "[\(i)]") }
            }
        }
        check(AnthropicStructuredFormat.schema(schema), "test")
    }

    func testTheAnswerIsReadFromTextWithOrWithoutAFence() {
        XCTAssertEqual(AnthropicStructuredFormat.object(fromText: #"{"a":1}"#)?["a"] as? Int, 1)
        XCTAssertEqual(AnthropicStructuredFormat.object(fromText: "```json\n{\"a\":2}\n```")?["a"] as? Int, 2)
        XCTAssertNil(AnthropicStructuredFormat.object(fromText: "[1,2]"), "an array is not the object asked for")
        XCTAssertNil(AnthropicStructuredFormat.object(fromText: "Sure! Here you go."))
    }

    // MARK: - Which models, and the refusal

    func testTheKnownRefusersAndOnlyThem() {
        for m in ["claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-2", "claude-sonnet-5-5-20261001"] {
            XCTAssertTrue(AnthropicStructuredFormat.refusesForcedToolChoice(m), m)
        }
        for m in ["claude-sonnet-5", "claude-haiku-5-5", "claude-haiku-4-5-20251001", "claude-opus-5-6", ""] {
            XCTAssertFalse(AnthropicStructuredFormat.refusesForcedToolChoice(m), m)
        }
    }

    func testTheRefusalIsRecognisedByItsTextAndNothingElseIs() {
        let live = #"tool_choice: type "tool" and "any" are not supported for this model."#
        XCTAssertTrue(AnthropicStructuredFormat.isForcedToolRefusal(AIConfig.AIError.badResponse(live)))
        XCTAssertFalse(AnthropicStructuredFormat.isForcedToolRefusal(AIConfig.AIError.badResponse("invalid x-api-key")))
        XCTAssertFalse(AnthropicStructuredFormat.isForcedToolRefusal(AIConfig.AIError.decoding(live)))
    }

    // MARK: - The client

    private func runtime(_ t: ScriptedTransport) -> AIRuntime {
        AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", transport: t)
    }

    private func textReply(_ text: String, stop: String = "end_turn") -> [String: Any] {
        ["model": "m", "content": [["type": "text", "text": text]], "stop_reason": stop,
         "usage": ["input_tokens": 100, "output_tokens": 40]]
    }

    private func call(_ model: String, _ t: ScriptedTransport) async throws -> [String: Any] {
        try await AIRuntime.$current.withValue(runtime(t)) {
            try await AnthropicClient().structured(system: "s", userContent: "u", toolName: "emit",
                                                   toolDescription: "d", schema: schema, model: model, maxTokens: 400)
        }
    }

    /// A model whose thinking cannot be switched off gets room to think on top of what the
    /// call asked for (EVAL_REPORT 40); every other model is sent exactly what was asked.
    func testAModelThatAlwaysThinksGetsHeadroomAndNoOtherDoes() async throws {
        let reply = #"{"chips":[{"label":"Egg","calories":78},{"label":"Toast","calories":80}]}"#
        for (model, expected) in [("claude-opus-5-5", 400 + AnthropicModelProfile.thinkingHeadroom),
                                  ("claude-fable-5-2", 400 + AnthropicModelProfile.thinkingHeadroom),
                                  ("claude-sonnet-5-5", 400)] {
            let t = ScriptedTransport([.json(200, textReply(reply))])
            _ = try await call(model, t)
            XCTAssertEqual(t.body()["max_tokens"] as? Int, expected, model)
        }
        XCTAssertEqual(AnthropicModelProfile.maxTokens(2200, for: "claude-opus-5-5-20261101"), 2200 + 4096, "a dated snapshot")
        XCTAssertEqual(AnthropicModelProfile.maxTokens(2200, for: "claude-opus-5"), 2200, "another model is not matched by prefix")
        XCTAssertEqual(AnthropicModelProfile.maxTokens(2200, for: "claude-haiku-5-5"), 2200)
        XCTAssertEqual(AnthropicModelProfile.maxTokens(2200, for: "claude-opus-4-8"), 2200)
    }

    func testARefuserIsAskedForTheFormatAndItsTextIsTheAnswer() async throws {
        let t = ScriptedTransport([.json(200, textReply(#"{"chips":[{"label":"Greek yogurt","calories":100},{"label":"Egg","calories":78}]}"#))])
        let out = try await call("claude-sonnet-5-5", t)
        XCTAssertEqual((out["chips"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(t.requests.count, 1, "no doomed forced call first")
        let body = t.body()
        XCTAssertNil(body["tools"]); XCTAssertNil(body["tool_choice"])
        let format = try XCTUnwrap((body["output_config"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual((format["schema"] as? [String: Any])?["additionalProperties"] as? Bool, false)
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "between_tools")
        XCTAssertEqual(body["max_tokens"] as? Int, 400)
    }

    func testFableIsSentNoThinkingFieldBecauseItTakesNone() async throws {
        let t = ScriptedTransport([.json(200, textReply(#"{"chips":[{"label":"A"},{"label":"B"}]}"#))])
        _ = try await call("claude-fable-5-2", t)
        XCTAssertNil(t.body()["thinking"])
        XCTAssertNotNil(t.body()["output_config"])
    }

    func testAnUnknownModelThatRefusesIsMovedToTheFormatAfterOneRequest() async throws {
        let refusal: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error",
            "message": #"tool_choice: type "tool" and "any" are not supported for this model."#]]
        let t = ScriptedTransport([.json(400, refusal), .json(200, textReply(#"{"chips":[{"label":"Oats"},{"label":"Egg"}]}"#))])
        let out = try await call("claude-opus-5-6", t)
        XCTAssertEqual((out["chips"] as? [[String: Any]])?.first?["label"] as? String, "Oats")
        XCTAssertEqual(t.requests.count, 2)
        XCTAssertNotNil(t.body(0)["tool_choice"], "the first try was the forced call")
        XCTAssertNil(t.body(1)["tool_choice"])
        XCTAssertNotNil(t.body(1)["output_config"])
    }

    func testAnyOtherFailureOfTheForcedCallIsNotRetriedAsAFormat() async {
        let t = ScriptedTransport([.json(401, ["type": "error", "error": ["type": "authentication_error", "message": "invalid x-api-key"]])])
        do {
            _ = try await call("claude-haiku-4-5-20251001", t)
            XCTFail("must throw")
        } catch AIConfig.AIError.badResponse(let m) {
            XCTAssertTrue(m.contains("invalid x-api-key"), m)
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(t.requests.count, 1)
    }

    func testAFormatAnswerCutOffAtTheCapIsNeverUsedEvenIfItParses() async {
        let t = ScriptedTransport([.json(200, textReply(#"{"chips":[]}"#, stop: "max_tokens"))])
        do {
            _ = try await call("claude-sonnet-5-5", t)
            XCTFail("must throw")
        } catch AIConfig.AIError.decoding(let what) {
            XCTAssertEqual(what, "the answer was cut off at 400 tokens")
        } catch { XCTFail("\(error)") }
    }

    func testAFormatAnswerThatIsNotJSONIsADecodingError() async {
        let t = ScriptedTransport([.json(200, textReply("I can't do that."))])
        do {
            _ = try await call("claude-sonnet-5-5", t)
            XCTFail("must throw")
        } catch AIConfig.AIError.decoding(let what) {
            XCTAssertEqual(what, "the answer was not a JSON object")
        } catch { XCTFail("\(error)") }
    }

    func testTheLimitsTakenOutOfTheRequestAreCheckedOnTheAnswer() {
        func broken(_ json: String) -> [String] {
            let obj = AnthropicStructuredFormat.object(fromText: json)
            return AnthropicStructuredFormat.violations(obj, against: schema)
        }
        XCTAssertEqual(broken(#"{"chips":[{"label":"A"},{"label":"B"}]}"#), [])
        XCTAssertEqual(broken(#"{"chips":[{"label":"placeholder"}]}"#), ["answer.chips: 1 items, at least 2"],
                       "the live failure: one item where two to four are asked for")
        XCTAssertEqual(broken(#"{"chips":[{"label":"A"},{"label":"B"},{"label":"C"},{"label":"D"},{"label":"E"}]}"#),
                       ["answer.chips: 5 items, at most 4"])
        XCTAssertEqual(broken(#"{"chips":[{"label":"A"},{"label":"B","calories":-5}]}"#), ["answer.chips[1].calories: -5.0, at least 0.0"])
        XCTAssertEqual(broken(#"{"chips":[{"label":"A"},{"label":"B","calories":null}]}"#), [], "null is allowed by the union")
        XCTAssertEqual(broken(#"{"chips":[{"label":"A"},{"label":"\#(String(repeating: "x", count: 31))"}]}"#),
                       ["answer.chips[1].label: 31 characters, at most 30"])
        XCTAssertEqual(broken(#"{"note":"no chips at all"}"#), [], "a missing field is the caller's to judge, as before")
    }

    func testAnAnswerThatBreaksAMovedLimitIsNotUsed() async {
        let t = ScriptedTransport([.json(200, textReply(#"{"chips":[{"label":"placeholder"}]}"#))])
        do {
            _ = try await call("claude-sonnet-5-5", t)
            XCTFail("must throw")
        } catch AIConfig.AIError.decoding(let what) {
            XCTAssertEqual(what, "the answer broke the schema (answer.chips: 1 items, at least 2)")
        } catch { XCTFail("\(error)") }
    }

    func testTheRepairForADoubleEncodedFieldStillApplies() async throws {
        let t = ScriptedTransport([.json(200, textReply(#"{"chips":"[{\"label\":\"Oats\"},{\"label\":\"Egg\"}]"}"#))])
        let out = try await call("claude-sonnet-5-5", t)
        XCTAssertEqual((out["chips"] as? [[String: Any]])?.first?["label"] as? String, "Oats")
    }

    func testAModelThatTakesAForcedCallIsUnchanged() async throws {
        let toolReply: [String: Any] = ["model": "m", "content": [["type": "tool_use", "id": "t", "name": "emit",
                                                                    "input": ["chips": [["label": "Egg"]]]]],
                                        "stop_reason": "tool_use", "usage": ["input_tokens": 1, "output_tokens": 1]]
        let t = ScriptedTransport([.json(200, toolReply)])
        let out = try await call("claude-haiku-4-5-20251001", t)
        XCTAssertEqual((out["chips"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((t.body()["tool_choice"] as? [String: Any])?["type"] as? String, "tool")
        XCTAssertNil(t.body()["output_config"])
    }
}
