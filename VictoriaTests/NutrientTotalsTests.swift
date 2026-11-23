import XCTest
@testable import Victoria

/// The rule the nutrition-detail feature rests on, as arithmetic: a value that is not known
/// is not counted as zero, and a total says how many foods it covers.
final class NutrientTotalsTests: XCTestCase {

    private let us = Locale(identifier: "en_US")

    private func item(_ values: [Nutrient: Double], quantity: Double = 1)
        -> (detail: NutrientDetail, quantity: Double) {
        (NutrientDetail(values), quantity)
    }

    // MARK: - Totals

    func testEveryFoodStatesIt_totalIsTheSumAndIsComplete() {
        let totals = NutrientTotals([item([.fiber: 4]), item([.fiber: 2.5]), item([.fiber: 0])])
        let fiber = totals[.fiber]
        XCTAssertEqual(fiber.total ?? -1, 6.5, accuracy: 1e-9)
        XCTAssertEqual(fiber.known, 3)
        XCTAssertEqual(fiber.foods, 3)
        XCTAssertTrue(fiber.isComplete)
        XCTAssertNil(fiber.coverageNote, "nothing is missing, so there is nothing to caveat")
    }

    func testNoFoodStatesIt_totalIsNilNotZero() {
        let totals = NutrientTotals([item([:]), item([.fiber: 3])])
        let sodium = totals[.sodium]
        XCTAssertNil(sodium.total, "unknown for every food is unknown, never 0")
        XCTAssertEqual(sodium.known, 0)
        XCTAssertFalse(sodium.isComplete)
        XCTAssertNil(sodium.valueText(locale: us))
        XCTAssertEqual(sodium.coverageNote, "not known for any of 2 foods")
        XCTAssertEqual(sodium.spoken, "Sodium, not known")
    }

    func testSomeFoodsStateIt_totalCountsOnlyThoseAndSaysHowMany() {
        // The owner's example: "fiber 18 g, from 4 of 6 foods".
        let totals = NutrientTotals([
            item([.fiber: 5]), item([.fiber: 6]), item([.fiber: 3]), item([.fiber: 4]),
            item([:]), item([.sodium: 200]),
        ])
        let fiber = totals[.fiber]
        XCTAssertEqual(fiber.total, 18)
        XCTAssertEqual(fiber.known, 4)
        XCTAssertEqual(fiber.foods, 6)
        XCTAssertFalse(fiber.isComplete, "a partial total is never presented as complete")
        XCTAssertEqual(fiber.valueText(locale: us), "18 g")
        XCTAssertEqual(fiber.coverageNote, "from 4 of 6 foods")
        XCTAssertEqual(fiber.spoken, "Fiber, 18 grams, from 4 of 6 foods")
    }

    func testAnExplicitZeroIsKnownAndCounts() {
        let totals = NutrientTotals([item([.addedSugars: 0]), item([:])])
        let added = totals[.addedSugars]
        XCTAssertEqual(added.total, 0, "0 from a label is a value")
        XCTAssertEqual(added.known, 1)
        XCTAssertEqual(added.valueText(locale: us), "0 g")
        XCTAssertEqual(added.coverageNote, "from 1 of 2 foods")
    }

    func testQuantityMultipliesThePerServingValue() {
        let totals = NutrientTotals([item([.sodium: 190, .fiber: 4], quantity: 2.5),
                                     item([.sodium: 10], quantity: 1)])
        XCTAssertEqual(totals[.sodium].total ?? -1, 190 * 2.5 + 10, accuracy: 1e-9)
        XCTAssertEqual(totals[.fiber].total ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(totals[.fiber].coverageNote, "from 1 of 2 foods")
    }

    func testNoFoods_everyLineIsUnknownAndNothingIsComplete() {
        let totals = NutrientTotals([(detail: NutrientDetail, quantity: Double)]())
        XCTAssertEqual(totals.foods, 0)
        XCTAssertTrue(totals.isEmpty)
        for line in totals.lines {
            XCTAssertNil(line.total)
            XCTAssertFalse(line.isComplete)
            XCTAssertNil(line.coverageNote)
        }
    }

    func testOneFood_theNoteReadsForASingleFood() {
        let totals = NutrientTotals([item([.fiber: 3])])
        XCTAssertNil(totals[.fiber].coverageNote)
        XCTAssertEqual(totals[.sodium].coverageNote, "not known for this food")
    }

    func testLinesAreInLabelOrderAndCoverEveryNutrient() {
        let totals = NutrientTotals([item([:])])
        XCTAssertEqual(totals.lines.map(\.nutrient), Nutrient.allCases)
        XCTAssertEqual(Nutrient.allCases, [.saturatedFat, .transFat, .cholesterol, .sodium, .fiber, .sugars,
                                           .addedSugars, .vitaminD, .calcium, .iron, .potassium],
                       "the order of 21 CFR 101.9(c)")
        for nutrient in Nutrient.allCases { XCTAssertEqual(totals[nutrient].nutrient, nutrient) }
    }

    func testDisplayedIsTheCoreRowsPlusWhateverIsKnown() {
        let none = NutrientTotals([item([:])])
        XCTAssertEqual(none.displayed.map(\.nutrient), [.saturatedFat, .sodium, .fiber, .sugars, .addedSugars])
        XCTAssertTrue(none.isEmpty)

        let some = NutrientTotals([item([.calcium: 220, .fiber: 3])])
        XCTAssertEqual(some.displayed.map(\.nutrient),
                       [.saturatedFat, .sodium, .fiber, .sugars, .addedSugars, .calcium])
        XCTAssertFalse(some.isEmpty)
    }

    func testTotalsFromEntriesUseTheEntryQuantity() {
        let a = FoodEntry(name: "Cereal", quantity: 2, calories: 140, detail: NutrientDetail([.fiber: 4, .sodium: 190]))
        let b = FoodEntry(name: "Coffee", calories: 5)
        let totals = NutrientTotals([a, b])
        XCTAssertEqual(totals[.fiber].total, 8)
        XCTAssertEqual(totals[.sodium].total, 380)
        XCTAssertEqual(totals[.sodium].coverageNote, "from 1 of 2 foods")
        XCTAssertNil(totals[.sugars].total)
    }

    // MARK: - Rounding and units

    func testFormatRoundsToOneDecimalBelowTenAndWholeFromTen() {
        XCTAssertEqual(Nutrient.fiber.format(0, locale: us), "0 g")
        XCTAssertEqual(Nutrient.fiber.format(0.04, locale: us), "0 g")
        XCTAssertEqual(Nutrient.fiber.format(0.05, locale: us), "0.1 g")
        XCTAssertEqual(Nutrient.fiber.format(0.5, locale: us), "0.5 g")
        XCTAssertEqual(Nutrient.fiber.format(3, locale: us), "3 g")
        XCTAssertEqual(Nutrient.fiber.format(3.04, locale: us), "3 g")
        XCTAssertEqual(Nutrient.fiber.format(8.86, locale: us), "8.9 g")
        XCTAssertEqual(Nutrient.fiber.format(9.96, locale: us), "10 g", "9.96 is ten, not 10.0 or 9.9")
        XCTAssertEqual(Nutrient.fiber.format(18.4, locale: us), "18 g")
        XCTAssertEqual(Nutrient.fiber.format(18.5, locale: us), "19 g")
    }

    func testFormatUsesEachNutrientsOwnUnitAndGroupsThousands() {
        XCTAssertEqual(Nutrient.sodium.format(1240, locale: us), "1,240 mg")
        XCTAssertEqual(Nutrient.iron.format(0.4, locale: us), "0.4 mg")
        XCTAssertEqual(Nutrient.vitaminD.format(2.5, locale: us), "2.5 mcg")
        XCTAssertEqual(Nutrient.sodium.format(1240, locale: Locale(identifier: "de_DE")), "1.240 mg")
        XCTAssertEqual(Nutrient.fiber.format(2.5, locale: Locale(identifier: "de_DE")), "2,5 g")
    }

    func testUnitsAreTheLabelsUnits() {
        XCTAssertEqual(Nutrient.allCases.filter { $0.unit == .g },
                       [.saturatedFat, .transFat, .fiber, .sugars, .addedSugars])
        XCTAssertEqual(Nutrient.allCases.filter { $0.unit == .mg },
                       [.cholesterol, .sodium, .calcium, .iron, .potassium])
        XCTAssertEqual(Nutrient.allCases.filter { $0.unit == .mcg }, [.vitaminD])
        XCTAssertEqual(Nutrient.Unit.mg.perGram, 1_000)
        XCTAssertEqual(Nutrient.Unit.mcg.perGram, 1_000_000)
    }

    func testArgumentNamesCarryTheUnitAndAreUnique() {
        let names = Nutrient.allCases.map(\.argumentName)
        XCTAssertEqual(Set(names).count, names.count)
        for nutrient in Nutrient.allCases {
            XCTAssertTrue(nutrient.argumentName.hasSuffix("_" + nutrient.unit.rawValue), nutrient.argumentName)
        }
    }

    func testAcceptsZeroAndTheBoundAndRefusesNegativeHugeAndNonFinite() {
        for nutrient in Nutrient.allCases {
            XCTAssertTrue(nutrient.accepts(0))
            XCTAssertTrue(nutrient.accepts(nutrient.plausibleMax))
            XCTAssertFalse(nutrient.accepts(-0.01))
            XCTAssertFalse(nutrient.accepts(nutrient.plausibleMax + 1))
            XCTAssertFalse(nutrient.accepts(.nan))
            XCTAssertFalse(nutrient.accepts(.infinity))
        }
    }

    func testEstimableAndCoreSets() {
        XCTAssertEqual(Nutrient.estimable, [.saturatedFat, .sodium, .fiber, .sugars])
        XCTAssertEqual(Nutrient.core, [.saturatedFat, .sodium, .fiber, .sugars, .addedSugars])
        XCTAssertFalse(Nutrient.estimable.contains(.addedSugars), "added sugars are never estimated")
    }

    // MARK: - The value type

    func testDetailSubscriptReadsAndWritesEveryNutrient() {
        var detail = NutrientDetail()
        XCTAssertTrue(detail.isEmpty)
        for (index, nutrient) in Nutrient.allCases.enumerated() {
            XCTAssertNil(detail[nutrient])
            detail[nutrient] = Double(index) + 0.5
        }
        for (index, nutrient) in Nutrient.allCases.enumerated() {
            XCTAssertEqual(detail[nutrient], Double(index) + 0.5, "\(nutrient) must not alias another field")
        }
        XCTAssertEqual(detail.known, Nutrient.allCases)
        detail[.sodium] = nil
        XCTAssertNil(detail.sodiumMg)
        XCTAssertFalse(detail.known.contains(.sodium))
    }

    func testScaledKeepsUnknownUnknown() {
        let half = NutrientDetail([.fiber: 4, .sodium: 190, .addedSugars: 0]).scaled(by: 0.5)
        XCTAssertEqual(half.fiberG, 2)
        XCTAssertEqual(half.sodiumMg, 95)
        XCTAssertEqual(half.addedSugarsG, 0)
        XCTAssertNil(half.sugarsG, "scaling never creates a value")
        XCTAssertEqual(half.known, [.sodium, .fiber, .addedSugars])
    }

    func testMergingOverlaysOnlyWhatTheOtherStates() {
        let base = NutrientDetail([.fiber: 4, .sodium: 190])
        let merged = base.merging(NutrientDetail([.sodium: 0, .sugars: 12]))
        XCTAssertEqual(merged.fiberG, 4, "what the edit does not mention is kept")
        XCTAssertEqual(merged.sodiumMg, 0, "an explicit 0 overwrites")
        XCTAssertEqual(merged.sugarsG, 12)
        XCTAssertNil(merged.addedSugarsG)
    }

    func testSummaryListsOnlyKnownValuesInLabelOrder() {
        XCTAssertNil(NutrientDetail().summary(locale: us))
        let detail = NutrientDetail([.fiber: 4, .sodium: 190, .saturatedFat: 0.5])
        XCTAssertEqual(detail.summary(locale: us), "saturated fat 0.5 g, sodium 190 mg, fiber 4 g")
        XCTAssertEqual(detail.summary(quantity: 2, locale: us), "saturated fat 1 g, sodium 380 mg, fiber 8 g")
    }

    func testEntryDetailRoundsTripsThroughItsStoredFields() {
        let entry = FoodEntry(name: "Soup", calories: 100)
        XCTAssertTrue(entry.detail.isEmpty, "a new entry knows none of them")
        XCTAssertNil(entry.sodiumMg)
        var detail = NutrientDetail()
        for (index, nutrient) in Nutrient.allCases.enumerated() { detail[nutrient] = Double(index + 1) }
        entry.detail = detail
        XCTAssertEqual(entry.detail, detail)
        XCTAssertEqual(entry.saturatedFatG, 1)
        XCTAssertEqual(entry.potassiumMg, 11)
        entry.detail = NutrientDetail([.fiber: 0])
        XCTAssertEqual(entry.fiberG, 0)
        XCTAssertNil(entry.potassiumMg, "assigning a detail without a value clears it to not known")
    }

    func testReloggedCopyCarriesTheDetailAndGetsItsOwnIdentity() {
        let original = FoodEntry(date: Date(timeIntervalSince1970: 1_000), mealType: .breakfast, name: "Cereal",
                                 servingDescription: "39 g", quantity: 2, calories: 140, proteinG: 5,
                                 carbsG: 29, fatG: 2.5, source: .barcode, barcode: "0016000275287",
                                 photoData: Data([1, 2, 3]), isFavorite: true,
                                 detail: NutrientDetail([.fiber: 4, .sodium: 190, .addedSugars: 0]))
        let day = Date(timeIntervalSince1970: 90_000)
        let copy = original.relogged(on: day, meal: .snack)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.date, day)
        XCTAssertEqual(copy.mealType, .snack)
        XCTAssertEqual(copy.name, "Cereal")
        XCTAssertEqual(copy.quantity, 2)
        XCTAssertEqual(copy.calories, 140)
        XCTAssertEqual(copy.source, .barcode)
        XCTAssertEqual(copy.barcode, "0016000275287")
        XCTAssertTrue(copy.isFavorite)
        XCTAssertNil(copy.photoData, "a repeat does not copy the photo")
        XCTAssertEqual(copy.detail, original.detail)
        XCTAssertEqual(copy.addedSugarsG, 0, "a known zero stays a zero")
        XCTAssertNil(copy.sugarsG, "and a value that was not known stays not known")
    }
}
