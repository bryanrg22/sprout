import XCTest
@testable import Sprout

/// Tests for the pure nutrition/fitness math. Every expected value here is computed
/// INDEPENDENTLY by hand from the published formula (Mifflin-St Jeor, Atwater, etc.),
/// not read back from the implementation — so a failure means the code is wrong.
final class NutritionMathTests: XCTestCase {

    private let acc = 0.01

    // MARK: - Unit conversions

    func testUnitConversions() {
        XCTAssertEqual(NutritionMath.lbToKg(220.462), 100.0, accuracy: 0.001)
        XCTAssertEqual(NutritionMath.kgToLb(100), 220.462, accuracy: 0.001)
        XCTAssertEqual(NutritionMath.inToCm(10), 25.4, accuracy: 0.0001)
        XCTAssertEqual(NutritionMath.cmToIn(25.4), 10, accuracy: 0.0001)
    }

    func testConversionRoundTrip() {
        XCTAssertEqual(NutritionMath.kgToLb(NutritionMath.lbToKg(150)), 150, accuracy: 0.0001)
        XCTAssertEqual(NutritionMath.cmToIn(NutritionMath.inToCm(70)), 70, accuracy: 0.0001)
    }

    // MARK: - BMR (Mifflin-St Jeor)

    /// Female, 158 lb (71.6677 kg), 65 in (165.1 cm), age 25.
    /// base = 10·71.6677 + 6.25·165.1 − 5·25 = 1623.552 ; female: −161 → 1462.55
    func testBMRFemale() {
        let kg = NutritionMath.lbToKg(158)
        let bmr = NutritionMath.bmr(sex: .female, weightKg: kg, heightCm: 165.1, ageYears: 25)
        XCTAssertEqual(bmr, 1462.55, accuracy: 0.1)
    }

    /// Same body but male: female value + 166 (the −161 becomes +5).
    func testBMRMaleIsFemalePlus166() {
        let kg = NutritionMath.lbToKg(158)
        let f = NutritionMath.bmr(sex: .female, weightKg: kg, heightCm: 165.1, ageYears: 25)
        let m = NutritionMath.bmr(sex: .male,   weightKg: kg, heightCm: 165.1, ageYears: 25)
        XCTAssertEqual(m - f, 166, accuracy: 0.0001)
    }

    // MARK: - TDEE

    func testTDEEMultipliers() {
        XCTAssertEqual(NutritionMath.tdee(bmr: 1000, activity: .sedentary),   1200, accuracy: acc)
        XCTAssertEqual(NutritionMath.tdee(bmr: 1000, activity: .light),       1375, accuracy: acc)
        XCTAssertEqual(NutritionMath.tdee(bmr: 1000, activity: .moderate),    1550, accuracy: acc)
        XCTAssertEqual(NutritionMath.tdee(bmr: 1000, activity: .veryActive),  1725, accuracy: acc)
        XCTAssertEqual(NutritionMath.tdee(bmr: 1000, activity: .extraActive), 1900, accuracy: acc)
    }

    // MARK: - Calorie goal + safe floor

    func testCalorieGoalNormalDeficit() {
        let g = NutritionMath.calorieGoal(tdee: 2011, dailyDeficit: 250, sex: .female)
        XCTAssertEqual(g.dailyCalories, 1761, accuracy: acc)
        XCTAssertFalse(g.wasClampedToFloor)
    }

    func testCalorieGoalClampsToFemaleFloor() {
        // 1400 − 250 = 1150, below the 1200 female floor → clamps up, flags it.
        let g = NutritionMath.calorieGoal(tdee: 1400, dailyDeficit: 250, sex: .female)
        XCTAssertEqual(g.dailyCalories, 1200, accuracy: acc)
        XCTAssertTrue(g.wasClampedToFloor)
    }

    func testCalorieGoalClampsToMaleFloor() {
        // 1600 − 250 = 1350, below the 1500 male floor.
        let g = NutritionMath.calorieGoal(tdee: 1600, dailyDeficit: 250, sex: .male)
        XCTAssertEqual(g.dailyCalories, 1500, accuracy: acc)
        XCTAssertTrue(g.wasClampedToFloor)
    }

    // MARK: - Direction-aware goal (lose / maintain / gain)

    /// REGRESSION: the new signed-adjustment path must give the EXACT same loss number
    /// as the old deficit path — her app must not shift by a single calorie.
    func testSignedAdjustmentMatchesLegacyDeficit() {
        let legacy = NutritionMath.calorieGoal(tdee: 2011, dailyDeficit: 250, sex: .female)
        let signed = NutritionMath.calorieGoal(tdee: 2011, dailyAdjustment: -250, sex: .female)
        XCTAssertEqual(signed.dailyCalories, legacy.dailyCalories, accuracy: 0.0001)
        XCTAssertEqual(signed.dailyCalories, 1761, accuracy: acc)
    }

    func testGainAddsSurplus() {
        // Gain: TDEE + surplus (no floor/ceiling hit). 2000 + 250 = 2250.
        let g = NutritionMath.calorieGoal(tdee: 2000, dailyAdjustment: 250, sex: .male)
        XCTAssertEqual(g.dailyCalories, 2250, accuracy: acc)
        XCTAssertFalse(g.wasClampedToFloor)
    }

    func testGainSurplusCappedAtLeanBulkCeiling() {
        // Asking for +800/day is capped to +500 (≈1 lb/wk) so it stays a lean bulk.
        let g = NutritionMath.calorieGoal(tdee: 2000, dailyAdjustment: 800, sex: .male)
        XCTAssertEqual(g.dailyCalories, 2500, accuracy: acc)   // 2000 + 500
        XCTAssertTrue(g.wasClampedToFloor)                     // flagged (reused flag = "was clamped")
    }

    func testGoalPaceSignedRatesAndAdjustments() {
        XCTAssertEqual(GoalPace.relaxed.signedWeeklyRateLbs, -0.5, accuracy: acc)
        XCTAssertEqual(GoalPace.relaxed.dailyCalorieAdjustment, -250, accuracy: acc)
        XCTAssertEqual(GoalPace.maintain.dailyCalorieAdjustment, 0, accuracy: acc)
        XCTAssertEqual(GoalPace.leanGain.signedWeeklyRateLbs, 0.5, accuracy: acc)
        XCTAssertEqual(GoalPace.leanGain.dailyCalorieAdjustment, 250, accuracy: acc)
        XCTAssertEqual(GoalPace.steadyGain.dailyCalorieAdjustment, 500, accuracy: acc)
        // Back-compat: dailyDeficit stays non-negative (0 for gain paces).
        XCTAssertEqual(GoalPace.relaxed.dailyDeficit, 250, accuracy: acc)
        XCTAssertEqual(GoalPace.leanGain.dailyDeficit, 0, accuracy: acc)
    }

    func testPacesFilteredByDirection() {
        let lose = GoalPace.paces(for: .lose)
        XCTAssertTrue(lose.contains(.relaxed) && lose.contains(.maintain))
        XCTAssertFalse(lose.contains(.leanGain))           // her app never offers gain
        let gain = GoalPace.paces(for: .gain)
        XCTAssertTrue(gain.contains(.leanGain) && gain.contains(.steadyGain))
        XCTAssertFalse(gain.contains(.relaxed))
    }

    func testCalorieGoalMaintainNotClamped() {
        // Maintain = 0 deficit, TDEE above floor → unchanged, not flagged.
        let g = NutritionMath.calorieGoal(tdee: 2000, dailyDeficit: 0, sex: .female)
        XCTAssertEqual(g.dailyCalories, 2000, accuracy: acc)
        XCTAssertFalse(g.wasClampedToFloor)
    }

    /// DOCUMENTS CURRENT BEHAVIOR (flagged as slightly odd): if TDEE itself is already
    /// below the floor and deficit is 0, the result is bumped to the floor but
    /// `wasClampedToFloor` is reported false (the flag only trips when deficit > 0).
    func testCalorieGoalFloorWithZeroDeficitDoesNotFlag() {
        let g = NutritionMath.calorieGoal(tdee: 1100, dailyDeficit: 0, sex: .female)
        XCTAssertEqual(g.dailyCalories, 1200, accuracy: acc)
        XCTAssertFalse(g.wasClampedToFloor) // <- intentional documentation of current logic
    }

    // MARK: - Macros

    /// calories 1761, weightKg 71.6677: P = 1.8·kg = 129, F = 0.8·kg = 57,
    /// C = (1761 − (129·4 + 57·9... using unrounded)) / 4 ≈ 182.
    func testMacrosTypical() {
        let kg = NutritionMath.lbToKg(158)
        let m = NutritionMath.macros(calories: 1761, weightKg: kg)
        XCTAssertEqual(m.proteinG, 129, accuracy: acc)
        XCTAssertEqual(m.fatG, 57, accuracy: acc)
        XCTAssertEqual(m.carbsG, 182, accuracy: 1.0) // rounding of intermediates
    }

    /// Macro grams must never go negative even if protein+fat exceed the calorie budget.
    func testMacrosCarbsClampNonNegative() {
        let m = NutritionMath.macros(calories: 200, weightKg: 90) // tiny budget, big body
        XCTAssertGreaterThanOrEqual(m.carbsG, 0)
        XCTAssertEqual(m.carbsG, 0, accuracy: acc)
    }

    // MARK: - BMI

    func testBMI() {
        let kg = NutritionMath.lbToKg(158)
        let bmi = NutritionMath.bmi(weightKg: kg, heightCm: 165.1)
        XCTAssertEqual(bmi, 26.29, accuracy: 0.05)
    }

    func testBMIZeroHeightIsSafe() {
        XCTAssertEqual(NutritionMath.bmi(weightKg: 70, heightCm: 0), 0)
    }

    func testBMICategories() {
        XCTAssertEqual(NutritionMath.bmiCategory(17), "Underweight")
        XCTAssertEqual(NutritionMath.bmiCategory(22), "Normal")
        XCTAssertEqual(NutritionMath.bmiCategory(27), "Overweight")
        XCTAssertEqual(NutritionMath.bmiCategory(33), "Above range")
        // Boundaries
        XCTAssertEqual(NutritionMath.bmiCategory(18.5), "Normal")
        XCTAssertEqual(NutritionMath.bmiCategory(25), "Overweight")
        XCTAssertEqual(NutritionMath.bmiCategory(30), "Above range")
    }

    // MARK: - Water

    func testDailyWater() {
        XCTAssertEqual(NutritionMath.dailyWaterOz(weightLbs: 158), 79, accuracy: acc)
        XCTAssertEqual(NutritionMath.dailyWaterOz(weightLbs: 200), 100, accuracy: acc)
    }

    // MARK: - Atwater (calories from macros)

    func testCaloriesFromMacros() {
        // 50·4 + 100·4 + 20·9 = 200 + 400 + 180 = 780
        XCTAssertEqual(NutritionMath.calories(proteinG: 50, carbsG: 100, fatG: 20), 780, accuracy: acc)
    }

    // MARK: - Step bonus

    func testStepBonusAboveBaseline() {
        // 9243 steps, 158 lb, light baseline 5000: extra 4243 · (158·0.00035) = 234.6 → 235
        let b = NutritionMath.stepBonusCalories(steps: 9243, weightLbs: 158, baselineSteps: 5000)
        XCTAssertEqual(b, 235, accuracy: acc)
    }

    func testStepBonusBelowBaselineIsZero() {
        XCTAssertEqual(NutritionMath.stepBonusCalories(steps: 3000, weightLbs: 158, baselineSteps: 5000), 0, accuracy: acc)
        XCTAssertEqual(NutritionMath.stepBonusCalories(steps: 5000, weightLbs: 158, baselineSteps: 5000), 0, accuracy: acc)
    }

    func testActivityBaselineSteps() {
        XCTAssertEqual(ActivityLevel.sedentary.baselineSteps, 3000)
        XCTAssertEqual(ActivityLevel.light.baselineSteps, 5000)
        XCTAssertEqual(ActivityLevel.extraActive.baselineSteps, 12500)
    }

    // MARK: - GoalPace deficits

    func testPaceDailyDeficits() {
        XCTAssertEqual(GoalPace.maintain.dailyDeficit, 0, accuracy: acc)
        XCTAssertEqual(GoalPace.relaxed.dailyDeficit, 250, accuracy: acc)   // 0.5 lb/wk
        XCTAssertEqual(GoalPace.steady.dailyDeficit, 500, accuracy: acc)    // 1.0 lb/wk
        XCTAssertEqual(GoalPace.ambitious.dailyDeficit, 750, accuracy: acc) // 1.5 lb/wk
    }
}
