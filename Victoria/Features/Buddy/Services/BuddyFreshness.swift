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

    static func evaluate(lastPublished: Date?, now: Date, calendar: Calendar) -> BuddyFreshness {
        .current
    }
}
