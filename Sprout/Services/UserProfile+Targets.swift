import Foundation

/// Where the day's calorie intake sits relative to her goal range (see `UserProfile.calorieStatus`).
enum CalorieGoalStatus { case under, inRange, over }

/// How the user prefers to see + enter water. Storage is ALWAYS canonical ounces
/// (`WaterEntry.amountOz`); this only affects display and the custom-amount input.
enum WaterUnit: String, CaseIterable, Identifiable {
    case oz, ml
    var id: String { rawValue }
    var label: String { self == .oz ? "oz" : "mL" }
    static let mlPerOz = 29.5735
}

/// Convenience computed targets derived from the profile via `NutritionMath`.
/// These recompute on demand so they always reflect the latest profile + weight.
extension UserProfile {

    /// Most recent weight to base targets on; falls back to start weight.
    func currentWeightLbs(latestLogged: Double?) -> Double {
        latestLogged ?? (startWeightLbs > 0 ? startWeightLbs : 150)
    }

    /// The weight every target is computed from: the smoothed trend of her weigh-ins, else
    /// her start weight, else 150. The one definition of "her weight now".
    func basisWeightLbs(weights: [WeightEntry]) -> Double {
        currentWeightLbs(latestLogged: TrendCalculator.currentTrend(weights))
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
        // and kept in sync from CoachPlan) — but still clamped to the safe floor. Ignore a garbage
        // override (non-finite or absurdly high, e.g. a stray 1.8e308) so it can never become the target.
        if calorieTargetOverride > 0, calorieTargetOverride.isFinite, calorieTargetOverride < 20_000 {
            return max(calorieTargetOverride, safeCalorieFloor)
        }
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

    // MARK: Calorie GOAL RANGE
    //
    // Weight loss is driven by the AVERAGE deficit over a week, not any single day — daily intake
    // naturally varies ±100–200 kcal. So "did she hit her goal?" is a RANGE, not one number (the
    // evidence-based pattern, e.g. MacroFactor). Direction-aware: LOSE/MAINTAIN get a band (a floor
    // to reach + a soft ceiling); GAIN is a single floor to exceed (eating over is the point).

    /// ± band (kcal) added above a computed target when there's no explicit plan ceiling.
    static let calorieGoalBand: Double = 150

    /// The day's calorie goal as a range. `high` is `.infinity` for a gain goal — NOT
    /// `.greatestFiniteMagnitude`, which is finite and slips past `.isFinite` guards (it once
    /// rendered as a 1.8e308 "goal"). Every consumer guards `high.isFinite` and falls back to a
    /// single number for gain. Uses the active plan's min/max when set.
    func calorieGoalRange(weightLbs: Double) -> (low: Double, high: Double) {
        let target = dailyCalorieTarget(weightLbs: weightLbs)   // floor-clamped; = plan min when active
        switch pace.direction {
        case .gain:
            return (target, .infinity)
        case .lose, .maintain:
            // Only honor a plan ceiling that's FINITE and sane. A stray/garbage override (e.g. an
            // old 1.8e308 value persisted or synced from CloudKit) is finite, so it would slip past
            // `.isFinite` and render as the "goal" — guard the absurd-high case here at the source.
            let sane = calorieMaxOverride.isFinite && calorieMaxOverride > target && calorieMaxOverride < 20_000
            let high = sane ? calorieMaxOverride : target + Self.calorieGoalBand
            return (target, high)
        }
    }

    /// Where today's intake sits relative to her goal range.
    func calorieStatus(consumed: Double, weightLbs: Double) -> CalorieGoalStatus {
        let (low, high) = calorieGoalRange(weightLbs: weightLbs)
        guard low > 0 else { return .under }
        if consumed < low * 0.97 { return .under }      // small grace so ~hitting the floor counts
        if consumed <= high { return .inRange }
        return .over
    }

    /// She's eaten enough to count as hitting her goal today (reached the floor — in range or a bit beyond).
    func hasReachedCalorieGoal(consumed: Double, weightLbs: Double) -> Bool {
        calorieStatus(consumed: consumed, weightLbs: weightLbs) != .under
    }

    /// Goal shown for the UI: "1,580–1,730" for a ranged (loss/maintain) goal, or "1,580" for a
    /// single-number (gain) goal.
    func calorieGoalText(weightLbs: Double) -> String {
        let (low, high) = calorieGoalRange(weightLbs: weightLbs)
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        func s(_ v: Double) -> String { f.string(from: v as NSNumber) ?? "\(Int(v))" }
        if high.isFinite && high > low { return "\(s(low))–\(s(high))" }
        return s(low)
    }

    /// Daily water goal in oz. Uses her explicit override when set, else the
    /// computed default (~½ bodyweight). Never returns 0.
    var waterTargetOz: Double {
        if waterGoalOzOverride > 0 { return waterGoalOzOverride }
        return recommendedWaterOz
    }

    /// The goal she gets with no goal of her own set: ~½ oz per lb of her START weight. It
    /// is what "Reset to recommended" in Settings applies, so it is also what that button shows.
    var recommendedWaterOz: Double {
        NutritionMath.dailyWaterOz(weightLbs: startWeightLbs > 0 ? startWeightLbs : 150)
    }

    /// How many "containers" (bottles/glasses) the goal works out to — for the
    /// by-the-bottle UI so she never thinks in ounces.
    var waterGoalContainers: Int {
        let size = waterContainerOz > 0 ? waterContainerOz : 16.9
        return max(1, Int((waterTargetOz / size).rounded()))
    }

    // MARK: Water unit (display + input)

    var waterUnit: WaterUnit {
        get { WaterUnit(rawValue: waterUnitRaw) ?? .oz }
        set { waterUnitRaw = newValue.rawValue }
    }
    var waterUnitLabel: String { waterUnit.label }

    /// Canonical oz → the user's chosen display unit.
    func waterDisplay(_ oz: Double) -> Double {
        waterUnit == .ml ? oz * WaterUnit.mlPerOz : oz
    }
    /// A value typed in the user's chosen unit → canonical oz (for storage).
    func waterToOz(_ value: Double) -> Double {
        waterUnit == .ml ? value / WaterUnit.mlPerOz : value
    }
    /// "<amount> of <goal> <unit>" in the chosen unit (mL rounded to the nearest 10 to read cleanly).
    func waterText(_ oz: Double, goalOz: Double) -> String {
        let round: (Double) -> Int = { self.waterUnit == .ml ? Int(($0 / 10).rounded()) * 10 : Int($0.rounded()) }
        return "\(round(waterDisplay(oz))) of \(round(waterDisplay(goalOz))) \(waterUnitLabel)"
    }
    /// Just the number (no unit) in the chosen unit — for editable fields. mL → nearest 10; oz keeps .9.
    func waterAmountValue(_ oz: Double) -> String {
        if waterUnit == .ml { return String(Int((waterDisplay(oz) / 10).rounded()) * 10) }
        return oz == oz.rounded() ? String(Int(oz)) : String(format: "%.1f", oz)
    }
    /// A single amount with its unit, e.g. "16 oz" / "500 mL".
    func waterAmount(_ oz: Double) -> String { "\(waterAmountValue(oz)) \(waterUnitLabel)" }
}
