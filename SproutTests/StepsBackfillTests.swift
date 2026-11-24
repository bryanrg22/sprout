import XCTest
import SwiftData
@testable import Sprout

/// Pins the step-history fix for the exact bug the user hit: a day frozen at a PARTIAL count
/// (e.g. 5,000 captured when the app was opened mid-day, never finalized) is corrected to its
/// REAL full total once the HealthKit daily backfill runs — and missing days get filled — so the
/// Progress average and the AI review stop under-reporting (5,183 → the true ~10k).
///
/// The HealthKit read itself needs a device; these tests pin the upsert/merge that writes the
/// corrected totals (the part most likely to harbor an off-by-one / duplicate / wrong-day bug).
@MainActor
final class StepsBackfillTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([StepsEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: config))
    }

    func testFrozenPartialDayIsCorrectedAndMissingDayFilled() throws {
        let ctx = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoAgo = cal.date(byAdding: .day, value: -2, to: today)!

        // The bug state: yesterday frozen at a partial 5,000 (opened mid-day, never finalized).
        ctx.insert(StepsEntry(date: yesterday, count: 5000))
        try ctx.save()

        // Apple Health's REAL totals: yesterday was actually 10,000; two days ago (never recorded
        // by the app at all) was 8,000.
        let real: [Date: Int] = [yesterday: 10000, twoAgo: 8000]
        let existing = try ctx.fetch(FetchDescriptor<StepsEntry>())
        let changed = HealthKitService.mergeDailySteps(real, into: ctx, existing: existing)

        XCTAssertEqual(changed, 2, "yesterday corrected + two-days-ago inserted")
        let all = try ctx.fetch(FetchDescriptor<StepsEntry>())
        XCTAssertEqual(all.count, 2, "no duplicate row for yesterday")
        let y = try XCTUnwrap(all.first { cal.isDate($0.date, inSameDayAs: yesterday) })
        XCTAssertEqual(y.count, 10000, "frozen partial day corrected to the real full total")
        let t = try XCTUnwrap(all.first { cal.isDate($0.date, inSameDayAs: twoAgo) })
        XCTAssertEqual(t.count, 8000, "missing day backfilled")
    }

    func testUnchangedDayIsNotRewritten() throws {
        let ctx = try makeContext()
        let today = Calendar.current.startOfDay(for: Date())
        ctx.insert(StepsEntry(date: today, count: 10000))
        try ctx.save()
        let existing = try ctx.fetch(FetchDescriptor<StepsEntry>())
        let changed = HealthKitService.mergeDailySteps([today: 10000], into: ctx, existing: existing)
        XCTAssertEqual(changed, 0, "an already-correct day isn't rewritten")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<StepsEntry>()).count, 1)
    }

    func testEmptyHealthDataIsNoOp() throws {
        let ctx = try makeContext()
        XCTAssertEqual(HealthKitService.mergeDailySteps([:], into: ctx, existing: []), 0)
    }
}
