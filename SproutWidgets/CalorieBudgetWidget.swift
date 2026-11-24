import WidgetKit
import SwiftUI

/// "Calories Left" — the calorie budget at a glance. Home (small/medium) + lock
/// screen (circular/rectangular/inline). Reads the shared snapshot the app writes.
struct CalorieBudgetWidget: Widget {
    let kind = "CalorieBudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            CalorieBudgetEntryView(entry: entry)
        }
        .configurationDisplayName("Calories Left")
        .description("Your calorie budget on your Lock Screen.")
        // Companion-forward lineup: the home calorie ring + macro card are dropped in favor of
        // the Companion widget (which already shows calories); calories stay as a Lock Screen
        // glance.
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct CalorieBudgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        // The widget runs in its OWN process where RootView never runs, so `Theme.current`
        // would otherwise stay at its `.cool` default. Adopt the user's skin (from the
        // snapshot) BEFORE any Theme color — incl. the container background — resolves.
        Theme.current = entry.snap.skin
        return Group {
                if entry.isUnavailable { WidgetUnavailableView(family: family) }
                else { CalorieBudgetView(snap: entry.snap, family: family) }
            }
            .containerBackground(Theme.background, for: .widget)
            .environment(\.colorScheme, entry.snap.skin.colorScheme)
    }
}
