import XCTest
@testable import Sprout

/// Integration tests for the computed targets on `UserProfile` — the layer the
/// dashboard, settings, and AI-coach context all read. Verifies the whole chain
/// (profile → BMR → TDEE → goal → macros) composes to hand-checked numbers.
final class ProfileTargetsTests: XCTestCase {

    private let acc = 0.5  // these compose several rounded steps

    /// The demo loss profile: female, 65 in, light, relaxed, 158 lb.
    private func victoria() -> UserProfile {
        let p = UserProfile()
        p.sex = .female
        p.heightCm = NutritionMath.inToCm(65)   // 165.1
        p.activityLevel = .light
        p.pace = .relaxed
        p.startWeightLbs = 158
        p.goalWeightLbs = 140
        p.dailyStepGoal = 8000
        // ageYears derives from birthDate; default profile is ~25y.
        return p
    }

    // MARK: - Full chain

    func testDailyCalorieTargetComposes() {
        // BMR 1462.55 · 1.375 = 2011.0 ; − 250 (relaxed) = 1761.0
        let target = victoria().dailyCalorieTarget(weightLbs: 158)
        XCTAssertEqual(target, 1761, accuracy: 3.0) // small age/rounding drift tolerated
    }

    func testCalorieGoalNotClampedForTypicalUser() {
        XCTAssertFalse(victoria().calorieGoal(weightLbs: 158).wasClampedToFloor)
    }

    func testMacroTargetsComposeAndSumBack() {
        let p = victoria()
        let target = p.dailyCalorieTarget(weightLbs: 158)
        let m = p.macroTargets(weightLbs: 158)
        XCTAssertEqual(m.proteinG, 129, accuracy: 1.0)
        XCTAssertEqual(m.fatG, 57, accuracy: 1.0)
        // Atwater on the macro grams should land within rounding of the calorie target.
        let kcalFromMacros = NutritionMath.calories(proteinG: m.proteinG, carbsG: m.carbsG, fatG: m.fatG)
        XCTAssertEqual(kcalFromMacros, target, accuracy: 12) // grams are rounded to whole numbers
    }

    func testWaterTargetFromStartWeight() {
        XCTAssertEqual(victoria().waterTargetOz, 79, accuracy: 0.5) // 158·0.5
    }

    // MARK: - currentWeightLbs fallback ladder

    func testCurrentWeightUsesLatestLoggedWhenPresent() {
        XCTAssertEqual(victoria().currentWeightLbs(latestLogged: 151.3), 151.3, accuracy: 0.0001)
    }

    func testCurrentWeightFallsBackToStartWeight() {
        XCTAssertEqual(victoria().currentWeightLbs(latestLogged: nil), 158, accuracy: 0.0001)
    }

    func testCurrentWeightUltimateFallbackIs150() {
        let p = UserProfile() // startWeightLbs defaults to 0
        XCTAssertEqual(p.currentWeightLbs(latestLogged: nil), 150, accuracy: 0.0001)
    }

    // MARK: - Step bonus gating (display-only by default)

    func testStepBonusZeroWhenFeatureOff() {
        let p = victoria()
        p.stepsAdjustCalories = false
        XCTAssertEqual(p.stepBonusCalories(weightLbs: 158, steps: 12000), 0, accuracy: 0.0001)
        // ...and the with-steps target equals the plain target.
        XCTAssertEqual(p.dailyTargetWithSteps(weightLbs: 158, steps: 12000),
                       p.dailyCalorieTarget(weightLbs: 158), accuracy: 0.0001)
    }

    func testStepBonusAppliedWhenFeatureOn() {
        let p = victoria()
        p.stepsAdjustCalories = true
        // light baseline 5000; 9243 steps, 158 lb → +235 kcal
        let bonus = p.stepBonusCalories(weightLbs: 158, steps: 9243)
        XCTAssertEqual(bonus, 235, accuracy: 1.0)
        XCTAssertEqual(p.dailyTargetWithSteps(weightLbs: 158, steps: 9243),
                       p.dailyCalorieTarget(weightLbs: 158) + bonus, accuracy: 0.0001)
    }

    // MARK: - Safety: a small, very-active dieter still never goes below the floor

    func testTargetNeverBelowSafeFloor() {
        let p = UserProfile()
        p.sex = .female
        p.heightCm = NutritionMath.inToCm(60) // petite
        p.activityLevel = .sedentary
        p.pace = .ambitious                    // biggest deficit
        p.startWeightLbs = 110
        let target = p.dailyCalorieTarget(weightLbs: 110)
        XCTAssertGreaterThanOrEqual(target, 1200) // female floor holds
    }

    // MARK: - Plan target overrides (the plan as the single source of truth)

    func testCalorieOverrideDrivesTheTarget() {
        let p = victoria()
        p.calorieTargetOverride = 1900
        XCTAssertEqual(p.dailyCalorieTarget(weightLbs: 158), 1900, accuracy: 0.0001)
    }

    /// A plan can RAISE the target freely, but can never route the app below the safe floor.
    func testCalorieOverrideStillClampedToSafeFloor() {
        let p = victoria()                 // female → floor 1200
        p.calorieTargetOverride = 900
        XCTAssertEqual(p.dailyCalorieTarget(weightLbs: 158), 1200, accuracy: 0.0001)
    }

    func testProteinOverrideDrivesProteinAndRefillsCarbs() {
        let p = victoria()
        p.calorieTargetOverride = 1800
        p.proteinTargetOverride = 150
        let m = p.macroTargets(weightLbs: 158)
        XCTAssertEqual(m.proteinG, 150, accuracy: 0.0001)
        // Macros still add up to the (overridden) calorie target within rounding.
        let kcal = NutritionMath.calories(proteinG: m.proteinG, carbsG: m.carbsG, fatG: m.fatG)
        XCTAssertEqual(kcal, 1800, accuracy: 12)
    }

    func testZeroOverrideFallsBackToComputed() {
        let p = victoria()
        p.calorieTargetOverride = 0
        p.proteinTargetOverride = 0
        XCTAssertEqual(p.dailyCalorieTarget(weightLbs: 158),
                       p.calorieGoal(weightLbs: 158).dailyCalories, accuracy: 0.0001)
    }
}
