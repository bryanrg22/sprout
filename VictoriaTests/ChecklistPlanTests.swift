import XCTest
@testable import Victoria

/// Tests for the PURE pieces of the personalized "Today's checklist" — the code-owned half of
/// the feature (the LLM call itself isn't exercised here). The load-bearing guarantees:
/// (1) icon validation maps unknown/typo'd SF Symbols to "checklist" and lets known ones through,
/// (2) the banned-word filter drops food-restriction / scale framing but keeps movement/rest/prep,
/// (3) `clean` trims, bounds, de-dupes, and applies both of the above,
/// (4) `fallback()` is the static presets as chips with NO proposed tasks, and
/// (5) `userPrompt` is goal- and context-aware (names her sports/bio, steers by direction).
final class ChecklistPlanTests: XCTestCase {

    // MARK: - Icon validation (unknown → "checklist")

    func testValidIconPassesKnownSymbols() {
        // A preset icon, a workout-type glyph, a meal-type glyph, and a curated extra all pass.
        XCTAssertEqual(ChecklistPlanService.validIcon("dumbbell.fill"), "dumbbell.fill")     // preset + strength
        XCTAssertEqual(ChecklistPlanService.validIcon("figure.run"), "figure.run")           // run
        XCTAssertEqual(ChecklistPlanService.validIcon("bed.double.fill"), "bed.double.fill") // preset
        XCTAssertEqual(ChecklistPlanService.validIcon("figure.soccer"), "figure.soccer")     // curated extra
        XCTAssertEqual(ChecklistPlanService.validIcon("carrot.fill"), "carrot.fill")         // meal-type + preset
    }

    func testValidIconRejectsUnknownToChecklist() {
        // A plausible-looking but non-existent / typo'd symbol must fall back, never render blank.
        XCTAssertEqual(ChecklistPlanService.validIcon("figure.quidditch"), "checklist")
        XCTAssertEqual(ChecklistPlanService.validIcon("dumbell.fil"), "checklist")   // typo
        XCTAssertEqual(ChecklistPlanService.validIcon(""), "checklist")
        XCTAssertEqual(ChecklistPlanService.validIcon("   "), "checklist")
    }

    func testValidIconTrimsWhitespace() {
        XCTAssertEqual(ChecklistPlanService.validIcon("  figure.walk  "), "figure.walk")
    }

    func testAllowedIconsIncludesPresetsAndTypes() {
        // The allow-list is derived from the presets + every WorkoutType/MealType glyph.
        for s in ChecklistSuggestion.all {
            XCTAssertTrue(ChecklistPlanService.allowedIcons.contains(s.systemIcon), "missing preset icon \(s.systemIcon)")
        }
        for t in WorkoutType.allCases {
            XCTAssertTrue(ChecklistPlanService.allowedIcons.contains(t.systemImage), "missing workout icon \(t.systemImage)")
        }
        for m in MealType.allCases {
            XCTAssertTrue(ChecklistPlanService.allowedIcons.contains(m.systemImage), "missing meal icon \(m.systemImage)")
        }
        XCTAssertTrue(ChecklistPlanService.allowedIcons.contains("checklist"))
    }

    // MARK: - Banned-word filter (food restriction / scale → dropped)

    func testIsAllowedKeepsMovementRestPrep() {
        for ok in ["Gym", "Leg day", "Soccer", "Evening run", "Yoga", "Stretch",
                   "Meal prep", "Sleep early", "8 hours of sleep", "Drink water",
                   "10 min walk", "Foam roll", "Morning stretch"] {
            XCTAssertTrue(ChecklistPlanService.isAllowed(ok), "should allow \(ok)")
        }
    }

    func testIsAllowedDropsFoodRestrictionAndScale() {
        for bad in ["Eat less", "Eat fewer carbs", "Cut calories", "Stay in a calorie deficit",
                    "Count calories", "Skip breakfast", "Skip a meal", "Fasting until noon",
                    "Intermittent fast", "Restrict snacks", "No eating after 8",
                    "Cheat day", "Weigh in", "Weigh-in", "Step on the scale",
                    "Diet starts today", "Lose weight"] {
            XCTAssertFalse(ChecklistPlanService.isAllowed(bad), "should reject \(bad)")
        }
    }

    func testIsAllowedIsCaseInsensitive() {
        XCTAssertFalse(ChecklistPlanService.isAllowed("EAT LESS"))
        XCTAssertFalse(ChecklistPlanService.isAllowed("Skip Dinner"))
    }

    // MARK: - boundTitle (trim + collapse + cap)

    func testBoundTitleTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(ChecklistPlanService.boundTitle("   Leg    day  "), "Leg day")
        XCTAssertEqual(ChecklistPlanService.boundTitle("Evening\nwalk"), "Evening walk")
    }

    func testBoundTitleCapsLength() {
        let long = String(repeating: "a", count: 100)
        let bounded = ChecklistPlanService.boundTitle(long)
        XCTAssertLessThanOrEqual(bounded.count, 28)
        XCTAssertFalse(bounded.isEmpty)
    }

    // MARK: - clean (validate icons, drop banned, de-dupe, bound)

    func testCleanValidatesIconsAndDropsBanned() {
        let input = [
            ChecklistProposal(title: "Soccer", icon: "figure.soccer"),       // ok
            ChecklistProposal(title: "Leg day", icon: "made.up.symbol"),     // ok title, bad icon → checklist
            ChecklistProposal(title: "Skip breakfast", icon: "figure.run"),  // banned title → dropped
            ChecklistProposal(title: "   ", icon: "figure.walk"),            // empty title → dropped
        ]
        let out = ChecklistPlanService.clean(input, max: 8)
        XCTAssertEqual(out.map(\.title), ["Soccer", "Leg day"])
        XCTAssertEqual(out[0].icon, "figure.soccer")
        XCTAssertEqual(out[1].icon, "checklist")   // unknown icon fell back
    }

    func testCleanDeDupesCaseInsensitivelyAndCaps() {
        let input = [
            ChecklistProposal(title: "Walk", icon: "figure.walk"),
            ChecklistProposal(title: "walk", icon: "figure.walk"),     // dupe (case-insensitive)
            ChecklistProposal(title: "Run", icon: "figure.run"),
            ChecklistProposal(title: "Yoga", icon: "figure.yoga"),
        ]
        let capped = ChecklistPlanService.clean(input, max: 2)
        XCTAssertEqual(capped.count, 2)                       // capped
        XCTAssertEqual(capped.map(\.title), ["Walk", "Run"]) // dupe removed, order preserved
    }

    // MARK: - fallback() shape (no tasks; presets as chips)

    func testFallbackHasNoTasksAndPresetChips() {
        let plan = ChecklistPlanService.fallback()
        XCTAssertTrue(plan.tasks.isEmpty, "fallback must never auto-propose tasks")
        XCTAssertEqual(plan.chips.count, ChecklistSuggestion.all.count)
        XCTAssertEqual(plan.chips.map(\.title), ChecklistSuggestion.all.map(\.title))
        XCTAssertEqual(plan.chips.map(\.icon), ChecklistSuggestion.all.map(\.systemIcon))
        // Every fallback chip's icon is, by construction, in the allow-list.
        for chip in plan.chips {
            XCTAssertEqual(ChecklistPlanService.validIcon(chip.icon), chip.icon)
        }
    }

    // MARK: - userPrompt (goal- and context-aware)

    func testUserPromptIsGoalAware() {
        let lose = ChecklistPlanService.userPrompt(
            name: "Victoria", direction: .lose,
            dataSummary: "- Name: Victoria", bio: "", memoryNotes: "")
        XCTAssertTrue(lose.contains("Victoria"))
        XCTAssertTrue(lose.lowercased().contains("weight loss"))

        let gain = ChecklistPlanService.userPrompt(
            name: "Sam", direction: .gain,
            dataSummary: "- Name: Sam", bio: "", memoryNotes: "")
        XCTAssertTrue(gain.lowercased().contains("strength") || gain.lowercased().contains("lean gain"))

        let maintain = ChecklistPlanService.userPrompt(
            name: "Alex", direction: .maintain,
            dataSummary: "- Name: Alex", bio: "", memoryNotes: "")
        XCTAssertTrue(maintain.lowercased().contains("maintain"))
    }

    func testUserPromptFoldsInDataBioAndMemory() {
        let prompt = ChecklistPlanService.userPrompt(
            name: "Victoria",
            direction: .lose,
            dataSummary: "- Recent workouts: Soccer practice; Leg day at the gym",
            bio: "I play on a rec soccer team Tuesdays",
            memoryNotes: "Lifts 3x/week, hates running")
        // The factual data summary is injected verbatim so the model can spot her sports.
        XCTAssertTrue(prompt.contains("Soccer practice"))
        XCTAssertTrue(prompt.contains("Leg day at the gym"))
        // Her own bio words and the durable notes both ride along to personalize the chips.
        XCTAssertTrue(prompt.contains("rec soccer team"))
        XCTAssertTrue(prompt.contains("hates running"))
    }

    func testUserPromptDefaultsNameAndHandlesEmptyBioNotes() {
        let prompt = ChecklistPlanService.userPrompt(
            name: "   ", direction: .lose,
            dataSummary: "- Name: She", bio: "   ", memoryNotes: "")
        XCTAssertTrue(prompt.contains("your friend"))               // blank name → "your friend"
        XCTAssertTrue(prompt.contains("hasn't written an about-me")) // empty bio handled
        XCTAssertTrue(prompt.contains("don't have durable notes"))   // empty notes handled
    }

    func testUserPromptForbidsFoodAndScaleFraming() {
        // The instruction that keeps Vita on-tone must be present in the per-call turn.
        let prompt = ChecklistPlanService.userPrompt(
            name: "Victoria", direction: .lose,
            dataSummary: "- Name: Victoria", bio: "", memoryNotes: "")
        XCTAssertTrue(prompt.lowercased().contains("nothing about food or the scale"))
    }

    // MARK: - System prompt + schema sanity

    func testSystemPromptBansRestrictionFraming() {
        let s = ChecklistPlanService.system.lowercased()
        XCTAssertTrue(s.contains("never"))
        XCTAssertTrue(s.contains("scale"))
        XCTAssertTrue(s.contains("restrict"))
        XCTAssertTrue(s.contains("showing up"))
    }

    func testSchemaBoundsTasksAndChips() {
        guard let props = ChecklistPlanService.schema["properties"] as? [String: Any],
              let tasks = props["tasks"] as? [String: Any],
              let chips = props["chips"] as? [String: Any] else {
            return XCTFail("schema shape changed")
        }
        XCTAssertEqual(tasks["minItems"] as? Int, 3)
        XCTAssertEqual(tasks["maxItems"] as? Int, 5)
        XCTAssertEqual(chips["minItems"] as? Int, 4)
        XCTAssertEqual(chips["maxItems"] as? Int, 8)
        XCTAssertEqual(ChecklistPlanService.schema["required"] as? [String], ["tasks", "chips"])
    }

    // MARK: - ChecklistProposal codable round-trip (cache safety)

    func testProposalDecodeIgnoresIdAndDefaultsMissingIcon() throws {
        // Cached/wire payloads carry only title+icon; a missing icon decodes to "checklist".
        let json = #"{"title":"Soccer"}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(ChecklistProposal.self, from: json)
        XCTAssertEqual(p.title, "Soccer")
        XCTAssertEqual(p.icon, "checklist")
    }

    func testPlanRoundTripsThroughJSON() throws {
        let plan = ChecklistPlan(
            tasks: [ChecklistProposal(title: "Leg day", icon: "dumbbell.fill")],
            chips: [ChecklistProposal(title: "Walk", icon: "figure.walk")])
        let data = try JSONEncoder().encode(plan)
        let back = try JSONDecoder().decode(ChecklistPlan.self, from: data)
        XCTAssertEqual(back.tasks.map(\.title), ["Leg day"])
        XCTAssertEqual(back.chips.map(\.icon), ["figure.walk"])
    }
}
