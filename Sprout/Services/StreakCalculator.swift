import Foundation

/// The single source of truth for the "logging streak" — consecutive days, counting back from
/// today, that the user ACTIVELY logged something in the app.
///
/// "Actively logged" = a food entry, a water entry, or a MANUAL weigh-in. It deliberately does
/// NOT count passively-synced Apple Health data:
/// - **Steps** are imported automatically (we backfill ~30 days on launch), so counting them
///   would read as a multi-week "streak" the user never earned — this was the "30-day streak out
///   of nowhere" bug.
/// - **Scale-synced weights** carry a `healthKitUUID`, so they're excluded too; only weigh-ins the
///   user entered by hand (no `healthKitUUID`) count.
///
/// Used by the dashboard, the widget, and the coach so every surface reports the SAME streak.
enum StreakCalculator {

    /// The set of days the user ACTIVELY logged (food / water / MANUAL weigh-in), as start-of-day
    /// dates, optionally dropping anything before `since` (the account start). This is the single
    /// definition of "a day you showed up": the streak count AND the consistency heatmap both
    /// derive from it, so they can never disagree. Excludes auto-imported steps and scale-synced
    /// weights (see the note above).
    static func loggedDays(foods: [FoodEntry],
                           waters: [WaterEntry] = [],
                           weights: [WeightEntry],
                           since: Date? = nil,
                           calendar cal: Calendar = .current) -> Set<Date> {
        var days = Set(foods.map { cal.startOfDay(for: $0.date) })
        days.formUnion(waters.map { cal.startOfDay(for: $0.date) })
        // Manual weigh-ins only — scale-synced ones carry a healthKitUUID and don't count as "logging".
        days.formUnion(weights.filter { $0.healthKitUUID == nil }.map { cal.startOfDay(for: $0.date) })
        if let since {
            let floor = cal.startOfDay(for: since)
            days = days.filter { $0 >= floor }
        }
        return days
    }

    /// How many days ago the most recent active log BEFORE today was — the "comeback" signal.
    /// `1` = logged yesterday (no gap), `14` = two silent weeks, `nil` = never logged before
    /// today (brand-new user — a first log is a beginning, not a comeback).
    ///
    /// Today's own logs are deliberately excluded: the moment she logs after two weeks away,
    /// today has entries but the gap she just crossed is still the story every surface needs
    /// (Vita's framing, the welcome-back card, insight suppression). Counting today would
    /// make the gap vanish at the exact moment it matters most.
    static func daysSinceLastLog(foods: [FoodEntry],
                                 waters: [WaterEntry] = [],
                                 weights: [WeightEntry],
                                 since: Date? = nil,
                                 calendar cal: Calendar = .current,
                                 now: Date = .now) -> Int? {
        let today = cal.startOfDay(for: now)
        let past = loggedDays(foods: foods, waters: waters, weights: weights, since: since, calendar: cal)
            .filter { $0 < today }
        guard let latest = past.max() else { return nil }
        return cal.dateComponents([.day], from: latest, to: today).day
    }

    /// Consecutive days with an active log, counting back from `now`. Returns 0 if today has none.
    /// Pass `since` to clamp to the account start so nothing before it can ever count.
    static func loggingStreak(foods: [FoodEntry],
                              waters: [WaterEntry] = [],
                              weights: [WeightEntry],
                              since: Date? = nil,
                              calendar cal: Calendar = .current,
                              now: Date = .now) -> Int {
        let days = loggedDays(foods: foods, waters: waters, weights: weights, since: since, calendar: cal)
        var streak = 0
        var day = cal.startOfDay(for: now)
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}
