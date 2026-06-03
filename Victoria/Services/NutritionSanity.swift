import Foundation

/// A small, deterministic guard over any calorie/macro quadruple — whether it came
/// from an AI photo/description estimate or a barcode/label/database lookup.
///
/// It cannot catch a *self-consistent* wrong answer (e.g. an AI that hallucinates a
/// number whose macros happen to add up). What it DOES catch is the broad class of
/// clearly-broken values that should never be logged silently:
///   • macros and calories that disagree by a wide margin (bad parse / unit mix-up),
///   • a single macro whose calories exceed the stated total (impossible),
///   • calories denser than pure fat (≈9 kcal/g) for the given weight,
///   • a macro weighing more than the whole food,
///   • negatives, and absurd single-item outliers.
///
/// When something looks off we DON'T block — the app's whole stance is "estimate,
/// then edit." We flag it (so the confirm sheet shows low confidence + a nudge to
/// check the number) and, when calories were missing, fill them from the macros.
enum NutritionSanity {

    // Atwater factors (kcal per gram).
    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarb = 4.0
    static let kcalPerGramFat = 9.0

    /// Calories implied by the macros alone.
    static func caloriesFromMacros(protein: Double, carbs: Double, fat: Double) -> Double {
        max(0, protein) * kcalPerGramProtein
        + max(0, carbs) * kcalPerGramCarb
        + max(0, fat) * kcalPerGramFat
    }

    /// The result of vetting a quadruple. `calories` may be filled in from the macros
    /// when the input had none; the macros themselves are returned clamped to ≥0.
    struct Check: Equatable {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        /// True when the numbers look physically implausible and deserve a second look.
        var isSuspicious: Bool
        /// A short, human-readable reason (nil when nothing's wrong) — surfaced as a note.
        var reason: String?
    }

    /// Vet a calorie/macro quadruple. `grams`, when known (food weight for the logged
    /// amount), unlocks the density and "macro heavier than the food" checks.
    static func check(calories: Double,
                      protein: Double,
                      carbs: Double,
                      fat: Double,
                      grams: Double? = nil) -> Check {
        // 1) Clamp negatives — a negative macro/calorie is always a parse error.
        let p = max(0, protein)
        let c = max(0, carbs)
        let f = max(0, fat)
        var cal = max(0, calories)

        let macroKcal = caloriesFromMacros(protein: p, carbs: c, fat: f)

        // 2) Fill missing calories from the macros (a fix, not a red flag).
        if cal <= 0 && macroKcal > 0 {
            cal = macroKcal.rounded()
            return Check(calories: cal, protein: p, carbs: c, fat: f,
                         isSuspicious: false, reason: nil)
        }

        var reasons: [String] = []

        // 3) Calories vs macros must roughly agree (tolerant of fibre/rounding/alcohol).
        if cal > 0 && macroKcal > 0 {
            let rel = abs(cal - macroKcal) / max(cal, macroKcal)
            if rel > 0.30 {
                reasons.append("the calories and macros don't match (\(Int(cal.rounded())) kcal vs ~\(Int(macroKcal.rounded())) from macros)")
            }
        }

        // 4) No single macro can supply more calories than the stated total.
        if cal > 0 {
            let limit = cal * 1.20   // 20% slack for rounding
            if p * kcalPerGramProtein > limit { reasons.append("protein alone exceeds the calories") }
            else if c * kcalPerGramCarb > limit { reasons.append("carbs alone exceed the calories") }
            else if f * kcalPerGramFat > limit { reasons.append("fat alone exceeds the calories") }
        }

        // 5) Weight-based checks when we know the food's grams.
        if let grams, grams > 0 {
            if cal / grams > 9.5 {            // denser than pure fat → impossible
                reasons.append("that's denser than pure fat for the serving size")
            }
            let gramSlack = grams * 1.05
            if p > gramSlack || c > gramSlack || f > gramSlack {
                reasons.append("a macro weighs more than the food itself")
            }
        } else {
            // 6) No weight: only guard against absurd single-item outliers.
            if cal > 5000 { reasons.append("that's an unusually large calorie total for one item") }
            if max(p, max(c, f)) > 500 { reasons.append("that's an unusually large amount of one macro") }
        }

        let suspicious = !reasons.isEmpty
        return Check(calories: cal, protein: p, carbs: c, fat: f,
                     isSuspicious: suspicious,
                     reason: suspicious ? "Double-check these numbers — \(reasons[0])." : nil)
    }
}
