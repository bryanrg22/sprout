import XCTest
@testable import Sprout

/// Pins the logging-streak definition after the "30-day streak out of nowhere" bug: the streak
/// must count only ACTIVE logging (food, water, manual weigh-ins) and must ignore passively-synced
/// Apple Health data — steps (never passed in now) and scale-synced weights (which carry a
/// `healthKitUUID`). Otherwise backfilling ~30 days of Health history reads as a 30-day streak the
/// user never earned.
final class StreakCalculatorTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    /// A fixed, deterministic "today" so the relative-day math doesn't depend on the wall clock.
    private var now: Date { cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: now)! }

    func testFoodOnConsecutiveDaysCounts() {
        let foods = [FoodEntry(date: day(0), name: "a", calories: 100),
                     FoodEntry(date: day(-1), name: "b", calories: 100)]
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: foods, weights: [], calendar: cal, now: now), 2)
    }

    func testManualWeighInsCount() {
        let weights = [WeightEntry(date: day(0), weightLbs: 150),
                       WeightEntry(date: day(-1), weightLbs: 151)]   // healthKitUUID nil → manual
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: [], weights: weights, calendar: cal, now: now), 2)
    }

    func testWaterCounts() {
        let water = [WaterEntry(date: day(0), amountOz: 12)]
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: [], waters: water, weights: [], calendar: cal, now: now), 1)
    }

    func testImportedWeightsDoNotCount() {
        // 30 days of scale-synced weigh-ins (healthKitUUID set) must NOT make a 30-day streak.
        let weights = (0..<30).map { WeightEntry(date: day(-$0), weightLbs: 150, healthKitUUID: "hk-\($0)") }
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: [], weights: weights, calendar: cal, now: now), 0)
    }

    /// The exact bug: a phone full of imported Health history + only today's real food should be a
    /// 1-day streak, not 30.
    func testImportedHistoryDoesNotInflateRealStreak() {
        let importedWeights = (0..<30).map { WeightEntry(date: day(-$0), weightLbs: 150, healthKitUUID: "hk-\($0)") }
        let foodToday = [FoodEntry(date: day(0), name: "a", calories: 100)]
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: foodToday, weights: importedWeights, calendar: cal, now: now), 1)
    }

    func testGapBreaksStreak() {
        // Food today and two days ago, nothing yesterday → streak is just today.
        let foods = [FoodEntry(date: day(0), name: "a", calories: 100),
                     FoodEntry(date: day(-2), name: "b", calories: 100)]
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: foods, weights: [], calendar: cal, now: now), 1)
    }

    func testNothingTodayIsZero() {
        let foods = [FoodEntry(date: day(-1), name: "a", calories: 100)]
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: foods, weights: [], calendar: cal, now: now), 0)
    }

    // MARK: - daysSinceLastLog (the comeback signal)

    /// A two-week break, then logging again today: the gap must still read 14 — today's own
    /// logs are excluded on purpose, so the welcome-back framing survives the very moment
    /// the user returns (which is exactly when it's needed).
    func testDaysSinceLastLogSurvivesLoggingToday() {
        let foods = [FoodEntry(date: day(0), name: "back", calories: 400),
                     FoodEntry(date: day(-14), name: "old", calories: 500)]
        XCTAssertEqual(StreakCalculator.daysSinceLastLog(foods: foods, weights: [], calendar: cal, now: now), 14)
    }

    func testDaysSinceLastLogYesterdayIsOne() {
        let foods = [FoodEntry(date: day(-1), name: "a", calories: 100)]
        XCTAssertEqual(StreakCalculator.daysSinceLastLog(foods: foods, weights: [], calendar: cal, now: now), 1)
    }

    /// Brand-new user (first-ever log is today, or nothing at all): no gap — a first log is
    /// a beginning, not a comeback.
    func testDaysSinceLastLogNilForNewUser() {
        XCTAssertNil(StreakCalculator.daysSinceLastLog(foods: [], weights: [], calendar: cal, now: now))
        let onlyToday = [FoodEntry(date: day(0), name: "first", calories: 100)]
        XCTAssertNil(StreakCalculator.daysSinceLastLog(foods: onlyToday, weights: [], calendar: cal, now: now))
    }

    /// Scale-synced weights during the break must not shrink the gap — they're passive data,
    /// same rule as the streak.
    func testDaysSinceLastLogIgnoresImportedWeights() {
        let foods = [FoodEntry(date: day(-10), name: "old", calories: 500)]
        let imported = (1..<10).map { WeightEntry(date: day(-$0), weightLbs: 150, healthKitUUID: "hk-\($0)") }
        XCTAssertEqual(StreakCalculator.daysSinceLastLog(foods: foods, weights: imported, calendar: cal, now: now), 10)
    }
}
