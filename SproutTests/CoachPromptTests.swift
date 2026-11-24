import XCTest
@testable import Sprout

/// Tests for the PURE pieces of Vita's personalized quick-prompt chips — the code-owned half
/// (the LLM call itself isn't exercised). The load-bearing guarantees:
/// (1) the 1–2 FIXED constants are ALWAYS present and ALWAYS lead the row,
/// (2) the no-key / failure fallback is exactly the fixed list (constants + generic extras),
/// (3) the banned-word `sanitize`/`isAllowed` filter drops food-restriction / scale framing but
///     keeps progress / training / fuel / feelings prompts,
/// (4) `clean` bounds, de-dupes (incl. against the constants), and caps the count,
/// (5) the period bucket key changes every ~3 days (so chips refresh) and is stable within a
///     bucket (so a plain re-open doesn't regenerate), and
/// (6) `userPrompt` is goal- and context-aware (names her data/bio/notes, steers by direction).
final class CoachPromptTests: XCTestCase {

    // MARK: - Constants always present + lead the row

    func testConstantsAreOneOrTwoShortStarters() {
        XCTAssertFalse(CoachPromptService.constants.isEmpty)
        XCTAssertLessThanOrEqual(CoachPromptService.constants.count, 2)
        // The two stable starters Bryan asked for are present.
        XCTAssertEqual(CoachPromptService.constants, ["Review my day", "How's my week?"])
        // Each constant is chip-short.
        for c in CoachPromptService.constants {
            XCTAssertLessThanOrEqual(c.split(separator: " ").count, 6, "constant too long: \(c)")
        }
    }

    func testFixedPromptsLeadWithConstantsAndAreNonEmpty() {
        let fixed = CoachPromptService.fixedPrompts()
        XCTAssertFalse(fixed.isEmpty, "the chip row must never be empty")
        // Constants come first, in order.
        XCTAssertEqual(Array(fixed.prefix(CoachPromptService.constants.count)), CoachPromptService.constants)
        // The generic extras follow.
        for extra in CoachPromptService.fixedExtras {
            XCTAssertTrue(fixed.contains(extra), "fixed list should include extra \(extra)")
        }
        // No duplicates (case-insensitive) — constants can't collide with extras.
        let lowered = fixed.map { $0.lowercased() }
        XCTAssertEqual(lowered.count, Set(lowered).count, "fixed list must have no dupes")
    }

    /// The no-key / failure path returns exactly `fixedPrompts()` — pinning the documented
    /// fallback shape (constants + extras) that the view also seeds the chips with synchronously.
    func testFallbackShapeIsConstantsPlusExtras() {
        XCTAssertEqual(CoachPromptService.fixedPrompts(),
                       CoachPromptService.constants + CoachPromptService.fixedExtras)
    }

    // MARK: - dedupedAppending (constants always lead, no dupes)

    func testDedupedAppendingPrependsConstantsAndDropsDupes() {
        let out = CoachPromptService.dedupedAppending(
            ["How did leg day feel?", "how's my week?", "Why am I tired?"],   // 2nd dupes a constant
            to: CoachPromptService.constants)
        // Constants lead.
        XCTAssertEqual(Array(out.prefix(2)), CoachPromptService.constants)
        // The case-insensitive duplicate of "How's my week?" was dropped.
        XCTAssertEqual(out.filter { $0.lowercased() == "how's my week?" }.count, 1)
        // The genuinely new personalized prompts came through.
        XCTAssertTrue(out.contains("How did leg day feel?"))
        XCTAssertTrue(out.contains("Why am I tired?"))
    }

    func testDedupedAppendingDropsEmptyAndWhitespace() {
        let out = CoachPromptService.dedupedAppending(["", "   ", "Real one"], to: ["Keep"])
        XCTAssertEqual(out, ["Keep", "Real one"])
    }

    // MARK: - Banned-word filter (food restriction / scale → dropped)

    func testIsAllowedKeepsProgressTrainingFuelFeelings() {
        for ok in ["How's my week?", "Review my day", "I'm feeling discouraged",
                   "Is this enough protein?", "How did leg day go?", "Why am I so tired?",
                   "Did I drink enough water?", "I crushed my workout", "How's my streak?",
                   "Help me hit my protein", "Am I fueling enough?", "How's my trend looking?"] {
            XCTAssertTrue(CoachPromptService.isAllowed(ok), "should allow \(ok)")
        }
    }

    func testIsAllowedDropsFoodRestrictionAndScale() {
        for bad in ["How do I eat less?", "Help me cut calories", "Stay in a calorie deficit",
                    "Should I skip breakfast?", "Tips for fasting", "Intermittent fast plan",
                    "How to restrict snacks", "Is a cheat day okay?", "When do I weigh in?",
                    "Weigh-in time", "Should I step on the scale?", "How to lose weight faster",
                    "Best diet for me", "How do I count calories?"] {
            XCTAssertFalse(CoachPromptService.isAllowed(bad), "should reject \(bad)")
        }
    }

    func testIsAllowedIsCaseInsensitiveAndSparesBreakfast() {
        XCTAssertFalse(CoachPromptService.isAllowed("EAT LESS today"))
        XCTAssertFalse(CoachPromptService.isAllowed("Skip Dinner tonight"))
        // "breakfast" must NOT trip the whole-word "fast" guard.
        XCTAssertTrue(CoachPromptService.isAllowed("What's a good breakfast?"))
    }

    // MARK: - boundPrompt (trim + collapse + unquote + cap)

    func testBoundPromptTrimsCollapsesAndUnquotes() {
        XCTAssertEqual(CoachPromptService.boundPrompt("  How's   my   week?  "), "How's my week?")
        XCTAssertEqual(CoachPromptService.boundPrompt("\"I crushed leg day\""), "I crushed leg day")
        XCTAssertEqual(CoachPromptService.boundPrompt("Why\nam I tired?"), "Why am I tired?")
    }

    func testBoundPromptCapsLength() {
        let long = String(repeating: "a", count: 100)
        let bounded = CoachPromptService.boundPrompt(long)
        XCTAssertLessThanOrEqual(bounded.count, 42)
        XCTAssertFalse(bounded.isEmpty)
    }

    // MARK: - clean (bound, drop banned, de-dupe vs constants + each other, cap count)

    func testCleanDropsBannedAndEmptyKeepsGood() {
        let input = [
            "How did leg day feel?",     // ok
            "Help me cut calories",      // banned → dropped
            "   ",                       // empty → dropped
            "Why am I so tired?",        // ok
        ]
        let out = CoachPromptService.clean(input)
        XCTAssertEqual(out, ["How did leg day feel?", "Why am I so tired?"])
    }

    func testCleanDeDupesAgainstConstantsAndItself() {
        let input = [
            "How's my week?",            // dupes a constant → dropped
            "How did leg day go?",
            "how did leg day go?",       // case-insensitive dupe → dropped
            "Why am I tired?",
        ]
        let out = CoachPromptService.clean(input)
        XCTAssertFalse(out.contains { $0.lowercased() == "how's my week?" }, "must not re-emit a constant")
        XCTAssertEqual(out, ["How did leg day go?", "Why am I tired?"])
    }

    func testCleanCapsCount() {
        let input = (0..<10).map { "Personalized prompt number \($0)" }
        let out = CoachPromptService.clean(input)
        XCTAssertLessThanOrEqual(out.count, CoachPromptService.personalizedCount)
    }

    // MARK: - Period bucket (refreshes every ~3 days; stable within a bucket)

    func testPeriodBucketChangesEveryThreeDays() {
        XCTAssertEqual(CoachPromptService.bucketDays, 3)
        // Anchor on the reference date (timeIntervalSinceReferenceDate == 0).
        let ref = Date(timeIntervalSinceReferenceDate: 0)
        let day: TimeInterval = 86_400

        let b0 = CoachPromptService.periodBucket(ref)
        // Same bucket across the next ~3 days (well within the window).
        XCTAssertEqual(CoachPromptService.periodBucket(ref.addingTimeInterval(1 * day + 100)), b0)
        XCTAssertEqual(CoachPromptService.periodBucket(ref.addingTimeInterval(2 * day + 100)), b0)
        // 3 days later → the next bucket.
        XCTAssertEqual(CoachPromptService.periodBucket(ref.addingTimeInterval(3 * day + 100)), b0 + 1)
        // 6 days later → two buckets on.
        XCTAssertEqual(CoachPromptService.periodBucket(ref.addingTimeInterval(6 * day + 100)), b0 + 2)
    }

    func testPeriodKeyIsPerUserAndBucketStableWithinWindow() {
        let user = UUID()
        let other = UUID()
        let ref = Date(timeIntervalSinceReferenceDate: 0)
        let day: TimeInterval = 86_400

        let k0 = CoachPromptService.periodKey(userId: user, now: ref)
        // Stable within the same 3-day bucket → a plain re-open serves cache, doesn't regenerate.
        XCTAssertEqual(CoachPromptService.periodKey(userId: user, now: ref.addingTimeInterval(2 * day + 100)), k0)
        // Rolls over after 3 days → chips refresh.
        XCTAssertNotEqual(CoachPromptService.periodKey(userId: user, now: ref.addingTimeInterval(3 * day + 100)), k0)
        // Different user → different key (picks never leak between profiles on a shared device).
        XCTAssertNotEqual(CoachPromptService.periodKey(userId: other, now: ref), k0)
        // The key embeds the user id and the bucket.
        XCTAssertTrue(k0.contains(user.uuidString))
        XCTAssertTrue(k0.hasSuffix("#\(CoachPromptService.periodBucket(ref))"))
    }

    func testCacheKeyMatchesPeriodBucket() {
        let user = UUID()
        let ref = Date(timeIntervalSinceReferenceDate: 0)
        let expected = "vita.prompts.\(user.uuidString).\(CoachPromptService.periodBucket(ref))"
        XCTAssertEqual(CoachPromptService.cacheKey(userId: user, now: ref), expected)
    }

    // MARK: - Cache round-trip (UserDefaults, personalized strings only)

    func testCacheRoundTripsPersonalizedStrings() {
        // A unique key so the test never collides with a real cache entry.
        let key = "vita.prompts.test.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertNil(CoachPromptService.readCache(key), "absent key reads nil")
        let prompts = ["How did leg day go?", "Why am I tired?", "How's my streak?"]
        CoachPromptService.writeCache(key, prompts)
        XCTAssertEqual(CoachPromptService.readCache(key), prompts)
    }

    func testReadCacheNilOnEmptyArray() {
        let key = "vita.prompts.test.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        CoachPromptService.writeCache(key, [])     // empty → treated as no cache
        XCTAssertNil(CoachPromptService.readCache(key))
    }

    // MARK: - System prompt + schema sanity

    func testSystemPromptBansRestrictionFraming() {
        let s = CoachPromptService.system.lowercased()
        XCTAssertTrue(s.contains("never"))
        XCTAssertTrue(s.contains("scale"))
        XCTAssertTrue(s.contains("short"))
    }

    func testSchemaBoundsPrompts() {
        guard let props = CoachPromptService.schema["properties"] as? [String: Any],
              let prompts = props["prompts"] as? [String: Any] else {
            return XCTFail("schema shape changed")
        }
        XCTAssertEqual(prompts["type"] as? String, "array")
        XCTAssertEqual(CoachPromptService.schema["required"] as? [String], ["prompts"])
    }

    // MARK: - userPrompt (goal- and context-aware)

    func testUserPromptIsGoalAware() {
        let lose = CoachPromptService.userPrompt(
            name: "Sam", direction: .lose,
            dataSummary: "- Name: Sam", bio: "", memoryNotes: "")
        XCTAssertTrue(lose.contains("Sam"))
        XCTAssertTrue(lose.lowercased().contains("weight loss"))

        let gain = CoachPromptService.userPrompt(
            name: "Sam", direction: .gain,
            dataSummary: "- Name: Sam", bio: "", memoryNotes: "")
        XCTAssertTrue(gain.lowercased().contains("strength") || gain.lowercased().contains("lean gain"))

        let maintain = CoachPromptService.userPrompt(
            name: "Alex", direction: .maintain,
            dataSummary: "- Name: Alex", bio: "", memoryNotes: "")
        XCTAssertTrue(maintain.lowercased().contains("maintain"))
    }

    func testUserPromptFoldsInDataBioAndMemoryAndNamesConstants() {
        let prompt = CoachPromptService.userPrompt(
            name: "Sam",
            direction: .lose,
            dataSummary: "- Recent workouts: Soccer practice; Leg day at the gym",
            bio: "I play on a rec soccer team Tuesdays",
            memoryNotes: "Lifts 3x/week, hates running")
        // The factual data summary is injected verbatim so the model can ground the chips.
        XCTAssertTrue(prompt.contains("Soccer practice"))
        XCTAssertTrue(prompt.contains("Leg day at the gym"))
        // Her own bio words and the durable notes both ride along to personalize the chips.
        XCTAssertTrue(prompt.contains("rec soccer team"))
        XCTAssertTrue(prompt.contains("hates running"))
        // The constants are named as "already shown" so the model doesn't waste a slot on them.
        for c in CoachPromptService.constants { XCTAssertTrue(prompt.contains(c)) }
    }

    func testUserPromptDefaultsNameAndHandlesEmptyBioNotes() {
        let prompt = CoachPromptService.userPrompt(
            name: "   ", direction: .lose,
            dataSummary: "- Name: She", bio: "   ", memoryNotes: "")
        XCTAssertTrue(prompt.contains("your friend"))                // blank name → "your friend"
        XCTAssertTrue(prompt.contains("hasn't written an about-me"))  // empty bio handled
        XCTAssertTrue(prompt.contains("don't have durable notes"))    // empty notes handled
    }

    func testUserPromptForbidsScaleFraming() {
        let prompt = CoachPromptService.userPrompt(
            name: "Sam", direction: .lose,
            dataSummary: "- Name: Sam", bio: "", memoryNotes: "")
        XCTAssertTrue(prompt.lowercased().contains("scale"))
    }
}
