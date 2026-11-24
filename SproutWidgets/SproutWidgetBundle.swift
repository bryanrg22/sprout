import WidgetKit
import SwiftUI

/// The widget extension's entry point. Home-screen widgets only — the lock-screen
/// accessory widgets were removed (they showed bare, context-thin numbers).
@main
struct SproutWidgetBundle: WidgetBundle {
    var body: some Widget {
        CompanionWidget()
        WeightTrendWidget()
    }
}
