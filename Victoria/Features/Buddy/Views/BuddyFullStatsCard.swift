import SwiftUI

/// Renders a buddy's FULL day — weight trend, calories, protein, and today's foods — for
/// partners who've **explicitly opted in** to sharing everything (the rest of the Buddy
/// experience stays activity-only).
///
/// This is the deliberate counterpart to `BuddyStatusCard`, which is contractually
/// number-free. Here the two people have *chosen* to share the real numbers, so the copy
/// is direct and warm — no hedging, no shame, just "here's how they're doing today."
///
/// **Self-hiding.** When the buddy hasn't opted in (`!snapshot.sharesFullData`) this
/// renders an `EmptyView` and reserves no space — so dropping it into the hub is safe even
/// when the buddy shares only activity. (Older snapshots predate the field and read as
/// not-sharing, so they hide too.)
///
/// Everything it shows comes straight off the `BuddySnapshotPayload` the buddy published;
/// it does no math beyond formatting + clamping a progress fraction for the bars.
struct BuddyFullStatsCard: View {
    let snapshot: BuddySnapshotPayload

    var body: some View {
        if snapshot.sharesFullData {
            card
        }
        // else: EmptyView — buddy shares activity only; this card stays hidden.
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            weightRow
            Divider().overlay(Theme.divider)
            caloriesRow
            proteinRow
            Divider().overlay(Theme.divider)
            foodsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Header — "{Name}'s day"

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle()
                    .fill(Theme.brand.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
            }
            Text(headerTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// "Victoria's day" — a warm, possessive title using the buddy's display name (falls
    /// back to a friendly generic when, somehow, the name is blank).
    private var headerTitle: String {
        let name = snapshot.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Their day" : "\(name)'s day"
    }

    // MARK: Weight — trend + signed weekly rate

    private var weightRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            statLabel("Weight")
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(weightText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                rateChip
            }
        }
    }

    private var weightText: String {
        "\(Self.oneDecimal(snapshot.trendWeightLbs)) lb"
    }

    /// A small signed rate ("↓ 1.2 lb/wk") tinted green when they're moving the helpful way
    /// (toward their goal), plus a soft "to goal X" reminder when a goal is set. When the
    /// rate is essentially flat we show a gentle "holding steady" instead of a 0.0 arrow.
    @ViewBuilder private var rateChip: some View {
        HStack(spacing: 6) {
            Text(rateText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(rateTint)
            if snapshot.goalWeightLbs > 0 {
                Text("· to goal \(Self.oneDecimal(snapshot.goalWeightLbs))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Below this magnitude (lb/wk) we treat the rate as flat — avoids a noisy "↓ 0.0".
    private static let flatRateThreshold = 0.1

    private var rateText: String {
        let rate = snapshot.weeklyRateLbs
        if abs(rate) < Self.flatRateThreshold { return "holding steady" }
        let arrow = rate < 0 ? "↓" : "↑"
        return "\(arrow) \(Self.oneDecimal(abs(rate))) lb/wk"
    }

    /// Green when they're trending the helpful direction. "Helpful" is goal-aware: if a goal
    /// is set, that's moving *toward* it (losing while above goal, or gaining while below);
    /// with no goal we treat losing as the positive default (this is a weight-loss app).
    /// Flat reads as a calm secondary color — neither win nor loss.
    private var rateTint: Color {
        let rate = snapshot.weeklyRateLbs
        if abs(rate) < Self.flatRateThreshold { return Theme.textSecondary }
        let goal = snapshot.goalWeightLbs
        let trend = snapshot.trendWeightLbs
        let movingTowardGoal: Bool
        if goal > 0, trend > 0 {
            // Above goal → want to lose (rate < 0); below goal → want to gain (rate > 0).
            movingTowardGoal = trend > goal ? (rate < 0) : (rate > 0)
        } else {
            movingTowardGoal = rate < 0   // no goal: losing is the warm default
        }
        return movingTowardGoal ? Theme.positive : Theme.textSecondary
    }

    // MARK: Calories — eaten / target with a thin progress bar

    private var caloriesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                statLabel("Calories today")
                Spacer(minLength: 0)
                Text(caloriesText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            progressBar(fraction: Self.fraction(snapshot.caloriesEaten, of: snapshot.calorieTarget),
                        tint: Theme.calories)
        }
    }

    private var caloriesText: String {
        let eaten = Self.grouped(snapshot.caloriesEaten)
        if snapshot.calorieTarget > 0 {
            return "\(eaten) / \(Self.grouped(snapshot.calorieTarget)) kcal"
        }
        return "\(eaten) kcal"
    }

    // MARK: Protein — eaten / target

    private var proteinRow: some View {
        HStack(alignment: .firstTextBaseline) {
            statLabel("Protein")
            Spacer(minLength: 0)
            Text(proteinText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.protein)
        }
    }

    private var proteinText: String {
        let eaten = Self.grouped(snapshot.proteinEaten)
        if snapshot.proteinTarget > 0 {
            return "\(eaten) / \(Self.grouped(snapshot.proteinTarget)) g"
        }
        return "\(eaten) g"
    }

    // MARK: Today's foods

    private var foodsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            statLabel("Eaten today")
            Text(foodsText)
                .font(.subheadline)
                .foregroundStyle(hasFoods ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hasFoods: Bool {
        !snapshot.todayFoods.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var foodsText: String {
        hasFoods ? snapshot.todayFoods : "Nothing logged yet"
    }

    // MARK: - Shared bits

    /// A small, uppercase section label (matches the quiet metadata style used across cards).
    private func statLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }

    /// A thin, rounded progress bar (track + tinted fill), clamped to 0...1. Mirrors the
    /// face-off's bar recipe so the two cards feel of a piece.
    private func progressBar(fraction: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.divider.opacity(0.6))
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(fraction, 1)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
    }

    // MARK: - Formatting helpers

    /// `eaten / target` as a 0...1 fraction (0 when there's no positive target).
    private static func fraction(_ value: Double, of target: Double) -> Double {
        guard target > 0 else { return 0 }
        return value / target
    }

    /// Grouped integer ("1,355"). Values are kcal/grams — whole numbers read cleanest.
    private static func grouped(_ value: Double) -> String {
        value.rounded().formatted(.number.grouping(.automatic))
    }

    /// One-decimal weight ("153.8"), trimming a trailing ".0" so round numbers stay clean.
    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var accessibilitySummary: String {
        var parts = [headerTitle]
        parts.append("weight \(weightText), \(rateText)")
        parts.append("calories \(caloriesText)")
        parts.append("protein \(proteinText)")
        parts.append(hasFoods ? "eaten today: \(snapshot.todayFoods)" : "nothing logged yet")
        return parts.joined(separator: ". ")
    }
}

#Preview("Buddy full stats") {
    ZStack {
        Theme.background.ignoresSafeArea()
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                // Opted in — full card.
                BuddyFullStatsCard(snapshot: .init(
                    ownerUserID: "b", displayName: "Victoria",
                    dayStreak: 6, characterMood: .thriving,
                    loggedToday: true, lastActive: .now,
                    sharesFullData: true,
                    trendWeightLbs: 153.8, goalWeightLbs: 140, weeklyRateLbs: -1.2,
                    caloriesEaten: 1355, calorieTarget: 1741,
                    proteinEaten: 98, proteinTarget: 126,
                    todayFoods: "Greek yogurt & berries, Grilled chicken salad, Trail mix"))

                // Nothing logged yet + holding steady (edge copy).
                BuddyFullStatsCard(snapshot: .init(
                    ownerUserID: "b", displayName: "Sam",
                    dayStreak: 2, characterMood: .happy,
                    loggedToday: false, lastActive: .now,
                    sharesFullData: true,
                    trendWeightLbs: 162, goalWeightLbs: 0, weeklyRateLbs: 0.0,
                    caloriesEaten: 0, calorieTarget: 1800,
                    proteinEaten: 0, proteinTarget: 130,
                    todayFoods: ""))

                // Not opted in — renders nothing (no card below this line in the preview).
                BuddyFullStatsCard(snapshot: .init(
                    ownerUserID: "b", displayName: "Alex",
                    dayStreak: 0, characterMood: .sleepy,
                    loggedToday: false, lastActive: .now))
            }
            .padding()
        }
    }
}
