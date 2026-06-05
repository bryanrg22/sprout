import SwiftUI
import SwiftData

/// One past workout, opened from the Workouts list — the "tap a day to see everything you did"
/// view, mirroring the food day view. Header shows the kind + focuses + a "45 min · 3 machines"
/// summary; below, each exercise as a row: name · weight · reps×sets.
struct WorkoutDayDetail: View {
    let session: WorkoutSession

    /// All exercise rows; we filter to this session's `id` in Swift (flat foreign key, no
    /// `@Relationship`). Re-queried live so a deletion elsewhere reflects here.
    @Query private var allExercises: [ExerciseEntry]

    private var exercises: [ExerciseEntry] {
        allExercises.filter { $0.sessionID == session.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                header

                if exercises.isEmpty {
                    emptyExercises
                } else {
                    exerciseCard
                }

                if !session.notes.isEmpty {
                    notesCard
                }
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(WorkoutSummary.dateLine(for: session))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: session.kind.systemImage)
                .font(.title2)
                .foregroundStyle(Theme.brand)
                .frame(width: 46, height: 46)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(WorkoutSummary.title(for: session))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(WorkoutSummary.summary(for: session, exerciseCount: exercises.count))
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
    }

    // MARK: Exercises

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().background(Theme.divider) }
                ExerciseDetailRow(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    private var emptyExercises: some View {
        HStack(spacing: Theme.Space.sm) {
            // The session's own icon (a dumbbell for a run reads wrong) — matches the header.
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
            Image(systemName: entry.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 30, height: 30)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

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
