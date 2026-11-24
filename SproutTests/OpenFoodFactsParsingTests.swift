import XCTest
@testable import Sprout

/// Tests the Open Food Facts → `FoodHit` parse against real-shaped data. The driving
/// case is the Muscle Milk shake that read wrong in testing: these lock down that a
/// correct lookup returns the LABEL numbers, that per-100 g-only products are scaled to
/// the real serving, and that a missing per-serving macro can no longer silently drop to 0.
final class OpenFoodFactsParsingTests: XCTestCase {

    private let tol = 1.0

    /// The exact nutriments shape Open Food Facts returns for barcode 0876063007160
    /// ("PRO Muscle Milk Protein Shake"), captured from the live API.
    private func muscleMilkProduct(includeServing: Bool = true,
                                   includeProteinServing: Bool = true) -> [String: Any] {
        var nutriments: [String: Any] = [
            "energy-kcal_100g": 53.1400966183575,
            "energy-kcal": 53.1400966183575,
            "proteins_100g": 9.66183574879227,
            "carbohydrates_100g": 2.65700483091787,
            "fat_100g": 0.603864734299517,
        ]
        if includeServing {
            nutriments["energy-kcal_serving"] = 220.0
            if includeProteinServing { nutriments["proteins_serving"] = 40.0 }
            nutriments["carbohydrates_serving"] = 11.0
            nutriments["fat_serving"] = 2.5
        }
        return [
            "product_name": "PRO Muscle Milk Protein Shake",
            "brands": "Muscle Milk",
            "serving_size": "1 bottle (414 ml)",
            "serving_quantity": 414.0,
            "nutriments": nutriments,
        ]
    }

    /// A correct lookup must return the LABEL numbers (220 / 40 / 11 / 2.5), not per-100 g.
    func testPerServingDataReturnsLabelNumbers() {
        let hit = OpenFoodFactsService.parse(product: muscleMilkProduct(), barcode: "0876063007160")
        XCTAssertEqual(hit.calories, 220, accuracy: tol)
        XCTAssertEqual(hit.proteinG, 40, accuracy: tol)
        XCTAssertEqual(hit.carbsG, 11, accuracy: tol)
        XCTAssertEqual(hit.fatG, 2.5, accuracy: tol)
        XCTAssertEqual(hit.servingDescription, "1 bottle (414 ml)")
        XCTAssertFalse(hit.isSuspicious, "Real product data should be plausible")
        XCTAssertEqual(hit.name, "PRO Muscle Milk Protein Shake")
        XCTAssertEqual(hit.brand, "Muscle Milk")
    }

    /// Per-100 g-only data + a declared serving weight must be SCALED to the serving,
    /// so a 414 ml bottle isn't logged as if it were 100 ml.
    func testPer100gScaledToServingWhenServingMacrosAbsent() {
        let product = muscleMilkProduct(includeServing: false)
        let hit = OpenFoodFactsService.parse(product: product, barcode: "x")
        // 53.14 × 4.14 ≈ 220, 9.66 × 4.14 ≈ 40
        XCTAssertEqual(hit.calories, 220, accuracy: 2.0)
        XCTAssertEqual(hit.proteinG, 40, accuracy: 1.0)
        XCTAssertEqual(hit.carbsG, 11, accuracy: 1.0)
        XCTAssertFalse(hit.isSuspicious)
    }

    /// The regression that motivated the rewrite: per-serving calories present but the
    /// per-serving PROTEIN field missing. The old code keyed every macro off one global
    /// "perServing" flag, so protein silently became 0. Now each macro resolves on its
    /// own (here: protein from per-100 g × serving), so it comes back ~40, never 0.
    func testMissingPerServingMacroFallsBackInsteadOfZero() {
        let product = muscleMilkProduct(includeServing: true, includeProteinServing: false)
        let hit = OpenFoodFactsService.parse(product: product, barcode: "x")
        XCTAssertEqual(hit.calories, 220, accuracy: tol)          // per-serving, present
        XCTAssertGreaterThan(hit.proteinG, 30,
            "protein must fall back to per-100g × serving (~40), not collapse to 0")
        XCTAssertEqual(hit.proteinG, 40, accuracy: 1.0)
    }

    /// Per-100 g-only data with NO serving weight: we can't scale, so we return per-100 g
    /// and say so via the basis description.
    func testPer100gWithNoServingWeightUsesHundredGramBasis() {
        var product = muscleMilkProduct(includeServing: false)
        product.removeValue(forKey: "serving_quantity")
        product.removeValue(forKey: "serving_size")
        let hit = OpenFoodFactsService.parse(product: product, barcode: "x")
        XCTAssertEqual(hit.calories, 53.14, accuracy: tol)
        XCTAssertEqual(hit.proteinG, 9.66, accuracy: tol)
        XCTAssertEqual(hit.servingDescription, "100 g")
    }

    /// A genuinely broken community entry (impossible macros) must come back flagged so
    /// the confirm sheet can warn instead of logging it as gospel.
    func testImplausibleProductIsFlagged() {
        let product: [String: Any] = [
            "product_name": "Bad Data Bar",
            "serving_size": "1 bar",
            "nutriments": [
                "energy-kcal_serving": 100.0,   // 100 kcal…
                "proteins_serving": 200.0,      // …but 200 g protein = 800 kcal. impossible.
                "carbohydrates_serving": 5.0,
                "fat_serving": 2.0,
            ],
        ]
        let hit = OpenFoodFactsService.parse(product: product, barcode: "x")
        XCTAssertTrue(hit.isSuspicious)
        XCTAssertNotNil(hit.sanityNote)
    }

    /// String-encoded numbers (Open Food Facts sometimes returns strings) must parse.
    func testStringEncodedNumbersParse() {
        let product: [String: Any] = [
            "product_name": "Stringy",
            "serving_size": "1 serving",
            "serving_quantity": "50",
            "nutriments": [
                "energy-kcal_serving": "120",
                "proteins_serving": "8",
                "carbohydrates_serving": "15",
                "fat_serving": "3",
            ],
        ]
        let hit = OpenFoodFactsService.parse(product: product, barcode: nil)
        XCTAssertEqual(hit.calories, 120, accuracy: tol)
        XCTAssertEqual(hit.proteinG, 8, accuracy: tol)
    }
}
