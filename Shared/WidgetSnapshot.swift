import Foundation

/// A small, Codable summary the app writes to the shared App Group so widgets can
/// render instantly without opening SwiftData. Holds exactly what the glance
/// widgets need — nothing more.
///
/// Shared by BOTH the app target (writes) and the widget extension (reads).
struct WidgetSnapshot: Codable {
    var updated: Date
    var name: String

    // Appearance — so the widget (a SEPARATE process that never runs RootView, and
    // whose `Theme.current` therefore stays at its `.cool` default) can render in the
    // user's actual skin + show the right pixel companion. Defaulted for back-compat:
    // a snapshot written before these fields existed still decodes (see init(from:)).
    var themeStyleRaw: String = ThemeStyle.cute.rawValue        // "cute" | "cool"
    var companionAvatarRaw: String = "victoria"                  // "victoria" | "bryan"

    // Calories
    var calorieTarget: Double        // the FLOOR / target (includes step bonus when steps-adjust is on)
    var calorieMax: Double = 0       // soft CEILING — top of her range; 0 = single-number (gain) goal / pre-range snapshot
    var caloriesEaten: Double
    var stepBonus: Double

    // Macros — eaten vs target (grams)
    var protein: Double;  var proteinTarget: Double
    var carbs: Double;    var carbsTarget: Double
    var fat: Double;      var fatTarget: Double

    // Activity
    var steps: Int;       var stepGoal: Int
    var waterOz: Double;  var waterGoalOz: Double

    // Weight
    var trendWeight: Double?         // smoothed trend (nil if no weigh-ins)
    var ratePerWeek: Double          // negative = losing
    var goalWeight: Double
    var trendSpark: [Double]         // recent smoothed points for a sparkline

    // Streak
    var streak: Int

    // MARK: Derived

    /// The palette the widget should paint with (the user's chosen skin). Falls back
    /// to `.cute` — the app's default — if the stored value is unknown.
    var skin: ThemeSkin { (ThemeStyle(rawValue: themeStyleRaw) ?? .cute).skin }
    /// True when this profile's solo companion is pixel-Bryan rather than Victoria.
    var usesBryanAvatar: Bool { companionAvatarRaw == "bryan" }

    var caloriesRemaining: Double { calorieTarget - caloriesEaten }
    /// A real calorie RANGE is available (0 = single-number gain goal / pre-range snapshot).
    var hasCalorieRange: Bool { calorieMax > calorieTarget }
    /// "Over" only once past the soft CEILING — never the instant she crosses the floor into her
    /// range. No range → never over (kind default, matching the in-app anti-restriction framing).
    var calorieOver: Bool { hasCalorieRange && caloriesEaten > calorieMax }
    var calorieProgress: Double { calorieTarget > 0 ? min(caloriesEaten / calorieTarget, 1) : 0 }
    var stepProgress: Double { stepGoal > 0 ? min(Double(steps) / Double(stepGoal), 1) : 0 }
    var waterProgress: Double { waterGoalOz > 0 ? min(waterOz / waterGoalOz, 1) : 0 }
    var poundsToGoal: Double? { trendWeight.map { max(0, $0 - goalWeight) } }
    var isLosing: Bool { ratePerWeek <= 0 }

    /// Friendly sample used for the gallery / placeholder rendering.
    static let placeholder = WidgetSnapshot(
        updated: .now, name: "Victoria",
        themeStyleRaw: ThemeStyle.cute.rawValue, companionAvatarRaw: "victoria",
        calorieTarget: 1740, calorieMax: 1900, caloriesEaten: 1355, stepBonus: 0,
        protein: 98, proteinTarget: 126,
        carbs: 132, carbsTarget: 184,
        fat: 45, fatTarget: 56,
        steps: 9243, stepGoal: 8000,
        waterOz: 36, waterGoalOz: 79,
        trendWeight: 153.8, ratePerWeek: -1.2, goalWeight: 140,
        trendSpark: [158, 157.5, 157.1, 156.4, 156.0, 155.4, 155.0,
                     154.7, 154.3, 154.1, 153.9, 153.8, 153.8, 153.7],
        streak: 28)
}

// MARK: - Back-compatible decoding
//
// Swift's *synthesized* `init(from:)` throws `keyNotFound` for a missing key even
// when the property has a default — so a snapshot written before `themeStyleRaw` /
// `companionAvatarRaw` existed would fail to decode. We supply a hand-written
// decoder that reads those two via `decodeIfPresent` (falling back to the app's
// defaults) and every other field normally. Putting it in an EXTENSION keeps the
// compiler-synthesized memberwise initializer (used by `placeholder` + the writer).
extension WidgetSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updated = try c.decode(Date.self, forKey: .updated)
        name    = try c.decode(String.self, forKey: .name)
        themeStyleRaw     = try c.decodeIfPresent(String.self, forKey: .themeStyleRaw) ?? ThemeStyle.cute.rawValue
        companionAvatarRaw = try c.decodeIfPresent(String.self, forKey: .companionAvatarRaw) ?? "victoria"
        calorieTarget = try c.decode(Double.self, forKey: .calorieTarget)
        calorieMax    = try c.decodeIfPresent(Double.self, forKey: .calorieMax) ?? 0
        caloriesEaten = try c.decode(Double.self, forKey: .caloriesEaten)
        stepBonus     = try c.decode(Double.self, forKey: .stepBonus)
        protein       = try c.decode(Double.self, forKey: .protein)
        proteinTarget = try c.decode(Double.self, forKey: .proteinTarget)
        carbs         = try c.decode(Double.self, forKey: .carbs)
        carbsTarget   = try c.decode(Double.self, forKey: .carbsTarget)
        fat           = try c.decode(Double.self, forKey: .fat)
        fatTarget     = try c.decode(Double.self, forKey: .fatTarget)
        steps         = try c.decode(Int.self, forKey: .steps)
        stepGoal      = try c.decode(Int.self, forKey: .stepGoal)
        waterOz       = try c.decode(Double.self, forKey: .waterOz)
        waterGoalOz   = try c.decode(Double.self, forKey: .waterGoalOz)
        trendWeight   = try c.decodeIfPresent(Double.self, forKey: .trendWeight)
        ratePerWeek   = try c.decode(Double.self, forKey: .ratePerWeek)
        goalWeight    = try c.decode(Double.self, forKey: .goalWeight)
        trendSpark    = try c.decode([Double].self, forKey: .trendSpark)
        streak        = try c.decode(Int.self, forKey: .streak)
    }
}

/// Read/write the snapshot through the shared App Group. Reads fall back to the
/// placeholder so a freshly-installed widget never looks broken.
enum WidgetSharedStore {
    static let appGroup = "group.com.bryanram.victoria"
    static let key = "widget_snapshot_v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return snap
    }

    static func save(_ snap: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        defaults?.set(data, forKey: key)
    }

    /// True when the shared container is actually reachable (for diagnostics).
    static var isAvailable: Bool { defaults != nil }
}
