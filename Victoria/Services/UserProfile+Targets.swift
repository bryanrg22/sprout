import Foundation

/// Convenience computed targets derived from the profile via `NutritionMath`.
/// These recompute on demand so they always reflect the latest profile + weight.
extension UserProfile {

    /// Most recent weight to base targets on; falls back to start weight.
    func currentWeightLbs(latestLogged: Double?) -> Double {
        latestLogged ?? (startWeightLbs > 0 ? startWeightLbs : 150)
    }

    func bmr(weightLbs: Double) -> Double {
        NutritionMath.bmr(sex: sex,
                          weightKg: NutritionMath.lbToKg(weightLbs),
                          heightCm: heightCm,
                          ageYears: ageYears)
    }

    func tdee(weightLbs: Double) -> Double {
        NutritionMath.tdee(bmr: bmr(weightLbs: weightLbs), activity: activityLevel)
    }

    func calorieGoal(weightLbs: Double) -> NutritionMath.CalorieGoal {
        NutritionMath.calorieGoal(tdee: tdee(weightLbs: weightLbs),
                                  dailyAdjustment: pace.dailyCalorieAdjustment,
                                  sex: sex)
    }

    func dailyCalorieTarget(weightLbs: Double) -> Double {
        calorieGoal(weightLbs: weightLbs).dailyCalories
    }

    func macroTargets(weightLbs: Double) -> NutritionMath.Macros {
        NutritionMath.macros(calories: dailyCalorieTarget(weightLbs: weightLbs),
                             weightKg: NutritionMath.lbToKg(weightLbs))
    }

    /// Daily water goal in oz. Uses her explicit override when set, else the
    /// computed default (~½ bodyweight). Never returns 0.
    var waterTargetOz: Double {
        if waterGoalOzOverride > 0 { return waterGoalOzOverride }
        return NutritionMath.dailyWaterOz(weightLbs: startWeightLbs > 0 ? startWeightLbs : 150)
    }

    /// How many "containers" (bottles/glasses) the goal works out to — for the
    /// by-the-bottle UI so she never thinks in ounces.
    var waterGoalContainers: Int {
        let size = waterContainerOz > 0 ? waterContainerOz : 16.9
        return max(1, Int((waterTargetOz / size).rounded()))
    }
}
