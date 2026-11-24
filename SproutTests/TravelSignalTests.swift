import XCTest
@testable import Sprout

/// Pins the travel-awareness signal: real moves vs DST clock changes, the bounded
/// adjustment window, the brief's travel rung, and the never-scold copy contract.
final class TravelSignalTests: XCTestCase {

    // MARK: - Detection (pure)

    func testFirstRunJustRemembers() {
        XCTAssertEqual(TravelSignal.evaluate(storedZoneID: nil, storedOffsetSec: nil,
                                             currentZoneID: "America/Los_Angeles",
                                             currentOffsetSec: -25200), .firstRun)
    }

    func testDSTIsNotTravel() {
        // Same place, clocks moved an hour — the phone didn't go anywhere.
        XCTAssertEqual(TravelSignal.evaluate(storedZoneID: "America/Los_Angeles",
                                             storedOffsetSec: -28800,
                                             currentZoneID: "America/Los_Angeles",
                                             currentOffsetSec: -25200), .dstOnly)
    }

    func testRealFlightIsAShift() {
        // LA (-7) → Paris (+2) = +9 hours east.
        XCTAssertEqual(TravelSignal.evaluate(storedZoneID: "America/Los_Angeles",
                                             storedOffsetSec: -25200,
                                             currentZoneID: "Europe/Paris",
                                             currentOffsetSec: 7200),
                       .shifted(hours: 9))
        // Paris → LA westward, negative.
        XCTAssertEqual(TravelSignal.evaluate(storedZoneID: "Europe/Paris",
                                             storedOffsetSec: 7200,
                                             currentZoneID: "America/Los_Angeles",
                                             currentOffsetSec: -25200),
                       .shifted(hours: -9))
    }

    func testNeighborZoneMoveIsQuietlyIgnored() {
        // LA → Denver (+1h) — not jet lag; no travel messaging.
        XCTAssertEqual(TravelSignal.evaluate(storedZoneID: "America/Los_Angeles",
                                             storedOffsetSec: -25200,
                                             currentZoneID: "America/Denver",
                                             currentOffsetSec: -21600), .unchanged)
    }

    func testAdjustmentWindowIsBounded() {
        XCTAssertEqual(TravelSignal.adjustmentDays(forHours: 2), 2)
        XCTAssertEqual(TravelSignal.adjustmentDays(forHours: -3), 3)
        XCTAssertEqual(TravelSignal.adjustmentDays(forHours: 9), 5)   // clamped — a trip
        XCTAssertEqual(TravelSignal.adjustmentDays(forHours: 12), 5)  // isn't a month of excuses
    }

    // MARK: - Persisted shell (isolated defaults)

    func testCheckNowRecordsShiftAndCurrentExpires() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "travel-tests"))
        d.removePersistentDomain(forName: "travel-tests")
        let la = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let now = Date()

        XCTAssertEqual(TravelSignal.checkNow(now: now, zone: la, defaults: d), .firstRun)
        XCTAssertNil(TravelSignal.current(now: now, defaults: d))

        XCTAssertEqual(TravelSignal.checkNow(now: now, zone: paris, defaults: d), .shifted(hours: 9))
        let shift = try XCTUnwrap(TravelSignal.current(now: now, defaults: d))
        XCTAssertEqual(shift.hours, 9)

        // Inside the window (day 3 of 5) → still active; after it → silent.
        let day3 = now.addingTimeInterval(3 * 86_400)
        XCTAssertNotNil(TravelSignal.current(now: day3, defaults: d))
        let day6 = now.addingTimeInterval(6 * 86_400)
        XCTAssertNil(TravelSignal.current(now: day6, defaults: d))
    }

    // MARK: - Surfaces

    func testBriefLeadsWithTravelOverMilestone() {
        var s = DailyBriefService.Signals()
        s.name = "Sam"
        s.trendEasedDown = true            // would normally win as a milestone…
        s.travelShiftHours = 9
        s.travelShiftDaysAgo = 1
        let pick = DailyBriefService.pick(s)
        XCTAssertEqual(pick.topic, .travel) // …but the new clock reframes the day first
        XCTAssertTrue(pick.body.contains("9"))
    }

    func testGapReturnStillOutranksTravel() {
        var s = DailyBriefService.Signals()
        s.daysAway = 5
        s.travelShiftHours = 9
        s.travelShiftDaysAgo = 0
        XCTAssertEqual(DailyBriefService.pick(s).topic, .gapReturn)
    }

    /// Copy contract: adjustment framing, never guilt, never clinical.
    func testCopyNeverScolds() {
        let shift = TravelSignal.Shift(hours: -9, at: .now)
        let texts = [TravelSignal.coachLine(shift),
                     DailyBriefService.pick({
                         var s = DailyBriefService.Signals()
                         s.travelShiftHours = -9; s.travelShiftDaysAgo = 2
                         return s
                     }()).body]
        for text in texts {
            let lower = text.lowercased()
            for banned in ["should have", "failed", "behind", "slipping", "excuse", "lazy"] {
                XCTAssertFalse(lower.contains(banned), "travel copy contained '\(banned)'")
            }
        }
        XCTAssertTrue(TravelSignal.coachLine(shift).contains("ADJUSTMENT"))
    }
}
