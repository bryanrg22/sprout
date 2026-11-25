import XCTest
@testable import Sprout

/// The estimator's four label nutrients (fiber, total sugars, saturated fat, sodium), end to
/// end through the shipped clients on every wire format the app speaks: Anthropic Messages,
/// OpenAI Responses and OpenAI Chat Completions. `FoodPhotoAnalyzer.analyze` runs under a
/// scoped `AIRuntime` with a scripted transport, so the request it builds and the reply it
/// decodes are the real ones.
///
/// What has to hold: "not known" has one spelling the schema allows on every provider
/// (null in a required field), and everything that is not a believable amount (a missing
/// key, a placeholder, an impossible number) decodes to `nil`, never to 0 and never to an
/// error that would cost the user the calories that did arrive.
final class MealEstimateDetailTests: XCTestCase {

    // MARK: - Wire formats

    private enum Wire: String, CaseIterable {
        case anthropic, openAIResponses, openAIChat

        var provider: AIProvider { self == .anthropic ? .anthropic : .openai }
        /// A model that routes to this wire format.
        var model: String? {
            switch self {
            case .anthropic: return nil
            case .openAIResponses: return "gpt-5.6-terra"
            case .openAIChat: return "gpt-4.1-mini"
            }
        }

        /// A provider reply carrying `estimate` as the forced `log_food` call's arguments.
        func reply(_ estimate: [String: Any]) -> [String: Any] {
            // swiftlint:disable:next force_try
            let arguments = String(decoding: try! JSONSerialization.data(withJSONObject: estimate), as: UTF8.self)
            switch self {
            case .anthropic:
                return ["content": [["type": "tool_use", "id": "tu_1", "name": "log_food", "input": estimate]],
                        "usage": ["input_tokens": 600, "output_tokens": 140]]
            case .openAIResponses:
                return ["model": "gpt-5.6-terra", "status": "completed",
                        "output": [["type": "function_call", "call_id": "call_1", "name": "log_food",
                                    "arguments": arguments]],
                        "usage": ["input_tokens": 600, "output_tokens": 140]]
            case .openAIChat:
                return ["choices": [["finish_reason": "tool_calls",
                                     "message": ["role": "assistant", "content": NSNull(),
                                                 "tool_calls": [["id": "call_1", "type": "function",
                                                                 "function": ["name": "log_food",
                                                                              "arguments": arguments]]]]]],
                        "usage": ["prompt_tokens": 600, "completion_tokens": 140]]
            }
        }

        /// The tool schema as it went out, from the request body.
        func sentSchema(_ body: [String: Any]) -> [String: Any]? {
            let tool = (body["tools"] as? [[String: Any]])?.first
            switch self {
            case .anthropic: return tool?["input_schema"] as? [String: Any]
            case .openAIResponses: return tool?["parameters"] as? [String: Any]
            case .openAIChat: return (tool?["function"] as? [String: Any])?["parameters"] as? [String: Any]
            }
        }

        var path: String {
            switch self {
            case .anthropic: return "/v1/messages"
            case .openAIResponses: return "/v1/responses"
            case .openAIChat: return "/v1/chat/completions"
            }
        }
    }

    /// A chicken-and-rice estimate with the nine original fields; `extra` adds or overrides.
    private func estimate(_ extra: [String: Any] = [:], calories: Double = 520, carbs: Double = 45,
                          fat: Double = 14) -> [String: Any] {
        var out: [String: Any] = [
            "items": [["name": "chicken and rice", "estimated_grams": 350, "calories": calories,
                       "protein_g": 46, "carbs_g": carbs, "fat_g": fat, "assumptions": "home portion"]],
            "total_calories": calories, "calories_low": calories * 0.85, "calories_high": calories * 1.15,
            "total_protein_g": 46, "total_carbs_g": carbs, "total_fat_g": fat,
            "confidence": "medium", "notes": "Grilled chicken with white rice.",
        ]
        for (key, value) in extra { out[key] = value }
        return out
    }

    private func analyze(_ estimate: [String: Any], on wire: Wire,
                         transport out: inout ScriptedTransport?) async throws -> FoodPhotoAnalyzer.Estimate {
        let transport = ScriptedTransport([.json(200, wire.reply(estimate))])
        out = transport
        let runtime = AIRuntime(provider: wire.provider, apiKey: "test-key-not-real", model: wire.model,
                                transport: transport)
        return try await AIRuntime.$current.withValue(runtime) {
            try await FoodPhotoAnalyzer.analyze(description: "grilled chicken with a cup of rice")
        }
    }

    /// Runs one scripted estimate on all three wire formats and hands each result to `check`.
    private func onEveryWire(_ estimate: [String: Any],
                             _ check: (FoodPhotoAnalyzer.Estimate, Wire) -> Void) async throws {
        for wire in Wire.allCases {
            var transport: ScriptedTransport?
            let result = try await analyze(estimate, on: wire, transport: &transport)
            XCTAssertEqual(transport?.requests.first?.url?.path, wire.path, "\(wire) went to its own endpoint")
            check(result, wire)
        }
    }

    // MARK: - Present

    func testAllFourPresentAreDecodedOnEveryWire() async throws {
        let sent = estimate(["total_fiber_g": 1.5, "total_sugars_g": 0.5,
                             "total_saturated_fat_g": 3.2, "total_sodium_mg": 410])
        try await onEveryWire(sent) { result, wire in
            XCTAssertEqual(result.total_calories, 520, "\(wire)")
            XCTAssertEqual(result.total_fiber_g, 1.5, "\(wire)")
            XCTAssertEqual(result.total_sugars_g, 0.5, "\(wire)")
            XCTAssertEqual(result.total_saturated_fat_g, 3.2, "\(wire)")
            XCTAssertEqual(result.total_sodium_mg, 410, "\(wire)")
            XCTAssertEqual(result.detail.known, [.saturatedFat, .sodium, .fiber, .sugars], "\(wire)")
        }
    }

    func testAGenuineZeroBesideRealValuesIsKept() async throws {
        // Grilled chicken alone: no fiber, no sugars, and that is the truth.
        let sent = estimate(["total_fiber_g": 0, "total_sugars_g": 0,
                             "total_saturated_fat_g": 1.4, "total_sodium_mg": 110],
                            calories: 230, carbs: 0, fat: 5)
        try await onEveryWire(sent) { result, wire in
            XCTAssertEqual(result.total_fiber_g, 0, "\(wire): 0 is a value when the others are real")
            XCTAssertEqual(result.total_sugars_g, 0, "\(wire)")
            XCTAssertEqual(result.total_saturated_fat_g, 1.4, "\(wire)")
            XCTAssertEqual(result.total_sodium_mg, 110, "\(wire)")
        }
    }

    // MARK: - Not known

    func testNullIsNotKnownOnEveryWire() async throws {
        let sent = estimate(["total_fiber_g": 1.5, "total_sugars_g": NSNull(),
                             "total_saturated_fat_g": 3.2, "total_sodium_mg": NSNull()])
        try await onEveryWire(sent) { result, wire in
            XCTAssertEqual(result.total_fiber_g, 1.5, "\(wire)")
            XCTAssertNil(result.total_sugars_g, "\(wire): null is the model saying it does not know")
            XCTAssertNil(result.total_sodium_mg, "\(wire)")
            XCTAssertEqual(result.detail.known, [.saturatedFat, .fiber], "\(wire)")
            XCTAssertNil(result.detail.sodiumMg, "\(wire): and it reaches the entry as not known, not 0")
        }
    }

    func testAnOlderResponseWithoutTheFieldsStillDecodes() async throws {
        // The reply shape from before these fields existed: nine fields, nothing else.
        try await onEveryWire(estimate()) { result, wire in
            XCTAssertEqual(result.total_calories, 520, "\(wire)")
            XCTAssertEqual(result.total_protein_g, 46, "\(wire)")
            XCTAssertEqual(result.items.count, 1, "\(wire)")
            XCTAssertNil(result.total_fiber_g, "\(wire)")
            XCTAssertNil(result.total_sugars_g, "\(wire)")
            XCTAssertNil(result.total_saturated_fat_g, "\(wire)")
            XCTAssertNil(result.total_sodium_mg, "\(wire)")
            XCTAssertTrue(result.detail.isEmpty, "\(wire)")
        }
    }

    // MARK: - Placeholders

    func testAllZeroFillerOnARealMealIsNotBelieved() async throws {
        // What a model does when it must fill required fields it has no basis for.
        let sent = estimate(["total_fiber_g": 0, "total_sugars_g": 0,
                             "total_saturated_fat_g": 0, "total_sodium_mg": 0])
        try await onEveryWire(sent) { result, wire in
            XCTAssertTrue(result.detail.isEmpty, "\(wire): four exact zeros on 520 kcal is a placeholder block")
            XCTAssertEqual(result.total_calories, 520, "\(wire): the rest of the estimate is kept")
        }
    }

    func testAllZeroOnANearlyEmptyDrinkIsBelieved() async throws {
        // Black coffee: under 50 kcal, where four zeros are the plain truth.
        let sent = estimate(["total_fiber_g": 0, "total_sugars_g": 0,
                             "total_saturated_fat_g": 0, "total_sodium_mg": 0],
                            calories: 5, carbs: 0, fat: 0)
        try await onEveryWire(sent) { result, wire in
            XCTAssertEqual(result.total_fiber_g, 0, "\(wire)")
            XCTAssertEqual(result.total_sodium_mg, 0, "\(wire)")
            XCTAssertEqual(result.detail.known.count, 4, "\(wire)")
        }
    }

    func testNegativeAndNonNumberPlaceholdersAreNotKnown() async throws {
        let sent = estimate(["total_fiber_g": -1, "total_sugars_g": "unknown",
                             "total_saturated_fat_g": "", "total_sodium_mg": "n/a"])
        try await onEveryWire(sent) { result, wire in
            XCTAssertTrue(result.detail.isEmpty, "\(wire)")
            XCTAssertEqual(result.total_calories, 520, "\(wire): a bad optional field never fails the estimate")
        }
    }

    func testOtherShapesInAnOptionalFieldAreNotKnown() async throws {
        let sent = estimate(["total_fiber_g": ["value": 3], "total_sugars_g": [1, 2],
                             "total_saturated_fat_g": true, "total_sodium_mg": 9_000_000])
        try await onEveryWire(sent) { result, wire in
            XCTAssertNil(result.total_fiber_g, "\(wire): an object")
            XCTAssertNil(result.total_sugars_g, "\(wire): an array")
            XCTAssertNil(result.total_sodium_mg, "\(wire): beyond any plausible meal")
            XCTAssertEqual(result.total_calories, 520, "\(wire)")
        }
    }

    func testAQuotedNumberIsRead() async throws {
        let sent = estimate(["total_fiber_g": "1.5", "total_sugars_g": " 2 ",
                             "total_saturated_fat_g": 3.2, "total_sodium_mg": "410"])
        try await onEveryWire(sent) { result, wire in
            XCTAssertEqual(result.total_fiber_g, 1.5, "\(wire)")
            XCTAssertEqual(result.total_sugars_g, 2, "\(wire)")
            XCTAssertEqual(result.total_sodium_mg, 410, "\(wire)")
        }
    }

    // MARK: - Amounts that cannot be true of the meal

    func testAPartLargerThanItsWholeIsNotKnown() async throws {
        // 45 g carbohydrate and 14 g fat: 80 g of sugars or 40 g of saturated fat cannot be.
        let sent = estimate(["total_fiber_g": 2, "total_sugars_g": 80,
                             "total_saturated_fat_g": 40, "total_sodium_mg": 410])
        try await onEveryWire(sent) { result, wire in
            XCTAssertNil(result.total_sugars_g, "\(wire): more sugars than carbohydrate")
            XCTAssertNil(result.total_saturated_fat_g, "\(wire): more saturated fat than fat")
            XCTAssertEqual(result.total_fiber_g, 2, "\(wire): the plausible ones are kept")
            XCTAssertEqual(result.total_sodium_mg, 410, "\(wire)")
        }
    }

    func testFiberPlusSugarsBeyondCarbohydrateDropsBoth() async throws {
        let sent = estimate(["total_fiber_g": 30, "total_sugars_g": 30,
                             "total_saturated_fat_g": 3, "total_sodium_mg": 410])
        try await onEveryWire(sent) { result, wire in
            XCTAssertNil(result.total_fiber_g, "\(wire): 30 + 30 g inside 45 g of carbohydrate")
            XCTAssertNil(result.total_sugars_g, "\(wire)")
            XCTAssertEqual(result.total_saturated_fat_g, 3, "\(wire)")
        }
    }

    func testRoundingSlackKeepsABorderlineValue() async throws {
        // 46 g of sugars against 45 g of carbohydrate is rounding, not a contradiction.
        let sent = estimate(["total_fiber_g": 0, "total_sugars_g": 46,
                             "total_saturated_fat_g": 14.5, "total_sodium_mg": 20])
        try await onEveryWire(sent) { result, wire in
            XCTAssertEqual(result.total_sugars_g, 46, "\(wire)")
            XCTAssertEqual(result.total_saturated_fat_g, 14.5, "\(wire)")
        }
    }

    func testZeroSaturatedFatInAFattyMealIsAPlaceholder() async throws {
        let sent = estimate(["total_fiber_g": 2, "total_sugars_g": 3,
                             "total_saturated_fat_g": 0, "total_sodium_mg": 410])
        try await onEveryWire(sent) { result, wire in
            XCTAssertNil(result.total_saturated_fat_g, "\(wire): 14 g of fat with no saturated fat does not exist")
            XCTAssertEqual(result.total_fiber_g, 2, "\(wire)")
        }
    }

    func testZeroSaturatedFatInALeanFoodIsKept() async throws {
        let sent = estimate(["total_fiber_g": 3, "total_sugars_g": 14,
                             "total_saturated_fat_g": 0, "total_sodium_mg": 1],
                            calories: 105, carbs: 27, fat: 0.4)
        try await onEveryWire(sent) { result, wire in
            XCTAssertEqual(result.total_saturated_fat_g, 0, "\(wire): a banana has next to none")
            XCTAssertEqual(result.total_sugars_g, 14, "\(wire)")
        }
    }

    // MARK: - The original fields are still strict

    func testAMissingOriginalFieldIsStillADecodingErrorOnEveryWire() async {
        var partial = estimate(["total_fiber_g": 2])
        partial["total_calories"] = nil
        for wire in Wire.allCases {
            var transport: ScriptedTransport?
            do {
                _ = try await analyze(partial, on: wire, transport: &transport)
                XCTFail("\(wire): expected a decoding error")
            } catch AIConfig.AIError.decoding {
                // expected: a partial estimate is never logged as a meal
            } catch {
                XCTFail("\(wire): expected decoding, got \(error)")
            }
        }
    }

    /// The note is one sentence of prose and is shown only when present. A reply without it
    /// (claude-haiku-5-5 sent one in 66 on 2026-11-25, EVAL_REPORT 37) keeps every number;
    /// a missing number is still an error (the test above).
    func testAMissingNoteKeepsTheEstimateOnEveryWire() async throws {
        var noNote = estimate()
        noNote["notes"] = nil
        try await onEveryWire(noNote) { result, wire in
            XCTAssertEqual(result.total_calories, 520, "\(wire)")
            XCTAssertEqual(result.total_protein_g, 46, "\(wire)")
            XCTAssertEqual(result.notes, "", "\(wire)")
        }
    }

    // MARK: - What is sent

    func testTheSchemaAsksForTheFourAsRequiredNullableNumbersOnEveryWire() async throws {
        let fields = ["total_fiber_g", "total_sugars_g", "total_saturated_fat_g", "total_sodium_mg"]
        for wire in Wire.allCases {
            var transport: ScriptedTransport?
            _ = try await analyze(estimate(), on: wire, transport: &transport)
            let body = try XCTUnwrap(transport?.body())
            let schema = try XCTUnwrap(wire.sentSchema(body), "\(wire)")
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any], "\(wire)")
            let required = try XCTUnwrap(schema["required"] as? [String], "\(wire)")
            for field in fields {
                let property = try XCTUnwrap(properties[field] as? [String: Any], "\(wire) \(field)")
                XCTAssertEqual(property["type"] as? [String], ["number", "null"],
                               "\(wire) \(field): null has to be a legal answer")
                XCTAssertTrue(required.contains(field),
                              "\(wire) \(field): required, so it means the same with and without strict mode")
            }
            // The original nine are still plain required numbers and strings.
            XCTAssertEqual((properties["total_calories"] as? [String: Any])?["type"] as? String, "number", "\(wire)")
            XCTAssertEqual(Set(required).count, 13, "\(wire)")
            // Nothing beyond the four is asked for.
            for absent in ["total_added_sugars_g", "total_cholesterol_mg", "total_potassium_mg", "total_calcium_mg"] {
                XCTAssertNil(properties[absent], "\(wire): \(absent) is never estimated")
            }
        }
    }

    func testTheEstimatedFieldsAreExactlyTheEstimableNutrients() {
        let properties = (FoodPhotoAnalyzer.estimateSchema["properties"] as? [String: Any]) ?? [:]
        let asked = Set(properties.keys.filter { $0.hasPrefix("total_") })
            .subtracting(["total_calories", "total_protein_g", "total_carbs_g", "total_fat_g"])
        XCTAssertEqual(asked, Set(Nutrient.estimable.map { "total_" + $0.argumentName }))
    }

    func testBothPromptsTellTheModelHowToSayItDoesNotKnow() async throws {
        func system(_ body: [String: Any]) -> String {
            if let text = body["system"] as? String { return text }
            return String(describing: body["system"] ?? "")
        }
        // Description path.
        var described: ScriptedTransport?
        _ = try await analyze(estimate(), on: .anthropic, transport: &described)
        let describeSystem = system(try XCTUnwrap(described?.body()))
        // Photo path.
        let photo = ScriptedTransport([.json(200, Wire.anthropic.reply(estimate()))])
        let runtime = AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", transport: photo)
        let fromPhoto = try await AIRuntime.$current.withValue(runtime) {
            try await FoodPhotoAnalyzer.analyze(imageData: Data([0xFF, 0xD8, 0xFF, 0xD9]), userNote: nil)
        }
        XCTAssertEqual(fromPhoto.total_calories, 520)
        let photoSystem = system(photo.body())

        for (name, text) in [("describe", describeSystem), ("photo", photoSystem)] {
            XCTAssertTrue(text.contains("total_fiber_g"), name)
            XCTAssertTrue(text.contains("total_sodium_mg"), name)
            XCTAssertTrue(text.contains("write null when you have no real basis"), name)
            XCTAssertTrue(text.contains("Never write 0 as a placeholder"), name)
            XCTAssertTrue(text.contains("Do not report any other nutrient"), name)
        }
    }

    // MARK: - Re-encoding (the evaluation record stores the estimate as JSON)

    func testAnEstimateEncodesAndDecodesBackWithUnknownsStillUnknown() throws {
        let data = try JSONSerialization.data(withJSONObject: estimate(["total_fiber_g": 1.5, "total_sodium_mg": NSNull()]))
        let decoded = try JSONDecoder().decode(FoodPhotoAnalyzer.Estimate.self, from: data)
        let again = try JSONDecoder().decode(FoodPhotoAnalyzer.Estimate.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again.total_fiber_g, 1.5)
        XCTAssertNil(again.total_sodium_mg)
        XCTAssertNil(again.total_sugars_g)
        XCTAssertEqual(again.total_calories, 520)
    }
}
