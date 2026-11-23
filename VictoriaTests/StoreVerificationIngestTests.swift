import XCTest
import SwiftData
@testable import Victoria

/// G4, "the store returns what was put in", part (c): the ingest paths are idempotent
/// against the real store.
///
/// The tracker pipes (Apple Health, Google Health) all write through four merge functions:
/// `mergeDailySteps`, `mergeDailySleep`, `mergeDailyVitals`, `mergeDetectedWorkouts`, with
/// `GoogleHealthSync.overlayVitals` and `dedupAgainstExisting` in front of the last two.
/// Every test here runs a delivery the way the app does: read the current rows from the
/// store, merge, save. Then it reads the result through a NEW `ModelContext`.
///
/// For each merge: one delivery and the same delivery twice leave the same rows (count and
/// contents, and the second run changes nothing, not even a row's `id`); a delivery with one
/// changed value updates that row in place and adds none.
///
/// Days are built from an explicit calendar and passed to the merges, so nothing depends on
/// the machine's clock or zone. The existing merge tests (`StepsBackfillTests`,
/// `HealthTrackerImportTests`) run on single-model containers with the device calendar.
@MainActor
final class StoreVerificationIngestTests: XCTestCase {

    private let fx = FixedCalendar()                    // America/Los_Angeles
    private var cal: Calendar { fx.calendar }

    // MARK: - One delivery, as the app runs it

    @discardableResult
    private func deliverSteps(_ perDay: [Date: Int], to container: ModelContainer,
                              calendar: Calendar? = nil) throws -> Int {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<StepsEntry>(sortBy: [SortDescriptor(\.date)]))
        return HealthKitService.mergeDailySteps(perDay, into: context, existing: existing,
                                                calendar: calendar ?? cal)
    }

    @discardableResult
    private func deliverSleep(_ perNight: [Date: HealthKitService.NightSleep],
                              to container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<SleepEntry>())
        return HealthKitService.mergeDailySleep(perNight, into: context, existing: existing, calendar: cal)
    }

    @discardableResult
    private func deliverVitals(_ perDay: [Date: (rhr: Double, hrv: Double)],
                               to container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<VitalsEntry>())
        return HealthKitService.mergeDailyVitals(perDay, into: context, existing: existing, calendar: cal)
    }

    /// The Google pipe's vitals step, as `GoogleHealthSync.refresh` runs it: overlay, then merge.
    @discardableResult
    private func deliverGoogleVitals(_ perDay: [Date: (rhr: Double, hrv: Double)],
                                     to container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<VitalsEntry>())
        let overlaid = GoogleHealthSync.overlayVitals(perDay, onto: existing, calendar: cal)
        return HealthKitService.mergeDailyVitals(overlaid, into: context, existing: existing, calendar: cal)
    }

    /// The workout step both pipes run: cross-pipe dedup, then merge by id.
    @discardableResult
    private func deliverWorkouts(_ found: [HealthKitService.ImportableWorkout],
                                 to container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<DetectedWorkout>())
        let fresh = GoogleHealthSync.dedupAgainstExisting(found, existing: existing)
        return HealthKitService.mergeDetectedWorkouts(fresh, into: context, existing: existing)
    }

    // MARK: - Row contents, read through a new context

    private func stepsRows(_ container: ModelContainer, identity: Bool = false) throws -> [String] {
        try TestStore.fetchAll(StepsEntry.self, in: container, sortBy: [SortDescriptor(\.date)]).map {
            "\($0.date.timeIntervalSinceReferenceDate) \($0.count)" + (identity ? " \($0.id) \($0.createdAt)" : "")
        }
    }

    private func sleepRows(_ container: ModelContainer, identity: Bool = false) throws -> [String] {
        try TestStore.fetchAll(SleepEntry.self, in: container, sortBy: [SortDescriptor(\.date)]).map {
            "\($0.date.timeIntervalSinceReferenceDate) \($0.asleepMinutes) \($0.inBedMinutes) \($0.deepMinutes) "
                + "\($0.remMinutes) \($0.coreMinutes) \($0.awakeMinutes)" + (identity ? " \($0.id) \($0.createdAt)" : "")
        }
    }

    private func vitalsRows(_ container: ModelContainer, identity: Bool = false) throws -> [String] {
        try TestStore.fetchAll(VitalsEntry.self, in: container, sortBy: [SortDescriptor(\.date)]).map {
            "\($0.date.timeIntervalSinceReferenceDate) \($0.restingHeartRate) \($0.hrvMs)"
                + (identity ? " \($0.id) \($0.createdAt)" : "")
        }
    }

    private func workoutRows(_ container: ModelContainer, identity: Bool = false) throws -> [String] {
        try TestStore.fetchAll(DetectedWorkout.self, in: container, sortBy: [SortDescriptor(\.date)]).map {
            "\($0.healthKitUUID) \($0.date.timeIntervalSinceReferenceDate) \($0.activity) \($0.durationMinutes) "
                + "\($0.caloriesBurned) \($0.sourceName)" + (identity ? " \($0.id) \($0.createdAt)" : "")
        }
    }

    // MARK: - Steps backfill

    func test_c_stepsBackfill_sameDeliveryTwiceEqualsOnce_thenAChangedDayUpdatesInPlace() throws {
        let feb18 = fx.at(2026, 2, 18), feb19 = fx.at(2026, 2, 19), feb20 = fx.at(2026, 2, 20)
        let delivery = [feb18: 8_000, feb19: 10_250, feb20: 4_321]

        let once = try TestStore.makeContainer()
        XCTAssertEqual(try deliverSteps(delivery, to: once), 3)

        let twice = try TestStore.makeContainer()
        XCTAssertEqual(try deliverSteps(delivery, to: twice), 3)
        let afterFirst = try stepsRows(twice, identity: true)
        XCTAssertEqual(try deliverSteps(delivery, to: twice), 0, "the second identical delivery must change nothing")

        XCTAssertEqual(try stepsRows(twice, identity: true), afterFirst, "a row was rewritten or replaced")
        XCTAssertEqual(try stepsRows(twice), try stepsRows(once))
        XCTAssertEqual(try stepsRows(twice), [
            "\(feb18.timeIntervalSinceReferenceDate) 8000",
            "\(feb19.timeIntervalSinceReferenceDate) 10250",
            "\(feb20.timeIntervalSinceReferenceDate) 4321",
        ])

        // Today's partial count finalizes: 4,321 becomes 9,876. One row changes, none is added.
        let todayID = try XCTUnwrap(TestStore.fetchAll(StepsEntry.self, in: twice).first { $0.date == feb20 }).id
        XCTAssertEqual(try deliverSteps([feb18: 8_000, feb19: 10_250, feb20: 9_876], to: twice), 1)
        let rows = try TestStore.fetchAll(StepsEntry.self, in: twice, sortBy: [SortDescriptor(\.date)])
        XCTAssertEqual(rows.map(\.count), [8_000, 10_250, 9_876])
        XCTAssertEqual(rows.map(\.date), [feb18, feb19, feb20])
        XCTAssertEqual(rows.last?.id, todayID, "the day was replaced by a new row instead of updated")
    }

    /// The delivery is keyed by any instant of the day; the row is stored at the start of that day.
    func test_c_stepsBackfill_storesTheStartOfDayAndMatchesAnyInstantOfThatDay() throws {
        let container = try TestStore.makeContainer()
        XCTAssertEqual(try deliverSteps([fx.at(2026, 2, 19, 14, 30): 5_000], to: container), 1)
        XCTAssertEqual(try deliverSteps([fx.at(2026, 2, 19, 23, 59, 59): 7_000], to: container), 1)

        let rows = try TestStore.fetchAll(StepsEntry.self, in: container)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.date, fx.at(2026, 2, 19))
        XCTAssertEqual(rows.first?.count, 7_000)
    }

    /// PINS CURRENT BEHAVIOUR, KNOWN RISK. The merges never read the store: they trust the
    /// `existing` array the caller hands them. A caller holding a snapshot taken before an
    /// earlier insert gets a second row for the same day. `RootView.refreshTrackerData`
    /// passes `@Query` arrays and relies on its single-flight flag for this.
    func test_c_pinsCurrentBehaviour_mergeTrustsTheCallersSnapshot_aStaleOneDuplicatesTheDay_knownRisk() throws {
        let container = try TestStore.makeContainer()
        let feb20 = fx.at(2026, 2, 20)
        let context = ModelContext(container)
        let snapshotTakenBeforeAnyInsert = try context.fetch(FetchDescriptor<StepsEntry>())

        XCTAssertEqual(HealthKitService.mergeDailySteps([feb20: 4_321], into: context,
                                                        existing: snapshotTakenBeforeAnyInsert, calendar: cal), 1)
        XCTAssertEqual(HealthKitService.mergeDailySteps([feb20: 4_321], into: context,
                                                        existing: snapshotTakenBeforeAnyInsert, calendar: cal), 1)

        XCTAssertEqual(try TestStore.fetchAll(StepsEntry.self, in: container).map(\.date), [feb20, feb20],
                       "if this is now 1 row the merge reads the store itself: update this test and the ledger")
    }

    /// A trip east and back. Rows are stored at local midnight, which is a different instant
    /// in each zone, and `mergeDailySteps` matches a delivery to "the first row on the same
    /// calendar day". After Los Angeles -> New York -> Los Angeles, the New York row for
    /// 10 February (21:00 on 9 February in Los Angeles) sits on the same Los Angeles day as the
    /// Los Angeles row for 9 February, and every later merge updates only the first of the two.
    func test_c_stepsBackfill_roundTripAcrossTimeZonesKeepsOneRowPerDay() throws {
        let la = FixedCalendar(zone: "America/Los_Angeles"), ny = FixedCalendar(zone: "America/New_York")
        let container = try TestStore.makeContainer()

        // In Los Angeles: 8 and 9 February (no daylight-saving change in this window).
        try deliverSteps([la.at(2026, 2, 8): 8_000, la.at(2026, 2, 9): 9_000], to: container, calendar: la.calendar)
        // In New York: Apple Health now buckets by New York days. 9 February again, then 10 and 11.
        try deliverSteps([ny.at(2026, 2, 9): 9_000, ny.at(2026, 2, 10): 10_000, ny.at(2026, 2, 11): 11_000],
                         to: container, calendar: ny.calendar)
        XCTAssertEqual(try TestStore.count(StepsEntry.self, in: container), 4, "no duplicate while away")
        // Back in Los Angeles: the last days again, bucketed by Los Angeles days.
        try deliverSteps([la.at(2026, 2, 9): 9_000, la.at(2026, 2, 10): 10_000,
                          la.at(2026, 2, 11): 11_000, la.at(2026, 2, 12): 12_000],
                         to: container, calendar: la.calendar)

        let rows = try TestStore.fetchAll(StepsEntry.self, in: container, sortBy: [SortDescriptor(\.date)])
        let perLosAngelesDay = Dictionary(grouping: rows) { la.calendar.startOfDay(for: $0.date) }
        XCTExpectFailure("""
            HealthKitSteps.swift:93 (and the same match in HealthKitSleepWorkouts.swift:121 and :211): \
            rows are stored at local midnight and matched by calendar day in the current zone, so after a \
            trip east and back one Los Angeles day holds two StepsEntry rows.
            """) {
            XCTAssertEqual(perLosAngelesDay.values.map(\.count).max(), 1,
                           "a calendar day holds more than one StepsEntry row")
            XCTAssertEqual(rows.count, 5, "8, 9, 10, 11 and 12 February")
        }
    }

    // MARK: - Sleep

    func test_c_sleepMerge_sameDeliveryTwiceEqualsOnce_thenACorrectedNightUpdatesInPlace() throws {
        let feb19 = fx.at(2026, 2, 19), feb20 = fx.at(2026, 2, 20)
        let delivery: [Date: HealthKitService.NightSleep] = [
            feb19: .init(asleep: 432, inBed: 465, deep: 81, rem: 104, core: 247, awake: 19),
            feb20: .init(asleep: 401, inBed: 430, deep: 70, rem: 95, core: 236, awake: 22),
        ]

        let once = try TestStore.makeContainer()
        XCTAssertEqual(try deliverSleep(delivery, to: once), 2)

        let twice = try TestStore.makeContainer()
        XCTAssertEqual(try deliverSleep(delivery, to: twice), 2)
        let afterFirst = try sleepRows(twice, identity: true)
        XCTAssertEqual(try deliverSleep(delivery, to: twice), 0)

        XCTAssertEqual(try sleepRows(twice, identity: true), afterFirst)
        XCTAssertEqual(try sleepRows(twice), try sleepRows(once))
        XCTAssertEqual(try sleepRows(twice), [
            "\(feb19.timeIntervalSinceReferenceDate) 432 465 81 104 247 19",
            "\(feb20.timeIntervalSinceReferenceDate) 401 430 70 95 236 22",
        ])

        // The tracker finalizes last night later in the day: every one of the six numbers moves.
        let nightID = try XCTUnwrap(TestStore.fetchAll(SleepEntry.self, in: twice).first { $0.date == feb20 }).id
        let corrected: [Date: HealthKitService.NightSleep] = [
            feb19: .init(asleep: 432, inBed: 465, deep: 81, rem: 104, core: 247, awake: 19),
            feb20: .init(asleep: 455, inBed: 480, deep: 88, rem: 110, core: 257, awake: 14),
        ]
        XCTAssertEqual(try deliverSleep(corrected, to: twice), 1)
        XCTAssertEqual(try sleepRows(twice), [
            "\(feb19.timeIntervalSinceReferenceDate) 432 465 81 104 247 19",
            "\(feb20.timeIntervalSinceReferenceDate) 455 480 88 110 257 14",
        ])
        XCTAssertEqual(try TestStore.fetchAll(SleepEntry.self, in: twice).first { $0.date == feb20 }?.id, nightID)
    }

    // MARK: - Vitals

    func test_c_vitalsMerge_sameDeliveryTwiceEqualsOnce_thenAChangedDayUpdatesInPlace() throws {
        let feb19 = fx.at(2026, 2, 19), feb20 = fx.at(2026, 2, 20)
        let delivery: [Date: (rhr: Double, hrv: Double)] = [feb19: (58, 46.5), feb20: (60.5, 0)]

        let once = try TestStore.makeContainer()
        XCTAssertEqual(try deliverVitals(delivery, to: once), 2)

        let twice = try TestStore.makeContainer()
        XCTAssertEqual(try deliverVitals(delivery, to: twice), 2)
        let afterFirst = try vitalsRows(twice, identity: true)
        XCTAssertEqual(try deliverVitals(delivery, to: twice), 0)

        XCTAssertEqual(try vitalsRows(twice, identity: true), afterFirst)
        XCTAssertEqual(try vitalsRows(twice), try vitalsRows(once))
        XCTAssertEqual(try vitalsRows(twice), [
            "\(feb19.timeIntervalSinceReferenceDate) 58.0 46.5",
            "\(feb20.timeIntervalSinceReferenceDate) 60.5 0.0",
        ])

        // Today's HRV arrives later: 0 becomes 44.
        let todayID = try XCTUnwrap(TestStore.fetchAll(VitalsEntry.self, in: twice).first { $0.date == feb20 }).id
        XCTAssertEqual(try deliverVitals([feb19: (58, 46.5), feb20: (60.5, 44)], to: twice), 1)
        XCTAssertEqual(try vitalsRows(twice), [
            "\(feb19.timeIntervalSinceReferenceDate) 58.0 46.5",
            "\(feb20.timeIntervalSinceReferenceDate) 60.5 44.0",
        ])
        XCTAssertEqual(try TestStore.fetchAll(VitalsEntry.self, in: twice).first { $0.date == feb20 }?.id, todayID)
    }

    /// The Google pipe sends half-days (HRV before resting HR). Through the store: the half
    /// that is 0 keeps the value another pipe already saved, and repeating the delivery is a no-op.
    func test_c_googleVitalsOverlay_halfDayKeepsTheStoredHalf_andIsIdempotent() throws {
        let feb20 = fx.at(2026, 2, 20)
        let container = try TestStore.makeContainer()
        XCTAssertEqual(try deliverVitals([feb20: (61, 0)], to: container), 1)           // Apple Health: RHR only

        XCTAssertEqual(try deliverGoogleVitals([feb20: (0, 47.5)], to: container), 1)   // Google: HRV only
        XCTAssertEqual(try vitalsRows(container), ["\(feb20.timeIntervalSinceReferenceDate) 61.0 47.5"])

        XCTAssertEqual(try deliverGoogleVitals([feb20: (0, 47.5)], to: container), 0)
        XCTAssertEqual(try vitalsRows(container), ["\(feb20.timeIntervalSinceReferenceDate) 61.0 47.5"])

        // A full Google day wins both halves, still in the same single row.
        XCTAssertEqual(try deliverGoogleVitals([feb20: (59, 49)], to: container), 1)
        XCTAssertEqual(try vitalsRows(container), ["\(feb20.timeIntervalSinceReferenceDate) 59.0 49.0"])
    }

    // MARK: - Detected workouts

    private func runWorkout(_ id: String, minutes: Int = 31, kcal: Double = 288.5) -> HealthKitService.ImportableWorkout {
        .init(healthKitUUID: id, date: fx.at(2026, 2, 19, 6, 40), activity: "Running",
              durationMinutes: minutes, caloriesBurned: kcal, sourceName: "Fitbit")
    }

    private func walkWorkout(_ id: String) -> HealthKitService.ImportableWorkout {
        .init(healthKitUUID: id, date: fx.at(2026, 2, 20, 12, 5), activity: "Walking",
              durationMinutes: 22, caloriesBurned: 90, sourceName: "Fitbit")
    }

    func test_c_detectedWorkoutMerge_sameDeliveryTwiceEqualsOnce_andAChangedValueAddsNoRow() throws {
        let delivery = [runWorkout("ghealth:exercise/1"), walkWorkout("ghealth:exercise/2")]
        let runStart = fx.at(2026, 2, 19, 6, 40).timeIntervalSinceReferenceDate
        let walkStart = fx.at(2026, 2, 20, 12, 5).timeIntervalSinceReferenceDate

        let once = try TestStore.makeContainer()
        XCTAssertEqual(try deliverWorkouts(delivery, to: once), 2)

        let twice = try TestStore.makeContainer()
        XCTAssertEqual(try deliverWorkouts(delivery, to: twice), 2)
        let afterFirst = try workoutRows(twice, identity: true)
        XCTAssertEqual(try deliverWorkouts(delivery, to: twice), 0)

        XCTAssertEqual(try workoutRows(twice, identity: true), afterFirst)
        XCTAssertEqual(try workoutRows(twice), try workoutRows(once))
        XCTAssertEqual(try workoutRows(twice), [
            "ghealth:exercise/1 \(runStart) Running 31 288.5 Fitbit",
            "ghealth:exercise/2 \(walkStart) Walking 22 90.0 Fitbit",
        ])

        // The run comes back under the same id with corrected numbers: still two rows.
        try deliverWorkouts([runWorkout("ghealth:exercise/1", minutes: 34, kcal: 301), walkWorkout("ghealth:exercise/2")], to: twice)
        XCTAssertEqual(try TestStore.count(DetectedWorkout.self, in: twice), 2, "a changed workout was duplicated")
        XCTAssertEqual(try TestStore.fetchAll(DetectedWorkout.self, in: twice).map(\.healthKitUUID).sorted(),
                       ["ghealth:exercise/1", "ghealth:exercise/2"])
    }

    /// The other three merges correct a row whose values changed. This one is insert-only: a
    /// workout that comes back under the same id with a corrected duration or calories keeps
    /// the values of its first delivery.
    func test_c_detectedWorkoutMerge_aChangedValueUpdatesTheStoredRow() throws {
        let container = try TestStore.makeContainer()
        try deliverWorkouts([runWorkout("ghealth:exercise/1")], to: container)
        try deliverWorkouts([runWorkout("ghealth:exercise/1", minutes: 34, kcal: 301)], to: container)

        let rows = try TestStore.fetchAll(DetectedWorkout.self, in: container)
        XCTAssertEqual(rows.count, 1)
        XCTExpectFailure("""
            HealthKitSleepWorkouts.swift:297: mergeDetectedWorkouts skips every id it already knows, so a \
            workout re-delivered with corrected values is never updated (the row keeps 31 min / 288.5 kcal).
            """) {
            XCTAssertEqual(rows.first?.durationMinutes, 34)
            XCTAssertEqual(rows.first?.caloriesBurned, 301)
        }
    }

    /// One session seen through both pipes (a `ghealth:` id and an Apple Health UUID, start
    /// times 5 minutes apart, 31 and 33 minutes long) is one row, whichever pipe came first,
    /// and stays one row when both pipes deliver again.
    func test_c_detectedWorkouts_sameSessionThroughBothPipesIsOneRowInEitherOrder() throws {
        let google = runWorkout("ghealth:exercise/1")
        let apple = HealthKitService.ImportableWorkout(
            healthKitUUID: "5E0C6F2A-0000-4000-8000-00000000AAAA", date: fx.at(2026, 2, 19, 6, 45),
            activity: "Running", durationMinutes: 33, caloriesBurned: 295, sourceName: "Health bridge")

        for (first, second) in [(google, apple), (apple, google)] {
            let container = try TestStore.makeContainer()
            XCTAssertEqual(try deliverWorkouts([first], to: container), 1)
            XCTAssertEqual(try deliverWorkouts([second], to: container), 0, "the other pipe's copy must be dropped")
            XCTAssertEqual(try deliverWorkouts([first], to: container), 0)
            XCTAssertEqual(try deliverWorkouts([second], to: container), 0)

            let rows = try TestStore.fetchAll(DetectedWorkout.self, in: container)
            XCTAssertEqual(rows.map(\.healthKitUUID), [first.healthKitUUID], "the first pipe to deliver wins")
            XCTAssertEqual(rows.first?.durationMinutes, first.durationMinutes)
        }
    }

    // MARK: - The four merges leave every other table alone

    func test_c_trackerMergesWriteOnlyTheirOwnTables() throws {
        let container = try TestStore.makeContainer()
        let feb20 = fx.at(2026, 2, 20)
        try deliverSteps([feb20: 4_321], to: container)
        try deliverSleep([feb20: .init(asleep: 401, inBed: 430)], to: container)
        try deliverVitals([feb20: (60.5, 44)], to: container)
        try deliverWorkouts([walkWorkout("ghealth:exercise/2")], to: container)

        var expected = Dictionary(uniqueKeysWithValues: AppSchema.schema.entities.map { ($0.name, 0) })
        expected["StepsEntry"] = 1
        expected["SleepEntry"] = 1
        expected["VitalsEntry"] = 1
        expected["DetectedWorkout"] = 1
        XCTAssertEqual(try TestStore.countsByEntity(in: container), expected)
    }
}
