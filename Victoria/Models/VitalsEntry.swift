import Foundation
import SwiftData

/// One day's recovery vitals, mirrored from Apple Health (a tracker like the Fitbit Air
/// measures these continuously; we keep the DAILY value — resting HR and HRV are only
/// meaningful as daily/overnight aggregates anyway, so nothing is lost vs "raw").
///
/// Passive data, same contract as `StepsEntry`/`SleepEntry`: never counts toward the
/// logging streak; context for the coach and (later) trend charts.
@Model
final class VitalsEntry {
    var id: UUID = UUID()
    var date: Date = Date.now          // start of day
    /// Resting heart rate in bpm (0 = not reported that day).
    var restingHeartRate: Double = 0
    /// Heart-rate variability (SDNN) in milliseconds (0 = not reported that day).
    var hrvMs: Double = 0
    var createdAt: Date = Date.now

    init(date: Date = .now, restingHeartRate: Double = 0, hrvMs: Double = 0) {
        self.id = UUID()
        self.date = date
        self.restingHeartRate = restingHeartRate
        self.hrvMs = hrvMs
        self.createdAt = .now
    }
}
