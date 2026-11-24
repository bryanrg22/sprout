import Foundation
import SwiftData

/// One day's step total (mirrored from Apple Health, or seeded for demos).
/// Stored per day so the dashboard can show today and we can chart history.
@Model
final class StepsEntry {
    var id: UUID = UUID()
    var date: Date = Date.now      // start of day
    var count: Int = 0
    var createdAt: Date = Date.now

    init(date: Date = .now, count: Int) {
        self.id = UUID()
        self.date = date
        self.count = count
        self.createdAt = .now
    }
}
