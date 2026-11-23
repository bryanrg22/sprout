import XCTest
@testable import Victoria

/// How old the buddy's last published day is (L-B11): a snapshot that has not moved for
/// days is not shown as today's. Dates come from an explicit calendar; no test reads the clock.
final class BuddyFreshnessTests: XCTestCase {

    private let la = FixedCalendar()

    private func freshness(published: Date?, now: Date) -> BuddyFreshness {
        BuddyFreshness.evaluate(lastPublished: published, now: now, calendar: la.calendar)
    }

    func testPublishedTodayIsCurrent() {
        XCTAssertEqual(freshness(published: la.at(2026, 11, 20, 0, 5), now: la.at(2026, 11, 20, 23, 50)), .current)
    }

    func testYesterdayAndTheDayBeforeAreQuietNotStale() {
        let late = la.at(2026, 11, 19, 23, 59)
        XCTAssertEqual(freshness(published: late, now: la.at(2026, 11, 20, 0, 1)), .quiet(since: late, days: 1),
                       "two minutes across midnight is still another day's data")
        let twoBack = la.at(2026, 11, 18, 8)
        XCTAssertEqual(freshness(published: twoBack, now: la.at(2026, 11, 20, 8)), .quiet(since: twoBack, days: 2))
    }

    func testThreeDaysOrMoreIsStale() {
        let three = la.at(2026, 11, 17, 21)
        XCTAssertEqual(freshness(published: three, now: la.at(2026, 11, 20, 7)), .stale(since: three, days: 3))
        let month = la.at(2026, 10, 20, 12)
        XCTAssertEqual(freshness(published: month, now: la.at(2026, 11, 20, 12)), .stale(since: month, days: 31))
    }

    func testNeverPublished() {
        XCTAssertEqual(freshness(published: nil, now: la.at(2026, 11, 20, 12)), .neverPublished)
    }

    func testDaysAreCalendarDaysAcrossTheClockChange() {
        // 1 November 2026 has 25 hours in Los Angeles.
        let before = la.at(2026, 10, 30, 23)
        XCTAssertEqual(freshness(published: before, now: la.at(2026, 11, 2, 1)), .stale(since: before, days: 3))
    }

    func testASnapshotStampedInTheFutureIsCurrent() {
        // The buddy's clock is ahead of mine: not "minus one day old".
        XCTAssertEqual(freshness(published: la.at(2026, 11, 21, 3), now: la.at(2026, 11, 20, 22)), .current)
    }

    func testTheSameInstantCanBeTodayInOneZoneAndYesterdayInAnother() {
        let ny = FixedCalendar(zone: "America/New_York")
        let published = la.at(2026, 11, 19, 22)                 // 01:00 on the 20th in New York
        let now = la.at(2026, 11, 20, 1)                        // 04:00 on the 20th in New York
        XCTAssertEqual(BuddyFreshness.evaluate(lastPublished: published, now: now, calendar: la.calendar),
                       .quiet(since: published, days: 1))
        XCTAssertEqual(BuddyFreshness.evaluate(lastPublished: published, now: now, calendar: ny.calendar), .current)
    }

    func testOnlyStaleOffersTheWayOut() {
        let now = la.at(2026, 11, 20, 12)
        XCTAssertFalse(freshness(published: now, now: now).isStale)
        XCTAssertFalse(freshness(published: la.at(2026, 11, 19, 12), now: now).isStale)
        XCTAssertTrue(freshness(published: la.at(2026, 11, 10, 12), now: now).isStale)
        XCTAssertFalse(freshness(published: nil, now: now).isStale)
    }
}
