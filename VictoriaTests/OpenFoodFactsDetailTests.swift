import XCTest
@testable import Victoria

/// The Open Food Facts → `FoodHit.detail` mapping, against responses recorded from the live
/// API (`Fixtures/OpenFoodFacts/`, with the barcodes and the request in its README).
///
/// What has to hold: the per-serving value is used when the product has one, per-100 g is
/// scaled by the serving weight exactly as the calories are, every amount arrives in grams
/// and is stored in the label's unit (mg, mcg), sodium falls back to salt ÷ 2.5 and says
/// so, and a nutrient the product does not list is `nil`, never 0.
final class OpenFoodFactsDetailTests: XCTestCase {

    private func product(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OpenFoodFacts/\(name).json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let body = try XCTUnwrap(object as? [String: Any], file: file, line: line)
        XCTAssertEqual(body["status"] as? Int, 1, "a recorded hit", file: file, line: line)
        return try XCTUnwrap(body["product"] as? [String: Any], file: file, line: line)
    }

    private func hit(_ name: String) throws -> OpenFoodFactsService.FoodHit {
        OpenFoodFactsService.parse(product: try product(name), barcode: nil)
    }

    /// The same product with some `nutriments` keys taken out, for a shape no recorded
    /// product had. The values that remain are still the recorded ones.
    private func product(_ name: String, removing shouldRemove: (String) -> Bool) throws -> [String: Any] {
        var p = try product(name)
        var n = try XCTUnwrap(p["nutriments"] as? [String: Any])
        for key in n.keys where shouldRemove(key) { n[key] = nil }
        p["nutriments"] = n
        return p
    }

    // MARK: - Per serving

    func testPerServingValuesAreTheLabelNumbers() throws {
        // The box: 140 kcal, sat fat 0.5 g, trans 0 g, cholesterol 0 mg, sodium 190 mg,
        // fiber 4 g, total sugars 2 g, added sugars 0 g, per 39 g.
        let hit = try hit("cereal-per-serving")
        XCTAssertEqual(hit.calories, 140, accuracy: 0.5)
        XCTAssertEqual(hit.servingDescription, "39g")
        let d = hit.detail
        XCTAssertEqual(d.saturatedFatG ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(d.transFatG, 0)
        XCTAssertEqual(d.cholesterolMg, 0)
        XCTAssertEqual(d.sodiumMg ?? -1, 190, accuracy: 1e-6, "0.19 g on the wire is 190 mg")
        XCTAssertEqual(d.fiberG, 4)
        XCTAssertEqual(d.sugarsG, 2)
        XCTAssertEqual(d.addedSugarsG, 0, "a listed zero is a zero")
        XCTAssertFalse(hit.sodiumFromSalt, "sodium is listed, so it is used as it is")
        XCTAssertNil(hit.sodiumNote)
    }

    func testNutrientsTheProductDoesNotListAreNotKnown() throws {
        let cereal = try hit("cereal-per-serving").detail
        // This product's entry has no vitamin or mineral keys at all.
        XCTAssertNil(cereal.vitaminDMcg)
        XCTAssertNil(cereal.calciumMg)
        XCTAssertNil(cereal.ironMg)
        XCTAssertNil(cereal.potassiumMg)
        XCTAssertEqual(cereal.known, [.saturatedFat, .transFat, .cholesterol, .sodium, .fiber, .sugars, .addedSugars])

        // A diet soda's entry lists no fiber, sugars or fats: those are unknown, not 0,
        // even though the true amounts are almost certainly zero.
        let soda = try hit("diet-soda-few-keys")
        XCTAssertEqual(soda.calories, 0)
        XCTAssertNil(soda.detail.fiberG)
        XCTAssertNil(soda.detail.sugarsG)
        XCTAssertNil(soda.detail.saturatedFatG)
        XCTAssertNil(soda.detail.transFatG)
        XCTAssertNil(soda.detail.cholesterolMg)
        XCTAssertEqual(soda.detail.addedSugarsG, 0, "the one it does list as zero")
        XCTAssertEqual(soda.detail.sodiumMg ?? -1, 40.1, accuracy: 1e-6)
        XCTAssertEqual(soda.detail.known, [.sodium, .addedSugars])
    }

    // MARK: - Per 100 g

    func testPer100gOnlyWithNoServingIsReportedPer100g() throws {
        let hit = try hit("spread-per-100g-only")
        XCTAssertEqual(hit.servingDescription, "100 g")
        XCTAssertEqual(hit.calories, 539, accuracy: 0.5)
        let d = hit.detail
        XCTAssertEqual(d.saturatedFatG ?? -1, 10.6, accuracy: 1e-9)
        XCTAssertEqual(d.sugarsG ?? -1, 56.3, accuracy: 1e-9)
        XCTAssertEqual(d.addedSugarsG ?? -1, 52.13, accuracy: 1e-9)
        XCTAssertEqual(d.fiberG, 0)
        XCTAssertEqual(d.sodiumMg ?? -1, 42.8, accuracy: 1e-6, "0.0428 g per 100 g")
        XCTAssertNil(d.transFatG)
        XCTAssertNil(d.cholesterolMg)
    }

    func testPer100gIsScaledByTheServingWeightLikeTheCalories() throws {
        // Derived from the recorded cereal: every `_serving` value removed, so only the
        // per-100 g values and the 39 g serving weight remain.
        let p = try product("cereal-per-serving") { $0.hasSuffix("_serving") }
        let hit = OpenFoodFactsService.parse(product: p, barcode: nil)
        XCTAssertEqual(hit.calories, 358.974358974359 * 0.39, accuracy: 0.01, "the existing calorie scaling")
        let d = hit.detail
        XCTAssertEqual(d.fiberG ?? -1, 10.2564102564103 * 0.39, accuracy: 1e-6)
        XCTAssertEqual(d.fiberG ?? -1, 4.0, accuracy: 0.001)
        XCTAssertEqual(d.sugarsG ?? -1, 2.0, accuracy: 0.001)
        XCTAssertEqual(d.saturatedFatG ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(d.sodiumMg ?? -1, 190, accuracy: 0.01)
        XCTAssertEqual(d.addedSugarsG, 0)
    }

    func testEachNutrientResolvesOnItsOwn() throws {
        // Only fiber loses its `_serving` value: it alone falls back to per-100 g × 39 g,
        // and it does not become 0 or drag the others with it.
        let p = try product("cereal-per-serving") { $0 == "fiber_serving" }
        let d = OpenFoodFactsService.parse(product: p, barcode: nil).detail
        XCTAssertEqual(d.fiberG ?? -1, 4.0, accuracy: 0.001)
        XCTAssertEqual(d.sugarsG, 2)
        XCTAssertEqual(d.sodiumMg ?? -1, 190, accuracy: 1e-6)
    }

    // MARK: - Salt and sodium

    func testSodiumComesFromSaltWhenOnlySaltIsListedAndSaysSo() throws {
        // Derived from the recorded cereal with its sodium keys removed (every recorded
        // product had both). Salt 0.475 g per serving ÷ 2.5 = 0.19 g = 190 mg.
        let p = try product("cereal-per-serving") { $0.hasPrefix("sodium") }
        let hit = OpenFoodFactsService.parse(product: p, barcode: nil)
        XCTAssertEqual(hit.detail.sodiumMg ?? -1, 190, accuracy: 1e-6)
        XCTAssertTrue(hit.sodiumFromSalt)
        XCTAssertEqual(hit.sodiumNote, "Sodium worked out from the listed salt (salt ÷ 2.5).")

        let draft = FoodDraft(from: hit, meal: .breakfast, source: .barcode)
        XCTAssertEqual(draft.notes, "Sodium worked out from the listed salt (salt ÷ 2.5).",
                       "the confirm sheet says which figure the sodium came from")
    }

    func testSaltFallbackAlsoScalesPer100g() throws {
        let p = try product("cereal-per-serving") { $0.hasPrefix("sodium") || $0.hasSuffix("_serving") }
        let hit = OpenFoodFactsService.parse(product: p, barcode: nil)
        // salt_100g 1.21794871794872 g × 0.39 ÷ 2.5 × 1000
        XCTAssertEqual(hit.detail.sodiumMg ?? -1, 190, accuracy: 0.01)
        XCTAssertTrue(hit.sodiumFromSalt)
    }

    func testListedSodiumWinsOverSalt() throws {
        // Recorded as received: both keys present and in the 2.5 ratio.
        let n = try XCTUnwrap(try product("cereal-per-serving")["nutriments"] as? [String: Any])
        let salt = try XCTUnwrap(n["salt_serving"] as? Double)
        let sodium = try XCTUnwrap(n["sodium_serving"] as? Double)
        XCTAssertEqual(salt / sodium, OpenFoodFactsService.saltPerSodium, accuracy: 1e-9)
        XCTAssertFalse(try hit("cereal-per-serving").sodiumFromSalt)
    }

    func testNeitherSaltNorSodiumIsNotKnown() throws {
        let p = try product("cereal-per-serving") { $0.hasPrefix("sodium") || $0.hasPrefix("salt") }
        let hit = OpenFoodFactsService.parse(product: p, barcode: nil)
        XCTAssertNil(hit.detail.sodiumMg)
        XCTAssertFalse(hit.sodiumFromSalt)
        XCTAssertNil(FoodDraft(from: hit, meal: .snack, source: .barcode).notes)
    }

    // MARK: - Grams on the wire, the label's unit in the app

    func testMineralsAndVitaminDAreConvertedFromGrams() throws {
        // iron_serving 0.0001 g, potassium_serving 0.11 g, calcium 0, vitamin D 0.
        let d = try hit("crisps-minerals").detail
        XCTAssertEqual(d.ironMg ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(d.potassiumMg ?? -1, 110, accuracy: 1e-6)
        XCTAssertEqual(d.calciumMg, 0)
        XCTAssertEqual(d.vitaminDMcg, 0)
        XCTAssertEqual(d.sodiumMg ?? -1, 152, accuracy: 1e-6)
        XCTAssertEqual(d.transFatG ?? -1, 0.142, accuracy: 1e-9)
        XCTAssertEqual(d.saturatedFatG ?? -1, 2.55, accuracy: 1e-9)
        XCTAssertEqual(d.known, Nutrient.allCases, "this product lists the whole label")
    }

    func testCholesterolAndAddedSugarsAboveZero() throws {
        // cholesterol_serving 0.01 g = 10 mg; added sugars 2 g; sodium 0.67 g = 670 mg.
        let d = try hit("soup-cholesterol").detail
        XCTAssertEqual(d.cholesterolMg ?? -1, 10, accuracy: 1e-6)
        XCTAssertEqual(d.addedSugarsG, 2)
        XCTAssertEqual(d.sugarsG, 4)
        XCTAssertEqual(d.sodiumMg ?? -1, 670, accuracy: 1e-6)
        XCTAssertEqual(d.ironMg ?? -1, 0.7, accuracy: 1e-9)
        XCTAssertEqual(d.potassiumMg ?? -1, 440, accuracy: 1e-6)
    }

    func testVitaminDInMicrograms() {
        // 2 mcg is 0.000002 g on the wire.
        let p: [String: Any] = ["product_name": "Fortified milk", "serving_quantity": 240.0,
                                "nutriments": ["energy-kcal_serving": 150.0, "vitamin-d_serving": 0.000002]]
        XCTAssertEqual(OpenFoodFactsService.parse(product: p, barcode: nil).detail.vitaminDMcg ?? -1, 2, accuracy: 1e-9)
    }

    func testTheEnteredValueAndUnitKeysAreIgnored() {
        // `_value` / `_unit` are what a contributor typed (here milligrams); only the
        // normalised `_serving` figure, in grams, is read.
        let p: [String: Any] = ["product_name": "Crackers",
                                "nutriments": ["energy-kcal_serving": 120.0, "sodium_serving": 0.23,
                                               "sodium_value": 230.0, "sodium_unit": "mg", "sodium": 230.0]]
        XCTAssertEqual(OpenFoodFactsService.parse(product: p, barcode: nil).detail.sodiumMg ?? -1, 230, accuracy: 1e-6)
    }

    func testNumbersSentAsStringsAndIntegersAreRead() {
        let p: [String: Any] = ["product_name": "Bar",
                                "nutriments": ["energy-kcal_serving": "200", "fiber_serving": "3.5", "sugars_serving": 7]]
        let d = OpenFoodFactsService.parse(product: p, barcode: nil).detail
        XCTAssertEqual(d.fiberG, 3.5)
        XCTAssertEqual(d.sugarsG, 7)
    }

    func testABrokenFigureIsLeftNotKnown() {
        // A negative amount, and sodium of 80 g a serving: bad community entries.
        let p: [String: Any] = ["product_name": "Bad entry",
                                "nutriments": ["energy-kcal_serving": 100.0, "fiber_serving": -3.0,
                                               "sodium_serving": 80.0, "sugars_serving": 5.0]]
        let hit = OpenFoodFactsService.parse(product: p, barcode: nil)
        XCTAssertNil(hit.detail.fiberG)
        XCTAssertNil(hit.detail.sodiumMg)
        XCTAssertEqual(hit.detail.sugarsG, 5)
        XCTAssertFalse(hit.sodiumFromSalt)
    }

    func testNoNutrimentsAtAllKnowsNothing() {
        let hit = OpenFoodFactsService.parse(product: ["product_name": "Mystery"], barcode: nil)
        XCTAssertTrue(hit.detail.isEmpty)
    }

    // MARK: - Into the draft

    func testDraftFromAHitCarriesTheDetail() throws {
        let hit = try hit("cereal-per-serving")
        let draft = FoodDraft(from: hit, meal: .breakfast, source: .barcode)
        XCTAssertEqual(draft.detail, hit.detail)
        XCTAssertNil(draft.notes, "plausible numbers and listed sodium leave no note")
    }

    func testEveryKeyStemIsMapped() {
        XCTAssertEqual(Set(OpenFoodFactsService.detailKeys.keys), Set(Nutrient.allCases))
    }
}
