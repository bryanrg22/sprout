import SwiftUI
import SwiftData

/// The flagship "Weekly Vita Reflection" card for the Today screen: once a week, Vita
/// writes a warm note that reasons over the last 7 days + the onboarding note.
///
/// Self-contained and self-gating:
/// - Owns its own `@Query`s for the week's data (the dashboard passes only the profile).
/// - Shows nothing at all unless a NEW weekly reflection is due (`WeeklyReflection.isDue`),
///   so it quietly appears once a week and then steps aside.
/// - While the (optional, cheap) AI note is being written, it shows a gentle shimmer
///   placeholder; on no API key / any failure / guardrail rejection it falls back to a
///   warm template inside `WeeklyReflection.make`, so it NEVER blocks on the network.
///
/// ED-safe by construction: it hands `WeeklyReflection` only qualitative facts + a couple
/// of safe day-counts — never a calorie/weight/macro number.
///
/// Integration (one line in DashboardView's VStack):
///     WeeklyReflectionCard(profile: profile).appearLift(didAppear, index: 2)
struct WeeklyReflectionCard: View {
    let profile: UserProfile

    @Query(sort: \FoodEntry.date) private var allFood: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]

    /// The finished note. `nil` while it's being written → shimmer placeholder.
    @State private var note: String?
    /// Whether a new reflection is due. Captured once on appear so marking it "shown"
    /// (which we do as soon as the note lands) doesn't make the card vanish mid-read.
    @State private var due = WeeklyReflection.isDue()

    var body: some View {
        if due {
            card
                .task { await load() }
        }
    }

    // MARK: - Load (once-a-week gated; template on no-key/any failure)

    private func load() async {
        guard note == nil else { return }                 // build it once per appearance
        let inputs = Self.buildInputs(profile: profile,
                                      food: allFood, weights: weights, water: water,
                                      steps: steps, workouts: workouts)
        let text = await WeeklyReflection.make(inputs)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.4)) { note = text }
            // Mark shown only now that we actually have a note on screen, so a crash
            // mid-fetch doesn't burn the week. Next week `isDue` flips true again.
            WeeklyReflection.markShown()
        }
    }

    /// Render the note's inline markdown — Vita sometimes emphasizes a word with *asterisks*
    /// — as real italics/bold while preserving the paragraph's whitespace. Plain-text fallback.
    private static func styled(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            header
            if let note {
                Text(Self.styled(note))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(Theme.brand.opacity(0.6))
                .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.map { "Your week with \(profile.coachName). \($0)" }
                            ?? "\(profile.coachName) is writing your weekly reflection.")
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            VitaHeartAvatar(size: 34).breathing()
            VStack(alignment: .leading, spacing: 1) {
                Text("Your week with \(profile.coachName) ✨")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Weekly reflection")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: 0)
        }
    }

    /// Gentle "writing…" placeholder: three shimmering lines + a soft caption, so the card
    /// reads as "Vita is composing this for you" rather than a dead/empty box.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 9) {
            ShimmerLine().frame(height: 12)
            ShimmerLine().frame(height: 12)
            ShimmerLine().frame(width: 180, height: 12)
            Text("\(profile.coachName) is reflecting on your week…")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    // MARK: - Inputs builder (mirrors DashboardView's per-day derivations)

    /// Turn the week's SwiftData entries into the qualitative `WeeklyReflection.Inputs`.
    /// Counts whole DAYS over the last 7 (incl. today) — never amounts — and reads the
    /// smoothed-trend *shape* from `TrendCalculator`. No calorie/weight number leaves here.
    static func buildInputs(profile: UserProfile,
                            food: [FoodEntry], weights: [WeightEntry], water: [WaterEntry],
                            steps: [StepsEntry], workouts: [WorkoutEntry],
                            now: Date = .now,
                            calendar: Calendar = .current) -> WeeklyReflection.Inputs {
        // The 7 day-starts we score over (today and the previous six).
        let today = calendar.startOfDay(for: now)
        let days: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }

        // Targets are weight-based; use the smoothed trend (fallback to start weight),
        // exactly like the dashboard's `basisWeight`.
        let basisWeight = TrendCalculator.currentTrend(weights)
            ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
        let calorieTarget = profile.dailyCalorieTarget(weightLbs: basisWeight)
        let proteinTarget = profile.macroTargets(weightLbs: basisWeight).proteinG
        let waterGoal = profile.waterTargetOz
        let stepGoal = profile.dailyStepGoal

        func sameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }
        func dayCalories(_ d: Date) -> Double { food.filter { sameDay($0.date, d) }.reduce(0) { $0 + $1.calories } }
        func dayProtein(_ d: Date) -> Double  { food.filter { sameDay($0.date, d) }.reduce(0) { $0 + $1.proteinG } }
        func dayWater(_ d: Date) -> Double    { water.filter { sameDay($0.date, d) }.reduce(0) { $0 + $1.amountOz } }
        func daySteps(_ d: Date) -> Int       { steps.filter { sameDay($0.date, d) }.reduce(0) { $0 + $1.count } }
        func dayLogged(_ d: Date) -> Bool {
            !food.filter { sameDay($0.date, d) }.isEmpty
            || dayWater(d) > 0
            || daySteps(d) > 0
            || weights.contains { sameDay($0.date, d) }
            || workouts.contains { sameDay($0.date, d) }
        }

        let daysLogged = days.filter(dayLogged).count
        // "Ate enough" = within the same gentle sufficiency band the dashboard celebrates
        // (>=85% of fuel, but a day with zero food doesn't count as "ate enough").
        let ateEnoughDays = calorieTarget > 0
            ? days.filter { dayCalories($0) >= calorieTarget * 0.85 && dayCalories($0) > 0 }.count
            : 0
        let proteinGoalDays = proteinTarget > 0
            ? days.filter { dayProtein($0) >= proteinTarget }.count : 0
        let waterGoalDays = waterGoal > 0
            ? days.filter { dayWater($0) >= waterGoal }.count : 0
        let stepGoalDays = stepGoal > 0
            ? days.filter { daySteps($0) >= stepGoal }.count : 0
        let workoutDays = days.filter { d in workouts.contains { sameDay($0.date, d) } }.count

        return WeeklyReflection.Inputs(
            name: profile.name,
            direction: profile.pace.direction,
            note: profile.onboardingNote,
            daysLogged: daysLogged,
            ateEnoughDays: ateEnoughDays,
            proteinGoalDays: proteinGoalDays,
            waterGoalDays: waterGoalDays,
            stepGoalDays: stepGoalDays,
            workoutDays: workoutDays,
            trend: trendShape(weights: weights, basisWeight: basisWeight, direction: profile.pace.direction)
        )
    }

    /// Read the smoothed-trend *shape* over the week. `.droppingFast` is the safety-critical
    /// case (→ the note pivots to "fuel enough"), keyed off `TrendCalculator.assess`'s
    /// bodyweight-scaled `.fast` tier — but only when she's actually losing.
    private static func trendShape(weights: [WeightEntry],
                                   basisWeight: Double,
                                   direction: GoalPace.Direction) -> WeeklyReflection.Inputs.TrendShape {
        // Need at least a couple of weigh-ins in the last ~2 weeks to read a trend at all.
        let recent = weights.filter { $0.date >= Date.now.addingTimeInterval(-14 * 86_400) }
        guard recent.count >= 2 else { return .notEnoughData }

        let rate = TrendCalculator.ratePerWeek(weights)          // lbs/week, negative = losing
        switch TrendCalculator.assess(ratePerWeek: rate, currentWeightLbs: basisWeight) {
        case .fast:          return .droppingFast                // too-quick loss → fuel up
        case .ideal, .slow:  return .easingDown                  // gentle, sustainable loss
        case .gainingOrFlat:
            // Flat vs. genuinely climbing. A small wobble reads as "steady"; a clear rise
            // (and especially a desired lean gain) reads as "climbing".
            if rate > 0.15 { return .climbing }
            return .steady
        }
    }
}

// MARK: - Vita heart avatar

/// Vita's little heart-in-a-glow avatar — same brand-gradient circle as the chat coach
/// avatar, with a heart instead of sparkles to give the weekly note its caring, personal
/// feel. Decorative only.
private struct VitaHeartAvatar: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(Theme.background)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.brandGradient))
            .shadow(color: Theme.brand.opacity(0.35), radius: 5, x: 0, y: 2)
            .accessibilityHidden(true)
    }
}

// MARK: - Shimmer placeholder line

/// A single rounded "skeleton" line with a soft sheen sweeping across it — the universal
/// "content is loading" cue. Respects Reduce Motion (falls back to a static muted bar).
private struct ShimmerLine: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let base = Theme.textSecondary.opacity(0.18)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(base)
                .overlay {
                    if !reduceMotion {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Theme.textSecondary.opacity(0.28), .clear],
                                    startPoint: .leading, endPoint: .trailing)
                            )
                            .offset(x: phase * geo.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
        }
    }
}
