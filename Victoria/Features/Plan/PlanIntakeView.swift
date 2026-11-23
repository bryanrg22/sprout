import SwiftUI
import SwiftData

/// The opt-in "let's build your plan" intake — a HYBRID, deliberately not a rigid Q&A: a little
/// structured context (her goal + current weight, read from the profile) plus two open boxes she
/// free-writes. On submit it runs the heavy authoring pass (the provider's top tier — Opus on
/// Anthropic) behind a real "thinking it through" state, then dismisses; the Plan card on Progress
/// picks up the new plan. (See docs/adaptive-plan.md.)
struct PlanIntakeView: View {
    let profile: UserProfile
    let foods: [FoodEntry]
    let weights: [WeightEntry]
    /// When set, this is an ADJUST (a plan already exists): we show her current targets and ask
    /// what's changed, rather than the first-time "let's build it" framing. Either way the build
    /// runs the same deep-research `generate` pass, so an adjust is a genuine re-research.
    var existingPlan: CoachPlan? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var timeframe = ""
    @State private var dayToDay = ""
    @State private var exercise = ""
    @State private var whatsChanged = ""   // adjust mode: the single "what's different now" box
    @State private var isBuilding = false
    @State private var errorText: String?
    @FocusState private var fieldFocused: Bool   // any intake box; drives the keyboard "Done" button

    private var isAdjust: Bool { existingPlan != nil }
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
            .navigationTitle(isAdjust ? "Adjust your plan" : "Build your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isBuilding { Button("Cancel") { dismiss() } }
                }
                // A "Done" above the keyboard so the submit button is always reachable — the boxes
                // grow as she types and can otherwise hide it (esp. on the single big adjust box).
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                        .font(.body.weight(.semibold))
                        .tint(Theme.brand)
                }
            }
        }
        .tint(Theme.brand)
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(isAdjust
                     ? "Tell \(coachName) what's changed since your last plan — a new goal or timeframe, a different schedule, new training, anything. \(coachName) will do fresh deep research over this **and** every day you've logged, and update your whole plan."
                     : "Tell \(coachName) what you're going for, in your own words. The more real the better — \(coachName) reasons over this **and** every day you've logged to build a plan just for you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Structured context (read straight from the profile — editable goals come later).
                if profile.goalWeightLbs > 0 {
                    HStack(spacing: Theme.Space.lg) {
                        labeledStat("Goal", profile.unitSystem.format(profile.goalWeightLbs, decimals: 0))
                        labeledStat("Now", "~" + profile.unitSystem.format(currentWeight, decimals: 0))
                    }
                }

                // When adjusting, show the plan she has now so she can see what she's changing from.
                if let plan = existingPlan, plan.hasRange || plan.proteinTarget > 0 {
                    HStack(spacing: Theme.Space.lg) {
                        if plan.hasRange { labeledStat("Plan fuel", "\(plan.calorieRangeText) kcal") }
                        if plan.proteinTarget > 0 { labeledStat("Plan protein", "\(Int(plan.proteinTarget)) g") }
                    }
                }

                if isAdjust {
                    // She already told Vita the whole picture when she built the plan — re-asking the
                    // full intake would be making a NEW plan. Adjusting just needs ONE open space for
                    // what's different now; Vita re-researches that against everything she's logged.
                    field(title: "What's changed?",
                          placeholder: "e.g. I want to go faster now · my schedule freed up · I started lifting 5×/week · I've hit a plateau · my goal shifted to 135…",
                          text: $whatsChanged, minHeight: 160)
                } else {
                    field(title: "By when?",
                          placeholder: "e.g. by the end of summer, before school starts",
                          text: $timeframe, minHeight: 44)

                    field(title: "What's your day-to-day like?",
                          placeholder: "Work / school, schedule, how much time you have, anything going on…",
                          text: $dayToDay, minHeight: 96)

                    field(title: "Your exercise & training",
                          placeholder: "Gym days, running, sports — or if you're just getting started…",
                          text: $exercise, minHeight: 96)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: build) {
                    Text(isAdjust ? "Update my plan" : "Build my plan")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .padding(.top, Theme.Space.xs)
            }
            .padding(Theme.Space.lg)
        }
        // Let her swipe the keyboard down to reach "Build my plan" — the boxes grow as she writes, so
        // without this the button can sit under the keyboard after she types in the last field.
        .scrollDismissesKeyboard(.interactively)
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
                .focused($fieldFocused)
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
            Text("Reading every day you've logged, checking current research, and thinking through how to actually get you there. This takes a moment.")
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
    nonisolated static let intakePrefix = CoachMemory.planIntakeLabel

    private func foldContextIntoProfile() {
        let bits = [dayToDay, exercise]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !bits.isEmpty else { return }
        let addition = Self.intakePrefix + "life + training: " + bits.joined(separator: " · ")
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
        let intake = isAdjust ? adjustIntake : """
        Timeframe: \(timeframe.trimmingCharacters(in: .whitespacesAndNewlines))
        Day-to-day: \(dayToDay.trimmingCharacters(in: .whitespacesAndNewlines))
        Exercise & schedule: \(exercise.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        let verb = isAdjust ? "update" : "build"
        errorText = nil
        isBuilding = true
        Task {
            do {
                _ = try await PlanService.generate(profile: profile, foods: foods, weights: weights,
                                                   intake: intake, context: context)
                await MainActor.run {
                    if !isAdjust { foldContextIntoProfile() }   // the first build grows her durable profile
                    dismiss()
                }
            } catch AIConfig.AIError.missingKey {
                await MainActor.run {
                    isBuilding = false
                    errorText = "\(coachName) needs your \(AIConfig.provider.label) key to \(verb) your plan — add one in More → AI."
                }
            } catch {
                await MainActor.run {
                    isBuilding = false
                    errorText = "Something went wrong \(verb == "update" ? "updating" : "building") your plan. Let's try again in a moment."
                }
            }
        }
    }

    /// The adjust-mode intake: the current plan (so the model adjusts FROM it, not blind) + what she
    /// said is different now. `generate` still re-researches it against every day she's logged.
    private var adjustIntake: String {
        var out = "This is an ADJUSTMENT to an existing plan."
        if let plan = existingPlan {
            if plan.hasRange { out += "\nCurrent plan fuel range: \(plan.calorieRangeText) kcal." }
            if plan.proteinTarget > 0 { out += "\nCurrent plan protein: \(Int(plan.proteinTarget)) g." }
            if !plan.headline.isEmpty { out += "\nCurrent plan headline: \(plan.headline)" }
        }
        out += "\n\nWhat's changed since that plan, in the user's own words:\n\(whatsChanged.trimmingCharacters(in: .whitespacesAndNewlines))"
        return out
    }
}
