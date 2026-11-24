import XCTest
import CloudKit
@testable import Sprout

/// The weekly competition (GOALS G12, EVAL_REPORT 29): a point a day for each of a person's
/// own targets hit, Monday to Sunday on both phones, and only which targets cross to the
/// buddy, never a number.
@MainActor
final class CompetitionTests: XCTestCase {

    // MARK: - One day

    private let loseTargets = CompetitionScoring.Targets(calorieLow: 1600, calorieHigh: 1750, protein: 120,
                                                         waterOz: 80, steps: 8000)

    private func day(food: Bool = true, kcal: Double = 1650, protein: Double = 125, water: Double = 80,
                     steps: Int = 8000, active: Bool = true) -> CompetitionScoring.DayTotals {
        .init(loggedFood: food, calories: kcal, protein: protein, waterOz: water, steps: steps, active: active)
    }

    func testAPerfectDayIsFivePoints() {
        let hits = CompetitionScoring.hits(day(), loseTargets)
        XCTAssertEqual(hits, [.calories, .protein, .water, .steps, .active])
        XCTAssertEqual(hits.points, 5)
    }

    func testNoFoodLoggedIsZeroWhateverElseHappened() {
        XCTAssertEqual(CompetitionScoring.hits(day(food: false, steps: 20_000), loseTargets), [])
    }

    func testCaloriesCountOnlyInsideTheRangeWithTheAppsSmallGraceAtTheFloor() {
        func hit(_ kcal: Double, _ t: CompetitionScoring.Targets) -> Bool {
            CompetitionScoring.hits(day(kcal: kcal), t).contains(.calories)
        }
        XCTAssertTrue(hit(1552, loseTargets), "97% of the 1,600 floor")
        XCTAssertFalse(hit(1551, loseTargets), "under the grace")
        XCTAssertTrue(hit(1750, loseTargets), "the ceiling itself")
        XCTAssertFalse(hit(1751, loseTargets), "over the ceiling misses too: eating enough is the target, not less")
        var gain = loseTargets
        gain.calorieHigh = .infinity
        XCTAssertTrue(hit(3400, gain), "a gain goal has no ceiling")
        XCTAssertFalse(hit(1500, gain))
        var none = loseTargets
        none.calorieLow = 0
        XCTAssertFalse(hit(1650, none), "no target, no point")
    }

    func testTheOtherTargetsCountAtTheTargetItselfAndNotBelow() {
        XCTAssertTrue(CompetitionScoring.hits(day(protein: 120), loseTargets).contains(.protein))
        XCTAssertFalse(CompetitionScoring.hits(day(protein: 119.9), loseTargets).contains(.protein))
        XCTAssertTrue(CompetitionScoring.hits(day(water: 80), loseTargets).contains(.water))
        XCTAssertFalse(CompetitionScoring.hits(day(water: 79), loseTargets).contains(.water))
        XCTAssertTrue(CompetitionScoring.hits(day(steps: 8000), loseTargets).contains(.steps))
        XCTAssertFalse(CompetitionScoring.hits(day(steps: 7999), loseTargets).contains(.steps))
        XCTAssertFalse(CompetitionScoring.hits(day(active: false), loseTargets).contains(.active))
    }

    func testTargetsAreTheOnesTodayShowsIncludingTheStepBonus() {
        let p = UserProfile()
        p.startWeightLbs = 160
        p.goalWeightLbs = 145
        p.stepsAdjustCalories = false
        let range = p.calorieGoalRange(weightLbs: 160)
        let flat = CompetitionScoring.targets(profile: p, basisWeight: 160, steps: 15_000)
        p.stepsAdjustCalories = true
        let bonus = p.stepBonusCalories(weightLbs: 160, steps: 15_000)
        XCTAssertGreaterThan(bonus, 0, "15,000 steps is above any baseline")
        let withBonus = CompetitionScoring.targets(profile: p, basisWeight: 160, steps: 15_000)
        XCTAssertEqual(withBonus.calorieLow, range.low + bonus)
        XCTAssertEqual(withBonus.calorieHigh, range.high + bonus)
        XCTAssertEqual(flat.calorieLow, range.low, "no bonus when steps do not change the budget")
        XCTAssertEqual(withBonus.protein, p.macroTargets(weightLbs: 160).proteinG)
        XCTAssertEqual(withBonus.waterOz, p.waterTargetOz)
        XCTAssertEqual(withBonus.steps, p.dailyStepGoal)
    }

    // MARK: - The week

    private func sundayFirst() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 1
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testTheWeekIsMondayToSundayEvenOnASundayFirstPhone() {
        let c = sundayFirst()
        let sunday = at(2026, 11, 29, 12, c)
        XCTAssertEqual(CompetitionRecord.dayKey(CompetitionWeek.start(of: sunday, calendar: c)), "2026-11-23",
                       "a Sunday belongs to the week that began on Monday")
        XCTAssertEqual(CompetitionRecord.dayKey(CompetitionWeek.start(of: at(2026, 11, 23, 0, c), calendar: c)), "2026-11-23")
        XCTAssertEqual(CompetitionRecord.dayKey(CompetitionWeek.start(of: at(2026, 11, 22, 23, c), calendar: c)), "2026-11-16")
    }

    func testTheRecordHoldsLastWeekWholeAndThisWeekUpToToday() throws {
        let c = sundayFirst()
        let now = at(2026, 11, 25, 20, c)            // Wednesday evening
        let p = UserProfile()
        p.startWeightLbs = 160
        p.dailyStepGoal = 8000
        p.waterGoalOzOverride = 64
        p.stepsAdjustCalories = false   // the step bonus has its own test above
        let low = p.calorieGoalRange(weightLbs: 160).low
        let protein = p.macroTargets(weightLbs: 160).proteinG
        let foods = [
            FoodEntry(date: at(2026, 11, 23, 9, c), name: "Monday", calories: low, proteinG: protein),
            FoodEntry(date: at(2026, 11, 24, 9, c), name: "Tuesday", calories: low * 2, proteinG: 10),
            FoodEntry(date: at(2026, 11, 17, 9, c), name: "Last Tuesday", calories: low, proteinG: protein),
        ]
        let record = CompetitionScoring.record(
            profile: p, foods: foods,
            water: [WaterEntry(date: at(2026, 11, 23, 10, c), amountOz: 64)],
            steps: [StepsEntry(date: c.startOfDay(for: at(2026, 11, 23, 0, c)), count: 9000),
                    StepsEntry(date: c.startOfDay(for: at(2026, 11, 25, 0, c)), count: 12_000)],
            sessions: [WorkoutSession(date: at(2026, 11, 24, 7, c))],
            detected: [DetectedWorkout(healthKitUUID: "x", date: at(2026, 11, 23, 17, c), activity: "Run", durationMinutes: 30)],
            basisWeight: 160, now: now, calendar: c)

        let this = try XCTUnwrap(record.days(forWeekStarting: "2026-11-23"))
        XCTAssertEqual(this.count, 3, "Monday to Wednesday: no days after today")
        XCTAssertEqual(this[0], [.calories, .protein, .water, .steps, .active], "Monday hit all five")
        XCTAssertEqual(this[1], [.active], "Tuesday: over the range, low protein, a logged workout")
        XCTAssertEqual(this[2], [], "Wednesday: 12,000 steps but no food logged")
        let last = try XCTUnwrap(record.days(forWeekStarting: "2026-11-16"))
        XCTAssertEqual(last.count, 7)
        XCTAssertEqual(last[1], [.calories, .protein])
        XCTAssertEqual(record.points(forWeekStarting: "2026-11-16"), 2)
        XCTAssertEqual(record.points(forWeekStarting: "2026-11-23"), 6)
    }

    func testNoProfileIsNoRecord() {
        XCTAssertEqual(CompetitionScoring.record(profile: nil, foods: [], water: [], steps: [], sessions: [],
                                                 detected: [], basisWeight: 150), .empty)
    }

    // MARK: - What crosses to the buddy

    func testTheWireFormatRoundTripsAndCarriesNoNumbersButTheTargetsHit() {
        let record = CompetitionRecord(weeks: ["2026-11-16": [[.calories, .water], [], [.protein, .water, .steps, .active, .calories]],
                                               "2026-11-23": [[.active]]])
        XCTAssertEqual(record.encoded, "2026-11-16:5,0,31;2026-11-23:16")
        XCTAssertEqual(CompetitionRecord.decode(record.encoded), record)
        XCTAssertEqual(CompetitionRecord.decode(""), .empty)
        XCTAssertEqual(CompetitionRecord.decode("2026-11-23:").days(forWeekStarting: "2026-11-23"), [])
    }

    func testAnythingMalformedDropsThatWeekInsteadOfInventingPoints() {
        let mixed = CompetitionRecord.decode("2026-11-16:5,0,31;bad:1;2026-11-23:1,2,3,4,5,6,7,8;2026-11-30:32;2026-12-07:x;2026-1-7:1")
        XCTAssertEqual(Array(mixed.weeks.keys), ["2026-11-16"])
    }

    func testTheMarginSaysWhoIsAhead() {
        let me = CompetitionRecord(weeks: ["w": [[.calories, .water]]])
        let them = CompetitionRecord(weeks: ["w": [[.active]]])
        XCTAssertEqual(CompetitionScoring.margin(mine: me, theirs: them, weekKey: "w"), 1)
        XCTAssertEqual(CompetitionScoring.margin(mine: them, theirs: me, weekKey: "w"), -1)
        XCTAssertNil(CompetitionScoring.margin(mine: me, theirs: .empty, weekKey: "w"))
    }

    func testTheCompetitionSurvivesTheFullDataOptOutBecauseItHoldsNoNumbers() {
        let payload = BuddySnapshotPayload(ownerUserID: "u", displayName: "Sam", dayStreak: 3, characterMood: .happy,
                                           loggedToday: true, lastActive: .now, sharesFullData: false,
                                           caloriesEaten: 1500, todayFoods: "Oats",
                                           competitionWeeks: "2026-11-23:31")
        XCTAssertEqual(payload.caloriesEaten, 0, "the opt-out still blanks the numbers")
        XCTAssertEqual(payload.todayFoods, "")
        XCTAssertEqual(payload.competitionWeeks, "2026-11-23:31")
        XCTAssertEqual(payload.withoutFullData.competitionWeeks, "2026-11-23:31")
    }

    func testTheCloudKitRecordCarriesItAndAnOlderRecordReadsAsNoCompetition() throws {
        let record = CKRecord(recordType: "BuddySnapshot")
        record["ownerUserID"] = "u" as CKRecordValue
        record["displayName"] = "Sam" as CKRecordValue
        XCTAssertEqual(try XCTUnwrap(CloudKitSyncService.snapshot(from: record)).competitionWeeks, "",
                       "a build older than the competition wrote no field")
        record["competitionWeeks"] = "2026-11-23:31,3" as CKRecordValue
        XCTAssertEqual(try XCTUnwrap(CloudKitSyncService.snapshot(from: record)).competitionWeeks, "2026-11-23:31,3")
    }

    // MARK: - The simulated buddy and what VoiceOver says

    func testTheSimulatedBuddysRecordIsFixed() {
        let c = sundayFirst()
        let wednesday = at(2026, 11, 25, 9, c)
        let sample = LocalMockSyncService.sampleCompetition(now: wednesday, calendar: c)
        XCTAssertEqual(sample.points(forWeekStarting: "2026-11-16"), 20)
        XCTAssertEqual(sample.days(forWeekStarting: "2026-11-23")?.map(\.points), [3, 4, 2])
        let sunday = LocalMockSyncService.sampleCompetition(now: at(2026, 11, 29, 9, c), calendar: c)
        XCTAssertEqual(sunday.days(forWeekStarting: "2026-11-23")?.count, 7)
    }

    func testVoiceOverSaysThePointsAndTheTargets() {
        let c = sundayFirst()
        let day = at(2026, 11, 24, 12, c)
        let name = day.formatted(.dateTime.weekday(.wide))
        XCTAssertEqual(CompetitionCard.spokenLabel(who: "You", date: day, hits: nil), "You, \(name): not yet")
        XCTAssertEqual(CompetitionCard.spokenLabel(who: "You", date: day, hits: []), "You, \(name): 0 points")
        XCTAssertEqual(CompetitionCard.spokenLabel(who: "Sam", date: day, hits: [.water]), "Sam, \(name): 1 point, water")
        XCTAssertEqual(CompetitionCard.spokenLabel(who: "Sam", date: day, hits: [.calories, .active]),
                       "Sam, \(name): 2 points, calories in range, active")
    }
}
