import Foundation

/// Response-level cache for the plan's WEB RESEARCH pass — the same "don't pay twice
/// for the same answer" doctrine as prompt caching, one level up. The evidence base
/// for "sustainable loss toward ~140 lb" doesn't change week to week, so a fresh
/// build within the TTL reuses the stored brief instead of re-running a live
/// web-search synthesis (the single most expensive call in the app).
///
/// Keying: goal direction + a 10-lb goal-weight band — close-enough goals share an
/// evidence base; a direction flip or a big goal move naturally misses and triggers
/// real research. TTL 30 days keeps the science current without being wasteful.
enum ResearchCache {

    struct Entry: Codable {
        let text: String
        let savedAt: Date
    }

    static let ttlDays = 30
    private static let prefix = "researchCache."

    /// Cache key for a goal. Pure and unit-tested.
    static func key(direction: GoalPace.Direction, goalWeightLbs: Double) -> String {
        let dir: String
        switch direction {
        case .lose:     dir = "lose"
        case .gain:     dir = "gain"
        case .maintain: dir = "maintain"
        }
        return "\(prefix)\(dir).band\(Int((max(0, goalWeightLbs) / 10).rounded(.down)))"
    }

    /// The stored brief for this key, if it's still fresh; nil on miss or expiry.
    static func lookup(key: String, now: Date = .now,
                       defaults: UserDefaults = .standard) -> String? {
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        let age = Calendar.current.dateComponents([.day], from: entry.savedAt, to: now).day ?? .max
        guard age <= ttlDays else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return entry.text
    }

    static func store(_ text: String, key: String, now: Date = .now,
                      defaults: UserDefaults = .standard) {
        guard !text.isEmpty,
              let data = try? JSONEncoder().encode(Entry(text: text, savedAt: now)) else { return }
        defaults.set(data, forKey: key)
    }
}
