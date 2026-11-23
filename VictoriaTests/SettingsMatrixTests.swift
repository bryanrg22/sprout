import SwiftData
import XCTest
@testable import Victoria

/// The settings matrix with NO adaptive plan: for each input a user can change, the derived
/// values that must move and, by exclusion, the ones that must not
/// (`docs/settings-dependencies.md`, table "No plan"). `SettingsMatrixPlanTests` is the same
/// matrix with a plan setting the targets.
///
/// Each row is run from every surface that can make the change (Settings, the coach's tool),
/// on a fresh world each time, and must give the same result from both. The fixture and its
/// numbers are in `SettingsWorld`.
@MainActor
final class SettingsMatrixTests: XCTestCase {

    private typealias Columns = Set<SettingsColumn>

    /// Runs one row from each surface on its own fresh world.
    private func row(_ label: String, moves: Columns, conditional: Columns = [],
                     file: StaticString = #filePath, line: UInt = #line,
                     surfaces: [(name: String, change: (SettingsWorld) -> Void)]) throws {
        for surface in surfaces {
            let world = try SettingsWorld(withPlan: false)
            assertRow("\(label) [\(surface.name)]", in: world, moves: moves, conditional: conditional,
                      file: file, line: line) { surface.change(world) }
        }
    }

    // MARK: - The goal

    /// Lose (relaxed, −250) → gain (lean gain, +250): 2678.68 → 3178.68, and the range
    /// becomes a single "at least" number. Yesterday's 2800 kcal no longer reaches the
    /// target, and an easing trend is no longer something to celebrate.
    func testGoalDirection() throws {
        try row("direction lose → gain",
                moves: [.calories, .macros, .widget, .coach, .buddy, .brief, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.pace = .leanGain } }),
                    ("coach", { w in w.viaCoach("set_goal_direction", ["direction": "gain"]) }),
                ])
    }

    /// Relaxed (−250) → steady (−500): 2678.68 → 2428.68, which the two 2600-kcal days now
    /// reach, so three days are nourished.
    func testPace() throws {
        try row("pace relaxed → steady",
                moves: [.calories, .macros, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.pace = .steady } }),
                    ("coach", { w in w.viaCoach("set_pace", ["pace": "steady"]) }),
                ])
    }

    /// Moderate (×1.55) → light (×1.375): TDEE 2928.68 → 2598.02, target 2348.02.
    func testActivityLevel() throws {
        try row("activity moderate → light",
                moves: [.calories, .macros, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.activityLevel = .light } }),
                    ("coach", { w in w.viaCoach("set_activity_level", ["level": "light"]) }),
                ])
    }

    /// A weigh-in of 185 a day after the last one moves the trend 200.503 → 198.36
    /// (α = 1 − e^(−1.04/7) = 0.138), so calories and every bodyweight-scaled macro move, and
    /// the protein target drops 164 → 162 g, which today's 163 g now reaches.
    ///
    /// Water does not move: with no goal of her own it is half the START weight (open, low).
    /// The brief is conditional: it changes only when the weekly rate crosses the band that
    /// `DailyBriefCard.trendEasedDown` celebrates (`SettingsMatrixValuesTests`).
    func testWeighIn() throws {
        try row("weigh-in 185",
                moves: [.calories, .macros, .widget, .coach, .buddy, .checklist, .achievements],
                conditional: [.brief],
                surfaces: [
                    ("Progress", { w in w.weighIn(185) }),
                    ("coach", { w in w.viaCoach("log_weight", ["weight": 185]) }),
                ])
    }

    /// Start weight 200 → 190. With weigh-ins logged the calorie basis is the trend, so
    /// calories and macros stay; the water goal with none of her own set is half the start
    /// weight, 100 → 95 oz, which yesterday's 97 oz reaches.
    func testStartWeight() throws {
        try row("start weight 200 → 190",
                moves: [.water, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.startWeightLbs = 190 } }),
                    ("coach", { w in w.viaCoach("set_start_weight", ["weight": 190]) }),
                ])
    }

    /// Goal weight 180 → 170: the chart line, the widget's "to goal", the buddy's view and
    /// what the coach is told. Never the calories: only pace sets the deficit.
    func testGoalWeight() throws {
        try row("goal weight 180 → 170",
                moves: [.widget, .coach, .buddy, .checklist],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.goalWeightLbs = 170 } }),
                    ("coach", { w in w.viaCoach("set_weight_goal", ["weight": 170]) }),
                ])
    }

    // MARK: - The body

    /// Height 180 → 170 cm: BMR −62.5, TDEE −96.88, target 2581.80 (now under 2600).
    /// Height is read-only in Settings; the coach's tool is the only way to change it.
    func testHeight() throws {
        try row("height 180 → 170",
                moves: [.calories, .macros, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [("coach", { w in w.viaCoach("set_height", ["cm": 170]) })])
    }

    /// Male → female: BMR −166, TDEE −257.3, target 2421.38; the safe floor 1500 → 1200.
    func testSex() throws {
        try row("sex male → female",
                moves: [.calories, .macros, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.sex = .female } }),
                    ("coach", { w in w.viaCoach("set_sex", ["sex": "female"]) }),
                ])
    }

    /// Age 30 → 45: BMR −75, TDEE −116.25, target 2562.43 (now under 2600).
    func testBirthDate() throws {
        try row("age 30 → 45",
                moves: [.calories, .macros, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [("coach", { w in w.viaCoach("set_birth_date", ["age": 45]) })])
    }

    // MARK: - Preferences

    /// Units change how weights are shown and typed, never what is stored (EVAL_REPORT 31):
    /// metric moves the widget (it gets kilograms), the coach (it is told and asked kilograms)
    /// and the checklist (its prompt carries the coach's context, now in kilograms). Nothing
    /// that depends on a stored value moves (`UnitsSafetyTests` checks the values themselves).
    func testUnits() throws {
        try row("units → metric", moves: [.widget, .coach, .checklist],
                surfaces: [("coach", { w in w.viaCoach("set_units", ["system": "metric"]) })])
        try row("a profile stored as metric", moves: [.widget, .coach, .checklist],
                surfaces: [("stored value", { w in w.inSettings { $0.unitSystem = .metric } })])
    }

    /// Step goal 8000 → 10000: today's 9000 steps no longer reach it. The checklist does not
    /// move: `ChecklistPlanService.make` builds its prompt without the steps rows, so the
    /// step goal is not in it.
    func testStepGoal() throws {
        try row("step goal 8000 → 10000",
                moves: [.widget, .coach, .buddy, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.dailyStepGoal = 10_000 } }),
                    ("coach", { w in w.viaCoach("set_step_goal", ["steps": 10_000]) }),
                ])
    }

    /// Steps count toward the budget: 9000 steps against the moderate baseline of 7500 earn
    /// (9000 − 7500) × 200.503 lb × 0.00035 = 105 kcal on the Today ring and the widget.
    ///
    /// Nothing else is told (open, `docs/settings-dependencies.md` N1): the Nutrients tab,
    /// the coach, the buddy snapshot, the companion and the achievements keep the target
    /// without the bonus. The coach column moves only because the tool's own description
    /// changes; `testStepBonusReachesOnlyTheRingAndTheWidget` pins the rest.
    func testStepsCountTowardBudget() throws {
        try row("steps add to budget: on",
                moves: [.calories, .widget],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.stepsAdjustCalories = true } }),
                    ("coach", { w in w.viaCoach("toggle_steps_in_budget", ["enabled": true]) }),
                ])
    }

    /// One drink: a 16.9 oz bottle → an 8 oz glass. The goal in ounces stays 100; it is now
    /// 13 glasses, not 6 bottles, wherever it is counted in drinks.
    func testWaterContainer() throws {
        try row("water container bottle → glass",
                moves: [.water, .coach, .checklist],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.waterContainerLabel = "glass"; $0.waterContainerOz = 8 } }),
                    ("coach", { w in w.viaCoach("set_water_container", ["oz": 8, "label": "glass"]) }),
                ])
    }

    /// Water goal: none of her own (100 oz) → 5 bottles = 84.5 oz, which yesterday's 97 oz reaches.
    func testWaterGoal() throws {
        try row("water goal → 5 bottles",
                moves: [.water, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.waterGoalOzOverride = 5 * 16.9 } }),
                    ("coach", { w in w.viaCoach("set_water_goal_containers", ["count": 5]) }),
                ])
    }

    /// Protein goal: computed 164 g → 150 g of her own, which today's 163 g reaches; carbs
    /// take up the difference. The coach's tool is the only way to set it.
    func testProteinGoal() throws {
        try row("protein goal → 150 g",
                moves: [.macros, .overrides, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [("coach", { w in w.viaCoach("set_protein_goal", ["grams": 150]) })])
    }

    /// Theme: the widget paints in it. Nothing computed reads it.
    func testTheme() throws {
        try row("theme cute → cool",
                moves: [.widget],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.themeStyle = .cool } }),
                    ("coach", { w in w.viaCoach("set_theme", ["theme": "cool"]) }),
                ])
    }

    /// The AI provider and a model override choose which client and model answer. No
    /// target, snapshot or prompt is computed from them.
    func testAIProviderAndModelOverride() throws {
        let world = try SettingsWorld(withPlan: false)
        let before = world.derived()

        let scoped = AIRuntime(provider: .openai, apiKey: "test-key-not-real")
        let underOpenAI = AIRuntime.$current.withValue(scoped) { world.derived() }
        XCTAssertEqual(underOpenAI, before, "switching the provider moved a derived value")

        let previous = AIConfig.modelOverride(for: .anthropic, tier: .coach)
        defer { AIConfig.setModelOverride(previous, for: .anthropic, tier: .coach) }
        AIConfig.setModelOverride("some-other-model", for: .anthropic, tier: .coach)
        XCTAssertEqual(world.derived(), before, "a model override moved a derived value")
    }

    // MARK: - The plan

    /// A plan is built (floor 2300, ceiling 2500, protein 180): its numbers become the
    /// targets everywhere. 2300 is reached on all three logged days.
    func testPlanBuilt() throws {
        let world = try SettingsWorld(withPlan: false)
        defer { world.tearDown() }
        assertRow("plan built", in: world,
                  moves: [.calories, .macros, .planFlag, .overrides, .widget, .coach, .buddy,
                          .checklist, .achievements]) {
            world.buildPlan(floor: 2300, ceiling: 2500, protein: 180)
        }
        XCTAssertEqual(world.derived()[.planFlag], "clear", "a new plan matches the goals it was built for")
    }
}
