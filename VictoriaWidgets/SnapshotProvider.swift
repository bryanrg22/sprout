import WidgetKit
import SwiftUI

/// One timeline entry carrying the shared snapshot.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

/// Shared timeline provider — both widgets read the same snapshot the app writes
/// to the App Group. The app calls `WidgetCenter.reloadAllTimelines()` on changes;
/// we also self-refresh every 30 min as a safety net (e.g. for the date rolling over).
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snap: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = context.isPreview ? .placeholder : WidgetSharedStore.load()
        completion(SnapshotEntry(date: .now, snap: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snap: WidgetSharedStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
