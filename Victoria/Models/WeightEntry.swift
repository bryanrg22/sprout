import Foundation
import SwiftData

/// A single weigh-in. Daily readings are noisy (water, glycogen, gut contents swing
/// ±2–4 lb), so the app never treats one of these as "the truth" — it feeds them into
/// the smoothed trend (see `TrendCalculator`).
@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var weightLbs: Double = 0
    var note: String?
    /// "manual" or "healthkit" — used to avoid HealthKit echo/duplicates.
    var source: String = "manual"
    var healthKitUUID: String?
    var createdAt: Date = Date.now

    init(date: Date = .now,
         weightLbs: Double,
         note: String? = nil,
         source: String = "manual",
         healthKitUUID: String? = nil) {
        self.id = UUID()
        self.date = date
        self.weightLbs = weightLbs
        self.note = note
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.createdAt = .now
    }
}
