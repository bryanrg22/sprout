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
        // A realistic clock time for each meal, so the "what time you ate" stamps vary.
        func mealHour(_ meal: MealType) -> (Int, Int) {
            switch meal {
            case .breakfast: return (8, 15)
            case .lunch:     return (12, 30)
            case .snack:     return (15, 30)
            case .dinner:    return (19, 0)
            }
        }
        func mealDate(_ meal: MealType, on day: Date) -> Date {
            let (h, m) = mealHour(meal)
            return calendar.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
        }
        func food(_ meal: MealType, _ name: String, _ serving: String,
                  _ kcal: Double, _ pr: Double, _ cb: Double, _ ft: Double) {
            context.insert(FoodEntry(date: mealDate(meal, on: .now), mealType: meal, name: name,
                                     servingDescription: serving,
                                     calories: kcal, proteinG: pr, carbsG: cb, fatG: ft))
        }
        food(.breakfast, "Greek yogurt & berries", "1 bowl", 240, 18, 30, 5)
        food(.lunch, "Grilled chicken salad", "1 plate", 420, 38, 22, 18)
        food(.snack, "Apple", "1 medium", 95, 0, 25, 0)
        food(.dinner, "Salmon & rice", "1 plate", 600, 42, 55, 22)

        // A couple of PAST days of food, so the Nutrients date-stepper has history to browse and
        // past-day macros are visible (the thing Victoria asked for).
        func pastFood(_ dayOffset: Int, _ meal: MealType, _ name: String, _ serving: String,
                      _ kcal: Double, _ pr: Double, _ cb: Double, _ ft: Double) {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
            context.insert(FoodEntry(date: mealDate(meal, on: day), mealType: meal, name: name,
                                     servingDescription: serving,
                                     calories: kcal, proteinG: pr, carbsG: cb, fatG: ft))
        }
        pastFood(-1, .breakfast, "Oatmeal & banana", "1 bowl", 310, 10, 54, 6)
        pastFood(-1, .lunch, "Turkey sandwich", "1 sandwich", 480, 32, 45, 18)
        pastFood(-1, .dinner, "Chicken stir-fry", "1 plate", 540, 40, 48, 20)
        pastFood(-2, .breakfast, "Eggs & toast", "2 eggs", 320, 20, 24, 16)
        pastFood(-2, .lunch, "Burrito bowl", "1 bowl", 620, 34, 70, 22)
        pastFood(-2, .dinner, "Pasta & veggies", "1 plate", 560, 22, 82, 16)
        // DEBUG only: nudge today's total to ~98% of goal (1355 → 1715 vs a 1742
        // target) so the celebratory "Fueled!" / "goal reached" state renders.
        if isFueledRequested {
            food(.snack, "Trail mix", "1 handful", 360, 9, 30, 22)
        }

        // Water today
        for _ in 0..<3 { context.insert(WaterEntry(date: .now, amountOz: 12)) }

        // A workout yesterday (legacy dashboard `WorkoutEntry`, feeds the activity row).
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) {
            context.insert(WorkoutEntry(date: yesterday, type: .strength, durationMinutes: 45))
        }

        // Recent gym/cardio sessions for the Workouts tab — grouped Today/Yesterday/…, with real
        // weights so the detail's volume hero and the weekly stats card have something to show.
        seedWorkouts(context, today: today, gaining: gaining)

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

    /// Seed a handful of recent `WorkoutSession`s (+ their `ExerciseEntry` rows) for the Workouts
    /// tab: a few gym days across the week plus one run, with weights scaled to the demo persona
    /// (Bryan lifts heavier than Victoria) so the volume hero + weekly stats read realistically.
    private static func seedWorkouts(_ context: ModelContext, today: Date, gaining: Bool) {
        let cal = Calendar.current
        func at(_ dayOffset: Int, hour: Int) -> Date {
            let d = cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
        }
        // Round a base weight to the nearest 5 lb after persona scaling.
        let scale = gaining ? 1.0 : 0.62
        func w(_ base: Double) -> Double { ((base * scale) / 5).rounded() * 5 }
        // Insert one exercise row, pulling the display name + icon from the catalog so it matches.
        func ex(_ session: WorkoutSession, _ key: String, _ weight: Double, reps: Int = 10, sets: Int = 3) {
            let m = MachineCatalog.machine(for: key)
            context.insert(ExerciseEntry(sessionID: session.id, date: session.date,
                                         machineKey: key,
                                         displayName: m?.name ?? key,
                                         iconName: m?.icon ?? "dumbbell.fill",
                                         weightLbs: weight, reps: reps, sets: sets))
        }

        // Today — Chest + Arms
        let chest = WorkoutSession(date: at(0, hour: 8), kind: .gym, focuses: [.chest, .arms], durationMinutes: 50)
        context.insert(chest)
        ex(chest, "chest_press", w(140))
        ex(chest, "incline_db_press", w(50))
        ex(chest, "cable_curl", w(40), reps: 12)
        ex(chest, "tricep_pushdown", w(50), reps: 12)

        // Yesterday — Legs
        let legs = WorkoutSession(date: at(-1, hour: 18), kind: .gym, focuses: [.legs], durationMinutes: 55)
        context.insert(legs)
        ex(legs, "leg_press", w(360), reps: 10, sets: 4)
        ex(legs, "leg_extension", w(120), reps: 12)
        ex(legs, "romanian_deadlift", w(155))
        ex(legs, "calf_raise", w(180), reps: 15, sets: 4)

        // 2 days ago — Back
        let back = WorkoutSession(date: at(-2, hour: 7), kind: .gym, focuses: [.back], durationMinutes: 48)
        context.insert(back)
        ex(back, "lat_pulldown", w(120))
        ex(back, "seated_cable_row", w(130))
        ex(back, "barbell_row", w(115))

        // 3 days ago — a run (cardio: the duration hero, no exercise rows)
        context.insert(WorkoutSession(date: at(-3, hour: 7), kind: .run, focuses: [], durationMinutes: 32))
    }
}
