import SwiftData
import XCTest
@testable import Victoria

/// The exact values behind the settings matrix, derived from the formulas in
/// `NutritionMath` and `UserProfile+Targets`, plus the cells the matrix leaves conditional
/// or records as open. The fixture and its base numbers are in `SettingsWorld`.
@MainActor
final class SettingsMatrixValuesTests: XCTestCase {

    private func world() throws -> SettingsWorld { try SettingsWorld(withPlan: false) }

    // MARK: - The fixture is what its header says

    func testBaseNumbers() throws {
        let w = try world()
        let p = w.profile, basis = w.basisWeight
        // EWMA with 7-day smoothing: 202 → 202 + (1 − e⁻¹)(201 − 202) = 201.368 → 200.503.
        XCTAssertEqual(basis, 200.5032, accuracy: 0.0005)
        XCTAssertEqual(TrendCalculator.ratePerWeek(w.weights), -0.748, accuracy: 0.005)
        XCTAssertEqual(p.ageYears, 30)
        // BMR = 10 × 90.947 kg + 6.25 × 180 cm − 5 × 30 + 5 = 1889.47; × 1.55 = 2928.68; − 250.
        XCTAssertEqual(p.bmr(weightLbs: basis), 1889.47, accuracy: 0.01)
        XCTAssertEqual(p.tdee(weightLbs: basis), 2928.68, accuracy: 0.01)
        XCTAssertEqual(p.dailyCalorieTarget(weightLbs: basis), 2678.68, accuracy: 0.01)
        // Loss: a band of +150 above the target.
        XCTAssertEqual(p.calorieGoalRange(weightLbs: basis).high, 2828.68, accuracy: 0.01)
        // Protein 1.8 g/kg = 163.7, fat 0.8 g/kg = 72.8, carbs (2678.68 − 654.82 − 654.82) / 4 = 342.3.
        let macros = p.macroTargets(weightLbs: basis)
        XCTAssertEqual(macros.proteinG, 164)
        XCTAssertEqual(macros.fatG, 73)
        XCTAssertEqual(macros.carbsG, 342)
        XCTAssertEqual(p.waterTargetOz, 100)          // 0.5 × start weight 200
        XCTAssertEqual(p.waterGoalContainers, 6)      // 100 / 16.9 = 5.9
    }

    // MARK: - Each input moves the calorie target to the value its formula gives

    func testCalorieTargetAfterEachChange() throws {
        let cases: [(String, Double, (SettingsWorld) -> Void)] = [
            // TDEE 2928.68 + 250
            ("lean gain", 3178.68, { $0.inSettings { $0.pace = .leanGain } }),
            // gain is capped at +500 whatever the pace asks: steady gain is +500
            ("steady gain", 3428.68, { $0.inSettings { $0.pace = .steadyGain } }),
            // TDEE, no adjustment
            ("maintain", 2928.68, { $0.inSettings { $0.pace = .maintain } }),
            // TDEE − 500, − 750
            ("steady", 2428.68, { $0.inSettings { $0.pace = .steady } }),
            ("ambitious", 2178.68, { $0.inSettings { $0.pace = .ambitious } }),
            // BMR 1889.47 × 1.375 − 250, × 1.9 − 250
            ("light", 2348.02, { $0.inSettings { $0.activityLevel = .light } }),
            ("extra active", 3339.99, { $0.inSettings { $0.activityLevel = .extraActive } }),
            // BMR − 6.25 × 10 = 1826.97; × 1.55 − 250
            ("height 170", 2581.80, { $0.viaCoach("set_height", ["cm": 170]) }),
            // BMR − 166 = 1723.47; × 1.55 − 250
            ("female", 2421.38, { $0.inSettings { $0.sex = .female } }),
            // BMR − 5 × 15 = 1814.47; × 1.55 − 250
            ("age 45", 2562.43, { $0.viaCoach("set_birth_date", ["age": 45]) }),
            // trend 200.503 + 0.1382 × (185 − 200.503) = 198.360 → BMR 1879.75; × 1.55 − 250
            ("weigh-in 185", 2663.61, { $0.weighIn(185) }),
        ]
        for (name, expected, change) in cases {
            let w = try world()
            change(w)
            XCTAssertEqual(w.profile.dailyCalorieTarget(weightLbs: w.basisWeight), expected, accuracy: 0.02, name)
        }
    }

    func testRangeShapeFollowsTheDirection() throws {
        let w = try world()
        XCTAssertEqual(w.profile.calorieGoalText(weightLbs: w.basisWeight), "2,679–2,829")
        w.inSettings { $0.pace = .leanGain }
        XCTAssertEqual(w.profile.calorieGoalRange(weightLbs: w.basisWeight).high, .infinity)
        XCTAssertEqual(w.profile.calorieGoalText(weightLbs: w.basisWeight), "3,179",
                       "a gain goal is one number to reach, not a band")
    }

    /// A very small, sedentary profile on the fastest pace: the target is the safe floor,
    /// and the floor follows sex (1500 male, 1200 female).
    func testSafeFloorFollowsSex() throws {
        let w = try world()
        w.inSettings { $0.activityLevel = .sedentary; $0.pace = .ambitious; $0.heightCm = 150 }
        w.context.insert(WeightEntry(date: w.now, weightLbs: 100))
        for entry in w.weights where entry.weightLbs > 150 { w.context.delete(entry) }
        try w.context.save()
        // 100 lb = 45.36 kg: BMR 453.6 + 937.5 − 150 + 5 = 1246.1; × 1.2 − 750 = 745 → floor.
        XCTAssertEqual(w.profile.dailyCalorieTarget(weightLbs: w.basisWeight), 1500)
        w.inSettings { $0.sex = .female }
        XCTAssertEqual(w.profile.dailyCalorieTarget(weightLbs: w.basisWeight), 1200)
    }

    func testMacrosAfterEachChange() throws {
        let cases: [(String, [Double], (SettingsWorld) -> Void)] = [
            // protein and fat follow bodyweight only; carbs fill what the calories leave
            ("lean gain", [164, 467, 73], { $0.inSettings { $0.pace = .leanGain } }),
            ("steady", [164, 280, 73], { $0.inSettings { $0.pace = .steady } }),
            // 198.360 lb = 89.975 kg: protein 161.95, fat 71.98, carbs (2663.61 − 647.82 − 647.82) / 4
            ("weigh-in 185", [162, 342, 72], { $0.weighIn(185) }),
            // her own protein: carbs are refilled around the rounded fat, (2678.68 − 150 × 4 − 73 × 9) / 4 = 355.4
            ("protein 150", [150, 355, 73], { $0.viaCoach("set_protein_goal", ["grams": 150]) }),
        ]
        for (name, expected, change) in cases {
            let w = try world()
            change(w)
            let m = w.profile.macroTargets(weightLbs: w.basisWeight)
            XCTAssertEqual([m.proteinG, m.carbsG, m.fatG], expected, name)
        }
    }

    func testWaterAfterEachChange() throws {
        var w = try world()
        w.viaCoach("set_water_goal_containers", ["count": 5])
        XCTAssertEqual(w.profile.waterTargetOz, 84.5, accuracy: 0.001)        // 5 × 16.9
        XCTAssertEqual(w.profile.waterGoalContainers, 5)

        w = try world()
        w.viaCoach("set_water_container", ["oz": 8, "label": "glass"])
        XCTAssertEqual(w.profile.waterTargetOz, 100, "the goal in ounces is not the container's business")
        XCTAssertEqual(w.profile.waterGoalContainers, 13)                      // 100 / 8 = 12.5

        w = try world()
        w.inSettings { $0.startWeightLbs = 190 }
        XCTAssertEqual(w.profile.waterTargetOz, 95)                            // 0.5 × 190

        // With a goal of her own set, the start weight no longer matters.
        w = try world()
        w.inSettings { $0.waterGoalOzOverride = 80 }
        w.inSettings { $0.startWeightLbs = 190 }
        XCTAssertEqual(w.profile.waterTargetOz, 80)
    }

    /// (9000 − 7500) × 200.503 lb × 0.00035 = 105.26 → 105 kcal, and none below the baseline
    /// her activity level already assumes (moderate: 7500; very active: 10000).
    func testStepBonus() throws {
        let w = try world()
        w.inSettings { $0.stepsAdjustCalories = true }
        XCTAssertEqual(w.profile.stepBonusCalories(weightLbs: w.basisWeight, steps: 9000), 105)
        XCTAssertEqual(w.profile.dailyTargetWithSteps(weightLbs: w.basisWeight, steps: 9000), 2783.68, accuracy: 0.01)
        let snap = WidgetDataWriter.snapshot(profile: w.profile, foods: w.foods, weights: w.weights,
                                             waters: w.water, steps: w.steps)
        XCTAssertEqual(snap.stepBonus, 105)
        XCTAssertEqual(snap.calorieTarget, 2783.68, accuracy: 0.01)
        XCTAssertEqual(snap.calorieMax, 2933.68, accuracy: 0.01)
        w.inSettings { $0.activityLevel = .veryActive }
        XCTAssertEqual(w.profile.stepBonusCalories(weightLbs: w.basisWeight, steps: 9000), 0)
    }

    // MARK: - The widget and buddy snapshots carry the same targets the app shows

    func testSnapshotsCarryTheTargets() throws {
        let w = try SettingsWorld(withPlan: true)
        defer { w.tearDown() }
        w.inSettings { $0.dailyStepGoal = 10_000; $0.themeStyle = .cool; $0.goalWeightLbs = 175 }
        let snap = WidgetDataWriter.snapshot(profile: w.profile, foods: w.foods, weights: w.weights,
                                             waters: w.water, steps: w.steps)
        XCTAssertEqual(snap.calorieTarget, 2300)
        XCTAssertEqual(snap.calorieMax, 2500)
        XCTAssertEqual(snap.proteinTarget, 180)
        XCTAssertEqual(snap.stepGoal, 10_000)
        XCTAssertEqual(snap.waterGoalOz, 100)
        XCTAssertEqual(snap.goalWeight, 175)
        XCTAssertEqual(snap.themeStyleRaw, "cool")
        XCTAssertEqual(snap.trendWeight ?? 0, 200.5032, accuracy: 0.0005)
        XCTAssertEqual(snap.steps, 9000)

        let buddy = BuddyStateComposer.compose(profile: w.profile, foods: w.foods, water: w.water,
                                               steps: w.steps, sessions: [], weights: w.weights)
        XCTAssertEqual(buddy.calorieTarget, 2300)
        XCTAssertEqual(buddy.proteinTarget, 180)
        XCTAssertEqual(buddy.stepGoal, 10_000)
        XCTAssertEqual(buddy.waterGoal, 100)
        XCTAssertEqual(buddy.goalWeightLbs, 175)

        // A gain goal has no ceiling: the widget's 0 means "single number".
        w.inSettings { $0.pace = .leanGain }
        let gain = WidgetDataWriter.snapshot(profile: w.profile, foods: w.foods, weights: w.weights,
                                             waters: w.water, steps: w.steps)
        XCTAssertEqual(gain.calorieTarget, 3178.68, accuracy: 0.01)
        XCTAssertEqual(gain.calorieMax, 0)
    }

    // MARK: - The coach reads the same numbers

    func testCoachContextQuotesTheTargets() throws {
        let w = try world()
        func summary() -> String {
            CoachContext.summary(profile: w.profile, foods: w.foods, weights: w.weights,
                                 water: w.water, steps: w.steps)
        }
        XCTAssertTrue(summary().contains("Daily calorie RANGE: 2,679–2,829 kcal"), summary())
        XCTAssertTrue(summary().contains("164 g protein, 342 g carbs, 73 g fat"))
        XCTAssertTrue(summary().contains("Goal weight: 180 lb (pace: relaxed, ~0.5 lb/week)"))
        XCTAssertTrue(summary().contains("of 100 oz goal (~6 bottles)"))
        XCTAssertTrue(summary().contains("Today's steps: 9,000 of 8,000 goal"))

        w.inSettings { $0.pace = .leanGain; $0.goalWeightLbs = 215 }
        w.viaCoach("set_water_goal_containers", ["count": 5])
        w.viaCoach("set_step_goal", ["steps": 10_000])
        XCTAssertTrue(summary().contains("Daily calorie target: 3,179 kcal, 164 g protein, 467 g carbs, 73 g fat"), summary())
        XCTAssertTrue(summary().contains("Goal weight: 215 lb (pace: lean gain, ~0.5 lb/week)"))
        XCTAssertTrue(summary().contains("oz goal (~5 bottles)"))
        XCTAssertTrue(summary().contains("Today's steps: 9,000 of 10,000 goal"))
    }

    // MARK: - Conditional cell: a weigh-in reaches the brief only through the weekly rate

    /// An easing trend is celebrated on a loss goal when the rate is between −2.5 and
    /// −0.2 lb/week, and never on a maintain or gain goal.
    func testBriefCelebratesAnEasingTrendOnlyOnALossGoal() {
        XCTAssertTrue(DailyBriefCard.trendEasedDown(direction: .lose, ratePerWeek: -0.75))
        XCTAssertFalse(DailyBriefCard.trendEasedDown(direction: .lose, ratePerWeek: -0.2))
        XCTAssertFalse(DailyBriefCard.trendEasedDown(direction: .lose, ratePerWeek: -2.5))
        XCTAssertFalse(DailyBriefCard.trendEasedDown(direction: .lose, ratePerWeek: 0.4))
        XCTAssertFalse(DailyBriefCard.trendEasedDown(direction: .gain, ratePerWeek: -0.75))
        XCTAssertFalse(DailyBriefCard.trendEasedDown(direction: .maintain, ratePerWeek: -0.75))
    }

    /// A weigh-in that turns the trend upward takes the celebration away.
    func testAWeighInThatReversesTheTrendChangesTheBrief() throws {
        let w = try world()
        XCTAssertTrue(w.derived()[.brief]?.hasPrefix("milestone") ?? false)
        w.weighIn(230)
        XCTAssertGreaterThan(TrendCalculator.ratePerWeek(w.weights), -0.2)
        XCTAssertFalse(w.derived()[.brief]?.hasPrefix("milestone") ?? true)
    }

    // MARK: - Age is a function of the date

    func testAgeOnADate() {
        let cal = FixedCalendar()
        let profile = UserProfile()
        profile.birthDate = cal.at(1996, 2, 20)
        XCTAssertEqual(profile.age(on: cal.at(2026, 2, 19), calendar: cal.calendar), 29)
        XCTAssertEqual(profile.age(on: cal.at(2026, 2, 20), calendar: cal.calendar), 30)
        XCTAssertEqual(profile.age(on: cal.at(2027, 2, 19, 23, 59), calendar: cal.calendar), 30)
    }

    // MARK: - Open, recorded as they are (docs/settings-dependencies.md, "Open")

    /// N1. With "steps add to my budget" on, the Today ring and the widget add the bonus and
    /// nothing else does: the Nutrients tab, the coach, the buddy snapshot, the companion and
    /// the achievements all read `dailyCalorieTarget`, which has no step bonus.
    func testStepBonusReachesOnlyTheRingAndTheWidget() throws {
        let w = try world()
        w.inSettings { $0.stepsAdjustCalories = true }
        let basis = w.basisWeight
        let ring = w.profile.dailyTargetWithSteps(weightLbs: basis, steps: w.todaySteps)
        let buddy = BuddyStateComposer.compose(profile: w.profile, foods: w.foods, water: w.water,
                                               steps: w.steps, sessions: [], weights: w.weights)
        XCTAssertEqual(ring, 2783.68, accuracy: 0.01)
        XCTExpectFailure("""
            Open (N1): the step bonus is added in DashboardView and WidgetDataWriter only. \
            The buddy snapshot, the companion and the coach's status line use the target without it.
            """) {
            XCTAssertEqual(buddy.calorieTarget, ring, accuracy: 0.01)
            XCTAssertEqual(CompanionTargets(profile: w.profile, basisWeightLbs: basis).calories, ring, accuracy: 0.01)
        }
    }

    /// With no water goal of her own, the goal follows the START weight, not the trend:
    /// 15 lb lighter, still 100 oz.
    func testComputedWaterGoalFollowsTheStartWeightNotTheTrend() throws {
        let w = try world()
        w.weighIn(185)
        XCTAssertEqual(w.profile.waterTargetOz, 100)
    }
}
