import SwiftUI
import SwiftData

/// The proactive "want to level up?" card for the Today screen — the approval layer
/// on top of `RecommendationEngine`.
///
/// It runs the free, on-device engine over a few weeks of step + water history and,
/// only when she's *consistently exceeded* a goal, PROPOSES nudging that goal up a
/// notch. Nothing changes until she taps **Apply**; **Not now** snoozes that specific
/// proposal so it's never naggy. It never proposes lowering anything and never
/// touches calories/weight — the engine enforces that; this view just presents it.
///
/// Self-contained: drop `RecommendationCard(profile:)` on the dashboard and it
/// queries its own data, renders, and persists snoozes. When there's nothing worth
/// proposing (the common case), it renders nothing at all.
struct RecommendationCard: View {
    @Bindable var profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \StepsEntry.date, order: .reverse) private var steps: [StepsEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var water: [WaterEntry]

    /// Fires the confetti burst on a successful apply.
    @State private var celebrate = 0
    /// Bumps `.sensoryFeedback` for the happy tap on apply.
    @State private var applauseTick = 0
    /// Once applied, swap the card for a brief "done" state before it disappears.
    @State private var applied = false
    /// Re-read snoozes after a "Not now" so the card recomputes and hides.
    @State private var snoozeTick = 0

    // MARK: Snooze persistence (UserDefaults — like InsightCard's phrase gate)

    /// How long a declined proposal stays quiet. Long, because re-asking about the
    /// same setting too soon is exactly the "naggy" feeling we're avoiding.
    private static let snoozeDays: Double = 14
    private func snoozeKey(_ id: String) -> String { "vita.rec.snoozed.\(id)" }

    /// Ids snoozed within the window — filtered out of the engine's pick.
    private var snoozedIDs: Set<String> {
        _ = snoozeTick                              // dependency so dismiss re-evaluates
        let now = Date.now.timeIntervalSince1970
        let window = Self.snoozeDays * 86_400
        // Each key stores the timestamp it was snoozed at; still-fresh ones count.
        let ids = ["raise_step_goal", "raise_water_goal"]
        return Set(ids.filter { id in
            let ts = UserDefaults.standard.double(forKey: snoozeKey(id))
            return ts > 0 && (now - ts) < window
        })
    }

    private func snooze(_ id: String) {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: snoozeKey(id))
        snoozeTick += 1
    }

    // MARK: Snapshot assembly (mirrors how DashboardView derives daily totals)

    private var input: RecommendationEngine.Input {
        let cal = Calendar.current

        // Per-day step totals, most-recent-first. One StepsEntry per day already, but
        // group defensively in case of duplicates.
        let stepsByDay = dailyTotals(steps, value: { Double($0.count) }, date: \.date)
        let waterByDay = dailyTotals(water, value: \.amountOz, date: \.date)

        let stepGoal = max(profile.dailyStepGoal, 0)
        let waterGoal = profile.waterTargetOz

        // Consecutive days (from today backwards) clearing each goal.
        let stepStreak = metStreak(stepsByDay, goal: Double(stepGoal), calendar: cal)
        let waterStreak = metStreak(waterByDay, goal: waterGoal, calendar: cal)

        // "Typical" = median over the met-streak window (robust to one big day),
        // falling back to the recent two weeks when the streak is short.
        let stepWindow = window(stepsByDay, lastNDays: max(stepStreak, 14), calendar: cal)
        let waterWindow = window(waterByDay, lastNDays: max(waterStreak, 14), calendar: cal)

        let stepDays = Set(stepsByDay.map { cal.startOfDay(for: $0.day) })
        let waterDays = Set(waterByDay.map { cal.startOfDay(for: $0.day) })
        let historyDays = stepDays.union(waterDays).count

        return RecommendationEngine.Input(
            stepGoal: stepGoal,
            stepGoalMetStreakDays: stepStreak,
            typicalDailySteps: Int(median(stepWindow).rounded()),
            waterGoalOz: waterGoal,
            waterGoalMetStreakDays: waterStreak,
            typicalDailyWaterOz: median(waterWindow),
            daysOfHistory: historyDays
        )
    }

    private var recommendation: RecommendationEngine.Recommendation? {
        RecommendationEngine.bestRecommendation(input, snoozed: snoozedIDs)
    }

    // MARK: Body

    var body: some View {
        if let rec = recommendation {
            card(rec)
                .overlay(ConfettiBurst(trigger: celebrate))
                .sensoryFeedback(.success, trigger: applauseTick)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: applied)
        }
    }

    @ViewBuilder
    private func card(_ rec: RecommendationEngine.Recommendation) -> some View {
        if applied {
            appliedState(rec)
        } else {
            proposalState(rec)
        }
    }

    // The proposal — headline, warm rationale, and the two actions.
    private func proposalState(_ rec: RecommendationEngine.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                ZStack {
                    Circle().fill(tint(rec.tintToken).opacity(0.18))
                    Image(systemName: rec.systemImage)
                        .font(.headline)
                        .foregroundStyle(tint(rec.tintToken))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(profile.coachName) has an idea")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(rec.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Text(rec.rationale)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.sm) {
                Button {
                    apply(rec)
                } label: {
                    Text(rec.applyButtonLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.brandGradient,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                }
                .buttonStyle(.jelly)
                .accessibilityLabel("Apply: \(rec.applyButtonLabel)")

                if rec.declineable {
                    Button {
                        snooze(rec.id)
                    } label: {
                        Text("Not now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, 11)
                            .padding(.horizontal, Theme.Space.md)
                            .background(Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .bouncyPress()
                    .accessibilityHint("Dismisses this suggestion for two weeks")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .overlay(alignment: .topTrailing) {
            Image(systemName: "wand.and.stars")
                .font(.caption2)
                .foregroundStyle(tint(rec.tintToken).opacity(0.6))
                .padding(10)
        }
    }

    // Brief celebratory confirmation shown right after Apply.
    private func appliedState(_ rec: RecommendationEngine.Recommendation) -> some View {
        HStack(spacing: Theme.Space.md) {
            ZStack {
                Circle().fill(Theme.positive.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.positive)
            }
            .frame(width: 40, height: 40)
            .popIn(applied)

            Text(rec.appliedConfirmation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    // MARK: Actions

    private func apply(_ rec: RecommendationEngine.Recommendation) {
        rec.apply(profile)                  // one-directional mutation (engine-guarded)
        try? context.save()
        applauseTick += 1
        celebrate += 1
        withAnimation { applied = true }
        // Also snooze the id so that, after the brief confirmation, the engine won't
        // immediately re-propose the same family on the next recompute.
        snooze(rec.id)
    }

    // MARK: Tint mapping (same vocabulary as InsightCard)

    private func tint(_ t: RecommendationEngine.Recommendation.Tint) -> Color {
        switch t {
        case .brand:    return Theme.brand
        case .info:     return Theme.info
        case .water:    return Theme.water
        case .positive: return Theme.positive
        }
    }
}

// MARK: - Pure history helpers (no SwiftData; trivially reasoned about)

private struct DayTotal { let day: Date; let total: Double }

extension RecommendationCard {

    /// Collapse a set of entries into one total per calendar day, most-recent-first.
    fileprivate func dailyTotals<T>(_ entries: [T],
                                    value: (T) -> Double,
                                    date: KeyPath<T, Date>) -> [DayTotal] {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e[keyPath: date])
            byDay[day, default: 0] += value(e)
        }
        return byDay
            .map { DayTotal(day: $0.key, total: $0.value) }
            .sorted { $0.day > $1.day }
    }

    /// Count consecutive days from today backwards where that day's total met `goal`.
    /// A gap (a missing day) or a miss ends the streak — same semantics as the
    /// dashboard's streak helpers. Returns 0 if today isn't present/met.
    fileprivate func metStreak(_ totals: [DayTotal], goal: Double, calendar cal: Calendar) -> Int {
        guard goal > 0 else { return 0 }
        let byDay = Dictionary(uniqueKeysWithValues:
            totals.map { (cal.startOfDay(for: $0.day), $0.total) })
        var n = 0
        var day = cal.startOfDay(for: .now)
        while let total = byDay[day], total >= goal {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    /// The daily totals within the last `lastNDays` calendar days.
    fileprivate func window(_ totals: [DayTotal], lastNDays: Int, calendar cal: Calendar) -> [Double] {
        guard lastNDays > 0 else { return [] }
        let cutoff = cal.date(byAdding: .day, value: -(lastNDays - 1),
                              to: cal.startOfDay(for: .now)) ?? .now
        return totals.filter { $0.day >= cutoff }.map(\.total)
    }

    /// Median — robust to a single unusually big (or small) day, so the bump we size
    /// reflects her typical effort, not an outlier.
    fileprivate func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
