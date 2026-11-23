import SwiftUI
import SwiftData

/// The once-a-day "note from Vita" on Today — Sprout's take on the Google Health Coach
/// morning card: a timestamped observation with a headline, one insight, and a tap-through
/// into Vita chat. Content comes from `DailyBriefService` (deterministic topic ladder +
/// optional one-cheap-call phrasing, cached for the day).
///
/// Self-hides while the WelcomeBackCard owns the moment (7+ day gap) so the top of Today
/// never stacks two greetings.
struct DailyBriefCard: View {
    let profile: UserProfile

    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    @Query(sort: \SleepEntry.date) private var sleep: [SleepEntry]
    @Query(sort: \VitalsEntry.date) private var vitals: [VitalsEntry]
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

    @State private var brief: DailyBriefService.Brief?

    var body: some View {
        // ZStack (not Group): a Group whose `if` is false contributes NO view, so a `.task`
        // hung on it never fires and the brief never loads. The ZStack always exists
        // (zero-sized while empty), so the task reliably runs on appear.
        ZStack {
            if let brief, !hiddenForWelcomeBack {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Theme.brand)
                        Text(timestamp)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    Text(brief.headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(brief.body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardElevated()
                .askVita {
                    AskVitaTopic(
                        name: "Today's note",
                        icon: "sparkles",
                        value: brief.headline,
                        question: "You mentioned this in today's note: \"\(brief.headline)\" — tell me more about what you saw and what I could do with it today.")
                }
            }
        }
        .task(id: DailyBriefService.dayKey()) {
            brief = await DailyBriefService.todaysBrief(signals: signals)
        }
    }

    /// Steps aside whenever a bigger Vita moment owns the top of Today: the 7+-day
    /// welcome card, or the once-a-week reflection on the day it appears (two stacked
    /// Vita notes was exactly the clutter the old InsightCard was removed for).
    private var hiddenForWelcomeBack: Bool {
        if WeeklyReflection.isDue() { return true }
        return (StreakCalculator.daysSinceLastLog(foods: foods, waters: water, weights: weights)
            ?? 0) >= WelcomeBackCard.minGapDays
    }

    private var timestamp: String {
        Date.now.formatted(date: .omitted, time: .shortened)
    }

    /// The one signal that depends on a setting: a trend easing down at a sustainable pace is
    /// a result to celebrate only on a loss goal.
    static func trendEasedDown(direction: GoalPace.Direction, ratePerWeek rate: Double) -> Bool {
        direction == .lose && rate < -0.2 && rate > -2.5
    }

    // MARK: - Signals from local data (the only facts the brief may use)

    private var signals: DailyBriefService.Signals {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today

        var s = DailyBriefService.Signals()
        s.name = profile.name
        s.daysAway = StreakCalculator.daysSinceLastLog(foods: foods, waters: water, weights: weights)
        s.streak = StreakCalculator.loggingStreak(foods: foods, waters: water, weights: weights)
        if let shift = TravelSignal.current() {
            s.travelShiftHours = shift.hours
            s.travelShiftDaysAgo = TravelSignal.daysAgo(shift)
        }

        if let night = sleep.first(where: { cal.isDate($0.date, inSameDayAs: today) }),
           night.asleepMinutes > 0 {
            s.sleepMinutes = night.asleepMinutes
            if night.deepMinutes > 0 { s.deepMinutes = night.deepMinutes }
        }
        let week = sleep.filter { $0.asleepMinutes > 0 && $0.date > cal.date(byAdding: .day, value: -7, to: today)! }
        if week.count >= 3 {
            s.sleepAvgMinutes = week.reduce(0) { $0 + $1.asleepMinutes } / week.count
        }

        if let v = vitals.last(where: { $0.restingHeartRate > 0 && $0.date >= cal.date(byAdding: .day, value: -2, to: today)! }) {
            s.restingHR = v.restingHeartRate
        }
        let rhrs = vitals.filter { $0.restingHeartRate > 0 && $0.date > cal.date(byAdding: .day, value: -7, to: today)! }
            .map(\.restingHeartRate)
        if rhrs.count >= 3 { s.restingHRAvg = rhrs.reduce(0, +) / Double(rhrs.count) }

        if let y = steps.first(where: { cal.isDate($0.date, inSameDayAs: yesterday) })?.count {
            s.stepsYesterday = y
        }
        let stepWeek = steps.filter { $0.count > 0 && $0.date > cal.date(byAdding: .day, value: -8, to: today)! && $0.date < today }
        if stepWeek.count >= 3 { s.stepsAvg = stepWeek.reduce(0) { $0 + $1.count } / stepWeek.count }

        s.workedOutYesterday = sessions.contains { cal.isDate($0.date, inSameDayAs: yesterday) }

        // Celebrate-only trend signal: eased down at a sustainable pace.
        let realWeights = weights.filter { $0.date <= .now }
        let rate = TrendCalculator.ratePerWeek(realWeights)
        s.trendEasedDown = Self.trendEasedDown(direction: profile.pace.direction, ratePerWeek: rate)

        return s
    }
}
