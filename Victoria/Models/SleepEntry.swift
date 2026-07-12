import Foundation
import SwiftData

/// One night's sleep, mirrored from Apple Health (which a Fitbit/tracker feeds via the
/// Fitbit→Health bridge, or Google Health's native sync once that ships).
///
/// `date` is the start-of-day of the morning she WOKE UP — "last night" for that day —
/// so today's row answers "how did she sleep?" the way a person means it.
///
/// Passive data, same contract as `StepsEntry`: it never counts toward the logging
/// streak (see `StreakCalculator`), it's just context the coach and charts can use.
@Model
final class SleepEntry {
    var id: UUID = UUID()
    var date: Date = Date.now        // start-of-day of the wake morning
    /// Minutes actually asleep (sleep stages summed; when a source reports only
    /// "in bed", this falls back to that so old-style sources still show something).
    var asleepMinutes: Int = 0
    /// Minutes in bed (0 when the source doesn't report it).
    var inBedMinutes: Int = 0
    // Stage breakdown (all 0 when the source reports only totals). A stage-capable
    // tracker (Fitbit Air etc.) gives the full picture: deep + REM + core ≈ asleep.
    var deepMinutes: Int = 0
    var remMinutes: Int = 0
    var coreMinutes: Int = 0
    /// Minutes awake DURING the sleep session (restlessness), not time before bed.
    var awakeMinutes: Int = 0
    var createdAt: Date = Date.now

    init(date: Date = .now,
         asleepMinutes: Int,
         inBedMinutes: Int = 0,
         deepMinutes: Int = 0,
         remMinutes: Int = 0,
         coreMinutes: Int = 0,
         awakeMinutes: Int = 0) {
        self.id = UUID()
        self.date = date
        self.asleepMinutes = asleepMinutes
        self.inBedMinutes = inBedMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.createdAt = .now
    }

    /// True when the source reported a real stage breakdown (not just totals).
    var hasStages: Bool { deepMinutes > 0 || remMinutes > 0 || coreMinutes > 0 }
}
