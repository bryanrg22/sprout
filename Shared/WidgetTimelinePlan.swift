import Foundation
import WidgetKit

/// One timeline entry carrying the shared snapshot.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    /// The user's snapshot could not be read. The widget draws `WidgetUnavailableView`
    /// in this case; `snap` then holds no data, only the appearance to draw it in.
    var isUnavailable: Bool = false
}

/// What the widget shows and when it next asks again, as a function of what could be
/// read. Pure, so every case is tested without WidgetKit running.
enum WidgetTimelinePlan {

    /// How soon to ask again when the snapshot could not be read (the phone is usually
    /// unlocked within minutes of a restart).
    static let retryWhenUnavailable: TimeInterval = 5 * 60
    /// The routine safety-net refresh.
    static let routineRefresh: TimeInterval = 30 * 60

    static func entries(stored: WidgetSnapshot?, appearance: WidgetAppearance, now: Date,
                        calendar: Calendar = .current) -> (entries: [SnapshotEntry], reloadAfter: Date) {
        guard let stored else {
            let entry = SnapshotEntry(date: now, snap: .unavailable(appearance: appearance), isUnavailable: true)
            return ([entry], now.addingTimeInterval(retryWhenUnavailable))
        }
        var entries = [SnapshotEntry(date: now, snap: stored.asOf(now, calendar: calendar))]
        let reload = now.addingTimeInterval(routineRefresh)
        // If midnight falls before the next refresh, the day's numbers reset exactly then
        // instead of showing yesterday's totals into the new day.
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                            matchingPolicy: .nextTime),
           midnight < reload {
            entries.append(SnapshotEntry(date: midnight, snap: stored.asOf(midnight, calendar: calendar)))
        }
        return (entries, reload)
    }
}
