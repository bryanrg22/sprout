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
    @Query private var profiles: [UserProfile]
    @Environment(AskVitaCenter.self) private var askVita: AskVitaCenter?

    private var coachName: String { profiles.first?.coachName ?? "Vita" }

    @State private var showLogFlow = false
    /// Bumped on delete for a soft haptic.
    @State private var deleteTick = 0

    /// The day being viewed — drives the date-stepper, mirroring the Nutrients page so a long
    /// history never becomes an endlessly-scrolling list. Browse with the chevrons or jump via the
    /// date picker.
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var showDatePicker = false
    @State private var navTick = 0
    /// Held false until the Workouts screen settles, then true — gates the empty-state hero's idle
    /// so the dumbbell never animates IN from a mid-transition spot on first open (just then sways).
    @State private var heroSettled = false

    /// Exercises for one session, in insertion order (by their own ascending nothing — stable on
    /// the array). Keyed lookup keeps the per-row cost tiny.
    private func exercises(for session: WorkoutSession) -> [ExerciseEntry] {
        exercises.filter { $0.sessionID == session.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    // "This week" sits at the very top — right under the title, above the day stepper.
                    weeklyStatsCard
                    dayNav
                    // Logging lives on the "today" view; past days are read-only history.
                    if isViewingToday {
                        logCTA
                    }
                    dayContent
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .accessibilityIdentifier(AccessibilityID.Workouts.root)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) { ModeSwitch() }
                ToolbarItem(placement: .primaryAction) { addButton }
            }
            .sheet(isPresented: $showLogFlow) {
                // Logging from a past day back-dates the session to that day (noon), so a workout
                // you forgot can be added later; today logs at "now".
                WorkoutLogFlow(logDate: isViewingToday ? nil
                               : cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDay))
            }
            .sheet(isPresented: $showDatePicker) { dayPickerSheet }
            .sensoryFeedback(.impact(weight: .light), trigger: deleteTick)
            .sensoryFeedback(.selection, trigger: navTick)
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

    // MARK: Day navigation (mirrors the Nutrients page — one day at a time, steppable)

    private var cal: Calendar { Calendar.current }
    private var startOfToday: Date { cal.startOfDay(for: .now) }
    private var isViewingToday: Bool { cal.isDateInToday(selectedDay) }
    private var canGoForward: Bool { selectedDay < startOfToday }
    /// The day the account began — no data exists before it, so don't browse earlier (mirrors Nutrients).
    private var accountStart: Date { min(cal.startOfDay(for: profiles.first?.createdAt ?? startOfToday), startOfToday) }
    private var canGoBack: Bool { selectedDay > accountStart }

    private var dayLabel: String {
        if cal.isDateInToday(selectedDay) { return "Today" }
        if cal.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(.dateTime.weekday(.wide))
    }

    private func step(_ days: Int) {
        let next = cal.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
        let clamped = min(max(cal.startOfDay(for: next), accountStart), startOfToday)
        navTick += 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { selectedDay = clamped }
    }

    /// The sessions logged on the selected day.
    private var daySessions: [WorkoutSession] {
        sessions.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }
    }

    private var dayNav: some View {
        HStack(spacing: Theme.Space.sm) {
            navChevron("chevron.left", enabled: canGoBack) { step(-1) }
                .accessibilityLabel("Previous day")

            Button {
                navTick += 1
                showDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.brand)
                    VStack(spacing: 1) {
                        Text(dayLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        if !isViewingToday {
                            Text(selectedDay.formatted(.dateTime.year().month().day()))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.brandSoft, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Selected day, \(dayLabel). Tap to pick a day.")

            navChevron("chevron.right", enabled: canGoForward) { step(1) }
                .accessibilityLabel("Next day")
        }
        .padding(.top, Theme.Space.xs)
    }

    private func navChevron(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? Theme.brand : Theme.textSecondary.opacity(0.35))
                .frame(width: 44, height: 44)
                .background(Circle().fill(enabled ? Theme.brandSoft : Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var dayPickerSheet: some View {
        NavigationStack {
            DatePicker("Jump to a day",
                       selection: Binding(get: { selectedDay },
                                          set: { selectedDay = min(max(cal.startOfDay(for: $0), accountStart), startOfToday) }),
                       in: accountStart...startOfToday, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.brand)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Pick a day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDatePicker = false }.foregroundStyle(Theme.brand)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Day content (the selected day's sessions, or an empty state)

    @ViewBuilder
    private var dayContent: some View {
        if daySessions.isEmpty && isViewingToday {
            todayEmptyState
        } else if daySessions.isEmpty {
            pastDayEmptyState
        } else {
            ForEach(daySessions) { session in
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
    }

    // MARK: Weekly stats

    /// A compact "this week" card — workouts · volume · minutes — the at-a-glance stats the bare
    /// list was missing. Sums the trailing 7 days; only shown once there's at least one session
    /// this week (the empty state has its own hero).
    @ViewBuilder
    private var weeklyStatsCard: some View {
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) ?? .now
        let weekSessions = sessions.filter { $0.date >= weekStart }
        let totalVolume = weekSessions.reduce(0.0) { $0 + WorkoutStats(session: $1, exercises: exercises(for: $1)).volumeLbs }
        let totalMinutes = weekSessions.reduce(0) { $0 + $1.durationMinutes }
        if !weekSessions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("This week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 0) {
                    statColumn("\(weekSessions.count)", weekSessions.count == 1 ? "workout" : "workouts")
                    statDivider
                    statColumn(totalVolume > 0 ? WorkoutStats.grouped(totalVolume) : "—", "lb lifted")
                    statDivider
                    statColumn("\(totalMinutes)", "min")
                }
                Divider().background(Theme.divider)
                weekBars
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardElevated()
        }
    }

    /// A 7-day mini bar chart of training minutes — the week's rhythm at a glance (today's label
    /// highlighted, rest days a faint stub). Gives the page a real metric/visual, not dead space.
    private var weekBars: some View {
        let days = weekDays
        let maxMin = max(1, days.map(\.minutes).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(day.minutes > 0 ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.divider))
                        .frame(height: max(5, CGFloat(Double(day.minutes) / Double(maxMin)) * 44))
                    Text(dayInitial(day.date))
                        .font(.system(size: 9, weight: cal.isDateInToday(day.date) ? .bold : .regular))
                        .foregroundStyle(cal.isDateInToday(day.date) ? Theme.brand : Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 60, alignment: .bottom)
        .padding(.top, 2)
    }

    /// Trailing 7 days (oldest → today) with each day's total training minutes.
    private var weekDays: [(date: Date, minutes: Int)] {
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let mins = sessions.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.durationMinutes }
            return (date: day, minutes: mins)
        }
    }

    private func dayInitial(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private func statColumn(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold)).monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1, height: 28)
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
        .accessibilityIdentifier(AccessibilityID.Workouts.log)
    }

    // MARK: Empty states

    /// Today has no workout yet — the warm hero (the `logCTA` above it is the action). Top-aligned
    /// in-flow under the day nav, not full-screen, so it sits naturally below the stepper.
    private var todayEmptyState: some View {
        VStack(spacing: Theme.Space.md) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 108, height: 108)
                    .breathing(heroSettled)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .wiggle(heroSettled)
            }
            .frame(width: 120, height: 120)   // stable bounds so the pulse/wiggle never reflow the column
            // Hold the idle until the screen has SETTLED, so the dumbbell never animates IN from a
            // mid-transition spot when you first open Workouts — it just sits, then gently comes alive.
            .task { try? await Task.sleep(for: .seconds(0.45)); heroSettled = true }
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
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.xl)
    }

    /// A past day with nothing logged — a friendly CARD (matching the Nutrients empty state) that
    /// recognizes you might have just forgotten, and offers to add it for THIS day (back-dated) or
    /// ask the coach to help.
    private var pastDayEmptyState: some View {
        VStack(spacing: Theme.Space.md) {
            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 76, height: 76)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.brand)
            }
            VStack(spacing: Theme.Space.xs) {
                Text("A quiet day here 🌙")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Nothing logged. Forgot a workout? Add it for this day, or ask \(coachName) to help.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Space.sm) {
                Button { showLogFlow = true } label: {
                    Label("Add a workout", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button { askToAddPast() } label: {
                    Label("Ask \(coachName)", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(Theme.brand)
                }
                .buttonStyle(.plain)
                .disabled(askVita == nil)
            }
        }
        .frame(maxWidth: .infinity)
        .cardElevated()
    }

    /// Deep-link the coach to help back-fill a forgotten workout for the day being viewed.
    private func askToAddPast() {
        askVita?.ask(AskVitaTopic(
            name: "Add a past workout",
            icon: "dumbbell.fill",
            value: dayLabel,
            question: "I forgot to log my workout on \(selectedDay.formatted(.dateTime.weekday(.wide).month().day())). Can you help me add it for that day? Ask me what I did, then log it."))
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
        .accessibilityIdentifier(AccessibilityID.Workouts.sessionRow)
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
    /// When nothing concrete was logged (just opened a gym session, or cardio with no duration),
    /// reads "Showed up" — still counts. NOT the kind label, which the title already shows (that
    /// duplicated to "Gym · Gym" / "Run · Run").
    static func summary(for session: WorkoutSession, exerciseCount: Int) -> String {
        var parts: [String] = []
        if session.durationMinutes > 0 { parts.append("\(session.durationMinutes) min") }
        if exerciseCount > 0 {
            parts.append(exerciseCount == 1 ? "1 machine" : "\(exerciseCount) machines")
        }
        return parts.isEmpty ? "Showed up" : parts.joined(separator: " · ")
    }
}

// MARK: - Aggregate stats

/// Pure aggregate stats for a session, computed from its exercise rows — the personalized numbers
/// the detail page and the weekly summary surface. **Volume** is the classic gym metric: total
/// weight moved = Σ (weight × reps × sets), which actually reflects the work done.
struct WorkoutStats {
    var volumeLbs: Double = 0
    var sets: Int = 0
    var reps: Int = 0            // total reps performed = Σ reps × sets
    var exercises: Int = 0
    var durationMinutes: Int = 0

    init(session: WorkoutSession, exercises rows: [ExerciseEntry]) {
        exercises = rows.count
        durationMinutes = session.durationMinutes
        for e in rows {
            volumeLbs += e.weightLbs * Double(e.reps) * Double(e.sets)
            sets += e.sets
            reps += e.reps * e.sets
        }
    }

    private enum Headline { case volume, sets, duration, showedUp }
    private var headlineKind: Headline {
        if volumeLbs > 0 { return .volume }
        if sets > 0 { return .sets }
        if durationMinutes > 0 { return .duration }
        return .showedUp
    }

    /// The big hero number + its unit, adaptive to what was actually logged:
    ///  • weights → total VOLUME ("12,400" · "lb lifted") — the real, personalized gym stat;
    ///  • bodyweight-only → SETS ("15" · "sets"); • cardio → DURATION ("45" · "min");
    ///  • nothing logged → a friendly "✓ · Showed up".
    var headline: (value: String, unit: String) {
        switch headlineKind {
        case .volume:   return (Self.grouped(volumeLbs), "lb lifted")
        case .sets:     return ("\(sets)", sets == 1 ? "set" : "sets")
        case .duration: return ("\(durationMinutes)", "min")
        case .showedUp: return ("✓", "Showed up")
        }
    }

    /// The supporting line under the hero — the parts that AREN'T already the headline.
    var secondary: String {
        var parts: [String] = []
        if exercises > 0 { parts.append(exercises == 1 ? "1 exercise" : "\(exercises) exercises") }
        if headlineKind == .volume, sets > 0 { parts.append("\(sets) sets") }
        if headlineKind != .duration, durationMinutes > 0 { parts.append("\(durationMinutes) min") }
        return parts.joined(separator: " · ")
    }

    /// Compact grouped integer, e.g. 12400 → "12,400".
    static func grouped(_ v: Double) -> String {
        formatter.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
}

#Preview {
    WorkoutsView()
        .modelContainer(for: [WorkoutSession.self, ExerciseEntry.self], inMemory: true)
}
