import SwiftUI
import SwiftData

/// The movement log. The whole point is to reward *showing up* — a 10-minute walk
/// is a win — so the tone is kind, the friction is low, and nothing is ever
/// required beyond "what you did" and "how long."
///
/// Recent workouts are grouped by day (Today / Yesterday / date) in a native dark
/// `List`, each row showing the activity icon, title, duration and optional kcal.
/// Swipe to delete. The "＋" toolbar button opens a small add sheet.
struct WorkoutLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]

    @State private var showingAdd = false
    @State private var deleteTick = 0

    /// One-shot confetti when she logs her FIRST workout of the day — a warm little
    /// "you showed up!" moment, not on every add.
    @State private var firstWorkoutConfetti = 0
    /// Remembers today's workout count to tell a real add (0 → 1) apart from
    /// deletes or the initial data load.
    @State private var lastTodayCount: Int?

    // MARK: - Grouping

    /// One day's worth of workouts, newest day first, entries within a day newest first.
    private struct DaySection: Identifiable {
        let day: Date            // start-of-day
        let entries: [WorkoutEntry]
        var id: Date { day }
    }

    /// `workouts` is already sorted date-descending by the `@Query`, so a stable
    /// group-by start-of-day preserves that order both across and within days.
    private var sections: [DaySection] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: workouts) { cal.startOfDay(for: $0.date) }
        return grouped
            .map { DaySection(day: $0.key, entries: $0.value) }
            .sorted { $0.day > $1.day }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    emptyState
                } else {
                    workoutList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            // A subtle one-shot celebration for the first workout logged today.
            .overlay { ConfettiBurst(trigger: firstWorkoutConfetti).ignoresSafeArea() }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { addButton }
            }
            .sheet(isPresented: $showingAdd) {
                AddWorkoutSheet()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: deleteTick)
            .sensoryFeedback(.success, trigger: firstWorkoutConfetti)
            // Celebrate the day's first workout (0 → 1); ignore deletes / first load.
            .onChange(of: todayCount) { _, count in
                defer { lastTodayCount = count }
                guard let previous = lastTodayCount else { return }
                if count > previous && previous == 0 { firstWorkoutConfetti += 1 }
            }
            .onAppear { if lastTodayCount == nil { lastTodayCount = todayCount } }
        }
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            showingAdd = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.brand)
        }
        .bouncyPress()   // springy squish on tap (same pattern as Achievements)
        .accessibilityLabel("Log a workout")
    }

    // MARK: - List

    private var workoutList: some View {
        List {
            // A gentle, non-shaming header that celebrates the habit.
            encouragementCard
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Theme.Space.sm, leading: Theme.Space.md,
                                          bottom: Theme.Space.md, trailing: Theme.Space.md))
                .listRowSeparator(.hidden)

            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        WorkoutRow(entry: entry)
                            .listRowBackground(Theme.card)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(Self.sectionTitle(for: section.day))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Self.dayTotalLabel(for: section.entries))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .tint(Theme.brand)
    }

    private var encouragementCard: some View {
        let count = todayCount
        let moved = count > 0
        return HStack(spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.brandSoft)
                    .frame(width: 38, height: 38)
                encouragementIcon(moved: moved)
            }
            Text(moved
                 ? "You moved today — that totally counts. Proud of you 💪"
                 : "Every little bit adds up. Even 10 minutes is a win 💚")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    /// A proud little pulse once she's moved today; a gentle wiggle inviting her to
    /// when she hasn't. Both degrade to still under Reduce Motion (via DelightKit).
    @ViewBuilder
    private func encouragementIcon(moved: Bool) -> some View {
        let icon = Image(systemName: moved ? "checkmark.seal.fill" : "figure.run")
            .font(.title3)
            .foregroundStyle(Theme.brand)
        if moved { icon.breathing() } else { icon.wiggle() }
    }

    /// Number of workouts logged today (drives the encouragement copy).
    private var todayCount: Int {
        workouts.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Space.lg) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 108, height: 108)
                    .breathing()
                Image(systemName: "figure.run")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .wiggle()
            }
            VStack(spacing: Theme.Space.xs) {
                Text("Let's get moving! 🏃")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("No workouts yet — even 10 minutes counts 💪")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A filled, springy primary CTA: the brand-gradient pill (matching
            // `.buttonStyle(.primary)`) plus a jelly squish on tap.
            Button {
                showingAdd = true
            } label: {
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

    // MARK: - Mutations

    private func delete(_ entry: WorkoutEntry) {
        deleteTick += 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            context.delete(entry)
            try? context.save()
        }
    }

    // MARK: - Formatting

    /// "Today" / "Yesterday" / a friendly date (e.g. "Mon, May 26" or with year if older).
    private static func sectionTitle(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = cal.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(
            sameYear
            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        )
    }

    /// "3 workouts · 75 min" style summary for a day's section header.
    private static func dayTotalLabel(for entries: [WorkoutEntry]) -> String {
        let minutes = entries.reduce(0) { $0 + $1.durationMinutes }
        let countPart = entries.count == 1 ? "1 workout" : "\(entries.count) workouts"
        return "\(countPart) · \(minutes) min"
    }
}

// MARK: - Row

/// A single workout row: activity icon, title, and a duration (+ optional kcal) footing.
private struct WorkoutRow: View {
    let entry: WorkoutEntry

    @State private var appeared = false

    /// A row is "fresh" if it was logged within the last few seconds, so the
    /// just-added workout springs in while existing/historical rows don't.
    private var isFresh: Bool { Date.now.timeIntervalSince(entry.createdAt) < 3 }
    private var popActive: Bool { isFresh ? appeared : true }

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: entry.type.systemImage)
                .font(.headline)
                .foregroundStyle(Theme.brand)
                .frame(width: 38, height: 38)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? entry.type.label : entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Theme.Space.xs) {
                    Label("\(entry.durationMinutes) min", systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                    if let focus = entry.focus {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(focus.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                    }
                    if let kcal = entry.caloriesBurned, kcal > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Label("\(Int(kcal.rounded())) kcal", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(Theme.calories)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Rectangle())
        // The freshly-logged workout springs in for a satisfying "logged it!" beat.
        .popIn(popActive)
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [entry.title.isEmpty ? entry.type.label : entry.title,
                     "\(entry.durationMinutes) minutes"]
        if let kcal = entry.caloriesBurned, kcal > 0 {
            parts.append("\(Int(kcal.rounded())) calories")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Add sheet

/// Low-friction "what did you do + how long" capture. Title is optional (defaults
/// to the activity label) and calories are optional too — most people don't know
/// them, and we never make the user feel they have to.
private struct AddWorkoutSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var type: WorkoutType = .strength
    @State private var focus: WorkoutFocus = .push
    @State private var title = ""
    @State private var durationMinutes = 30
    @State private var caloriesText = ""
    @State private var notes = ""
    @State private var didSave = false

    /// Friendly preset durations in minutes — 10 leads, because 10 counts.
    private let durations: [Int] = [10, 15, 20, 30, 45, 60, 75, 90, 120]

    private var caloriesValue: Double? {
        let trimmed = caloriesText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let v = Double(trimmed), v > 0 else { return nil }
        return v
    }

    /// True for run/cardio efforts where a dedicated tracker (pace, distance, routes)
    /// genuinely adds something we don't capture — drives the `RunningAppCard` nudge.
    /// Deliberately excludes `.walk` (the app's "10 minutes counts" base case) and
    /// non-cardio types so the suggestion only appears when it's actually useful.
    private var isRunOrCardio: Bool {
        switch type {
        case .run, .cardio, .cycle, .hiit: return true
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you do?") {
                    Picker("Activity", selection: $type) {
                        ForEach(WorkoutType.allCases) { t in
                            Label(t.label, systemImage: t.systemImage).tag(t)
                        }
                    }
                    TextField(type.label, text: $title)
                        .textInputAutocapitalization(.sentences)
                    // The "type of day" — only for strength/gym sessions.
                    if type == .strength {
                        Picker("Focus", selection: $focus) {
                            ForEach(WorkoutFocus.allCases) { f in
                                Text(f.label).tag(f)
                            }
                        }
                    }
                }

                // A right-moment nudge: only while logging a run/cardio effort, suggest
                // tracking it in Strava (we don't track pace/distance/routes). Dismissed
                // forever once she taps its "x" (sticky via @AppStorage inside the card).
                if isRunOrCardio {
                    Section {
                        RunningAppCard()
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                    .animation(.easeInOut, value: type)
                }

                Section("How long?") {
                    Picker("Duration", selection: $durationMinutes) {
                        ForEach(durations, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section {
                    HStack {
                        Label("Calories", systemImage: "flame.fill")
                            .foregroundStyle(Theme.calories)
                        Spacer()
                        TextField("Optional", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text("kcal")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } footer: {
                    Text("Calories are optional — log them only if you know them.")
                }

                Section {
                    TextField("Exercises, sets, weights — e.g. Bench 3×8 @ 135", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Jot what you did — Vita reads this to understand your training.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add workout")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.brand)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.success, trigger: didSave)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // `WorkoutEntry.init` falls back to `type.label` when the title is empty,
        // so an untitled entry still reads nicely.
        let entry = WorkoutEntry(
            type: type,
            title: trimmedTitle,
            durationMinutes: durationMinutes,
            caloriesBurned: caloriesValue,
            focus: type == .strength ? focus : nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        context.insert(entry)
        try? context.save()
        didSave = true
        dismiss()
    }
}
