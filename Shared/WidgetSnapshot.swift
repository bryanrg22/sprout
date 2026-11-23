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

    /// This snapshot as it should read at `now`. The numbers that belong to one day
    /// (eaten, macros, steps, water, the step bonus inside the calorie target) are only
    /// true on the day the app wrote them; on a later day they are zero until the app
    /// writes again. Targets, the weight trend and the streak carry over.
    func asOf(_ now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        guard !calendar.isDate(updated, inSameDayAs: now), updated < now else { return self }
        var next = self
        next.calorieTarget = max(0, calorieTarget - stepBonus)
        if calorieMax > 0 { next.calorieMax = max(0, calorieMax - stepBonus) }
        next.stepBonus = 0
        next.caloriesEaten = 0
        next.protein = 0
        next.carbs = 0
        next.fat = 0
        next.steps = 0
        next.waterOz = 0
        return next
    }

    /// What a widget shows when it cannot read the user's snapshot (the app has never
    /// written one, or the phone restarted and has not been unlocked yet): nothing about
    /// anyone. Rendered through `WidgetUnavailableView`, never through the data views.
    static func unavailable(appearance: WidgetAppearance) -> WidgetSnapshot {
        WidgetSnapshot(
            updated: .distantPast, name: "",
            themeStyleRaw: appearance.themeStyleRaw, companionAvatarRaw: appearance.companionAvatarRaw,
            calorieTarget: 0, calorieMax: 0, caloriesEaten: 0, stepBonus: 0,
            protein: 0, proteinTarget: 0, carbs: 0, carbsTarget: 0, fat: 0, fatTarget: 0,
            steps: 0, stepGoal: 0, waterOz: 0, waterGoalOz: 0,
            trendWeight: nil, ratePerWeek: 0, goalWeight: 0, trendSpark: [], streak: 0)
    }

    /// Sample numbers for the widget gallery and the redacted placeholder ONLY. It is never
    /// a fallback for the user's own data: a widget that cannot read a snapshot shows
    /// `unavailable`, not this.
    static let placeholder = WidgetSnapshot(
        updated: .now, name: "Sample",
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

/// The two things about a widget that are not personal data: which skin and which
/// companion to draw. Kept apart from the snapshot so the "nothing to show yet" state
/// can still be drawn in the user's own look.
struct WidgetAppearance: Codable, Equatable {
    var themeStyleRaw: String
    var companionAvatarRaw: String

    /// The widget process's own default skin, used when nothing was ever written.
    static let fallback = WidgetAppearance(themeStyleRaw: ThemeStyle.cool.rawValue, companionAvatarRaw: "")
}

/// Read/write the snapshot through the shared App Group.
///
/// A read can fail: nothing written yet, or the phone restarted and has not been
/// unlocked, when the app group's files are still encrypted. A failed read returns nil.
/// It must never be papered over with sample data, which a widget would then show as
/// though it were the user's.
enum WidgetSharedStore {
    static let appGroup = "group.com.bryanram.victoria"
    static let key = "widget_snapshot_v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// The user's snapshot, or nil when it cannot be read.
    static func read() -> WidgetSnapshot? {
        decode(defaults?.data(forKey: key))
    }

    /// Pure half of `read`, so the "cannot read" cases are testable.
    static func decode(_ data: Data?) -> WidgetSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snap: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        defaults?.set(data, forKey: key)
        saveAppearance(WidgetAppearance(themeStyleRaw: snap.themeStyleRaw,
                                        companionAvatarRaw: snap.companionAvatarRaw))
    }

    // MARK: Appearance (not personal; readable before the first unlock)

    private static var appearanceURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget_appearance.json")
    }

    /// Theme and companion only, written without file protection so the widget can draw
    /// its empty state in the right skin while the phone is still locked after a restart.
    /// Nothing about the user's body, food or activity is ever written this way.
    static func saveAppearance(_ appearance: WidgetAppearance) {
        guard let url = appearanceURL, let data = try? JSONEncoder().encode(appearance) else { return }
        try? data.write(to: url, options: [.atomic, .noFileProtection])
    }

    static func readAppearance() -> WidgetAppearance {
        guard let url = appearanceURL, let data = try? Data(contentsOf: url),
              let appearance = try? JSONDecoder().decode(WidgetAppearance.self, from: data)
        else { return .fallback }
        return appearance
    }

    /// True when the shared container is actually reachable (for diagnostics).
    static var isAvailable: Bool { defaults != nil }
}
