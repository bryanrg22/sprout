import XCTest
@testable import Sprout

/// The rows of a Nutrition Facts panel below the macros, read from OCR text. The inputs are
/// the lines a text scanner returns for a real panel: the FDA's own sample label, the same
/// label with the misreads OCR makes, older and shorter labels, and the lines that look like
/// rows but are not. What it must never do is turn a row it could not read into 0.
final class NutritionLabelDetailParserTests: XCTestCase {

    private func parse(_ lines: [String]) -> NutrientDetail { NutritionLabelDetailParser.parse(lines) }

    /// The FDA's sample label, one printed row per line, as a scanner returns it.
    private let sampleLabel = [
        "Nutrition Facts",
        "8 servings per container",
        "Serving size 2/3 cup (55g)",
        "Amount per serving",
        "Calories 230",
        "% Daily Value*",
        "Total Fat 8g 10%",
        "Saturated Fat 1g 5%",
        "Trans Fat 0g",
        "Cholesterol 0mg 0%",
        "Sodium 160mg 7%",
        "Total Carbohydrate 37g 13%",
        "Dietary Fiber 4g 14%",
        "Total Sugars 12g",
        "Includes 10g Added Sugars 20%",
        "Protein 3g",
        "Vitamin D 2mcg 10%",
        "Calcium 260mg 20%",
        "Iron 8mg 45%",
        "Potassium 240mg 6%",
        "* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.",
    ]

    private func assertSampleValues(_ d: NutrientDetail, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(d.saturatedFatG, 1, file: file, line: line)
        XCTAssertEqual(d.transFatG, 0, file: file, line: line)
        XCTAssertEqual(d.cholesterolMg, 0, file: file, line: line)
        XCTAssertEqual(d.sodiumMg, 160, file: file, line: line)
        XCTAssertEqual(d.fiberG, 4, file: file, line: line)
        XCTAssertEqual(d.sugarsG, 12, file: file, line: line)
        XCTAssertEqual(d.addedSugarsG, 10, file: file, line: line)
        XCTAssertEqual(d.vitaminDMcg, 2, file: file, line: line)
        XCTAssertEqual(d.calciumMg, 260, file: file, line: line)
        XCTAssertEqual(d.ironMg, 8, file: file, line: line)
        XCTAssertEqual(d.potassiumMg, 240, file: file, line: line)
    }

    // MARK: - A whole panel

    func testReadsEveryRowOfTheSampleLabel() {
        assertSampleValues(parse(sampleLabel))
    }

    func testReadsTheSameLabelThroughTypicalMisreads() {
        // O for 0, l for 1, S for 5, "meg" for mcg, "rng" for mg, and no space before a unit.
        let misread = [
            "Nutrition Facts",
            "Serving size 2/3 cup (55g)",
            "Calories 23O",
            "% Daily Value*",
            "Total Fat 8g 1O%",
            "Saturated Fat lg S%",
            "Trans Fat Og",
            "Cholesterol Omg O%",
            "Sodium 16Omg 7%",
            "Total Carbohydrate 37g 13%",
            "Dietary Fiber 4g l4%",
            "Total Sugars l2g",
            "lncludes 1Og Added Sugars 2O%",
            "Protein 3g",
            "Vitamin D 2meg 1O%",
            "Calcium 26Omg 2O%",
            "Iron 8rng 4S%",
            "Potassium 24Omg 6%",
        ]
        assertSampleValues(parse(misread))
    }

    func testAnOCRItemHoldingSeveralPrintedLinesIsSplit() {
        let blocks = [
            "Saturated Fat 1g 5%\nTrans Fat 0g\nCholesterol 0mg 0%\nSodium 160mg 7%",
            "Dietary Fiber 4g 14%\nTotal Sugars 12g\nIncludes 10g Added Sugars 20%",
            "Vitamin D 2mcg 10%\nCalcium 260mg 20%\nIron 8mg 45%\nPotassium 240mg 6%",
        ]
        assertSampleValues(parse(blocks))
    }

    func testRowsMergedOntoOneLineKeepTheirOwnAmounts() {
        let d = parse(["Saturated Fat 1g 5% Trans Fat 0g",
                       "Total Sugars 12g Includes 10g Added Sugars 20%",
                       "Vitamin D 2mcg 10% Calcium 260mg 20% Iron 8mg 45% Potassium 240mg 6%"])
        XCTAssertEqual(d.saturatedFatG, 1)
        XCTAssertEqual(d.transFatG, 0)
        XCTAssertEqual(d.sugarsG, 12, "total sugars must not take the added-sugars amount beside it")
        XCTAssertEqual(d.addedSugarsG, 10)
        XCTAssertEqual(d.vitaminDMcg, 2)
        XCTAssertEqual(d.calciumMg, 260)
        XCTAssertEqual(d.ironMg, 8)
        XCTAssertEqual(d.potassiumMg, 240)
    }

    func testTwoColumnLabelTakesThePerServingColumn() {
        let d = parse(["Sodium 160mg 7% 320mg 14%", "Dietary Fiber 4g 14% 8g 29%"])
        XCTAssertEqual(d.sodiumMg, 160)
        XCTAssertEqual(d.fiberG, 4)
    }

    // MARK: - Wordings

    func testCommonWordingsOfEachRow() {
        let d = parse(["Sat. Fat 2.5g 13%", "Trans Fat 0g", "Cholest. 5mg 2%", "Sodium 95mg",
                       "Fibre 3g", "Sugars 9g", "Incl. 4g Added Sugars 8%",
                       "Vit. D 0mcg 0%", "Calcium 20mg 2%", "Iron 1.8mg 10%", "Potas. 150mg 4%"])
        XCTAssertEqual(d.saturatedFatG, 2.5)
        XCTAssertEqual(d.transFatG, 0)
        XCTAssertEqual(d.cholesterolMg, 5)
        XCTAssertEqual(d.sodiumMg, 95)
        XCTAssertEqual(d.fiberG, 3)
        XCTAssertEqual(d.sugarsG, 9)
        XCTAssertEqual(d.addedSugarsG, 4)
        XCTAssertEqual(d.vitaminDMcg, 0)
        XCTAssertEqual(d.calciumMg, 20)
        XCTAssertEqual(d.ironMg, 1.8)
        XCTAssertEqual(d.potassiumMg, 150)
    }

    func testAddedSugarsWithTheAmountAfterTheName() {
        XCTAssertEqual(parse(["Added Sugars 7g 14%"]).addedSugarsG, 7)
    }

    func testAddedSugarsRowDoesNotCountAsTotalSugars() {
        let d = parse(["Includes 10g Added Sugars 20%"])
        XCTAssertEqual(d.addedSugarsG, 10)
        XCTAssertNil(d.sugarsG, "the label did not give a total-sugars row we could read")
    }

    // MARK: - Rows that are not the row they resemble

    func testOtherFatsFibersAndSugarAlcoholAreNotMistaken() {
        let d = parse(["Polyunsaturated Fat 2g", "Monounsaturated Fat 4g", "Unsaturated Fat 6g",
                       "Soluble Fiber 1g", "Insoluble Fiber 2g", "Sugar Alcohol 5g"])
        XCTAssertNil(d.saturatedFatG)
        XCTAssertNil(d.fiberG)
        XCTAssertNil(d.sugarsG)
        XCTAssertTrue(d.isEmpty)
    }

    func testAPercentDailyValueIsNeverReadAsAnAmount() {
        // An older panel that states its vitamins and minerals only as percentages.
        let d = parse(["Vitamin A 10% • Vitamin C 0%", "Calcium 2% • Iron 6%", "Vitamin D 10%", "Potassium 4%"])
        XCTAssertNil(d.calciumMg)
        XCTAssertNil(d.ironMg)
        XCTAssertNil(d.vitaminDMcg)
        XCTAssertNil(d.potassiumMg)
        XCTAssertTrue(d.isEmpty)
    }

    func testIngredientListAndFootnoteAreNotRows() {
        let d = parse([
            "INGREDIENTS: Whole grain oats, sugar, salt, calcium carbonate 2mg, iron 4mg, vitamin D3 1mcg.",
            "* The % Daily Value tells you how much a nutrient in a serving contributes to a daily diet. Sodium 2300mg.",
            "2,000 calories a day is used for general nutrition advice. Potassium 4700mg",
        ])
        XCTAssertTrue(d.isEmpty, "nothing here is a row of the panel")
    }

    func testWordsThatContainARowNameDoNotMatch() {
        let d = parse(["Environment friendly 5g pouch", "Transport weight 300g", "Decalcium 4mg"])
        XCTAssertTrue(d.isEmpty)
    }

    // MARK: - Amounts

    func testAmountOnTheLineAfterItsName() {
        let d = parse(["Sodium", "160mg", "7%", "Dietary Fiber", "4g"])
        XCTAssertEqual(d.sodiumMg, 160)
        XCTAssertEqual(d.fiberG, 4)
    }

    func testANameAloneIsNotGivenTheNextRowsAmount() {
        // The amount for "Sodium" was lost; the next line is a different row.
        let d = parse(["Sodium", "Total Carbohydrate 37g 13%"])
        XCTAssertNil(d.sodiumMg)
    }

    func testUnitLostButPercentStillThere() {
        let d = parse(["Sodium 160 7%", "Dietary Fiber 4 14%", "Total Sugars 12"])
        XCTAssertEqual(d.sodiumMg, 160)
        XCTAssertEqual(d.fiberG, 4)
        XCTAssertEqual(d.sugarsG, 12)
    }

    func testLessThanIsReadAsHalfTheBound() {
        let d = parse(["Cholesterol less than 5mg 1%", "Dietary Fiber <1g", "Total Sugars Less than 1g"])
        XCTAssertEqual(d.cholesterolMg, 2.5)
        XCTAssertEqual(d.fiberG, 0.5)
        XCTAssertEqual(d.sugarsG, 0.5)
    }

    func testOtherUnitsAreConverted() {
        XCTAssertEqual(parse(["Sodium 0.16g"]).sodiumMg, 160)
        XCTAssertEqual(parse(["Vitamin D 80 IU 20%"]).vitaminDMcg, 2)
        XCTAssertEqual(parse(["Vitamin D 2µg"]).vitaminDMcg, 2)
        XCTAssertEqual(parse(["Vitamin D 2.5ug"]).vitaminDMcg, 2.5)
        XCTAssertEqual(parse(["Calcium 0.26g"]).calciumMg, 260)
        XCTAssertNil(parse(["Calcium 300 IU"]).calciumMg, "only vitamin D is ever stated in IU")
    }

    func testDecimalAndThousandsSeparators() {
        XCTAssertEqual(parse(["Saturated Fat 0.5g"]).saturatedFatG, 0.5)
        XCTAssertEqual(parse(["Saturated Fat 0,5g"]).saturatedFatG, 0.5, "a decimal comma")
        XCTAssertEqual(parse(["Saturated Fat O.5g"]).saturatedFatG, 0.5, "O read for the leading zero")
        XCTAssertEqual(parse(["Potassium 1,240mg 26%"]).potassiumMg, 1240, "a thousands comma")
        XCTAssertEqual(parse(["Sodium 1 240 mg"]).sodiumMg, 240,
                       "a split number cannot be rejoined; this is the known limit, not a goal")
    }

    func testAnImplausibleAmountIsLeftNotKnown() {
        XCTAssertNil(parse(["Dietary Fiber 4000g"]).fiberG)
        XCTAssertNil(parse(["Sodium 160000mg"]).sodiumMg)
        XCTAssertNil(parse(["Iron 800mg"]).ironMg)
    }

    func testARowWithNoReadableAmountIsNotKnownNotZero() {
        let d = parse(["Sodium mg 7%", "Dietary Fiber g", "Total Sugars", "Protein 3g"])
        XCTAssertNil(d.sodiumMg)
        XCTAssertNil(d.fiberG)
        XCTAssertNil(d.sugarsG)
    }

    func testAPrintedZeroIsZero() {
        let d = parse(["Trans Fat 0g", "Cholesterol 0mg 0%", "Includes 0g Added Sugars 0%"])
        XCTAssertEqual(d.transFatG, 0)
        XCTAssertEqual(d.cholesterolMg, 0)
        XCTAssertEqual(d.addedSugarsG, 0)
    }

    // MARK: - "Not a significant source of …"

    func testNotASignificantSourceDeclaresTheRowsItNames() {
        // A simplified label (a soda): few rows, then the sentence, wrapped over two lines.
        let d = parse([
            "Calories 140", "Total Fat 0g 0%", "Sodium 45mg 2%", "Total Carbohydrate 39g 14%",
            "Total Sugars 39g", "Includes 39g Added Sugars 78%", "Protein 0g",
            "Not a significant source of saturated fat, trans fat, cholesterol, dietary",
            "fiber, vitamin D, calcium, iron and potassium.",
        ])
        XCTAssertEqual(d.sodiumMg, 45)
        XCTAssertEqual(d.sugarsG, 39)
        XCTAssertEqual(d.addedSugarsG, 39)
        for nutrient in [Nutrient.saturatedFat, .transFat, .cholesterol, .vitaminD, .calcium, .iron, .potassium] {
            XCTAssertEqual(d[nutrient], 0, "\(nutrient) is declared insignificant, which the label rule defines as zero")
        }
        XCTAssertEqual(d.fiberG, 0.5, "for fiber the rule's threshold is 'less than 1 gram', read as half the bound")
        XCTAssertEqual(d.known, Nutrient.allCases)
    }

    func testTheSentenceDoesNotOverwriteARowAndStopsAtItsFullStop() {
        let d = parse(["Dietary Fiber 2g 7%",
                       "Not a significant source of dietary fiber or trans fat. Calcium and iron were not measured."])
        XCTAssertEqual(d.fiberG, 2, "the row that was read wins")
        XCTAssertEqual(d.transFatG, 0)
        XCTAssertNil(d.calciumMg, "named after the full stop, so not part of the declaration")
        XCTAssertNil(d.ironMg)
    }

    // MARK: - Nothing to read

    func testNoLinesAndNoRowsGiveAnEmptyDetail() {
        XCTAssertTrue(parse([]).isEmpty)
        XCTAssertTrue(parse(["", "   "]).isEmpty)
        XCTAssertTrue(parse(["Nutrition Facts", "Calories 230", "Total Fat 8g", "Total Carbohydrate 37g", "Protein 3g"]).isEmpty)
    }

    // MARK: - Through the scanner's parser

    func testTheScannedDraftCarriesMacrosAndTheRowsBelowThem() throws {
        let draft = try XCTUnwrap(ScanView.parseNutritionLabel(sampleLabel))
        XCTAssertEqual(draft.calories, 230)
        XCTAssertEqual(draft.fatG, 8)
        XCTAssertEqual(draft.carbsG, 37)
        XCTAssertEqual(draft.proteinG, 3)
        XCTAssertEqual(draft.source, .barcode)
        assertSampleValues(draft.detail)
    }

    func testAMacrosOnlyLabelLeavesTheDetailNotKnown() throws {
        let draft = try XCTUnwrap(ScanView.parseNutritionLabel(["Calories 120", "Total Fat 2g", "Total Carb 20g", "Protein 5g"]))
        XCTAssertEqual(draft.calories, 120)
        XCTAssertTrue(draft.detail.isEmpty)
    }

    func testWithoutCaloriesThereIsStillNoDraft() {
        XCTAssertNil(ScanView.parseNutritionLabel(["Sodium 160mg 7%", "Dietary Fiber 4g"]),
                     "the existing rule: no calories, keep scanning")
    }
}
