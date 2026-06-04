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
        XCTAssertEqual(PlanService.loggedDayCount(foods: foods, weights: weights, now: d0, calendar: cal), 2)
    }

    func testLoggedDayCountExcludesFutureDatedEntries() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let today = FoodEntry(date: now, name: "a", calories: 100)
        let future = FoodEntry(date: cal.date(byAdding: .day, value: 3, to: now)!, name: "b", calories: 100)
        XCTAssertEqual(PlanService.loggedDayCount(foods: [today, future], weights: [], now: now, calendar: cal), 1,
                       "a future-dated entry must not inflate the logged-day count")
    }

    /// num() salvages a messy numeric string (the dead-today string branch) — keeps the sign and the
    /// first dot rather than dropping them.
    func testMakePlanSalvagesMessyNumericStrings() {
        let plan = PlanService.makePlan(from: ["calorie_min": "1,600 kcal", "calorie_max": "~1750"], dataPoints: 0)
        XCTAssertEqual(plan.calorieMin, 1600)
        XCTAssertEqual(plan.calorieMax, 1750)
    }

    func testUserContentIncludesIntakeWhenPresent() {
        let withIntake = PlanService.userContent(dataSummary: "DATA", intake: "I edit videos 6h a day")
        XCTAssertTrue(withIntake.contains("DATA"))
        XCTAssertTrue(withIntake.contains("I edit videos 6h a day"))

        let without = PlanService.userContent(dataSummary: "DATA", intake: "   ")
        XCTAssertTrue(without.contains("DATA"))
        XCTAssertTrue(without.contains("didn't add extra context"))
    }

    // MARK: - Review pass: changelog preservation (the core P3 invariant)

    /// The whole point of the review pass: adaptation is visible. Given an old plan with N changelog
    /// entries and a freshly-authored result (which always carries exactly one new entry), merging
    /// must yield N+1 entries — the old ones first, in order, with the new one appended last.
    func testReviewMergeAppendsNewChangelogEntryPreservingHistory() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let oldChangelog = [
            PlanChange(date: t0, summary: "Built your starting plan."),
            PlanChange(date: t0.addingTimeInterval(86_400), summary: "Bumped protein to 140g."),
        ]
        // A fresh review result → makePlan stamps exactly one new entry.
        let reviewResult: [String: Any] = [
            "headline": "Still on track",
            "calorie_min": 1600, "calorie_max": 1750, "protein_target": 140,
            "insights": [],
            "changelog_note": "Trimmed ceiling 50 kcal — loss stalled this week.",
        ]
        let fresh = PlanService.makePlan(from: reviewResult,
                                         dataPoints: 14,
                                         now: t0.addingTimeInterval(2 * 86_400))

        let merged = PlanService.mergedChangelog(old: oldChangelog, new: fresh.changelog)

        XCTAssertEqual(merged.count, 3)                                     // N (2) + 1
        XCTAssertEqual(merged[0].summary, "Built your starting plan.")      // old first…
        XCTAssertEqual(merged[1].summary, "Bumped protein to 140g.")        // …in order…
        XCTAssertEqual(merged[2].summary, "Trimmed ceiling 50 kcal — loss stalled this week.") // new last
    }

    /// Generalizes the invariant across N: any old count yields N+1, with the appended entry last.
    func testReviewMergeYieldsNPlusOneForAnyHistoryLength() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for n in 0...5 {
            let old = (0..<n).map { i in
                PlanChange(date: base.addingTimeInterval(Double(i) * 86_400), summary: "entry \(i)")
            }
            let fresh = PlanService.makePlan(from: ["changelog_note": "new review line"], dataPoints: 0)
            let merged = PlanService.mergedChangelog(old: old, new: fresh.changelog)
            XCTAssertEqual(merged.count, n + 1, "N=\(n) should yield N+1 entries")
            XCTAssertEqual(merged.last?.summary, "new review line", "new entry must be last (N=\(n))")
            // Old entries preserved in their original order at the front.
            for i in 0..<n { XCTAssertEqual(merged[i].summary, "entry \(i)") }
        }
    }

    /// The merge keeps the old entries' identities/dates intact (it doesn't rebuild them) and never
    /// mutates the inputs — so a default "No change needed" review still records a line in history.
    func testReviewMergePreservesOldEntryDatesAndDoesNotMutateInputs() {
        let d0 = Date(timeIntervalSince1970: 1_700_000_000)
        let old = [PlanChange(date: d0, summary: "Built your starting plan.")]
        // A "nothing changed" review: no changelog_note → makePlan defaults it to "Plan created.".
        let fresh = PlanService.makePlan(from: [:], dataPoints: 10)
        let merged = PlanService.mergedChangelog(old: old, new: fresh.changelog)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].date, d0)                 // original date carried through unchanged
        XCTAssertEqual(merged[0].id, old[0].id)            // same entry, not a rebuilt copy
        XCTAssertEqual(old.count, 1)                       // input left untouched
    }

    // MARK: - daysSince helper

    func testDaysSinceCountsWholeCalendarDays() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
            .addingTimeInterval(11 * 3600)                  // 11am "today"
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: now)!
        XCTAssertEqual(PlanService.daysSince(threeDaysAgo, now: now, calendar: cal), 3)
        XCTAssertEqual(PlanService.daysSince(now, now: now, calendar: cal), 0)         // same day → 0
        // Defends against a future-dated plan (clock skew / CloudKit): never negative.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(PlanService.daysSince(tomorrow, now: now, calendar: cal), 0)
    }

    // MARK: - Review prompts (pure)

    func testReviewUserContentIncludesPlanAndData() {
        let plan = CoachPlan(
            headline: "On track for 135",
            assessment: "Trending down nicely.",
            calorieMin: 1600, calorieMax: 1750, proteinTarget: 130,
            insights: [PlanInsight(title: "Protein short", body: "78g vs 130g", tone: .nudge)]
        )
        let out = PlanService.reviewUserContent(plan: plan, dataSummary: "FRESH-DATA", daysSince: 5)
        XCTAssertTrue(out.contains("On track for 135"))     // current plan echoed in…
        XCTAssertTrue(out.contains("FRESH-DATA"))           // …alongside the new data
        XCTAssertTrue(out.contains("Protein short"))        // existing insights surfaced for comparison
        XCTAssertTrue(out.contains("5 days ago"))           // cadence framing
        XCTAssertTrue(out.contains("write_plan"))           // re-emit instruction
    }

    func testReviewUserContentSingularDayAndTodayPhrasing() {
        let plan = CoachPlan(headline: "Hi")
        XCTAssertTrue(PlanService.reviewUserContent(plan: plan, dataSummary: "D", daysSince: 1)
            .contains("1 day ago"))                          // singular, not "1 days"
        XCTAssertTrue(PlanService.reviewUserContent(plan: plan, dataSummary: "D", daysSince: 0)
            .contains("today"))                              // 0 days → "today"
    }

    func testReviewUserContentHandlesUnsetTargetsAndNoInsights() {
        let plan = CoachPlan(headline: "Hi")               // no range, no protein, no insights
        let out = PlanService.reviewUserContent(plan: plan, dataSummary: "D", daysSince: 2)
        XCTAssertTrue(out.contains("not set"))             // range + protein both render "not set"
        XCTAssertTrue(out.contains("none on the current plan"))
    }

    func testReviewSystemPromptKeepsRangeRuleAndChangelogInstruction() {
        let profile = UserProfile()
        profile.name = "Victoria"
        let sys = PlanService.reviewSystemPrompt(profile: profile)
        XCTAssertTrue(sys.contains("Victoria"))
        XCTAssertTrue(sys.contains("RANGE"))                       // range-not-point rule survives
        XCTAssertTrue(sys.contains("No change needed — on track")) // the explicit no-op line
        XCTAssertTrue(sys.lowercased().contains("only if the data warrants"))
    }

    // MARK: - Coaching patterns (beneficial teaching moments, P4)

    private func femaleLossProfile() -> UserProfile {
        let p = UserProfile()
        p.sex = .female
        p.pace = .relaxed   // a loss pace
        return p
    }

    private func days(_ kcal: Double, count: Int, endingAt now: Date, cal: Calendar) -> [FoodEntry] {
        (0..<count).map { FoodEntry(date: cal.date(byAdding: .day, value: -$0, to: now)!, name: "x", calories: kcal) }
    }

    func testCoachingFlagsFrameVeryLowIntakeAsEatMore() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let flags = PlanService.coachingFlags(profile: femaleLossProfile(),
                                              foods: days(900, count: 3, endingAt: now, cal: cal),
                                              weights: [], now: now, calendar: cal)
        // Beneficial framing ("eat a bit MORE → better results"), not a warning.
        XCTAssertTrue(flags.contains { $0.lowercased().contains("eating a bit more") })
    }

    func testCoachingFlagsQuietAtHealthyIntake() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let flags = PlanService.coachingFlags(profile: femaleLossProfile(),
                                              foods: days(1700, count: 3, endingAt: now, cal: cal),
                                              weights: [], now: now, calendar: cal)
        XCTAssertTrue(flags.isEmpty)
    }

    func testCoachingNoteEmptyWhenNothingStandsOut() {
        XCTAssertEqual(PlanService.coachingNote(profile: femaleLossProfile(), foods: [], weights: []), "")
    }

    /// Only 1–2 logged days at a low number is under-LOGGING, not under-eating — the "eat more"
    /// teaching moment must stay quiet until there's enough signal (≥3 days).
    func testCoachingFlagsQuietWithTooFewLoggedDays() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let flags = PlanService.coachingFlags(profile: femaleLossProfile(),
                                              foods: days(500, count: 2, endingAt: now, cal: cal),
                                              weights: [], now: now, calendar: cal)
        XCTAssertTrue(flags.isEmpty)
    }

    /// A future-dated weigh-in (clock skew / fat-finger) must not count toward the ≥3 real weigh-ins
    /// the fast-loss moment needs, nor slide the trend window — here only 2 real points → no flag.
    func testCoachingFlagsIgnoreFutureDatedWeighIn() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let weights = [
            WeightEntry(date: cal.date(byAdding: .day, value: -7, to: now)!, weightLbs: 180),
            WeightEntry(date: now, weightLbs: 160),                                  // steep real loss
            WeightEntry(date: cal.date(byAdding: .day, value: 7, to: now)!, weightLbs: 140), // future
        ]
        let flags = PlanService.coachingFlags(profile: femaleLossProfile(),
                                              foods: [], weights: weights, now: now, calendar: cal)
        XCTAssertTrue(flags.isEmpty, "future weigh-in shouldn't be counted as a third real data point")
    }

    // MARK: - makePlan: inverted calorie range

    /// The model occasionally swaps the bounds (min > max). makePlan must normalize, not store it
    /// as-is where `hasRange` is false and the targets silently read "not set".
    func testMakePlanNormalizesInvertedCalorieRange() {
        let plan = PlanService.makePlan(from: ["calorie_min": 1900, "calorie_max": 1500], dataPoints: 5)
        XCTAssertEqual(plan.calorieMin, 1500)
        XCTAssertEqual(plan.calorieMax, 1900)
        XCTAssertTrue(plan.hasRange)
        XCTAssertTrue(plan.calorieRangeText.contains("–"))
    }

    // MARK: - Plan-intake → durable profile notes (PlanIntakeView.foldingIntake)

    /// Editing-then-rebuilding the plan must REPLACE the prior intake line, not stack a near-duplicate,
    /// while leaving unrelated durable notes untouched.
    func testFoldingIntakeReplacesPriorLineInsteadOfDuplicating() {
        let prefix = PlanIntakeView.intakePrefix
        let first = prefix + "her life + training: edits videos"
        let once = PlanIntakeView.foldingIntake(first, into: "- likes oat milk", prefix: prefix)
        XCTAssertTrue(once.contains("likes oat milk"))
        XCTAssertTrue(once.contains("edits videos"))

        let second = prefix + "her life + training: edits videos · lifts 3x/week"   // superset edit
        let twice = PlanIntakeView.foldingIntake(second, into: once, prefix: prefix)
        XCTAssertEqual(twice.components(separatedBy: prefix).count - 1, 1)   // exactly ONE intake line
        XCTAssertTrue(twice.contains("lifts 3x/week"))
        XCTAssertTrue(twice.contains("likes oat milk"))                     // unrelated note preserved
    }

    /// Over the cap, drop WHOLE leading lines (never a mid-sentence `suffix`), always keeping the
    /// just-added line.
    func testFoldingIntakeBoundsByWholeLinesKeepingNewest() {
        let prefix = PlanIntakeView.intakePrefix
        let bulky = (0..<60).map { "- old durable fact number \($0) about her" }.joined(separator: "\n")
        let addition = prefix + "her life + training: the freshest line"
        let out = PlanIntakeView.foldingIntake(addition, into: bulky, prefix: prefix, maxChars: 500)
        XCTAssertLessThanOrEqual(out.count, 500)
        XCTAssertTrue(out.hasSuffix("the freshest line"))                   // newest survives the trim
        XCTAssertFalse(out.contains("number 0 "))                          // oldest dropped from front
        for line in out.split(separator: "\n") {                           // whole-line integrity
            XCTAssertTrue(line.hasPrefix("- old durable") || line.hasPrefix(prefix))
        }
    }

    // MARK: - Research phase (web-search grounding)

    func testResearchPromptsAreGoalAwareAndCarryHerWords() {
        let p = femaleLossProfile()        // a loss pace
        p.name = "Victoria"
        let sys = PlanService.researchSystemPrompt(profile: p)
        XCTAssertTrue(sys.contains("Victoria"))
        XCTAssertTrue(sys.lowercased().contains("search"))                  // it's a live-web brief
        XCTAssertTrue(sys.lowercased().contains("source"))                  // must name sources

        let user = PlanService.researchUserContent(profile: p, intake: "I edit videos 6h a day")
        XCTAssertTrue(user.contains("fat loss"))                           // direction-aware
        XCTAssertTrue(user.contains("I edit videos 6h a day"))             // her words drive the searches
        XCTAssertTrue(user.lowercased().contains("no plan yet"))           // research-only, not the plan
    }
}
