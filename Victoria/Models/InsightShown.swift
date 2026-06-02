import Foundation
import SwiftData

/// Records that a given daily insight was surfaced, so the engine can avoid
/// repeating the same line day after day (freshness = the difference between a
/// "wow" insight and wallpaper). One row per (insight id, day).
@Model
final class InsightShown {
    var insightID: String = ""
    var shownAt: Date = Date.now

    init(insightID: String, shownAt: Date = .now) {
        self.insightID = insightID
        self.shownAt = shownAt
    }
}
