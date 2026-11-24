import XCTest
@testable import Sprout

/// Tests for the smoothed-trend engine — the emotional heart of the app. Expected
/// values are derived by hand from the EWMA / least-squares definitions.
final class TrendCalculatorTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private func base() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    /// Build weigh-ins from (dayOffset, weight) pairs.
    private func entries(_ pairs: [(Int, Double)]) -> [WeightEntry] {
        let b = base()
        return pairs.map { WeightEntry(date: b.addingTimeInterval(Double($0.0) * day), weightLbs: $0.1) }
    }

    // MARK: - Empty / single

    func testEmptyTrendIsEmpty() {
        XCTAssertTrue(TrendCalculator.trend([]).isEmpty)
        XCTAssertNil(TrendCalculator.currentTrend([]))
    }

    func testSingleEntryTrendEqualsItself() throws {
        let e = entries([(0, 175)])
        let t = TrendCalculator.trend(e)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(try XCTUnwrap(t.first?.value), 175, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(TrendCalculator.currentTrend(e)), 175, accuracy: 0.0001)
    }

    func testRateWithSinglePointIsZero() {
        XCTAssertEqual(TrendCalculator.ratePerWeek(entries([(0, 175)])), 0, accuracy: 0.0001)
    }

    // MARK: - EWMA correctness

    /// Two points 7 days apart, smoothing 7: alpha = 1 − e^(−1) = 0.632.
    /// t = 200 + 0.632·(190 − 200) = 193.68.
    func testEWMATwoPointsKnownValue() {
        let t = TrendCalculator.trend(entries([(0, 200), (7, 190)]), smoothingDays: 7)
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[0].value, 200, accuracy: 0.0001)
        // alpha = 1 − e^(−1) = 0.632121 ; 200 + 0.632121·(190−200) = 193.6788
        XCTAssertEqual(t[1].value, 193.6788, accuracy: 0.001)
    }

    /// The trend must lag the raw reading: a single big drop pulls the trend only partway.
    func testTrendLagsRawReading() {
        let t = TrendCalculator.trend(entries([(0, 200), (1, 180)]), smoothingDays: 7)
        // After 1 day: alpha = 1 − e^(−1/7) = 0.1331 → 200 + 0.1331·(−20) = 197.34
        XCTAssertEqual(t[1].value, 197.337, accuracy: 0.01)
        XCTAssertGreaterThan(t[1].value, 180) // trend stays well above the noisy low reading
    }

    /// Unsorted input must be sorted internally (same result regardless of order).
    func testUnsortedInputIsSorted() throws {
        let inOrder    = entries([(0, 200), (7, 190), (14, 185)])
        let outOfOrder = entries([(14, 185), (0, 200), (7, 190)])
        let sorted   = TrendCalculator.trend(inOrder, smoothingDays: 7)
        let shuffled = TrendCalculator.trend(outOfOrder, smoothingDays: 7)
        XCTAssertEqual(sorted.map(\.value), shuffled.map(\.value))
        // currentTrend must agree regardless of input order.
        XCTAssertEqual(try XCTUnwrap(TrendCalculator.currentTrend(outOfOrder)),
                       try XCTUnwrap(sorted.last?.value), accuracy: 0.0001)
    }

    /// Same-day duplicate (dt = 0 → alpha 0) must not crash or NaN; trend holds.
    func testSameDayDuplicateNoNaN() {
        let t = TrendCalculator.trend(entries([(0, 200), (0, 190)]), smoothingDays: 7)
        XCTAssertFalse(t.last!.value.isNaN)
        XCTAssertEqual(t.last!.value, 200, accuracy: 0.0001) // dt=0 → no movement
    }

    // MARK: - Rate per week

    /// Once the trend has CONVERGED (long steady decline), its slope matches the raw
    /// slope: 1 lb/day = −7 lb/week. Use 45 days so the EWMA window is fully settled.
    func testRateConvergesToTrueRate() {
        let pairs = (0...45).map { ($0, 200.0 - Double($0)) }   // 1 lb/day down
        let rate = TrendCalculator.ratePerWeek(entries(pairs))
        XCTAssertEqual(rate, -7, accuracy: 0.5)
    }

    /// DOCUMENTED BEHAVIOR: early in a new trend the smoothing LAGS, so the reported
    /// rate under-shoots the true rate (conservative). Over the first ~15 days of a
    /// 1 lb/day decline the rate reads roughly −4 to −6 lb/wk, not −7. This is
    /// intentional (avoids over-promising); locking it in so we notice if it changes.
    func testRateLagsEarlyInTrend() {
        let pairs = (0...15).map { ($0, 200.0 - Double($0)) }
        let rate = TrendCalculator.ratePerWeek(entries(pairs))
        XCTAssertLessThan(rate, 0)                 // losing
        XCTAssertGreaterThan(rate, -7)             // but under-reports the true −7
        XCTAssertEqual(rate, -4.68, accuracy: 0.3) // current measured lag value
    }

    func testRateGainPositive() {
        let pairs = (0...15).map { ($0, 150.0 + Double($0) * 0.5) }
        XCTAssertGreaterThan(TrendCalculator.ratePerWeek(entries(pairs)), 0)
    }

    func testRateFlatIsZero() {
        let pairs = (0...20).map { ($0, 160.0) }
        XCTAssertEqual(TrendCalculator.ratePerWeek(entries(pairs)), 0, accuracy: 0.01)
    }

    // MARK: - Projected goal date

    func testProjectedGoalDateWhenLosing() {
        let pairs = (0...20).map { ($0, 200.0 - Double($0)) } // losing toward goal
        let eta = TrendCalculator.projectedGoalDate(entries(pairs), goalLbs: 150)
        XCTAssertNotNil(eta)
        XCTAssertGreaterThan(eta!, Date.now) // in the future
    }

    func testProjectedGoalDateNilWhenGainingAwayFromGoal() {
        let pairs = (0...20).map { ($0, 150.0 + Double($0)) } // gaining, goal is below
        XCTAssertNil(TrendCalculator.projectedGoalDate(entries(pairs), goalLbs: 140))
    }

    func testProjectedGoalDateNilWhenFlat() {
        let pairs = (0...20).map { ($0, 160.0) }
        XCTAssertNil(TrendCalculator.projectedGoalDate(entries(pairs), goalLbs: 140))
    }

    func testProjectedGoalDateNilWhenNoData() {
        XCTAssertNil(TrendCalculator.projectedGoalDate([], goalLbs: 140))
    }

    // MARK: - Rate assessment (scaled to bodyweight)

    func testAssessGainingOrFlat() {
        XCTAssertEqual(TrendCalculator.assess(ratePerWeek: 0, currentWeightLbs: 160), .gainingOrFlat)
        XCTAssertEqual(TrendCalculator.assess(ratePerWeek: 0.5, currentWeightLbs: 160), .gainingOrFlat) // gaining
        XCTAssertEqual(TrendCalculator.assess(ratePerWeek: -0.04, currentWeightLbs: 160), .gainingOrFlat) // negligible
    }

    func testAssessIdealZone() {
        // 160 lb: half% = 0.8, one% = 1.6. A 1.2 lb/wk loss is "ideal".
        XCTAssertEqual(TrendCalculator.assess(ratePerWeek: -1.2, currentWeightLbs: 160), .ideal)
    }

    func testAssessSlow() {
        // loss 0.3 lb/wk is below half% (0.8) but above the 0.05 floor → slow
        XCTAssertEqual(TrendCalculator.assess(ratePerWeek: -0.3, currentWeightLbs: 160), .slow)
    }

    func testAssessFast() {
        // loss 2.5 lb/wk exceeds one% (1.6) → fast
        XCTAssertEqual(TrendCalculator.assess(ratePerWeek: -2.5, currentWeightLbs: 160), .fast)
    }

    func testAssessZeroWeightIsSafe() {
        XCTAssertEqual(TrendCalculator.assess(ratePerWeek: -1, currentWeightLbs: 0), .gainingOrFlat)
    }
}
