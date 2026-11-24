import XCTest
import SwiftData
@testable import Sprout

/// The coach's `log_food` and `edit_food` with the label nutrients: optional arguments where
/// absent means NOT KNOWN, an explicit 0 means zero, and a negative or implausible number
/// refuses the call. Also the two other places a saved entry's detail leaves the model
/// layer: the line the coach reads about each food, and the add/edit sheet's text fields.
@MainActor
final class CoachFoodDetailToolTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([UserProfile.self, FoodEntry.self, WaterEntry.self, WeightEntry.self, CoachMemory.self,
                             WorkoutEntry.self, WorkoutSession.self, ExerciseEntry.self, CoachPlan.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: config))
    }

    /// A fixture user ("Sam"): a lean-gain profile, so nothing here depends on a loss floor.
    private func profile() -> UserProfile {
        let p = UserProfile()
        p.name = "Sam"
        p.sex = .male
        p.pace = .leanGain
        p.startWeightLbs = 150
        p.goalWeightLbs = 165
        return p
    }

    private struct UnexpectedParse: Error {}

    private let bowl: [String: Any] = ["name": "Chicken bowl", "meal": "lunch", "calories": 600,
                                       "protein_g": 45, "carbs_g": 50, "fat_g": 20]

    private func parse(_ name: CoachTools.Name, _ input: [String: Any],
                       todaysFoods: [FoodEntry] = []) -> CoachTools.ParseResult {
        CoachTools.parse(name: name.rawValue, input: input, profile: profile(), todaysFoods: todaysFoods)
    }

    private func request(_ name: CoachTools.Name, _ input: [String: Any], todaysFoods: [FoodEntry] = [],
                         file: StaticString = #filePath, line: UInt = #line) throws -> CoachTools.ParsedRequest {
        switch parse(name, input, todaysFoods: todaysFoods) {
        case .ok(let request): return request
        case .invalid(let why):
            XCTFail("expected .ok, got .invalid: \(why)", file: file, line: line)
            throw UnexpectedParse()
        }
    }

    private func invalidReason(_ name: CoachTools.Name, _ input: [String: Any], todaysFoods: [FoodEntry] = [],
                               file: StaticString = #filePath, line: UInt = #line) -> String {
        switch parse(name, input, todaysFoods: todaysFoods) {
        case .ok(let request):
            XCTFail("expected .invalid, got .ok: \(request.confirmSummary)", file: file, line: line)
            return ""
        case .invalid(let why): return why
        }
    }

    private func schema(_ name: CoachTools.Name) throws -> [String: Any] {
        let tool = try XCTUnwrap(CoachTools.schemas(for: profile()).first { ($0["name"] as? String) == name.rawValue })
        return try XCTUnwrap(tool["input_schema"] as? [String: Any])
    }

    // MARK: - Schemas

    func testBothToolsOfferEveryNutrientAsAnOptionalNumber() throws {
        for tool in [CoachTools.Name.logFood, .editFood] {
            let schema = try schema(tool)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            let required = try XCTUnwrap(schema["required"] as? [String])
            for nutrient in Nutrient.allCases {
                let property = try XCTUnwrap(properties[nutrient.argumentName] as? [String: Any],
                                             "\(tool.rawValue) lacks \(nutrient.argumentName)")
                XCTAssertEqual(property["type"] as? String, "number")
                XCTAssertFalse(required.contains(nutrient.argumentName),
                               "\(nutrient.argumentName) must stay optional: absent is how the model says not known")
                let description = try XCTUnwrap(property["description"] as? String)
                XCTAssertTrue(description.contains(nutrient.unit.rawValue), "the unit is stated: \(description)")
            }
        }
        XCTAssertEqual(try XCTUnwrap(try schema(.logFood)["required"] as? [String]),
                       ["name", "meal", "calories", "protein_g", "carbs_g", "fat_g"], "unchanged")
        XCTAssertEqual(try XCTUnwrap(try schema(.editFood)["required"] as? [String]), ["name"], "unchanged")
    }

    func testLogFoodSaysWhichNutrientsMayBeEstimated() throws {
        let properties = try XCTUnwrap(try schema(.logFood)["properties"] as? [String: Any])
        for nutrient in Nutrient.allCases {
            let description = try XCTUnwrap((properties[nutrient.argumentName] as? [String: Any])?["description"] as? String)
            if Nutrient.estimable.contains(nutrient) {
                XCTAssertTrue(description.contains("work it out from the food"), nutrient.argumentName)
                XCTAssertTrue(description.contains("Never send 0 as a placeholder"), nutrient.argumentName)
            } else {
                XCTAssertTrue(description.contains("ONLY when the user gives the number"), nutrient.argumentName)
            }
        }
    }

    // MARK: - log_food: parse

    func testAbsentArgumentsAreNotKnown() throws {
        guard case .logFood(let draft) = try request(.logFood, bowl).action else { return XCTFail("wrong action") }
        XCTAssertTrue(draft.detail.isEmpty, "the call named none of them, so none is known")
        XCTAssertEqual(draft.calories, 600, "and the rest of the call is untouched")
    }

    func testSuppliedArgumentsAreStoredAndAnExplicitZeroIsAZero() throws {
        var input = bowl
        input["fiber_g"] = 6
        input["sodium_mg"] = 880.5
        input["added_sugars_g"] = 0
        input["trans_fat_g"] = 0.0
        guard case .logFood(let draft) = try request(.logFood, input).action else { return XCTFail("wrong action") }
        XCTAssertEqual(draft.detail.fiberG, 6)
        XCTAssertEqual(draft.detail.sodiumMg, 880.5)
        XCTAssertEqual(draft.detail.addedSugarsG, 0, "0 was sent, so 0 is known")
        XCTAssertEqual(draft.detail.transFatG, 0)
        XCTAssertNil(draft.detail.sugarsG, "not sent, so not known")
        XCTAssertNil(draft.detail.saturatedFatG)
        XCTAssertEqual(draft.detail.known, [.transFat, .sodium, .fiber, .addedSugars])
    }

    func testEveryNutrientArgumentIsRead() throws {
        var input = bowl
        for (index, nutrient) in Nutrient.allCases.enumerated() { input[nutrient.argumentName] = Double(index + 1) }
        guard case .logFood(let draft) = try request(.logFood, input).action else { return XCTFail("wrong action") }
        for (index, nutrient) in Nutrient.allCases.enumerated() {
            XCTAssertEqual(draft.detail[nutrient], Double(index + 1), nutrient.argumentName)
        }
    }

    func testNullAndNonNumbersAreNotKnownAndNumericStringsAreRead() throws {
        var input = bowl
        input["fiber_g"] = NSNull()
        input["sugars_g"] = "unknown"
        input["sodium_mg"] = "450"
        guard case .logFood(let draft) = try request(.logFood, input).action else { return XCTFail("wrong action") }
        XCTAssertNil(draft.detail.fiberG)
        XCTAssertNil(draft.detail.sugarsG, "a word is not a number, and is not a zero either")
        XCTAssertEqual(draft.detail.sodiumMg, 450)
    }

    func testANegativeNutrientRefusesTheCall() {
        var input = bowl
        input["fiber_g"] = -2
        let why = invalidReason(.logFood, input)
        XCTAssertTrue(why.contains("Fiber"), why)
        XCTAssertTrue(why.contains("Nothing was logged"), why)
    }

    func testAnImplausibleNutrientRefusesTheCall() {
        // 2,000 g of sodium: milligrams and grams confused by a factor of a thousand.
        var input = bowl
        input["sodium_mg"] = 2_000_000
        let why = invalidReason(.logFood, input)
        XCTAssertTrue(why.contains("Sodium has to be between 0 and 50000 mg"), why)
        XCTAssertTrue(why.contains("Nothing was logged"), why)
    }

    func testTheBoundItselfIsAccepted() throws {
        var input = bowl
        input["sodium_mg"] = Nutrient.sodium.plausibleMax
        guard case .logFood(let draft) = try request(.logFood, input).action else { return XCTFail("wrong action") }
        XCTAssertEqual(draft.detail.sodiumMg, 50_000)
    }

    // MARK: - log_food: apply

    func testApplyWritesKnownValuesAndLeavesTheRestNil() throws {
        let ctx = try makeContext()
        var input = bowl
        input["quantity"] = 2
        input["fiber_g"] = 6
        input["sodium_mg"] = 880
        input["added_sugars_g"] = 0
        let message = CoachTools.apply(try request(.logFood, input), to: profile(), context: ctx)
        let entry = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.fiberG, 6, "per serving, like the calories")
        XCTAssertEqual(entry.sodiumMg, 880)
        XCTAssertEqual(entry.addedSugarsG, 0)
        XCTAssertNil(entry.sugarsG)
        XCTAssertNil(entry.saturatedFatG)
        XCTAssertNil(entry.potassiumMg)
        XCTAssertTrue(message.contains("Also recorded: sodium 1760 mg, fiber 12 g, added sugars 0 g."),
                      "the model is told what was stored, for the amount logged: \(message)")
    }

    func testApplyWithoutAnyDetailSaysNothingAboutIt() throws {
        let ctx = try makeContext()
        let message = CoachTools.apply(try request(.logFood, bowl), to: profile(), context: ctx)
        let entry = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertTrue(entry.detail.isEmpty)
        XCTAssertFalse(message.contains("Also recorded"), message)
    }

    // MARK: - edit_food

    private func seed(_ ctx: ModelContext, detail: NutrientDetail = NutrientDetail()) -> FoodEntry {
        let entry = FoodEntry(date: .now, mealType: .breakfast, name: "Granola", calories: 210,
                              proteinG: 5, carbsG: 32, fatG: 7, detail: detail)
        ctx.insert(entry)
        try? ctx.save()
        return entry
    }

    func testEditSetsOnlyTheNutrientsItNames() throws {
        let ctx = try makeContext()
        let entry = seed(ctx, detail: NutrientDetail([.fiber: 4, .sodium: 95]))
        let req = try request(.editFood, ["name": "Granola", "sugars_g": 11, "sodium_mg": 0], todaysFoods: [entry])
        let message = CoachTools.apply(req, to: profile(), context: ctx)
        XCTAssertEqual(entry.sugarsG, 11)
        XCTAssertEqual(entry.sodiumMg, 0, "an explicit 0 replaces 95")
        XCTAssertEqual(entry.fiberG, 4, "not named, so kept")
        XCTAssertNil(entry.addedSugarsG, "not named and not known before, so still not known")
        XCTAssertEqual(entry.calories, 210, "the macros were not part of the edit")
        XCTAssertTrue(message.contains("Set per serving: sodium 0 mg, total sugars 11 g."), message)
    }

    func testAnEditOfOnlyANutrientIsAChange() throws {
        let ctx = try makeContext()
        let entry = seed(ctx)
        guard case .editFood(_, let changes) = try request(.editFood, ["name": "Granola", "fiber_g": 5],
                                                           todaysFoods: [entry]).action else {
            return XCTFail("wrong action")
        }
        XCTAssertTrue(changes.hasAnyChange)
        XCTAssertEqual(changes.detail.known, [.fiber])
        XCTAssertNil(changes.calories)
    }

    func testAnEditThatNamesNothingIsStillRefused() throws {
        let ctx = try makeContext()
        let entry = seed(ctx)
        let why = invalidReason(.editFood, ["name": "Granola", "fiber_g": NSNull()], todaysFoods: [entry])
        XCTAssertTrue(why.contains("Nothing was changed"), why)
    }

    func testEditRefusesANegativeOrImplausibleNutrient() throws {
        let ctx = try makeContext()
        let entry = seed(ctx, detail: NutrientDetail([.fiber: 4]))
        var why = invalidReason(.editFood, ["name": "Granola", "fiber_g": -1], todaysFoods: [entry])
        XCTAssertTrue(why.contains("Nothing was changed"), why)
        why = invalidReason(.editFood, ["name": "Granola", "iron_mg": 9_000], todaysFoods: [entry])
        XCTAssertTrue(why.contains("Iron has to be between 0 and 500 mg"), why)
        XCTAssertEqual(entry.fiberG, 4, "a refused edit writes nothing")
    }

    func testUndoPutsNotKnownBack() throws {
        let ctx = try makeContext()
        let entry = seed(ctx, detail: NutrientDetail([.fiber: 4]))
        let req = try request(.editFood, ["name": "Granola", "fiber_g": 6, "sodium_mg": 120], todaysFoods: [entry])
        let applied = CoachTools.applyReturningUndo(req, to: profile(), context: ctx)
        XCTAssertEqual(entry.fiberG, 6)
        XCTAssertEqual(entry.sodiumMg, 120)
        try XCTUnwrap(applied.undo)()
        XCTAssertEqual(entry.fiberG, 4, "the old value is back")
        XCTAssertNil(entry.sodiumMg, "and what was not known before is not known again, not 0")
    }

    func testUndoOfALoggedFoodWithDetailRemovesIt() throws {
        let ctx = try makeContext()
        var input = bowl
        input["fiber_g"] = 6
        let applied = CoachTools.applyReturningUndo(try request(.logFood, input), to: profile(), context: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).count, 1)
        try XCTUnwrap(applied.undo)()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).count, 0)
    }

    // MARK: - What the coach reads about a food

    func testItemLineShowsKnownNutrientsScaledAndLeavesUnknownOut() {
        let entry = FoodEntry(date: .now, mealType: .breakfast, name: "Cereal", servingDescription: "39 g",
                              quantity: 2, calories: 140, proteinG: 5, carbsG: 29, fatG: 2.5,
                              detail: NutrientDetail([.fiber: 4, .sodium: 190, .addedSugars: 0]))
        let line = CoachContext.itemLines([entry]).joined()
        XCTAssertTrue(line.contains("also: sodium 380 mg, fiber 8 g, added sugars 0 g"), line)
        XCTAssertFalse(line.contains("saturated fat"), "a nutrient that is not known is not mentioned: \(line)")
        XCTAssertFalse(line.contains("total sugars"), line)
        XCTAssertTrue(line.contains("serving: 39 g"), "the existing detail is still there: \(line)")
    }

    func testItemLineForAFoodWithNoDetailIsUnchanged() {
        let entry = FoodEntry(date: .now, mealType: .lunch, name: "Soup", calories: 180, proteinG: 9, carbsG: 20, fatG: 6)
        let lines = CoachContext.itemLines([entry])
        XCTAssertEqual(lines, ["Soup (Lunch) — 180 kcal, 9g P / 20g C / 6g F"])
    }

    // MARK: - The add/edit sheet's fields

    func testAnEmptyFieldIsNotKnownAndZeroIsZero() {
        XCTAssertNil(FoodDetailInput.value("", for: .fiber), "blank is not known")
        XCTAssertNil(FoodDetailInput.value("   ", for: .fiber))
        XCTAssertEqual(FoodDetailInput.value("0", for: .fiber), 0, "0 typed is a zero")
        XCTAssertEqual(FoodDetailInput.value("4", for: .fiber), 4)
        XCTAssertEqual(FoodDetailInput.value(" 2.5 ", for: .fiber), 2.5)
        XCTAssertEqual(FoodDetailInput.value("2,5", for: .fiber), 2.5, "a decimal pad that types a comma")
    }

    func testInvalidTextIsFlaggedAndNeverSaved() {
        for text in ["abc", "-1", "1.2.3", "5000"] {
            XCTAssertTrue(FoodDetailInput.isInvalid(text, for: .fiber), text)
            XCTAssertNil(FoodDetailInput.value(text, for: .fiber), text)
        }
        XCTAssertFalse(FoodDetailInput.isInvalid("", for: .fiber), "blank is allowed: it means not known")
        XCTAssertFalse(FoodDetailInput.isInvalid("0", for: .fiber))
        XCTAssertTrue(FoodDetailInput.hasInvalid([.fiber: "4", .sodium: "x"]))
        XCTAssertFalse(FoodDetailInput.hasInvalid([.fiber: "4", .sodium: ""]))
    }

    func testFieldsRoundTripADetailWithoutInventingZeros() {
        let detail = NutrientDetail([.fiber: 4, .saturatedFat: 0.5, .sodium: 190, .addedSugars: 0, .iron: 1.13])
        let text = FoodDetailInput.text(for: detail)
        XCTAssertEqual(text[.fiber], "4")
        XCTAssertEqual(text[.saturatedFat], "0.5")
        XCTAssertEqual(text[.addedSugars], "0", "a known zero shows as 0")
        XCTAssertEqual(text[.iron], "1.13")
        XCTAssertNil(text[.sugars], "a nutrient that is not known starts as an empty field")
        XCTAssertEqual(FoodDetailInput.detail(from: text), detail)

        // Clearing a field makes it not known again; it does not become 0.
        var cleared = text
        cleared[.sodium] = ""
        XCTAssertNil(FoodDetailInput.detail(from: cleared).sodiumMg)
        XCTAssertTrue(FoodDetailInput.detail(from: [:]).isEmpty, "a manual add that touches none of them knows none")
    }

    func testTheEditSheetStartsFromTheEntrysDetail() {
        let entry = FoodEntry(name: "Cereal", calories: 140, detail: NutrientDetail([.fiber: 4, .addedSugars: 0]))
        let draft = AddFoodSheet.draft(from: entry)
        XCTAssertEqual(draft.detail, entry.detail)
        XCTAssertTrue(FoodDraft().detail.isEmpty, "a new manual draft knows none of them")
    }
}
