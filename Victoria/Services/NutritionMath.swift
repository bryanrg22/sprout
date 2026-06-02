import Foundation

/// Pure, testable nutrition/fitness math. All functions work in METRIC internally;
/// convert at the UI boundary. Sources: Mifflin-St Jeor (AJCN 1990), CDC/NHS/Mayo
/// Clinic guidance. Everything here is an estimate — surface a "not medical advice"
/// disclaimer in the UI.
enum NutritionMath {

    // MARK: - Unit conversions
    static func lbToKg(_ lb: Double) -> Double { lb / 2.20462 }
    static func kgToLb(_ kg: Double) -> Double { kg * 2.20462 }
    static func inToCm(_ inches: Double) -> Double { inches * 2.54 }
    static func cmToIn(_ cm: Double) -> Double { cm / 2.54 }

    // MARK: - BMR (Mifflin-St Jeor)
    /// kcal/day. weightKg, heightCm, age in years.
    static func bmr(sex: BiologicalSex, weightKg: Double, heightCm: Double, ageYears: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears)
        switch sex {
        case .male:   return base + 5
        case .female: return base - 161
        }
    }

    // MARK: - TDEE
    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    // MARK: - Calorie goal for weight loss (with safe floor)
    struct CalorieGoal {
        let dailyCalories: Double
        /// True when the requested deficit was reduced to respect the safe floor.
        let wasClampedToFloor: Bool
    }

    /// Daily calorie target for a LOSS goal: TDEE − deficit, clamped to a safe floor
    /// (~1200 kcal women / ~1500 kcal men). Kept as-is for back-compat (her app).
    static func calorieGoal(tdee: Double, dailyDeficit: Double, sex: BiologicalSex) -> CalorieGoal {
        let floor: Double = (sex == .female) ? 1200 : 1500
        let raw = tdee - max(0, dailyDeficit)
        if raw < floor {
            return CalorieGoal(dailyCalories: floor, wasClampedToFloor: dailyDeficit > 0)
        }
        return CalorieGoal(dailyCalories: raw, wasClampedToFloor: false)
    }

    /// Direction-aware daily calorie target. `adjustment` is SIGNED:
    /// negative = deficit (lose), 0 = maintain, positive = surplus (gain).
    /// - Loss: clamp DOWN to the safe floor (never recommend eating dangerously little).
    /// - Gain: cap the surplus at a "lean bulk" ceiling (≈ +1 lb/wk → +500 kcal); beyond
    ///   that, extra calories just become fat, so we don't auto-recommend more.
    static func calorieGoal(tdee: Double, dailyAdjustment: Double, sex: BiologicalSex) -> CalorieGoal {
        if dailyAdjustment <= 0 {
            // Loss / maintain — reuse the floor logic.
            return calorieGoal(tdee: tdee, dailyDeficit: -dailyAdjustment, sex: sex)
        }
        // Gain — cap the surplus so it stays a lean bulk, not fat-gain.
        let surplusCeiling: Double = 500   // ~1 lb/wk; research: faster = unnecessary fat
        let clamped = min(dailyAdjustment, surplusCeiling)
        return CalorieGoal(dailyCalories: tdee + clamped,
                           wasClampedToFloor: dailyAdjustment > surplusCeiling)
    }

    // MARK: - Macros (protein anchored by bodyweight, fat by floor, carbs fill remainder)
    struct Macros { let proteinG, carbsG, fatG: Double }

    static func macros(calories: Double,
                       weightKg: Double,
                       proteinPerKg: Double = 1.8,
                       fatPerKg: Double = 0.8) -> Macros {
        let proteinG = proteinPerKg * weightKg
        let fatG     = fatPerKg * weightKg
        let usedKcal = proteinG * 4 + fatG * 9
        let carbsG   = max(0, calories - usedKcal) / 4
        return Macros(proteinG: proteinG.rounded(), carbsG: carbsG.rounded(), fatG: fatG.rounded())
    }

    // MARK: - BMI (display/context only — never used to gate or shame)
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        guard m > 0 else { return 0 }
        return weightKg / (m * m)
    }

    static func bmiCategory(_ value: Double) -> String {
        switch value {
        case ..<18.5: return "Underweight"
        case ..<25:   return "Normal"
        case ..<30:   return "Overweight"
        default:      return "Above range"
        }
    }

    // MARK: - Water (rough, non-clinical)
    /// ~0.5 oz per lb bodyweight.
    static func dailyWaterOz(weightLbs: Double) -> Double {
        (weightLbs * 0.5).rounded()
    }

    // MARK: - Energy from macros (Atwater)
    static func calories(proteinG: Double, carbsG: Double, fatG: Double) -> Double {
        proteinG * 4 + carbsG * 4 + fatG * 9
    }
}
