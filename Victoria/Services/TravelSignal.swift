import Foundation

/// Travel awareness from the signal that's already in her pocket: the PHONE's timezone.
/// When the zone identifier changes with a real UTC-offset delta (a flight, not a DST
/// clock change), we record the shift and treat the next few days as an adjustment
/// window — so Vita, the daily brief, and the recovery framing can say "your body's on
/// a new clock" instead of misreading jet-lagged sleep and appetite as backsliding.
///
/// This is the Whoop/Google-class "it knew I was traveling" insight at zero marginal
/// cost: no location permission, no web search, no LLM call — one comparison at launch.
///
/// Honesty rules:
/// - DST is NOT travel: same zone identifier + 1h offset change is ignored.
/// - The window is bounded (≈1 day per hour shifted, 2–5 days) — after that the body
///   has adjusted and the app stops talking about the trip.
enum TravelSignal {

    struct Shift: Equatable {
        /// Signed hours moved: +east (e.g. LA→Paris +9), −west.
        let hours: Int
        let at: Date
    }

    private static let zoneKey = "travel.zoneID"
    private static let offsetKey = "travel.offsetSec"
    private static let shiftHoursKey = "travel.shiftHours"
    private static let shiftAtKey = "travel.shiftAt"

    // MARK: - Detection (pure core + a thin persisted shell)

    enum Evaluation: Equatable {
        case firstRun          // nothing stored yet — just remember today's zone
        case unchanged
        case dstOnly           // same place, clocks moved — not travel
        case shifted(hours: Int)
    }

    /// Pure comparison, unit-tested: did the phone MOVE, or did the clocks?
    static func evaluate(storedZoneID: String?, storedOffsetSec: Int?,
                         currentZoneID: String, currentOffsetSec: Int) -> Evaluation {
        guard let storedZoneID, let storedOffsetSec else { return .firstRun }
        guard storedZoneID != currentZoneID else {
            return storedOffsetSec == currentOffsetSec ? .unchanged : .dstOnly
        }
        let deltaHours = Int((Double(currentOffsetSec - storedOffsetSec) / 3600).rounded())
        // Neighboring-zone moves (±1h) aren't jet lag — record the new home quietly.
        return abs(deltaHours) >= 2 ? .shifted(hours: deltaHours) : .unchanged
    }

    /// Adjustment window: the classic ~1 day per time zone, clamped to something humane.
    static func adjustmentDays(forHours hours: Int) -> Int {
        min(5, max(2, abs(hours)))
    }

    /// Call once per launch/foreground. Compares the current zone to the last-seen one,
    /// records a shift when the phone genuinely moved, and always updates the baseline.
    @discardableResult
    static func checkNow(now: Date = .now,
                         zone: TimeZone = .current,
                         defaults: UserDefaults = .standard) -> Evaluation {
        let result = evaluate(storedZoneID: defaults.string(forKey: zoneKey),
                              storedOffsetSec: defaults.object(forKey: offsetKey) as? Int,
                              currentZoneID: zone.identifier,
                              currentOffsetSec: zone.secondsFromGMT(for: now))
        if case .shifted(let hours) = result {
            defaults.set(hours, forKey: shiftHoursKey)
            defaults.set(now, forKey: shiftAtKey)
            Diagnostics.shared.log("travel: timezone shifted \(hours >= 0 ? "+" : "")\(hours)h → adjustment window \(adjustmentDays(forHours: hours))d", .app)
        }
        defaults.set(zone.identifier, forKey: zoneKey)
        defaults.set(zone.secondsFromGMT(for: now), forKey: offsetKey)
        return result
    }

    /// The active shift, if we're still inside its adjustment window; nil otherwise.
    static func current(now: Date = .now,
                        defaults: UserDefaults = .standard) -> Shift? {
        guard let at = defaults.object(forKey: shiftAtKey) as? Date else { return nil }
        let hours = defaults.integer(forKey: shiftHoursKey)
        guard hours != 0 else { return nil }
        let daysAgo = Calendar.current.dateComponents([.day], from: at, to: now).day ?? .max
        guard daysAgo <= adjustmentDays(forHours: hours) else { return nil }
        return Shift(hours: hours, at: at)
    }

    // MARK: - Copy (pure, testable — the only words the surfaces may use)

    /// Days into the adjustment window, for phrasing ("today" vs "N days ago").
    static func daysAgo(_ shift: Shift, now: Date = .now) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: shift.at, to: now).day ?? 0)
    }

    /// The line Vita sees, folded into her data snapshot.
    static func coachLine(_ shift: Shift, now: Date = .now) -> String {
        let dir = shift.hours > 0 ? "east" : "west"
        let days = daysAgo(shift, now: now)
        let when = days == 0 ? "today" : (days == 1 ? "yesterday" : "\(days) days ago")
        return "Travel: her timezone shifted \(abs(shift.hours))h \(dir) \(when) — jet lag "
            + "disrupts sleep, appetite, and energy for a few days. Treat off-pattern days as "
            + "ADJUSTMENT, not backsliding; suggest light anchors (morning light, water, gentle "
            + "movement) and never scold a shifted schedule."
    }
}
