import XCTest
@testable import Victoria

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

    // MARK: - Number preservation

    func testNumbersAreNormalized() {
        XCTAssertEqual(Graders.numbers(in: "15,420 steps, HR 59, 7.5 h. Day 3."), [15420, 59, 7.5, 3])
        XCTAssertEqual(Graders.numbers(in: "no digits here"), [])
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
        let all = try rows("coach_tool_choice/v1.jsonl", as: Graders.ToolExpectation.self)
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

    func testCoachDatasetDecodesAndUsesRealActionNames() throws {
        let cases = try rows("coach_tool_choice/v1.jsonl", as: Graders.ToolExpectation.self)
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
}
