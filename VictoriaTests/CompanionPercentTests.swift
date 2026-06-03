import XCTest
@testable import Victoria

/// Pins the fix for the capped-at-100% bug: a metric over its target must report its TRUE
/// percentage (e.g. 200% water) for the label, while the ring FILL stays clamped to full.
final class CompanionPercentTests: XCTestCase {
    func testOverTargetReportsRealPercentButRingStaysFull() {
        // 100 oz water on a 50 oz goal = 200%.
        let state = CompanionEngine.evaluate(
            caloriesEaten: 0, calorieTarget: 2000,
            protein: 0, proteinTarget: 100,
            waterOz: 100, waterTargetOz: 50,
            loggedToday: true)
        let water = try! XCTUnwrap(state.needs.first { $0.kind == .water })
        XCTAssertEqual(water.rawFraction, 2.0, accuracy: 0.001)   // 200% — the real number for the label
        XCTAssertEqual(water.fraction, 1.0, accuracy: 0.001)      // ring fill capped (can't overfill)
    }

    func testUnderTargetRawEqualsClamped() {
        let state = CompanionEngine.evaluate(
            caloriesEaten: 500, calorieTarget: 2000,
            protein: 0, proteinTarget: 100,
            waterOz: 0, waterTargetOz: 50,
            loggedToday: true)
        let food = try! XCTUnwrap(state.needs.first { $0.kind == .food })
        XCTAssertEqual(food.rawFraction, 0.25, accuracy: 0.001)   // 25%
        XCTAssertEqual(food.fraction, 0.25, accuracy: 0.001)      // identical below 100%
    }
}
