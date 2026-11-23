import Foundation

/// Detects the moment someone crosses a daily goal, so their buddy can be auto-cheered
/// ("🎉 Victoria just hit her calorie goal!"). Pure + deterministic; the actual ping
/// reuses the proven nudge push. Each milestone celebrates **at most once per day**
/// (guarded in UserDefaults) so a buddy is pinged on the *crossing*, not on every refresh.
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

    // MARK: Per-day, per-user persistence guard

    private static func key(_ m: BuddyMilestone, myUserID: String, dayKey: String) -> String {
        "buddy.milestone.\(myUserID).\(m.rawValue).\(dayKey)"
    }

    private static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    /// Returns milestones reached for the FIRST time today AND records them as celebrated,
    /// so each fires a single ping per day. Call once per publish.
    static func consumeNewlyReached(_ i: BuddyMilestoneInput,
                                    myUserID: String,
                                    day: Date = .now,
                                    calendar: Calendar = .current,
                                    defaults: UserDefaults = .standard) -> Set<BuddyMilestone> {
        let dk = dayKey(day, calendar: calendar)
        let already = Set(BuddyMilestone.allCases.filter {
            defaults.bool(forKey: key($0, myUserID: myUserID, dayKey: dk))
        })
        let fresh = newlyReached(i, alreadyCelebrated: already)
        for m in fresh { defaults.set(true, forKey: key(m, myUserID: myUserID, dayKey: dk)) }
        return fresh
    }
}
