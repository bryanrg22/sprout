import XCTest
@testable import Victoria

/// What a widget may show. The rule these protect: a widget shows the user's own
/// numbers for the day they belong to, or nothing; never sample data as if it were real.
final class WidgetSnapshotTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    private func snapshot(updated: Date) -> WidgetSnapshot {
        WidgetSnapshot(updated: updated, name: "Alex",
                       themeStyleRaw: ThemeStyle.cool.rawValue, companionAvatarRaw: "bryan",
                       calorieTarget: 2750, calorieMax: 2950, caloriesEaten: 1900, stepBonus: 150,
                       protein: 120, proteinTarget: 160, carbs: 210, carbsTarget: 320, fat: 60, fatTarget: 80,
                       steps: 9100, stepGoal: 8000, waterOz: 48, waterGoalOz: 90,
                       trendWeight: 161.2, ratePerWeek: 0.4, goalWeight: 172,
                       trendSpark: [160, 160.6, 161.2], streak: 12)
    }

    private let appearance = WidgetAppearance(themeStyleRaw: ThemeStyle.cool.rawValue, companionAvatarRaw: "bryan")

    // MARK: - A failed read is nil, never sample data

    func testMissingOrCorruptDataDecodesToNil() {
        XCTAssertNil(WidgetSharedStore.decode(nil))
        XCTAssertNil(WidgetSharedStore.decode(Data()))
        XCTAssertNil(WidgetSharedStore.decode(Data("{\"name\":\"x\"}".utf8)))
        XCTAssertNil(WidgetSharedStore.decode(Data("not json".utf8)))
    }

    func testStoredSnapshotRoundTrips() throws {
        let original = snapshot(updated: date(23, 18))
        let decoded = try XCTUnwrap(WidgetSharedStore.decode(try JSONEncoder().encode(original)))
        XCTAssertEqual(decoded.name, "Alex")
        XCTAssertEqual(decoded.caloriesEaten, 1900)
        XCTAssertEqual(decoded.companionAvatarRaw, "bryan")
    }

    func testUnreadableSnapshotShowsNothingAboutAnyone() {
        let plan = WidgetTimelinePlan.entries(stored: nil, appearance: appearance, now: date(24, 7), calendar: cal)
        XCTAssertEqual(plan.entries.count, 1)
        let entry = plan.entries[0]
        XCTAssertTrue(entry.isUnavailable)
        XCTAssertEqual(entry.snap.name, "", "no name, and in particular not the sample's")
        XCTAssertEqual(entry.snap.caloriesEaten, 0)
        XCTAssertEqual(entry.snap.calorieTarget, 0)
        XCTAssertNil(entry.snap.trendWeight)
        XCTAssertEqual(entry.snap.goalWeight, 0)
        XCTAssertEqual(entry.snap.streak, 0)
        XCTAssertTrue(entry.snap.trendSpark.isEmpty)
        XCTAssertEqual(entry.snap.themeStyleRaw, ThemeStyle.cool.rawValue, "drawn in the user's own skin")
        XCTAssertEqual(entry.snap.companionAvatarRaw, "bryan")
    }

    func testUnreadableSnapshotIsRetriedSoon() {
        let now = date(24, 7)
        let plan = WidgetTimelinePlan.entries(stored: nil, appearance: appearance, now: now, calendar: cal)
        XCTAssertEqual(plan.reloadAfter.timeIntervalSince(now), 5 * 60)
    }

    func testTheSampleIsNotAnyRealPersonsName() {
        XCTAssertEqual(WidgetSnapshot.placeholder.name, "Sample")
    }

    func testNothingEverWrittenFallsBackToTheNeutralAppearance() {
        XCTAssertEqual(WidgetAppearance.fallback.themeStyleRaw, ThemeStyle.cool.rawValue)
        XCTAssertEqual(WidgetAppearance.fallback.companionAvatarRaw, "")
    }

    // MARK: - Day totals belong to their day

    func testSameDayIsShownAsWritten() {
        let s = snapshot(updated: date(23, 18)).asOf(date(23, 23, 59), calendar: cal)
        XCTAssertEqual(s.caloriesEaten, 1900)
        XCTAssertEqual(s.steps, 9100)
        XCTAssertEqual(s.calorieTarget, 2750)
    }

    func testNextDayResetsTheDayTotalsAndKeepsTheRest() {
        let s = snapshot(updated: date(23, 18)).asOf(date(24, 7), calendar: cal)
        XCTAssertEqual(s.caloriesEaten, 0)
        XCTAssertEqual(s.protein, 0)
        XCTAssertEqual(s.carbs, 0)
        XCTAssertEqual(s.fat, 0)
        XCTAssertEqual(s.steps, 0)
        XCTAssertEqual(s.waterOz, 0)
        XCTAssertEqual(s.stepBonus, 0)
        XCTAssertEqual(s.calorieTarget, 2600, "yesterday's step bonus comes out of the target")
        XCTAssertEqual(s.calorieMax, 2800)
        // carried over
        XCTAssertEqual(s.name, "Alex")
        XCTAssertEqual(s.proteinTarget, 160)
        XCTAssertEqual(s.stepGoal, 8000)
        XCTAssertEqual(s.waterGoalOz, 90)
        XCTAssertEqual(s.trendWeight, 161.2)
        XCTAssertEqual(s.goalWeight, 172)
        XCTAssertEqual(s.streak, 12)
    }

    func testSingleNumberGoalKeepsNoRangeAfterTheReset() {
        var gain = snapshot(updated: date(23, 18))
        gain.calorieMax = 0
        XCTAssertEqual(gain.asOf(date(24, 7), calendar: cal).calorieMax, 0)
    }

    func testASnapshotFromTheFutureIsLeftAlone() {
        // The clock moved back (travel west, manual change): do not blank today's real numbers.
        let s = snapshot(updated: date(24, 1)).asOf(date(23, 23), calendar: cal)
        XCTAssertEqual(s.caloriesEaten, 1900)
    }

    // MARK: - The timeline flips at midnight by itself

    func testMiddayTimelineIsOneEntryRefreshedInHalfAnHour() {
        let now = date(23, 12)
        let plan = WidgetTimelinePlan.entries(stored: snapshot(updated: date(23, 11)), appearance: appearance,
                                              now: now, calendar: cal)
        XCTAssertEqual(plan.entries.count, 1)
        XCTAssertFalse(plan.entries[0].isUnavailable)
        XCTAssertEqual(plan.entries[0].snap.caloriesEaten, 1900)
        XCTAssertEqual(plan.reloadAfter.timeIntervalSince(now), 30 * 60)
    }

    func testTimelineCrossingMidnightResetsAtMidnight() {
        let now = date(23, 23, 45)
        let plan = WidgetTimelinePlan.entries(stored: snapshot(updated: date(23, 20)), appearance: appearance,
                                              now: now, calendar: cal)
        XCTAssertEqual(plan.entries.count, 2)
        XCTAssertEqual(plan.entries[0].snap.caloriesEaten, 1900, "still today's numbers before midnight")
        XCTAssertEqual(plan.entries[1].date, date(24, 0))
        XCTAssertEqual(plan.entries[1].snap.caloriesEaten, 0, "the new day starts empty")
        XCTAssertEqual(plan.entries[1].snap.steps, 0)
        XCTAssertEqual(plan.entries[1].snap.streak, 12)
    }

    func testAStaleSnapshotReadInTheMorningIsAlreadyReset() {
        let plan = WidgetTimelinePlan.entries(stored: snapshot(updated: date(23, 20)), appearance: appearance,
                                              now: date(24, 8), calendar: cal)
        XCTAssertEqual(plan.entries[0].snap.caloriesEaten, 0)
        XCTAssertEqual(plan.entries[0].snap.name, "Alex")
    }
}
