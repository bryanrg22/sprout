import XCTest
@testable import Victoria

/// Pins the pure logic of the adaptive Plan (see docs/adaptive-plan.md): the `CoachPlan` model's
/// JSON-backed arrays + derived fields, and `PlanService`'s mapping of a model `write_plan` result
/// into a `CoachPlan` (tolerant of missing / loosely-typed fields). The actual Opus call is verified
/// live in the sim; this covers everything that can go wrong without the network.
final class AdaptivePlanTests: XCTestCase {

    // MARK: - CoachPlan model

    func testInsightsRoundTripThroughJSON() {
        let plan = CoachPlan(insights: [
            PlanInsight(title: "Protein short", body: "78g vs 130g", tone: .nudge),
            PlanInsight(title: "Nice streak", body: "5 days", tone: .win),
        ])
        XCTAssertEqual(plan.insights.count, 2)
        XCTAssertEqual(plan.insights[0].title, "Protein short")
        XCTAssertEqual(plan.insights[0].tone, .nudge)
        XCTAssertEqual(plan.insights[1].tone, .win)
    }

    func testChangelogRoundTrip() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = CoachPlan(changelog: [PlanChange(date: when, summary: "Built your plan")])
        XCTAssertEqual(plan.changelog.count, 1)
        XCTAssertEqual(plan.changelog[0].summary, "Built your plan")
    }

    func testEmptyArraysAreSafe() {
        let plan = CoachPlan()
        XCTAssertEqual(plan.insights.count, 0)
        XCTAssertEqual(plan.changelog.count, 0)
        XCTAssertEqual(plan.insightsJSON, "[]")
    }

    func testRangeAndConfidenceDerived() {
        let p = CoachPlan(calorieMin: 1600, calorieMax: 1750, dataPointsAtBuild: 3)
        XCTAssertTrue(p.hasRange)
        XCTAssertTrue(p.isEarlyRead)                       // 3 < 7
        XCTAssertTrue(p.calorieRangeText.contains("–"))    // a real range
        XCTAssertTrue(p.calorieRangeText.contains("600"))
        XCTAssertTrue(p.calorieRangeText.contains("750"))

        let none = CoachPlan(calorieMin: 0, calorieMax: 0, dataPointsAtBuild: 20)
        XCTAssertFalse(none.hasRange)
        XCTAssertEqual(none.calorieRangeText, "")
        XCTAssertFalse(none.isEarlyRead)

        let single = CoachPlan(calorieMin: 1700, calorieMax: 1700)
        XCTAssertFalse(single.calorieRangeText.contains("–"))  // not a range
    }

    // MARK: - PlanService.makePlan (result → model)

    private var sampleResult: [String: Any] {
        [
            "headline": "On track for 135",
            "assessment": "You're trending down nicely.",
            "strategy": "Hold the deficit, hit protein.",
            "calorie_min": 1600,
            "calorie_max": 1750,
            "protein_target": 130,
            "goal_summary": "Lose to 135",
            "timeframe": "by end of summer",
            "insights": [
                ["title": "Protein's short", "body": "78g vs 130g target", "tone": "nudge"],
                ["title": "Great streak", "body": "5 days in a row", "tone": "win"],
                ["title": "Bogus tone", "body": "x", "tone": "not-a-tone"],   // tone → .nudge
                ["body": "no title here"],                                     // dropped
            ],
            "changelog_note": "Built your starting plan.",
        ]
    }

    func testMakePlanMapsCoreFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = PlanService.makePlan(from: sampleResult, dataPoints: 5, now: now)
        XCTAssertEqual(plan.headline, "On track for 135")
        XCTAssertEqual(plan.calorieMin, 1600)
        XCTAssertEqual(plan.calorieMax, 1750)
        XCTAssertEqual(plan.proteinTarget, 130)
        XCTAssertEqual(plan.timeframe, "by end of summer")
        XCTAssertEqual(plan.dataPointsAtBuild, 5)
        XCTAssertTrue(plan.isEarlyRead)
    }

    func testMakePlanFiltersAndParsesInsights() {
        let plan = PlanService.makePlan(from: sampleResult, dataPoints: 5)
        // The title-less insight is dropped; 3 remain.
        XCTAssertEqual(plan.insights.count, 3)
        XCTAssertEqual(plan.insights[0].tone, .nudge)
        XCTAssertEqual(plan.insights[1].tone, .win)
        XCTAssertEqual(plan.insights[2].tone, .nudge)   // unknown tone falls back to .nudge
    }

    func testMakePlanStampsChangelog() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = PlanService.makePlan(from: sampleResult, dataPoints: 5, now: now)
        XCTAssertEqual(plan.changelog.count, 1)
        XCTAssertEqual(plan.changelog[0].summary, "Built your starting plan.")
    }

    func testMakePlanToleratesMissingFieldsAndStringNumbers() {
        let sparse: [String: Any] = [
            "headline": "Hi",
            "calorie_min": "1600",   // number as string
            "calorie_max": 1750.0,   // double
            // no insights, no changelog_note, no protein
        ]
        let plan = PlanService.makePlan(from: sparse, dataPoints: 0)
        XCTAssertEqual(plan.calorieMin, 1600)
        XCTAssertEqual(plan.calorieMax, 1750)
        XCTAssertEqual(plan.proteinTarget, 0)
        XCTAssertEqual(plan.insights.count, 0)
        XCTAssertEqual(plan.changelog[0].summary, "Plan created.")   // default note
    }

    // MARK: - Helpers

    func testLoggedDayCountIsDistinctDays() {
        let cal = Calendar(identifier: .gregorian)
        let d0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let d1 = cal.date(byAdding: .day, value: -1, to: d0)!
        let foods = [
            FoodEntry(date: d0, name: "a", calories: 100),
            FoodEntry(date: d0, name: "b", calories: 100),   // same day
            FoodEntry(date: d1, name: "c", calories: 100),
        ]
        let weights = [WeightEntry(date: d0, weightLbs: 150)]  // same day as food
        XCTAssertEqual(PlanService.loggedDayCount(foods: foods, weights: weights, calendar: cal), 2)
    }

    func testUserContentIncludesIntakeWhenPresent() {
        let withIntake = PlanService.userContent(dataSummary: "DATA", intake: "I edit videos 6h a day")
        XCTAssertTrue(withIntake.contains("DATA"))
        XCTAssertTrue(withIntake.contains("I edit videos 6h a day"))

        let without = PlanService.userContent(dataSummary: "DATA", intake: "   ")
        XCTAssertTrue(without.contains("DATA"))
        XCTAssertTrue(without.contains("didn't add extra context"))
    }
}
