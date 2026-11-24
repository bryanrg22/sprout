import Foundation

/// How old the buddy's last published day is, in whole calendar days.
enum BuddyFreshness: Equatable {
    /// Published today.
    case current
    /// Published `days` days ago: not today's data, but recent.
    case quiet(since: Date, days: Int)
    /// Nothing published for `days` days: shown as old, with the way out.
    case stale(since: Date, days: Int)
    /// Linked, and the buddy has never published.
    case neverPublished

    /// Old enough that the screen says so and offers to unpair.
    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    /// From this many days without a publish, the snapshot is shown as old. Two quiet days
    /// are a weekend away; a buddy who reinstalled never publishes under the old id again.
    static let staleAfterDays = 3

    /// - Parameters:
    ///   - lastPublished: the snapshot's `lastActive` (stamped by the buddy's phone at
    ///     publish), or nil when there is no snapshot.
    ///   - now, calendar: mine. Days are whole calendar days in my zone, so a snapshot from
    ///     23:59 yesterday is a day old two minutes later, and a snapshot stamped ahead of
    ///     my clock is simply current.
    static func evaluate(lastPublished: Date?, now: Date, calendar: Calendar) -> BuddyFreshness {
        guard let lastPublished else { return .neverPublished }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: lastPublished),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return .current }
        if days < staleAfterDays { return .quiet(since: lastPublished, days: days) }
        return .stale(since: lastPublished, days: days)
    }
}
