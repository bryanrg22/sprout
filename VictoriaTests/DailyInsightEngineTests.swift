import XCTest
@testable import Victoria

/// Tests for the proactive-insight rules engine. The load-bearing guarantees:
/// (1) it celebrates sufficiency/protein/hydration/consistency, (2) it NEVER
/// surfaces a restriction-framed message, (3) the worst-case nudge is a gentle
/// "fuel up" only when genuinely under late in the day, (4) freshness dedup works.
final class DailyInsightEngineTests: XCTestCase {

    /// A balanced "good day" baseline; tweak per test.
    private func goodDay() -> DailyInsightEngine.Input {
        .init(caloriesEaten: 1700, calorieTarget: 1750,
              protein: 130, proteinTarget: 126,
              waterOz: 80, waterGoalOz: 75,
              steps: 9000, stepGoal: 8000,
              loggedAnythingToday: true,
              loggingStreakDays: 4, proteinHitStreakDays: 1,
              hydrationHitStreakDays: 1, workoutToday: false,
              hourOfDay: 20)
    }

    // MARK: Under-eating → gentle fuel nudge is the top pick

    func testUnderEatingLateGetsGentleFuelNudge() {
        var i = goodDay()
        i.caloriesEaten = 600          // ~34% of target
        i.protein = 30
        i.hourOfDay = 19
        let best = DailyInsightEngine.bestInsight(i)
        XCTAssertEqual(best?.id, "fuel_up")
        // And it must read as an invitation, never shame.
        let msg = best?.template.lowercased() ?? ""
        XCTAssertFalse(msg.contains("too much"))
        XCTAssertFalse(msg.contains("over"))
    }

    func testUnderEatingEarlyDoesNotNagYet() {
        var i = goodDay()
        i.caloriesEaten = 300
        i.hourOfDay = 9               // morning — don't nag about low intake yet
        let ids = DailyInsightEngine.allCandidates(i).map(\.id)
        XCTAssertFalse(ids.contains("fuel_up"))
    }

    // MARK: Celebrations

    func testProteinStreakCelebrated() {
        var i = goodDay()
        i.proteinHitStreakDays = 3
        let ids = DailyInsightEngine.allCandidates(i).map(\.id)
        XCTAssertTrue(ids.contains("protein_streak"))
    }

    func testWellFueledWin() {
        let i = goodDay()             // 1700/1750 = 97%
        let ids = DailyInsightEngine.allCandidates(i).map(\.id)
        XCTAssertTrue(ids.contains("well_fueled"))
    }

    func testWeekStreakBeatsSmallerWins() {
        var i = goodDay()
        i.loggingStreakDays = 7
        // Week streak (score 80) should outrank e.g. hydrated (45) / well_fueled (70).
        let best = DailyInsightEngine.bestInsight(i)
        XCTAssertEqual(best?.id, "streak_week")
    }

    // MARK: Silence / freshness

    func testNothingLoggedYieldsNoInsight() {
        var i = goodDay()
        i.loggedAnythingToday = false
        i.caloriesEaten = 0; i.protein = 0; i.waterOz = 0; i.steps = 0
        i.loggingStreakDays = 0; i.proteinHitStreakDays = 0; i.hydrationHitStreakDays = 0
        XCTAssertNil(DailyInsightEngine.bestInsight(i))
    }

    func testFreshnessSkipsRecentlyShown() {
        let i = goodDay()
        let first = DailyInsightEngine.bestInsight(i)
        XCTAssertNotNil(first)
        // Showing the same id again should yield a DIFFERENT insight (or nil), never a repeat.
        let second = DailyInsightEngine.bestInsight(i, recentlyShown: [first!.id])
        XCTAssertNotEqual(second?.id, first?.id)
    }

    // MARK: Comeback day (returning after a break)

    /// Day one back after two silent weeks, eating light in the evening: the engine must
    /// greet the return — NOT fire the "you're under your fuel" nudge, which reads as a
    /// scolding when the user just worked up the nerve to come back.
    func testComebackDayWelcomesInsteadOfFuelNudge() {
        var i = goodDay()
        i.caloriesEaten = 600
        i.hourOfDay = 19
        i.daysAwayBeforeToday = 14
        let ids = DailyInsightEngine.allCandidates(i).map(\.id)
        XCTAssertFalse(ids.contains("fuel_up"))
        XCTAssertEqual(DailyInsightEngine.bestInsight(i)?.id, "welcome_back")
    }

    /// Regression: with no gap (logged yesterday), behavior is exactly as before — the
    /// fuel nudge still fires and no welcome appears.
    func testNormalDayUnchangedByComebackLogic() {
        var i = goodDay()
        i.caloriesEaten = 600
        i.protein = 30
        i.hourOfDay = 19               // daysAwayBeforeToday defaults to 1
        let ids = DailyInsightEngine.allCandidates(i).map(\.id)
        XCTAssertTrue(ids.contains("fuel_up"))
        XCTAssertFalse(ids.contains("welcome_back"))
    }

    // MARK: The hard guarantee — no restriction framing anywhere in the catalog

    func testNoCandidateEverRewardsRestriction() {
        // Sweep a wide range of inputs; assert no surfaced copy uses restriction language.
        let banned = ["eat less", "cut back", "deficit", "too much", "burn off", "cheat", "bad food", "guilt"]
        for cals in stride(from: 0.0, through: 2600, by: 200) {
            for hour in [9, 14, 20] {
                var i = goodDay()
                i.caloriesEaten = cals
                i.hourOfDay = hour
                for c in DailyInsightEngine.allCandidates(i) {
                    let t = c.template.lowercased()
                    for phrase in banned {
                        XCTAssertFalse(t.contains(phrase), "Insight \(c.id) contained banned phrase '\(phrase)'")
                    }
                }
            }
        }
    }
}
