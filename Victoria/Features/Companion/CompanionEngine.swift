import SwiftUI

// MARK: - Companion (Tamagotchi-style buddy)
//
// A little creature that lives in the app and reflects how WELL-FED and cared-for
// Victoria is today. It is deliberately **health-positive / anti-restriction**:
//
//   • It THRIVES when she has eaten *enough* of her calorie target, hit a healthy
//     share of her protein, and stayed hydrated — i.e. when she fuels her body.
//   • It gets progressively sleepy / hungry / weak when she UNDER-eats or stops
//     logging. The single worst state is *under-eating*, because the real user
//     loves food, wrongly believes she's "fat", and tends to restrict.
//   • It NEVER reacts negatively to eating "a lot." There is intentionally no
//     "too much" / "over" / "stuffed" state and no shaming language anywhere —
//     going over target is, if anything, totally fine and never penalised. The
//     fractions below are clamped at 1.0 so "more than the target" simply reads
//     as a full, happy meter, never as a problem.
//
// This type is PURE (no SwiftUI views, no SwiftData, no I/O) so the threshold
// logic can be unit-tested in isolation. `CompanionCard` renders the result.

/// The companion's emotional state, from best (well-fed) to most in-need (hungry).
///
/// Ordered intentionally from healthiest → most under-fuelled. The `evaluate`
/// logic only ever moves *down* this list as fuel drops; it never punishes a
/// high intake.
enum CompanionMood: Int, CaseIterable, Comparable {
    /// Eating enough + balanced + hydrated. The reward state.
    case thriving
    /// Doing great, just a little short on one need.
    case happy
    /// Coasting — fed enough to be okay, room to round out the day.
    case content
    /// Running low on fuel/water; getting drowsy. A gentle nudge, not alarm.
    case sleepy
    /// Clearly under-eating. The most in-need state — always kind, never scolding.
    case hungry

    static func < (lhs: CompanionMood, rhs: CompanionMood) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short, friendly name for the state (shown under the face).
    var label: String {
        switch self {
        case .thriving: return "Thriving"
        case .happy:    return "Happy"
        case .content:  return "Content"
        case .sleepy:   return "Sleepy"
        case .hungry:   return "Hungry"
        }
    }

    /// SF Symbol used as the creature's "face" — a safe fallback until pixel-art
    /// of Victoria's buddy is dropped in. All verified to exist on iOS 18.
    var faceSymbol: String {
        switch self {
        case .thriving: return "face.smiling.inverse"
        case .happy:    return "face.smiling"
        case .content:  return "face.smiling"
        case .sleepy:   return "moon.zzz.fill"
        case .hungry:   return "fork.knife"
        }
    }

    /// A tiny status glyph that floats by the creature to amplify the mood
    /// (sparkles when thriving, a little "zzz" when sleepy, etc.).
    var auraSymbol: String {
        switch self {
        case .thriving: return "sparkles"
        case .happy:    return "heart.fill"
        case .content:  return "leaf.fill"
        case .sleepy:   return "zzz"
        case .hungry:   return "drop.fill"
        }
    }

    /// Accent color drawn from the Theme palette — bright/positive at the top,
    /// cooler/calmer as the buddy gets sleepy or hungry. Never red; nothing here
    /// is an "error", it's just a need waiting to be met.
    var accent: Color {
        switch self {
        case .thriving: return Theme.brand     // electric lime — the reward color
        case .happy:    return Theme.positive  // soft green
        case .content:  return Theme.info      // calm blue
        case .sleepy:   return Theme.water      // cool cyan, drowsy
        case .hungry:   return Theme.warning    // warm amber — "I need a little fuel"
        }
    }
}

/// A normalized 0...1 reading of one of the buddy's "needs" (food / protein /
/// water). Always clamped, so going over a target reads as a full, content meter
/// — never as an overflow to worry about.
struct CompanionNeed: Identifiable {
    enum Kind: String, CaseIterable {
        case food, protein, water
    }

    let kind: Kind
    /// 0...1, where 1 means "this need is fully met (or exceeded)".
    let fraction: Double

    var id: String { kind.rawValue }

    /// True once this need is comfortably met — drives the "filled" pip styling.
    var isMet: Bool { fraction >= 0.85 }

    var label: String {
        switch kind {
        case .food:    return "Food"
        case .protein: return "Protein"
        case .water:   return "Water"
        }
    }

    /// Verified SF Symbols (iOS 18).
    var systemImage: String {
        switch kind {
        case .food:    return "flame.fill"
        case .protein: return "bolt.fill"
        case .water:   return "drop.fill"
        }
    }

    /// Matches the app's existing metric colors (calories = lime, protein = blue,
    /// water = cyan) so the pips read consistently with the dashboard.
    var tint: Color {
        switch kind {
        case .food:    return Theme.calories
        case .protein: return Theme.protein
        case .water:   return Theme.water
        }
    }
}

/// The full, render-ready snapshot the view consumes. Produced by `evaluate`.
struct CompanionState {
    let mood: CompanionMood
    /// A warm, first-person line from the buddy for this mood.
    let message: String
    /// The three need readings, each 0...1 (food, protein, water), in display order.
    let needs: [CompanionNeed]

    /// Convenience accessors for the individual ring/pip fractions.
    var foodFraction: Double    { needs.first { $0.kind == .food }?.fraction ?? 0 }
    var proteinFraction: Double { needs.first { $0.kind == .protein }?.fraction ?? 0 }
    var waterFraction: Double   { needs.first { $0.kind == .water }?.fraction ?? 0 }

    /// A single 0...1 "overall vitality" used for the creature's halo/ring. The
    /// average of the three needs — a simple, honest read of how fuelled she is.
    var vitality: Double {
        guard !needs.isEmpty else { return 0 }
        return needs.map(\.fraction).reduce(0, +) / Double(needs.count)
    }
}

// MARK: - Evaluation

enum CompanionEngine {

    /// Tunable thresholds (fractions of each daily target). Pulled out so the
    /// intent is legible and the logic stays easy to test/adjust.
    ///
    /// Anti-restriction note: every threshold is a *minimum* — "have you had
    /// **enough**?" There is no upper bound anywhere. Eating past a target is
    /// always fine and is treated identically to exactly hitting it.
    enum Threshold {
        /// Thriving requires a healthy share of each need.
        static let thrivingCalories = 0.80
        static let thrivingProtein  = 0.70
        static let thrivingWater     = 0.60

        /// Happy — eating well, maybe a little short on one thing.
        static let happyCalories = 0.65
        static let happyProtein  = 0.50

        /// Content — fed enough to be okay for now.
        static let contentCalories = 0.45

        /// Below this, by the time the day is winding down, she's truly
        /// under-eating → the gentle "let's get you some fuel" state.
        static let underEatingCalories = 0.40
    }

    /// Evaluate the buddy's state from today's running totals vs. the user's
    /// targets. Everything is health-positive: the function rewards *eating
    /// enough* and only ever gets sadder as fuel drops.
    ///
    /// - Parameters:
    ///   - caloriesEaten: kcal logged so far today.
    ///   - calorieTarget: her daily calorie target (from `UserProfile`).
    ///   - protein:       grams of protein logged today.
    ///   - proteinTarget: her daily protein target (g).
    ///   - waterOz:       fluid ounces of water logged today.
    ///   - waterTargetOz: her daily water target (oz).
    ///   - loggedToday:   whether she's logged *anything* today. Drives the
    ///                    encouraging "let's start the day" copy when false.
    static func evaluate(caloriesEaten: Double,
                         calorieTarget: Double,
                         protein: Double,
                         proteinTarget: Double,
                         waterOz: Double,
                         waterTargetOz: Double,
                         loggedToday: Bool) -> CompanionState {

        // Normalize each need to 0...1. Clamp at 1 so "over target" = a full,
        // happy meter (NEVER an overflow / problem). Guard against zero targets.
        let calFrac   = clamp01(safeRatio(caloriesEaten, calorieTarget))
        let proFrac   = clamp01(safeRatio(protein, proteinTarget))
        let waterFrac = clamp01(safeRatio(waterOz, waterTargetOz))

        let needs = [
            CompanionNeed(kind: .food,    fraction: calFrac),
            CompanionNeed(kind: .protein, fraction: proFrac),
            CompanionNeed(kind: .water,   fraction: waterFrac)
        ]

        let mood = mood(calFrac: calFrac,
                        proFrac: proFrac,
                        waterFrac: waterFrac,
                        loggedToday: loggedToday)

        return CompanionState(mood: mood,
                              message: message(for: mood, loggedToday: loggedToday),
                              needs: needs)
    }

    // MARK: Mood decision

    /// Picks a mood from the (clamped) need fractions. Reads top-down: best case
    /// first, falling through to gentler/needier states. Calories — *fuel* — is
    /// the dominant signal, because under-eating is the thing we most want to
    /// catch and kindly counter.
    private static func mood(calFrac: Double,
                             proFrac: Double,
                             waterFrac: Double,
                             loggedToday: Bool) -> CompanionMood {

        // Nothing logged yet: she hasn't fuelled up, so the buddy is sleepy and
        // waiting — but the *copy* (see `message`) is an invitation, not a worry.
        guard loggedToday else { return .sleepy }

        // Clearly under-eating is the most-in-need state. Checked FIRST so it
        // always wins, even if (somehow) protein/water look okay.
        if calFrac < Threshold.underEatingCalories {
            return .hungry
        }

        // Thriving: a healthy share of ALL three needs.
        if calFrac >= Threshold.thrivingCalories,
           proFrac >= Threshold.thrivingProtein,
           waterFrac >= Threshold.thrivingWater {
            return .thriving
        }

        // Happy: eating well + decent protein, just not fully topped up.
        if calFrac >= Threshold.happyCalories,
           proFrac >= Threshold.happyProtein {
            return .happy
        }

        // Content: fed enough to be okay; room to round out the day.
        if calFrac >= Threshold.contentCalories {
            return .content
        }

        // Between under-eating and "content" — low-ish fuel, getting drowsy.
        return .sleepy
    }

    // MARK: Copy
    //
    // Every line is first-person, warm, and framed around *fuelling* her — never
    // around weight, restriction, or eating "too much". The hungry line is the
    // emotional heart: a soft 🥺 plea to eat *something*, with zero guilt.

    private static func message(for mood: CompanionMood, loggedToday: Bool) -> String {
        if !loggedToday {
            return "Morning! I'm still a little sleepy — log a bite or some water and I'll wake right up 💛"
        }
        switch mood {
        case .thriving:
            return "I feel amazing — you've fed us so well today! Look at us glow ✨"
        case .happy:
            return "Mmm, that hit the spot. A little more and we'll be unstoppable 💪"
        case .content:
            return "We're doing okay! Got room for a snack? I'd love a little more fuel 🌱"
        case .sleepy:
            return "I'm getting a bit drowsy… a snack or some water would perk us right up 😴"
        case .hungry:
            return "I'm getting hungry — let's eat something, okay? Fuelling up makes us both stronger 🥺"
        }
    }

    // MARK: Math helpers (kept tiny + pure)

    private static func safeRatio(_ value: Double, _ target: Double) -> Double {
        target > 0 ? value / target : 0
    }

    private static func clamp01(_ x: Double) -> Double {
        min(1, max(0, x))
    }
}
