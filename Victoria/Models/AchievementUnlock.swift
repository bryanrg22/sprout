import Foundation
import SwiftData

/// A record that a given achievement has been earned. The catalog of achievements
/// (ids, titles, rules) lives in code (see Features/Achievements); this only stores
/// WHICH ones are unlocked and when, so the grid can show earned vs locked.
@Model
final class AchievementUnlock {
    /// Stable identifier matching an entry in the achievement catalog.
    var achievementID: String = ""
    var unlockedAt: Date = Date.now

    init(achievementID: String, unlockedAt: Date = .now) {
        self.achievementID = achievementID
        self.unlockedAt = unlockedAt
    }
}
