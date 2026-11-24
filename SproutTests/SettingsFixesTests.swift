import SwiftData
import XCTest
@testable import Sprout

/// The smaller defects fixed with the settings matrix (audit-lifecycle B18, B20, B22), and
/// the sentences in Settings and on the plan card that say what a change does (L-B2).
@MainActor
final class SettingsFixesTests: XCTestCase {

    // MARK: - B18: height not in whole inches

    /// Feet came from the truncated inches and inches from the rounded inches, so 182 cm
    /// (71.65 in) read 5′0″.
    func testHeightIsRoundedBeforeItIsSplit() {
        XCTAssertEqual(SettingsCopy.heightText(cm: 182), "6′0″ (182 cm)")
        XCTAssertEqual(SettingsCopy.heightText(cm: 152), "5′0″ (152 cm)")       // 59.84 in
        XCTAssertEqual(SettingsCopy.heightText(cm: 181), "5′11″ (181 cm)")      // 71.26 in
        XCTAssertEqual(SettingsCopy.heightText(cm: 213), "7′0″ (213 cm)")       // 83.86 in
    }

    /// Every height the onboarding stepper can produce (whole inches) reads back as itself.
    func testWholeInchHeightsAreUnchanged() {
        for inches in 48...84 {
            let h = SettingsCopy.feetAndInches(cm: Double(inches) * 2.54)
            XCTAssertEqual(h.feet * 12 + h.inches, inches)
            XCTAssertLessThan(h.inches, 12)
        }
    }

    // MARK: - B20: "Reset to recommended (N)"

    /// The button showed half the TREND weight and applied half the START weight. What it
    /// shows is now the number it applies.
    func testResetToRecommendedAppliesTheNumberItShows() throws {
        let w = try SettingsWorld(withPlan: false)
        w.inSettings { $0.startWeightLbs = 200; $0.waterGoalOzOverride = 5 * 16.9 }
        w.weighIn(150)                                        // the trend is now well under 200
        XCTAssertLessThan(w.basisWeight, 195)

        let shown = w.profile.recommendedWaterOz              // the button's label
        w.inSettings { $0.waterGoalOzOverride = 0 }           // the button's action
        XCTAssertEqual(w.profile.waterTargetOz, shown)
        XCTAssertEqual(shown, 100)                            // 0.5 × start weight 200
    }

    func testRecommendedWaterWithNoStartWeightUsesTheDefaultWeight() {
        let profile = UserProfile()
        profile.startWeightLbs = 0
        XCTAssertEqual(profile.recommendedWaterOz, 75)        // 0.5 × 150
    }

    // MARK: - B22: start weight used as the current weight

    /// The companion judged "enough food" at the start weight while the ring used the trend.
    /// Start 200, trend 170: the companion's target was 2675 kcal and the ring's 2464. Now
    /// they are one number.
    func testCompanionUsesTheSameBasisWeightAsTheRing() throws {
        let w = try SettingsWorld(withPlan: false)
        for entry in w.weights { w.context.delete(entry) }
        w.context.insert(WeightEntry(date: w.now, weightLbs: 170))
        try w.context.save()
        let basis = w.basisWeight
        XCTAssertEqual(basis, 170)

        let ring = w.profile.dailyCalorieTarget(weightLbs: basis)
        let companion = CompanionTargets(profile: w.profile, basisWeightLbs: basis)
        XCTAssertEqual(companion.calories, ring)
        XCTAssertEqual(companion.proteinG, w.profile.macroTargets(weightLbs: basis).proteinG)
        // 170 lb = 77.111 kg: BMR 771.11 + 1125 − 150 + 5 = 1751.11; × 1.55 − 250 = 2464.22.
        XCTAssertEqual(companion.calories, 2464.22, accuracy: 0.01)
        // At the start weight, 200 lb = 90.719 kg: BMR 1887.19; × 1.55 − 250 = 2675.14.
        XCTAssertEqual(w.profile.dailyCalorieTarget(weightLbs: 200), 2675.14, accuracy: 0.01)
    }

    /// A preview has no weigh-ins to hand over; the start weight stands in, as before.
    func testCompanionWithoutABasisWeightFallsBackToTheStartWeight() {
        let profile = UserProfile()
        profile.startWeightLbs = 180
        XCTAssertEqual(CompanionTargets(profile: profile, basisWeightLbs: nil).calories,
                       profile.dailyCalorieTarget(weightLbs: 180))
    }

    /// Loss goal, started at 180, now at 150. A goal of 160 is above where she is.
    func testGoalWeightIsCheckedAgainstTheCurrentWeightNotTheStartWeight() {
        let profile = UserProfile()
        profile.pace = .relaxed
        profile.startWeightLbs = 180
        func result(_ goal: Double, current: Double?) -> CoachTools.ParseResult {
            CoachTools.parse(name: "set_weight_goal", input: ["weight": goal], profile: profile,
                             currentWeightLbs: current)
        }
        guard case .invalid(let reason) = result(160, current: 150) else {
            return XCTFail("a loss goal above the current weight was accepted")
        }
        XCTAssertTrue(reason.contains("below your current 150 lb"), reason)
        guard case .ok = result(140, current: 150) else { return XCTFail("140 is below 150") }
        // With no weigh-ins to go by, the start weight stands in.
        guard case .ok = result(160, current: nil) else { return XCTFail("160 is below the start weight") }

        profile.pace = .leanGain
        guard case .invalid = result(175, current: 190) else {
            return XCTFail("a gain goal below the current weight was accepted")
        }
        guard case .ok = result(200, current: 190) else { return XCTFail("200 is above 190") }
    }

    /// After a direction switch the coach is told when the goal weight is on the wrong side
    /// of where she is NOW: start 200, trend 170, goal 180, switching to lose.
    func testDirectionSwitchChecksTheGoalAgainstTheTrend() throws {
        let w = try SettingsWorld(withPlan: false)
        for entry in w.weights { w.context.delete(entry) }
        w.context.insert(WeightEntry(date: w.now, weightLbs: 170))
        w.profile.pace = .leanGain
        try w.context.save()
        let applied = try XCTUnwrap(w.viaCoach("set_goal_direction", ["direction": "lose"]))
        XCTAssertTrue(applied.message.contains("wrong side of their current weight"),
                      "goal 180 is above the current 170: \(applied.message)")
    }

    // MARK: - L-B2: the copy says what happens

    private func goalsFooter(_ source: SettingsCopy.TargetSource) -> String {
        SettingsCopy.goalsFooter(startWeightLbs: 200, goalWeightLbs: 180, currentWeightLbs: 195,
                                 pace: .relaxed, source: source)
    }

    func testGoalsFooterDoesNotPromiseWhatAPlanPrevents() {
        let withPlan = goalsFooter(.plan)
        XCTAssertFalse(withPlan.contains("right away"), "with a plan, pace and weights do not move the targets")
        XCTAssertTrue(withPlan.contains("Your adaptive plan sets your daily targets."))
        XCTAssertTrue(withPlan.contains("sets the plan's numbers aside"))
        XCTAssertTrue(withPlan.contains("marks the plan for a rebuild"))

        let setAside = goalsFooter(.planSetAside)
        XCTAssertTrue(setAside.contains("built for a different goal"))
        XCTAssertTrue(setAside.contains("switch the goal back"))

        let calculated = goalsFooter(.calculated)
        XCTAssertTrue(calculated.hasPrefix("Started at 200 lb → aiming for 180 lb at a relaxed pace."))
        XCTAssertTrue(calculated.contains("Goal and pace change your daily calories right away."))
        XCTAssertTrue(calculated.contains("move your chart, not your calories"),
                      "goal weight and starting weight never were calorie inputs")
    }

    /// The heads-up about a goal on the wrong side used to replace the sentence about what
    /// changing does; both are shown now.
    func testGoalsFooterKeepsTheHeadsUp() {
        let text = SettingsCopy.goalsFooter(startWeightLbs: 200, goalWeightLbs: 210, currentWeightLbs: 195,
                                            pace: .relaxed, source: .plan)
        XCTAssertTrue(text.contains("Heads-up: your goal weight is at or above where you are now"))
        XCTAssertTrue(text.contains("Your adaptive plan sets your daily targets."))
    }

    func testTargetsFooterNamesWhatSetsTheTargets() {
        let plan = SettingsCopy.targetsFooter(source: .plan, planFloor: 2300, planProtein: 180,
                                              clampedToFloor: false, coachName: "Vita")
        XCTAssertTrue(plan.hasPrefix("Set by your adaptive plan — floor 2300 kcal, protein 180 g."))
        let aside = SettingsCopy.targetsFooter(source: .planSetAside, planFloor: 0, planProtein: 0,
                                               clampedToFloor: false, coachName: "Vita")
        XCTAssertTrue(aside.contains("its numbers are set aside until you rebuild it"))
        XCTAssertFalse(aside.contains("Set by your adaptive plan"))
        let floor = SettingsCopy.targetsFooter(source: .calculated, planFloor: 0, planProtein: 0,
                                               clampedToFloor: true, coachName: "Vita")
        XCTAssertTrue(floor.contains("safe minimum"))
    }

    func testTargetSource() {
        XCTAssertEqual(SettingsCopy.targetSource(hasPlanNumbers: false, suspended: false), .calculated)
        XCTAssertEqual(SettingsCopy.targetSource(hasPlanNumbers: true, suspended: false), .plan)
        XCTAssertEqual(SettingsCopy.targetSource(hasPlanNumbers: true, suspended: true), .planSetAside)
    }

    func testPlanCardNoticeSaysWhetherTheNumbersStillApply() {
        XCTAssertTrue(PlanGoalsCopy.bannerBody(suspended: true).contains("set aside"))
        XCTAssertTrue(PlanGoalsCopy.bannerBody(suspended: false).contains("still set your daily targets"))
    }

    // MARK: - PlanTargetSync: the rule itself

    private func plan(calories: GoalPace.Direction?, protein: GoalPace.Direction?) -> PlanTargetSync.PlanTargets {
        .init(hasRange: true, calorieMin: 1600, calorieMax: 1750, proteinTarget: 120,
              caloriesDirection: calories, proteinDirection: protein)
    }

    func testNumbersWrittenForAnotherDirectionAreNotMirrored() {
        let loss = plan(calories: .lose, protein: .lose)
        XCTAssertEqual(PlanTargetSync.overrides(plan: loss, currentProtein: 120, direction: .lose),
                       .init(calorie: 1600, calorieMax: 1750, protein: 120))
        for other in [GoalPace.Direction.gain, .maintain] {
            XCTAssertEqual(PlanTargetSync.overrides(plan: loss, currentProtein: 120, direction: other),
                           .init(calorie: 0, calorieMax: 0, protein: 0))
            XCTAssertTrue(PlanTargetSync.isSuspended(plan: loss, direction: other))
        }
        XCTAssertFalse(PlanTargetSync.isSuspended(plan: loss, direction: .lose))
    }

    func testCaloriesAndProteinAreJudgedSeparately() {
        let mixed = plan(calories: .lose, protein: .gain)
        XCTAssertEqual(PlanTargetSync.overrides(plan: mixed, currentProtein: 0, direction: .gain),
                       .init(calorie: 0, calorieMax: 0, protein: 120))
        XCTAssertEqual(PlanTargetSync.overrides(plan: mixed, currentProtein: 0, direction: .lose),
                       .init(calorie: 1600, calorieMax: 1750, protein: 0))
    }

    /// No record of the direction (a plan from before the record existed): mirrored as before.
    func testAnUnknownDirectionIsMirrored() {
        let unknown = plan(calories: nil, protein: nil)
        XCTAssertEqual(PlanTargetSync.overrides(plan: unknown, currentProtein: 0, direction: .gain),
                       .init(calorie: 1600, calorieMax: 1750, protein: 120))
        XCTAssertFalse(PlanTargetSync.isSuspended(plan: unknown, direction: .gain))
        XCTAssertFalse(PlanTargetSync.isSuspended(plan: nil, direction: .gain))
    }

    func testDirectionRecordSurvivesItsStoredSpelling() {
        for direction in [GoalPace.Direction.lose, .maintain, .gain] {
            XCTAssertEqual(GoalPace.Direction(storedName: direction.storedName), direction)
        }
        XCTAssertNil(GoalPace.Direction(storedName: "sideways"))
    }
}
