import SwiftUI
import SwiftData

/// The adaptive **Plan** on the Progress screen: a CTA when there's no plan yet, or the plan itself —
/// headline, assessment, the calorie *range* + protein, and the insight "tickets." This is the plan
/// "standing still"; tapping through to Vita (the plan "talking back") comes in P2. (docs/adaptive-plan.md)
struct PlanCard: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \CoachPlan.updatedAt, order: .reverse) private var plans: [CoachPlan]
    @Query private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var showIntake = false

    private var plan: CoachPlan? { plans.first }
    private var coachName: String { profile.coachName.isEmpty ? "Vita" : profile.coachName }

    var body: some View {
        Group {
            if let plan {
                planView(plan)
            } else {
                cta
            }
        }
        .sheet(isPresented: $showIntake) {
            PlanIntakeView(profile: profile, foods: foods, weights: weights)
        }
    }

    // MARK: - CTA (no plan yet)

    private var cta: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                Text("Your plan").font(.headline).foregroundStyle(Theme.textPrimary)
            }
            Text("Let \(coachName) study your goals and every day you've logged, then build a personal plan — real targets, honest insights, and it adapts as you go.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showIntake = true } label: {
                Text("Build my plan").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.brand.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.brand.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Plan view

    private func planView(_ plan: CoachPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            // Header: label + refresh
            HStack {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                    Text("Your plan").font(.headline).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Button { showIntake = true } label: {
                    Image(systemName: "arrow.clockwise").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.brand)
                .accessibilityLabel("Rebuild plan")
            }

            if !plan.headline.isEmpty {
                Text(plan.headline).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.isEarlyRead {
                Label("Early read — it'll sharpen as you log more", systemImage: "hourglass")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            }

            if !plan.assessment.isEmpty {
                MarkdownMessage(plan.assessment, color: Theme.textPrimary)
            }

            // Targets — the RANGE + protein.
            if plan.hasRange || plan.proteinTarget > 0 {
                HStack(spacing: Theme.Space.lg) {
                    if plan.hasRange {
                        targetStat("Daily fuel", "\(plan.calorieRangeText) kcal")
                    }
                    if plan.proteinTarget > 0 {
                        targetStat("Protein", "\(Int(plan.proteinTarget))g")
                    }
                }
                .padding(.top, 2)
            }

            // Insight "tickets".
            if !plan.insights.isEmpty {
                VStack(spacing: Theme.Space.sm) {
                    ForEach(plan.insights) { InsightRow(insight: $0) }
                }
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func targetStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.headline).foregroundStyle(Theme.brand)
        }
    }
}

/// One insight ticket — tone-colored dot + title + body.
private struct InsightRow: View {
    let insight: PlanInsight

    private var tint: Color {
        switch insight.tone {
        case .win:   return Theme.positive
        case .watch: return Theme.warning
        case .nudge: return Theme.brand
        }
    }
    private var icon: String {
        switch insight.tone {
        case .win:   return "checkmark.circle.fill"
        case .watch: return "exclamationmark.circle.fill"
        case .nudge: return "arrow.up.forward.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.body).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
