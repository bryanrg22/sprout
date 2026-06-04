import SwiftUI
import SwiftData

/// The **Workouts** tab: a warm primary "Log a workout" CTA plus the list of recent sessions,
/// newest first, each tappable into its `WorkoutDayDetail`. On-brand with the rest of the app
/// (Theme tokens, `.cardElevated()`, the food/workout list idiom).
///
/// Phase 1 scope: logging + history + day detail. No strength charts / no day-suggestions
/// (those are Phase 2).
struct WorkoutsView: View {
    @Environment(\.modelContext) private var context

    /// Newest-first so the list reads like the food log. (`ExerciseEntry` rows are linked by a
    /// flat `sessionID`, so we fetch them all and group in Swift — same approach as the checklist
    /// filtering today's items client-side.)
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var exercises: [ExerciseEntry]

    @State private var showLogFlow = false
    /// Bumped on delete for a soft haptic.
    @State private var deleteTick = 0

    /// Exercises for one session, in insertion order (by their own ascending nothing — stable on
    /// the array). Keyed lookup keeps the per-row cost tiny.
    private func exercises(for session: WorkoutSession) -> [ExerciseEntry] {
        exercises.filter { $0.sessionID == session.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { addButton }
            }
            .sheet(isPresented: $showLogFlow) {
                WorkoutLogFlow()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: deleteTick)
        }
    }

    // MARK: Add button (toolbar)

    private var addButton: some View {
        Button { showLogFlow = true } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.brand)
        }
        .bouncyPress()
        .accessibilityLabel("Log a workout")
    }

    // MARK: List

    private var sessionList: some View {
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                // The always-present primary CTA at the top of the populated state.
                logCTA

                ForEach(sessions) { session in
                    NavigationLink {
                        WorkoutDayDetail(session: session)
                    } label: {
                        SessionRow(session: session, exercises: exercises(for: session))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { delete(session) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(Theme.Space.md)
        }
    }

    /// The big, filled brand-gradient "Log a workout" pill — the primary action in both states.
    private var logCTA: some View {
        Button { showLogFlow = true } label: {
            Label("Log a workout", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.brandGradient,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .accessibilityLabel("Log a workout")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Space.lg) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 108, height: 108)
                    .breathing()
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .wiggle()
            }
            VStack(spacing: Theme.Space.xs) {
                Text("Let's log a workout! 🏋️‍♀️")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Tap the machines you did — we'll assume a comfy 3×10. Edit anything you like.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { showLogFlow = true } label: {
                Label("Log your first workout", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.brandGradient,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .bouncyPress()
            .padding(.top, Theme.Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.xl)
    }

    // MARK: Mutations

    private func delete(_ session: WorkoutSession) {
        deleteTick += 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            // Remove the session AND its linked exercise rows (no @Relationship cascade).
            for entry in exercises(for: session) { context.delete(entry) }
            context.delete(session)
            try? context.save()
        }
    }
}

// MARK: - Session row

/// A single recent-session row: the kind's icon, a title ("Gym · Legs" / "Run"), a friendly date,
/// and a compact summary footing ("45 min · 3 machines"). Tapping opens the day detail.
private struct SessionRow: View {
    let session: WorkoutSession
    let exercises: [ExerciseEntry]

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: session.kind.systemImage)
                .font(.headline)
                .foregroundStyle(Theme.brand)
                .frame(width: 38, height: 38)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutSummary.title(for: session))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(WorkoutSummary.dateLine(for: session))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: Theme.Space.sm)

            Text(WorkoutSummary.summary(for: session, exerciseCount: exercises.count))
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(WorkoutSummary.title(for: session)), \(WorkoutSummary.summary(for: session, exerciseCount: exercises.count))")
    }
}

// MARK: - Shared summary formatting

/// Small, pure formatters shared by the list row + the day detail header, so both read the same.
enum WorkoutSummary {
    /// "Gym · Legs, Arms" for a gym session with focuses, else just the kind label ("Run").
    static func title(for session: WorkoutSession) -> String {
        guard session.kind.isGym else { return session.kind.label }
        let focuses = session.focuses
        guard !focuses.isEmpty else { return session.kind.label }
        return "\(session.kind.label) · \(focuses.map(\.label).joined(separator: ", "))"
    }

    /// "Today" / "Yesterday" / a friendly date (with the year only when it's not this year).
    static func dateLine(for session: WorkoutSession) -> String {
        let cal = Calendar.current
        let day = session.date
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = cal.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(
            sameYear
            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        )
    }

    /// "45 min · 3 machines" — drops the duration when unset, and the machine count when 0.
    static func summary(for session: WorkoutSession, exerciseCount: Int) -> String {
        var parts: [String] = []
        if session.durationMinutes > 0 { parts.append("\(session.durationMinutes) min") }
        if exerciseCount > 0 {
            parts.append(exerciseCount == 1 ? "1 machine" : "\(exerciseCount) machines")
        }
        return parts.isEmpty ? session.kind.label : parts.joined(separator: " · ")
    }
}

#Preview {
    WorkoutsView()
        .modelContainer(for: [WorkoutSession.self, ExerciseEntry.self], inMemory: true)
}
