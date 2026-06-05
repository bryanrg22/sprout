import XCTest
@testable import Victoria

/// Pins the **frecency** ordering of `MachineCatalog.ranked(history:now:)` — the recency-weighted
/// "frequency + recency" model (Mozilla's awesomebar approach) that makes a current go-to lift pin
/// to the top of the workout grid while stale usage fades. Each use scores by how recently it
/// happened (≤2d → 8, ≤7d → 4, ≤30d → 2, else 1) and a machine's score is the SUM, so a recent
/// streak beats a larger-but-older pile of reps.
///
/// All cases inject a FIXED `now` and build `ExerciseEntry`s with explicit dates relative to it, so
/// there's zero wall-clock flakiness (no `Date.now`, no random). Logic-only: no UI, no live store.
final class MachineCatalogTests: XCTestCase {

    /// A fixed, deterministic "today" so the day-bucket math never depends on the wall clock.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// `days` whole days before `now` (24h × days). Used for explicit, deterministic entry dates.
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    /// A bare exercise row for a machine key on a given date (only key + date matter to ranking).
    private func entry(_ key: String, _ date: Date) -> ExerciseEntry {
        ExerciseEntry(sessionID: UUID(), date: date, machineKey: key,
                      displayName: key, iconName: "dumbbell.fill")
    }

    private func index(of key: String, in machines: [Machine]) -> Int {
        machines.firstIndex { $0.key == key }!
    }

    // MARK: 1. Recency beats stale frequency

    /// The headline behavior: A used 5× in the last 5 days (frecency 8+8+8+4+4 = 32) must outrank B
    /// used 8× ~60 days ago (frecency 8×1 = 8). Raw counts would put B first (8 > 5) — frecency,
    /// which weights recency, must not.
    func testRecencyBeatsStaleFrequency() {
        let recent = (0..<5).map { entry("bicep_curl", daysAgo(Double($0))) }     // 0..4 days ago
        let stale  = (0..<8).map { entry("leg_press",  daysAgo(60 + Double($0))) } // ~60 days ago
        let ranked = MachineCatalog.ranked(history: recent + stale, now: now)

        XCTAssertLessThan(index(of: "bicep_curl", in: ranked), index(of: "leg_press", in: ranked),
                          "A recent 5× streak must outrank a larger-but-stale 8× pile.")
        XCTAssertEqual(ranked.first?.key, "bicep_curl",
                       "The recent go-to should pin to the very top of the grid.")
    }

    // MARK: 2. Used before unused

    /// ANY machine with history outranks ANY never-used one — even a single ancient use (frecency 1)
    /// beats every unused machine, and nothing is dropped (ranking reorders, never hides).
    func testUsedBeforeUnused() {
        // One very old use of a deep-catalog machine; everything else is unused.
        let ranked = MachineCatalog.ranked(history: [entry("leg_press", daysAgo(365))], now: now)
        XCTAssertEqual(ranked.first?.key, "leg_press",
                       "A used machine ranks ahead of every unused one, however stale.")
        XCTAssertEqual(ranked.count, MachineCatalog.all.count)
        XCTAssertEqual(Set(ranked.map(\.key)), Set(MachineCatalog.all.map(\.key)),
                       "Ranking reorders the catalog, it never adds or drops machines.")
    }

    // MARK: 3. Empty history → catalog order (the popularity prior)

    func testEmptyHistoryIsCatalogOrder() {
        let ranked = MachineCatalog.ranked(history: [], now: now)
        XCTAssertEqual(ranked.map(\.key), MachineCatalog.all.map(\.key),
                       "No history → the curated catalog order (the popularity prior) is shown.")
    }

    // MARK: 4. Recent tiebreak (equal frecency)

    /// Two machines with EQUAL frecency (each used once in the same recency bucket) → the one used
    /// more recently ranks first. Both single uses land in the ≤2-day bucket (weight 8), so the only
    /// differentiator is the exact date: `seated_cable_row` (1 day ago) beats `lat_pulldown` (2 days
    /// ago) even though `lat_pulldown` sits earlier in the catalog — recency wins the tie.
    func testRecentTiebreakOnEqualFrecency() {
        let history = [entry("lat_pulldown",     daysAgo(2)),
                       entry("seated_cable_row", daysAgo(1))]
        let ranked = MachineCatalog.ranked(history: history, now: now)
        XCTAssertLessThan(index(of: "seated_cable_row", in: ranked),
                          index(of: "lat_pulldown", in: ranked),
                          "Equal frecency: the more-recently-used machine ranks first.")
    }

    // MARK: 5. Stable catalog tiebreak (never-used machines)

    /// Two never-used machines must keep their relative catalog order (no jitter). `treadmill`
    /// precedes `bike` in the catalog, and with no history for either they must stay in that order.
    func testStableCatalogTiebreakForUnused() {
        // A single use of an unrelated machine, so the fast empty-history path isn't taken.
        let ranked = MachineCatalog.ranked(history: [entry("bicep_curl", daysAgo(1))], now: now)
        XCTAssertLessThan(index(of: "treadmill", in: ranked), index(of: "bike", in: ranked),
                          "Never-used machines keep their curated catalog order.")
        // And that order matches the catalog's own (full stable check on the unused tail).
        let used: Set<String> = ["bicep_curl"]
        let unused = ranked.map(\.key).filter { !used.contains($0) }
        let catalogUnused = MachineCatalog.all.map(\.key).filter { !used.contains($0) }
        XCTAssertEqual(unused, catalogUnused, "Unused machines stay in catalog order, no jitter.")
    }

    // MARK: Extra edge cases

    /// Future-dated rows (clock skew / back-and-forth edits) clamp to "today" — they score as the
    /// freshest bucket (8) and must not crash or sort oddly. A future single use should still rank
    /// like a same-day use and beat a 90-day-old one.
    func testFutureDatedClampsToToday() {
        let history = [entry("leg_press",  daysAgo(-3)),   // 3 days in the FUTURE → clamps to today
                       entry("bicep_curl", daysAgo(90))]   // genuinely stale
        let ranked = MachineCatalog.ranked(history: history, now: now)
        XCTAssertLessThan(index(of: "leg_press", in: ranked), index(of: "bicep_curl", in: ranked),
                          "A future-dated use clamps to today (weight 8) and beats a stale one.")
    }

    /// Many same-day uses simply sum their weights — five uses today = 5×8 = 40 — so a single
    /// heavy day still reads as a strong go-to and outranks a machine touched once a week ago.
    func testManySameDayUsesSumWeights() {
        let today = (0..<5).map { _ in entry("leg_press", now) }       // 5 × 8 = 40
        let weekOld = [entry("bicep_curl", daysAgo(7))]                // 1 × 4 = 4
        let ranked = MachineCatalog.ranked(history: today + weekOld, now: now)
        XCTAssertEqual(ranked.first?.key, "leg_press",
                       "Same-day uses sum, so a heavy day pins the machine to the top.")
        XCTAssertLessThan(index(of: "leg_press", in: ranked), index(of: "bicep_curl", in: ranked))
    }

    /// An off-catalog custom key in history must not crash or inject a phantom tile.
    func testUnknownKeysAreIgnored() {
        let history = [entry("custom_\(UUID().uuidString)", daysAgo(1)),
                       entry("leg_press", daysAgo(1))]
        let ranked = MachineCatalog.ranked(history: history, now: now)
        XCTAssertEqual(ranked.count, MachineCatalog.all.count)
        XCTAssertEqual(ranked.first?.key, "leg_press")
        XCTAssertFalse(ranked.contains { $0.key.hasPrefix("custom_") })
    }
}
