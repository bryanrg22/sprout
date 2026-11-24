import XCTest
import SwiftData
@testable import Sprout

/// G4, "the store returns what was put in", parts (a), (d), (e) and (f).
///
/// (a) The full production schema (`AppSchema`) opens in memory and registers exactly the
///     `@Model` classes that exist in the source tree.
/// (d) The queries the screens depend on return exact, hand-computed values from one fixed
///     fixture. "Now" is 18:30 on Friday 20 February 2026 in Los Angeles; every date is built
///     from that explicit calendar, and rows are inserted out of order so that an order in a
///     result comes from the store's sort, not from the insertion.
/// (e) A deleted row is gone from a new context, and deleting one model's rows leaves the
///     other nineteen models alone.
/// (f) Two profiles in one store: which one the app's gate takes today (pinned, known risk).
///
/// The screens fetch a whole table with `@Query` and filter in memory with the device
/// calendar. Where the app has the same filter as a function that takes the calendar and the
/// date (`CoachContext.todaysFoods`, `todaysWaterOz`, `StreakCalculator`, `TrendCalculator`),
/// the test calls it; where the filter is a private property of a view, the test states the
/// same expression with the fixed calendar and names the view.
///
/// Part (b) is in `StoreVerificationRoundTripTests.swift` and
/// `StoreVerificationRoundTripTrackerBuddyTests.swift`; (c) in `StoreVerificationIngestTests.swift`.
@MainActor
final class StoreVerificationTests: XCTestCase {

    private let fx = FixedCalendar()                    // America/Los_Angeles
    private var cal: Calendar { fx.calendar }
    /// The fixture's "now": Friday 20 February 2026, 18:30.
    private var now: Date { fx.at(2026, 2, 20, 18, 30) }

    // MARK: - (a) Schema

    /// The 20 models the app persists. A model added to `AppSchema` changes this list on purpose.
    private let expectedEntityNames = [
        "AchievementUnlock", "BuddyLink", "BuddySnapshot", "ChatMessage", "ChecklistItem",
        "CoachMemory", "CoachPlan", "DetectedWorkout", "ExerciseEntry", "FoodEntry",
        "InsightShown", "Nudge", "SleepEntry", "StepsEntry", "UserProfile",
        "VitalsEntry", "WaterEntry", "WeightEntry", "WorkoutEntry", "WorkoutSession",
    ]

    func test_a_fullProductionSchemaOpensInMemoryWithAll20Models() throws {
        let container = try TestStore.makeContainer()

        XCTAssertEqual(AppSchema.models.count, 20)
        XCTAssertEqual(Set(AppSchema.models.map { ObjectIdentifier($0) }).count, 20,
                       "a model is registered twice")
        XCTAssertEqual(AppSchema.schema.entities.map(\.name).sorted(), expectedEntityNames)
        XCTAssertEqual(container.schema.entities.map(\.name).sorted(), expectedEntityNames)

        // Every table answers a query on a new store, and starts empty.
        let counts = try TestStore.countsByEntity(in: container)
        XCTAssertEqual(counts.keys.sorted(), expectedEntityNames)
        XCTAssertEqual(counts.values.reduce(0, +), 0)
    }

    func test_a_testContainerIsInMemoryWithCloudKitOffAndIsolatedPerContainer() throws {
        let first = try TestStore.makeContainer()
        let second = try TestStore.makeContainer()

        XCTAssertEqual(first.configurations.count, 1)
        let configuration = try XCTUnwrap(first.configurations.first)
        XCTAssertTrue(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.cloudKitContainerIdentifier, "CloudKit must be off in tests")

        let context = ModelContext(first)
        context.insert(WaterEntry(date: fx.at(2026, 2, 20, 9), amountOz: 12))
        try context.save()
        XCTAssertEqual(try TestStore.count(WaterEntry.self, in: first), 1)
        XCTAssertEqual(try TestStore.count(WaterEntry.self, in: second), 0,
                       "two test containers must not share a store")
    }

    /// Reads the app's Swift sources (the checkout this test was compiled from) and collects
    /// every class declared under `@Model`. A model class that is not in `AppSchema.models`
    /// compiles, and its rows are never saved; this is the test that notices.
    func test_a_everyModelClassInTheSourceTreeIsRegisteredInAppSchema() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SproutTests
            .deletingLastPathComponent()   // repository root
        let pattern = try NSRegularExpression(
            pattern: #"^[ \t]*@Model\b[^\n]*\n?[ \t]*(?:(?:public|internal|fileprivate|private|final)[ \t]+)*class[ \t]+(\w+)"#,
            options: [.anchorsMatchLines])

        var declared: [String] = []
        var filesRead = 0
        for directory in ["Sprout", "Shared", "SproutWidgets"] {
            let url = root.appendingPathComponent(directory)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil),
                                      "cannot read the source tree at \(url.path)")
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                filesRead += 1
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    declared.append(String(text[Range(match.range(at: 1), in: text)!]))
                }
            }
        }

        XCTAssertGreaterThan(filesRead, 100, "the source tree was not found at \(root.path)")
        XCTAssertEqual(declared.count, Set(declared).count, "two @Model classes share a name")
        XCTAssertEqual(declared.count, 20, "the number of @Model classes in the source tree changed")
        XCTAssertEqual(declared.sorted(), AppSchema.schema.entities.map(\.name).sorted(),
                       "a @Model class is missing from AppSchema.models, or AppSchema lists a class that is gone")
    }

    // MARK: - (d) The fixture

    /// Saves the fixture and returns its container. Rows go in out of date order.
    private func seededContainer() throws -> ModelContainer {
        let container = try TestStore.makeContainer()
        let context = ModelContext(container)

        // Food: (when, meal, name, servings, kcal, protein, carbs, fat) per serving.
        context.insert(FoodEntry(date: fx.at(2026, 2, 20, 23, 59, 59), mealType: .snack, name: "Yogurt",
                                 quantity: 2, calories: 90, proteinG: 9, carbsG: 7, fatG: 2.5))
        context.insert(FoodEntry(date: fx.at(2026, 2, 21, 0, 0, 0), mealType: .breakfast, name: "Tomorrow's oats",
                                 quantity: 1, calories: 300, proteinG: 10, carbsG: 50, fatG: 5))
        context.insert(FoodEntry(date: fx.at(2026, 2, 20, 8, 10), mealType: .breakfast, name: "Oats",
                                 quantity: 1, calories: 320, proteinG: 12, carbsG: 54, fatG: 6))
        context.insert(FoodEntry(date: fx.at(2026, 2, 19, 23, 59, 59), mealType: .dinner, name: "Pasta",
                                 quantity: 1, calories: 650, proteinG: 22, carbsG: 90, fatG: 18))
        context.insert(FoodEntry(date: fx.at(2026, 2, 20, 12, 45), mealType: .lunch, name: "Chicken bowl",
                                 quantity: 1.5, calories: 480, proteinG: 40, carbsG: 50, fatG: 12))
        context.insert(FoodEntry(date: fx.at(2026, 2, 20, 0, 0, 0), mealType: .snack, name: "Midnight tea",
                                 quantity: 1, calories: 5, proteinG: 0, carbsG: 1, fatG: 0))

        // Water, in ounces.
        context.insert(WaterEntry(date: fx.at(2026, 2, 20, 15, 30), amountOz: 12))
        context.insert(WaterEntry(date: fx.at(2026, 2, 19, 23, 59, 59), amountOz: 20))
        context.insert(WaterEntry(date: fx.at(2026, 2, 20, 0, 0, 0), amountOz: 8))
        context.insert(WaterEntry(date: fx.at(2026, 2, 21, 0, 0, 0), amountOz: 5))
        context.insert(WaterEntry(date: fx.at(2026, 2, 18, 10), amountOz: 24))
        context.insert(WaterEntry(date: fx.at(2026, 2, 20, 9), amountOz: 16.9))

        // Weigh-ins at 07:00: three by hand, a week apart, and one older scale sync.
        context.insert(WeightEntry(date: fx.at(2026, 2, 13, 7), weightLbs: 180))
        context.insert(WeightEntry(date: fx.at(2026, 2, 20, 7), weightLbs: 179))
        context.insert(WeightEntry(date: fx.at(2026, 1, 2, 7), weightLbs: 185,
                                   source: "healthkit", healthKitUUID: "HK-SCALE-1"))
        context.insert(WeightEntry(date: fx.at(2026, 2, 6, 7), weightLbs: 182))

        // Steps, one row per day at local midnight. 18 February has none.
        context.insert(StepsEntry(date: fx.at(2026, 2, 19), count: 10_250))
        context.insert(StepsEntry(date: fx.at(2026, 2, 17), count: 8_000))
        context.insert(StepsEntry(date: fx.at(2026, 2, 20), count: 4_321))

        // Sleep, keyed by the wake morning. Tonight's row (20 February) has not synced yet.
        context.insert(SleepEntry(date: fx.at(2026, 2, 18), asleepMinutes: 395, inBedMinutes: 410))
        context.insert(SleepEntry(date: fx.at(2026, 2, 19), asleepMinutes: 432, inBedMinutes: 465,
                                  deepMinutes: 81, remMinutes: 104, coreMinutes: 247, awakeMinutes: 19))

        try context.save()
        return container
    }

    // MARK: - (d) Queries

    func test_d_todaysFoodEntriesAndTheirCalorieAndMacroTotals() throws {
        let reader = ModelContext(try seededContainer())

        // As DashboardView: every entry sorted by date, then the "is it today" filter.
        let all = try reader.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(all.map(\.name),
                       ["Pasta", "Midnight tea", "Oats", "Chicken bowl", "Yogurt", "Tomorrow's oats"])
        let today = CoachContext.todaysFoods(all, calendar: cal, now: now)
        // 00:00:00 and 23:59:59 today are in; 23:59:59 yesterday and 00:00:00 tomorrow are out.
        XCTAssertEqual(today.map(\.name), ["Midnight tea", "Oats", "Chicken bowl", "Yogurt"])

        // The same day asked of the store as a date range returns the same rows.
        let start = fx.at(2026, 2, 20), end = fx.at(2026, 2, 21)
        let ranged = try reader.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(ranged.map(\.persistentModelID), today.map(\.persistentModelID))

        // Totals = per-serving value x servings, summed (the sums DashboardView and the widget use):
        //   kcal     5x1 + 320x1 + 480x1.5 + 90x2  = 5 + 320 + 720 + 180 = 1225
        //   protein  0   + 12    + 40x1.5  + 9x2   = 0 + 12 + 60 + 18    = 90
        //   carbs    1   + 54    + 50x1.5  + 7x2   = 1 + 54 + 75 + 14    = 144
        //   fat      0   + 6     + 12x1.5  + 2.5x2 = 0 + 6 + 18 + 5      = 29
        XCTAssertEqual(today.reduce(0) { $0 + $1.totalCalories }, 1225)
        XCTAssertEqual(today.reduce(0) { $0 + $1.totalProteinG }, 90)
        XCTAssertEqual(today.reduce(0) { $0 + $1.totalCarbsG }, 144)
        XCTAssertEqual(today.reduce(0) { $0 + $1.totalFatG }, 29)

        // As FoodLogView for another selected day (19 February): one entry, 650 kcal.
        let yesterday = all.filter { cal.isDate($0.date, inSameDayAs: fx.at(2026, 2, 19, 12)) }
        XCTAssertEqual(yesterday.map(\.name), ["Pasta"])
        XCTAssertEqual(yesterday.reduce(0) { $0 + $1.totalCalories }, 650)
    }

    func test_d_weightTrendWindow() throws {
        let reader = ModelContext(try seededContainer())

        // As WeightView: every weigh-in, ascending by date.
        let weights = try reader.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(weights.map(\.date),
                       [fx.at(2026, 1, 2, 7), fx.at(2026, 2, 6, 7), fx.at(2026, 2, 13, 7), fx.at(2026, 2, 20, 7)])
        XCTAssertEqual(weights.map(\.weightLbs), [185, 182, 180, 179])

        // The 1-month chart window (WeightView.rangedWeights, cutoff = one month before now,
        // 20 January 18:30) as a store query: the 2 January scale reading is outside it.
        let cutoff = try XCTUnwrap(cal.date(byAdding: .month, value: -1, to: now))
        XCTAssertEqual(cutoff, fx.at(2026, 1, 20, 18, 30))
        let window = try reader.fetch(FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date >= cutoff }, sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(window.map(\.weightLbs), [182, 180, 179])

        // The trend is a time-decayed average over the FULL history, alpha = 1 - e^(-days/7):
        //   2 Jan   185                                                      = 185
        //   6 Feb   35 days later, alpha = 1 - e^-5 = 0.9932621
        //           185 + 0.9932621 x (182 - 185)                            = 182.0202138
        //   13 Feb  7 days later, alpha = 1 - e^-1 = 0.6321206
        //           182.0202138 + 0.6321206 x (180 - 182.0202138)            = 180.7431951
        //   20 Feb  180.7431951 + 0.6321206 x (179 - 180.7431951)            = 179.6412857
        let trend = TrendCalculator.trend(weights)
        XCTAssertEqual(trend.map(\.date), weights.map(\.date))
        XCTAssertEqual(trend[0].value, 185, accuracy: 1e-9)
        XCTAssertEqual(trend[1].value, 182.0202138, accuracy: 1e-6)
        XCTAssertEqual(trend[2].value, 180.7431951, accuracy: 1e-6)
        XCTAssertEqual(trend[3].value, 179.6412857, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(TrendCalculator.currentTrend(weights)), 179.6412857, accuracy: 1e-6)

        // Rate: least-squares slope of the trend over the 14 days up to the last weigh-in
        // (6, 13 and 20 February; days 0, 7, 14). For three evenly spaced points the slope is
        // (last - first) / 14 per day = (179.6412857 - 182.0202138) / 14 = -0.1699234,
        // x 7 = -1.1894641 lb per week.
        XCTAssertEqual(TrendCalculator.ratePerWeek(weights), -1.1894641, accuracy: 1e-6)
    }

    func test_d_loggingStreakInputs() throws {
        let reader = ModelContext(try seededContainer())
        let foods = try reader.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        let waters = try reader.fetch(FetchDescriptor<WaterEntry>())
        let weights = try reader.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))

        // Days with an active log:
        //   food    19, 20, 21 Feb          water   18, 19, 20, 21 Feb
        //   weigh-ins by hand  6, 13, 20 Feb   (2 Jan is a scale sync: it does not count)
        // 17 Feb has only a steps row, which is passive and does not count either.
        let logged = StreakCalculator.loggedDays(foods: foods, waters: waters, weights: weights, calendar: cal)
        XCTAssertEqual(logged.sorted(), [fx.at(2026, 2, 6), fx.at(2026, 2, 13), fx.at(2026, 2, 18),
                                         fx.at(2026, 2, 19), fx.at(2026, 2, 20), fx.at(2026, 2, 21)])

        // Back from 20 Feb: 20, 19, 18, then 17 is missing. Streak 3; last log before today was 1 day ago.
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: foods, waters: waters, weights: weights,
                                                      calendar: cal, now: now), 3)
        XCTAssertEqual(StreakCalculator.daysSinceLastLog(foods: foods, waters: waters, weights: weights,
                                                         calendar: cal, now: now), 1)
        // Without water (the coach's version passes no water) 18 Feb drops out: 20, 19. Streak 2.
        XCTAssertEqual(StreakCalculator.loggingStreak(foods: foods, weights: weights, calendar: cal, now: now), 2)
        // An account created on 10 Feb cannot count 6 Feb.
        XCTAssertEqual(StreakCalculator.loggedDays(foods: foods, waters: waters, weights: weights,
                                                   since: fx.at(2026, 2, 10, 15), calendar: cal).sorted(),
                       [fx.at(2026, 2, 13), fx.at(2026, 2, 18), fx.at(2026, 2, 19), fx.at(2026, 2, 20), fx.at(2026, 2, 21)])
    }

    func test_d_todaysWater() throws {
        let reader = ModelContext(try seededContainer())
        let water = try reader.fetch(FetchDescriptor<WaterEntry>())
        XCTAssertEqual(water.count, 6)

        // Today: 8 (00:00:00) + 16.9 (09:00) + 12 (15:30) = 36.9 oz.
        // Not today: 20 (23:59:59 yesterday), 24 (18 Feb), 5 (00:00:00 tomorrow).
        XCTAssertEqual(CoachContext.todaysWaterOz(water, calendar: cal, now: now), 36.9, accuracy: 1e-9)

        // The same day asked of the store as a date range: the same three rows.
        let start = fx.at(2026, 2, 20), end = fx.at(2026, 2, 21)
        let ranged = try reader.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(ranged.map(\.amountOz), [8, 16.9, 12])
    }

    func test_d_stepsEntryForADay() throws {
        let reader = ModelContext(try seededContainer())
        // As DashboardView / FoodLogView: sorted by date, first row on the asked day, else 0.
        let steps = try reader.fetch(FetchDescriptor<StepsEntry>(sortBy: [SortDescriptor(\.date)]))
        func count(on day: Date) -> Int { steps.first { cal.isDate($0.date, inSameDayAs: day) }?.count ?? 0 }

        XCTAssertEqual(steps.map(\.count), [8_000, 10_250, 4_321])          // 17, 19, 20 Feb
        XCTAssertEqual(count(on: now), 4_321)                               // today, asked at 18:30
        XCTAssertEqual(count(on: fx.at(2026, 2, 19, 23, 59, 59)), 10_250)
        XCTAssertEqual(count(on: fx.at(2026, 2, 18, 12)), 0, "no row for 18 Feb")
        XCTAssertEqual(count(on: fx.at(2026, 2, 17)), 8_000)

        // One row per day: the store holds exactly one row inside 19 February.
        let start = fx.at(2026, 2, 19), end = fx.at(2026, 2, 20)
        let ranged = try reader.fetch(FetchDescriptor<StepsEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }))
        XCTAssertEqual(ranged.map(\.count), [10_250])
    }

    func test_d_latestSleepNight() throws {
        let container = try seededContainer()
        let today = cal.startOfDay(for: now)
        // TrackerDetailView.lastNight: newest first; today's night if it has sleep, else the newest that has.
        func latestNight(_ context: ModelContext) throws -> SleepEntry? {
            let sleep = try context.fetch(FetchDescriptor<SleepEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            return sleep.first { cal.isDate($0.date, inSameDayAs: today) && $0.asleepMinutes > 0 }
                ?? sleep.first { $0.asleepMinutes > 0 }
        }

        // Tonight has not synced: the latest night is the one that ended on 19 February.
        let reader = ModelContext(container)
        let latest = try XCTUnwrap(try latestNight(reader))
        XCTAssertEqual(latest.date, fx.at(2026, 2, 19))
        XCTAssertEqual([latest.asleepMinutes, latest.inBedMinutes, latest.deepMinutes,
                        latest.remMinutes, latest.coreMinutes, latest.awakeMinutes], [432, 465, 81, 104, 247, 19])
        // The coach is told nothing about "last night" when today's row is missing.
        let all = try reader.fetch(FetchDescriptor<SleepEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        XCTAssertNil(CoachContext.lastNightSleepLine(all, now: now, calendar: cal))

        // Today's night arrives through the ingest path: it becomes the latest night.
        let writer = ModelContext(container)
        HealthKitService.mergeDailySleep([today: .init(asleep: 401, inBed: 430)], into: writer,
                                         existing: try writer.fetch(FetchDescriptor<SleepEntry>()), calendar: cal)
        let after = ModelContext(container)
        let newest = try XCTUnwrap(try latestNight(after))
        XCTAssertEqual(newest.date, fx.at(2026, 2, 20))
        XCTAssertEqual(newest.asleepMinutes, 401)
        // 401 minutes = 6 h 41 min. Three nights (395, 432, 401) average 1228 / 3 = 409 min = 6 h 49 min.
        let line = try XCTUnwrap(CoachContext.lastNightSleepLine(
            try after.fetch(FetchDescriptor<SleepEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])),
            now: now, calendar: cal))
        XCTAssertTrue(line.hasPrefix("Last night's sleep: 6h 41m asleep"), line)
        XCTAssertTrue(line.hasSuffix("~6h 49m average over the last 3 nights"), line)
    }

    // MARK: - (e) Deleting

    func test_e_deletedRowIsGoneFromANewContext() throws {
        let container = try seededContainer()
        let writer = ModelContext(container)
        let bowl = try XCTUnwrap(writer.fetch(FetchDescriptor<FoodEntry>()).first { $0.name == "Chicken bowl" })
        let bowlID = bowl.persistentModelID
        writer.delete(bowl)
        try writer.save()

        let reader = ModelContext(container)
        let foods = try reader.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(foods.map(\.name), ["Pasta", "Midnight tea", "Oats", "Yogurt", "Tomorrow's oats"])
        XCTAssertFalse(foods.contains { $0.persistentModelID == bowlID })
        // Today's calories without the bowl: 1225 - 720 = 505.
        XCTAssertEqual(CoachContext.todaysFoods(foods, calendar: cal, now: now).reduce(0) { $0 + $1.totalCalories }, 505)
        // Nothing else moved.
        XCTAssertEqual(try TestStore.count(WaterEntry.self, in: container), 6)
        XCTAssertEqual(try TestStore.count(WeightEntry.self, in: container), 4)
        XCTAssertEqual(try TestStore.count(StepsEntry.self, in: container), 3)
        XCTAssertEqual(try TestStore.count(SleepEntry.self, in: container), 2)
    }

    /// Two rows of every model, then every `WaterEntry` deleted the way the app deletes
    /// (object by object): water is empty and the other nineteen tables still hold two rows.
    func test_e_deletingOneModelsRowsLeavesTheOtherNineteenModelsUntouched() throws {
        let container = try TestStore.makeContainer()
        let writer = ModelContext(container)
        for _ in 0..<2 { insertOneOfEveryModel(into: writer) }
        try writer.save()

        let two = Dictionary(uniqueKeysWithValues: expectedEntityNames.map { ($0, 2) })
        XCTAssertEqual(try TestStore.countsByEntity(in: container), two)

        let deleter = ModelContext(container)
        for entry in try deleter.fetch(FetchDescriptor<WaterEntry>()) { deleter.delete(entry) }
        try deleter.save()

        var expected = two
        expected["WaterEntry"] = 0
        XCTAssertEqual(try TestStore.countsByEntity(in: container), expected)

        // A session's exercises are linked by a plain id, not a relationship: deleting the
        // session does not delete them (the app's delete paths remove both by hand).
        for session in try deleter.fetch(FetchDescriptor<WorkoutSession>()) { deleter.delete(session) }
        try deleter.save()
        expected["WorkoutSession"] = 0
        XCTAssertEqual(try TestStore.countsByEntity(in: container), expected)
        XCTAssertEqual(try TestStore.count(ExerciseEntry.self, in: container), 2)
    }

    private func insertOneOfEveryModel(into context: ModelContext) {
        let day = fx.at(2026, 2, 20), noon = fx.at(2026, 2, 20, 12)
        let session = WorkoutSession(date: noon, kind: .gym, focuses: [.legs])
        let rows: [any PersistentModel] = [
            UserProfile(),
            WeightEntry(date: noon, weightLbs: 180),
            FoodEntry(date: noon, name: "Oats", calories: 320),
            WorkoutEntry(date: noon, type: .walk, durationMinutes: 20),
            WaterEntry(date: noon, amountOz: 12),
            ChatMessage(role: "user", content: "hi", createdAt: noon),
            CoachMemory(profileNotes: "note", updatedAt: noon),
            CoachPlan(headline: "plan", createdAt: noon, updatedAt: noon),
            StepsEntry(date: day, count: 4_321),
            SleepEntry(date: day, asleepMinutes: 401),
            DetectedWorkout(healthKitUUID: UUID().uuidString, date: noon, activity: "Walking", durationMinutes: 22),
            VitalsEntry(date: day, restingHeartRate: 60, hrvMs: 44),
            AchievementUnlock(achievementID: "streak_7", unlockedAt: noon),
            InsightShown(insightID: "fuel_up", shownAt: noon),
            BuddyLink(myUserID: "me", pairingCode: "VITA-0000", createdAt: noon),
            Nudge(fromUserID: "them", toUserID: "me", createdAt: noon),
            BuddySnapshot(ownerUserID: "them", displayName: "Alex", lastActive: noon),
            ChecklistItem(title: "Walk", day: day),
            session,
            ExerciseEntry(sessionID: session.id, date: noon, machineKey: "leg_press"),
        ]
        XCTAssertEqual(rows.count, AppSchema.models.count, "one row per registered model")
        rows.forEach { context.insert($0) }
    }

    // MARK: - (f) Two profiles

    /// PINS CURRENT BEHAVIOUR, KNOWN RISK. An iCloud restore can leave two `UserProfile` rows.
    /// `RootView` reads `@Query private var profiles` with no sort and takes `profiles.first`
    /// (RootView.swift:7 and :23), then shows the app only if that row has finished onboarding.
    /// Today that is the row the store returns first, which is the row saved first, whatever
    /// its `createdAt` and whether or not it is the finished one: when the unfinished copy is
    /// saved first, a user with a complete profile is sent back to onboarding.
    /// This test asserts that behaviour as it is. It does not say the behaviour is right.
    func test_f_pinsCurrentBehaviour_twoProfiles_gateTakesTheFirstSavedRowWhateverItsState_knownRisk() throws {
        func profile(_ name: String, created: Date, onboarded: Bool) -> UserProfile {
            let p = UserProfile()
            p.name = name
            p.createdAt = created
            p.onboardingComplete = onboarded
            return p
        }
        /// What `RootView` sees: an unsorted fetch, first row.
        func gateProfile(_ container: ModelContainer) throws -> UserProfile? {
            try ModelContext(container).fetch(FetchDescriptor<UserProfile>()).first
        }
        let january = fx.at(2026, 1, 5, 9), february = fx.at(2026, 2, 20, 9)

        // The finished, older profile is saved first: the gate takes it and shows the app.
        let finishedFirst = try TestStore.makeContainer()
        var writer = ModelContext(finishedFirst)
        writer.insert(profile("finished", created: january, onboarded: true))
        try writer.save()
        writer.insert(profile("unfinished copy", created: february, onboarded: false))
        try writer.save()
        XCTAssertEqual(try TestStore.count(UserProfile.self, in: finishedFirst), 2)
        XCTAssertEqual(try gateProfile(finishedFirst)?.name, "finished")
        XCTAssertEqual(try gateProfile(finishedFirst)?.onboardingComplete, true)

        // The same two rows saved in the other order: the gate takes the unfinished copy,
        // although it is the newer one and a finished profile exists. Onboarding is shown.
        let unfinishedFirst = try TestStore.makeContainer()
        writer = ModelContext(unfinishedFirst)
        writer.insert(profile("unfinished copy", created: february, onboarded: false))
        try writer.save()
        writer.insert(profile("finished", created: january, onboarded: true))
        try writer.save()
        XCTAssertEqual(try TestStore.count(UserProfile.self, in: unfinishedFirst), 2)
        XCTAssertEqual(try gateProfile(unfinishedFirst)?.name, "unfinished copy")
        XCTAssertEqual(try gateProfile(unfinishedFirst)?.onboardingComplete, false)
    }
}
