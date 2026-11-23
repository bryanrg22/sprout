import XCTest
import SwiftData
@testable import Victoria

/// The backup is the data-safety net, so prove it actually captures logged data and
/// round-trips through JSON (encode → file → decode) intact.
@MainActor
final class DataExportTests: XCTestCase {
    func testBackupCapturesLoggedDataAndRoundTrips() throws {
        let schema = Schema([UserProfile.self, FoodEntry.self, WeightEntry.self,
                             WaterEntry.self, StepsEntry.self, WorkoutEntry.self, ChatMessage.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        ctx.insert(FoodEntry(name: "Apple", quantity: 2, calories: 95, proteinG: 1, carbsG: 25, fatG: 0))
        ctx.insert(WaterEntry(amountOz: 16))
        try ctx.save()

        guard let url = DataExport.makeBackup(context: ctx, profile: UserProfile()) else {
            return XCTFail("backup file was not created")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(DataExport.Backup.self, from: Data(contentsOf: url))

        XCTAssertEqual(backup.food.count, 1)
        let food = try XCTUnwrap(backup.food.first)
        XCTAssertEqual(food.name, "Apple")
        XCTAssertEqual(food.quantity, 2, accuracy: 0.001)
        XCTAssertEqual(backup.water.count, 1)
        XCTAssertNotNil(backup.profile, "profile summary should be included")
        XCTAssertFalse(backup.appVersion.isEmpty)
    }

    /// The label nutrients are in the backup, and "not known" survives it: a nutrient an
    /// entry does not state has no key in the file at all, and a stated 0 is written as 0.
    func testBackupCarriesLabelNutrientsAndKeepsNotKnownApartFromZero() throws {
        let schema = Schema([UserProfile.self, FoodEntry.self, WeightEntry.self,
                             WaterEntry.self, StepsEntry.self, WorkoutEntry.self, ChatMessage.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        var full = NutrientDetail()
        for (index, nutrient) in Nutrient.allCases.enumerated() { full[nutrient] = Double(index) + 0.5 }
        ctx.insert(FoodEntry(name: "Label food", quantity: 2, calories: 140, detail: full))
        ctx.insert(FoodEntry(name: "Partial food", calories: 300,
                             detail: NutrientDetail([.fiber: 4, .addedSugars: 0])))
        ctx.insert(FoodEntry(name: "Plain food", calories: 95))
        try ctx.save()

        let url = try XCTUnwrap(DataExport.makeBackup(context: ctx, profile: nil))
        let data = try Data(contentsOf: url)

        // Through the typed model.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(DataExport.Backup.self, from: data)
        let byName = Dictionary(uniqueKeysWithValues: backup.food.map { ($0.name, $0) })
        let label = try XCTUnwrap(byName["Label food"])
        XCTAssertEqual(label.saturatedFatG, 0.5)
        XCTAssertEqual(label.transFatG, 1.5)
        XCTAssertEqual(label.cholesterolMg, 2.5)
        XCTAssertEqual(label.sodiumMg, 3.5)
        XCTAssertEqual(label.fiberG, 4.5)
        XCTAssertEqual(label.sugarsG, 5.5)
        XCTAssertEqual(label.addedSugarsG, 6.5)
        XCTAssertEqual(label.vitaminDMcg, 7.5)
        XCTAssertEqual(label.calciumMg, 8.5)
        XCTAssertEqual(label.ironMg, 9.5)
        XCTAssertEqual(label.potassiumMg, 10.5)
        XCTAssertEqual(label.quantity, 2, "per serving, with the quantity beside it, like the calories")
        let partial = try XCTUnwrap(byName["Partial food"])
        XCTAssertEqual(partial.fiberG, 4)
        XCTAssertEqual(partial.addedSugarsG, 0)
        XCTAssertNil(partial.sodiumMg)

        // Through the raw file, which is what another tool would read.
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(raw["food"] as? [[String: Any]])
        let rawByName = Dictionary(uniqueKeysWithValues: rows.map { (($0["name"] as? String) ?? "", $0) })
        let keys = ["saturatedFatG", "transFatG", "cholesterolMg", "sodiumMg", "fiberG", "sugarsG",
                    "addedSugarsG", "vitaminDMcg", "calciumMg", "ironMg", "potassiumMg"]
        let plain = try XCTUnwrap(rawByName["Plain food"])
        for key in keys {
            XCTAssertNil(plain[key], "\(key) is not known, so the file has no such key (not 0, not null)")
            XCTAssertNotNil(try XCTUnwrap(rawByName["Label food"])[key], "\(key) is exported when known")
        }
        let rawPartial = try XCTUnwrap(rawByName["Partial food"])
        XCTAssertEqual(rawPartial["addedSugarsG"] as? Double, 0, "a stated zero is written as 0")
        XCTAssertEqual(rawPartial["fiberG"] as? Double, 4)
        XCTAssertNil(rawPartial["sodiumMg"])
        XCTAssertEqual(plain["calories"] as? Double, 95, "the existing columns are unchanged")
    }
}
