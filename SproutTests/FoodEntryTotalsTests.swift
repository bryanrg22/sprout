import XCTest
@testable import Sprout

/// Pins the quantity fix: a logged amount of N servings must count N× the per-serving
/// nutrition everywhere (the bug was that `quantity` was stored but never multiplied,
/// so "2 apples" only counted one — a silent calorie undercount).
final class FoodEntryTotalsTests: XCTestCase {
    func testQuantityScalesTotals() {
        let e = FoodEntry(name: "Apple", quantity: 2, calories: 95, proteinG: 1, carbsG: 25, fatG: 0)
        XCTAssertEqual(e.totalCalories, 190, accuracy: 0.001)
        XCTAssertEqual(e.totalProteinG, 2, accuracy: 0.001)
        XCTAssertEqual(e.totalCarbsG, 50, accuracy: 0.001)
        XCTAssertEqual(e.totalFatG, 0, accuracy: 0.001)
    }

    func testQuantityOneLeavesValuesUnchanged() {
        let e = FoodEntry(name: "Shake", quantity: 1, calories: 220, proteinG: 40, carbsG: 11, fatG: 2.5)
        XCTAssertEqual(e.totalCalories, 220, accuracy: 0.001)
        XCTAssertEqual(e.totalProteinG, 40, accuracy: 0.001)
        XCTAssertEqual(e.totalCarbsG, 11, accuracy: 0.001)
        XCTAssertEqual(e.totalFatG, 2.5, accuracy: 0.001)
    }

    func testFractionalQuantity() {
        let e = FoodEntry(name: "Half bar", quantity: 0.5, calories: 200, proteinG: 10, carbsG: 24, fatG: 8)
        XCTAssertEqual(e.totalCalories, 100, accuracy: 0.001)
        XCTAssertEqual(e.totalProteinG, 5, accuracy: 0.001)
    }
}
