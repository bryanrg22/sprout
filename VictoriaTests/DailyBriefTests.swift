import XCTest
@testable import Victoria

/// Pins the once-a-day Vita brief: the deterministic topic ladder (research-derived
/// priority: gap > milestone > cross-signal > quiet day > check-in), the day cache, the
/// rephrase guardrails — and the prompt-caching invariant on the coach system prompt.
final class DailyBriefTests: XCTestCase {

    private func base() -> DailyBriefService.Signals {
        var s = DailyBriefService.Signals()
        s.name = "Bryan"
        s.daysAway = 1
        s.streak = 3
        return s
    }

    // MARK: - Topic ladder

    func testGapReturnWinsOverEverything() {
        var s = base()
        s.daysAway = 5
        s.trendEasedDown = true            // would otherwise be a milestone
        s.sleepMinutes = 500; s.sleepAvgMinutes = 400
        XCTAssertEqual(DailyBriefService.pick(s).topic, .gapReturn)
    }

    /// A 7+ day gap belongs to the WelcomeBackCard, not the brief.
    func testLongGapIsNotTheBriefsTopic() {
        var s = base()
        s.daysAway = 10
        XCTAssertNotEqual(DailyBriefService.pick(s).topic, .gapReturn)
    }

    func testTrendEasedDownIsAMilestone() {
        var s = base()
        s.trendEasedDown = true
        let picked = DailyBriefService.pick(s)
        XCTAssertEqual(picked.topic, .milestone)
        XCTAssertTrue(picked.headline.lowercased().contains("trend"))
    }

    func testWeeklyStreakMilestone() {
        var s = base()
        s.streak = 14
        XCTAssertEqual(DailyBriefService.pick(s).topic, .milestone)
        s.streak = 15   // not a multiple of 7 — no forced milestone
        XCTAssertNotEqual(DailyBriefService.pick(s).topic, .milestone)
    }

    /// The Google-Health signature move: big effort + steady body = cross-signal receipt.
    func testBigDaySteadyHeartIsCrossSignal() {
        var s = base()
        s.stepsYesterday = 15000; s.stepsAvg = 8000
        s.restingHR = 62; s.restingHRAvg = 61
        let picked = DailyBriefService.pick(s)
        XCTAssertEqual(picked.topic, .crossSignal)
        XCTAssertTrue(picked.body.contains("15,000") || picked.body.contains("15000"))
    }

    func testGreatSleepIsCrossSignal() {
        var s = base()
        s.sleepMinutes = 480; s.sleepAvgMinutes = 400
        XCTAssertEqual(DailyBriefService.pick(s).topic, .crossSignal)
    }

    /// Quiet day is REFRAMED as recovery — never guilt (the anti-Google-card).
    func testQuietDayReassuresNeverShames() {
        var s = base()
        s.stepsYesterday = 900; s.stepsAvg = 9000
        let picked = DailyBriefService.pick(s)
        XCTAssertEqual(picked.topic, .quietDay)
        let text = (picked.headline + " " + picked.body).lowercased()
        for banned in ["should have", "missed", "only ", "failed", "behind", "make up"] {
            XCTAssertFalse(text.contains(banned), "quiet-day copy must not contain '\(banned)'")
        }
    }

    func testNothingStandsOutIsAWarmCheckIn() {
        XCTAssertEqual(DailyBriefService.pick(base()).topic, .checkIn)
    }

    /// Missing metrics never crash the ladder — a signals struct with nothing set still briefs.
    func testEmptySignalsFallThroughSafely() {
        XCTAssertEqual(DailyBriefService.pick(DailyBriefService.Signals()).topic, .checkIn)
    }

    // MARK: - Day cache

    func testCacheRoundTripAndDayScoping() {
        let defaults = UserDefaults(suiteName: "dailyBriefTests")!
        defaults.removePersistentDomain(forName: "dailyBriefTests")

        let key = DailyBriefService.dayKey()
        let brief = DailyBriefService.Brief(headline: "h", body: "b", topic: "checkIn", dayKey: key)
        DailyBriefService.store(brief, defaults: defaults)
        XCTAssertEqual(DailyBriefService.cachedBrief(dayKey: key, defaults: defaults), brief)
        // A different day's key must not serve yesterday's brief.
        XCTAssertNil(DailyBriefService.cachedBrief(dayKey: "1999-01-01", defaults: defaults))
    }

    // MARK: - Rephrase parsing guardrails

    func testParseSplitsHeadlineAndBody() {
        let out = DailyBriefService.parse("Great sleep last night!\nYour body did real repair work — enjoy the energy today.")
        XCTAssertEqual(out?.headline, "Great sleep last night!")
        XCTAssertTrue(out?.body.contains("repair work") == true)
    }

    func testParseRejectsHarmfulOrMalformed() {
        XCTAssertNil(DailyBriefService.parse("Skip a meal today to make up for yesterday.\nYou got this!"))
        XCTAssertNil(DailyBriefService.parse("HeadlineOnlyNoBody"))
        XCTAssertNil(DailyBriefService.parse(""))
        XCTAssertNil(DailyBriefService.parse(String(repeating: "x", count: 600)))
    }

    // MARK: - Prompt-caching invariant (the stable prefix must not move with data)

    /// The stable part of the coach system prompt must be byte-identical regardless of the
    /// live data — otherwise every message invalidates the prompt cache and the split is
    /// worthless. The volatile part must carry the data.
    func testSystemPartsStableIsDataIndependent() {
        let p = UserProfile()
        p.name = "Victoria"
        let noData = CoachContext.systemParts(profile: p, foods: [], weights: [])
        let food = FoodEntry(date: .now, name: "In-N-Out Double Double", calories: 670)
        let withData = CoachContext.systemParts(profile: p, foods: [food], weights: [])

        XCTAssertEqual(noData.stable, withData.stable,
                       "logging food must not change one byte of the cached prefix")
        XCTAssertFalse(noData.stable.contains("In-N-Out"))
        XCTAssertTrue(withData.volatile.contains("In-N-Out Double Double"))
        // And the combined prompt is exactly what system() returns (single source of truth).
        XCTAssertEqual(withData.stable + withData.volatile,
                       CoachContext.system(profile: p, foods: [food], weights: []))
    }

    func testSystemValueBuildsCacheControlBlocks() throws {
        // No prefix → plain string (legacy behavior).
        XCTAssertEqual(AnthropicClient.systemValue("v", cachedPrefix: nil) as? String, "v")
        // With prefix → two text blocks, cache_control on the FIRST only.
        let blocks = try XCTUnwrap(AnthropicClient.systemValue("volatile", cachedPrefix: "stable") as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["text"] as? String, "stable")
        XCTAssertNotNil(blocks[0]["cache_control"])
        XCTAssertEqual(blocks[1]["text"] as? String, "volatile")
        XCTAssertNil(blocks[1]["cache_control"])
    }
}
