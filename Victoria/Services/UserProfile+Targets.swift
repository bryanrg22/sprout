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

    /// The safe minimum daily intake (kcal) — the same floor `NutritionMath.calorieGoal` enforces.
    /// A plan override is never allowed to route the app below this.
    var safeCalorieFloor: Double { sex == .female ? 1200 : 1500 }

    func dailyCalorieTarget(weightLbs: Double) -> Double {
        // The adaptive Plan, when active, is the single source of truth (mirrored into the override
        // and kept in sync from CoachPlan) — but still clamped to the safe floor.
        if calorieTargetOverride > 0 { return max(calorieTargetOverride, safeCalorieFloor) }
        return calorieGoal(weightLbs: weightLbs).dailyCalories
    }

    func macroTargets(weightLbs: Double) -> NutritionMath.Macros {
        let calories = dailyCalorieTarget(weightLbs: weightLbs)
        let base = NutritionMath.macros(calories: calories, weightKg: NutritionMath.lbToKg(weightLbs))
        // Honor the plan's protein target when set: anchor protein, refill carbs so the macros still
        // add up to the calorie target (fat stays at the bodyweight floor).
        guard proteinTargetOverride > 0 else { return base }
        let proteinG = proteinTargetOverride
        let carbsG = max(0, calories - proteinG * 4 - base.fatG * 9) / 4
        return NutritionMath.Macros(proteinG: proteinG.rounded(), carbsG: carbsG.rounded(), fatG: base.fatG)
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
