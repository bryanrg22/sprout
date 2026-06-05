import Foundation
import SwiftData

/// DEBUG-only demo data seeding, used to populate the app for screenshots/testing.
/// Triggered by launching with `--seed-demo`; never runs in normal use.
enum DemoSeed {
    static var isRequested: Bool { CommandLine.arguments.contains("--seed-demo") }

    /// DEBUG: push today's food past the calorie goal so the celebratory "Fueled!"
    /// state can be screenshotted. Never used in normal seeding.
    static var isFueledRequested: Bool { CommandLine.arguments.contains("--demo-fueled") }

    /// DEBUG: seed a lean-GAIN profile (Bryan's version) instead of the default
    /// loss profile, so the gain framing/copy can be screenshotted. Never used in
    /// normal seeding.
    static var isGainRequested: Bool { CommandLine.arguments.contains("--demo-gain") }

    /// Which tab to open on launch, from `--demo-tab <name>`.
    static var initialTab: Int {
        guard let i = CommandLine.arguments.firstIndex(of: "--demo-tab"),
              i + 1 < CommandLine.arguments.count else { return 0 }
        // Tab order: Today(0) · Nutrients(1) · Progress(2) · Workouts(3) · Vita(4).
        // (Buddy is a Dashboard quick-link, not a tab — 5-tab max keeps Vita on the bar.)
        switch CommandLine.arguments[i + 1] {
        case "food": return 1
        case "progress": return 2
        case "workouts": return 3
        case "coach": return 4
        default: return 0
        }
    }

    static func seedIfNeeded(_ context: ModelContext, hasProfile: Bool) {
        guard isRequested, !hasProfile else { return }
        seed(context)
    }

    static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Profile
        let gaining = isGainRequested
        let p = UserProfile()
        p.name = gaining ? "Bryan" : "Victoria"
        p.sex = gaining ? .male : .female
        p.birthDate = calendar.date(byAdding: .year, value: -24, to: today) ?? today
        p.heightCm = gaining ? 178 : 165
        p.startWeightLbs = 158
        p.goalWeightLbs = gaining ? 172 : 140      // gain → goal ABOVE start
        p.activityLevel = .light
        p.pace = gaining ? .leanGain : .relaxed
        p.themeStyle = gaining ? .cool : .cute     // Bryan = cool/dark, Victoria = cute/pastel
        p.companionAvatar = gaining ? .bryan : .victoria
        p.homeGym = gaining ? .twentyFourHour : .usc   // Bryan trains at 24 Hour, one demo per home gym
        p.dailyStepGoal = 8000
        p.onboardingComplete = true
        WhatsNew.markSeen()   // seeded demo user is "caught up" — show What's New only via --whats-new
        context.insert(p)

        // Steps — last 7 days, as if mirrored from Apple Health.
        let stepCounts = [9243, 11020, 6500, 8800, 12300, 7400, 10100]
        for (i, s) in stepCounts.enumerated() {
            let day = calendar.date(byAdding: .day, value: -i, to: today) ?? today
            context.insert(StepsEntry(date: day, count: s))
        }

        // 28 days of weigh-ins: gentle downward trend + realistic daily noise.
        for i in 0..<28 {
            let day = calendar.date(byAdding: .day, value: -i, to: today) ?? today
            // Loss demo: older days heavier (trend drifts down). Gain demo: older
            // days lighter (trend drifts UP) so the gain framing has real momentum.
            let base = gaining ? (156.0 - Double(i) * 0.16) : (152.6 + Double(i) * 0.19)
            let noise = Double.random(in: -1.2...1.3)
            context.insert(WeightEntry(date: day, weightLbs: ((base + noise) * 10).rounded() / 10))
        }

        // Today's food
        func food(_ meal: MealType, _ name: String, _ serving: String,
                  _ kcal: Double, _ pr: Double, _ cb: Double, _ ft: Double) {
            context.insert(FoodEntry(date: .now, mealType: meal, name: name,
                                     servingDescription: serving,
                                     calories: kcal, proteinG: pr, carbsG: cb, fatG: ft))
        }
        food(.breakfast, "Greek yogurt & berries", "1 bowl", 240, 18, 30, 5)
        food(.lunch, "Grilled chicken salad", "1 plate", 420, 38, 22, 18)
        food(.snack, "Apple", "1 medium", 95, 0, 25, 0)
        food(.dinner, "Salmon & rice", "1 plate", 600, 42, 55, 22)
        // DEBUG only: nudge today's total to ~98% of goal (1355 → 1715 vs a 1742
        // target) so the celebratory "Fueled!" / "goal reached" state renders.
        if isFueledRequested {
            food(.snack, "Trail mix", "1 handful", 360, 9, 30, 22)
        }

        // Water today
        for _ in 0..<3 { context.insert(WaterEntry(date: .now, amountOz: 12)) }

        // A workout yesterday
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) {
            context.insert(WorkoutEntry(date: yesterday, type: .strength, durationMinutes: 45))
        }

        // Coach conversation
        context.insert(ChatMessage(
            role: "assistant",
            content: "Hi Victoria! I'm Vita, your coach 💚 I'm here whenever you want to check in, ask a question, or just need a little encouragement.",
            createdAt: calendar.date(byAdding: .minute, value: -6, to: .now) ?? .now,
            isSystemSeed: true))
        context.insert(ChatMessage(
            role: "user",
            content: "How's my week going?",
            createdAt: calendar.date(byAdding: .minute, value: -4, to: .now) ?? .now))
        context.insert(ChatMessage(
            role: "assistant",
            content: "Really well! Your trend is down about a pound this week, and you've logged several days in a row. That consistency is exactly what makes it stick — keep being kind to yourself 💚",
            createdAt: calendar.date(byAdding: .minute, value: -3, to: .now) ?? .now))

        try? context.save()
    }
}
