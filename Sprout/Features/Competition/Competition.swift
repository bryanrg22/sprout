import Foundation

/// The weekly competition between two buddies (GOALS G12, EVAL_REPORT 29).
///
/// Each person is scored against their OWN targets, so someone losing and someone gaining
/// compete on equal terms (the owner: "not just eating correct, but being in their ranges").
/// A day earns one point for each target hit, up to five. A day with no food logged scores
/// nothing: logging is part of it. Most points in the week wins.
///
/// Only which targets were hit crosses to the other phone, never a number: no calories, no
/// weights, no food. The week runs Monday to Sunday on both phones whatever their calendar
/// settings, so the two always score the same seven days.
struct CompetitionHits: OptionSet, Equatable, Hashable {
    let rawValue: Int
    /// Calories inside the person's own range (the range Today shows).
    static let calories = CompetitionHits(rawValue: 1 << 0)
    /// Protein at or above the person's target.
    static let protein = CompetitionHits(rawValue: 1 << 1)
    /// Water at or above the person's goal.
    static let water = CompetitionHits(rawValue: 1 << 2)
    /// Steps at or above the person's goal.
    static let steps = CompetitionHits(rawValue: 1 << 3)
    /// A workout logged, or one Apple Health or the tracker detected.
    static let active = CompetitionHits(rawValue: 1 << 4)

    static let all: [CompetitionHits] = [.calories, .protein, .water, .steps, .active]
    static let maxPerDay = 5

    var points: Int { Self.all.filter { contains($0) }.count }

    var label: String {
        switch self {
        case .calories: return "Calories in range"
        case .protein: return "Protein"
        case .water: return "Water"
        case .steps: return "Steps"
        case .active: return "Active"
        default: return Self.all.filter { contains($0) }.map(\.label).joined(separator: ", ")
        }
    }
}

enum CompetitionWeek {
    /// Monday-first, in the phone's time zone: both phones agree on which days a week holds.
    static func calendar(_ base: Calendar = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = base.timeZone
        c.locale = base.locale
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    static func start(of date: Date, calendar base: Calendar = .current) -> Date {
        let c = calendar(base)
        return c.dateInterval(of: .weekOfYear, for: date)?.start ?? c.startOfDay(for: date)
    }
}

/// A person's results for the current week and the one before, as published to the buddy.
/// The wire form is one short string, `2026-11-16:31,7,0,31,15,0,3;2026-11-23:31,7`: each
/// week's Monday, then one number per day from Monday (the `CompetitionHits` bits). A week
/// in progress lists only the days so far.
struct CompetitionRecord: Equatable {
    /// Week start (`yyyy-MM-dd` of its Monday) → the hits of each day from Monday.
    var weeks: [String: [CompetitionHits]]

    static let empty = CompetitionRecord(weeks: [:])

    func days(forWeekStarting key: String) -> [CompetitionHits]? { weeks[key] }

    func points(forWeekStarting key: String) -> Int? {
        weeks[key].map { $0.reduce(0) { $0 + $1.points } }
    }

    var encoded: String {
        weeks.keys.sorted().map { key in
            key + ":" + (weeks[key] ?? []).map { String($0.rawValue) }.joined(separator: ",")
        }.joined(separator: ";")
    }

    /// Reads the wire form. Anything malformed (an unknown week format, a day value outside
    /// the five bits, more than seven days) drops that week rather than inventing points.
    static func decode(_ text: String) -> CompetitionRecord {
        var weeks: [String: [CompetitionHits]] = [:]
        for part in text.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2, isDayKey(String(pieces[0])) else { continue }
            let values = pieces[1].isEmpty ? [] : pieces[1].split(separator: ",").map { Int($0) }
            guard values.count <= 7, values.allSatisfy({ $0.map { (0..<32).contains($0) } ?? false }) else { continue }
            weeks[String(pieces[0])] = values.map { CompetitionHits(rawValue: $0!) }
        }
        return CompetitionRecord(weeks: weeks)
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func isDayKey(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        return parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

enum CompetitionScoring {

    /// One day's numbers, as the person's own app has them.
    struct DayTotals: Equatable {
        var loggedFood: Bool
        var calories: Double
        var protein: Double
        var waterOz: Double
        var steps: Int
        var active: Bool
    }

    /// The person's targets for a day, from the same functions Today uses.
    struct Targets: Equatable {
        /// The calorie range's floor and ceiling; the ceiling is infinite for a gain goal.
        var calorieLow: Double
        var calorieHigh: Double
        var protein: Double
        var waterOz: Double
        var steps: Int
    }

    /// A small grace under the calorie floor, the same as `UserProfile.calorieStatus`, so a
    /// day a few calories short of the floor still counts as in range.
    static let calorieFloorGrace = 0.97

    static func targets(profile: UserProfile, basisWeight: Double, steps: Int) -> Targets {
        let range = profile.calorieGoalRange(weightLbs: basisWeight)
        // The step bonus moves the whole range, as on Today and the widget.
        let bonus = profile.stepBonusCalories(weightLbs: basisWeight, steps: steps)
        return Targets(calorieLow: range.low + bonus,
                       calorieHigh: range.high.isFinite ? range.high + bonus : .infinity,
                       protein: profile.macroTargets(weightLbs: basisWeight).proteinG,
                       waterOz: profile.waterTargetOz,
                       steps: profile.dailyStepGoal)
    }

    static func hits(_ day: DayTotals, _ t: Targets) -> CompetitionHits {
        guard day.loggedFood else { return [] }
        var hits: CompetitionHits = []
        if t.calorieLow > 0, day.calories >= t.calorieLow * calorieFloorGrace, day.calories <= t.calorieHigh {
            hits.insert(.calories)
        }
        if t.protein > 0, day.protein >= t.protein { hits.insert(.protein) }
        if t.waterOz > 0, day.waterOz >= t.waterOz { hits.insert(.water) }
        if t.steps > 0, day.steps >= t.steps { hits.insert(.steps) }
        if day.active { hits.insert(.active) }
        return hits
    }

    /// This week (so far) and last week, from the person's own data. Targets are today's:
    /// the app does not keep past targets, so a changed goal rescores the two weeks.
    static func record(profile: UserProfile?, foods: [FoodEntry], water: [WaterEntry], steps: [StepsEntry],
                       sessions: [WorkoutSession], detected: [DetectedWorkout], basisWeight: Double,
                       now: Date = .now, calendar base: Calendar = .current) -> CompetitionRecord {
        guard let profile else { return .empty }
        let cal = CompetitionWeek.calendar(base)
        let today = cal.startOfDay(for: now)
        let thisWeek = CompetitionWeek.start(of: now, calendar: base)
        guard let lastWeek = cal.date(byAdding: .day, value: -7, to: thisWeek) else { return .empty }
        var weeks: [String: [CompetitionHits]] = [:]
        for start in [lastWeek, thisWeek] {
            var days: [CompetitionHits] = []
            for offset in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: offset, to: start), day <= today else { break }
                let same: (Date) -> Bool = { cal.isDate($0, inSameDayAs: day) }
                let food = foods.filter { same($0.date) }
                let stepCount = steps.filter { same($0.date) }.map(\.count).max() ?? 0
                let totals = DayTotals(
                    loggedFood: !food.isEmpty,
                    calories: food.reduce(0) { $0 + $1.totalCalories },
                    protein: food.reduce(0) { $0 + $1.totalProteinG },
                    waterOz: water.filter { same($0.date) }.reduce(0) { $0 + $1.amountOz },
                    steps: stepCount,
                    active: sessions.contains { same($0.date) } || detected.contains { same($0.date) })
                days.append(hits(totals, targets(profile: profile, basisWeight: basisWeight, steps: stepCount)))
            }
            weeks[CompetitionRecord.dayKey(start, calendar: cal)] = days
        }
        return CompetitionRecord(weeks: weeks)
    }

    /// Who is ahead in a week: positive when I am, negative when my buddy is, zero for a tie.
    static func margin(mine: CompetitionRecord, theirs: CompetitionRecord, weekKey: String) -> Int? {
        guard let m = mine.points(forWeekStarting: weekKey), let t = theirs.points(forWeekStarting: weekKey) else {
            return nil
        }
        return m - t
    }
}
