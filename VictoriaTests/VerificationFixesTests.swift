import XCTest
import SwiftData
@testable import Victoria

/// Regressions for defects found in the 2026-11-22 verification pass (docs/EVAL_REPORT.md
/// section 3). Each test is the user-visible failure, written so it fails on the old code.
final class VerificationFixesTests: XCTestCase {

    // MARK: - Buddy privacy: nothing opt-in leaves the device without the opt-in

    private func payload(shares: Bool) -> BuddySnapshotPayload {
        BuddySnapshotPayload(ownerUserID: "me", displayName: "Alex", dayStreak: 12,
                             characterMood: .happy, loggedToday: true, lastActive: .now,
                             stepsToday: 9000, stepGoal: 8000, waterToday: 50, waterGoal: 80,
                             workedOutToday: true, workoutSummary: "Run · 30 min",
                             sharesFullData: shares,
                             trendWeightLbs: 161.4, goalWeightLbs: 172, weeklyRateLbs: 0.4,
                             caloriesEaten: 2100, calorieTarget: 2600,
                             proteinEaten: 140, proteinTarget: 160,
                             carbsEaten: 230, carbTarget: 300, fatEaten: 70, fatTarget: 80,
                             todayFoods: "Greek yogurt, Chicken burrito bowl")
    }

    func testSnapshotWithoutOptInCarriesNoWeightCaloriesOrFood() {
        let p = payload(shares: false)
        XCTAssertFalse(p.sharesFullData)
        XCTAssertEqual(p.trendWeightLbs, 0)
        XCTAssertEqual(p.goalWeightLbs, 0)
        XCTAssertEqual(p.weeklyRateLbs, 0)
        XCTAssertEqual(p.caloriesEaten, 0)
        XCTAssertEqual(p.calorieTarget, 0)
        XCTAssertEqual(p.proteinEaten, 0)
        XCTAssertEqual(p.proteinTarget, 0)
        XCTAssertEqual(p.carbsEaten, 0)
        XCTAssertEqual(p.carbTarget, 0)
        XCTAssertEqual(p.fatEaten, 0)
        XCTAssertEqual(p.fatTarget, 0)
        XCTAssertEqual(p.todayFoods, "")
    }

    func testSnapshotWithoutOptInKeepsTheActivityFaceOff() {
        let p = payload(shares: false)
        XCTAssertEqual(p.displayName, "Alex")
        XCTAssertEqual(p.dayStreak, 12)
        XCTAssertEqual(p.stepsToday, 9000)
        XCTAssertEqual(p.stepGoal, 8000)
        XCTAssertEqual(p.waterToday, 50)
        XCTAssertEqual(p.waterGoal, 80)
        XCTAssertTrue(p.workedOutToday)
        XCTAssertEqual(p.workoutSummary, "Run · 30 min")
        XCTAssertTrue(p.loggedToday)
    }

    func testSnapshotWithOptInCarriesTheFullPicture() {
        let p = payload(shares: true)
        XCTAssertTrue(p.sharesFullData)
        XCTAssertEqual(p.trendWeightLbs, 161.4)
        XCTAssertEqual(p.caloriesEaten, 2100)
        XCTAssertEqual(p.todayFoods, "Greek yogurt, Chicken burrito bowl")
    }

    func testFlagTurnedOffAfterBuildIsStrippedAtUpload() {
        // The fields are mutable; the upload path strips again with `withoutFullData`.
        var p = payload(shares: true)
        p.sharesFullData = false
        XCTAssertEqual(p.trendWeightLbs, 161.4, "mutation alone does not blank the fields")
        let sent = p.withoutFullData
        XCTAssertEqual(sent.trendWeightLbs, 0)
        XCTAssertEqual(sent.todayFoods, "")
        XCTAssertEqual(sent.stepsToday, 9000)
    }

    // MARK: - Plan targets: a protein goal set without a plan survives a relaunch

    func testNoPlanKeepsTheUsersProteinTarget() {
        let next = PlanTargetSync.overrides(plan: nil, currentProtein: 150)
        XCTAssertEqual(next, .init(calorie: 0, calorieMax: 0, protein: 150))
    }

    func testNoPlanAndNoProteinTargetStaysAtComputedDefaults() {
        XCTAssertEqual(PlanTargetSync.overrides(plan: nil, currentProtein: 0),
                       .init(calorie: 0, calorieMax: 0, protein: 0))
        XCTAssertEqual(PlanTargetSync.overrides(plan: nil, currentProtein: -5).protein, 0)
    }

    func testPlanNumbersWinOverTheCurrentOverride() {
        let plan = PlanTargetSync.PlanTargets(hasRange: true, calorieMin: 1600, calorieMax: 1750, proteinTarget: 120)
        XCTAssertEqual(PlanTargetSync.overrides(plan: plan, currentProtein: 150),
                       .init(calorie: 1600, calorieMax: 1750, protein: 120))
    }

    func testPlanWithoutARangeSetsNoCalorieOverride() {
        let plan = PlanTargetSync.PlanTargets(hasRange: false, calorieMin: 0, calorieMax: 0, proteinTarget: 0)
        XCTAssertEqual(PlanTargetSync.overrides(plan: plan, currentProtein: 150),
                       .init(calorie: 0, calorieMax: 0, protein: 0),
                       "a plan that sets no protein clears a stale override, as before")
    }

    // MARK: - "Goals changed" flag clears

    func testGoalsChangedFlagCanBeCleared() throws {
        let schema = Schema([CoachPlan.self])
        let container = try ModelContainer(for: schema,
                                           configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let plan = CoachPlan()
        context.insert(plan)
        XCTAssertFalse(plan.goalsChangedSinceBuild)
        plan.markGoalsChanged()
        XCTAssertTrue(plan.goalsChangedSinceBuild)
        plan.clearGoalsChanged()
        XCTAssertFalse(plan.goalsChangedSinceBuild, "a rebuild keeps the plan id, so the flag must be cleared explicitly")
    }

    // MARK: - Nutrients tab follows today across midnight

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testSameDayChangesNothing() {
        let monday = date(2026, 11, 23)
        let r = FoodLogDay.rolledForward(selected: monday, lastKnownToday: monday,
                                         now: date(2026, 11, 23, 22), calendar: cal)
        XCTAssertEqual(r.selected, monday)
        XCTAssertEqual(r.today, monday)
    }

    func testViewingTodayMovesToTheNewDayAfterMidnight() {
        let monday = date(2026, 11, 23), tuesday = date(2026, 11, 24)
        let r = FoodLogDay.rolledForward(selected: monday, lastKnownToday: monday,
                                         now: date(2026, 11, 24, 7), calendar: cal)
        XCTAssertEqual(r.selected, tuesday, "a meal added Tuesday morning must not be saved to Monday")
        XCTAssertEqual(r.today, tuesday)
    }

    func testABrowsedDayIsLeftAlone() {
        let saturday = date(2026, 11, 21), monday = date(2026, 11, 23), tuesday = date(2026, 11, 24)
        let r = FoodLogDay.rolledForward(selected: saturday, lastKnownToday: monday,
                                         now: date(2026, 11, 24, 7), calendar: cal)
        XCTAssertEqual(r.selected, saturday)
        XCTAssertEqual(r.today, tuesday)
    }

    func testSeveralDaysInTheBackground() {
        let monday = date(2026, 11, 23), friday = date(2026, 11, 27)
        let r = FoodLogDay.rolledForward(selected: monday, lastKnownToday: monday,
                                         now: date(2026, 11, 27, 9), calendar: cal)
        XCTAssertEqual(r.selected, friday)
    }

    func testClockMovedBackNeverLeavesAFutureDaySelected() {
        // Flying west across midnight (or a manual clock change): "today" is now the day before.
        let tuesday = date(2026, 11, 24), monday = date(2026, 11, 23), sunday = date(2026, 11, 22)
        var r = FoodLogDay.rolledForward(selected: tuesday, lastKnownToday: tuesday,
                                         now: date(2026, 11, 23, 23), calendar: cal)
        XCTAssertEqual(r.selected, monday, "was following today")
        r = FoodLogDay.rolledForward(selected: sunday, lastKnownToday: tuesday,
                                     now: date(2026, 11, 23, 23), calendar: cal)
        XCTAssertEqual(r.selected, sunday, "an earlier browsed day is still valid")
    }

    func testDaylightSavingDayRollsLikeAnyOther() {
        // US clocks went back on 2026-11-01; the day is 25 hours long.
        let oct31 = date(2026, 10, 31), nov1 = date(2026, 11, 1), nov2 = date(2026, 11, 2)
        var r = FoodLogDay.rolledForward(selected: oct31, lastKnownToday: oct31,
                                         now: date(2026, 11, 1, 1), calendar: cal)
        XCTAssertEqual(r.selected, nov1)
        r = FoodLogDay.rolledForward(selected: nov1, lastKnownToday: nov1,
                                     now: date(2026, 11, 1, 23), calendar: cal)
        XCTAssertEqual(r.selected, nov1, "23:00 on the long day is still the same day")
        r = FoodLogDay.rolledForward(selected: nov1, lastKnownToday: nov1,
                                     now: date(2026, 11, 2, 0), calendar: cal)
        XCTAssertEqual(r.selected, nov2)
    }
}
