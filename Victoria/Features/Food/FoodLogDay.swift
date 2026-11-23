import Foundation

/// Which day the Nutrients tab should show after time has passed while it was open.
enum FoodLogDay {

    /// The view keeps the selected day in memory, and the app can sit in the background
    /// across midnight. If the user was on "today" when we last looked, they are still on
    /// today, so the selection moves to the new day (otherwise a meal added on Tuesday
    /// morning is saved to Monday). If they had browsed to another day, it is left alone.
    ///
    /// - Parameters:
    ///   - selected: the day currently shown (start of day).
    ///   - lastKnownToday: the start of "today" as of the last check.
    ///   - now: the current instant.
    /// - Returns: the day to show, and the new `lastKnownToday`.
    static func rolledForward(selected: Date, lastKnownToday: Date, now: Date,
                              calendar: Calendar = .current) -> (selected: Date, today: Date) {
        let today = calendar.startOfDay(for: now)
        guard today != lastKnownToday else { return (selected, today) }
        let wasFollowingToday = calendar.isDate(selected, inSameDayAs: lastKnownToday)
        // A selection can never sit in the future (e.g. after the clock or zone moved back).
        let next = wasFollowingToday ? today : min(selected, today)
        return (next, today)
    }
}
