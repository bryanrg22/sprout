import WidgetKit
import SwiftUI

/// "Companion" — the cute pixel buddy plus a key metric, so a glance at the home
/// screen feels like checking in on someone. Home only (small/medium); the buddy
/// art needs the room, so it skips the tiny lock-screen accessory families.
/// Reads the shared snapshot the app writes.
struct CompanionWidget: Widget {
    let kind = "CompanionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            CompanionEntryView(entry: entry)
        }
        .configurationDisplayName("Companion")
        .description("Your pixel buddy plus today's key numbers.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct CompanionEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        // Adopt the user's skin before any Theme color resolves (see CalorieBudgetWidget).
        Theme.current = entry.snap.skin
        return Group {
                if entry.isUnavailable { WidgetUnavailableView(family: family) }
                else { CompanionView(snap: entry.snap, family: family) }
            }
            .containerBackground(Theme.widgetBackground, for: .widget)
            .environment(\.colorScheme, entry.snap.skin.colorScheme)
    }
}
