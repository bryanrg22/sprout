import XCTest
import SwiftData
@testable import Victoria

/// Pins the tracker-data (Fitbit-via-Apple-Health) ingestion added for the Fitbit Air:
/// the sleep/detected-workout MERGE logic (upsert, correct, never duplicate — the same
/// contract as the steps backfill) and the coach-context lines built from the mirrors.
/// The HealthKit reads themselves need a real device; these tests pin everything after.
@MainActor
final class HealthTrackerImportTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SleepEntry.self, DetectedWorkout.self, VitalsEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: config))
    }

    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: .now) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    // MARK: - Sleep merge

    func testSleepMergeInsertsCorrectsAndNeverDuplicates() throws {
        let ctx = try makeContext()
        // The bridge synced a PARTIAL night this morning (5h), later finalized to 7h 20m.
        ctx.insert(SleepEntry(date: today, asleepMinutes: 300, inBedMinutes: 320))
        try ctx.save()

        let real: [Date: HealthKitService.NightSleep] = [
            today: .init(asleep: 440, inBed: 470, deep: 80, rem: 105, core: 255, awake: 12),  // corrected + stages
            day(-1): .init(asleep: 415, inBed: 430),                                          // backfilled, totals-only
        ]
        var existing = try ctx.fetch(FetchDescriptor<SleepEntry>())
        let changed = HealthKitService.mergeDailySleep(real, into: ctx, existing: existing)
        XCTAssertEqual(changed, 2)

        let all = try ctx.fetch(FetchDescriptor<SleepEntry>())
        XCTAssertEqual(all.count, 2, "no duplicate row for the corrected night")
        let t = try XCTUnwrap(all.first { cal.isDate($0.date, inSameDayAs: today) })
        XCTAssertEqual(t.asleepMinutes, 440)
        XCTAssertEqual(t.deepMinutes, 80)
        XCTAssertEqual(t.remMinutes, 105)
        XCTAssertTrue(t.hasStages)
        let y = try XCTUnwrap(all.first { cal.isDate($0.date, inSameDayAs: day(-1)) })
        XCTAssertFalse(y.hasStages, "totals-only source stays stage-less")

        // Re-running with identical data must be a no-op.
        existing = all
        XCTAssertEqual(HealthKitService.mergeDailySleep(real, into: ctx, existing: existing), 0)
    }

    // MARK: - Vitals merge

    func testVitalsMergeUpsertsAndIsIdempotent() throws {
        let ctx = try makeContext()
        let real: [Date: (rhr: Double, hrv: Double)] = [today: (58, 46), day(-1): (60, 0)]
        var existing = try ctx.fetch(FetchDescriptor<VitalsEntry>())
        XCTAssertEqual(HealthKitService.mergeDailyVitals(real, into: ctx, existing: existing), 2)
        existing = try ctx.fetch(FetchDescriptor<VitalsEntry>())
        XCTAssertEqual(HealthKitService.mergeDailyVitals(real, into: ctx, existing: existing), 0)
        // A later sync that fills in yesterday's missing HRV corrects the row in place.
        let corrected: [Date: (rhr: Double, hrv: Double)] = [day(-1): (60, 44)]
        XCTAssertEqual(HealthKitService.mergeDailyVitals(corrected, into: ctx, existing: existing), 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<VitalsEntry>()).count, 2, "no duplicate day")
    }

    // MARK: - Detected-workout merge

    func testDetectedWorkoutsDedupeByHealthKitUUID() throws {
        let ctx = try makeContext()
        ctx.insert(DetectedWorkout(healthKitUUID: "A", date: day(-1), activity: "Running",
                                   durationMinutes: 30, sourceName: "Fitbit"))
        try ctx.save()

        let found = [
            HealthKitService.ImportableWorkout(healthKitUUID: "A", date: day(-1), activity: "Running",
                                               durationMinutes: 30, caloriesBurned: 250, sourceName: "Fitbit"),
            HealthKitService.ImportableWorkout(healthKitUUID: "B", date: today, activity: "Walking",
                                               durationMinutes: 22, caloriesBurned: 90, sourceName: "Fitbit"),
        ]
        let existing = try ctx.fetch(FetchDescriptor<DetectedWorkout>())
        let added = HealthKitService.mergeDetectedWorkouts(found, into: ctx, existing: existing)
        XCTAssertEqual(added, 1, "only the new UUID is inserted")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DetectedWorkout>()).count, 2)
    }

    // MARK: - Coach context lines

    func testSleepLineShowsLastNightStagesAndWeeklyAverage() {
        let sleep = [
            SleepEntry(date: today, asleepMinutes: 444, inBedMinutes: 470,
                       deepMinutes: 80, remMinutes: 105, coreMinutes: 259, awakeMinutes: 12),
            SleepEntry(date: day(-1), asleepMinutes: 420),
            SleepEntry(date: day(-2), asleepMinutes: 400),
        ]
        let line = CoachContext.lastNightSleepLine(sleep)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("7h 24m"), "444 min → 7h 24m, got: \(line!)")
        XCTAssertTrue(line!.contains("1h 20m deep"))
        XCTAssertTrue(line!.contains("1h 45m REM"))
        XCTAssertTrue(line!.contains("average over the last 3 nights"))

        // Totals-only night → no stage parenthetical, line still works.
        let plain = CoachContext.lastNightSleepLine([SleepEntry(date: today, asleepMinutes: 400)])
        XCTAssertNotNil(plain)
        XCTAssertFalse(plain!.contains("deep"))
    }

    func testRecoveryVitalsLine() {
        let vitals = [
            VitalsEntry(date: today, restingHeartRate: 58, hrvMs: 46),
            VitalsEntry(date: day(-1), restingHeartRate: 60, hrvMs: 40),
            VitalsEntry(date: day(-2), restingHeartRate: 62, hrvMs: 43),
        ]
        let line = CoachContext.recoveryVitalsLine(vitals)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("resting HR 58 bpm"))
        XCTAssertTrue(line!.contains("HRV 46 ms"))
        XCTAssertTrue(line!.contains("7-day avg: 60 bpm"))
        // Stale (all older than 3 days) → nil, never presented as current.
        let old = [VitalsEntry(date: day(-5), restingHeartRate: 58, hrvMs: 46)]
        XCTAssertNil(CoachContext.recoveryVitalsLine(old))
    }

    /// Stale data must not masquerade as "last night": with no row for today, no line.
    func testSleepLineNilWithoutLastNight() {
        let old = [SleepEntry(date: day(-3), asleepMinutes: 400)]
        XCTAssertNil(CoachContext.lastNightSleepLine(old))
        XCTAssertNil(CoachContext.lastNightSleepLine([]))
    }

    func testDetectedWorkoutLinesFormatAndCap() {
        let detected = [
            DetectedWorkout(healthKitUUID: "1", date: today, activity: "Running",
                            durationMinutes: 32, caloriesBurned: 280, sourceName: "Fitbit"),
            DetectedWorkout(healthKitUUID: "2", date: day(-1), activity: "Walking",
                            durationMinutes: 20),
        ]
        let lines = CoachContext.detectedWorkoutLines(detected)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("Today — Running, 32 min, 280 kcal (Fitbit)"))
        XCTAssertTrue(lines[1].contains("Yesterday — Walking, 20 min"))
        XCTAssertFalse(lines[1].contains("kcal"), "no kcal shown when the source didn't report it")

        let many = (0..<9).map {
            DetectedWorkout(healthKitUUID: "m\($0)", date: day(-$0), activity: "Walking", durationMinutes: 10)
        }
        let capped = CoachContext.detectedWorkoutLines(many, limit: 5)
        XCTAssertEqual(capped.count, 6)
        XCTAssertTrue(capped.last!.contains("and 4 more"))
    }

    /// The summary threads tracker data through end-to-end (and stays silent without it).
    func testSummaryIncludesTrackerDataWhenPresent() {
        let p = UserProfile()
        let sleep = [SleepEntry(date: today, asleepMinutes: 431)]
        let detected = [DetectedWorkout(healthKitUUID: "x", date: today, activity: "Running",
                                        durationMinutes: 30, sourceName: "Fitbit")]
        let s = CoachContext.summary(profile: p, foods: [], weights: [],
                                     sleep: sleep, detected: detected)
        XCTAssertTrue(s.contains("Last night's sleep: 7h 11m"))
        XCTAssertTrue(s.contains("auto-detected"))
        XCTAssertTrue(s.contains("Running, 30 min"))

        let bare = CoachContext.summary(profile: p, foods: [], weights: [])
        XCTAssertFalse(bare.contains("Last night's sleep"))
        XCTAssertFalse(bare.contains("auto-detected"))
    }
}
