import Foundation

/// Biological sex — used only for the BMR equation (Mifflin-St Jeor differs by a constant).
enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case female, male
    var id: String { rawValue }
    var label: String { self == .female ? "Female" : "Male" }
}

/// Standard activity multipliers applied to BMR to estimate TDEE.
enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, veryActive, extraActive
    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary:   return 1.2
        case .light:       return 1.375
        case .moderate:    return 1.55
        case .veryActive:  return 1.725
        case .extraActive: return 1.9
        }
    }

    var label: String {
        switch self {
        case .sedentary:   return "Not very active"
        case .light:       return "Lightly active"
        case .moderate:    return "Moderately active"
        case .veryActive:  return "Very active"
        case .extraActive: return "Extremely active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary:   return "Desk job, little exercise"
        case .light:       return "Light exercise 1–3 days/week"
        case .moderate:    return "Moderate exercise 3–5 days/week"
        case .veryActive:  return "Hard exercise 6–7 days/week"
        case .extraActive: return "Hard daily exercise + physical job"
        }
    }
}

/// The pace + DIRECTION of the weight goal. Loss biases toward gentle, sustainable
/// rates (never crash diets); gain biases toward a "lean bulk" (small surplus, never
/// piling on fat). The signed weekly rate drives everything: negative = lose,
/// 0 = maintain, positive = gain.
enum GoalPace: String, Codable, CaseIterable, Identifiable {
    // Loss (existing — unchanged values so current users are byte-identical)
    case relaxed       // lose ~0.5 lb/wk
    case steady        // lose ~1.0 lb/wk
    case ambitious     // lose ~1.5 lb/wk
    case maintain      // 0 lb/wk
    // Gain (new — lean-bulk paces)
    case leanGain      // gain ~0.5 lb/wk
    case steadyGain    // gain ~1.0 lb/wk
    var id: String { rawValue }

    /// Which direction this pace moves weight.
    enum Direction { case lose, maintain, gain }
    var direction: Direction {
        switch self {
        case .relaxed, .steady, .ambitious: return .lose
        case .maintain:                      return .maintain
        case .leanGain, .steadyGain:         return .gain
        }
    }

    /// SIGNED weekly rate in lb: negative = losing, positive = gaining.
    var signedWeeklyRateLbs: Double {
        switch self {
        case .relaxed:    return -0.5
        case .steady:     return -1.0
        case .ambitious:  return -1.5
        case .maintain:   return 0.0
        case .leanGain:   return 0.5
        case .steadyGain: return 1.0
        }
    }

    /// Magnitude only (kept for existing call sites: loss timeline/projection math).
    var weeklyRateLbs: Double { abs(signedWeeklyRateLbs) }

    /// SIGNED daily kcal adjustment (~3500 kcal/lb → 500 kcal/lb-week).
    /// Negative = deficit (eat less than TDEE), positive = surplus (eat more).
    var dailyCalorieAdjustment: Double { signedWeeklyRateLbs * 500.0 }

    /// Back-compat: the loss-only call site expects a non-negative deficit.
    var dailyDeficit: Double { max(0, -dailyCalorieAdjustment) }

    /// Paces offered to a user, filtered by their goal direction (set during onboarding).
    static func paces(for direction: Direction) -> [GoalPace] {
        allCases.filter { $0.direction == direction || $0 == .maintain }
    }

    var label: String {
        switch self {
        case .relaxed:    return "Relaxed"
        case .steady:     return "Steady"
        case .ambitious:  return "Ambitious"
        case .maintain:   return "Maintain"
        case .leanGain:   return "Lean gain"
        case .steadyGain: return "Steady gain"
        }
    }

    var subtitle: String {
        switch self {
        case .relaxed:    return "About 0.5 lb / week"
        case .steady:     return "About 1 lb / week"
        case .ambitious:  return "About 1.5 lb / week"
        case .maintain:   return "Hold steady"
        case .leanGain:   return "About 0.5 lb / week"
        case .steadyGain: return "About 1 lb / week"
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case imperial, metric
    var id: String { rawValue }
    /// The unit every weight is stored, entered and shown in. Pounds for BOTH systems: the
    /// app has no kg conversion, and labelling a stored pound value "kg" is how a weigh-in
    /// typed in kg came to be stored as pounds (EVAL_REPORT 3, L-B7). Vita's `set_units`
    /// declines metric for the same reason. `metric` stays a case so a profile that was
    /// switched before this still decodes; `docs/settings-dependencies.md` lists every
    /// weight input and output a real conversion has to cover.
    var weightUnit: String { "lb" }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack, other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .breakfast: return "sun.horizon.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "carrot.fill"
        case .other:     return "fork.knife"
        }
    }
    var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .lunch:     return 1
        case .dinner:    return 2
        case .snack:     return 3
        case .other:     return 4
        }
    }
}

/// How a food entry was created — drives the confidence/edit affordances in the UI.
enum FoodSource: String, Codable, CaseIterable, Identifiable {
    case photo, barcode, search, manual, quickAdd, favorite
    var id: String { rawValue }
}

enum EstimateConfidence: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case strength, cardio, walk, run, cycle, yoga, hiit, sports, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hiit: return "HIIT"
        default:    return rawValue.capitalized
        }
    }
    var systemImage: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio:   return "heart.fill"
        case .walk:     return "figure.walk"
        case .run:      return "figure.run"
        case .cycle:    return "figure.outdoor.cycle"
        case .yoga:     return "figure.yoga"
        case .hiit:     return "bolt.fill"
        case .sports:   return "sportscourt.fill"
        case .other:    return "figure.mixed.cardio"
        }
    }
}

/// The "type of day" for a strength session — the training split. Optional, and only
/// meaningful for gym/strength workouts, so she (and the AI) can see "push day / leg day"
/// patterns over time and tailor advice. Never required.
enum WorkoutFocus: String, Codable, CaseIterable, Identifiable {
    case push, pull, legs, upper, lower, fullBody, core, cardio, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .push:     return "Push"
        case .pull:     return "Pull"
        case .legs:     return "Legs"
        case .upper:    return "Upper body"
        case .lower:    return "Lower body"
        case .fullBody: return "Full body"
        case .core:     return "Core"
        case .cardio:   return "Cardio"
        case .other:    return "Other"
        }
    }
}
