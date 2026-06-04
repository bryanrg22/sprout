import SwiftUI
import SwiftData

/// The opt-in "let's build your plan" intake — a HYBRID, deliberately not a rigid Q&A: a little
/// structured context (her goal + current weight, read from the profile) plus two open boxes she
/// free-writes. On submit it runs the heavy Opus authoring pass behind a real "thinking it through"
/// state, then dismisses; the Plan card on Progress picks up the new plan. (See docs/adaptive-plan.md.)
struct PlanIntakeView: View {
    let profile: UserProfile
    let foods: [FoodEntry]
    let weights: [WeightEntry]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var timeframe = ""
    @State private var dayToDay = ""
    @State private var exercise = ""
    @State private var isBuilding = false
    @State private var errorText: String?

    private var coachName: String { profile.coachName.isEmpty ? "Vita" : profile.coachName }
    private var unit: String { profile.unitSystem.weightUnit }
    private var currentWeight: Double { TrendCalculator.currentTrend(weights) ?? profile.startWeightLbs }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if isBuilding {
                    buildingState
                } else {
                    form
                }
            }
            .navigationTitle("Build your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isBuilding { Button("Cancel") { dismiss() } }
                }
            }
        }
        .tint(Theme.brand)
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text("Tell \(coachName) what you're going for, in your own words. The more real the better — she reasons over this **and** every day you've logged to build a plan just for you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Structured context (read straight from the profile — editable goals come later).
                if profile.goalWeightLbs > 0 {
                    HStack(spacing: Theme.Space.lg) {
                        labeledStat("Goal", "\(Int(profile.goalWeightLbs)) \(unit)")
                        labeledStat("Now", "~\(Int(currentWeight.rounded())) \(unit)")
                    }
                }

                field(title: "By when?",
                      placeholder: "e.g. by the end of summer, before school starts",
                      text: $timeframe, minHeight: 44)

                field(title: "What's your day-to-day like?",
                      placeholder: "Work / school, schedule, how much time you have, anything going on…",
                      text: $dayToDay, minHeight: 96)

                field(title: "Your exercise & training",
                      placeholder: "Gym days, running, sports — or if you're just getting started…",
                      text: $exercise, minHeight: 96)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: build) {
                    Text("Build my plan")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .padding(.top, Theme.Space.xs)
            }
            .padding(Theme.Space.lg)
        }
    }

    private func labeledStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.headline).foregroundStyle(Theme.textPrimary)
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.brand)
                .padding(Theme.Space.md)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.cardRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Building state

    private var buildingState: some View {
        VStack(spacing: Theme.Space.lg) {
            ProgressView().controlSize(.large).tint(Theme.brand)
            Text("\(coachName) is studying your data…")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Reading every day you've logged and thinking through how to actually get you there. This takes a few seconds.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.xl)
        }
        .padding(Theme.Space.lg)
    }

    // MARK: - Build

    /// Fold the LASTING context she shared (her day-to-day + training) into her durable profile
    /// (`CoachMemory.profileNotes`) — so it grows her "about me" and Vita carries it everywhere, not
    /// just inside the plan. Deduped + bounded, mirroring the remember_about_user tool. (The timeframe
    /// is goal-specific, not durable, so it stays out of the profile.)
    /// Stable label every plan-intake note carries, so a rebuild replaces it in place instead of
    /// stacking near-duplicates.
    nonisolated static let intakePrefix = "From her plan intake — "

    private func foldContextIntoProfile() {
        let bits = [dayToDay, exercise]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !bits.isEmpty else { return }
        let addition = Self.intakePrefix + "her life + training: " + bits.joined(separator: " · ")
        let memory = CoachMemory.fetchOrCreate(in: context, profile: profile)
        let merged = Self.foldingIntake(addition, into: memory.profileNotes, prefix: Self.intakePrefix)
        guard merged != memory.profileNotes else { return }   // exact rebuild → nothing to write
        memory.profileNotes = merged
        memory.updatedAt = .now
        try? context.save()
    }

    /// Fold a plan-intake line into existing profile notes: drop any prior line with the same stable
    /// `prefix` (so editing-then-rebuilding replaces rather than duplicates), append the new one, then
    /// bound the result by dropping WHOLE leading lines — never a raw `suffix(maxChars)` that would
    /// slice an older note mid-sentence — always keeping the just-added line (it's last). Pure + testable.
    nonisolated static func foldingIntake(_ addition: String, into existing: String,
                                          prefix: String, maxChars: Int = 2000) -> String {
        var lines = existing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.hasPrefix(prefix) }
        lines.append(addition)
        var notes = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        while notes.count > maxChars, let nl = notes.firstIndex(of: "\n") {
            notes = String(notes[notes.index(after: nl)...])
        }
        return notes
    }

    private func build() {
        let intake = """
        Timeframe: \(timeframe.trimmingCharacters(in: .whitespacesAndNewlines))
        Day-to-day: \(dayToDay.trimmingCharacters(in: .whitespacesAndNewlines))
        Exercise & schedule: \(exercise.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        errorText = nil
        isBuilding = true
        Task {
            do {
                _ = try await PlanService.generate(profile: profile, foods: foods, weights: weights,
                                                   intake: intake, context: context)
                await MainActor.run {
                    foldContextIntoProfile()   // what she shared also grows her durable profile
                    dismiss()
                }
            } catch AIConfig.AIError.missingKey {
                await MainActor.run {
                    isBuilding = false
                    errorText = "\(coachName) needs an Anthropic key to build your plan — add one in More → AI."
                }
            } catch {
                await MainActor.run {
                    isBuilding = false
                    errorText = "Something went wrong building your plan. Let's try again in a moment."
                }
            }
        }
    }
}
