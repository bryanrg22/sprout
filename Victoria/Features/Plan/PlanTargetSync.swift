import Foundation

/// How the active plan's targets are mirrored into the profile overrides that the rings,
/// achievements and Vita's context read through `dailyCalorieTarget` / `macroTargets`.
enum PlanTargetSync {

    struct PlanTargets: Equatable {
        var hasRange: Bool
        var calorieMin: Double
        var calorieMax: Double
        var proteinTarget: Double
    }

    struct Overrides: Equatable {
        var calorie: Double
        var calorieMax: Double
        var protein: Double
    }

    /// With a plan, the plan's numbers win. With NO plan the calorie overrides fall back to 0
    /// (the computed defaults, since only a plan ever sets them), but the protein override is
    /// left as it is: without a plan its only writer is the user, through Vita's
    /// `set_protein_goal`, and that choice must survive a relaunch.
    static func overrides(plan: PlanTargets?, currentProtein: Double) -> Overrides {
        guard let plan else {
            return Overrides(calorie: 0, calorieMax: 0, protein: max(0, currentProtein))
        }
        return Overrides(calorie: plan.hasRange ? plan.calorieMin : 0,
                         calorieMax: plan.hasRange ? plan.calorieMax : 0,
                         protein: max(0, plan.proteinTarget))
    }
}
