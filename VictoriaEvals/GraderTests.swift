import UIKit
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
}
