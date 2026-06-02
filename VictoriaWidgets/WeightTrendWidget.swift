import WidgetKit
import SwiftUI

/// "Weight Trend" — the smoothed trend (never the noisy daily number) at a glance.
/// Home (small) only.
struct WeightTrendWidget: Widget {
    let kind = "WeightTrendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            WeightTrendEntryView(entry: entry)
        }
        .configurationDisplayName("Weight Trend")
        .description("Your smoothed weight trend and weekly rate.")
        .supportedFamilies([.systemSmall])
    }
}

private struct WeightTrendEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        // Adopt the user's skin before any Theme color resolves (see CalorieBudgetWidget).
        Theme.current = entry.snap.skin
        return WeightTrendView(snap: entry.snap, family: family)
            .containerBackground(Theme.widgetBackground, for: .widget)
            .environment(\.colorScheme, entry.snap.skin.colorScheme)
    }
}
