import Foundation

/// The "cheap, code-owned gate" for Smart Food Suggestions — pure, free, on-device.
///
/// Architecture (mirrors `CoachContext` + `DailyInsightEngine`): **every number is
/// computed here, in Swift.** The LLM never does arithmetic and never decides what's
/// true — it only *phrases* suggestions over the factual `Context` this engine builds.
/// That keeps the math correct, testable, and impossible for the model to fabricate.
///
/// What it figures out from her REAL data:
/// - the current meal slot from the time of day (so a suggestion lands as breakfast vs. dinner),
/// - how much room she has left today to ADD calories + protein toward her targets,
/// - her most-frequently-logged foods over the last ~2 weeks (so suggestions reference
///   foods she actually eats — "the chicken bowl you love", not generic advice),
/// - whether she's been trending UNDER her protein target lately (the #1 satiety/results lever),
/// - her goal direction (lose / maintain / gain).
///
/// Tone contract (read `SmartSuggestionsView` / `FoodSuggestionService` too): this powers a
/// sharp, encouraging friend who wants her to WIN. Suggestions are additive/upgrade-oriented
/// (add protein, swap up to a better version of what she already eats, hit satiety, fuel
/// results). The engine only supplies facts and a couple of *directional* flags — it never
/// emits user-facing copy, and it carries no shame/restriction framing.
enum FoodSuggestionEngine {

    // MARK: - Meal slot

    /// The four meal slots, matching `MealType` but defined here so the *pure* engine
    /// (and its tests) don't depend on the model layer's enum semantics.
    enum MealSlot: String, Equatable {
        case breakfast, lunch, dinner, snack

        /// Human label used inside the LLM prompt ("It's around lunch").
        var label: String { rawValue }

        /// Bridge to the app's `MealType` so callers can pre-select the right meal when
        /// she taps through to log. One-to-one mapping.
        var mealType: MealType {
            switch self {
            case .breakfast: return .breakfast
            case .lunch:     return .lunch
            case .dinner:    return .dinner
            case .snack:     return .snack
            }
        }
    }

    /// The meal slot for a given hour of day (0...23). Bucketing favors the *next*
    /// eating opportunity so a suggestion is forward-looking:
    /// - 4–11  → breakfast
    /// - 11–15 → lunch
    /// - 15–17 → snack (the classic afternoon gap)
    /// - 17–22 → dinner
    /// - else (late night / pre-dawn) → snack
    ///
    /// Deliberately mirrors the boundaries of `MealTime.current` already used by the
    /// photo-log default so the whole app agrees on "what meal is it right now."
    static func mealSlot(hourOfDay hour: Int) -> MealSlot {
        switch hour {
        case 4..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default:      return .snack
        }
    }

    /// Convenience: the meal slot for a concrete `Date` (defaults to now).
    static func mealSlot(at date: Date = .now, calendar: Calendar = .current) -> MealSlot {
        mealSlot(hourOfDay: calendar.component(.hour, from: date))
    }

    // MARK: - Top foods

    /// A frequently-logged food, with how often she's logged it in the window and a
    /// representative protein-per-serving figure (averaged across those logs). The
    /// protein average lets the prompt say "your usual X is light on protein" honestly.
    struct TopFood: Equatable {
        let name: String
        let count: Int
        let avgProteinG: Double
    }

    /// Her most-frequently-logged foods over the last `days` days, most-frequent first.
    ///
    /// Grouping is case-insensitive and trims whitespace so "Greek yogurt" and
    /// "greek yogurt " collapse into one. Ties break by the most *recent* log (so a food
    /// she ate yesterday outranks one she ate twice last week), then alphabetically for
    /// determinism in tests. Empty / blank names are ignored.
    static func topFoods(_ foods: [FoodEntry],
                         days: Int = 14,
                         limit: Int = 5,
                         now: Date = .now,
                         calendar: Calendar = .current) -> [TopFood] {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        let recent = foods.filter { $0.date >= cutoff }

        // Aggregate by a normalized key while keeping the original display casing.
        struct Agg { var display: String; var count: Int; var proteinSum: Double; var lastDate: Date }
        var byKey: [String: Agg] = [:]
        for f in recent {
            let display = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = display.lowercased()
            if var a = byKey[key] {
                a.count += 1
                a.proteinSum += f.proteinG
                if f.date > a.lastDate { a.lastDate = f.date }
                byKey[key] = a
            } else {
                byKey[key] = Agg(display: display, count: 1, proteinSum: f.proteinG, lastDate: f.date)
            }
        }

        return byKey.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }      // most frequent
                if lhs.lastDate != rhs.lastDate { return lhs.lastDate > rhs.lastDate } // then most recent
                return lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending
            }
            .prefix(limit)
            .map { TopFood(name: $0.display,
                           count: $0.count,
                           avgProteinG: $0.count > 0 ? $0.proteinSum / Double($0.count) : 0) }
    }

    // MARK: - Protein trend

    /// Whether she's been averaging UNDER her protein target across the recent logged
    /// days. We only count days she actually logged food (skipping empty days avoids
    /// punishing a day she simply didn't track), require at least `minDays` of data so
    /// one light day can't flip it, and use a small tolerance so being a hair under
    /// doesn't read as "under."
    ///
    /// Returns `nil` when there isn't enough data to say (caller treats nil as "unknown",
    /// not "fine") — `false` means she's genuinely been hitting it.
    static func isUnderProteinTrend(_ foods: [FoodEntry],
                                    proteinTarget: Double,
                                    days: Int = 7,
                                    minDays: Int = 3,
                                    tolerance: Double = 0.9,
                                    now: Date = .now,
                                    calendar: Calendar = .current) -> Bool? {
        guard proteinTarget > 0 else { return nil }
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now

        // Sum protein per calendar day (only days with logs count).
        var proteinByDay: [Date: Double] = [:]
        for f in foods where f.date >= cutoff {
            let day = calendar.startOfDay(for: f.date)
            proteinByDay[day, default: 0] += f.proteinG
        }
        guard proteinByDay.count >= minDays else { return nil }

        let avg = proteinByDay.values.reduce(0, +) / Double(proteinByDay.count)
        return avg < proteinTarget * tolerance
    }

    // MARK: - Context (the factual snapshot handed to the LLM)

    /// Goal direction, decoupled from `GoalPace.Direction` so the pure engine + tests
    /// don't depend on the model layer. The caller maps one to the other.
    enum Direction: String, Equatable { case lose, maintain, gain }

    /// Everything the LLM needs to phrase good suggestions — and nothing it could get
    /// wrong. All numbers are pre-computed and rounded; the model only writes sentences.
    struct Context: Equatable {
        // Identity / framing
        var name: String                 // her first name (or "" → engine uses a neutral fallback)
        var direction: Direction

        // Today so far vs. targets — "remaining" is ROOM TO ADD (clamped ≥ 0).
        var calorieTarget: Int
        var caloriesEaten: Int
        var caloriesRemaining: Int
        var proteinTarget: Int
        var proteinEaten: Int
        var proteinRemaining: Int

        // When it is (for the model) + the slot we chose.
        var mealSlot: MealSlot

        // Behavior signals
        var topFoods: [TopFood]          // most-frequent first (may be empty)
        var underProteinTrend: Bool?     // true = trending under lately; nil = unknown

        // What she's already eaten TODAY (item names, newest first), so a pick never re-pitches
        // something she's already had (e.g. a second protein shake) and builds on the real day.
        var eatenToday: [String] = []

        // Optional location flavor — a single nearby healthy spot to (maybe) reference.
        var nearbyPlace: NearbyPlace?

        /// True when there's essentially nothing to personalize from yet — drives the
        /// "log a few meals and I'll tailor picks" empty state in the UI.
        var hasEnoughHistory: Bool { !topFoods.isEmpty }
    }

    /// A nearby place worth a suggestion (e.g. a grocery store or salad spot). Kept as a
    /// plain value here so the engine stays free of MapKit; `NearbyPlacesService`
    /// produces these.
    struct NearbyPlace: Equatable {
        var name: String
        /// A short category word for phrasing ("grocery", "salad", "café"). Optional.
        var category: String?
    }

    /// Build the factual `Context` from raw inputs. Pure — no SwiftData, no I/O, no clock
    /// except the injected `now` (so tests are deterministic).
    ///
    /// - `foods` should be the user's full recent history (the engine windows it itself).
    /// - `caloriesEatenToday` / `proteinEatenToday` are today's running totals (the caller
    ///   already computes these for the Food tab; we take them rather than re-filter, so
    ///   "today" matches exactly what she sees on screen).
    static func makeContext(name: String,
                            direction: Direction,
                            calorieTarget: Double,
                            proteinTarget: Double,
                            caloriesEatenToday: Double,
                            proteinEatenToday: Double,
                            foods: [FoodEntry],
                            nearbyPlace: NearbyPlace? = nil,
                            now: Date = .now,
                            calendar: Calendar = .current) -> Context {
        let calTarget = Int(calorieTarget.rounded())
        let calEaten = Int(caloriesEatenToday.rounded())
        let proTarget = Int(proteinTarget.rounded())
        let proEaten = Int(proteinEatenToday.rounded())

        // Names of what she's logged TODAY, newest first (blank names dropped). Drives the
        // "don't re-suggest something she's already had today" guidance in the prompt.
        let eatenTodayNames = foods
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.date > $1.date }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Context(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            direction: direction,
            calorieTarget: calTarget,
            caloriesEaten: calEaten,
            caloriesRemaining: max(0, calTarget - calEaten),
            proteinTarget: proTarget,
            proteinEaten: proEaten,
            proteinRemaining: max(0, proTarget - proEaten),
            mealSlot: mealSlot(at: now, calendar: calendar),
            topFoods: topFoods(foods, now: now, calendar: calendar),
            underProteinTrend: isUnderProteinTrend(foods, proteinTarget: proteinTarget,
                                                   now: now, calendar: calendar),
            eatenToday: eatenTodayNames,
            nearbyPlace: nearbyPlace
        )
    }

    // MARK: - Prompt rendering

    /// Render the `Context` into a compact, factual prompt block for the LLM. This is the
    /// *only* place facts become text; the model reads this and returns suggestions.
    ///
    /// We keep it terse and list-shaped (cheap tokens, easy for the model to scan) and we
    /// pre-translate the direction + protein flag into plain phrasing so the model is
    /// steered toward the right emphasis without us writing the actual suggestions.
    static func renderPrompt(_ ctx: Context) -> String {
        var lines: [String] = []

        let who = ctx.name.isEmpty ? "The user" : ctx.name
        let goal: String
        switch ctx.direction {
        case .lose:     goal = "fat loss while keeping muscle"
        case .gain:     goal = "a lean muscle gain"
        case .maintain: goal = "maintaining and recomposition"
        }
        lines.append("\(who) is working toward \(goal).")

        // What meal we're suggesting for.
        lines.append("Right now it's around \(ctx.mealSlot.label) — suggest things that fit that meal.")

        // Room to add today (framed as fuel toward the target, never as a "budget left").
        lines.append("Today so far: \(ctx.caloriesEaten) of \(ctx.calorieTarget) kcal "
                     + "(\(ctx.caloriesRemaining) kcal of room to add) and "
                     + "\(ctx.proteinEaten) of \(ctx.proteinTarget) g protein "
                     + "(\(ctx.proteinRemaining) g of protein still to hit today).")

        // Protein trend flag → directional emphasis.
        switch ctx.underProteinTrend {
        case .some(true):
            lines.append("She's been landing UNDER her protein target most days lately — "
                         + "lean toward protein-forward picks that fix that.")
        case .some(false):
            lines.append("She's been hitting her protein consistently — keep that momentum; "
                         + "you don't have to force more protein into every pick.")
        case .none:
            break   // not enough data — say nothing rather than guess
        }

        // Her real foods.
        if ctx.topFoods.isEmpty {
            lines.append("No clear pattern of go-to foods yet, so keep picks broadly useful.")
        } else {
            let list = ctx.topFoods.map { f -> String in
                let p = Int(f.avgProteinG.rounded())
                return "\(f.name) (logged \(f.count)×, ~\(p) g protein)"
            }.joined(separator: "; ")
            lines.append("Foods she logs most: \(list). "
                         + "Reference these by name where it fits — upgrade or build on what she "
                         + "already eats rather than inventing unfamiliar meals.")
        }

        // What she's already had TODAY — so a pick never repeats it (the "2nd Muscle Milk"
        // problem) and instead moves her forward to the next useful thing.
        if !ctx.eatenToday.isEmpty {
            var seen = Set<String>()
            let unique = ctx.eatenToday
                .filter { seen.insert($0.lowercased()).inserted }
                .prefix(8)
                .joined(separator: ", ")
            lines.append("She has ALREADY eaten these today: \(unique). Do not re-suggest "
                         + "something she's already had today — build on the day and suggest the "
                         + "NEXT useful thing instead.")
        }

        // Optional nearby place.
        if let place = ctx.nearbyPlace {
            let cat = place.category.map { " (\($0))" } ?? ""
            lines.append("There's a healthy option nearby: \(place.name)\(cat). "
                         + "You MAY make ONE suggestion a 'nearby' pick that references it; "
                         + "skip it if it doesn't fit naturally.")
        }

        return lines.joined(separator: "\n")
    }
}
