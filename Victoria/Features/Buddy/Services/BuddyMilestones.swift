import Foundation

/// Detects the moment someone crosses a goal, so their buddy can be auto-cheered
/// ("🎉 Alex just hit their calorie goal today!"). The ping itself is an ordinary nudge.
///
/// A daily goal (calories, protein, steps, water) is celebrated at most once per day. A
/// streak tier (3, 7, 14, 30 days) is celebrated once per streak: day four of a streak is
/// not another "3-day streak". A milestone counts as celebrated only once its nudge was
/// actually sent (`pending` then `markSent`), so one that failed to send is tried again.
enum BuddyMilestone: String, CaseIterable {
    case calories, protein, steps, water
    case streak3, streak7, streak14, streak30

    /// The warm message the BUDDY receives. `name` is the achiever's display name.
    /// Health-POSITIVE only — celebrates *reaching* (we fuel toward goals, never restrict).
    func message(name: String) -> String {
        switch self {
        case .calories: return "🎉 \(name) just hit their calorie goal today!"
        case .protein:  return "💪 \(name) just hit their protein goal!"
        case .steps:    return "🚶 \(name) just reached their step goal!"
        case .water:    return "💧 \(name) just finished their water for the day!"
        case .streak3:  return "🔥 \(name) is on a 3-day logging streak!"
        case .streak7:  return "🔥 \(name) just hit a 7-day streak — a whole week!"
        case .streak14: return "🔥 \(name) is on a 14-day streak. Amazing."
        case .streak30: return "🏆 \(name) just hit a 30-DAY streak!"
        }
    }

    /// The number of days a streak tier stands for; nil for a daily goal.
    var streakThreshold: Int? {
        switch self {
        case .streak3:  return 3
        case .streak7:  return 7
        case .streak14: return 14
        case .streak30: return 30
        case .calories, .protein, .steps, .water: return nil
        }
    }

    /// The message for a milestone reached at `dayStreak`. A streak tier that is sent late
    /// (paired on day five, or the send on day three failed) says the real number rather
    /// than the tier's.
    func message(name: String, dayStreak: Int) -> String {
        guard let threshold = streakThreshold, dayStreak > threshold else { return message(name: name) }
        return "🔥 \(name) is on a \(dayStreak)-day logging streak!"
    }
}

/// Today's stats + goals for one person, used to decide which milestones are met.
struct BuddyMilestoneInput {
    var caloriesEaten: Double = 0
    var calorieTarget: Double = 0
    var proteinEaten: Double = 0
    var proteinTarget: Double = 0
    var steps: Int = 0
    var stepGoal: Int = 0
    var waterOz: Double = 0
    var waterGoal: Double = 0
    var dayStreak: Int = 0
}

/// Detects when the buddy system crosses into a new calendar day, so "today" resets:
/// fresh snapshot republished, goal-celebrations re-armed (the per-day milestone guard
/// already keys by day, so this just triggers a prompt republish on the new day's first open).
enum BuddyDay {
    private static let key = "buddy.lastActiveDay"

    /// Returns true the FIRST time it's called on a calendar day that differs from the last
    /// recorded one (and records the new day). The very first call ever just initializes —
    /// there's no "previous day" to roll over from — so it returns false then.
    static func rolledOver(_ now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let last = (defaults.object(forKey: key) as? Date).map { cal.startOfDay(for: $0) }
        guard last != today else { return false }
        defaults.set(today, forKey: key)
        return last != nil
    }
}

enum BuddyMilestones {
    /// Reached the goal within a 3% grace band — mirrors the app's kind "Fueled!" framing
    /// so calorie/protein "hits" feel like reaching, not maxing-out.
    static let reachBand = 0.97

    /// Which milestones the stats currently MEET (ignoring whether already celebrated).
    /// Only the HIGHEST streak tier is returned, so passing day 7 doesn't also re-fire day 3.
    static func met(_ i: BuddyMilestoneInput) -> Set<BuddyMilestone> {
        var out: Set<BuddyMilestone> = []
        if i.calorieTarget > 0, i.caloriesEaten >= i.calorieTarget * reachBand { out.insert(.calories) }
        if i.proteinTarget > 0, i.proteinEaten >= i.proteinTarget * reachBand { out.insert(.protein) }
        if i.stepGoal > 0, i.steps >= i.stepGoal { out.insert(.steps) }
        if i.waterGoal > 0, i.waterOz >= i.waterGoal { out.insert(.water) }
        if i.dayStreak >= 30 { out.insert(.streak30) }
        else if i.dayStreak >= 14 { out.insert(.streak14) }
        else if i.dayStreak >= 7 { out.insert(.streak7) }
        else if i.dayStreak >= 3 { out.insert(.streak3) }
        return out
    }

    /// Met now, minus anything already celebrated. Pure — the UserDefaults wrapper is below.
    static func newlyReached(_ i: BuddyMilestoneInput,
                             alreadyCelebrated: Set<BuddyMilestone>) -> Set<BuddyMilestone> {
        met(i).subtracting(alreadyCelebrated)
    }

    // MARK: What has been sent (UserDefaults, per user)

    /// The key under which `m` is recorded as sent. A daily goal is keyed by the day; a
    /// streak tier by the day its streak started, so it is sent once per streak.
    private static func key(_ m: BuddyMilestone, input i: BuddyMilestoneInput, myUserID: String,
                            day: Date, calendar: Calendar) -> String {
        guard m.streakThreshold != nil else {
            return "buddy.milestone.\(myUserID).\(m.rawValue).\(dayKey(day, calendar: calendar))"
        }
        let today = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .day, value: -(max(i.dayStreak, 1) - 1), to: today) ?? today
        return "buddy.milestone.\(myUserID).\(m.rawValue).from.\(dayKey(start, calendar: calendar))"
    }

    private static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    /// Milestones the stats meet now that have not been sent. Reads only; nothing is
    /// recorded until `markSent`.
    static func pending(_ i: BuddyMilestoneInput,
                        myUserID: String,
                        day: Date,
                        calendar: Calendar = .current,
                        defaults: UserDefaults = .standard) -> Set<BuddyMilestone> {
        met(i).filter { !defaults.bool(forKey: key($0, input: i, myUserID: myUserID, day: day, calendar: calendar)) }
    }

    /// Record that `m`'s nudge was sent. Call after the send succeeded, not before.
    static func markSent(_ m: BuddyMilestone,
                         input i: BuddyMilestoneInput,
                         myUserID: String,
                         day: Date,
                         calendar: Calendar = .current,
                         defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(m, input: i, myUserID: myUserID, day: day, calendar: calendar))
    }

    /// `pending` and `markSent` in one step, for a caller with no send that can fail.
    static func consumeNewlyReached(_ i: BuddyMilestoneInput,
                                    myUserID: String,
                                    day: Date = .now,
                                    calendar: Calendar = .current,
                                    defaults: UserDefaults = .standard) -> Set<BuddyMilestone> {
        let fresh = pending(i, myUserID: myUserID, day: day, calendar: calendar, defaults: defaults)
        for m in fresh { markSent(m, input: i, myUserID: myUserID, day: day, calendar: calendar, defaults: defaults) }
        return fresh
    }
}
