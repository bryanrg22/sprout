import SwiftUI
import SwiftData

/// The adaptive **Plan** on the Progress screen: a CTA when there's no plan yet, or the plan itself —
/// headline, assessment, the calorie *range* + protein, and the insight "tickets." This is the plan
/// "standing still"; tapping through to Vita (the plan "talking back") comes in P2. (docs/adaptive-plan.md)
struct PlanCard: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(AskVitaCenter.self) private var askVita: AskVitaCenter?
    @Query(sort: \CoachPlan.updatedAt, order: .reverse) private var plans: [CoachPlan]
    @Query private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var showIntake = false
    @State private var isReviewing = false
    @State private var reviewError: String?

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
            // Pass the current plan when one exists → the intake opens in "adjust" framing (shows her
            // current targets, asks what's changed). nil → the first-time "build" framing.
            PlanIntakeView(profile: profile, foods: foods, weights: weights, existingPlan: plan)
        }
    }

    // MARK: - CTA (no plan yet)

    private var cta: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                Text("Your plan").font(.headline).foregroundStyle(Theme.textPrimary)
            }
            Text("\(coachName) will do deep research on your goals and every day you've logged — then build a plan that truly helps you reach them, with real targets that adapt as you go.")
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

    /// Compact on Progress by design: just the headline + the live targets, then a clear "adjust"
    /// block. The deep narrative (assessment, insights, the research brief) lives in the "Your
    /// progress" recap above and inside Vita — the plan card here is the at-a-glance + the way in to
    /// changing it, not a wall of text.
    private func planView(_ plan: CoachPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            // Header: label + a light "re-check against my latest data" refresh.
            HStack {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                    Text("Your plan").font(.headline).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                if isReviewing {
                    ProgressView().controlSize(.small).tint(Theme.brand)
                } else {
                    Button { Task { await review() } } label: {
                        Image(systemName: "arrow.clockwise").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.brand)
                    .accessibilityLabel("Re-check my plan against my latest data")
                }
            }

            if !plan.headline.isEmpty {
                Text(plan.headline).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.isEarlyRead {
                Label("Early read — it'll sharpen as you log more", systemImage: "hourglass")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            }

            // Targets — the RANGE + protein (the live numbers driving the whole app).
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

            // Goals changed since this plan was authored → its premises (not just its
            // numbers) are stale. Offer the FULL rebuild with fresh research, loudly.
            if plan.goalsChangedSinceBuild {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Label("Your goals changed since this plan was built",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.warning)
                    Text("These targets were researched for your old goal. A fresh build re-does the research around the new one.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { showIntake = true } label: {
                        Label("Rebuild with fresh research", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                }
                .padding(Theme.Space.md)
                .background(Theme.warning.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }

            // The "adjust" block — got new details, or want a fresh deep-research pass?
            Divider().overlay(Theme.divider).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Got new details, or want to go deeper?")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("Tell \(coachName) what's changed and she'll do fresh deep research and update your whole plan — your targets adjust everywhere.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showIntake = true } label: {
                    Label("Adjust my plan", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                Button { askAdjust(plan) } label: {
                    Text("or ask \(coachName) to tweak it")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.brand)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            if let reviewError {
                Text(reviewError).font(.caption).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    /// Conversational adjust: hand Vita the current plan + a "what should change?" prompt so she can
    /// tweak it in chat (she has the plan in context + the edit_plan tools). The deep-research path is
    /// the "Adjust my plan" button above (re-opens the intake). Mirrors `askInsight`.
    private func askAdjust(_ plan: CoachPlan) {
        let targets = plan.hasRange ? "My plan's fuel range is \(plan.calorieRangeText) kcal"
            + (plan.proteinTarget > 0 ? " and protein is \(Int(plan.proteinTarget))g. " : ". ") : ""
        askVita?.ask(AskVitaTopic(
            name: "Adjust my plan",
            icon: "slider.horizontal.3",
            value: "",
            question: "I'd like to adjust my plan. \(targets)Look at how I've actually been doing (weight trend, calories, protein, steps, consistency) and tell me what to tweak and why — and make the change if it helps."))
    }

    // MARK: - Adapt (the P3 review pass)

    /// Re-read the latest data against the existing plan and adapt it in place (range / protein /
    /// insights + a changelog line) — the lighter "are we on target?" pass, not a full rebuild.
    @MainActor
    private func review() async {
        guard !isReviewing else { return }
        isReviewing = true
        reviewError = nil
        do {
            _ = try await PlanService.review(profile: profile, foods: foods, weights: weights, context: context)
        } catch AIConfig.AIError.missingKey {
            reviewError = "\(coachName) needs your \(AIConfig.provider.label) key to update your plan."
        } catch {
            reviewError = "Couldn't update your plan just now — try again in a moment."
        }
        isReviewing = false
    }

    private func targetStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.headline).foregroundStyle(Theme.brand)
        }
    }
}
