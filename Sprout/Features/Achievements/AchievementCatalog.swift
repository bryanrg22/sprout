import Foundation

/// # Achievements — the health-positive philosophy
///
/// Sprout is built for people who are more at risk of eating too little than too much.
/// So every badge here rewards
/// **doing more of a good thing**: eating *enough*, hitting protein, drinking
/// water, logging consistently, moving, resting, and being kind to herself.
///
/// **Hard rules baked into these rules (never violate):**
/// - We NEVER reward eating *little*, a calorie deficit, skipping meals, or any
///   "lower is better" weight milestone. There is no "lost X lbs" badge.
/// - Weight data is used *only* as a neutral "you showed up and logged a
///   check-in" signal (for streaks/consistency) — never compared to a goal,
///   never framed as good/bad.
/// - Calorie-related badges fire for *reaching* a healthy target (nourishment),
///   not for staying under it.
/// - Copy is always warm and celebratory; nothing here can shame.
///
/// `Achievement` is pure data (no SwiftUI) so the catalog + the earning logic
/// are deterministic and unit-testable. The view layer maps `tint`/`systemImage`
/// onto Theme colors and SF Symbols.

// MARK: - Achievement value type

/// A single badge in the catalog. `id` is the stable key persisted in
/// `AchievementUnlock.achievementID`; everything else is presentation + the
/// human-readable promise of the badge.
struct Achievement: Identifiable, Hashable {
    /// Stable identifier persisted in `AchievementUnlock`. Never change these
    /// once shipped, or earned badges would orphan.
    let id: String
    /// Short, punchy badge name.
    let title: String
    /// One-line, kind description of how it's earned / what it celebrates.
    let blurb: String
    /// SF Symbol name for the badge medal.
    let systemImage: String
    /// Theme token name the view resolves to a color (keeps this file SwiftUI-free).
    /// One of: brand, protein, water, carbs, fat, positive, info, warning.
    let tint: TintToken

    /// The colors a badge may use. The view maps these onto `Theme` tokens so
    /// this catalog stays a pure model with no SwiftUI dependency.
    enum TintToken: String, Hashable {
        case brand, protein, water, carbs, fat, positive, info, warning
    }
}

// MARK: - Catalog + earning logic

enum AchievementCatalog {

    /// The full, ordered catalog of badges. Order here is the display order.
    ///
    /// All 12 reward *positive* behaviors. Read each `blurb` for the promise.
    static let all: [Achievement] = [
        Achievement(
            id: "first_steps",
            title: "First Steps",
            blurb: "Logged your very first thing. The journey starts here.",
            systemImage: "sparkles",
            tint: .brand
        ),
        Achievement(
            id: "nourished_day",
            title: "Well Fed",
            blurb: "Ate enough to hit your calorie target — fuel, not restriction.",
            systemImage: "fork.knife",
            tint: .brand
        ),
        Achievement(
            id: "protein_pro",
            title: "Protein Pro",
            blurb: "Hit your protein goal for the day. Strong food for a strong you.",
            systemImage: "fish.fill",
            tint: .protein
        ),
        Achievement(
            id: "hydrated",
            title: "Hydrated",
            blurb: "Reached your water goal. Your body says thank you.",
            systemImage: "drop.fill",
            tint: .water
        ),
        Achievement(
            id: "treat_yourself",
            title: "Treat Yourself",
            blurb: "Logged a treat — guilt-free. Joy is part of a healthy life.",
            systemImage: "birthday.cake.fill",
            tint: .carbs
        ),
        Achievement(
            id: "early_bird",
            title: "Early Bird",
            blurb: "Logged breakfast. A fed morning is a kinder day.",
            systemImage: "sun.horizon.fill",
            tint: .warning
        ),
        Achievement(
            id: "balanced_plate",
            title: "Balanced Plate",
            blurb: "Logged protein, carbs, and fat in one day — all three matter.",
            systemImage: "circle.hexagongrid.fill",
            tint: .fat
        ),
        Achievement(
            id: "strong",
            title: "Strong",
            blurb: "Logged a workout. Showing up is the whole win.",
            systemImage: "dumbbell.fill",
            tint: .positive
        ),
        Achievement(
            id: "on_the_move",
            title: "On the Move",
            blurb: "Hit your step goal for a day. Movement you enjoy counts.",
            systemImage: "figure.walk",
            tint: .info
        ),
        Achievement(
            id: "consistency_7",
            title: "Consistency",
            blurb: "Logged something 7 days in a row. Habits beat willpower.",
            systemImage: "flame.fill",
            tint: .warning
        ),
        Achievement(
            id: "nourished_3",
            title: "Nourished",
            blurb: "Met your calorie target on 3 different days. Steady fuel.",
            systemImage: "leaf.fill",
            tint: .positive
        ),
        Achievement(
            id: "self_kindness",
            title: "Self-Kindness",
            blurb: "Two full weeks of checking in. Proud of how you show up.",
            systemImage: "heart.fill",
            tint: .brand
        ),
    ]

    /// Look a badge up by its stable id.
    static func achievement(id: String) -> Achievement? {
        all.first { $0.id == id }
    }

    // MARK: Earning evaluation

    /// Returns the achievements whose rule is satisfied by the given data and
    /// that are **not** already in `alreadyUnlocked`. Pure + deterministic so it
    /// can be unit-tested without a SwiftData store.
    ///
    /// Every rule below rewards a *positive* action (eating enough, protein,
    /// water, movement, consistency, a treat). None reward eating little or a
    /// weight number. Weight entries contribute only to "you logged a check-in"
    /// signals (streak / distinct days), never to a goal comparison.
    ///
    /// It only ever reports badges to ADD: a badge in `alreadyUnlocked` is never returned
    /// and nothing here takes one away, so a badge unlocked under an earlier rule stays.
    /// `now` and `calendar` say what "today" is; a test passes its own.
    static func newlyEarned(
        foods: [FoodEntry],
        weights: [WeightEntry],
        water: [WaterEntry],
        steps: [StepsEntry],
        workouts: [WorkoutSession],
        profile: UserProfile,
        alreadyUnlocked: Set<String>,
        now: Date = .now,
        calendar cal: Calendar = .current
    ) -> [Achievement] {

        // Weight to base targets on — mirror the dashboard: smoothed trend, then
        // start weight, then a neutral 150 fallback. (Used ONLY to know what
        // "enough" food is; never to judge the weight itself.)
        let basisWeight = TrendCalculator.currentTrend(weights)
            ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
        let calorieTarget = profile.dailyCalorieTarget(weightLbs: basisWeight)
        let proteinTarget = profile.macroTargets(weightLbs: basisWeight).proteinG
        let waterTarget = profile.waterTargetOz
        let stepGoal = profile.dailyStepGoal

        // --- Per-day aggregates over food ---
        let foodByDay = Dictionary(grouping: foods) { cal.startOfDay(for: $0.date) }

        /// Days on which she ate at least `calorieTarget` (reaching the target =
        /// nourished). We only count days with *some* food so an empty day with a
        /// target of 0 can't trivially qualify.
        let nourishedDays: Set<Date> = {
            guard calorieTarget > 0 else { return [] }
            return Set(foodByDay.compactMap { day, items -> Date? in
                let total = items.reduce(0) { $0 + $1.totalCalories }
                return total >= calorieTarget ? day : nil
            })
        }()

        /// Days she hit her protein goal.
        let proteinHitToday: Bool = {
            guard proteinTarget > 0 else { return false }
            let todayProtein = foods
                .filter { cal.isDate($0.date, inSameDayAs: now) }
                .reduce(0) { $0 + $1.totalProteinG }
            return todayProtein >= proteinTarget
        }()

        // --- Days in a row the user logged something, ending today ---
        // `StreakCalculator`'s definition, the one behind the header streak: food, water
        // or a weigh-in entered by hand. Steps imported from Apple Health (a month of them
        // is backfilled at first launch) and scale-synced weights are not logging; counting
        // them unlocked the 7- and 14-day badges on day one.
        let currentStreak = StreakCalculator.loggingStreak(foods: foods, waters: water, weights: weights,
                                                           calendar: cal, now: now)

        // --- Hydration: did any single day reach the water goal? ---
        let waterByDay = Dictionary(grouping: water) { cal.startOfDay(for: $0.date) }
        let hitWaterGoalSomeDay: Bool = {
            guard waterTarget > 0 else { return false }
            return waterByDay.values.contains { dayDrinks in
                dayDrinks.reduce(0) { $0 + $1.amountOz } >= waterTarget
            }
        }()

        // --- Steps: did any logged day reach the step goal? ---
        let hitStepGoalSomeDay: Bool = {
            guard stepGoal > 0 else { return false }
            return steps.contains { $0.count >= stepGoal }
        }()

        // --- Breakfast logged ever? ---
        let loggedBreakfast = foods.contains { $0.mealType == .breakfast }

        // --- Balanced plate: a single day with protein, carbs, AND fat all > 0 ---
        let hadBalancedDay = foodByDay.values.contains { items in
            let p = items.reduce(0) { $0 + $1.totalProteinG }
            let c = items.reduce(0) { $0 + $1.totalCarbsG }
            let f = items.reduce(0) { $0 + $1.totalFatG }
            return p > 0 && c > 0 && f > 0
        }

        // --- Treat: a dessert/treat logged, guilt-free. Detected by name keywords
        // (so it works regardless of meal type) OR a snack-type entry whose name
        // reads like a treat. Deliberately generous — we WANT this to fire. ---
        let loggedTreat = foods.contains { isTreat($0) }

        // --- Activity ---
        let loggedWorkout = !workouts.isEmpty
        let loggedAnything = !foods.isEmpty || !weights.isEmpty
            || !water.isEmpty || !steps.isEmpty || !workouts.isEmpty

        // Map each badge id to whether its rule is satisfied now.
        let satisfied: [String: Bool] = [
            "first_steps":     loggedAnything,
            "nourished_day":   !nourishedDays.isEmpty,
            "protein_pro":     proteinHitToday,
            "hydrated":        hitWaterGoalSomeDay,
            "treat_yourself":  loggedTreat,
            "early_bird":      loggedBreakfast,
            "balanced_plate":  hadBalancedDay,
            "strong":          loggedWorkout,
            "on_the_move":     hitStepGoalSomeDay,
            "consistency_7":   currentStreak >= 7,
            "nourished_3":     nourishedDays.count >= 3,
            "self_kindness":   currentStreak >= 14,
        ]

        // Preserve catalog order; only return newly-satisfied, not-yet-unlocked.
        return all.filter { badge in
            (satisfied[badge.id] ?? false) && !alreadyUnlocked.contains(badge.id)
        }
    }

    // MARK: Helpers

    /// Treats/desserts she can log guilt-free. Matches common dessert/treat words
    /// in the entry name, or a snack entry that reads like one. Case-insensitive.
    static func isTreat(_ food: FoodEntry) -> Bool {
        let name = food.name.lowercased()
        let treatWords = [
            "dessert", "treat", "cake", "cookie", "brownie", "ice cream",
            "chocolate", "candy", "donut", "doughnut", "pie", "pastry",
            "cupcake", "muffin", "croissant", "cheesecake", "pudding",
            "milkshake", "shake", "fries", "pizza", "chips", "gelato",
            "waffle", "pancake", "syrup", "froyo", "sundae", "macaron",
        ]
        return treatWords.contains { name.contains($0) }
    }
}
