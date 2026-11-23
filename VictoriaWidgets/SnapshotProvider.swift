import WidgetKit
import SwiftUI

/// Shared timeline provider — every widget reads the same snapshot the app writes
/// to the App Group. The app calls `WidgetCenter.reloadAllTimelines()` on changes.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snap: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // The gallery shows the user's own numbers when there are some, the sample otherwise.
        if context.isPreview {
            completion(SnapshotEntry(date: .now, snap: WidgetSharedStore.read()?.asOf(.now) ?? .placeholder))
        } else {
            completion(WidgetTimelinePlan.entries(stored: WidgetSharedStore.read(),
                                                  appearance: WidgetSharedStore.readAppearance(),
                                                  now: .now).entries[0])
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let plan = WidgetTimelinePlan.entries(stored: WidgetSharedStore.read(),
                                              appearance: WidgetSharedStore.readAppearance(),
                                              now: .now)
        completion(Timeline(entries: plan.entries, policy: .after(plan.reloadAfter)))
    }
}

/// Drawn when there is no snapshot to show. Says nothing about anyone.
struct WidgetUnavailableView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Open Sprout")
        case .accessoryCircular:
            Image(systemName: "leaf.fill").font(.title3)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Sprout").font(.headline)
                Text("Open the app to refresh").font(.caption2)
            }
        default:
            VStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.title2).foregroundStyle(Theme.textSecondary)
                Text("Open Sprout to refresh")
                    .font(.caption).multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
