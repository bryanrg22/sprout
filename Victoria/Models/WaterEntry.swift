import Foundation
import SwiftData

/// A single water intake event (logged in fluid ounces). Aggregated per day on the dashboard.
@Model
final class WaterEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var amountOz: Double = 0
    var createdAt: Date = Date.now

    init(date: Date = .now, amountOz: Double) {
        self.id = UUID()
        self.date = date
        self.amountOz = amountOz
        self.createdAt = .now
    }
}
