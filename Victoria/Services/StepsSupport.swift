import Foundation

extension ActivityLevel {
    /// Steps a typical day at this activity level already includes. We only award
    /// bonus calories for steps ABOVE this, so we don't double-count the activity
    /// multiplier already baked into TDEE.
    var baselineSteps: Int {
        switch self {
        case .sedentary:   return 3000
        case .light:       return 5000
        case .moderate:    return 7500
        case .veryActive:  return 10000
        case .extraActive: return 12500
        }
    }
}

extension NutritionMath {
    /// Calories earned from steps above the activity baseline.
    /// ~0.00035 kcal per step per lb → ~0.055 kcal/step at 158 lb (gross walking cost).
    static func stepBonusCalories(steps: Int, weightLbs: Double, baselineSteps: Int) -> Double {
        let extra = max(0, steps - baselineSteps)
        let perStep = max(0.3, weightLbs) * 0.00035
        return (Double(extra) * perStep).rounded()
    }
}

extension UserProfile {
    /// Bonus calories she's "earned" from today's steps (0 if the feature is off).
    func stepBonusCalories(weightLbs: Double, steps: Int) -> Double {
        guard stepsAdjustCalories else { return 0 }
        return NutritionMath.stepBonusCalories(steps: steps,
                                               weightLbs: weightLbs,
                                               baselineSteps: activityLevel.baselineSteps)
    }

    /// Daily calorie target including the step bonus.
    func dailyTargetWithSteps(weightLbs: Double, steps: Int) -> Double {
        dailyCalorieTarget(weightLbs: weightLbs) + stepBonusCalories(weightLbs: weightLbs, steps: steps)
    }
}
