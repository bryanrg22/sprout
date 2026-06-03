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
}
