import Foundation
import SwiftData

/// A workout AUTO-DETECTED by a tracker (Fitbit etc.) and mirrored from Apple Health —
/// distinct from `WorkoutSession`, which is what the user logs by hand in the Workouts tab.
///
/// Kept separate on purpose: detected workouts are passive data (they never count toward
/// the logging streak, and they don't appear as hand-logged sessions she'd then feel she
/// has to curate). They give the coach the "you moved today even though you logged
/// nothing" picture. Deduped by the HealthKit sample UUID.
@Model
final class DetectedWorkout {
    var id: UUID = UUID()
    /// HealthKit sample UUID — the dedup key across imports.
    var healthKitUUID: String = ""
    var date: Date = Date.now        // workout start time
    /// Human-readable activity ("Running", "Walking", "Strength training", …).
    var activity: String = ""
    var durationMinutes: Int = 0
    /// Active energy for the workout (0 when the source doesn't report it).
    var caloriesBurned: Double = 0
    /// The reporting app/device ("Fitbit", "Sync Solver", …) — shown so it's clear
    /// where a detected session came from.
    var sourceName: String = ""
    var createdAt: Date = Date.now

    init(healthKitUUID: String,
         date: Date,
         activity: String,
         durationMinutes: Int,
         caloriesBurned: Double = 0,
         sourceName: String = "") {
        self.id = UUID()
        self.healthKitUUID = healthKitUUID
        self.date = date
        self.activity = activity
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.sourceName = sourceName
        self.createdAt = .now
    }
}
