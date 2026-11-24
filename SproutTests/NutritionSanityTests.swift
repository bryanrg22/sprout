import XCTest
@testable import Sprout

/// The deterministic guard that protects a logged entry from an obviously-broken
/// calorie/macro estimate (whether from AI or a community database). These tests pin
/// BOTH directions: real foods must pass untouched (no false alarms), and the broken
/// classes must be flagged.
final class NutritionSanityTests: XCTestCase {

    private let tol = 0.5

    // MARK: Atwater math

    func testCaloriesFromMacros() {
        // 4·P + 4·C + 9·F = 40 + 80 + 45 = 165
        XCTAssertEqual(NutritionSanity.caloriesFromMacros(protein: 10, carbs: 20, fat: 5),
                       165, accuracy: tol)
        // Negatives don't subtract.
        XCTAssertEqual(NutritionSanity.caloriesFromMacros(protein: -10, carbs: 20, fat: 0),
                       80, accuracy: tol)
    }

    // MARK: Real foods must NOT be flagged (guard against false positives)

    func testRealFoodsAreNotSuspicious() {
        // (name, cal, p, c, f, grams)
        let foods: [(String, Double, Double, Double, Double, Double?)] = [
            ("chicken breast 100g", 165, 31, 0, 3.6, 100),
            ("banana 118g", 105, 1.3, 27, 0.4, 118),
            ("olive oil 1 tbsp", 119, 0, 0, 13.5, 14),
            ("white sugar 100g", 387, 0, 100, 0, 100),
            ("butter 100g", 717, 0.85, 0.06, 81, 100),
            ("Muscle Milk PRO bottle", 220, 40, 11, 2.5, 414),   // the real product, correct
            ("avocado 100g", 160, 2, 9, 15, 100),
            ("plain bagel", 245, 10, 48, 1.5, 95),
        ]
        for (name, cal, p, c, f, g) in foods {
            let result = NutritionSanity.check(calories: cal, protein: p, carbs: c, fat: f, grams: g)
            XCTAssertFalse(result.isSuspicious, "\(name) should pass clean; got: \(result.reason ?? "")")
            XCTAssertNil(result.reason, "\(name) should have no note")
        }
    }

    // MARK: Fills missing calories from macros (a fix, not a flag)

    func testFillsMissingCaloriesFromMacros() {
        let r = NutritionSanity.check(calories: 0, protein: 30, carbs: 40, fat: 10)
        XCTAssertEqual(r.calories, 370, accuracy: tol)   // 4·30 + 4·40 + 9·10
        XCTAssertFalse(r.isSuspicious)
    }

    // MARK: Broken classes MUST be flagged

    func testProteinExceedingCaloriesIsFlagged() {
        // 100 g protein = 400 kcal, but only 100 kcal stated → impossible.
        let r = NutritionSanity.check(calories: 100, protein: 100, carbs: 0, fat: 0)
        XCTAssertTrue(r.isSuspicious)
        XCTAssertNotNil(r.reason)
    }

    func testCaloriesVsMacrosMismatchIsFlagged() {
        // Macros imply ~500 kcal; label says 200 → a parse/unit error.
        let r = NutritionSanity.check(calories: 200, protein: 40, carbs: 40, fat: 20)
        XCTAssertTrue(r.isSuspicious)
    }

    func testImpossibleDensityIsFlagged() {
        // 500 kcal packed into 20 g → 25 kcal/g, denser than pure fat.
        let r = NutritionSanity.check(calories: 500, protein: 10, carbs: 10, fat: 5, grams: 20)
        XCTAssertTrue(r.isSuspicious)
    }

    func testMacroHeavierThanFoodIsFlagged() {
        // 50 g protein in a 30 g food can't happen.
        let r = NutritionSanity.check(calories: 200, protein: 50, carbs: 0, fat: 0, grams: 30)
        XCTAssertTrue(r.isSuspicious)
    }

    func testAbsurdOutliersWithoutWeightAreFlagged() {
        XCTAssertTrue(NutritionSanity.check(calories: 8000, protein: 50, carbs: 100, fat: 30).isSuspicious)
        XCTAssertTrue(NutritionSanity.check(calories: 1000, protein: 700, carbs: 10, fat: 10).isSuspicious)
    }

    func testNegativesAreClampedToZero() {
        let r = NutritionSanity.check(calories: 200, protein: -5, carbs: 20, fat: -2, grams: 100)
        XCTAssertEqual(r.protein, 0, accuracy: tol)
        XCTAssertEqual(r.fat, 0, accuracy: tol)
    }

    // MARK: Documented limitation

    /// A *self-consistent* wrong answer — like the 869 kcal / 166 g-protein number that
    /// slipped through in testing — has internally-agreeing macros and a normal density,
    /// so a deterministic guard CANNOT catch it. This is by design: that case is caught by
    /// the human-in-the-loop confirm sheet + easy editing, not by this function. Pinned so
    /// the limitation is explicit; if detection improves later, update this deliberately.
    func test_selfConsistentHallucination_isNotCaught_knownLimitation() {
        let r = NutritionSanity.check(calories: 869, protein: 166, carbs: 41.4, fat: 10.4, grams: 414)
        XCTAssertFalse(r.isSuspicious,
            "Self-consistent values pass the deterministic guard by design — caught by confirm/edit, not here.")
    }
}
