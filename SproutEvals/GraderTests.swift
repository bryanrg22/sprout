import UIKit
import XCTest
@testable import Sprout

/// Offline checks of the evaluation machinery itself: the graders against hand-written
/// outputs, and every dataset row against the app (does it decode, does the template
/// ladder pick the topic the row claims, does a correct tool call actually pass).
/// No network, no key. These run in CI; the live evals do not.
@MainActor
final class GraderTests: XCTestCase {

    /// `Evals/` on the host, found from this file's own path (the simulator reads host paths).
    private var evalsRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Evals")
    }

    private func rows<T: Decodable>(_ path: String, as type: T.Type) throws -> [T] {
        try EvalDataset.decode(contentsOf: evalsRoot.appendingPathComponent("datasets/\(path)"), as: type)
    }

    // MARK: - Candidate specs

    func testCandidateSpecParsing() {
        XCTAssertEqual(EvalCandidate.parse("anthropic:claude-haiku-4-5"),
                       EvalCandidate(provider: .anthropic, model: "claude-haiku-4-5", effort: nil))
        XCTAssertEqual(EvalCandidate.parse(" openai:gpt-5.6-terra@medium "),
                       EvalCandidate(provider: .openai, model: "gpt-5.6-terra", effort: "medium"))
        XCTAssertEqual(EvalCandidate.parse("openai:gpt-5.6-terra@medium")?.id, "openai:gpt-5.6-terra@medium")
        XCTAssertNil(EvalCandidate.parse("gemini:pro"))
        XCTAssertNil(EvalCandidate.parse("openai:"))
        XCTAssertNil(EvalCandidate.parse("no-colon"))
    }

    // MARK: - Meal grader

    private func estimate(total: Double, low: Double, high: Double, items: [Double],
                          protein: Double = 0, carbs: Double = 0, fat: Double = 0,
                          confidence: String = "high") -> FoodPhotoAnalyzer.Estimate {
        FoodPhotoAnalyzer.Estimate(
            items: items.map { .init(name: "x", estimated_grams: 100, calories: $0, protein_g: 0,
                                     carbs_g: 0, fat_g: 0, assumptions: "") },
            total_calories: total, calories_low: low, calories_high: high,
            total_protein_g: protein, total_carbs_g: carbs, total_fat_g: fat,
            confidence: confidence, notes: "")
    }

    private let banana = Graders.MealTruth(id: "b", description: "banana", kcal: 105, protein_g: 1.3,
                                           carbs_g: 26.9, fat_g: 0.4, source: "test")

    func testMealWithinToleranceEdge() {
        // 20% of 105 is 21: 126 passes, 127 fails.
        XCTAssertTrue(Graders.meal(estimate(total: 126, low: 100, high: 140, items: [126]), truth: banana).pass)
        XCTAssertFalse(Graders.meal(estimate(total: 127, low: 100, high: 140, items: [127]), truth: banana).pass)
        XCTAssertTrue(Graders.meal(estimate(total: 84, low: 80, high: 110, items: [84]), truth: banana).pass)
        XCTAssertFalse(Graders.meal(estimate(total: 83, low: 80, high: 110, items: [83]), truth: banana).pass)
    }

    func testMealScoresAreComputedFromTheEstimate() {
        let graded = Graders.meal(estimate(total: 110, low: 90, high: 130, items: [60, 50],
                                           protein: 2.3, carbs: 20.9, fat: 0.4), truth: banana)
        XCTAssertEqual(graded.scores["kcal_pct_error"] ?? -1, 5.0 / 105.0, accuracy: 1e-9)
        XCTAssertEqual(graded.scores["protein_abs_error_g"] ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(graded.scores["carbs_abs_error_g"] ?? -1, 6.0, accuracy: 1e-9)
        XCTAssertEqual(graded.scores["fat_abs_error_g"] ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertEqual(graded.scores["truth_in_stated_range"], 1)
        XCTAssertEqual(graded.scores["items_sum_to_total"], 1)
        XCTAssertEqual(graded.scores["range_well_formed"], 1)
        XCTAssertEqual(graded.scores["confidence_is_valid"], 1)
    }

    func testMealFlagsInconsistentOutput() {
        // Items sum to 200 but the total says 110; the range excludes both the total and the truth.
        let graded = Graders.meal(estimate(total: 110, low: 150, high: 140, items: [120, 80],
                                           confidence: "certain"), truth: banana)
        XCTAssertEqual(graded.scores["items_sum_to_total"], 0)
        XCTAssertEqual(graded.scores["range_well_formed"], 0)
        XCTAssertEqual(graded.scores["truth_in_stated_range"], 0)
        XCTAssertEqual(graded.scores["confidence_is_valid"], 0)
    }

    func testPercentErrorOnZeroTruth() {
        XCTAssertEqual(Graders.absPctError(0, 0), 0)
        XCTAssertEqual(Graders.absPctError(5, 0), 1)
    }

    // MARK: - Meal grader: the label nutrients

    private func withDetail(_ base: FoodPhotoAnalyzer.Estimate, fiber: Double?, sugars: Double?,
                            saturatedFat: Double?, sodium: Double?) -> FoodPhotoAnalyzer.Estimate {
        var out = base
        out.total_fiber_g = fiber
        out.total_sugars_g = sugars
        out.total_saturated_fat_g = saturatedFat
        out.total_sodium_mg = sodium
        return out
    }

    /// A banana with its label nutrients (round numbers for the arithmetic, not USDA's).
    private var bananaWithDetail: Graders.MealTruth {
        Graders.MealTruth(id: "b", description: "banana", kcal: 105, protein_g: 1.3, carbs_g: 26.9, fat_g: 0.4,
                          source: "test", fiber_g: 3.0, sugars_g: 14.0, saturated_fat_g: 0.1, sodium_mg: 1.0)
    }

    func testDetailErrorIsAbsoluteInEachNutrientsOwnUnit() {
        let estimate = withDetail(estimate(total: 105, low: 90, high: 120, items: [105]),
                                  fiber: 2.5, sugars: 17, saturatedFat: 0.1, sodium: 26)
        let scores = Graders.meal(estimate, truth: bananaWithDetail).scores
        XCTAssertEqual(scores["fiber_g_abs_error"] ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(scores["sugars_g_abs_error"] ?? -1, 3.0, accuracy: 1e-9)
        XCTAssertEqual(scores["saturated_fat_g_abs_error"] ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertEqual(scores["sodium_mg_abs_error"] ?? -1, 25.0, accuracy: 1e-9, "milligrams, not grams")
        for name in ["fiber_g", "sugars_g", "saturated_fat_g", "sodium_mg"] {
            XCTAssertEqual(scores["\(name)_answered"], 1, name)
            XCTAssertNil(scores["\(name)_unknown_when_no_basis"], "no case here is labelled no-basis")
        }
    }

    func testAnAbstentionIsCountedAsNotAnsweredAndNeverAsAnError() {
        let estimate = withDetail(estimate(total: 105, low: 90, high: 120, items: [105]),
                                  fiber: 3, sugars: nil, saturatedFat: nil, sodium: 1)
        let scores = Graders.meal(estimate, truth: bananaWithDetail).scores
        XCTAssertEqual(scores["sugars_g_answered"], 0)
        XCTAssertNil(scores["sugars_g_abs_error"], "not known is not an error of 0 g and not an error of 14 g")
        XCTAssertEqual(scores["saturated_fat_g_answered"], 0)
        XCTAssertNil(scores["saturated_fat_g_abs_error"])
        XCTAssertEqual(scores["fiber_g_answered"], 1)
        XCTAssertEqual(scores["fiber_g_abs_error"] ?? -1, 0, accuracy: 1e-9)
    }

    func testANutrientTheTruthDoesNotStateIsNotGraded() {
        // The v1 rows, and any v3 row where USDA lists nothing for an ingredient.
        let estimate = withDetail(estimate(total: 105, low: 90, high: 120, items: [105]),
                                  fiber: 3, sugars: 14, saturatedFat: 0.1, sodium: 1)
        let scores = Graders.meal(estimate, truth: banana).scores
        for name in ["fiber_g", "sugars_g", "saturated_fat_g", "sodium_mg"] {
            XCTAssertNil(scores["\(name)_abs_error"], name)
            XCTAssertNil(scores["\(name)_answered"], name)
        }
        // Partly stated: only what is stated is graded.
        let partial = Graders.MealTruth(id: "p", description: "x", kcal: 105, protein_g: 1, carbs_g: 27, fat_g: 0.4,
                                        source: "test", fiber_g: 3.0, sodium_mg: 1.0)
        let partialScores = Graders.meal(estimate, truth: partial).scores
        XCTAssertNotNil(partialScores["fiber_g_abs_error"])
        XCTAssertNotNil(partialScores["sodium_mg_abs_error"])
        XCTAssertNil(partialScores["sugars_g_abs_error"])
        XCTAssertNil(partialScores["saturated_fat_g_answered"])
    }

    func testSayingUnknownWhereThereIsNoBasisIsScored() {
        // A description that cannot settle sodium (how was it seasoned?), labelled as such.
        let vague = Graders.MealTruth(id: "v", description: "a bowl of homemade soup", kcal: 200, protein_g: 10,
                                      carbs_g: 20, fat_g: 8, source: "test", fiber_g: 3.0,
                                      no_basis: ["sodium_mg"])
        let abstained = withDetail(estimate(total: 200, low: 150, high: 260, items: [200]),
                                   fiber: 3, sugars: 4, saturatedFat: 2, sodium: nil)
        var scores = Graders.meal(abstained, truth: vague).scores
        XCTAssertEqual(scores["sodium_mg_unknown_when_no_basis"], 1)
        XCTAssertNil(scores["sodium_mg_answered"], "a no-basis nutrient is scored only for the abstention")
        XCTAssertNil(scores["sodium_mg_abs_error"])
        XCTAssertEqual(scores["fiber_g_answered"], 1, "the others are graded as usual")

        let guessed = withDetail(abstained, fiber: 3, sugars: 4, saturatedFat: 2, sodium: 900)
        scores = Graders.meal(guessed, truth: vague).scores
        XCTAssertEqual(scores["sodium_mg_unknown_when_no_basis"], 0, "it produced a number it had no basis for")
    }

    func testTheLabelNutrientsDoNotDecideThePass() {
        // Calories right, every label nutrient badly wrong: still a pass, by the unchanged rule.
        let wrong = withDetail(estimate(total: 105, low: 90, high: 120, items: [105]),
                               fiber: 30, sugars: 0, saturatedFat: 9, sodium: 2_000)
        XCTAssertTrue(Graders.meal(wrong, truth: bananaWithDetail).pass)
        // Calories wrong, label nutrients perfect: still a fail.
        let off = withDetail(estimate(total: 200, low: 180, high: 220, items: [200]),
                             fiber: 3, sugars: 14, saturatedFat: 0.1, sodium: 1)
        XCTAssertFalse(Graders.meal(off, truth: bananaWithDetail).pass)
    }

    func testOnlyTheEstimableNutrientsAreGraded() {
        let scores = Graders.mealDetail(withDetail(estimate(total: 105, low: 90, high: 120, items: [105]),
                                                   fiber: 3, sugars: 14, saturatedFat: 0.1, sodium: 1),
                                        truth: bananaWithDetail)
        XCTAssertEqual(Set(scores.keys), Set(Nutrient.estimable.flatMap {
            ["\($0.argumentName)_abs_error", "\($0.argumentName)_answered"]
        }))
        for nutrient in Nutrient.allCases where !Nutrient.estimable.contains(nutrient) {
            XCTAssertNil(bananaWithDetail.truth(for: nutrient), "\(nutrient) is not asked of the estimator")
        }
    }

    // MARK: - Number preservation

    func testNumbersAreNormalized() {
        XCTAssertEqual(Graders.numbers(in: "15,420 steps, HR 59, 7.5 h. Day 3."), [15420, 59, 7.5, 3])
        XCTAssertEqual(Graders.numbers(in: "no digits here"), [])
    }

    func testNumbersWrittenAsWordsCount() {
        XCTAssertEqual(Graders.numbers(in: "Alex, fourteen days in a row now!"), [14])
        XCTAssertEqual(Graders.numbers(in: "Twenty-eight days. Eight hours east."), [28, 8])
        XCTAssertEqual(Graders.numbers(in: "a ten-minute walk"), [10])
        XCTAssertEqual(Graders.numbers(in: "ninety"), [90])
        XCTAssertEqual(Graders.numbers(in: "one steady day at a time; no one is perfect"), [],
                       "'one' is not counted as a quantity")
        XCTAssertEqual(Graders.numbers(in: "someone often went eighty-one times"), [81])
        // The rule the brief is graded on: a number kept in words is still kept.
        let kept = Graders.numbersPreserved(source: "14 days of showing up in a row.",
                                            rewrite: "Fourteen days in a row, Alex.")
        XCTAssertTrue(kept.allKept); XCTAssertTrue(kept.noneInvented)
        let invented = Graders.numbersPreserved(source: "14 days of showing up in a row.",
                                                rewrite: "14 days; go for thirty.")
        XCTAssertFalse(invented.noneInvented)
    }

    func testFoodValueIsCaloriesTimesQuantity() throws {
        let view = try view("log_food", ["name": "Egg", "meal": "breakfast", "calories": 72,
                                         "protein_g": 6, "carbs_g": 0, "fat_g": 5, "quantity": 2])
        XCTAssertEqual(view.number(key: "calories") ?? 0, 72, accuracy: 0.001)
        XCTAssertEqual(view.number(key: "calories*quantity") ?? 0, 144, accuracy: 0.001)
        XCTAssertNil(view.number(key: "calories*nonexistent"))
    }

    func testNumbersPreserved() {
        let source = "15,420 steps, and your resting heart rate is holding at 59."
        var r = Graders.numbersPreserved(source: source, rewrite: "You hit 15420 steps and your heart sat at 59!")
        XCTAssertTrue(r.allKept); XCTAssertTrue(r.noneInvented)
        r = Graders.numbersPreserved(source: source, rewrite: "Big day — 15,420 steps!")
        XCTAssertFalse(r.allKept, "dropped 59"); XCTAssertTrue(r.noneInvented)
        r = Graders.numbersPreserved(source: source, rewrite: "15,420 steps, HR 59 — try for 16,000 today.")
        XCTAssertTrue(r.allKept); XCTAssertFalse(r.noneInvented, "16,000 was never in the source")
    }

    func testFemininePronounDetectionIsWordBased() {
        XCTAssertTrue(Graders.containsFemininePronoun("She showed up again."))
        XCTAssertTrue(Graders.containsFemininePronoun("Proud of her streak!"))
        XCTAssertFalse(Graders.containsFemininePronoun("There you are — here for the weather, sheer effort."))
    }

    func testSentenceCount() {
        XCTAssertEqual(Graders.sentenceCount("One. Two! Three?"), 3)
        XCTAssertEqual(Graders.sentenceCount("Just one line"), 1)
    }

    func testBriefGradePassesOnlyWhenFactsAndPersonAreIntact() {
        let template = ("14 days of showing up in a row.", "Showing up beats being perfect.")
        XCTAssertTrue(LiveEvals.gradeBrief(template: template, reply: ("14 days straight, Alex.", "That consistency is everything."),
                                           readerIsNotAWoman: true).pass)
        XCTAssertFalse(LiveEvals.gradeBrief(template: template, reply: ("Two weeks straight.", "Keep going."),
                                            readerIsNotAWoman: true).pass, "the number 14 was dropped")
        XCTAssertFalse(LiveEvals.gradeBrief(template: template, reply: ("14 days straight.", "She keeps showing up."),
                                            readerIsNotAWoman: true).pass, "wrong person")
        XCTAssertTrue(LiveEvals.gradeBrief(template: template, reply: ("14 days straight.", "She keeps showing up."),
                                           readerIsNotAWoman: false).pass)
    }

    // MARK: - Tool-choice grader, driven through the app's real parser

    struct FixtureRejected: Error { let tool: String; let reason: String }

    private func view(_ tool: String, _ input: [String: Any], user key: String = "gain") throws -> Graders.ActionView {
        let user = EvalFixtures.user(key)
        switch CoachTools.parse(name: tool, input: input, profile: user.profile, todaysFoods: user.foods) {
        case .ok(let request): return Graders.ActionView(request.action)
        case .invalid(let reason): throw FixtureRejected(tool: tool, reason: reason)
        }
    }

    private func expectation(_ id: String) throws -> Graders.ToolExpectation {
        let all = try rows("coach_tool_choice/v2.jsonl", as: Graders.ToolExpectation.self)
        return try XCTUnwrap(all.first { $0.id == id }, "no case \(id)")
    }

    /// For each case below, the tool call a correct model would make must be accepted by
    /// the app AND pass the case's own expectation. This is what proves the labels in the
    /// dataset are written in the vocabulary the grader actually sees.
    func testCorrectCallsPassTheirCases() throws {
        let correct: [(String, String, [String: Any])] = [
            ("water-2-bottles", "log_water", ["containers": 2]),
            ("water-20oz", "log_water", ["oz": 20]),
            ("weight-morning", "log_weight", ["weight": 161.2]),
            ("weight-loss-user", "log_weight", ["weight": 157.6]),
            ("food-banana", "log_food", ["name": "Banana", "meal": "snack", "calories": 105,
                                         "protein_g": 1.3, "carbs_g": 27, "fat_g": 0.4]),
            ("food-stated-calories", "log_food", ["name": "Protein shake", "meal": "lunch", "calories": 220,
                                                  "protein_g": 30, "carbs_g": 12, "fat_g": 5]),
            // Two eggs can be logged as one entry of 155 or as two servings of about 72:
            // both are the same meal, and both must pass.
            ("food-eggs", "log_food", ["name": "Two hard-boiled eggs", "meal": "breakfast", "calories": 155,
                                       "protein_g": 13, "carbs_g": 1, "fat_g": 11]),
            ("food-eggs", "log_food", ["name": "Hard-boiled egg", "meal": "breakfast", "calories": 72,
                                       "protein_g": 6.3, "carbs_g": 0.4, "fat_g": 4.8, "quantity": 2]),
            ("workout-run", "log_workout", ["kind": "run", "minutes": 30]),
            ("workout-lift", "log_workout", ["kind": "gym", "minutes": 45]),
            ("food-delete", "delete_food", ["name": "Greek yogurt"]),
            ("food-edit-calories", "edit_food", ["name": "Chicken burrito bowl", "calories": 800]),
            ("step-goal", "set_step_goal", ["steps": 10000]),
            ("water-goal", "set_water_goal_containers", ["count": 6]),
            ("goal-weight-gain", "set_weight_goal", ["weight": 175]),
            ("goal-weight-loss", "set_weight_goal", ["weight": 140]),
            ("start-weight", "set_start_weight", ["weight": 156]),
            ("protein-goal", "set_protein_goal", ["grams": 150]),
            ("units-metric", "set_units", ["system": "metric"]),
            ("height-cm", "set_height", ["cm": 180]),
            ("coach-name", "set_coach_name", ["name": "Max"]),
            ("steps-budget-off", "toggle_steps_in_budget", ["enabled": false]),
            ("direction-switch", "set_goal_direction", ["direction": "gain"]),
            ("pace-faster", "set_pace", ["pace": "steady"]),
            ("remember-vegetarian", "remember_about_user", ["note": "Vegetarian"]),
            ("remember-injury", "remember_about_user", ["note": "Bad left knee; cannot run"]),
        ]
        for (caseID, tool, input) in correct {
            let expect = try expectation(caseID)
            let called: Graders.ActionView
            do { called = try view(tool, input, user: expect.profile) } catch {
                XCTFail("\(caseID): the app rejected a correct \(tool) call: \(error)")
                continue
            }
            let graded = Graders.toolChoice(expect: expect, called: called, invalid: false)
            XCTAssertTrue(graded.pass, "\(caseID): a correct \(tool) call resolved to \(called.text) and did not pass \(graded.scores)")
        }
    }

    func testWrongCallsFailTheirCases() throws {
        // Right tool, wrong number.
        var expect = try expectation("water-2-bottles")
        var graded = Graders.toolChoice(expect: expect, called: try view("log_water", ["containers": 3]), invalid: false)
        XCTAssertFalse(graded.pass)
        XCTAssertEqual(graded.scores["tool_correct"], 1)
        XCTAssertEqual(graded.scores["arguments_correct"], 0)
        // Wrong tool.
        graded = Graders.toolChoice(expect: expect, called: try view("set_step_goal", ["steps": 9000]), invalid: false)
        XCTAssertEqual(graded.scores["tool_correct"], 0)
        XCTAssertEqual(graded.scores["decision_correct"], 1, "it was right to act, wrong about how")
        // Answered in prose when it should have acted.
        graded = Graders.toolChoice(expect: expect, called: nil, invalid: false)
        XCTAssertFalse(graded.pass)
        XCTAssertEqual(graded.scores["decision_correct"], 0)
        // A call the app rejects never passes.
        graded = Graders.toolChoice(expect: expect, called: nil, invalid: true)
        XCTAssertFalse(graded.pass)
        XCTAssertEqual(graded.scores["call_was_valid"], 0)

        // A question: prose passes, any action fails and is counted as acting when it should not.
        expect = try expectation("q-banana-calories")
        XCTAssertTrue(Graders.toolChoice(expect: expect, called: nil, invalid: false).pass)
        graded = Graders.toolChoice(expect: expect,
                                    called: try view("log_food", ["name": "Banana", "meal": "snack", "calories": 105,
                                                                  "protein_g": 1, "carbs_g": 27, "fat_g": 0]),
                                    invalid: false)
        XCTAssertFalse(graded.pass)
        XCTAssertEqual(graded.scores["acted_when_should_not"], 1)
    }

    // MARK: - Datasets are well formed

    func testMealDatasetDecodesAndIsSane() throws {
        let cases = try rows("meal_describe/v1.jsonl", as: Graders.MealTruth.self)
        XCTAssertEqual(cases.count, 14)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        for c in cases {
            // Atwater check on the truth itself: 4/4/9 should land near the stated calories.
            let atwater = 4 * c.protein_g + 4 * c.carbs_g + 9 * c.fat_g
            XCTAssertLessThan(Graders.absPctError(atwater, c.kcal), 0.12, "\(c.id): macros and calories disagree")
            XCTAssertTrue(c.source.contains("FDC "), "\(c.id) must cite its USDA record")
        }
    }

    /// `meal_describe/v3` is v1's cases plus the label nutrients of the same USDA records, built
    /// by `build_v3.py` from the `detail` blocks `fetch_usda.py` caches. This test holds the
    /// three files to one another in whichever state they are in:
    /// - no ingredient has cached detail yet (the USDA demo key was rate-limited): v3 must
    ///   not exist, because it could only hold made-up or missing columns;
    /// - the detail is cached: v3 must exist, repeat every v1 row exactly, and each new column
    ///   must be the arithmetic on the cached per-100 g values, or null where a record does
    ///   not list the nutrient.
    func testMealDatasetV3IsV1PlusTheLabelNutrientsOfTheSameRecords() throws {
        let directory = evalsRoot.appendingPathComponent("datasets/meal_describe")
        let cacheData = try Data(contentsOf: directory.appendingPathComponent("usda_cache.json"))
        let cache = try XCTUnwrap(JSONSerialization.jsonObject(with: cacheData) as? [String: [String: Any]])
        var per100g: [Int: [String: Double]] = [:]
        for entry in cache.values {
            guard let detail = entry["detail"] as? [String: Any], let id = detail["fdcId"] as? Int,
                  let values = detail["per100g"] as? [String: Any] else { continue }
            per100g[id] = values.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }

        func objects(_ name: String) throws -> [[String: Any]] {
            try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        }
        /// [(FDC id, grams)] from "FDC 173944 Bananas, raw x 118 g; FDC … x 32 g".
        func parts(_ source: String) throws -> [(id: Int, grams: Double)] {
            try source.components(separatedBy: "; ").map { part in
                let words = part.split(separator: " ")
                let id = try XCTUnwrap(words.count > 1 ? Int(words[1]) : nil, part)
                let grams = try XCTUnwrap(words.count > 2 ? Double(words[words.count - 2]) : nil, part)
                return (id, grams)
            }
        }

        let v1 = try objects("v1.jsonl")
        let needed = Set(try v1.flatMap { try parts(try XCTUnwrap($0["source"] as? String)).map(\.id) })
        let v3URL = directory.appendingPathComponent("v3.jsonl")
        let v3Exists = FileManager.default.fileExists(atPath: v3URL.path)

        guard needed.isSubset(of: Set(per100g.keys)) else {
            XCTAssertFalse(v3Exists, "v3.jsonl exists but usda_cache.json lacks the label nutrients it must be built from")
            return
        }
        XCTAssertTrue(v3Exists, "the label nutrients are cached: run Evals/datasets/meal_describe/build_v3.py")
        guard v3Exists else { return }

        let v3 = try objects("v3.jsonl")
        XCTAssertEqual(v3.count, v1.count)
        let columns: [(name: String, places: Double)] = [
            ("saturated_fat_g", 1), ("trans_fat_g", 1), ("cholesterol_mg", 1), ("sodium_mg", 1), ("fiber_g", 1),
            ("sugars_g", 1), ("added_sugars_g", 1), ("vitamin_d_mcg", 2), ("calcium_mg", 1), ("iron_mg", 1),
            ("potassium_mg", 1),
        ]
        XCTAssertEqual(Set(columns.map(\.name)), Set(Nutrient.allCases.map(\.argumentName)),
                       "one column per label nutrient, named like the app names it")
        let withheld = Self.withheldColumns
        for (old, new) in zip(v1, v3) {
            let id = (old["id"] as? String) ?? "?"
            for key in ["id", "description", "source"] {
                XCTAssertEqual(new[key] as? String, old[key] as? String, "\(id) \(key)")
            }
            for key in ["kcal", "protein_g", "carbs_g", "fat_g"] {
                XCTAssertEqual(new[key] as? Double, old[key] as? Double, "\(id) \(key): v3 repeats v1 exactly")
            }
            XCTAssertEqual(Set(new.keys), Set(old.keys).union(columns.map(\.name)), "\(id): v1's keys plus the eleven")
            let sourceParts = try parts(try XCTUnwrap(old["source"] as? String))
            for column in columns {
                var expected: Double? = 0
                for part in sourceParts {
                    guard let value = per100g[part.id]?[column.name],
                          !(withheld[part.id] ?? []).contains(column.name) else { expected = nil; break }
                    expected = (expected ?? 0) + value * part.grams / 100
                }
                if let expected {
                    let got = try XCTUnwrap(new[column.name] as? Double, "\(id) \(column.name) should be known")
                    XCTAssertEqual(got, expected, accuracy: 0.5 * pow(10, -column.places) + 1e-9, "\(id) \(column.name)")
                } else {
                    XCTAssertTrue(new[column.name] is NSNull,
                                  "\(id) \(column.name): a record does not list it, so it is null, never 0")
                }
            }
        }
        // And it decodes as the truth type the live evaluation loads.
        let typed = try rows("meal_describe/v3.jsonl", as: Graders.MealTruth.self)
        XCTAssertEqual(typed.map(\.id), try rows("meal_describe/v1.jsonl", as: Graders.MealTruth.self).map(\.id))
        for truth in typed {
            if let saturated = truth.saturated_fat_g { XCTAssertLessThanOrEqual(saturated, truth.fat_g + 0.2, truth.id) }
            if let fiber = truth.fiber_g, let sugars = truth.sugars_g {
                XCTAssertLessThanOrEqual(fiber + sugars, truth.carbs_g + 0.5, truth.id)
            }
            XCTAssertNil(truth.no_basis, "\(truth.id): every v3 portion is a named food in grams")
        }
    }

    /// The (record, column) pairs `build_v3.py` withholds, kept in step with its `WITHHELD`
    /// table: a value that is USDA's but does not describe the food the case names.
    private static let withheldColumns: [Int: [String]] = [
        // "Peanut butter, smooth style, without salt": the cases say "smooth peanut butter".
        172470: ["sodium_mg"],
    ]

    func testCoachDatasetDecodesAndUsesRealActionNames() throws {
        let cases = try rows("coach_tool_choice/v2.jsonl", as: Graders.ToolExpectation.self)
        XCTAssertEqual(cases.count, 34)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        let known: Set<String> = [
            "none", "stepGoal", "waterContainers", "pace", "logFood", "editFood", "deleteFood", "logWaterOz",
            "logWeight", "weightGoal", "startWeight", "rememberFact", "updatePlan", "logWorkout", "editPlan",
            "forgetFact", "setUnits", "setTheme", "setHomeGym", "setGoalDirection", "setHeight", "setBirthDate",
            "setSex", "setActivityLevel", "setCompanion", "setCoachName", "setWaterContainer", "setProteinGoal",
            "toggleStepsInBudget",
        ]
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.profile), c.id)
            XCTAssertFalse(c.kinds.isEmpty, c.id)
            XCTAssertTrue(Set(c.kinds).isSubset(of: known), "\(c.id) names an unknown action: \(c.kinds)")
        }
    }

    func testBriefDatasetTopicsMatchTheTemplateLadder() throws {
        let cases = try rows("daily_brief/v1.jsonl", as: LiveEvals.BriefCase.self)
        XCTAssertEqual(cases.count, 13)
        for c in cases {
            XCTAssertEqual(DailyBriefService.pick(c.signals).topic.rawValue, c.topic, c.id)
        }
        XCTAssertEqual(Set(cases.map(\.topic)), ["gapReturn", "travel", "milestone", "crossSignal", "quietDay", "checkIn"],
                       "every rung of the ladder is covered")
    }

    // MARK: - A whole live-eval attempt, on a scripted model

    func testLiveRunIsSkippedUnlessConfigured() {
        XCTAssertThrowsError(try EvalEnv.requireLive()) { XCTAssertTrue($0 is XCTSkip) }
    }

    // MARK: - Character image grader (the Avatar evaluation)

    func testAGoodCharacterPassesWithItsExactMetrics() {
        let png = TestImages.characterPNG(side: 1024)
        let m = Graders.imageMetrics(png)
        XCTAssertTrue(m.decodable)
        XCTAssertEqual(m.width, 1024)
        XCTAssertEqual(m.height, 1024)
        XCTAssertTrue(m.isSquare1024)
        XCTAssertTrue(m.hasAlpha)
        XCTAssertTrue(m.transparentTopCorners)
        XCTAssertFalse(m.transparentCorners, "the shoulders reach the bottom corners in this drawing")
        XCTAssertEqual(m.transparentShare, 24.0 / 64.0, accuracy: 0.0001, "24 of the 64 cells are clear")
        XCTAssertEqual(m.distinctColours, 5, "hair, skin, eyes, mouth, top")

        let graded = Graders.avatar(png)
        XCTAssertTrue(graded.pass)
        XCTAssertEqual(graded.scores["decodable"], 1)
        XCTAssertEqual(graded.scores["square_1024"], 1)
        XCTAssertEqual(graded.scores["has_alpha"], 1)
        XCTAssertEqual(graded.scores["transparent_top_corners"], 1)
        XCTAssertEqual(graded.scores["transparent_corners"], 0)
        XCTAssertEqual(graded.scores["distinct_colours"], 5)
        XCTAssertEqual(graded.scores["is_pixel_art"], 1)
    }

    func testAllFourCornersClearIsRecordedWhenTheDrawingLeavesThem() {
        let grid = ["....", ".HH.", ".SS.", "...."]
        let png = TestImages.png(width: 1024, height: 1024, grid: grid, palette: TestImages.characterPalette)
        let m = Graders.imageMetrics(png)
        XCTAssertTrue(m.transparentTopCorners)
        XCTAssertTrue(m.transparentCorners)
        XCTAssertEqual(m.transparentShare, 12.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(m.distinctColours, 2)
    }

    func testAPhotographFailsOnBackgroundAndPalette() throws {
        let jpeg = try XCTUnwrap(TestImages.spectrum(side: 1024).jpegData(compressionQuality: 0.9))
        let m = Graders.imageMetrics(jpeg)
        XCTAssertTrue(m.decodable)
        XCTAssertTrue(m.isSquare1024)
        XCTAssertFalse(m.hasAlpha)
        XCTAssertFalse(m.transparentTopCorners)
        XCTAssertEqual(m.transparentShare, 0)
        XCTAssertGreaterThan(m.distinctColours, 200, "a picture shaded in two directions has hundreds of colours")
        XCTAssertGreaterThan(m.distinctColours, Graders.pixelArtColourLimit)
        let graded = Graders.avatar(jpeg)
        XCTAssertFalse(graded.pass)
        XCTAssertEqual(graded.scores["is_pixel_art"], 0)
    }

    func testACharacterOnAPaintedBackgroundFails() {
        let painted = TestImages.png(width: 1024, height: 1024, grid: TestImages.characterGrid,
                                     palette: TestImages.characterPalette, background: .white)
        let graded = Graders.avatar(painted)
        XCTAssertEqual(graded.scores["has_alpha"], 1, "the channel is there; nothing in it is clear")
        XCTAssertEqual(graded.scores["transparent_top_corners"], 0)
        XCTAssertEqual(graded.scores["transparent_share"], 0)
        XCTAssertEqual(graded.scores["distinct_colours"], 6, "the five colours and the white backdrop")
        XCTAssertFalse(graded.pass)
    }

    func testTheWrongSizeFailsEvenWhenEverythingElseIsRight() {
        let small = TestImages.characterPNG(side: 512)
        let graded = Graders.avatar(small)
        XCTAssertEqual(graded.scores["square_1024"], 0)
        XCTAssertEqual(graded.scores["transparent_top_corners"], 1)
        XCTAssertEqual(graded.scores["is_pixel_art"], 1)
        XCTAssertFalse(graded.pass)

        let wide = TestImages.png(width: 1536, height: 1024, grid: TestImages.characterGrid,
                                  palette: TestImages.characterPalette)
        XCTAssertEqual(Graders.avatar(wide).scores["square_1024"], 0)
    }

    func testBytesThatAreNotAnImageScoreZeroEverywhere() {
        let graded = Graders.avatar(Data("definitely not a png".utf8))
        XCTAssertFalse(graded.pass)
        XCTAssertEqual(Graders.imageMetrics(Data("definitely not a png".utf8)), Graders.ImageMetrics())
        for (name, value) in graded.scores { XCTAssertEqual(value, 0, name) }
        XCTAssertEqual(graded.scores.count, 8)
    }

    func testColourCountMergesNearShadesAndIgnoresStrayPixels() throws {
        // Two close shades quantise to one colour; a third, real colour is counted.
        let palette: [Character: UIColor] = [
            "A": UIColor(red: 0.53, green: 0.2, blue: 0.2, alpha: 1),
            "B": UIColor(red: 0.54, green: 0.2, blue: 0.2, alpha: 1),
            "C": UIColor(red: 0.1, green: 0.8, blue: 0.3, alpha: 1),
        ]
        let merged = try XCTUnwrap(AvatarImage.rgba(ofImageData:
            TestImages.png(width: 100, height: 100, grid: ["AB", "CC"], palette: palette)))
        XCTAssertEqual(Graders.distinctColours(merged), 2)

        // One stray pixel of a new colour in 10,000 is under the share floor and not a palette entry.
        var stray = [String](repeating: String(repeating: "A", count: 100), count: 100)
        stray[50] = String(repeating: "A", count: 50) + "C" + String(repeating: "A", count: 49)
        let pixels = try XCTUnwrap(AvatarImage.rgba(ofImageData:
            TestImages.png(width: 100, height: 100, grid: stray, palette: palette)))
        XCTAssertEqual(Graders.distinctColours(pixels), 1)
        XCTAssertEqual(Graders.distinctColours(pixels, minShare: 0), 2, "with no floor the stray pixel counts")
    }

    func testAFullyTransparentImageHasNoColoursAndIsNotPixelArt() {
        let empty = TestImages.png(width: 1024, height: 1024)
        let m = Graders.imageMetrics(empty)
        XCTAssertEqual(m.transparentShare, 1)
        XCTAssertEqual(m.distinctColours, 0)
        XCTAssertFalse(Graders.avatar(empty).pass, "an empty picture is not a character")
    }

    // The image models do not return exact 0 and exact 255 (measured, EVAL_REPORT 23).

    func testACharacterAsTheImageModelsReturnItIsGradedAsOne() throws {
        let png = TestImages.characterPNGAsReturnedByAModel()
        let pixels = try XCTUnwrap(AvatarImage.rgba(ofImageData: png))
        XCTAssertEqual(pixels.alpha(x: 512, y: 300), 253, "the helper really writes a not-quite-solid pixel")
        XCTAssertFalse(pixels.bytes.enumerated().contains { $0.offset % 4 == 3 && $0.element == 255 },
                       "no pixel of it is at alpha 255")

        let m = Graders.imageMetrics(png)
        XCTAssertEqual(m.distinctColours, 5, "hair, skin, eyes, mouth, top: counted although none is at 255")
        XCTAssertTrue(m.transparentTopCorners, "a trace of alpha 1 or 2 in a corner cannot be seen")
        XCTAssertFalse(m.transparentCorners, "the shoulders still reach the bottom corners")
        XCTAssertLessThan(m.transparentShare, 24.0 / 64.0, "the app's own share counts exact 0 only")
        XCTAssertGreaterThan(m.transparentShare, 0.36)
        XCTAssertTrue(Graders.avatar(png).pass)
        XCTAssertNoThrow(try AvatarImage.validateCharacterPNG(png), "and the app accepts it")
    }

    func testTheAlphaTolerancesStopExactlyWhereTheySay() throws {
        func image(corner: UInt8, body: UInt8) -> Data {
            TestImages.png(width: 200, height: 200) { x, y in
                if x < 3, y < 3 { return (10, 10, 10, corner) }
                if (60..<140).contains(x), (60..<140).contains(y) { return (0x38, 0x78, 0xB8, body) }
                return (0, 0, 0, 0)
            }
        }
        XCTAssertTrue(Graders.imageMetrics(image(corner: Graders.clearAlphaCeiling, body: 255)).transparentTopCorners)
        XCTAssertFalse(Graders.imageMetrics(image(corner: Graders.clearAlphaCeiling + 1, body: 255)).transparentTopCorners,
                       "a mark that can be seen in a top corner still fails")
        XCTAssertEqual(Graders.imageMetrics(image(corner: 0, body: Graders.solidAlphaFloor)).distinctColours, 1)
        XCTAssertEqual(Graders.imageMetrics(image(corner: 0, body: Graders.solidAlphaFloor - 1)).distinctColours, 0,
                       "a see-through shape is not a solid colour, and an image of only that is not pixel art")
        XCTAssertFalse(Graders.avatar(image(corner: 0, body: 128)).pass)
    }

    func testThePixelArtLimitSitsInTheMeasuredGap() {
        // EVAL_REPORT 23: ten pixel characters counted 24 to 45, three photographs 72 to 81.
        XCTAssertGreaterThan(Graders.pixelArtColourLimit, 45)
        XCTAssertLessThan(Graders.pixelArtColourLimit, 72)
    }

    func testRegradeGradesEverySavedCharacterAndWritesOneRecord() throws {
        let run = FileManager.default.temporaryDirectory.appendingPathComponent("regrade-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: run) }
        let low = run.appendingPathComponent("avatars/gpt-image-2.6-flare@low")
        let medium = run.appendingPathComponent("avatars/gpt-image-2.6-flare@medium")
        try FileManager.default.createDirectory(at: low, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: medium, withIntermediateDirectories: true)
        try TestImages.characterPNGAsReturnedByAModel().write(to: low.appendingPathComponent("b-AAAA.png"))
        try TestImages.characterPNG(side: 512).write(to: low.appendingPathComponent("a-BBBB.png"))
        try Data("not a png".utf8).write(to: medium.appendingPathComponent("c-CCCC.png"))
        try Data([1]).write(to: medium.appendingPathComponent(".DS_Store"))

        let images = try LiveEvals.regradeAvatars(in: run)
        XCTAssertEqual(images.map(\.file), ["a-BBBB.png", "b-AAAA.png", "c-CCCC.png"])
        XCTAssertEqual(images.map(\.candidate), ["gpt-image-2.6-flare@low", "gpt-image-2.6-flare@low",
                                                 "gpt-image-2.6-flare@medium"])
        XCTAssertEqual(images.map(\.pass), [false, true, false], "wrong size, good, not an image")
        XCTAssertEqual(images[1].scores["distinct_colours"], 5)

        let written = try JSONSerialization.jsonObject(with:
            Data(contentsOf: run.appendingPathComponent("regrade-avatar.json"))) as? [String: Any]
        let graders = try XCTUnwrap(written?["graders"] as? [String: Any])
        XCTAssertEqual(graders["pixel_art_colour_limit"] as? Int, Graders.pixelArtColourLimit)
        XCTAssertEqual(graders["solid_alpha_floor"] as? Int, Int(Graders.solidAlphaFloor))
        XCTAssertEqual((written?["images"] as? [[String: Any]])?.count, 3)

        XCTAssertTrue(try LiveEvals.regradeAvatars(in: run.appendingPathComponent("missing")).isEmpty)
    }

    func testImageCostUsesTheThreeRatesAndNeverGuessesAModel() throws {
        let usage = AvatarGenerator.Usage(inputTokens: 1_210, inputTextTokens: 310, inputImageTokens: 900,
                                          outputTokens: 4_160, totalTokens: 5_370)
        // 310 x $5 + 900 x $8 + 4,160 x $30, per million.
        let flare = try XCTUnwrap(Graders.imageCostUSD(model: "gpt-image-2.6-flare", usage: usage))
        XCTAssertEqual(flare, 0.13355, accuracy: 0.0000001)
        XCTAssertNotNil(Graders.imageCostUSD(model: "gpt-image-2.6-sunburst", usage: usage))
        XCTAssertNil(Graders.imageCostUSD(model: "an-image-model-with-no-rates", usage: usage))

        // Input the response does not break down is priced at the dearer (image) rate.
        let lump = AvatarGenerator.Usage(inputTokens: 1_000, inputTextTokens: 0, inputImageTokens: 0,
                                         outputTokens: 0, totalTokens: 1_000)
        XCTAssertEqual(try XCTUnwrap(Graders.imageCostUSD(model: "gpt-image-2.6-flare", usage: lump)), 0.008,
                       accuracy: 0.0000001)
    }

    // MARK: - The Avatar evaluation's own plumbing

    func testAvatarCasesAreThePhotosOfTheFolderInNameOrder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-cases-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["b-glasses.jpg", "a-long-hair.PNG", "README.md", "notes.txt", ".DS_Store", "c.heic"] {
            try Data([1]).write(to: folder.appendingPathComponent(name))
        }
        XCTAssertEqual(LiveEvals.avatarCases(in: folder).map(\.id), ["a-long-hair", "b-glasses", "c"])
        XCTAssertEqual(LiveEvals.avatarCases(in: folder, limit: 2).map(\.id), ["a-long-hair", "b-glasses"])
        XCTAssertEqual(LiveEvals.avatarCases(in: folder).first?.url.lastPathComponent, "a-long-hair.PNG")
        XCTAssertTrue(LiveEvals.avatarCases(in: folder.appendingPathComponent("missing")).isEmpty)
    }

    func testAvatarOutcomeRecordsScoresUsageCostAndSavesTheImage() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-out-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let png = TestImages.characterPNG(side: 1024)
        let character = AvatarGenerator.Character(
            png: png, pixelSize: 1024, model: "gpt-image-2.6-flare", quality: "low", promptVersion: "avatar-v1",
            usage: .init(inputTokens: 1_210, inputTextTokens: 310, inputImageTokens: 900, outputTokens: 4_160,
                         totalTokens: 5_370),
            latencyMs: 41_500)
        let outcome = LiveEvals.avatarOutcome(character, caseID: "a-long-hair", out: out)
        XCTAssertTrue(outcome.ok)
        XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.scores["generator_accepted"], 1)
        XCTAssertEqual(outcome.scores["generation_latency_ms"], 41_500)
        XCTAssertEqual(outcome.scores["input_text_tokens"], 310)
        XCTAssertEqual(outcome.scores["input_image_tokens"], 900)
        XCTAssertEqual(outcome.scores["output_tokens"], 4_160)
        XCTAssertEqual(try XCTUnwrap(outcome.scores["cost_usd"]), 0.13355, accuracy: 0.0000001)
        XCTAssertEqual(outcome.scores["distinct_colours"], 5)

        let folder = out.appendingPathComponent("avatars/gpt-image-2.6-flare@low")
        let saved = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(try XCTUnwrap(saved.first).hasPrefix("a-long-hair-"))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(try XCTUnwrap(saved.first))), png)
        XCTAssertTrue(outcome.output.hasPrefix("gpt-image-2.6-flare low avatar-v1 avatars/gpt-image-2.6-flare@low/a-long-hair-"),
                      outcome.output)

        // Without usage there is no cost: never an estimate.
        var bare = character
        bare.usage = nil
        let noUsage = LiveEvals.avatarOutcome(bare, caseID: "x", out: nil)
        XCTAssertNil(noUsage.scores["cost_usd"])
        XCTAssertNil(noUsage.scores["output_tokens"])
        XCTAssertTrue(noUsage.output.hasSuffix("not saved"))
    }

    func testThePhotoFolderHasItsReadmeAndIsKeptOutOfGit() throws {
        let readme = try String(contentsOf: evalsRoot.appendingPathComponent("datasets/avatar/photos/README.md"),
                                encoding: .utf8)
        XCTAssertTrue(readme.contains("Synthetic"))
        XCTAssertTrue(readme.contains("Consented"))
        let ignore = try String(contentsOf: evalsRoot.deletingLastPathComponent().appendingPathComponent(".gitignore"),
                                encoding: .utf8)
        for rule in ["Evals/datasets/avatar/photos/*", "!Evals/datasets/avatar/photos/README.md", "Evals/runs/*/avatars/"] {
            XCTAssertTrue(ignore.split(separator: "\n").contains(Substring(rule)), "missing .gitignore rule: \(rule)")
        }
    }

    // MARK: - The eight wording and structure evaluations: shared pieces

    private let alex = Graders.Reader(name: "Alex", isWoman: false, isMan: true)
    private let sam = Graders.Reader(name: "Sam", isWoman: true, isMan: false)

    private func textReply(_ text: String) -> ScriptedTransport.Reply {
        .json(200, ["content": [["type": "text", "text": text]], "usage": ["input_tokens": 10, "output_tokens": 10]])
    }

    private func toolReply(_ input: [String: Any]) -> ScriptedTransport.Reply {
        .json(200, ["content": [["type": "tool_use", "id": "tu_1", "name": "tool", "input": input]],
                    "usage": ["input_tokens": 10, "output_tokens": 10]])
    }

    private let serverError: ScriptedTransport.Reply = .json(500, ["error": ["message": "boom"]])

    /// Runs `call` against a scripted model, the way an evaluation attempt runs against a real one.
    private func scripted<T>(_ replies: [ScriptedTransport.Reply], provider: AIProvider = .anthropic,
                             model: String? = nil, _ call: () async -> T) async -> T {
        let runtime = AIRuntime(provider: provider, apiKey: "test-key-not-real", model: model,
                                transport: ScriptedTransport(replies))
        return await AIRuntime.$current.withValue(runtime) { await call() }
    }

    /// Runs `call` as the app runs with no key stored, and counts the requests it made.
    private func withNoKey<T>(_ call: () async -> T) async -> (result: T, requests: Int) {
        let transport = ScriptedTransport([])
        let runtime = AIRuntime(provider: .anthropic, apiKey: "", transport: transport)
        let result = await AIRuntime.$current.withValue(runtime) { await call() }
        return (result, transport.requests.count)
    }

    private func isMissingKey(_ error: Error?) -> Bool {
        if case .missingKey? = error as? AIConfig.AIError { return true }
        return false
    }

    private func words(_ count: Int) -> String { Array(repeating: "word", count: count).joined(separator: " ") }
    private func sentences(_ count: Int) -> String { Array(repeating: "You showed up.", count: count).joined(separator: " ") }

    // MARK: - The recorder that keeps a reply the app discards

    func testModelOutputIsReadFromEveryWireFormat() throws {
        func output(_ object: [String: Any]) throws -> (text: String?, failure: String?) {
            EvalRunner.modelOutput(inResponse: try JSONSerialization.data(withJSONObject: object))
        }
        // Anthropic Messages: text blocks, and a tool call as the JSON of its input.
        XCTAssertEqual(try output(["content": [["type": "text", "text": "Hello."]]]).text, "Hello.")
        XCTAssertEqual(try output(["content": [["type": "tool_use", "id": "t", "name": "n", "input": ["prompts": ["a"]]]]]).text,
                       #"{"prompts":["a"]}"#)
        // OpenAI Responses: a message item, and a function call's argument string.
        XCTAssertEqual(try output(["output": [["type": "message", "content": [["type": "output_text", "text": "Hi there."]]]]]).text,
                       "Hi there.")
        XCTAssertEqual(try output(["output": [["type": "function_call", "name": "n", "arguments": #"{"a":1}"#]]]).text, #"{"a":1}"#)
        XCTAssertEqual(try output(["output": [], "output_text": "Plain."]).text, "Plain.")
        // A model's reasoning is not its reply.
        XCTAssertEqual(try output(["output": [["type": "reasoning", "content": [["type": "reasoning_text", "text": "Hmm."]]],
                                              ["type": "message", "content": [["type": "output_text", "text": "Done."]]]]]).text, "Done.")
        XCTAssertEqual(try output(["content": [["type": "thinking", "thinking": "Hmm.", "text": "Hmm."],
                                               ["type": "text", "text": "Done."]]]).text, "Done.")
        // OpenAI Chat Completions: the message content, and a tool call's argument string.
        XCTAssertEqual(try output(["choices": [["message": ["role": "assistant", "content": "Chat."]]]]).text, "Chat.")
        XCTAssertEqual(try output(["choices": [["message": ["tool_calls": [["function": ["name": "n", "arguments": #"{"b":2}"#]]]]]]]).text,
                       #"{"b":2}"#)
        // An error body has no reply, and its message is kept.
        let failed = try output(["error": ["message": "tool_choice is not supported"]])
        XCTAssertNil(failed.text)
        XCTAssertEqual(failed.failure, "tool_choice is not supported")
        XCTAssertNil(EvalRunner.modelOutput(inResponse: Data("not json".utf8)).text)
        XCTAssertEqual(EvalRunner.jsonObject(#"{"prompts":["a","b"]}"#)?["prompts"] as? [String], ["a", "b"])
        XCTAssertNil(EvalRunner.jsonObject("Hello."))
        XCTAssertNil(EvalRunner.jsonObject(nil))
    }

    func testRecordingKeepsTheReplyTheAppThrowsAway() async {
        // Used: the app's result and the reply are both in hand.
        var tap = await scripted([textReply("You're on a roll!")]) {
            await EvalRunner.recording { await InsightPhraser.rephrase(template: "t", factualHint: "h") }
        }
        XCTAssertEqual(tap.value ?? nil, "You're on a roll!")
        XCTAssertEqual(tap.raw, "You're on a roll!")
        // Discarded by the sanitiser: the app returns nil, the reply is still recorded.
        tap = await scripted([textReply("No need to cut back today!")]) {
            await EvalRunner.recording { await InsightPhraser.rephrase(template: "t", factualHint: "h") }
        }
        XCTAssertNil(tap.value ?? nil)
        XCTAssertEqual(tap.raw, "No need to cut back today!")
        // A failed call: no reply, and the provider's message.
        tap = await scripted([serverError]) {
            await EvalRunner.recording { await InsightPhraser.rephrase(template: "t", factualHint: "h") }
        }
        XCTAssertNil(tap.value ?? nil)
        XCTAssertNil(tap.raw)
        XCTAssertEqual(tap.failure, "boom")
        // A thrown error is a failure result, with the reply that caused it.
        let thrown = await scripted([toolReply(["headline": "Only a headline"])]) {
            await EvalRunner.recording { try await ProgressSummaryService.summary(snapshot: "Current logging streak: 4 day(s)") }
        }
        XCTAssertNil(thrown.value)
        XCTAssertEqual(thrown.raw, #"{"headline":"Only a headline"}"#)
        // The runtime in force keeps reporting usage through the wrapped transport.
        let usage = UsageRecorder()
        let runtime = AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", model: "pinned-model",
                                transport: ScriptedTransport([textReply("Hi.")]), onUsage: { usage.record($0) })
        _ = await AIRuntime.$current.withValue(runtime) {
            await EvalRunner.recording { await InsightPhraser.rephrase(template: "t", factualHint: "h") }
        }
        XCTAssertEqual(usage.all.count, 1)
    }

    /// The same attempts through the OpenAI client, on both of its wire paths: a model on
    /// the Responses API and one on Chat Completions. The reply is kept on each.
    func testRecordingReadsBothOpenAIWirePaths() async throws {
        let streak = try XCTUnwrap(try rows("insight_line/v1.jsonl", as: LiveEvals.InsightCase.self).first { $0.id == "protein-streak-4" })
        let progress = try XCTUnwrap(try rows("progress_summary/v1.jsonl", as: LiveEvals.ProgressCase.self).first { $0.id == "sam-on-track" })
        let recap = #"{"headline":"Steady and on track","body":"Your trend is 156.4 lb. Protein landed on 5 of 7 days.","highlights":["21-day logging streak","Protein on 5 of 7 days"]}"#
        func responsesText(_ text: String) -> ScriptedTransport.Reply {
            .json(200, ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]],
                        "usage": ["input_tokens": 10, "output_tokens": 10]])
        }
        func responsesCall(_ arguments: String) -> ScriptedTransport.Reply {
            .json(200, ["status": "completed", "output": [["type": "reasoning", "summary": []],
                                                          ["type": "function_call", "call_id": "c1", "name": "write_summary", "arguments": arguments]]])
        }
        func chatText(_ text: String) -> ScriptedTransport.Reply {
            .json(200, ["choices": [["message": ["role": "assistant", "content": text], "finish_reason": "stop"]]])
        }
        func chatCall(_ arguments: String) -> ScriptedTransport.Reply {
            .json(200, ["choices": [["message": ["role": "assistant", "tool_calls": [["id": "c1", "type": "function",
                                                 "function": ["name": "write_summary", "arguments": arguments]]]],
                                     "finish_reason": "tool_calls"]]])
        }
        XCTAssertTrue(OpenAIClient.usesResponsesAPI("gpt-6-luna"))
        XCTAssertFalse(OpenAIClient.usesResponsesAPI("gpt-4.1-mini"))
        for (model, text, call) in [("gpt-6-luna", responsesText, responsesCall), ("gpt-4.1-mini", chatText, chatCall)] {
            var outcome = await scripted([text("4 days of protein in a row, nice!")], provider: .openai, model: model) {
                await LiveEvals.insightAttempt(streak)
            }
            XCTAssertTrue(outcome.pass, model)
            outcome = await scripted([text("4 days of protein, no need to cut back!")], provider: .openai, model: model) {
                await LiveEvals.insightAttempt(streak)
            }
            XCTAssertFalse(outcome.ok, model)
            XCTAssertEqual(outcome.output, "4 days of protein, no need to cut back!", model)

            outcome = await scripted([call(recap)], provider: .openai, model: model) { await LiveEvals.progressAttempt(progress) }
            XCTAssertTrue(outcome.ok, model); XCTAssertTrue(outcome.pass, model)
            outcome = await scripted([call(#"{"headline":"Only a headline"}"#)], provider: .openai, model: model) {
                await LiveEvals.progressAttempt(progress)
            }
            XCTAssertFalse(outcome.ok, model)
            XCTAssertEqual(outcome.output, #"{"headline":"Only a headline"}"#, model)
            outcome = await scripted([.json(400, ["error": ["message": "bad request"]])], provider: .openai, model: model) {
                await LiveEvals.insightAttempt(streak)
            }
            XCTAssertEqual(outcome.error, "the call failed: bad request", model)
        }
    }

    func testNotUsedSaysWhichAndKeepsTheReply() {
        let discarded = EvalOutcome.notUsed(raw: "Aim for 1600 calories.", failure: nil, discardedBy: "the sanitiser")
        XCTAssertFalse(discarded.ok); XCTAssertFalse(discarded.pass)
        XCTAssertEqual(discarded.error, "the sanitiser discarded the reply")
        XCTAssertEqual(discarded.output, "Aim for 1600 calories.")
        XCTAssertEqual(discarded.scores, ["used": 0])
        let failed = EvalOutcome.notUsed(raw: nil, failure: "boom", discardedBy: "the sanitiser")
        XCTAssertEqual(failed.error, "the call failed: boom")
        XCTAssertEqual(failed.output, "")
    }

    // MARK: - Text checks

    func testWrongPersonPronounIsAboutTheReader() {
        XCTAssertTrue(Graders.containsMasculinePronoun("He showed up again."))
        XCTAssertTrue(Graders.containsMasculinePronoun("Proud of his streak, and of him."))
        XCTAssertFalse(Graders.containsMasculinePronoun("This is the theme: history, hills and chimes."))
        XCTAssertTrue(Graders.wrongPersonPronoun("She is on a roll.", reader: alex))
        XCTAssertFalse(Graders.wrongPersonPronoun("He is on a roll.", reader: alex))
        XCTAssertTrue(Graders.wrongPersonPronoun("He is on a roll.", reader: sam))
        XCTAssertFalse(Graders.wrongPersonPronoun("She is on a roll.", reader: sam))
        XCTAssertFalse(Graders.wrongPersonPronoun("You are on a roll.", reader: alex))
        // A reader who is neither: both are wrong.
        let unknown = Graders.Reader(name: "", isWoman: false, isMan: false)
        XCTAssertTrue(Graders.wrongPersonPronoun("her streak", reader: unknown))
        XCTAssertTrue(Graders.wrongPersonPronoun("his streak", reader: unknown))
        XCTAssertEqual(EvalFixtures.reader("gain"), alex)
        XCTAssertEqual(EvalFixtures.reader("loss"), sam)
        XCTAssertEqual(EvalFixtures.reader("loss", name: "").name, "")
        XCTAssertEqual(EvalFixtures.direction("gain"), .gain)
        XCTAssertEqual(EvalFixtures.direction("loss"), .lose)
        XCTAssertEqual(EvalFixtures.direction("loss", override: "maintain"), .maintain)
        XCTAssertNil(EvalFixtures.direction("gain", override: "unknown"))
    }

    func testWordsEmojiPhrasesAndStems() {
        XCTAssertEqual(Graders.wordCount("🔥 21-day logging streak"), 3, "an emoji alone is not a word")
        XCTAssertEqual(Graders.wordCount("  Steady   and — on track  "), 4)
        XCTAssertEqual(Graders.wordCount(""), 0)
        XCTAssertEqual(Graders.emojiCount("No emoji, 3 digits: 1 2 3 #"), 0, "digits and # are not emoji")
        XCTAssertEqual(Graders.emojiCount("Proud of you 💛"), 1)
        XCTAssertEqual(Graders.emojiCount("❤️ and 💪🏽 and 🇺🇸"), 3, "a variation selector, a skin tone and a flag are one each")

        XCTAssertTrue(Graders.containsPhrase("Not bad at all!", "bad"))
        XCTAssertFalse(Graders.containsPhrase("You earned a badge.", "bad"))
        XCTAssertTrue(Graders.containsPhrase("You SHOULDN'T worry.", "should"))
        XCTAssertFalse(Graders.containsPhrase("Square your shoulders.", "should"))
        XCTAssertTrue(Graders.containsPhrase("Time to cut back.", "cut back"))
        XCTAssertEqual(Graders.phrases(in: "Too much? No rush.", from: ["too much", "no rush", "cheat"]), ["too much", "no rush"])

        XCTAssertTrue(Graders.mentions("Allergic to PEANUTS.", "peanut"))
        XCTAssertTrue(Graders.mentions("Two eggs", "egg"))
        XCTAssertFalse(Graders.mentions("Likes veggies", "egg"), "a keyword must begin a word")
        XCTAssertFalse(Graders.mentions("Strength training", "rain"))
        XCTAssertTrue(Graders.mentions("Starts at 4am.", "4am"))

        XCTAssertEqual(Graders.numbersNotGiven(in: "5 of 7 days, then twelve more", given: "on 5 of 7 logged day(s)"), [12])
        XCTAssertEqual(Graders.numbersNotGiven(in: "1,640 a day", given: "this week: 1640"), [])
        XCTAssertTrue(Graders.hasListOrHeader("Great week.\n- logged six days"))
        XCTAssertTrue(Graders.hasListOrHeader("# Your week"))
        XCTAssertFalse(Graders.hasListOrHeader("Great week - really.\nKeep going."))

        XCTAssertEqual(Graders.itemBounds(ProgressSummaryService.schema, "highlights"), 2...4)
        XCTAssertEqual(Graders.itemBounds(FoodSuggestionService.schema, "suggestions"), 2...3)
        XCTAssertEqual(Graders.itemBounds(CoachPromptService.schema, "prompts"), 2...5)
        XCTAssertEqual(Graders.itemBounds(ChecklistPlanService.schema, "tasks"), 3...5)
        XCTAssertEqual(Graders.itemBounds(ChecklistPlanService.schema, "chips"), 4...8)
        XCTAssertNil(Graders.itemBounds(ChecklistPlanService.schema, "missing"))
    }

    // MARK: - insightLine

    private let streakTemplate = "4 days of hitting your protein in a row — your body is getting exactly what it needs. 🌟"
    private let streakHint = "The user hit the protein goal 4 days in a row — celebrate this streak."

    func testInsightLineGraderPassRule() {
        func grade(_ line: String, _ reader: Graders.Reader? = nil) -> (scores: [String: Double], pass: Bool) {
            Graders.insightLine(template: streakTemplate, hint: streakHint, line: line, reader: reader ?? alex)
        }
        let good = grade("Four days of protein in a row, you're on a roll! 🌟")
        XCTAssertTrue(good.pass)
        XCTAssertEqual(good.scores, ["used": 1, "all_numbers_kept": 1, "no_number_invented": 1, "wrong_person_pronoun": 0,
                                     "one_sentence": 1, "at_most_22_words": 1, "at_most_one_emoji": 1, "no_hashtag": 1,
                                     "changed_the_wording": 1])
        // Every number kept.
        let dropped = grade("You're on a real protein roll!")
        XCTAssertFalse(dropped.pass); XCTAssertEqual(dropped.scores["all_numbers_kept"], 0)
        // None invented.
        let invented = grade("4 days of protein, now go for 10!")
        XCTAssertFalse(invented.pass); XCTAssertEqual(invented.scores["no_number_invented"], 0)
        // The right person, both ways round.
        XCTAssertFalse(grade("4 days in a row, she is on a roll!").pass)
        XCTAssertTrue(grade("4 days in a row, she is on a roll!", sam).pass)
        XCTAssertFalse(grade("4 days in a row, he is on a roll!", sam).pass)
        XCTAssertTrue(grade("4 days in a row, he is on a roll!").pass)
        XCTAssertEqual(grade("4 days in a row, she is on a roll!").scores["wrong_person_pronoun"], 1)

        // A number the observation gave, though the template does not show it, is not invented.
        let away = Graders.insightLine(template: "Welcome back 💛 Today's a fresh start.",
                                       hint: "The user logged again today after 14 days away.",
                                       line: "Fourteen days away and you came back, that's the hard part!", reader: sam)
        XCTAssertTrue(away.pass)
        XCTAssertFalse(Graders.insightLine(template: "Welcome back 💛 Today's a fresh start.",
                                           hint: "The user logged again today after 14 days away.",
                                           line: "Three weeks away and you came back!", reader: sam).pass)
    }

    func testInsightLineGraderScoresDoNotDecideThePass() {
        func grade(_ line: String) -> (scores: [String: Double], pass: Bool) {
            Graders.insightLine(template: streakTemplate, hint: streakHint, line: line, reader: alex)
        }
        let two = grade("4 days in a row. Keep it going!")
        XCTAssertTrue(two.pass); XCTAssertEqual(two.scores["one_sentence"], 0)
        // 22 words is the stated limit: 22 scores, 23 does not.
        XCTAssertEqual(grade("4 " + words(21)).scores["at_most_22_words"], 1)
        XCTAssertEqual(grade("4 " + words(22)).scores["at_most_22_words"], 0)
        XCTAssertTrue(grade("4 " + words(22)).pass)
        XCTAssertEqual(grade("4 days in a row 💪").scores["at_most_one_emoji"], 1)
        XCTAssertEqual(grade("4 days in a row 💪🌟").scores["at_most_one_emoji"], 0)
        XCTAssertEqual(grade("4 days in a row #streak").scores["no_hashtag"], 0)
        XCTAssertEqual(grade(streakTemplate).scores["changed_the_wording"], 0)
        XCTAssertTrue(grade(streakTemplate).pass, "the template is itself a correct line")
    }

    func testInsightDatasetMapsOntoTheEngineAndTheTemplateItFallsBackTo() async throws {
        let cases = try rows("insight_line/v1.jsonl", as: LiveEvals.InsightCase.self)
        XCTAssertEqual(cases.count, 19)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.user), c.id)
            let chosen = try XCTUnwrap(c.chosen, "\(c.id): the engine has nothing to say for this day")
            XCTAssertEqual(chosen.insight.id, c.insight, c.id)
            XCTAssertEqual(Set(Graders.numbers(in: chosen.insight.template)), Set(c.keep), "\(c.id): keep is the template's numbers")
            // With no key the card keeps the template, and makes no request.
            let shown = await withNoKey { await InsightPhraser.phrase(template: chosen.insight.template, factualHint: chosen.hint) }
            XCTAssertEqual(shown.result, chosen.insight.template, c.id)
            XCTAssertEqual(shown.requests, 0, c.id)
            XCTAssertTrue(Graders.insightLine(template: chosen.insight.template, hint: chosen.hint,
                                              line: chosen.insight.template, reader: c.reader).pass,
                          "\(c.id): the template must pass its own case")
        }
        XCTAssertEqual(Set(cases.map(\.insight)),
                       ["welcome_back", "fuel_up", "protein_hit", "protein_streak", "well_fueled", "hydrated",
                        "hydration_streak", "streak_week", "streak_3", "moved", "steps_goal", "gentle_default"],
                       "every insight the engine can choose is covered")
        XCTAssertEqual(cases.filter { $0.user == "gain" }.count, 10)
        XCTAssertEqual(cases.filter { $0.user == "loss" }.count, 9)
        // The line whose wording depends on the goal is covered for every direction, and for none.
        let fueled = Set(cases.filter { $0.insight == "well_fueled" }.compactMap { $0.chosen?.insight.template })
        XCTAssertEqual(fueled.count, 4)
    }

    func testInsightAttemptOnAScriptedModel() async throws {
        let cases = try rows("insight_line/v1.jsonl", as: LiveEvals.InsightCase.self)
        let streak = try XCTUnwrap(cases.first { $0.id == "protein-streak-4" })

        var outcome = await scripted([textReply("\"Four days of protein in a row, you're on a roll!\"")]) {
            await LiveEvals.insightAttempt(streak)
        }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.output, "Four days of protein in a row, you're on a roll!", "graded as the app shows it")

        outcome = await scripted([textReply("A whole week of protein, amazing!")]) { await LiveEvals.insightAttempt(streak) }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass, "used, but the 4 is gone")

        // The sanitiser's own rules decide "used": a banned phrase, and the 180-character limit.
        outcome = await scripted([textReply("4 days of protein, no need to cut back now!")]) { await LiveEvals.insightAttempt(streak) }
        XCTAssertFalse(outcome.ok); XCTAssertFalse(outcome.pass)
        XCTAssertEqual(outcome.scores, ["used": 0])
        XCTAssertEqual(outcome.error, "the sanitiser discarded the reply")
        XCTAssertEqual(outcome.output, "4 days of protein, no need to cut back now!", "the discarded reply is kept")
        let atLimit = "4 " + String(repeating: "a", count: 178)
        outcome = await scripted([textReply(atLimit)]) { await LiveEvals.insightAttempt(streak) }
        XCTAssertTrue(outcome.ok, "180 characters is kept")
        outcome = await scripted([textReply(atLimit + "a")]) { await LiveEvals.insightAttempt(streak) }
        XCTAssertFalse(outcome.ok, "181 characters is discarded")

        outcome = await scripted([serverError]) { await LiveEvals.insightAttempt(streak) }
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.error, "the call failed: boom")
    }

    // MARK: - weeklyReflection

    private func week(note: String = "", name: String = "Alex") -> WeeklyReflection.Inputs {
        WeeklyReflection.Inputs(name: name, direction: .gain, note: note, daysLogged: 6, ateEnoughDays: 3,
                                proteinGoalDays: 4, waterGoalDays: 0, stepGoalDays: 0, workoutDays: 3, trend: .climbing)
    }

    func testWeeklyReflectionGraderPassRule() {
        func grade(_ text: String, note: String = "", reader: Graders.Reader? = nil) -> (scores: [String: Double], pass: Bool) {
            let inputs = week(note: note)
            return Graders.weeklyReflection(given: WeeklyReflection.userPrompt(inputs), counts: [6, 3, 4, 0, 0, 3],
                                            name: inputs.name, text: text, reader: reader ?? alex)
        }
        let good = grade("Alex, you showed up six of seven days this week. Protein landed on four of them. "
                         + "That is the work paying off 💪 Next week builds on this one.")
        XCTAssertTrue(good.pass)
        XCTAssertEqual(good.scores, ["used": 1, "no_number_invented": 1, "wrong_person_pronoun": 0,
                                     "three_to_five_sentences": 1, "at_most_one_emoji": 1, "no_list_or_header": 1,
                                     "name_used_once": 1, "repeats_a_given_count": 1])
        // A count that is not one of the given ones.
        let invented = grade("Alex, you trained on five days. That is strong. Keep going.")
        XCTAssertFalse(invented.pass); XCTAssertEqual(invented.scores["no_number_invented"], 0)
        // A number from the person's own note is given.
        XCTAssertTrue(grade("Alex, that ten-kilometre race is getting closer. You trained three days. Keep going.",
                            note: "Training for a ten-kilometre race.").pass)
        XCTAssertFalse(grade("Alex, that ten-kilometre race is getting closer. You trained three days. Keep going.").pass)
        // The right person.
        XCTAssertFalse(grade("Alex logged six days. She trained on three. Proud of that.").pass)
        XCTAssertTrue(grade("Sam logged six days. She trained on three. Proud of that.", reader: sam).pass)
        XCTAssertFalse(grade("Sam logged six days. He trained on three. Proud of that.", reader: sam).pass)
    }

    func testWeeklyReflectionGraderScores() {
        func scores(_ text: String, name: String = "Alex") -> [String: Double] {
            Graders.weeklyReflection(given: WeeklyReflection.userPrompt(week(name: name)), counts: [6, 3, 4, 0, 0, 3],
                                     name: name, text: text, reader: alex).scores
        }
        // Three to five sentences, at each edge.
        XCTAssertEqual(scores(sentences(2))["three_to_five_sentences"], 0)
        XCTAssertEqual(scores(sentences(3))["three_to_five_sentences"], 1)
        XCTAssertEqual(scores(sentences(5))["three_to_five_sentences"], 1)
        XCTAssertEqual(scores(sentences(6))["three_to_five_sentences"], 0)
        // The name once: not zero times, not twice.
        XCTAssertEqual(scores("You showed up. Keep going. Proud of you.")["name_used_once"], 0)
        XCTAssertEqual(scores("Alex, you showed up. Keep going. Proud of you.")["name_used_once"], 1)
        XCTAssertEqual(scores("Alex, you showed up. Keep going, Alex. Proud of you.")["name_used_once"], 0)
        XCTAssertNil(scores("You showed up.", name: "")["name_used_once"], "no name given, nothing to score")
        XCTAssertEqual(scores("Proud of you 💛")["at_most_one_emoji"], 1)
        XCTAssertEqual(scores("Proud of you 💛💪")["at_most_one_emoji"], 0)
        XCTAssertEqual(scores("Your week:\n- six days logged")["no_list_or_header"], 0)
        XCTAssertEqual(scores("You showed up. Keep going.")["repeats_a_given_count"], 0)
        XCTAssertEqual(scores("You logged six days.")["repeats_a_given_count"], 1)
        // None of these decides the pass.
        XCTAssertTrue(Graders.weeklyReflection(given: WeeklyReflection.userPrompt(week()), counts: [6, 3, 4, 0, 0, 3],
                                               name: "Alex", text: "Great.\n- you showed up 💛💪", reader: alex).pass)
    }

    func testWeeklyDatasetMapsOntoTheInputsAndTheTemplateItFallsBackTo() async throws {
        let cases = try rows("weekly_reflection/v1.jsonl", as: LiveEvals.WeeklyCase.self)
        XCTAssertEqual(cases.count, 16)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        let leads = ["consistency": "showed up almost every day", "fueled": "fueled yourself well on",
                     "protein": "reached your protein on", "moved": "moved your body",
                     "checkedIn": "you checked in this week", "freshPage": "a fresh week is a fresh page"]
        var branches = Set<String>()
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.user), c.id)
            let inputs = try XCTUnwrap(c.inputs, "\(c.id) does not map onto WeeklyReflection.Inputs")
            XCTAssertEqual(inputs.name, c.user == "gain" ? "Alex" : "Sam")
            for count in c.counts {
                XCTAssertTrue((0...7).contains(count), c.id)
                XCTAssertLessThanOrEqual(count, c.daysLogged, "\(c.id): a goal day is a logged day")
            }
            // With no key the card shows the template, and makes no request.
            let template = WeeklyReflection.template(for: inputs)
            let shown = await withNoKey { await WeeklyReflection.make(inputs) }
            XCTAssertEqual(shown.result, template, c.id)
            XCTAssertEqual(shown.requests, 0, c.id)
            XCTAssertTrue(template.contains(try XCTUnwrap(leads[c.lead], "\(c.id): unknown lead \(c.lead)")),
                          "\(c.id): the template does not open with the \(c.lead) lead")
            XCTAssertEqual(WeeklyReflection.sanitize(template), template, "\(c.id): the template passes the app's sanitiser")
            XCTAssertTrue(Graders.weeklyReflection(given: WeeklyReflection.userPrompt(inputs), counts: c.counts,
                                                   name: inputs.name, text: template, reader: c.reader).pass,
                          "\(c.id): the template must pass its own case")
            branches.insert("\(inputs.direction)/\(c.trend)")
        }
        XCTAssertEqual(Set(cases.map(\.lead)), Set(leads.keys), "every opening of the template is covered")
        // Every pairing of goal and trend that the prompt and the template word differently.
        XCTAssertEqual(branches, ["lose/easingDown", "lose/droppingFast", "lose/steady", "lose/climbing", "lose/notEnoughData",
                                  "gain/climbing", "gain/easingDown", "gain/droppingFast", "gain/steady", "gain/notEnoughData",
                                  "maintain/steady", "maintain/easingDown", "maintain/climbing"])
        XCTAssertEqual(cases.filter { $0.user == "gain" }.count, 7)
        XCTAssertEqual(cases.filter { $0.user == "loss" }.count, 9)
        XCTAssertTrue(cases.contains { $0.note.isEmpty } && cases.contains { !$0.note.isEmpty })
    }

    func testWeeklyAttemptOnAScriptedModel() async throws {
        let cases = try rows("weekly_reflection/v1.jsonl", as: LiveEvals.WeeklyCase.self)
        let item = try XCTUnwrap(cases.first { $0.id == "alex-climbing-consistent" })
        let good = "Alex, you showed up all seven days this week. Protein landed on six of them. "
            + "Your trend is climbing, right where you want it. Next week builds on this."
        var outcome = await scripted([textReply(good)]) { await LiveEvals.weeklyAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.output, good)

        // A digit, a banned phrase, and the 900-character limit are the sanitiser's.
        outcome = await scripted([textReply("Alex, try for 3000 calories next week.")]) { await LiveEvals.weeklyAttempt(item) }
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.error, "the sanitiser discarded the reply")
        XCTAssertEqual(outcome.output, "Alex, try for 3000 calories next week.")
        outcome = await scripted([textReply("Alex, no need to feel guilty about the weekend.")]) { await LiveEvals.weeklyAttempt(item) }
        XCTAssertFalse(outcome.ok)
        let atLimit = String(repeating: "a", count: 900)
        outcome = await scripted([textReply(atLimit)]) { await LiveEvals.weeklyAttempt(item) }
        XCTAssertTrue(outcome.ok, "900 characters is kept")
        outcome = await scripted([textReply(atLimit + "a")]) { await LiveEvals.weeklyAttempt(item) }
        XCTAssertFalse(outcome.ok, "901 characters is discarded")

        outcome = await scripted([serverError]) { await LiveEvals.weeklyAttempt(item) }
        XCTAssertEqual(outcome.error, "the call failed: boom")
    }

    // MARK: - onboardingNote

    func testOnboardingNoteGraderPassRule() {
        let inputs = OnboardingCoachMessage.Inputs(name: "Alex", direction: .gain, paceLabel: "Lean gain",
                                                   activityLabel: "Lightly active",
                                                   note: "I lift 4 days a week but I never eat enough on rest days.")
        let notGain = ["lose weight", "weight loss", "deficit"]
        func grade(_ text: String, reader: Graders.Reader? = nil) -> (scores: [String: Double], pass: Bool) {
            Graders.onboardingNote(given: OnboardingCoachMessage.userPrompt(inputs), name: "Alex", mustNotSay: notGain,
                                   text: text, reader: reader ?? alex)
        }
        let good = grade("Alex, let's build. Four days of lifting is a strong base, and we'll make rest days count too 💪")
        XCTAssertTrue(good.pass)
        XCTAssertEqual(good.scores, ["used": 1, "no_number_invented": 1, "wrong_person_pronoun": 0,
                                     "names_only_the_given_goal": 1, "two_to_four_sentences": 1, "at_most_one_emoji": 1,
                                     "no_list_or_header": 1, "name_used_once": 1])
        // A number the person did not give.
        let invented = grade("Alex, let's build. Five meals a day will get you there.")
        XCTAssertFalse(invented.pass); XCTAssertEqual(invented.scores["no_number_invented"], 0)
        // A goal other than the one it was told.
        let otherGoal = grade("Alex, let's build. This is not about weight loss, it is about muscle.")
        XCTAssertFalse(otherGoal.pass); XCTAssertEqual(otherGoal.scores["names_only_the_given_goal"], 0)
        XCTAssertFalse(grade("Alex, a sensible DEFICIT gets you there. Let's go.").pass, "matched whatever the case")
        // The right person.
        XCTAssertFalse(grade("Alex is in. She is ready to build.").pass)
        XCTAssertTrue(grade("Alex is in. He is ready to build.").pass)
        XCTAssertFalse(grade("Sam is in. He is ready to build.", reader: sam).pass)
    }

    func testOnboardingNoteGraderScores() {
        func scores(_ text: String, name: String = "Sam") -> [String: Double] {
            let inputs = OnboardingCoachMessage.Inputs(name: name, direction: .lose, paceLabel: "Relaxed",
                                                       activityLabel: "Lightly active", note: "")
            return Graders.onboardingNote(given: OnboardingCoachMessage.userPrompt(inputs), name: name, mustNotSay: [],
                                          text: text, reader: sam).scores
        }
        XCTAssertEqual(scores(sentences(1))["two_to_four_sentences"], 0)
        XCTAssertEqual(scores(sentences(2))["two_to_four_sentences"], 1)
        XCTAssertEqual(scores(sentences(4))["two_to_four_sentences"], 1)
        XCTAssertEqual(scores(sentences(5))["two_to_four_sentences"], 0)
        XCTAssertEqual(scores("You're in. Let's go.")["name_used_once"], 0)
        XCTAssertEqual(scores("Sam, you're in. Let's go.")["name_used_once"], 1)
        XCTAssertEqual(scores("Sam, you're in. Let's go, Sam.")["name_used_once"], 0)
        XCTAssertNil(scores("You're in.", name: "")["name_used_once"])
        XCTAssertEqual(scores("Let's go 💪")["at_most_one_emoji"], 1)
        XCTAssertEqual(scores("Let's go 💪🔥")["at_most_one_emoji"], 0)
        XCTAssertEqual(scores("• protein\n• steps")["no_list_or_header"], 0)
        XCTAssertEqual(scores("Sam, you're in. Let's go.")["names_only_the_given_goal"], 1, "an empty list forbids nothing")
    }

    func testOnboardingDatasetMapsOntoTheInputsAndTheTemplateItFallsBackTo() async throws {
        let cases = try rows("onboarding_note/v1.jsonl", as: LiveEvals.OnboardingCase.self)
        XCTAssertEqual(cases.count, 15)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        var directions = Set<String>()
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.user), c.id)
            let inputs = try XCTUnwrap(c.inputs, "\(c.id): the pace or the activity is not one of the app's")
            XCTAssertFalse(c.mustNotSay.isEmpty, c.id)
            // A fixture user keeps the goal direction of the fixture, or holds steady.
            XCTAssertTrue([EvalFixtures.direction(c.user), .maintain].contains(inputs.direction), c.id)
            directions.insert("\(inputs.direction)")
            let template = OnboardingCoachMessage.template(for: inputs)
            let shown = await withNoKey { await OnboardingCoachMessage.make(inputs) }
            XCTAssertEqual(shown.result, template, c.id)
            XCTAssertEqual(shown.requests, 0, c.id)
            if (c.name ?? "").isEmpty {
                // With no name the note starts with its own sentence, never a stand-in name (EVAL_REPORT 26).
                XCTAssertEqual(template.first?.isUppercase, true, c.id)
                XCTAssertFalse(template.lowercased().contains("friend"), c.id)
            } else {
                XCTAssertTrue(template.hasPrefix(inputs.name + ","), c.id)
            }
            XCTAssertEqual(OnboardingCoachMessage.sanitize(template), template, "\(c.id): the template passes the app's sanitiser")
            XCTAssertTrue(Graders.onboardingNote(given: OnboardingCoachMessage.userPrompt(inputs), name: inputs.name,
                                                 mustNotSay: c.mustNotSay, text: template, reader: c.reader).pass,
                          "\(c.id): the template must pass its own case")
            // The phrases a case forbids are about another goal, never the one it is told.
            XCTAssertTrue(Graders.phrases(in: OnboardingCoachMessage.userPrompt(inputs).components(separatedBy: "Goal rule:")[0],
                                          from: c.mustNotSay).isEmpty, "\(c.id): a forbidden phrase is in the goal it is told")
        }
        XCTAssertEqual(directions, ["lose", "maintain", "gain"])
        XCTAssertEqual(Set(cases.map(\.pace)), Set(GoalPace.allCases.map(\.rawValue)), "every pace is covered")
        XCTAssertEqual(Set(cases.map(\.activity)), Set(ActivityLevel.allCases.map(\.rawValue)), "every activity level is covered")
        XCTAssertEqual(cases.filter { $0.user == "gain" }.count, 7)
        XCTAssertEqual(cases.filter { $0.user == "loss" }.count, 8)
        XCTAssertEqual(cases.filter { $0.note.isEmpty }.count, 6)
        XCTAssertEqual(cases.filter { $0.note.rangeOfCharacter(from: .decimalDigits) != nil }.count, 2,
                       "two notes hold a figure, which a rewrite may only repeat in words")
        XCTAssertEqual(cases.filter { $0.name == "" }.count, 1)
    }

    func testOnboardingAttemptOnAScriptedModel() async throws {
        let cases = try rows("onboarding_note/v1.jsonl", as: LiveEvals.OnboardingCase.self)
        let item = try XCTUnwrap(cases.first { $0.id == "alex-lean-gain-note-with-a-figure" })
        var outcome = await scripted([textReply("Alex, let's build. Four days of lifting is a strong base.")]) {
            await LiveEvals.onboardingAttempt(item)
        }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        // Repeating the person's own figure in digits is what the sanitiser throws away.
        outcome = await scripted([textReply("Alex, let's build. Lifting 4 days a week is a strong base.")]) {
            await LiveEvals.onboardingAttempt(item)
        }
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.error, "the sanitiser discarded the reply")
        XCTAssertEqual(outcome.output, "Alex, let's build. Lifting 4 days a week is a strong base.")
        outcome = await scripted([textReply("Alex, let's build. Forget weight loss, this is about muscle.")]) {
            await LiveEvals.onboardingAttempt(item)
        }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass, "used, but it names another goal")
        let atLimit = String(repeating: "a", count: 700)
        outcome = await scripted([textReply(atLimit)]) { await LiveEvals.onboardingAttempt(item) }
        XCTAssertTrue(outcome.ok, "700 characters is kept")
        outcome = await scripted([textReply(atLimit + "a")]) { await LiveEvals.onboardingAttempt(item) }
        XCTAssertFalse(outcome.ok, "701 characters is discarded")
        outcome = await scripted([serverError]) { await LiveEvals.onboardingAttempt(item) }
        XCTAssertEqual(outcome.error, "the call failed: boom")
    }

    // MARK: - memoryFold

    private func fact(_ kind: String, _ keywords: String...) -> Graders.PlantedFact {
        Graders.PlantedFact(kind: kind, name: keywords[0], keywords: keywords)
    }

    private var memoryExpectation: Graders.MemoryExpectation {
        Graders.MemoryExpectation(
            currentNotes: "- Works as an electrician", currentSummary: "Was asking about packed lunches.",
            facts: [fact("allergy", "peanut"), fact("injury", "knee"), fact("preference", "oat milk", "oatmilk"),
                    fact("schedule", "night shift", "nights")],
            retracted: ["marathon"], existing: [fact("existing", "electrician")],
            smallTalk: ["raining", "the game"], mustNotStore: ["161.2"], reader: alex)
    }

    private let goodNotes = "- Works as an electrician\n- Allergic to peanuts\n- Left knee is sore on deep squats\n"
        + "- Drinks oat milk\n- Works night shifts, Sunday to Thursday\n- Pulled out of the April half marathon"

    private func memoryReply(notes: String?, summary: String? = "Shared an allergy, an injury and a shift pattern.") -> String {
        var object: [String: Any] = [:]
        if let notes { object["notes"] = notes }
        if let summary { object["summary"] = summary }
        return EvalRunner.compactJSON(object)
    }

    func testARetractedFactIsReadAsGoneOnlyWhenTheNoteSaysSo() {
        let marathon = ["marathon"]
        XCTAssertTrue(Graders.stillStates("- Training for a half marathon in April", keywords: marathon))
        XCTAssertTrue(Graders.stillStates("- Knee is sore. Signed up for a half marathon.", keywords: marathon))
        XCTAssertTrue(Graders.stillStates("- Drinks coffee at the office; marathon in April", keywords: marathon),
                      "'off' inside 'coffee' and 'office' is not a retraction word")
        XCTAssertFalse(Graders.stillStates("- Pulled out of the April half marathon (knee)", keywords: marathon))
        XCTAssertFalse(Graders.stillStates("- Not running the half marathon", keywords: marathon))
        XCTAssertFalse(Graders.stillStates("- Half marathon is off", keywords: marathon))
        XCTAssertFalse(Graders.stillStates("- Half marathon entry cancelled and refunded", keywords: marathon))
        XCTAssertFalse(Graders.stillStates("- Isn’t doing the half marathon any more", keywords: marathon))
        XCTAssertFalse(Graders.stillStates("- Was signed up for a half marathon; withdrew", keywords: marathon))
        XCTAssertFalse(Graders.stillStates("- Allergic to peanuts\n- Left knee is sore", keywords: marathon), "never mentioned")
        // Only the clause that mentions the fact is read.
        XCTAssertTrue(Graders.stillStates("- Not a morning person. Running a marathon in April.", keywords: marathon))
        XCTAssertTrue(Graders.stillStates("- Vegetarian", keywords: ["vegetarian"]))
        XCTAssertFalse(Graders.stillStates("- Back to eating chicken and fish (no longer vegetarian)", keywords: ["vegetarian"]))
    }

    func testMemoryFoldGraderPassRule() {
        let expect = memoryExpectation
        let good = Graders.memoryFold(raw: memoryReply(notes: goodNotes), expect: expect)
        XCTAssertTrue(good.pass)
        for name in ["parses", "all_facts_kept", "facts_kept_share", "retracted_fact_absent", "existing_notes_kept",
                     "notes_within_budget", "summary_within_budget", "both_fields_returned", "small_talk_not_kept",
                     "no_app_owned_number_stored", "bare_json", "no_gendered_pronoun", "kept_allergy", "kept_injury",
                     "kept_preference", "kept_schedule"] {
            XCTAssertEqual(good.scores[name], 1, name)
        }
        XCTAssertEqual(good.scores["wrong_person_pronoun"], 0)
        XCTAssertEqual(good.scores["notes_chars"], Double(goodNotes.count))

        // It must parse, as the app parses it.
        let prose = Graders.memoryFold(raw: "Here are the updated notes: peanuts, knee, oat milk, night shifts.", expect: expect)
        XCTAssertFalse(prose.pass); XCTAssertEqual(prose.scores, ["parses": 0])
        // A code fence is tolerated by the app's parser, so it parses; it is only recorded.
        let fenced = Graders.memoryFold(raw: "```json\n" + memoryReply(notes: goodNotes) + "\n```", expect: expect)
        XCTAssertTrue(fenced.pass); XCTAssertEqual(fenced.scores["bare_json"], 0)

        // Every planted fact.
        let noAllergy = Graders.memoryFold(raw: memoryReply(notes: goodNotes.replacingOccurrences(of: "- Allergic to peanuts\n", with: "")),
                                           expect: expect)
        XCTAssertFalse(noAllergy.pass)
        XCTAssertEqual(noAllergy.scores["kept_allergy"], 0)
        XCTAssertEqual(noAllergy.scores["facts_kept_share"], 0.75)
        XCTAssertEqual(noAllergy.scores["kept_injury"], 1)
        // A fact in the summary only is not a durable note.
        XCTAssertFalse(Graders.memoryFold(
            raw: memoryReply(notes: goodNotes.replacingOccurrences(of: "- Allergic to peanuts\n", with: ""),
                             summary: "Mentioned a peanut allergy."), expect: expect).pass)
        // The fact that was taken back.
        let stale = Graders.memoryFold(raw: memoryReply(notes: goodNotes.replacingOccurrences(
            of: "- Pulled out of the April half marathon", with: "- Training for a half marathon in April")), expect: expect)
        XCTAssertFalse(stale.pass); XCTAssertEqual(stale.scores["retracted_fact_absent"], 0)
        XCTAssertTrue(Graders.memoryFold(raw: memoryReply(notes: goodNotes.replacingOccurrences(
            of: "\n- Pulled out of the April half marathon", with: "")), expect: expect).pass, "leaving it out is right too")
        // The notes that were passed in.
        let dropped = Graders.memoryFold(raw: memoryReply(notes: goodNotes.replacingOccurrences(
            of: "- Works as an electrician\n", with: "")), expect: expect)
        XCTAssertFalse(dropped.pass); XCTAssertEqual(dropped.scores["existing_notes_kept"], 0)
        // No notes returned: the app keeps the old ones, which hold none of the new facts.
        let summaryOnly = Graders.memoryFold(raw: memoryReply(notes: nil), expect: expect)
        XCTAssertFalse(summaryOnly.pass)
        XCTAssertEqual(summaryOnly.scores["both_fields_returned"], 0)
        XCTAssertEqual(summaryOnly.scores["existing_notes_kept"], 1)
        XCTAssertEqual(summaryOnly.scores["facts_kept_share"], 0)
    }

    func testMemoryFoldBudgetsAtTheirEdges() {
        let expect = memoryExpectation
        func notes(_ length: Int) -> String { goodNotes + "\n" + String(repeating: "x", count: length - goodNotes.count - 1) }
        XCTAssertEqual(notes(CoachMemoryService.notesCharBudget).count, 1500)
        let atNotes = Graders.memoryFold(raw: memoryReply(notes: notes(1500)), expect: expect)
        XCTAssertTrue(atNotes.pass); XCTAssertEqual(atNotes.scores["notes_within_budget"], 1)
        let overNotes = Graders.memoryFold(raw: memoryReply(notes: notes(1501)), expect: expect)
        XCTAssertFalse(overNotes.pass)
        XCTAssertEqual(overNotes.scores["notes_within_budget"], 0)
        XCTAssertEqual(overNotes.scores["notes_chars"], 1501)
        XCTAssertEqual(overNotes.scores["all_facts_kept"], 1, "the facts survived the clamp; the budget alone fails it")

        let atSummary = Graders.memoryFold(raw: memoryReply(notes: goodNotes, summary: String(repeating: "s", count: 1000)),
                                           expect: expect)
        XCTAssertTrue(atSummary.pass)
        let overSummary = Graders.memoryFold(raw: memoryReply(notes: goodNotes, summary: String(repeating: "s", count: 1001)),
                                             expect: expect)
        XCTAssertFalse(overSummary.pass); XCTAssertEqual(overSummary.scores["summary_within_budget"], 0)
        XCTAssertEqual(CoachMemoryService.summaryCharBudget, 1000)
    }

    func testMemoryFoldScoresDoNotDecideThePass() {
        let expect = memoryExpectation
        var graded = Graders.memoryFold(raw: memoryReply(notes: goodNotes + "\n- It was raining for days"), expect: expect)
        XCTAssertTrue(graded.pass); XCTAssertEqual(graded.scores["small_talk_not_kept"], 0)
        graded = Graders.memoryFold(raw: memoryReply(notes: goodNotes + "\n- Weighed 161.2"), expect: expect)
        XCTAssertTrue(graded.pass); XCTAssertEqual(graded.scores["no_app_owned_number_stored"], 0)
        graded = Graders.memoryFold(raw: memoryReply(notes: goodNotes, summary: "He shared an allergy."), expect: expect)
        XCTAssertTrue(graded.pass)
        XCTAssertEqual(graded.scores["no_gendered_pronoun"], 0)
        XCTAssertEqual(graded.scores["wrong_person_pronoun"], 0, "Alex is a man; it is still a guess")
        graded = Graders.memoryFold(raw: memoryReply(notes: goodNotes, summary: "She shared an allergy."), expect: expect)
        XCTAssertEqual(graded.scores["wrong_person_pronoun"], 1)
    }

    func testMemoryDatasetPlantsWhatItClaimsAndAPerfectFoldPasses() async throws {
        let cases = try rows("memory_fold/v1.jsonl", as: LiveEvals.MemoryCase.self)
        XCTAssertEqual(cases.count, 12)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.user), c.id)
            XCTAssertGreaterThanOrEqual(c.messages.count, 12, c.id)
            XCTAssertTrue(c.messages.allSatisfy { ["user", "assistant"].contains($0.role) }, c.id)
            XCTAssertEqual(c.snapshots.map(\.content), c.messages.map(\.content), c.id)
            XCTAssertEqual(c.snapshots.map(\.createdAt), c.snapshots.map(\.createdAt).sorted(), "\(c.id): oldest first")
            XCTAssertEqual(Set(c.facts.map(\.kind)), ["allergy", "injury", "preference", "schedule"],
                           "\(c.id): one fact of each kind")
            XCTAssertEqual(c.facts.count, 4, c.id)

            let said = c.messages.filter { $0.role == "user" }.map(\.content).joined(separator: "\n")
            let all = c.messages.map(\.content).joined(separator: "\n")
            for planted in c.facts {
                XCTAssertTrue(planted.keywords.contains { Graders.mentions(said, $0) }, "\(c.id): \(planted.name) is not in what the user said")
                XCTAssertFalse(planted.keywords.contains { Graders.mentions(c.currentNotes, $0) }, "\(c.id): \(planted.name) is already in the notes")
                XCTAssertFalse(planted.keywords.contains { keyword in c.retracted.keywords.contains { Graders.mentions($0, keyword) || Graders.mentions(keyword, $0) } },
                               "\(c.id): \(planted.name) shares a keyword with the retracted fact")
            }
            XCTAssertTrue(c.retracted.keywords.contains { Graders.mentions(said, $0) || Graders.mentions(c.currentNotes, $0) },
                          "\(c.id): the retracted fact is never stated")
            for kept in c.existing {
                XCTAssertTrue(kept.keywords.contains { Graders.mentions(c.currentNotes, $0) }, "\(c.id): \(kept.name) is not in the notes passed in")
            }
            XCTAssertEqual(c.existing.isEmpty, c.currentNotes.isEmpty || c.id == "never", c.id)
            XCTAssertTrue(c.smallTalk.contains { Graders.mentions(all, $0) }, "\(c.id): no small talk in the batch")
            XCTAssertTrue(c.mustNotStore.contains { all.contains($0) }, "\(c.id): the app-owned number is not in the batch")
            // The notes passed in still state the retracted fact where the case says it was saved earlier.
            if c.retracted.keywords.contains(where: { Graders.mentions(c.currentNotes, $0) }) {
                XCTAssertTrue(Graders.stillStates(c.currentNotes, keywords: c.retracted.keywords), c.id)
            }

            // With no key the app folds nothing, makes no request, and leaves the memory as it was.
            let unkeyed = await withNoKey {
                await CoachMemoryService.consolidate(currentNotes: c.currentNotes, currentSummary: c.currentSummary,
                                                     olderMessages: c.snapshots, profileName: c.reader.name)
            }
            XCTAssertNil(unkeyed.result, c.id)
            XCTAssertEqual(unkeyed.requests, 0, c.id)

            // A fold a careful person would write passes: the old notes without the retracted
            // line, plus one line per planted fact. And echoing the batch back does not.
            let keptLines = c.currentNotes.split(separator: "\n").map(String.init)
                .filter { line in !c.retracted.keywords.contains { Graders.mentions(line, $0) } }
            let perfect = (keptLines + c.facts.map { "- " + $0.keywords[0] }).joined(separator: "\n")
            let graded = Graders.memoryFold(raw: memoryReply(notes: perfect, summary: "The user shared updates."),
                                            expect: c.expectation)
            XCTAssertTrue(graded.pass, "\(c.id): a perfect fold does not pass \(graded.scores)")
            XCTAssertEqual(graded.scores["small_talk_not_kept"], 1, c.id)
            XCTAssertEqual(graded.scores["no_app_owned_number_stored"], 1, c.id)
            let unchanged = Graders.memoryFold(raw: memoryReply(notes: c.currentNotes.isEmpty ? "(none yet)" : c.currentNotes,
                                                                summary: "Nothing new."), expect: c.expectation)
            XCTAssertFalse(unchanged.pass, "\(c.id): leaving the notes as they were must not pass")
        }
        XCTAssertEqual(cases.filter { $0.user == "gain" }.count, 6)
        XCTAssertEqual(cases.filter { $0.user == "loss" }.count, 6)
        XCTAssertEqual(cases.filter { $0.currentNotes.isEmpty }.count, 5, "five first folds")
        XCTAssertEqual(cases.filter { !$0.currentSummary.isEmpty }.count, 4)
        XCTAssertEqual(cases.filter { c in c.retracted.keywords.contains { Graders.mentions(c.currentNotes, $0) } }.count, 2,
                       "in two cases the fact taken back was already saved")
    }

    func testMemoryAttemptOnAScriptedModel() async throws {
        let cases = try rows("memory_fold/v1.jsonl", as: LiveEvals.MemoryCase.self)
        let item = try XCTUnwrap(cases.first { $0.id == "alex-first-fold" })
        let notes = "- Allergic to peanuts\n- Left knee sore on deep squats\n- Drinks oat milk\n- Works night shifts"
        let reply = memoryReply(notes: notes)
        var outcome = await scripted([textReply(reply)]) { await LiveEvals.memoryAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.output, reply)

        outcome = await scripted([textReply(memoryReply(notes: notes + "\n- Training for a half marathon in April"))]) {
            await LiveEvals.memoryAttempt(item)
        }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass, "it kept the plan the user dropped")

        // A reply the app's parser cannot read: recorded, and not usable.
        outcome = await scripted([textReply("Sure! Notes: peanuts, knee, oat milk, night shifts.")]) {
            await LiveEvals.memoryAttempt(item)
        }
        XCTAssertFalse(outcome.ok); XCTAssertFalse(outcome.pass)
        XCTAssertEqual(outcome.error, "the reply did not parse as {notes, summary}")
        XCTAssertEqual(outcome.output, "Sure! Notes: peanuts, knee, oat milk, night shifts.")
        XCTAssertEqual(outcome.scores, ["parses": 0])

        outcome = await scripted([serverError]) { await LiveEvals.memoryAttempt(item) }
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.error, "the call failed: boom")
    }

    // MARK: - progressSummary

    private let progressSnapshot = """
        Weight trend: 156.4 lb
        Weekly rate: -0.6 lb/wk (negative = losing)
        Goal weight: 145.0 lb (goal direction: lose)
        Still to go: 11.4 lb
        Total weigh-ins: 18
        Avg calories over 7 logged day(s) this week: 1640 (fuel target 1700)
        Protein goal reached on 5 of 7 logged day(s) (target 115g)
        Current logging streak: 21 day(s)
        """

    private func recap(headline: String = "Steady and on track",
                       body: String = "Your trend is 156.4 lb, down 0.6 lb a week. Protein landed on 5 of 7 days.",
                       highlights: [String] = ["🔥 21-day logging streak", "Protein on 5 of 7 days"]) -> ProgressSummary {
        ProgressSummary(headline: headline, body: body, highlights: highlights)
    }

    func testProgressSummaryGraderPassRule() {
        func grade(_ summary: ProgressSummary, _ reader: Graders.Reader? = nil) -> (scores: [String: Double], pass: Bool) {
            Graders.progressSummary(snapshot: progressSnapshot, summary: summary, reader: reader ?? sam)
        }
        let good = grade(recap())
        XCTAssertTrue(good.pass)
        XCTAssertEqual(good.scores, ["highlights_within_schema": 1, "no_number_invented": 1, "wrong_person_pronoun": 0,
                                     "no_banned_phrase": 1, "headline_3_to_6_words": 1, "body_2_to_4_sentences": 1,
                                     "highlights_3_to_8_words": 1, "names_a_given_figure": 1])
        // The schema's own bounds on the highlights: 2 to 4.
        let line = "Protein on 5 of 7 days"
        XCTAssertFalse(grade(recap(highlights: [line])).pass)
        XCTAssertTrue(grade(recap(highlights: [line, line])).pass)
        XCTAssertTrue(grade(recap(highlights: [line, line, line, line])).pass)
        XCTAssertFalse(grade(recap(highlights: [line, line, line, line, line])).pass)
        XCTAssertFalse(grade(recap(highlights: [line, "  "])).pass, "a blank highlight is not a highlight")
        XCTAssertEqual(grade(recap(highlights: [line])).scores["highlights_within_schema"], 0)
        // No number that is not in the snapshot, in any of the three fields.
        XCTAssertFalse(grade(recap(body: "Down 0.6 lb a week, so about 2.4 lb a month. Keep going.")).pass)
        XCTAssertFalse(grade(recap(headline: "Down 12 pounds already")).pass)
        XCTAssertFalse(grade(recap(highlights: [line, "Aim for 130g protein"])).pass)
        XCTAssertFalse(grade(recap(body: "Your trend is about 156 lb. Protein landed on 5 of 7 days.")).pass,
                       "a rounded figure is not the figure given")
        XCTAssertFalse(grade(recap(body: "Three weeks of logging. Protein landed on 5 of 7 days.")).pass, "a number in words counts")
        XCTAssertEqual(grade(recap(headline: "Down 12 pounds already")).scores["no_number_invented"], 0)
        // The right person.
        XCTAssertFalse(grade(recap(body: "He is on track. Protein landed on 5 of 7 days.")).pass)
        XCTAssertTrue(grade(recap(body: "He is on track. Protein landed on 5 of 7 days."), alex).pass)
        XCTAssertFalse(grade(recap(body: "She is on track. Protein landed on 5 of 7 days."), alex).pass)
        // The prompt's own banned vocabulary, each phrase, as whole words.
        for phrase in Graders.progressSummaryBans {
            let graded = grade(recap(body: "Protein landed on 5 of 7 days. Remember: \(phrase)."))
            XCTAssertFalse(graded.pass, phrase)
            XCTAssertEqual(graded.scores["no_banned_phrase"], 0, phrase)
        }
        XCTAssertFalse(grade(recap(body: "You shouldn't worry. Protein landed on 5 of 7 days.")).pass)
        XCTAssertTrue(grade(recap(body: "You earned that badge. Protein landed on 5 of 7 days.")).pass, "'badge' is not 'bad'")
        XCTAssertTrue(grade(recap(body: "Shoulder work is paying off. Protein landed on 5 of 7 days.")).pass)
    }

    func testProgressSummaryGraderScores() {
        func scores(_ summary: ProgressSummary) -> [String: Double] {
            Graders.progressSummary(snapshot: progressSnapshot, summary: summary, reader: sam).scores
        }
        XCTAssertEqual(scores(recap(headline: words(2)))["headline_3_to_6_words"], 0)
        XCTAssertEqual(scores(recap(headline: words(3)))["headline_3_to_6_words"], 1)
        XCTAssertEqual(scores(recap(headline: words(6)))["headline_3_to_6_words"], 1)
        XCTAssertEqual(scores(recap(headline: words(7)))["headline_3_to_6_words"], 0)
        XCTAssertEqual(scores(recap(body: sentences(1)))["body_2_to_4_sentences"], 0)
        XCTAssertEqual(scores(recap(body: sentences(2)))["body_2_to_4_sentences"], 1)
        XCTAssertEqual(scores(recap(body: sentences(4)))["body_2_to_4_sentences"], 1)
        XCTAssertEqual(scores(recap(body: sentences(5)))["body_2_to_4_sentences"], 0)
        XCTAssertEqual(scores(recap(highlights: [words(3), words(2)]))["highlights_3_to_8_words"], 0)
        XCTAssertEqual(scores(recap(highlights: [words(3), "💪 " + words(8)]))["highlights_3_to_8_words"], 1)
        XCTAssertEqual(scores(recap(highlights: [words(3), words(9)]))["highlights_3_to_8_words"], 0)
        XCTAssertEqual(scores(recap(body: sentences(2), highlights: [words(3), words(3)]))["names_a_given_figure"], 0)
        // None of these decides the pass.
        XCTAssertTrue(Graders.progressSummary(snapshot: progressSnapshot,
                                              summary: recap(headline: words(9), body: sentences(6), highlights: [words(1), words(12)]),
                                              reader: sam).pass)
    }

    func testTheBannedListsAreThePromptsOwn() {
        // The prompts wrap their lines, which leaves runs of spaces inside a quoted phrase.
        func flat(_ prompt: String) -> String { prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let recapPrompt = flat(ProgressSummaryService.system), foodPrompt = flat(FoodSuggestionService.system)
        for phrase in Graders.progressSummaryBans {
            XCTAssertTrue(recapPrompt.contains("\"\(phrase)\""), "the recap prompt does not ban \"\(phrase)\"")
        }
        for phrase in Graders.foodSuggestionBans {
            XCTAssertTrue(foodPrompt.contains("\"\(phrase)\""), "the suggestions prompt does not ban \"\(phrase)\"")
        }
        // And nothing the prompts ban is missing: every quoted phrase after "HARD BANS" is in the list.
        func quoted(after marker: String, upTo end: String, in prompt: String) -> Set<String> {
            guard let start = prompt.range(of: marker), let stop = prompt.range(of: end, range: start.upperBound..<prompt.endIndex),
                  let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"") else { return [] }
            let section = String(prompt[start.upperBound..<stop.lowerBound])
            return Set(regex.matches(in: section, range: NSRange(section.startIndex..., in: section)).compactMap {
                Range($0.range(at: 1), in: section).map { String(section[$0]) }
            })
        }
        XCTAssertEqual(quoted(after: "HARD BANS", upTo: "FORMAT", in: recapPrompt), Set(Graders.progressSummaryBans))
        XCTAssertEqual(quoted(after: "HARD BANS", upTo: "FORMAT", in: foodPrompt), Set(Graders.foodSuggestionBans))
    }

    func testProgressDatasetWritesTheSnapshotTheCardWrites() async throws {
        let cases = try rows("progress_summary/v1.jsonl", as: LiveEvals.ProgressCase.self)
        XCTAssertEqual(cases.count, 15)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.user), c.id)
            let direction = try XCTUnwrap(c.goalDirection, c.id)
            // The card writes no snapshot at all without a weigh-in or some food.
            XCTAssertTrue(c.weightTrend != nil || c.loggedDays != nil, "\(c.id): the card would show its empty state")
            XCTAssertEqual(c.weightTrend == nil, c.snapshot.contains(LiveEvals.ProgressCase.noTrend), c.id)
            XCTAssertEqual(c.loggedDays == nil, c.snapshot.contains(LiveEvals.ProgressCase.noFood), c.id)
            if let trend = c.weightTrend {
                let goal = try XCTUnwrap(c.goalWeight, c.id)
                XCTAssertNotNil(c.weeklyRate, c.id); XCTAssertNotNil(c.weighIns, c.id)
                // "Still to go" as the card computes it for the goal's direction.
                switch direction {
                case .lose: XCTAssertEqual(try XCTUnwrap(c.stillToGo, c.id), max(0, trend - goal), accuracy: 0.05, c.id)
                case .gain: XCTAssertEqual(try XCTUnwrap(c.stillToGo, c.id), max(0, goal - trend), accuracy: 0.05, c.id)
                case .maintain: XCTAssertNil(c.stillToGo, c.id)
                }
            }
            if let logged = c.loggedDays {
                XCTAssertTrue((1...7).contains(logged), c.id)
                XCTAssertTrue((0...logged).contains(try XCTUnwrap(c.proteinHitDays, c.id)), c.id)
                XCTAssertNotNil(c.avgCalories, c.id); XCTAssertNotNil(c.fuelTarget, c.id); XCTAssertNotNil(c.proteinTarget, c.id)
            }
            if let stepDays = c.stepDays { XCTAssertTrue((1...7).contains(stepDays), c.id) }
            if let workouts = c.workoutsThisWeek { XCTAssertTrue((1...7).contains(workouts), c.id) }
            XCTAssertGreaterThanOrEqual(c.streak, 0, c.id)

            // With no key the card is hidden; the service refuses, and nothing is sent.
            let snapshot = c.snapshot
            let unkeyed = await withNoKey { () -> Error? in
                do { _ = try await ProgressSummaryService.summary(snapshot: snapshot); return nil } catch { return error }
            }
            XCTAssertTrue(isMissingKey(unkeyed.result), c.id)
            XCTAssertEqual(unkeyed.requests, 0, c.id)
        }

        // Every piece of wording the mirror writes is in the view that builds the real snapshot,
        // and every line the view can write is written by at least one case.
        let view = try String(contentsOf: evalsRoot.deletingLastPathComponent()
            .appendingPathComponent("Sprout/Features/Weight/ProgressSummaryCard.swift"), encoding: .utf8)
        let written = cases.map(\.snapshot).joined(separator: "\n")
        for label in ["Weight trend: ", "Weekly rate: ", "/wk (negative = losing)", "Goal weight: ", "(goal direction: ",
                      "Still to go: ", "Projected goal date: ", "Total weigh-ins: ", LiveEvals.ProgressCase.noTrend,
                      "Avg calories over ", " logged day(s) this week: ", "(fuel target ", "Protein goal reached on ",
                      " logged day(s) (target ", LiveEvals.ProgressCase.noFood, "Avg steps over ", " day(s): ", "(goal ",
                      "Workouts this week: ", "Current logging streak: ", "About the user, from their own profile: "] {
            XCTAssertTrue(view.contains(label), "the card no longer writes \"\(label)\"")
            XCTAssertTrue(written.contains(label), "no case writes \"\(label)\"")
        }
        XCTAssertTrue(written.contains("(goal direction: lose)") && written.contains("(goal direction: gain)")
                      && written.contains("(goal direction: maintain)"))
        XCTAssertEqual(try XCTUnwrap(cases.first { $0.id == "sam-on-track" }).snapshot, """
            Weight trend: 156.4 lb
            Weekly rate: -0.6 lb/wk (negative = losing)
            Goal weight: 145.0 lb (goal direction: lose)
            Still to go: 11.4 lb
            Projected goal date: Apr 9, 2027
            Total weigh-ins: 18
            Avg calories over 7 logged day(s) this week: 1640 (fuel target 1700)
            Protein goal reached on 5 of 7 logged day(s) (target 115g)
            Avg steps over 7 day(s): 8420 (goal 8000)
            Workouts this week: 3
            Current logging streak: 21 day(s)
            """)
        XCTAssertEqual(cases.filter { $0.user == "gain" }.count, 7)
        XCTAssertEqual(cases.filter { $0.user == "loss" }.count, 8)
    }

    func testProgressAttemptOnAScriptedModel() async throws {
        let cases = try rows("progress_summary/v1.jsonl", as: LiveEvals.ProgressCase.self)
        let item = try XCTUnwrap(cases.first { $0.id == "sam-on-track" })
        let good: [String: Any] = ["headline": "Steady and on track",
                                   "body": "Your trend is 156.4 lb, down 0.6 lb a week. Protein landed on 5 of 7 days.",
                                   "highlights": ["🔥 21-day logging streak", "Protein on 5 of 7 days"]]
        var outcome = await scripted([toolReply(good)]) { await LiveEvals.progressAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        XCTAssertTrue(outcome.output.hasPrefix("Steady and on track\nYour trend is 156.4 lb"))

        var invented = good
        invented["body"] = "Your trend is 156.4 lb. At this rate you lose 2.4 lb a month."
        outcome = await scripted([toolReply(invented)]) { await LiveEvals.progressAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass, "usable, but 2.4 is in no snapshot")

        // A reply the service cannot decode is not usable; what the model sent is kept.
        outcome = await scripted([toolReply(["headline": "Only a headline"])]) { await LiveEvals.progressAttempt(item) }
        XCTAssertFalse(outcome.ok); XCTAssertFalse(outcome.pass)
        XCTAssertEqual(outcome.output, #"{"headline":"Only a headline"}"#)
        XCTAssertTrue(outcome.error?.contains("decoding") ?? false, outcome.error ?? "")
        // The model answered in prose instead of calling the tool (what a model that rejects a forced call does).
        outcome = await scripted([textReply("Here is your recap.")]) { await LiveEvals.progressAttempt(item) }
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.output, "Here is your recap.")
        // A model that refuses the forced call is asked again with the JSON-schema format, whose
        // answer is the reply's text (EVAL_REPORT 30)...
        let refusal: ScriptedTransport.Reply = .json(400, ["error": ["message": "tool_choice is not supported for this model"]])
        let goodText = String(data: try JSONSerialization.data(withJSONObject: good), encoding: .utf8)!
        outcome = await scripted([refusal, textReply(goodText)]) { await LiveEvals.progressAttempt(item) }
        XCTAssertTrue(outcome.ok, outcome.error ?? "")
        XCTAssertTrue(outcome.pass)
        // ...and when that fails too, the call is not usable and says why.
        outcome = await scripted([refusal, .json(400, ["error": ["message": "overloaded schema"]])]) {
            await LiveEvals.progressAttempt(item)
        }
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.error?.contains("overloaded schema") ?? false, outcome.error ?? "")
    }

    // MARK: - foodSuggestions

    private func pick(_ kind: Suggestion.Kind = .add, _ title: String = "Protein yogurt bowl",
                      _ detail: String = "Add a cup of Greek yogurt with berries for about 20 g of protein.",
                      _ emoji: String = "🥣") -> Suggestion {
        Suggestion(kind: kind, title: title, detail: detail, emoji: emoji)
    }

    private func foodExpectation(place: String? = nil, avoid: [String]? = nil, reader: Graders.Reader? = nil) -> Graders.FoodExpectation {
        Graders.FoodExpectation(nearbyPlace: place, topFoods: ["Greek yogurt", "Oatmeal"], eatenToday: ["Oatmeal"],
                                avoid: avoid, reader: reader ?? sam)
    }

    func testFoodSuggestionsGraderPassRule() {
        let wrap = pick(.idea, "Turkey wrap upgrade", "Roll three slices of turkey into a wrap with spinach.", "🌯")
        let good = Graders.foodSuggestions([pick(), wrap], rawCount: 2, expect: foodExpectation())
        XCTAssertTrue(good.pass)
        XCTAssertEqual(good.scores, ["shown_within_schema": 1, "nearby_rule_kept": 1, "wrong_person_pronoun": 0,
                                     "no_banned_phrase": 1, "details_one_sentence": 1, "titles_2_to_5_words": 1,
                                     "one_emoji_each": 1, "names_a_logged_food": 1, "nothing_eaten_today_in_a_title": 1,
                                     "model_count_within_schema": 1])
        // The schema's own bounds: 2 to 3.
        XCTAssertFalse(Graders.foodSuggestions([pick()], rawCount: nil, expect: foodExpectation()).pass)
        XCTAssertTrue(Graders.foodSuggestions([pick(), wrap, pick()], rawCount: nil, expect: foodExpectation()).pass)
        XCTAssertFalse(Graders.foodSuggestions([pick(), wrap, pick(), wrap], rawCount: nil, expect: foodExpectation()).pass)
        XCTAssertFalse(Graders.foodSuggestions([pick(), pick(.add, "Egg whites", "Add a cup of egg whites.", " ")],
                                               rawCount: nil, expect: foodExpectation()).pass, "a blank emoji")
        // A nearby pick only when a place was offered, and at most one.
        let nearby = pick(.nearby, "Corner Market run", "Grab a rotisserie chicken from Corner Market on the way home.", "🛒")
        XCTAssertFalse(Graders.foodSuggestions([pick(), nearby], rawCount: nil, expect: foodExpectation()).pass,
                       "no place was offered")
        let withPlace = Graders.foodSuggestions([pick(), nearby], rawCount: nil, expect: foodExpectation(place: "Corner Market"))
        XCTAssertTrue(withPlace.pass)
        XCTAssertEqual(withPlace.scores["nearby_pick_names_the_place"], 1)
        XCTAssertFalse(Graders.foodSuggestions([nearby, nearby], rawCount: nil, expect: foodExpectation(place: "Corner Market")).pass,
                       "two nearby picks")
        XCTAssertEqual(Graders.foodSuggestions([pick(), pick(.nearby, "Deli stop", "Grab a turkey sandwich nearby.", "🥪")],
                                               rawCount: nil, expect: foodExpectation(place: "Corner Market"))
            .scores["nearby_pick_names_the_place"], 0)
        // The right person.
        let his = pick(.add, "Egg white boost", "Add egg whites to his usual oatmeal.")
        XCTAssertFalse(Graders.foodSuggestions([pick(), his], rawCount: nil, expect: foodExpectation()).pass)
        XCTAssertTrue(Graders.foodSuggestions([pick(), his], rawCount: nil, expect: foodExpectation(reader: alex)).pass)
        // The prompt's own banned vocabulary.
        for phrase in Graders.foodSuggestionBans {
            let graded = Graders.foodSuggestions([pick(), pick(.idea, "Simple swap", "Remember, \(phrase).")],
                                                 rawCount: nil, expect: foodExpectation())
            XCTAssertFalse(graded.pass, phrase)
            XCTAssertEqual(graded.scores["no_banned_phrase"], 0, phrase)
        }
    }

    func testFoodSuggestionsGraderScores() {
        func scores(_ second: Suggestion, rawCount: Int? = nil, avoid: [String]? = nil) -> [String: Double] {
            Graders.foodSuggestions([pick(), second], rawCount: rawCount, expect: foodExpectation(avoid: avoid)).scores
        }
        XCTAssertEqual(scores(pick(.add, "Egg whites", "Add egg whites. They are quick."))["details_one_sentence"], 0)
        XCTAssertEqual(scores(pick(.add, words(1)))["titles_2_to_5_words"], 0)
        XCTAssertEqual(scores(pick(.add, words(2)))["titles_2_to_5_words"], 1)
        XCTAssertEqual(scores(pick(.add, words(5)))["titles_2_to_5_words"], 1)
        XCTAssertEqual(scores(pick(.add, words(6)))["titles_2_to_5_words"], 0)
        XCTAssertEqual(scores(pick(.add, "Egg whites", "Add a cup of egg whites.", "🥚🍳"))["one_emoji_each"], 0)
        XCTAssertEqual(scores(pick(.add, "Egg whites", "Add a cup of egg whites.", "egg"))["one_emoji_each"], 0)
        XCTAssertEqual(scores(pick(.add, "Oatmeal with protein", "Stir protein powder into a bowl."))["nothing_eaten_today_in_a_title"], 0,
                       "oatmeal was already eaten today")
        XCTAssertEqual(Graders.foodSuggestions([pick(.add, "Egg whites", "Add a cup of egg whites."),
                                                pick(.idea, "Bean chili", "Make a pot of bean chili.")],
                                               rawCount: nil, expect: foodExpectation()).scores["names_a_logged_food"], 0)
        // The model's own count, when its reply could be read.
        XCTAssertNil(scores(pick())["model_count_within_schema"])
        XCTAssertEqual(scores(pick(), rawCount: 3)["model_count_within_schema"], 1)
        XCTAssertEqual(scores(pick(), rawCount: 4)["model_count_within_schema"], 0)
        XCTAssertEqual(scores(pick(), rawCount: 1)["model_count_within_schema"], 0)
        // A diet the logged foods show: a score, never the pass.
        XCTAssertNil(scores(pick())["avoided_foods_absent"], "the case shows no diet")
        XCTAssertEqual(scores(pick(), avoid: ["chicken", "egg"])["avoided_foods_absent"], 1)
        let chicken = pick(.add, "Grilled chicken add-on", "Add grilled chicken to your veggie burger.")
        XCTAssertEqual(scores(chicken, avoid: ["chicken", "egg"])["avoided_foods_absent"], 0)
        XCTAssertEqual(scores(pick(.add, "More veggies", "Add roasted eggplant and veggies to the bowl."), avoid: ["egg", "ham"])["avoided_foods_absent"], 1)
        XCTAssertEqual(scores(pick(.add, "Egg white boost", "Fold two eggs into the bowl."), avoid: ["egg"])["avoided_foods_absent"], 0)
        XCTAssertEqual(scores(pick(.add, "Egg white boost", "Add a cup of egg whites."), avoid: ["egg"])["avoided_foods_absent"], 0)
        XCTAssertTrue(Graders.namesFood("Grilled sausages", "sausage"))
        XCTAssertFalse(Graders.namesFood("A veggie hamburger", "ham"))
        XCTAssertTrue(Graders.foodSuggestions([pick(), chicken], rawCount: 5,
                                              expect: foodExpectation(avoid: ["chicken"])).pass)
    }

    func testFoodDatasetMapsOntoTheEngineContext() async throws {
        let cases = try rows("food_suggestions/v1.jsonl", as: LiveEvals.FoodCase.self)
        XCTAssertEqual(cases.count, 18)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        var slots = Set<String>(), directions = Set<String>(), trends = Set<String>()
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.user), c.id)
            let context = try XCTUnwrap(c.context, "\(c.id) does not map onto FoodSuggestionEngine.Context")
            // The view only asks for suggestions when there are logged foods to build on.
            XCTAssertTrue(context.hasEnoughHistory, "\(c.id): the app would show its empty state and never call the model")
            XCTAssertEqual(context.caloriesRemaining, max(0, c.calorieTarget - c.caloriesEaten), c.id)
            XCTAssertEqual(context.proteinRemaining, max(0, c.proteinTarget - c.proteinEaten), c.id)
            XCTAssertEqual(context.name, c.user == "gain" ? "Alex" : "Sam", c.id)
            slots.insert(c.mealSlot); directions.insert(context.direction.rawValue)
            trends.insert(c.underProteinTrend.map { "\($0)" } ?? "unknown")

            // The facts of the case reach the prompt the engine renders.
            let prompt = FoodSuggestionService.userTurn(for: context)
            XCTAssertTrue(prompt.contains("Right now it's around \(c.mealSlot)"), c.id)
            XCTAssertTrue(prompt.contains("\(c.caloriesEaten) of \(c.calorieTarget) kcal"), c.id)
            for food in c.topFoods { XCTAssertTrue(prompt.contains(food.name), "\(c.id): \(food.name)") }
            for eaten in c.eatenToday { XCTAssertTrue(prompt.contains(eaten), "\(c.id): \(eaten)") }
            XCTAssertEqual(c.eatenToday.isEmpty, !prompt.contains("ALREADY eaten these today"), c.id)
            XCTAssertEqual(c.nearbyPlace == nil, !prompt.contains("There's a healthy option nearby"), c.id)
            if let place = c.nearbyPlace { XCTAssertTrue(prompt.contains(place.name), c.id) }

            // A case that shows a diet shows it in every food it logs.
            XCTAssertEqual(c.diet == nil, c.avoid == nil, c.id)
            for word in c.avoid ?? [] {
                for name in c.topFoods.map(\.name) + c.eatenToday {
                    XCTAssertFalse(Graders.namesFood(name, word), "\(c.id): the logged food \(name) is outside the case's own diet")
                }
            }

            // With no key the view shows its note; the service refuses, and nothing is sent.
            let unkeyed = await withNoKey { () -> Error? in
                do { _ = try await FoodSuggestionService.suggestions(for: context); return nil } catch { return error }
            }
            XCTAssertTrue(isMissingKey(unkeyed.result), c.id)
            XCTAssertEqual(unkeyed.requests, 0, c.id)
        }
        XCTAssertEqual(slots, ["breakfast", "lunch", "dinner", "snack"])
        XCTAssertEqual(directions, ["lose", "maintain", "gain"])
        XCTAssertEqual(trends, ["true", "false", "unknown"])
        XCTAssertEqual(cases.filter { $0.user == "gain" }.count, 8)
        XCTAssertEqual(cases.filter { $0.user == "loss" }.count, 10)
        XCTAssertEqual(cases.filter { $0.nearbyPlace != nil }.count, 4)
        XCTAssertEqual(cases.filter { $0.diet != nil }.count, 4)
    }

    func testFoodAttemptOnAScriptedModel() async throws {
        let cases = try rows("food_suggestions/v1.jsonl", as: LiveEvals.FoodCase.self)
        let item = try XCTUnwrap(cases.first { $0.id == "sam-vegetarian-lunch" })
        func suggestion(_ kind: String, _ title: String, _ detail: String) -> [String: Any] {
            ["kind": kind, "title": title, "detail": detail, "emoji": "🥗"]
        }
        let lentil = suggestion("add", "Lentil soup plus", "Stir a scoop of cottage cheese into your lentil soup for 14 g more protein.")
        let tofu = suggestion("idea", "Tofu rice bowl", "Build a tofu stir-fry bowl with edamame and brown rice.")
        var outcome = await scripted([toolReply(["suggestions": [lentil, tofu]])]) { await LiveEvals.foodAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.scores["avoided_foods_absent"], 1)
        XCTAssertEqual(outcome.scores["model_count_within_schema"], 1)
        XCTAssertTrue(outcome.output.hasPrefix("[add] 🥗 Lentil soup plus: Stir a scoop"), outcome.output)

        let chicken = suggestion("add", "Grilled chicken add-on", "Add grilled chicken to your veggie burger for 30 g of protein.")
        outcome = await scripted([toolReply(["suggestions": [lentil, chicken]])]) { await LiveEvals.foodAttempt(item) }
        XCTAssertTrue(outcome.pass, "the feature is told no diet, so this is recorded and does not fail the case")
        XCTAssertEqual(outcome.scores["avoided_foods_absent"], 0)

        // One suggestion left after the service drops an empty row: shown, and under the schema's minimum.
        outcome = await scripted([toolReply(["suggestions": [lentil, suggestion("add", "", "")]])]) { await LiveEvals.foodAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass)
        XCTAssertEqual(outcome.scores["shown_within_schema"], 0)
        // Four returned, three shown: the app's cap makes it showable; the model's own count is recorded.
        outcome = await scripted([toolReply(["suggestions": [lentil, tofu, lentil, tofu]])]) { await LiveEvals.foodAttempt(item) }
        XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.scores["model_count_within_schema"], 0)

        // Nothing the service can use: not usable, and what the model sent is kept.
        outcome = await scripted([toolReply(["suggestions": [suggestion("add", "", "")]])]) { await LiveEvals.foodAttempt(item) }
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.output.contains("\"suggestions\""), outcome.output)
        outcome = await scripted([toolReply(["picks": []])]) { await LiveEvals.foodAttempt(item) }
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.output, #"{"picks":[]}"#)
        outcome = await scripted([serverError]) { await LiveEvals.foodAttempt(item) }
        XCTAssertFalse(outcome.ok); XCTAssertEqual(outcome.output, "")
    }

    // MARK: - coachPrompts

    private let chipsGiven = "Logging streak: 9 days in a row — celebrate this consistency\nToday — Gym (Legs), 60 min"

    func testCoachPromptsGraderPassRule() {
        func grade(_ shown: [String], raw: [String]? = nil, routine: [String] = [], reader: Graders.Reader? = nil)
            -> (scores: [String: Double], pass: Bool) {
            Graders.coachPrompts(given: chipsGiven, shown: shown, raw: raw, routine: routine, reader: reader ?? alex)
        }
        let three = ["How did leg day go?", "Help me hit my protein", "Proud of my 9-day streak"]
        let good = grade(three, raw: three, routine: ["leg"])
        XCTAssertTrue(good.pass)
        XCTAssertEqual(good.scores, ["count_within_bounds": 1, "no_number_invented": 1, "wrong_person_pronoun": 0,
                                     "returned_the_count_asked": 1, "chips_at_most_six_words": 1,
                                     "model_count_within_schema": 1, "none_dropped_by_the_app": 1, "none_cut_short": 1,
                                     "nods_to_the_routine": 1])
        // At least the schema's minimum (2) and at most the app's own cap (3).
        XCTAssertFalse(grade(Array(three.prefix(1))).pass)
        XCTAssertTrue(grade(Array(three.prefix(2))).pass)
        XCTAssertEqual(grade(Array(three.prefix(2))).scores["returned_the_count_asked"], 0)
        XCTAssertFalse(grade(three + ["One more chip"]).pass)
        XCTAssertEqual(CoachPromptService.personalizedCount, 3)
        // No number that was not given.
        let invented = grade(["Can I squat 200 lb?", "Help me hit my protein"])
        XCTAssertFalse(invented.pass); XCTAssertEqual(invented.scores["no_number_invented"], 0)
        XCTAssertTrue(grade(["Sixty minutes of legs, wow", "Help me hit my protein"]).pass, "60 is in the data, written as a word")
        // A chip is the user's own first person.
        XCTAssertFalse(grade(["Is she proud of me?", "Help me hit my protein"]).pass)
        XCTAssertTrue(grade(["Is she proud of me?", "Help me hit my protein"], reader: sam).pass)
        XCTAssertFalse(grade(["Tell him I trained", "Help me hit my protein"], reader: sam).pass)
    }

    func testCoachPromptsGraderScores() {
        func scores(_ shown: [String], raw: [String]? = nil, routine: [String] = []) -> [String: Double] {
            Graders.coachPrompts(given: chipsGiven, shown: shown, raw: raw, routine: routine, reader: alex).scores
        }
        XCTAssertEqual(scores([words(6), words(2)])["chips_at_most_six_words"], 1)
        XCTAssertEqual(scores([words(7), words(2)])["chips_at_most_six_words"], 0)
        // Read from the model's own list, when there is one.
        XCTAssertNil(scores(["a b", "c d"])["none_dropped_by_the_app"])
        XCTAssertEqual(scores(["a b", "c d", "e f"], raw: ["a b", "c d", "e f", "g h", "i j"])["none_dropped_by_the_app"], 1,
                       "five returned, three kept by the cap")
        XCTAssertEqual(scores(["a b", "c d", "e f"], raw: ["a b", "c d", "e f", "g h", "i j"])["model_count_within_schema"], 1)
        XCTAssertEqual(scores(["a b", "c d", "e f"], raw: ["a b", "c d", "e f", "g h", "i j", "k l"])["model_count_within_schema"], 0)
        XCTAssertEqual(scores(["a b", "c d"], raw: ["a b", "c d", "Start a diet"])["none_dropped_by_the_app"], 0)
        XCTAssertEqual(scores(["a b", "c d"], raw: ["a b", "c d"])["none_cut_short"], 1)
        XCTAssertEqual(scores(["a b", "c d"], raw: ["a b", String(repeating: "long ", count: 12)])["none_cut_short"], 0)
        // The app bounds a chip at 42 characters, and the schema asks for 2 to 5.
        XCTAssertEqual(scores(["a b", "c d"], raw: ["a b", String(repeating: "a", count: 42)])["none_cut_short"], 1)
        XCTAssertEqual(scores(["a b", "c d"], raw: ["a b", String(repeating: "a", count: 43)])["none_cut_short"], 0)
        XCTAssertEqual(scores(["a b"], raw: ["a b"])["model_count_within_schema"], 0)
        XCTAssertEqual(scores(["a b", "c d"], raw: ["a b", "c d"])["model_count_within_schema"], 1)
        XCTAssertNil(scores(["a b", "c d"])["nods_to_the_routine"], "the case describes no routine")
        XCTAssertEqual(scores(["How did leg day go?", "c d"], routine: ["swim", "leg"])["nods_to_the_routine"], 1)
        XCTAssertEqual(scores(["How was my week?", "c d"], routine: ["swim", "leg"])["nods_to_the_routine"], 0)
    }

    private func coachCases(_ task: String) throws -> [LiveEvals.CoachDataCase] {
        try rows("\(task)/v1.jsonl", as: LiveEvals.CoachDataCase.self)
    }

    /// The checks both datasets share: each case builds the app's own inputs, and what the
    /// case describes reaches the user turn the feature sends.
    private func checkCoachCases(_ cases: [LiveEvals.CoachDataCase],
                                 userTurn: (LiveEvals.CoachDataCase.Inputs, String) -> String) {
        XCTAssertEqual(cases.count, 16)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        var directions = Set<String>()
        for c in cases {
            XCTAssertTrue(["gain", "loss"].contains(c.user), c.id)
            XCTAssertTrue(c.isWellFormed, "\(c.id): a pace, a workout kind, a muscle focus or `logging` is not one of the app's")
            let inputs = c.inputs()
            XCTAssertEqual(inputs.sessions.count, c.sessions.count, c.id)
            XCTAssertEqual(inputs.profile.onboardingNote, c.bio, c.id)
            XCTAssertEqual(inputs.memory?.profileNotes ?? "", c.memoryNotes, c.id)
            XCTAssertEqual(inputs.foods.isEmpty, c.logging == "none", c.id)
            directions.insert("\(inputs.profile.pace.direction)")
            let summary = LiveEvals.coachDataSummary(inputs)
            let turn = userTurn(inputs, summary)
            XCTAssertTrue(turn.contains("Name: \(c.name == "" ? "your friend" : inputs.profile.name)"), c.id)
            XCTAssertEqual(c.sessions.isEmpty, !summary.contains("Recent gym/training sessions"), c.id)
            XCTAssertEqual(c.logging == "none", summary.contains("Today's intake: nothing logged yet"), c.id)
            XCTAssertEqual(c.bio.isEmpty, turn.contains("hasn't written an about-me note"), c.id)
            XCTAssertEqual(c.memoryNotes.isEmpty, turn.contains("You don't have durable notes"), c.id)
            if !c.bio.isEmpty { XCTAssertTrue(turn.contains(c.bio), c.id) }
            if !c.memoryNotes.isEmpty { XCTAssertTrue(turn.contains(c.memoryNotes), c.id) }
            for session in c.sessions where session.minutes > 0 {
                XCTAssertTrue(summary.contains(", \(session.minutes) min"), "\(c.id): a \(session.kind) session is not in the summary")
            }
            // A routine is described only where the model is shown one.
            XCTAssertEqual(c.routine.isEmpty, c.sessions.isEmpty, c.id)
            if !c.routine.isEmpty { XCTAssertTrue(c.routine.contains { Graders.mentions(turn, $0) }, c.id) }
        }
        XCTAssertEqual(directions, ["lose", "maintain", "gain"])
        XCTAssertEqual(cases.filter { $0.user == "gain" }.count, 7)
        XCTAssertEqual(cases.filter { $0.user == "loss" }.count, 9)
        XCTAssertEqual(cases.filter { $0.name == "" }.count, 1)
        XCTAssertEqual(cases.filter { $0.bio.isEmpty && $0.memoryNotes.isEmpty }.count, 5)
        XCTAssertEqual(cases.filter { $0.sessions.isEmpty }.count, 4)
        XCTAssertEqual(cases.filter { $0.logging == "none" }.count, 4)
    }

    func testCoachPromptsDatasetBuildsTheAppsInputsAndFallsBackToTheFixedChips() async throws {
        let cases = try coachCases("coach_prompts")
        checkCoachCases(cases) { inputs, summary in
            CoachPromptService.userPrompt(name: inputs.profile.name, direction: inputs.profile.pace.direction,
                                          dataSummary: summary, bio: inputs.profile.onboardingNote,
                                          memoryNotes: inputs.memory?.profileNotes ?? "")
        }
        for c in cases {
            let inputs = c.inputs()
            let unkeyed = await withNoKey {
                await CoachPromptService.prompts(profile: inputs.profile, foods: inputs.foods, weights: inputs.weights,
                                                 sessions: inputs.sessions, water: inputs.water, memory: inputs.memory)
            }
            XCTAssertEqual(unkeyed.result, CoachPromptService.fixedPrompts(), c.id)
            XCTAssertEqual(unkeyed.requests, 0, c.id)
        }
    }

    func testCoachPromptsAttemptOnAScriptedModel() async throws {
        let item = try XCTUnwrap(try coachCases("coach_prompts").first { $0.id == "alex-lifter-bio-and-notes" })
        let three = ["How did leg day go?", "Why am I tired after late shifts?", "I crushed my squats"]
        var outcome = await scripted([toolReply(["prompts": three])]) { await LiveEvals.coachPromptsAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.scores["nods_to_the_routine"], 1)
        XCTAssertEqual(outcome.scores["none_dropped_by_the_app"], 1)
        XCTAssertEqual(outcome.output, EvalRunner.compactJSON(["prompts": three]))

        // The app's own filter drops a chip about dieting; two are left, which still shows.
        outcome = await scripted([toolReply(["prompts": ["How did leg day go?", "Should I start a diet?", "I crushed my squats"]])]) {
            await LiveEvals.coachPromptsAttempt(item)
        }
        XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.scores["none_dropped_by_the_app"], 0)
        XCTAssertEqual(outcome.scores["returned_the_count_asked"], 0)
        // One left: under the minimum.
        outcome = await scripted([toolReply(["prompts": ["How did leg day go?", "Should I start a diet?", "Cheat day ideas"]])]) {
            await LiveEvals.coachPromptsAttempt(item)
        }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass)
        // A number the data does not hold.
        outcome = await scripted([toolReply(["prompts": ["Can I squat 400 lb soon?", "How did leg day go?", "I crushed my squats"]])]) {
            await LiveEvals.coachPromptsAttempt(item)
        }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass)
        XCTAssertEqual(outcome.scores["no_number_invented"], 0)
        // Nothing left: the chat shows the fixed chips, and the reply is kept.
        outcome = await scripted([toolReply(["prompts": ["Should I start a diet?", "Cheat day ideas"]])]) {
            await LiveEvals.coachPromptsAttempt(item)
        }
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.error, "the chip filter discarded the reply")
        XCTAssertTrue(outcome.output.contains("Cheat day ideas"))
        outcome = await scripted([toolReply(["chips": three])]) { await LiveEvals.coachPromptsAttempt(item) }
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.output.contains("\"chips\""))
    }

    // MARK: - checklistPlan

    private func proposals(_ count: Int, prefix: String = "Task") -> [ChecklistProposal] {
        (0..<count).map { ChecklistProposal(title: "\(prefix) \(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"][$0])", icon: "figure.walk") }
    }

    func testChecklistPlanGraderPassRule() {
        func grade(tasks: Int, chips: Int) -> Bool {
            Graders.checklistPlan(given: "", plan: ChecklistPlan(tasks: proposals(tasks), chips: proposals(chips, prefix: "Chip")),
                                  raw: nil, routine: [], reader: alex).pass
        }
        // The schema's own bounds: 3 to 5 tasks, 4 to 8 chips.
        XCTAssertFalse(grade(tasks: 2, chips: 4))
        XCTAssertTrue(grade(tasks: 3, chips: 4))
        XCTAssertTrue(grade(tasks: 5, chips: 8))
        XCTAssertFalse(grade(tasks: 6, chips: 8))
        XCTAssertFalse(grade(tasks: 3, chips: 3))
        XCTAssertFalse(grade(tasks: 5, chips: 9))
        XCTAssertFalse(grade(tasks: 0, chips: 7), "the no-key fallback (no tasks) is not a plan")

        let plan = ChecklistPlan(tasks: proposals(3), chips: proposals(3, prefix: "Chip") + [ChecklistProposal(title: "Walk her dog", icon: "figure.walk")])
        let wrong = Graders.checklistPlan(given: "", plan: plan, raw: nil, routine: [], reader: alex)
        XCTAssertFalse(wrong.pass); XCTAssertEqual(wrong.scores["wrong_person_pronoun"], 1)
        XCTAssertTrue(Graders.checklistPlan(given: "", plan: plan, raw: nil, routine: [], reader: sam).pass)
        let good = Graders.checklistPlan(given: "", plan: ChecklistPlan(tasks: proposals(3), chips: proposals(4, prefix: "Chip")),
                                         raw: nil, routine: [], reader: alex)
        XCTAssertEqual(good.scores, ["tasks_within_schema": 1, "chips_within_schema": 1, "wrong_person_pronoun": 0,
                                     "titles_at_most_four_words": 1, "no_number_outside_the_data": 1])
    }

    func testChecklistPlanGraderScores() {
        func scores(_ extra: String, given: String = "", raw: [String: Any]? = nil, routine: [String] = []) -> (scores: [String: Double], pass: Bool) {
            let plan = ChecklistPlan(tasks: proposals(3), chips: proposals(3, prefix: "Chip") + [ChecklistProposal(title: extra, icon: "figure.walk")])
            return Graders.checklistPlan(given: given, plan: plan, raw: raw, routine: routine, reader: alex)
        }
        XCTAssertEqual(scores(words(4)).scores["titles_at_most_four_words"], 1)
        XCTAssertEqual(scores(words(5)).scores["titles_at_most_four_words"], 0)
        // The prompt's own examples carry numbers, so a number is recorded and never fails the plan.
        let walk = scores("10 min walk")
        XCTAssertTrue(walk.pass); XCTAssertEqual(walk.scores["no_number_outside_the_data"], 0)
        XCTAssertEqual(scores("60 min leg day", given: "Today — Gym (Legs), 60 min").scores["no_number_outside_the_data"], 1)
        XCTAssertNil(scores("Leg day").scores["reflects_the_routine"])
        XCTAssertEqual(scores("Leg day", routine: ["leg", "swim"]).scores["reflects_the_routine"], 1)
        XCTAssertEqual(scores("Evening walk", routine: ["leg", "swim"]).scores["reflects_the_routine"], 0)

        func item(_ title: String, _ icon: String) -> [String: Any] { ["title": title, "icon": icon] }
        let tasks = [item("Task a", "figure.walk"), item("Task b", "figure.run"), item("Task c", "dumbbell.fill")]
        let chips = [item("Chip a", "figure.walk"), item("Chip b", "figure.quidditch"), item("Chip c", "bed.double.fill"),
                     item("Leg day", "checklist")]
        var graded = scores("Leg day", raw: ["tasks": tasks, "chips": chips])
        XCTAssertEqual(graded.scores["none_dropped_by_the_app"], 1)
        XCTAssertEqual(graded.scores["none_cut_short"], 1)
        XCTAssertEqual(graded.scores["icons_known_share"], 6.0 / 7.0, "one invented symbol in seven")
        graded = scores("Leg day", raw: ["tasks": tasks, "chips": chips + [item("Skip dinner", "fork.knife")]])
        XCTAssertEqual(graded.scores["none_dropped_by_the_app"], 0, "the model sent five chips and four are shown")
        graded = scores("Leg day", raw: ["tasks": tasks, "chips": Array(chips.dropLast()) + [item("A very long title that runs past the chip", "checklist")]])
        XCTAssertEqual(graded.scores["none_cut_short"], 0)
        // The app bounds a title at 28 characters.
        graded = scores("Leg day", raw: ["tasks": tasks, "chips": [item(String(repeating: "a", count: 28), "checklist")]])
        XCTAssertEqual(graded.scores["none_cut_short"], 1)
        graded = scores("Leg day", raw: ["tasks": tasks, "chips": [item(String(repeating: "a", count: 29), "checklist")]])
        XCTAssertEqual(graded.scores["none_cut_short"], 0)
        XCTAssertNil(scores("Leg day").scores["icons_known_share"], "nothing to read without the model's reply")
    }

    func testChecklistDatasetBuildsTheAppsInputsAndFallsBackToThePresets() async throws {
        let cases = try coachCases("checklist_plan")
        checkCoachCases(cases) { inputs, summary in
            ChecklistPlanService.userPrompt(name: inputs.profile.name, direction: inputs.profile.pace.direction,
                                            dataSummary: summary, bio: inputs.profile.onboardingNote,
                                            memoryNotes: inputs.memory?.profileNotes ?? "")
        }
        // Both features read the same inputs, so the two datasets hold the same situations.
        XCTAssertEqual(cases.map(\.id), try coachCases("coach_prompts").map(\.id))
        let presets = ChecklistPlanService.fallback()
        XCTAssertTrue(presets.tasks.isEmpty)
        XCTAssertEqual(presets.chips.map(\.title), ChecklistSuggestion.all.map(\.title))
        for c in cases {
            let inputs = c.inputs()
            let unkeyed = await withNoKey { () -> Error? in
                do {
                    _ = try await ChecklistPlanService.make(profile: inputs.profile, foods: inputs.foods, weights: inputs.weights,
                                                            sessions: inputs.sessions, water: inputs.water, memory: inputs.memory)
                    return nil
                } catch { return error }
            }
            XCTAssertTrue(isMissingKey(unkeyed.result), "\(c.id): with no key the card keeps the presets")
            XCTAssertEqual(unkeyed.requests, 0, c.id)
        }
    }

    func testChecklistAttemptOnAScriptedModel() async throws {
        let item = try XCTUnwrap(try coachCases("checklist_plan").first { $0.id == "alex-lifter-bio-and-notes" })
        func entry(_ title: String, _ icon: String = "figure.walk") -> [String: Any] { ["title": title, "icon": icon] }
        let tasks = [entry("Leg day at the gym", "dumbbell.fill"), entry("Evening walk"), entry("Early night", "bed.double.fill")]
        let chips = [entry("Gym", "dumbbell.fill"), entry("Walk"), entry("Stretch", "figure.flexibility"), entry("Meal prep", "carrot.fill")]
        var outcome = await scripted([toolReply(["tasks": tasks, "chips": chips])]) { await LiveEvals.checklistAttempt(item) }
        XCTAssertTrue(outcome.ok); XCTAssertTrue(outcome.pass)
        XCTAssertEqual(outcome.scores["reflects_the_routine"], 1)
        XCTAssertEqual(outcome.scores["icons_known_share"], 1)
        XCTAssertTrue(outcome.output.contains("Leg day at the gym"))

        // The app's own filter drops a task about the scale; two tasks are left, under the minimum.
        outcome = await scripted([toolReply(["tasks": [tasks[0], tasks[1], entry("Morning weigh-in")], "chips": chips])]) {
            await LiveEvals.checklistAttempt(item)
        }
        XCTAssertTrue(outcome.ok); XCTAssertFalse(outcome.pass)
        XCTAssertEqual(outcome.scores["tasks_within_schema"], 0)
        XCTAssertEqual(outcome.scores["none_dropped_by_the_app"], 0)
        // Nothing left after cleaning: the service throws, the card keeps its presets, the reply is kept.
        outcome = await scripted([toolReply(["tasks": [entry("Skip dinner")], "chips": [entry("Start a diet")]])]) {
            await LiveEvals.checklistAttempt(item)
        }
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.output.contains("Skip dinner"))
        outcome = await scripted([serverError]) { await LiveEvals.checklistAttempt(item) }
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.error?.contains("boom") ?? false, outcome.error ?? "")
    }

    // MARK: - Every live evaluation can be asked for by name

    func testEveryLiveEvalIsNamedInTheRunScript() throws {
        let script = try String(contentsOf: evalsRoot.appendingPathComponent("run.sh"), encoding: .utf8)
        let usage = script.components(separatedBy: "set -euo pipefail")[0]
        // `run.sh <Name>` runs `LiveEvals/test<Name>`, so the names are the test methods'.
        let names = (LiveEvals.defaultTestSuite.tests).compactMap { test -> String? in
            guard let range = test.name.range(of: " test") else { return nil }
            return String(test.name[range.upperBound...].dropLast())
        }
        for added in ["InsightLine", "WeeklyReflection", "OnboardingNote", "MemoryFold", "ProgressSummary",
                      "FoodSuggestions", "CoachPrompts", "ChecklistPlan"] {
            XCTAssertTrue(names.contains(added), "LiveEvals has no test\(added)")
        }
        XCTAssertEqual(names.count, 12)
        for name in names {
            XCTAssertTrue(Graders.containsPhrase(usage, name), "Evals/run.sh does not list \(name) in its usage")
        }
        XCTAssertTrue(script.contains(#"-only-testing:"SproutEvals/LiveEvals/test${EVAL}""#))
    }
}
