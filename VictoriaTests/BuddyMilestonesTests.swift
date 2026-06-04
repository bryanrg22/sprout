import XCTest
@testable import Victoria

/// The brain of the "live buddy" cheer: which daily goals were just crossed, fired once
/// per day. Push delivery is verified on-device; this pins the detection + the guard.
final class BuddyMilestonesTests: XCTestCase {

    func testCalorieGoalReachedWithinGraceBand() {
        // 97% of target counts as "fueled" (kind framing); 96% does not.
        var i = BuddyMilestoneInput(caloriesEaten: 1455, calorieTarget: 1500)   // 97%
        XCTAssertTrue(BuddyMilestones.met(i).contains(.calories))
        i.caloriesEaten = 1440                                                   // 96%
        XCTAssertFalse(BuddyMilestones.met(i).contains(.calories))
    }

    func testProteinStepsWaterGoals() {
        let i = BuddyMilestoneInput(
            proteinEaten: 100, proteinTarget: 100,
            steps: 8200, stepGoal: 8000,
            waterOz: 80, waterGoal: 79)
        let met = BuddyMilestones.met(i)
        XCTAssertTrue(met.contains(.protein))
        XCTAssertTrue(met.contains(.steps))
        XCTAssertTrue(met.contains(.water))
    }

    func testNoGoalsSetMeansNoMilestones() {
        // Targets of 0 must never fire (avoid celebrating against an unset goal).
        let i = BuddyMilestoneInput(caloriesEaten: 500, calorieTarget: 0,
                                    proteinEaten: 50, proteinTarget: 0,
                                    steps: 100, stepGoal: 0,
                                    waterOz: 10, waterGoal: 0)
        XCTAssertTrue(BuddyMilestones.met(i).isEmpty)
    }

    func testOnlyHighestStreakTierFires() {
        XCTAssertEqual(BuddyMilestones.met(BuddyMilestoneInput(dayStreak: 7)).intersection([.streak3, .streak7, .streak14, .streak30]),
                       [.streak7])
        XCTAssertEqual(BuddyMilestones.met(BuddyMilestoneInput(dayStreak: 30)).intersection([.streak3, .streak7, .streak14, .streak30]),
                       [.streak30])
        XCTAssertTrue(BuddyMilestones.met(BuddyMilestoneInput(dayStreak: 2)).isEmpty)
    }

    func testConsumeFiresOncePerDayThenGuards() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let uid = "u-\(UUID().uuidString)"
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let i = BuddyMilestoneInput(caloriesEaten: 1600, calorieTarget: 1500, dayStreak: 7)

        let first = BuddyMilestones.consumeNewlyReached(i, myUserID: uid, day: day, defaults: defaults)
        XCTAssertEqual(first, [.calories, .streak7])

        // Same day → already celebrated → nothing fires again.
        let second = BuddyMilestones.consumeNewlyReached(i, myUserID: uid, day: day, defaults: defaults)
        XCTAssertTrue(second.isEmpty)

        // Next day → the guard key changes → it can fire once more.
        let nextDay = day.addingTimeInterval(24 * 3600)
        let third = BuddyMilestones.consumeNewlyReached(i, myUserID: uid, day: nextDay, defaults: defaults)
        XCTAssertEqual(third, [.calories, .streak7])
    }

    func testNewDayRolloverDetection() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(2 * 24 * 3600)   // +2 days, definitely a new day
        // First call ever just initializes — no previous day to roll over from.
        XCTAssertFalse(BuddyDay.rolledOver(day1, defaults: defaults))
        // Same day again → no rollover.
        XCTAssertFalse(BuddyDay.rolledOver(day1, defaults: defaults))
        // A new calendar day → rollover.
        XCTAssertTrue(BuddyDay.rolledOver(day2, defaults: defaults))
        // Same (new) day again → no rollover.
        XCTAssertFalse(BuddyDay.rolledOver(day2, defaults: defaults))
    }

    func testMessagesAreWarmAndNamed() {
        XCTAssertTrue(BuddyMilestone.calories.message(name: "Victoria").contains("Victoria"))
        XCTAssertTrue(BuddyMilestone.streak30.message(name: "Bryan").contains("30"))
    }

    // MARK: - Snapshot freshness (a stale snapshot must not read as "logged today")

    private func snapshot(loggedToday: Bool, lastActive: Date) -> BuddySnapshotPayload {
        BuddySnapshotPayload(ownerUserID: "u", displayName: "Victoria", dayStreak: 2,
                             characterMood: .happy, loggedToday: loggedToday, lastActive: lastActive)
    }

    func testStaleSnapshotIsNotLoggedTodayEffective() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let stale = snapshot(loggedToday: true, lastActive: yesterday)   // logged "today" — but yesterday
        XCTAssertFalse(stale.reflectsToday)
        XCTAssertFalse(stale.loggedTodayEffective, "a snapshot from yesterday must not count as logged today")
    }

    func testFreshSnapshotIsLoggedTodayEffective() {
        let fresh = snapshot(loggedToday: true, lastActive: .now)
        XCTAssertTrue(fresh.reflectsToday)
        XCTAssertTrue(fresh.loggedTodayEffective)
    }

    func testFreshButNotLoggedIsNotEffective() {
        let fresh = snapshot(loggedToday: false, lastActive: .now)        // active today, hasn't logged
        XCTAssertTrue(fresh.reflectsToday)
        XCTAssertFalse(fresh.loggedTodayEffective)
    }
}
