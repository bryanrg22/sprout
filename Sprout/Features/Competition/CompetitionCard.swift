import SwiftUI

/// The weekly competition, in the Buddy hub: this week's points for both people, a row of
/// days each, and last week's result. Tapping a day shows which targets it hit.
struct CompetitionCard: View {
    let mine: CompetitionRecord
    let theirs: CompetitionRecord
    let myName: String
    let buddyName: String
    var now: Date = .now

    @State private var detail: Detail?

    private struct Detail: Identifiable, Equatable {
        let who: String
        let date: Date
        let hits: CompetitionHits
        var id: String { who + CompetitionRecord.dayKey(date) }
    }

    private var cal: Calendar { CompetitionWeek.calendar() }
    private var thisWeek: Date { CompetitionWeek.start(of: now) }
    private var lastWeek: Date { cal.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek }
    private var thisKey: String { CompetitionRecord.dayKey(thisWeek, calendar: cal) }
    private var lastKey: String { CompetitionRecord.dayKey(lastWeek, calendar: cal) }

    /// Whether the buddy's app sends competition results at all (an older build does not).
    private var buddyTakesPart: Bool { theirs.days(forWeekStarting: thisKey) != nil || theirs.days(forWeekStarting: lastKey) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Label("This week's competition", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            Text("A point a day for each of your own targets: calories in range, protein, water, steps, and being active.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if buddyTakesPart {
                scoreLine
                row(name: myName, record: mine)
                row(name: buddyName, record: theirs)
                lastWeekLine
            } else {
                Text("Waiting for \(buddyName)'s app to update: the competition starts once both of you have this version.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier(AccessibilityID.Competition.waiting)
                row(name: myName, record: mine)
            }

            if let detail {
                detailView(detail)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .animation(.easeInOut(duration: 0.2), value: detail)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Competition.card)
    }

    private var scoreLine: some View {
        let me = mine.points(forWeekStarting: thisKey) ?? 0
        let them = theirs.points(forWeekStarting: thisKey) ?? 0
        let status: String = me == them ? "Tied" : (me > them ? "You're ahead" : "\(buddyName) is ahead")
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Text("\(me)")
                .font(.largeTitle.weight(.bold)).monospacedDigit()
                .foregroundStyle(me >= them ? Theme.brand : Theme.textPrimary)
            Text("–")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
            Text("\(them)")
                .font(.largeTitle.weight(.bold)).monospacedDigit()
                .foregroundStyle(them > me ? Theme.brand : Theme.textPrimary)
            Spacer(minLength: Theme.Space.sm)
            Text(status)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: you \(me) points, \(buddyName) \(them) points. \(status).")
        .accessibilityIdentifier(AccessibilityID.Competition.score)
    }

    private func row(name: String, record: CompetitionRecord) -> some View {
        let days = record.days(forWeekStarting: thisKey) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    let date = cal.date(byAdding: .day, value: index, to: thisWeek) ?? thisWeek
                    dayCell(date: date, hits: index < days.count ? days[index] : nil, who: name)
                }
            }
        }
    }

    private func dayCell(date: Date, hits: CompetitionHits?, who: String) -> some View {
        let points = hits?.points ?? 0
        return Button {
            guard let hits else { return }
            let next = Detail(who: who, date: date, hits: hits)
            detail = detail == next ? nil : next
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hits == nil ? AnyShapeStyle(Theme.divider.opacity(0.4))
                              : points == 0 ? AnyShapeStyle(Theme.divider)
                              : AnyShapeStyle(Theme.brand.opacity(0.25 + 0.15 * Double(points))))
                    Text(hits == nil ? "" : "\(points)")
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(points >= 3 ? Color.white : Theme.textPrimary)
                }
                .frame(height: 34)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(hits == nil)
        .accessibilityLabel(Self.spokenLabel(who: who, date: date, hits: hits))
    }

    private var lastWeekLine: some View {
        let me = mine.points(forWeekStarting: lastKey)
        let them = theirs.points(forWeekStarting: lastKey)
        let text: String
        if let me, let them {
            let result = me == them ? "a tie" : (me > them ? "you won" : "\(buddyName) won")
            text = "Last week: \(me) – \(them), \(result)."
        } else {
            text = "Last week: not enough data from both of you."
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier(AccessibilityID.Competition.lastWeek)
    }

    private func detailView(_ d: Detail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(d.who), \(d.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())): \(d.hits.points) of 5")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(CompetitionHits.all, id: \.rawValue) { target in
                Label(target.label, systemImage: d.hits.contains(target) ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(d.hits.contains(target) ? Theme.textPrimary : Theme.textSecondary)
            }
            if d.hits.isEmpty {
                Text("No food logged that day, so no points.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.brandSoft))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Competition.dayDetail)
    }

    static func spokenLabel(who: String, date: Date, hits: CompetitionHits?) -> String {
        let day = date.formatted(.dateTime.weekday(.wide))
        guard let hits else { return "\(who), \(day): not yet" }
        if hits.isEmpty { return "\(who), \(day): 0 points" }
        let names = CompetitionHits.all.filter { hits.contains($0) }.map { $0.label.lowercased() }
        return "\(who), \(day): \(hits.points) \(hits.points == 1 ? "point" : "points"), " + names.joined(separator: ", ")
    }
}
