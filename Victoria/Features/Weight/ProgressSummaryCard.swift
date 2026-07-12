import SwiftUI
import SwiftData

/// "Your progress" — an AI-written recap on the Progress tab that reads ALL the metrics
/// (weight trend, nutrition, activity, consistency) from real logged data and tells the
/// honest story. Numbers are computed here in code; the model only phrases them.
///
/// Mirrors `SmartSuggestionsView`: gated on an API key, cached by day (one call/day unless
/// refreshed), and degrades gracefully to no-key / not-enough-data / error states.
struct ProgressSummaryCard: View {
    let profile: UserProfile

    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \WaterEntry.date) private var water: [WaterEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    // `WorkoutSession` is what the Workouts tab writes; the legacy `WorkoutEntry` is debug-only, so
    // reading it counted zero real workouts for real users (only `.date` is used here).
    @Query(sort: \WorkoutSession.date) private var workouts: [WorkoutSession]

    @State private var phase: Phase = .idle
    @State private var reloadTick = 0

    private enum Phase: Equatable {
        case idle, loading, loaded(ProgressSummary), empty, error
    }

    var body: some View {
        if !AIConfig.hasActiveKey {
            // No key → quietly hide (the weight chart still stands on its own). The note to
            // add a key lives on the Food tab + Settings; we don't nag here too.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.spacingM) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Theme.spacingL)
            // Re-run when the user refreshes (reloadTick) OR when the targets change — so adjusting
            // the plan refreshes this recap right away instead of leaving yesterday's-numbers story.
            .task(id: "\(reloadTick)|\(targetSignature)") { await load() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.spacingS) {
            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
            }
            Text("Your progress")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Button {
                clearCache()
                reloadTick += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(phase == .loading ? Theme.textSecondary : Theme.brand)
                    .frame(width: 32, height: 32)
                    .background(Theme.brandSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(phase == .loading)
            .accessibilityLabel("Refresh progress recap")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            HStack(spacing: Theme.spacingS) {
                ProgressView()
                Text("Reading your trends…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, Theme.spacingS)

        case .loaded(let summary):
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                Text(summary.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !summary.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(summary.highlights.enumerated()), id: \.offset) { _, h in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(Theme.brand).frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(h)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }

        case .empty:
            Text("Log a few weigh-ins and meals and I'll start reading your trends here 💚")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .error:
            HStack(spacing: Theme.spacingS) {
                Text("Couldn't write your recap just now.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Retry") { reloadTick += 1 }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
            }
        }
    }

    // MARK: - Load (cache → network)

    private func load() async {
        // Serve today's cached recap if present (one call/day unless refreshed).
        if let cached = cachedSummary() {
            phase = .loaded(cached)
            return
        }
        guard let snapshot = buildSnapshot() else { phase = .empty; return }
        phase = .loading
        do {
            let summary = try await ProgressSummaryService.summary(snapshot: snapshot)
            cache(summary)
            phase = .loaded(summary)
        } catch {
            phase = .error
        }
    }

    // MARK: - Snapshot (the FACTS — computed in code)

    private var basisWeight: Double {
        TrendCalculator.currentTrend(weights) ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
    }
    private var unit: String { profile.unitSystem.weightUnit }

    /// Builds a factual, line-by-line snapshot for the model. Returns nil when there's not
    /// enough logged data to say anything meaningful.
    private func buildSnapshot() -> String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var lines: [String] = []

        // Weight
        if let trend = TrendCalculator.currentTrend(weights) {
            lines.append("Weight trend: \(fmt1(trend)) \(unit)")
            lines.append("Weekly rate: \(fmt1(TrendCalculator.ratePerWeek(weights))) \(unit)/wk (negative = losing)")
            lines.append("Goal weight: \(fmt1(profile.goalWeightLbs)) \(unit) (goal direction: \(profile.pace.direction))")
            if let remaining = directionRemaining(trend) {
                lines.append("Still to go: \(fmt1(remaining)) \(unit)")
            }
            if let eta = TrendCalculator.projectedGoalDate(weights, goalLbs: profile.goalWeightLbs) {
                lines.append("Projected goal date: \(eta.formatted(.dateTime.month(.abbreviated).day().year()))")
            }
            lines.append("Total weigh-ins: \(weights.count)")
        } else {
            lines.append("Weight: not enough weigh-ins for a trend yet")
        }

        // Nutrition (last 7 calendar days that have food)
        let calTarget = profile.dailyCalorieTarget(weightLbs: basisWeight)
        let proteinTarget = profile.macroTargets(weightLbs: basisWeight).proteinG
        let last7 = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        var dayCalories: [Double] = []
        var proteinHitDays = 0
        for day in last7 {
            let dayFoods = foods.filter { cal.isDate($0.date, inSameDayAs: day) }
            guard !dayFoods.isEmpty else { continue }
            dayCalories.append(dayFoods.reduce(0) { $0 + $1.totalCalories })
            let protein = dayFoods.reduce(0) { $0 + $1.totalProteinG }
            if proteinTarget > 0, protein >= proteinTarget * 0.97 { proteinHitDays += 1 }
        }
        if !dayCalories.isEmpty {
            let avg = dayCalories.reduce(0, +) / Double(dayCalories.count)
            lines.append("Avg calories over \(dayCalories.count) logged day(s) this week: \(Int(avg.rounded())) (fuel target \(Int(calTarget.rounded())))")
            lines.append("Protein goal reached on \(proteinHitDays) of \(dayCalories.count) logged day(s) (target \(Int(proteinTarget.rounded()))g)")
        } else {
            lines.append("Nutrition: nothing logged in the last 7 days")
        }

        // Activity (last 7 days)
        let weekSteps = last7.compactMap { day in steps.first { cal.isDate($0.date, inSameDayAs: day) }?.count }
        if !weekSteps.isEmpty {
            lines.append("Avg steps over \(weekSteps.count) day(s): \(weekSteps.reduce(0, +) / weekSteps.count) (goal \(profile.dailyStepGoal))")
        }
        let workoutDays = last7.filter { day in workouts.contains { cal.isDate($0.date, inSameDayAs: day) } }.count
        if workoutDays > 0 { lines.append("Workouts this week: \(workoutDays)") }

        // Consistency — the SAME calc the Today streak chip uses (active logging only: food /
        // water / manual weigh-in, clamped to the account start), so the recap can never disagree
        // with the flame. Steps are auto-imported (~30 days backfilled), so counting them here was
        // the "34-day streak" bug.
        let streak = StreakCalculator.loggingStreak(foods: foods, waters: water,
                                                    weights: weights, since: profile.createdAt)
        lines.append("Current logging streak: \(streak) day(s)")

        // Who she is — her editable About You profile, so the recap speaks to her real life, not just
        // numbers (the same canonical bio chat + the plan read). Keeps every AI surface consistent.
        let bio = profile.onboardingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bio.isEmpty { lines.append("About her, in her own profile: \(bio)") }

        // Need at least a weigh-in or some food to say anything real.
        guard !weights.isEmpty || !dayCalories.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// Pounds left to the goal in the goal's direction (nil for maintain / no trend).
    private func directionRemaining(_ trend: Double) -> Double? {
        switch profile.pace.direction {
        case .lose: return max(0, trend - profile.goalWeightLbs)
        case .gain: return max(0, profile.goalWeightLbs - trend)
        case .maintain: return nil
        }
    }

    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: - Daily cache

    /// The targets that drive the recap — calorie/protein/water overrides + step goal. Folded into
    /// the cache key so that the moment the plan (or Vita) changes a goal, the previously-cached recap
    /// is bypassed and a fresh one is written against the new numbers — no stale "your progress" story.
    private var targetSignature: String {
        "\(Int(profile.calorieTargetOverride))-\(Int(profile.proteinTargetOverride))-"
        + "\(Int(profile.waterGoalOzOverride))-\(profile.dailyStepGoal)"
    }
    private var cacheKey: String {
        "progress.summary." + Date.now.formatted(.iso8601.year().month().day()) + "." + targetSignature
    }
    private func cachedSummary() -> ProgressSummary? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(ProgressSummary.self, from: data)
    }
    private func cache(_ summary: ProgressSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    private func clearCache() { UserDefaults.standard.removeObject(forKey: cacheKey) }
}
