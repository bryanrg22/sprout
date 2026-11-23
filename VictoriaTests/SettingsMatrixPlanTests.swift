import SwiftData
import XCTest
@testable import Victoria

/// The settings matrix WITH an adaptive plan setting the targets
/// (`docs/settings-dependencies.md`, table "Plan active"), and the behaviour EVAL_REPORT 3
/// L-B2 asked for: a change of goal direction sets the plan's numbers aside at once and
/// reversibly; any other change to what the plan was built around keeps the numbers and
/// raises the rebuild notice.
///
/// The plan in `SettingsWorld` was written for a loss goal: floor 2300, ceiling 2500,
/// protein 180 g. With it the targets are 2300 kcal, P 180 / C 231 / F 73
/// (carbs = (2300 − 180 × 4 − 72.76 × 9) / 4).
@MainActor
final class SettingsMatrixPlanTests: XCTestCase {

    private typealias Columns = Set<SettingsColumn>

    private func row(_ label: String, moves: Columns, conditional: Columns = [],
                     file: StaticString = #filePath, line: UInt = #line,
                     surfaces: [(name: String, change: (SettingsWorld) -> Void)]) throws {
        for surface in surfaces {
            let world = try SettingsWorld(withPlan: true)
            defer { world.tearDown() }
            assertRow("\(label) [\(surface.name)]", in: world, moves: moves, conditional: conditional,
                      file: file, line: line) { surface.change(world) }
        }
    }

    // MARK: - The matrix

    /// Lose → gain: the loss plan's 2300 kcal and 180 g stop being the targets. They are the
    /// computed gain targets, 3178.68 kcal as a single number and 164 g, and the plan is flagged.
    func testGoalDirection() throws {
        try row("direction lose → gain",
                moves: [.calories, .macros, .planFlag, .overrides, .widget, .coach, .buddy, .brief,
                        .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.pace = .leanGain } }),
                    ("coach", { w in w.viaCoach("set_goal_direction", ["direction": "gain"]) }),
                ])
    }

    /// Pace within the direction: the plan's numbers stay, the plan is flagged, and the
    /// coach is told both the new pace and that the plan is stale.
    func testPace() throws {
        try row("pace relaxed → steady",
                moves: [.planFlag, .coach, .checklist],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.pace = .steady } }),
                    ("coach", { w in w.viaCoach("set_pace", ["pace": "steady"]) }),
                ])
    }

    /// Activity level: the plan's numbers stay and the plan is flagged. The coach's data is
    /// unchanged (the plan sets the calories), so only the note about the plan is new, and
    /// the checklist prompt, which is built from the data alone, does not move.
    func testActivityLevel() throws {
        try row("activity moderate → light",
                moves: [.planFlag, .coach],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.activityLevel = .light } }),
                    ("coach", { w in w.viaCoach("set_activity_level", ["level": "light"]) }),
                ])
    }

    /// A weigh-in does not move the plan's calories or protein and does not flag the plan:
    /// following the trend is what the plan's review is for. Fat and carbs are still scaled
    /// to bodyweight (fat 0.8 g/kg: 73 → 72 g), so the macro split moves.
    func testWeighIn() throws {
        try row("weigh-in 185",
                moves: [.macros, .widget, .coach, .buddy, .checklist],
                conditional: [.brief],
                surfaces: [
                    ("Progress", { w in w.weighIn(185) }),
                    ("coach", { w in w.viaCoach("log_weight", ["weight": 185]) }),
                ])
    }

    func testStartWeight() throws {
        try row("start weight 200 → 190",
                moves: [.water, .planFlag, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.startWeightLbs = 190 } }),
                    ("coach", { w in w.viaCoach("set_start_weight", ["weight": 190]) }),
                ])
    }

    /// The coach's `set_weight_goal` did not flag the plan before; Settings did.
    func testGoalWeight() throws {
        try row("goal weight 180 → 170",
                moves: [.planFlag, .widget, .coach, .buddy, .checklist],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.goalWeightLbs = 170 } }),
                    ("coach", { w in w.viaCoach("set_weight_goal", ["weight": 170]) }),
                ])
    }

    /// Height, sex and age are what her energy needs are computed from. With a plan the
    /// plan's numbers stay, so the only things that move are the flag and the coach's note.
    func testHeight() throws {
        try row("height 180 → 170", moves: [.planFlag, .coach],
                surfaces: [("coach", { w in w.viaCoach("set_height", ["cm": 170]) })])
    }

    func testSex() throws {
        try row("sex male → female", moves: [.planFlag, .coach],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.sex = .female } }),
                    ("coach", { w in w.viaCoach("set_sex", ["sex": "female"]) }),
                ])
    }

    func testBirthDate() throws {
        try row("age 30 → 45", moves: [.planFlag, .coach],
                surfaces: [("coach", { w in w.viaCoach("set_birth_date", ["age": 45]) })])
    }

    func testUnits() throws {
        try row("units → metric", moves: [],
                surfaces: [("coach", { w in w.viaCoach("set_units", ["system": "metric"]) })])
        try row("a profile stored as metric", moves: [.coach],
                surfaces: [("stored value", { w in w.inSettings { $0.unitSystem = .metric } })])
    }

    func testStepGoal() throws {
        try row("step goal 8000 → 10000",
                moves: [.widget, .coach, .buddy, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.dailyStepGoal = 10_000 } }),
                    ("coach", { w in w.viaCoach("set_step_goal", ["steps": 10_000]) }),
                ])
    }

    /// The step bonus is added on top of the plan's floor and ceiling: ring 2300 → 2405.
    func testStepsCountTowardBudget() throws {
        try row("steps add to budget: on",
                moves: [.calories, .widget],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.stepsAdjustCalories = true } }),
                    ("coach", { w in w.viaCoach("toggle_steps_in_budget", ["enabled": true]) }),
                ])
    }

    func testWaterContainer() throws {
        try row("water container bottle → glass",
                moves: [.water, .coach, .checklist],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.waterContainerLabel = "glass"; $0.waterContainerOz = 8 } }),
                    ("coach", { w in w.viaCoach("set_water_container", ["oz": 8, "label": "glass"]) }),
                ])
    }

    func testWaterGoal() throws {
        try row("water goal → 5 bottles",
                moves: [.water, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.waterGoalOzOverride = 5 * 16.9 } }),
                    ("coach", { w in w.viaCoach("set_water_goal_containers", ["count": 5]) }),
                ])
    }

    /// With a plan the protein goal lives on the plan: 180 → 150 g, which today's 163 g reaches.
    func testProteinGoal() throws {
        try row("protein goal → 150 g",
                moves: [.macros, .overrides, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [("coach", { w in w.viaCoach("set_protein_goal", ["grams": 150]) })])
    }

    func testTheme() throws {
        try row("theme cute → cool", moves: [.widget],
                surfaces: [
                    ("Settings", { w in w.inSettings { $0.themeStyle = .cool } }),
                    ("coach", { w in w.viaCoach("set_theme", ["theme": "cool"]) }),
                ])
    }

    /// The plan's targets edited through the coach (floor 2700, ceiling 2900, protein 160):
    /// only the day of 2800 kcal reaches the new floor, and today's 163 g reaches the protein.
    func testPlanEdited() throws {
        try row("plan edited",
                moves: [.calories, .macros, .overrides, .widget, .coach, .buddy, .checklist, .achievements],
                surfaces: [("coach", { w in
                    w.viaCoach("edit_plan", ["calorie_min": 2700, "calorie_max": 2900, "protein_target": 160,
                                             "change_note": "Raised the range."])
                })])
    }

    /// A rebuild replaces the numbers in the same row and clears the flag.
    func testPlanRebuilt() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        world.inSettings { $0.pace = .steady }
        XCTAssertEqual(world.derived()[.planFlag], "flagged")
        assertRow("plan rebuilt", in: world,
                  moves: [.calories, .macros, .planFlag, .overrides, .widget, .coach, .buddy,
                          .checklist, .achievements]) {
            world.buildPlan(floor: 2700, ceiling: 2900, protein: 160)
        }
        XCTAssertEqual(world.derived()[.planFlag], "clear")
    }

    // MARK: - L-B2: direction sets the plan's numbers aside, and it is reversible

    /// The exact numbers on each side of a direction change, from both surfaces.
    func testDirectionChangeFallsBackToComputedTargets() throws {
        let surfaces: [(String, (SettingsWorld) -> Void)] = [
            ("Settings", { w in w.inSettings { $0.pace = .leanGain } }),
            ("coach", { w in w.viaCoach("set_goal_direction", ["direction": "gain"]) }),
        ]
        for (name, change) in surfaces {
            let world = try SettingsWorld(withPlan: true)
            defer { world.tearDown() }
            let profile = world.profile, basis = world.basisWeight

            // The plan drives: its floor, its ceiling, its protein.
            XCTAssertEqual(profile.dailyCalorieTarget(weightLbs: basis), 2300, name)
            XCTAssertEqual(profile.calorieGoalRange(weightLbs: basis).high, 2500, name)
            XCTAssertEqual(profile.macroTargets(weightLbs: basis).proteinG, 180, name)

            change(world)

            // TDEE 2928.68 + 250 (lean gain) = 3178.68, a single number; protein 1.8 g/kg = 164.
            XCTAssertEqual(profile.dailyCalorieTarget(weightLbs: basis), 3178.68, accuracy: 0.01, name)
            XCTAssertEqual(profile.calorieGoalRange(weightLbs: basis).high, .infinity, name)
            XCTAssertEqual(profile.macroTargets(weightLbs: basis).proteinG, 164, name)
            XCTAssertEqual(profile.calorieTargetOverride, 0, name)
            XCTAssertEqual(profile.calorieMaxOverride, 0, name)
            XCTAssertEqual(profile.proteinTargetOverride, 0, name)
            XCTAssertEqual(world.plan?.goalsChangedSinceBuild, true, name)
            XCTAssertTrue(PlanTargetSync.isSuspended(plan: world.plan, for: profile), name)

            // The plan itself is untouched: that is what makes this reversible.
            XCTAssertEqual(world.plan?.calorieMin, 2300, name)
            XCTAssertEqual(world.plan?.calorieMax, 2500, name)
            XCTAssertEqual(world.plan?.proteinTarget, 180, name)
        }
    }

    /// Switching back before a rebuild restores the plan's numbers. The notice stays: the
    /// goals did change, and only a rebuild clears it.
    func testSwitchingDirectionBackRestoresThePlansNumbers() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        let before = world.derived()

        world.inSettings { $0.pace = .leanGain }
        XCTAssertNotEqual(world.derived()[.calories], before[.calories])

        world.inSettings { $0.pace = .relaxed }
        var after = world.derived()
        XCTAssertEqual(after[.planFlag], "flagged")
        XCTAssertEqual(world.profile.calorieTargetOverride, 2300)
        XCTAssertEqual(world.profile.calorieMaxOverride, 2500)
        XCTAssertEqual(world.profile.proteinTargetOverride, 180)
        XCTAssertFalse(PlanTargetSync.isSuspended(plan: world.plan, for: world.profile))
        // Every number is back. The flag and the coach's note about it are the only difference.
        for column: SettingsColumn in [.planFlag, .coach] { after[column] = before[column] }
        XCTAssertEqual(after, before)
    }

    /// Undo of the coach's direction change puts everything back, the flag included.
    func testUndoOfTheCoachsDirectionChangeRestoresEverything() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        let before = world.derived()
        let applied = world.viaCoach("set_goal_direction", ["direction": "gain"])
        XCTAssertNotEqual(world.derived(), before)
        try XCTUnwrap(applied?.undo)()
        XCTAssertEqual(world.derived(), before)
    }

    /// The tool result tells the model what happened to the plan, in both directions.
    func testTheCoachIsToldThePlanWasSetAside() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        let away = try XCTUnwrap(world.viaCoach("set_goal_direction", ["direction": "gain"]))
        XCTAssertTrue(away.message.contains("set aside"), away.message)
        XCTAssertFalse(away.message.contains("still drives"), away.message)
        let back = try XCTUnwrap(world.viaCoach("set_goal_direction", ["direction": "lose"]))
        XCTAssertTrue(back.message.contains("driving her targets"), back.message)
        // And the standing context says so for every later turn while it is set aside.
        world.viaCoach("set_goal_direction", ["direction": "gain"])
        XCTAssertTrue(PlanGoalsCopy.coachNote(plan: world.plan, profile: world.profile).contains("set its calorie range and protein target aside"))
    }

    /// Lose → maintain is a change of direction too: a deficit plan is not a maintenance plan.
    func testMaintainIsADirection() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        world.inSettings { $0.pace = .maintain }
        // TDEE 2928.68, no adjustment; lose/maintain keep a band of +150.
        XCTAssertEqual(world.profile.dailyCalorieTarget(weightLbs: world.basisWeight), 2928.68, accuracy: 0.01)
        XCTAssertEqual(world.profile.calorieGoalRange(weightLbs: world.basisWeight).high, 3078.68, accuracy: 0.01)
    }

    /// While the plan is set aside, a number set through the coach is set for the goal she
    /// has now, so it drives; the rest of the plan stays set aside.
    func testANumberSetWhileSetAsideDrivesAndTheRestDoesNot() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        world.inSettings { $0.pace = .leanGain }

        world.viaCoach("set_protein_goal", ["grams": 170])
        XCTAssertEqual(world.profile.proteinTargetOverride, 170, "her own protein number for the gain goal")
        XCTAssertEqual(world.profile.calorieTargetOverride, 0, "the loss plan's calories stay out")
        XCTAssertEqual(world.profile.dailyCalorieTarget(weightLbs: world.basisWeight), 3178.68, accuracy: 0.01)

        world.viaCoach("edit_plan", ["calorie_min": 3100, "calorie_max": 3300, "change_note": "Gain range."])
        XCTAssertEqual(world.profile.calorieTargetOverride, 3100)
        XCTAssertFalse(PlanTargetSync.isSuspended(plan: world.plan, for: world.profile))

        // Back to a loss goal: those two numbers were written for gain, so they step aside.
        world.inSettings { $0.pace = .relaxed }
        XCTAssertEqual(world.profile.calorieTargetOverride, 0)
        XCTAssertEqual(world.profile.proteinTargetOverride, 0)
    }

    /// A ceiling alone does not bring a set-aside floor back.
    func testACeilingAloneDoesNotReviveTheOldFloor() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        world.inSettings { $0.pace = .leanGain }
        world.viaCoach("edit_plan", ["calorie_max": 3400, "change_note": "Ceiling."])
        XCTAssertEqual(world.profile.calorieTargetOverride, 0)
        XCTAssertEqual(world.profile.dailyCalorieTarget(weightLbs: world.basisWeight), 3178.68, accuracy: 0.01)
    }

    // MARK: - L-B2: every other plan input raises the notice and keeps the numbers

    func testEveryPlanInputFlagsThePlanAndKeepsItsNumbers() throws {
        let changes: [(String, (SettingsWorld) -> Void)] = [
            ("pace, Settings", { w in w.inSettings { $0.pace = .ambitious } }),
            ("pace, coach", { w in w.viaCoach("set_pace", ["pace": "ambitious"]) }),
            ("activity, Settings", { w in w.inSettings { $0.activityLevel = .veryActive } }),
            ("activity, coach", { w in w.viaCoach("set_activity_level", ["level": "veryActive"]) }),
            ("goal weight, Settings", { w in w.inSettings { $0.goalWeightLbs = 175 } }),
            ("goal weight, coach", { w in w.viaCoach("set_weight_goal", ["weight": 175]) }),
            ("start weight, Settings", { w in w.inSettings { $0.startWeightLbs = 205 } }),
            ("start weight, coach", { w in w.viaCoach("set_start_weight", ["weight": 205]) }),
            ("sex, Settings", { w in w.inSettings { $0.sex = .female } }),
            ("height, coach", { w in w.viaCoach("set_height", ["cm": 175]) }),
            ("age, coach", { w in w.viaCoach("set_birth_date", ["age": 40]) }),
        ]
        for (name, change) in changes {
            let world = try SettingsWorld(withPlan: true)
            defer { world.tearDown() }
            XCTAssertEqual(world.plan?.goalsChangedSinceBuild, false, name)
            change(world)
            XCTAssertEqual(world.plan?.goalsChangedSinceBuild, true, "\(name) raised no notice")
            XCTAssertEqual(world.profile.calorieTargetOverride, 2300, name)
            XCTAssertEqual(world.profile.calorieMaxOverride, 2500, name)
            XCTAssertEqual(world.profile.proteinTargetOverride, 180, name)
            XCTAssertEqual(world.profile.dailyCalorieTarget(weightLbs: world.basisWeight), 2300, name)
        }
    }

    /// What is not a plan input raises no notice.
    func testOtherSettingsDoNotFlagThePlan() throws {
        let changes: [(String, (SettingsWorld) -> Void)] = [
            ("weigh-in", { w in w.viaCoach("log_weight", ["weight": 199]) }),
            ("step goal", { w in w.inSettings { $0.dailyStepGoal = 9000 } }),
            ("water goal", { w in w.viaCoach("set_water_goal_containers", ["count": 7]) }),
            ("theme", { w in w.viaCoach("set_theme", ["theme": "cool"]) }),
            ("protein goal", { w in w.viaCoach("set_protein_goal", ["grams": 150]) }),
            ("a food log", { w in w.viaCoach("log_food", ["name": "Banana", "meal": "snack", "calories": 105,
                                                          "protein_g": 1.3, "carbs_g": 27, "fat_g": 0.4]) }),
        ]
        for (name, change) in changes {
            let world = try SettingsWorld(withPlan: true)
            defer { world.tearDown() }
            change(world)
            XCTAssertEqual(world.plan?.goalsChangedSinceBuild, false, "\(name) flagged the plan")
        }
    }

    /// Undoing the change that raised the notice takes the notice away; a notice that was
    /// already there stays.
    func testUndoClearsOnlyTheNoticeItRaised() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        let pace = try XCTUnwrap(world.viaCoach("set_pace", ["pace": "steady"]))
        XCTAssertEqual(world.plan?.goalsChangedSinceBuild, true)
        try XCTUnwrap(pace.undo)()
        XCTAssertEqual(world.plan?.goalsChangedSinceBuild, false)

        world.inSettings { $0.goalWeightLbs = 175 }
        let again = try XCTUnwrap(world.viaCoach("set_pace", ["pace": "steady"]))
        try XCTUnwrap(again.undo)()
        XCTAssertEqual(world.plan?.goalsChangedSinceBuild, true, "the goal-weight change is still unanswered")
    }

    // MARK: - A plan from before the direction record existed

    /// Such a plan is taken to be written for the direction in force when it is first seen,
    /// so the first direction change after the update already sets it aside.
    func testAPlanWithNoRecordIsAnchoredToTheDirectionInForceBeforeTheChange() throws {
        for surface in ["Settings", "coach"] {
            let world = try SettingsWorld(withPlan: true)
            defer { world.tearDown() }
            world.plan?.caloriesDirection = nil
            world.plan?.proteinDirection = nil
            if surface == "Settings" { world.inSettings { $0.pace = .leanGain } }
            else { world.viaCoach("set_goal_direction", ["direction": "gain"]) }
            XCTAssertEqual(world.plan?.caloriesDirection, .lose, surface)
            XCTAssertEqual(world.profile.calorieTargetOverride, 0, surface)
        }
    }

    /// A plan with no record that is already flagged could have been built for either
    /// direction, so its numbers are left driving, as they were before this change.
    func testAFlaggedPlanWithNoRecordKeepsDriving() throws {
        let world = try SettingsWorld(withPlan: true)
        defer { world.tearDown() }
        world.plan?.caloriesDirection = nil
        world.plan?.proteinDirection = nil
        world.plan?.markGoalsChanged()
        world.inSettings { $0.pace = .leanGain }
        XCTAssertNil(world.plan?.caloriesDirection)
        XCTAssertEqual(world.profile.calorieTargetOverride, 2300)
    }
}
