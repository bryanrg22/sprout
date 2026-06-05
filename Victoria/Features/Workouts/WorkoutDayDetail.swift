import SwiftUI
import SwiftData

/// One past workout, opened from the Workouts list — the "tap a day to see everything you did"
/// view, mirroring the food day view. Header shows the kind + focuses + a "45 min · 3 machines"
/// summary; below, each exercise as a row: name · weight · reps×sets.
struct WorkoutDayDetail: View {
    let session: WorkoutSession

    /// All exercise rows; filtered to this session in Swift (flat foreign key, no `@Relationship`).
    /// Re-queried live so an edit or delete reflects here immediately.
    @Query private var allExercises: [ExerciseEntry]
    @Query private var profiles: [UserProfile]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AskVitaCenter.self) private var askVita: AskVitaCenter?

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var exercises: [ExerciseEntry] {
        // Sorted by catalog order so the breakdown reads intentionally (chest moves grouped, etc.)
        // rather than in arbitrary `@Query` order; off-catalog customs fall to the end, stably.
        let rows = allExercises.filter { $0.sessionID == session.id }
        return rows.sorted {
            (MachineCatalog.catalogIndex[$0.machineKey] ?? .max) < (MachineCatalog.catalogIndex[$1.machineKey] ?? .max)
        }
    }
    private var stats: WorkoutStats { WorkoutStats(session: session, exercises: exercises) }
    private var coachName: String { profiles.first?.coachName ?? "Vita" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                header
                heroCard
                if exercises.isEmpty { emptyExercises } else { exerciseCard }
                if !session.notes.isEmpty { notesCard }
                actions
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle(WorkoutSummary.dateLine(for: session))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) { WorkoutLogFlow(editing: session) }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This \(session.kind.label.lowercased()) session will be removed.")
        }
    }

    // MARK: Header (title + attribute chips — no longer the old "Gym again" summary row)

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(WorkoutSummary.title(for: session))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !headerChips.isEmpty {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(Array(headerChips.enumerated()), id: \.offset) { _, chip in
                        detailChip(chip.text, systemImage: chip.icon)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerChips: [(text: String, icon: String)] {
        // Lead with WHEN she trained (start time), then duration + machine count.
        var chips: [(text: String, icon: String)] = [
            (text: session.date.formatted(date: .omitted, time: .shortened), icon: "clock")
        ]
        if session.durationMinutes > 0 { chips.append((text: "\(session.durationMinutes) min", icon: "timer")) }
        if !exercises.isEmpty {
            chips.append((text: exercises.count == 1 ? "1 machine" : "\(exercises.count) machines", icon: "dumbbell"))
        }
        return chips
    }

    private func detailChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.card, in: Capsule())
    }

    // MARK: Hero stat (the personalized number — total volume / sets / duration)

    private var heroCard: some View {
        let h = stats.headline
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(h.value)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(h.unit)
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: session.kind.systemImage)
                    .font(.title2)
                    .foregroundStyle(Theme.brand)
            }
            if !stats.secondary.isEmpty {
                Text(stats.secondary)
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    // MARK: Exercises

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Exercises")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().background(Theme.divider) }
                    ExerciseDetailRow(entry: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    private var emptyExercises: some View {
        HStack(spacing: Theme.Space.sm) {
            // The session's own icon (a dumbbell for a run reads wrong).
            Image(systemName: session.kind.systemImage)
                .foregroundStyle(Theme.textSecondary)
            Text(session.kind.isGym ? "No machines logged for this one." : "A \(session.kind.label.lowercased()) session.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(session.notes)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    // MARK: Actions (Edit · Ask <coach> · Delete — mirrors the food detail)

    private var actions: some View {
        VStack(spacing: Theme.Space.sm) {
            Button { showEdit = true } label: {
                Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)

            HStack(spacing: Theme.Space.sm) {
                Button {
                    askVita?.ask(askWorkoutVitaTopic(session: session, exercises: exercises, stats: stats))
                    dismiss()
                } label: {
                    Label("Ask \(coachName)", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(Theme.brand)
                }
                .buttonStyle(.plain)
                .disabled(askVita == nil)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(Theme.warning)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    // MARK: Logic

    private func delete() {
        // Remove the session AND its linked exercise rows (no @Relationship cascade).
        for entry in exercises { context.delete(entry) }
        context.delete(session)
        try? context.save()
        dismiss()
    }
}

// MARK: - Ask-the-coach topic

/// Builds the "Ask <coach> about this workout" topic — EDUCATE-first and encouraging: it asks how
/// the session fits the user's goals and for an easy way to progress, never to judge it. Shared
/// shape with `askVitaTopic(for:)` on the food side.
func askWorkoutVitaTopic(session: WorkoutSession, exercises: [ExerciseEntry], stats: WorkoutStats) -> AskVitaTopic {
    let title = WorkoutSummary.title(for: session)
    let value = [stats.headline.value + " " + stats.headline.unit, stats.secondary]
        .filter { !$0.isEmpty }.joined(separator: " · ")
    let list = exercises.prefix(10).map { e -> String in
        let setsReps = "\(e.sets)×\(e.reps)"
        return e.weightLbs > 0 ? "\(e.displayName) \(WorkoutFormat.weight(e.weightLbs)) lb \(setsReps)" : "\(e.displayName) \(setsReps)"
    }.joined(separator: ", ")
    let question: String
    if exercises.isEmpty {
        question = "I did a \(session.kind.label.lowercased()) session"
            + (session.durationMinutes > 0 ? " for \(session.durationMinutes) minutes" : "")
            + ". How does this fit my goals, and any tips for next time?"
    } else {
        question = "I just logged a \(title) workout: \(list). How does this look for my goals, "
            + "and is there an easy way to progress it next time?"
    }
    return AskVitaTopic(name: title, icon: session.kind.systemImage, value: value, question: question)
}

// MARK: - Exercise row

/// A single exercise line: icon disc, name, and a "135 lb · 3×10" detail (weight dropped when
/// unset). Read-only — matches the food day-view row idiom.
private struct ExerciseDetailRow: View {
    let entry: ExerciseEntry

    /// "135 lb · 3×10", or just "3×10" when no weight was recorded (`weightLbs == 0`).
    private var detail: String {
        let setsReps = "\(entry.sets)×\(entry.reps)"
        guard entry.weightLbs > 0 else { return setsReps }
        return "\(WorkoutFormat.weight(entry.weightLbs)) lb · \(setsReps)"
    }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            MachineImage(key: entry.machineKey, symbolName: entry.iconName)
                .font(.subheadline.weight(.semibold))   // sizes the SF-Symbol fallback
                .foregroundStyle(Theme.brand)
                .padding(4)                              // inset so a photo sits cleanly in the disc
                .frame(width: 30, height: 30)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            Text(entry.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Theme.Space.sm)

            Text(detail)
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.displayName), \(detail)")
    }
}

// MARK: - Number formatting

/// Pure weight formatting shared by the detail row + the log flow: whole numbers stay clean
/// ("135"), fractional weights show one decimal ("47.5").
enum WorkoutFormat {
    static func weight(_ lbs: Double) -> String {
        lbs == lbs.rounded() ? String(Int(lbs)) : String(format: "%.1f", lbs)
    }
}
