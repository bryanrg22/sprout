import SwiftUI

/// One calendar week of activity, for the card at the top of Workouts: how many of its days
/// had any activity, and what each day held.
///
/// "Activity" is anything that says the person moved that day: a workout logged in the app,
/// or one Apple Health or the tracker detected. A day counts once however many it had. The
/// week follows the person's calendar (Sunday or Monday first), as the system's own
/// calendar views do.
struct ActivityWeek: Equatable {
    struct Day: Equatable, Identifiable {
        let date: Date
        /// Workouts logged in the app that day.
        var logged: Int
        /// Workouts detected by Apple Health or the tracker that day.
        var detected: Int
        /// Minutes of logged and detected workouts together.
        var minutes: Int
        /// After today: nothing can have happened yet.
        let isFuture: Bool
        let isToday: Bool

        var id: Date { date }
        var isActive: Bool { logged + detected > 0 }
    }

    /// The first day of the week, at midnight.
    let start: Date
    /// Seven days, in calendar order.
    let days: [Day]

    var activeDays: Int { days.filter(\.isActive).count }
    var containsToday: Bool { days.contains(where: \.isToday) }

    /// One workout as this card needs it: when it was and how long.
    struct Entry: Equatable {
        let date: Date
        let minutes: Int
    }

    /// The week containing `day`.
    static func containing(_ day: Date, logged: [Entry], detected: [Entry],
                           now: Date = .now, calendar: Calendar = .current) -> ActivityWeek {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        let days: [Day] = (0..<7).map { offset in
            // Added in days, not seconds, so a week across a clock change still has 7 midnights.
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let sameDay: (Entry) -> Bool = { calendar.isDate($0.date, inSameDayAs: date) }
            let l = logged.filter(sameDay)
            let d = detected.filter(sameDay)
            return Day(date: date, logged: l.count, detected: d.count,
                       minutes: (l + d).reduce(0) { $0 + max(0, $1.minutes) },
                       isFuture: date > today, isToday: date == today)
        }
        return ActivityWeek(start: start, days: days)
    }

    /// "Nov 17 – 23", or "Nov 30 – Dec 6" across a month.
    var rangeLabel: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        let calendar = Calendar.current
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let from = first.formatted(.dateTime.month(.abbreviated).day())
        let to = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(from) – \(to)"
    }

    /// What VoiceOver reads for one day.
    static func spokenLabel(for day: Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if day.isFuture { return "\(date), not yet" }
        guard day.isActive else { return "\(date), no activity" }
        var parts: [String] = []
        if day.logged > 0 { parts.append(day.logged == 1 ? "1 workout logged" : "\(day.logged) workouts logged") }
        if day.detected > 0 { parts.append(day.detected == 1 ? "1 tracked" : "\(day.detected) tracked") }
        if day.minutes > 0 { parts.append("\(day.minutes) minutes") }
        return "\(date), active: " + parts.joined(separator: ", ")
    }
}

/// The card: the week's range with arrows, "N of 7 days active", and seven tappable days.
struct ActivityWeekCard: View {
    let week: ActivityWeek
    /// The day the page is showing; its cell is marked.
    let selectedDay: Date
    /// One line under the days: the week's logged workouts, minutes and volume; nil hides it.
    let summary: String?
    let canGoBack: Bool
    let canGoForward: Bool
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onSelect: (Date) -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(week.containsToday ? "This week" : week.rangeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(week.activeDays)")
                            .font(.title.weight(.bold)).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("of 7 days active")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(week.activeDays) of 7 days active, \(week.rangeLabel)")
                    .accessibilityIdentifier(AccessibilityID.Workouts.weekActiveDays)
                }
                Spacer(minLength: 0)
                arrow("chevron.left", enabled: canGoBack, label: "Previous week", action: onPreviousWeek)
                    .accessibilityIdentifier(AccessibilityID.Workouts.weekPrevious)
                arrow("chevron.right", enabled: canGoForward, label: "Next week", action: onNextWeek)
                    .accessibilityIdentifier(AccessibilityID.Workouts.weekNext)
            }
            HStack(spacing: 4) {
                ForEach(week.days) { day in dayCell(day) }
            }
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier(AccessibilityID.Workouts.weekSummary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Workouts.week)
    }

    private func dayCell(_ day: ActivityWeek.Day) -> some View {
        let selected = calendar.isDate(day.date, inSameDayAs: selectedDay)
        return Button { onSelect(day.date) } label: {
            VStack(spacing: 6) {
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(day.isToday ? .bold : .regular))
                    .foregroundStyle(day.isToday ? Theme.brand : Theme.textSecondary)
                ZStack {
                    Circle()
                        .fill(day.isActive ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.divider.opacity(day.isFuture ? 0.4 : 1)))
                    if day.isActive {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Theme.brand, lineWidth: day.isToday && !day.isActive ? 2 : 0))
                Text(day.date.formatted(.dateTime.day()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(day.isFuture ? Theme.textSecondary.opacity(0.5) : Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(selected ? Theme.brandSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .accessibilityLabel(ActivityWeek.spokenLabel(for: day))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Workouts.weekDay(day.date))
    }

    private func arrow(_ name: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? Theme.brand : Theme.textSecondary.opacity(0.35))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
