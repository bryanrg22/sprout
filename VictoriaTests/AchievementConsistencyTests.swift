import XCTest
@testable import Victoria

/// The 7- and 14-day consistency badges count the days the user logged something, by the
/// same definition as `StreakCalculator` (L-B6): food, water or a weigh-in entered by hand.
/// Steps imported from Apple Health and weights synced from a scale are not logging.
final class AchievementConsistencyTests: XCTestCase {

    private let la = FixedCalendar()
    private var now: Date { la.at(2026, 11, 20, 18) }

    /// Noon on the day `daysAgo` days before `now`.
    private func day(_ daysAgo: Int) -> Date {
        la.calendar.date(byAdding: .day, value: -daysAgo, to: la.at(2026, 11, 20, 12))!
    }

    private func earned(foods: [FoodEntry] = [],
                        weights: [WeightEntry] = [],
                        water: [WaterEntry] = [],
                        steps: [StepsEntry] = [],
                        already: Set<String> = []) -> Set<String> {
        Set(AchievementCatalog.newlyEarned(foods: foods, weights: weights, water: water, steps: steps,
                                           workouts: [], profile: UserProfile(), alreadyUnlocked: already,
                                           now: now, calendar: la.calendar).map(\.id))
    }

    func testThirtyDaysOfImportedStepsUnlockNoConsistencyBadge() {
        // What the launch backfill writes on day one: a month of Apple Health step totals.
        let imported = (0..<30).map { StepsEntry(date: day($0), count: 7_500) }

        let badges = earned(steps: imported)

        XCTAssertFalse(badges.contains("consistency_7"), "imported steps are not days the user logged")
        XCTAssertFalse(badges.contains("self_kindness"))
    }

    func testScaleSyncedWeightsUnlockNoConsistencyBadge() {
        let synced = (0..<14).map { WeightEntry(date: day($0), weightLbs: 180, source: "healthkit",
                                                healthKitUUID: "hk-\($0)") }

        let badges = earned(weights: synced)

        XCTAssertFalse(badges.contains("consistency_7"))
        XCTAssertFalse(badges.contains("self_kindness"))
    }

    func testSevenDaysOfFoodUnlockTheSevenDayBadgeOnly() {
        let foods = (0..<7).map { FoodEntry(date: day($0), name: "Oatmeal", calories: 300) }

        let badges = earned(foods: foods)

        XCTAssertTrue(badges.contains("consistency_7"))
        XCTAssertFalse(badges.contains("self_kindness"))
    }

    func testSixDaysIsNotSeven() {
        let foods = (0..<6).map { FoodEntry(date: day($0), name: "Oatmeal", calories: 300) }
        XCTAssertFalse(earned(foods: foods).contains("consistency_7"))
    }

    func testFourteenDaysMixedAcrossFoodWaterAndManualWeighInsUnlockBoth() {
        // Any one of the three counts for a day, exactly as in the header streak.
        let foods = (0..<5).map { FoodEntry(date: day($0), name: "Rice bowl", calories: 500) }
        let water = (5..<10).map { WaterEntry(date: day($0), amountOz: 16) }
        let weighIns = (10..<14).map { WeightEntry(date: day($0), weightLbs: 180) }

        let badges = earned(foods: foods, weights: weighIns, water: water)

        XCTAssertTrue(badges.contains("consistency_7"))
        XCTAssertTrue(badges.contains("self_kindness"))
    }

    func testAStreakThatDoesNotReachTodayDoesNotCount() {
        let foods = (1..<9).map { FoodEntry(date: day($0), name: "Oatmeal", calories: 300) }   // nothing today
        XCTAssertFalse(earned(foods: foods).contains("consistency_7"))
    }

    func testImportedStepsDoNotBridgeAGapInLogging() {
        // Logged on 4 of the last 7 days; steps exist for all 7.
        let foods = [0, 1, 4, 6].map { FoodEntry(date: day($0), name: "Oatmeal", calories: 300) }
        let steps = (0..<7).map { StepsEntry(date: day($0), count: 9_000) }
        XCTAssertFalse(earned(foods: foods, steps: steps).contains("consistency_7"))
    }

    func testTheBadgeAgreesWithTheHeaderStreak() {
        let foods = (0..<7).map { FoodEntry(date: day($0), name: "Oatmeal", calories: 300) }
        let steps = (0..<30).map { StepsEntry(date: day($0), count: 9_000) }
        let streak = StreakCalculator.loggingStreak(foods: foods, weights: [], calendar: la.calendar, now: now)
        XCTAssertEqual(streak, 7)
        XCTAssertEqual(earned(foods: foods, steps: steps).contains("consistency_7"), streak >= 7)
        XCTAssertEqual(earned(foods: foods, steps: steps).contains("self_kindness"), streak >= 14)
    }

    func testABadgeAlreadyUnlockedIsNeitherOfferedAgainNorTakenAway() {
        // Unlocked under the old rule, from steps alone. The rule now says no; the catalog
        // only ever reports badges to add, and the stored unlock is not part of its answer.
        let imported = (0..<30).map { StepsEntry(date: day($0), count: 7_500) }
        let already: Set<String> = ["first_steps", "on_the_move", "consistency_7", "self_kindness"]

        let badges = earned(steps: imported, already: already)

        XCTAssertTrue(badges.isDisjoint(with: already))
    }

    func testStepsStillEarnTheStepBadge() {
        // The step badge is about steps and is unchanged.
        let profile = UserProfile()
        let steps = [StepsEntry(date: day(0), count: profile.dailyStepGoal + 1)]
        XCTAssertTrue(earned(steps: steps).contains("on_the_move"))
    }
}
