import SwiftUI
import SwiftData

/// Everything that goes into MY published buddy snapshot, composed from the same local @Query data
/// the dashboard reads. Bundled into one value so the **two** places that publish — the Buddy hub
/// (`BuddyHomeView.publishMyState`) and the always-on `BuddyAutoPublisher` below — build it
/// IDENTICALLY from a single source of truth.
struct MyBuddyState {
    var loggedToday: Bool
    var dayStreak: Int
    var stepsToday: Int
    var stepGoal: Int
    var waterToday: Double
    var waterGoal: Double
    var workedOutToday: Bool
    var workoutSummary: String
    var sharesFullData: Bool
    var trendWeightLbs: Double
    var goalWeightLbs: Double
    var weeklyRateLbs: Double
    var caloriesEaten: Double
    var calorieTarget: Double
    var proteinEaten: Double
    var proteinTarget: Double
    var carbsEaten: Double
    var carbTarget: Double
    var fatEaten: Double
    var fatTarget: Double
    var todayFoods: String
    var displayName: String
    /// The weekly competition record, encoded (see `CompetitionRecord`).
    var competitionWeeks: String = ""
}

/// Builds `MyBuddyState` from raw local data — the ONE place this computation lives, so the hub and
/// the background auto-publisher can never drift. Mirrors `DashboardView` / `SettingsView` reads so
/// the buddy sees exactly what I see.
enum BuddyStateComposer {

    static func compose(profile: UserProfile?,
                        foods: [FoodEntry],
                        water: [WaterEntry],
                        steps: [StepsEntry],
                        sessions: [WorkoutSession],
                        weights: [WeightEntry],
                        detected: [DetectedWorkout] = [],
                        now: Date = .now) -> MyBuddyState {
        let cal = Calendar.current
        let todayFood = foods.filter { cal.isDateInToday($0.date) }
        let waterOz   = water.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountOz }
        let stepsT    = steps.first { cal.isDateInToday($0.date) }?.count ?? 0
        let logged    = !todayFood.isEmpty || waterOz > 0 || stepsT > 0
        // Shared streak calc (food / water / manual weigh-ins only — never auto-steps).
        let streak    = StreakCalculator.loggingStreak(foods: foods, waters: water, weights: weights)
        let workedOut = sessions.contains { cal.isDateInToday($0.date) }

        // Basis weight for target math — smoothed trend, else start weight, else a safe 150
        // (mirrors UserProfile.currentWeightLbs / BuddyHomeView.publishMyState). Real (non-future)
        // weigh-ins only, so a clock-skewed entry can't skew the trend/rate the buddy sees.
        let realWeights = weights.filter { $0.date <= .now }
        let basis = TrendCalculator.currentTrend(realWeights)
            ?? ((profile?.startWeightLbs ?? 0) > 0 ? profile!.startWeightLbs : 150)
        let sharesFull = profile?.shareFullStatsWithBuddy ?? false
        let myName = (profile?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Your buddy"
        let macros = profile.map { $0.macroTargets(weightLbs: basis) }

        // Break the heavy reduces/maps into typed locals first — a single big initializer with all of
        // these inline blows the Swift type-checker's budget ("unable to type-check in reasonable time").
        let stepGoal: Int = max(profile?.dailyStepGoal ?? 0, 0)
        let waterGoal: Double = max(profile?.waterTargetOz ?? 0, 0)
        let calsEaten: Double = todayFood.reduce(0.0) { $0 + $1.totalCalories }
        let calTarget: Double = profile.map { $0.dailyCalorieTarget(weightLbs: basis) } ?? 0
        let protEaten: Double = todayFood.reduce(0.0) { $0 + $1.totalProteinG }
        let carbEaten: Double = todayFood.reduce(0.0) { $0 + $1.totalCarbsG }
        let fatsEaten: Double = todayFood.reduce(0.0) { $0 + $1.totalFatG }
        let foodNames: String = todayFood.map(\.name).filter { !$0.isEmpty }.prefix(8).joined(separator: ", ")
        let trend: Double = TrendCalculator.currentTrend(realWeights) ?? 0
        let rate: Double = TrendCalculator.ratePerWeek(realWeights)     // SIGNED (negative = losing)

        return MyBuddyState(
            loggedToday: logged,
            dayStreak: streak,
            stepsToday: stepsT,
            stepGoal: stepGoal,
            waterToday: waterOz,
            waterGoal: waterGoal,
            workedOutToday: workedOut,
            workoutSummary: workoutSummary(sessions),
            sharesFullData: sharesFull,
            trendWeightLbs: trend,
            goalWeightLbs: profile?.goalWeightLbs ?? 0,
            weeklyRateLbs: rate,
            caloriesEaten: calsEaten,
            calorieTarget: calTarget,
            proteinEaten: protEaten,
            proteinTarget: macros?.proteinG ?? 0,
            carbsEaten: carbEaten,
            carbTarget: macros?.carbsG ?? 0,
            fatEaten: fatsEaten,
            fatTarget: macros?.fatG ?? 0,
            todayFoods: foodNames,
            displayName: myName,
            competitionWeeks: CompetitionScoring.record(
                profile: profile, foods: foods, water: water, steps: steps, sessions: sessions,
                detected: detected, basisWeight: basis, now: now, calendar: cal).encoded
        )
    }

    /// A short, SAFE label of today's workout for the face-off — "Chest · Arms" for a gym session,
    /// "Run · 30 min" for cardio, "Chest · Arms +1" when there were several. Movement only: no
    /// weights, reps, or intensity that would invite comparison. Empty when nothing was logged.
    static func workoutSummary(_ sessions: [WorkoutSession]) -> String {
        let cal = Calendar.current
        let today = sessions.filter { cal.isDateInToday($0.date) }.sorted { $0.date > $1.date }
        guard let first = today.first else { return "" }
        func label(_ s: WorkoutSession) -> String {
            if s.kind.isGym {
                let f = s.focuses
                return f.isEmpty ? s.kind.label : f.map(\.label).joined(separator: " · ")
            }
            return s.durationMinutes > 0 ? "\(s.kind.label) · \(s.durationMinutes) min" : s.kind.label
        }
        let base = label(first)
        let extra = today.count - 1
        return extra > 0 ? "\(base) +\(extra)" : base
    }
}

/// An invisible, ALWAYS-MOUNTED view (lives at `RootView`, so it's alive on every tab) that keeps my
/// buddy snapshot fresh the moment I log — **not** only when I happen to open the Buddy tab.
///
/// Why this exists: publishing used to live entirely in `BuddyHomeView`, a `NavigationLink`
/// destination that only exists while the Buddy page is open. So logging a meal on the Today tab and
/// closing the app uploaded NOTHING — my buddy didn't see it until I next visited the Buddy tab. This
/// view fixes the WRITE side: it watches my data and re-publishes shortly after any log (debounced),
/// and immediately when the app goes to the background — so my buddy's push subscription actually
/// fires in the normal "log → put the phone down" flow.
struct BuddyAutoPublisher: View {
    @Query private var foods: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \DetectedWorkout.date) private var detected: [DetectedWorkout]

    @Environment(\.scenePhase) private var scenePhase
    // A publish-only view model — no push observer (that's the Buddy hub's job; a second observer
    // would just double-refresh a snapshot this view never displays). It shares the app's
    // publish coordinator with the hub's model, so the two never publish at once.
    @State private var model = BuddyViewModel(observePushes: false)

    private var profile: UserProfile? { UserProfile.primary(of: profiles) }

    /// Drives the debounced `.task(id:)` so rapid logs coalesce into one upload.
    private var dataSignature: String {
        Self.signature(sharesFullStats: profile?.shareFullStatsWithBuddy ?? false,
                       foods: foods, water: water, steps: steps,
                       sessionCount: sessions.count, weightCount: weights.count,
                       now: .now, calendar: .current)
    }

    /// A cheap value that changes whenever something publish-worthy changes: a food, water,
    /// step, workout or weigh-in, and the "Share my full stats" switch. The switch is in
    /// it so that turning sharing OFF publishes a snapshot without the full stats within
    /// seconds, instead of leaving the last full one in place until the next log.
    static func signature(sharesFullStats: Bool,
                          foods: [FoodEntry], water: [WaterEntry], steps: [StepsEntry],
                          sessionCount: Int, weightCount: Int,
                          now: Date, calendar cal: Calendar) -> String {
        let cals = foods.filter { cal.isDate($0.date, inSameDayAs: now) }.reduce(0) { $0 + $1.totalCalories }
        let w    = water.filter { cal.isDate($0.date, inSameDayAs: now) }.reduce(0) { $0 + $1.amountOz }
        let st   = steps.first { cal.isDate($0.date, inSameDayAs: now) }?.count ?? 0
        return "\(foods.count)|\(Int(cals))|\(Int(w))|\(st)|\(sessionCount)|\(weightCount)|\(sharesFullStats ? "full" : "activity")"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            // Debounce: when my data changes, wait for the logging to settle, then upload ONCE.
            // `.task(id:)` cancels + restarts on every change, so a flurry of logs → one publish.
            .task(id: dataSignature) {
                // Asked of the service each time, not remembered from launch: this model did
                // not do the pairing, the Buddy screen's did.
                guard model.refreshLinkState() else { return }
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                await publish()
            }
            // Leaving the app: upload my latest right now, so "log a meal → close the app" reaches
            // my buddy in seconds (their snapshot subscription wakes them), not "next time I open
            // the Buddy tab."
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    Task { await publish() }
                case .active:
                    // Self-heal: a publish that failed (bad network at the moment of logging,
                    // CloudKit hiccup, …) used to be LOST FOREVER — the buddy just saw an
                    // ever-staler snapshot. Retry on every return to the app while the last
                    // attempt failed, and refresh anyway when the last success is old enough
                    // that the buddy would be looking at yesterday's me.
                    if model.needsPublishOnForeground() {
                        Task { await publish() }
                    }
                default:
                    break
                }
            }
    }

    private func publish() async {
        let s = BuddyStateComposer.compose(profile: profile, foods: foods, water: water,
                                           steps: steps, sessions: sessions, weights: weights,
                                           detected: detected)
        // Publishes only while linked, then cheers the buddy for any goal just crossed.
        await model.publishIfLinked(s)
    }
}
