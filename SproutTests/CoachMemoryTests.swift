import XCTest
import SwiftData
@testable import Sprout

/// Tests for the AI coach's long-term memory layer. The load-bearing guarantees:
/// (1) `CoachMemory.fetchOrCreate` is a true singleton and seeds from the onboarding note,
/// (2) `CoachContext` injects the memory blocks when present and is byte-for-byte unchanged
/// when memory is nil/empty (backward compatibility), (3) the pure "which messages are
/// un-folded" selection logic is correct at its boundaries, and (4) the JSON parsing for the
/// background consolidation call is robust (fences, partial answers, length clamping).
final class CoachMemoryTests: XCTestCase {

    // MARK: - Helpers

    /// A fresh in-memory SwiftData context holding the models these tests touch.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([CoachMemory.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func profile(name: String = "Sam", note: String = "") -> UserProfile {
        let p = UserProfile()
        p.name = name
        p.onboardingNote = note
        return p
    }

    /// Build a user/assistant ChatMessage with an explicit creation time (seconds offset from
    /// a fixed base) so ordering in the selection tests is deterministic.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func msg(_ offset: TimeInterval,
                     role: String = "user",
                     content: String = "hi",
                     seed: Bool = false) -> ChatMessage {
        ChatMessage(role: role, content: content,
                    createdAt: base.addingTimeInterval(offset), isSystemSeed: seed)
    }

    // MARK: - fetch-or-create singleton + seeding

    func testFetchOrCreateReturnsSameSingleInstance() throws {
        let ctx = try makeContext()
        let first = CoachMemory.fetchOrCreate(in: ctx, profile: profile())
        let second = CoachMemory.fetchOrCreate(in: ctx, profile: profile())
        XCTAssertEqual(first.id, second.id, "fetch-or-create must return the same row")

        let all = try ctx.fetch(FetchDescriptor<CoachMemory>())
        XCTAssertEqual(all.count, 1, "there must be exactly one CoachMemory row")
    }

    func testFetchOrCreateSeedsFromOnboardingNote() throws {
        let ctx = try makeContext()
        let note = "I run 3x a week, hate cardio machines, love spicy food, two kids."
        let memory = CoachMemory.fetchOrCreate(in: ctx, profile: profile(note: note))
        XCTAssertTrue(memory.profileNotes.contains(note),
                      "durable notes should be seeded from the onboarding note")
    }

    func testFetchOrCreateEmptyWhenNoOnboardingNote() throws {
        let ctx = try makeContext()
        let memory = CoachMemory.fetchOrCreate(in: ctx, profile: profile(note: "   "))
        XCTAssertTrue(memory.profileNotes.isEmpty,
                      "blank/whitespace onboarding note should not seed any notes")
    }

    func testFetchOrCreateDoesNotReseedExistingRow() throws {
        let ctx = try makeContext()
        // First creation seeds from the note.
        _ = CoachMemory.fetchOrCreate(in: ctx, profile: profile(note: "original note"))
        // A later fetch with a DIFFERENT note must NOT clobber the existing, evolved notes.
        let again = CoachMemory.fetchOrCreate(in: ctx, profile: profile(note: "totally different"))
        XCTAssertTrue(again.profileNotes.contains("original note"))
        XCTAssertFalse(again.profileNotes.contains("totally different"))
    }

    // MARK: - CoachContext memory injection (backward compatibility)

    func testSystemPromptUnchangedWhenMemoryNil() {
        let p = profile()
        let withDefault = CoachContext.system(profile: p, foods: [], weights: [])
        let withExplicitNil = CoachContext.system(profile: p, foods: [], weights: [], memory: nil)
        XCTAssertEqual(withDefault, withExplicitNil,
                       "omitting memory must equal passing nil (default-arg backward compat)")
        // And none of the memory section labels should appear.
        XCTAssertFalse(withDefault.contains("durable notes"))
        XCTAssertFalse(withDefault.contains("single source of truth"))
    }

    func testSystemPromptUnchangedWhenMemoryEmpty() throws {
        let ctx = try makeContext()
        let p = profile()
        let emptyMemory = CoachMemory.fetchOrCreate(in: ctx, profile: profile(note: ""))
        let baseline = CoachContext.system(profile: p, foods: [], weights: [], memory: nil)
        let withEmpty = CoachContext.system(profile: p, foods: [], weights: [], memory: emptyMemory)
        XCTAssertEqual(baseline, withEmpty,
                       "an empty memory must inject nothing (identical to nil)")
    }

    func testSystemPromptInjectsNotesAndSummaryWhenPresent() {
        let p = profile()
        let memory = CoachMemory(profileNotes: "Loves spicy food. Two kids. Hates burpees.",
                                 conversationSummary: "Lately working through a busy-week plateau.")
        let out = CoachContext.system(profile: p, foods: [], weights: [], memory: memory)
        XCTAssertTrue(out.contains("Loves spicy food"))
        XCTAssertTrue(out.contains("busy-week plateau"))
        // The precedence note (numbers win) must be present so memory can't override stats.
        XCTAssertTrue(out.contains("single source of truth"))
    }

    func testMemoryBlockInjectsOnlyNonEmptyHalves() {
        // Only notes present.
        let notesOnly = CoachContext.memoryBlock(
            CoachMemory(profileNotes: "Prefers morning workouts.", conversationSummary: "")
        )
        XCTAssertTrue(notesOnly.contains("Prefers morning workouts"))
        XCTAssertTrue(notesOnly.contains("durable notes"))
        XCTAssertFalse(notesOnly.contains("(summary)"),
                       "an empty summary must not add the summary block")

        // Only summary present.
        let summaryOnly = CoachContext.memoryBlock(
            CoachMemory(profileNotes: "", conversationSummary: "Catching up after a trip.")
        )
        XCTAssertTrue(summaryOnly.contains("Catching up after a trip"))
        XCTAssertFalse(summaryOnly.contains("durable notes"),
                       "empty notes must not add the durable-notes block")

        // Both empty → nothing at all.
        XCTAssertEqual(CoachContext.memoryBlock(CoachMemory()), "")
        // Nil → nothing at all.
        XCTAssertEqual(CoachContext.memoryBlock(nil), "")
    }

    func testMemoryNeverDuplicatesLiveNumbers() {
        // A belt-and-suspenders check on the architecture's core invariant: the system prompt's
        // numeric facts come from the data snapshot, NOT memory — even if memory contained a
        // number-shaped string, the precedence note tells the model the live numbers win.
        let memory = CoachMemory(profileNotes: "Mentioned wanting to feel strong.",
                                 conversationSummary: "Settling into a routine.")
        let out = CoachContext.system(profile: profile(), foods: [], weights: [], memory: memory)
        // The authoritative line must come before the memory block.
        guard let truthRange = out.range(of: "single source of truth"),
              let notesRange = out.range(of: "Mentioned wanting to feel strong") else {
            return XCTFail("expected both the precedence note and the memory notes")
        }
        XCTAssertTrue(truthRange.lowerBound < notesRange.lowerBound,
                      "the 'numbers win' note must precede the qualitative memory")
    }

    // MARK: - Pure selection logic: which messages are un-folded

    func testNothingToConsolidateWhenWithinWindow() {
        let msgs = (0..<3).map { msg(TimeInterval($0)) }   // 3 ≤ window
        let result = CoachMemoryService.messagesToConsolidate(
            messages: msgs, windowSize: 16, summarizedThrough: nil)
        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(CoachMemoryService.hasWorkToDo(
            messages: msgs, windowSize: 16, summarizedThrough: nil))
    }

    func testConsolidatesOnlyMessagesOlderThanWindow() {
        // 5 messages, window 3 → the oldest 2 are "older" and should be folded.
        let msgs = (0..<5).map { msg(TimeInterval($0)) }
        let result = CoachMemoryService.messagesToConsolidate(
            messages: msgs, windowSize: 3, summarizedThrough: nil)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.createdAt),
                       [msgs[0].createdAt, msgs[1].createdAt],
                       "should return the two oldest, in order")
        XCTAssertTrue(CoachMemoryService.hasWorkToDo(
            messages: msgs, windowSize: 3, summarizedThrough: nil))
    }

    func testHighWaterMarkExcludesAlreadyFolded() {
        // 6 messages, window 2 → older set is indices 0..3. If we've already folded through
        // index 1's time, only indices 2 and 3 remain un-folded.
        let msgs = (0..<6).map { msg(TimeInterval($0)) }
        let result = CoachMemoryService.messagesToConsolidate(
            messages: msgs, windowSize: 2, summarizedThrough: msgs[1].createdAt)
        XCTAssertEqual(result.map(\.createdAt),
                       [msgs[2].createdAt, msgs[3].createdAt])
    }

    func testNothingLeftWhenHighWaterCoversAllOlder() {
        let msgs = (0..<5).map { msg(TimeInterval($0)) }
        // Folded through the newest "older" message (index 2, since window 2 keeps 3 & 4).
        let result = CoachMemoryService.messagesToConsolidate(
            messages: msgs, windowSize: 2, summarizedThrough: msgs[2].createdAt)
        XCTAssertTrue(result.isEmpty)
    }

    func testSeedMessagesAreNeverConsolidated() {
        // The first message is the canned welcome seed; it must be excluded from both the
        // window accounting and the fold set (it's persona, never sent to the API).
        var msgs: [ChatMessage] = [msg(0, role: "assistant", content: "welcome", seed: true)]
        msgs += (1..<5).map { msg(TimeInterval($0)) }   // 4 real messages
        // Window 2 → of the 4 REAL messages, the oldest 2 (indices 1,2) are older.
        let result = CoachMemoryService.messagesToConsolidate(
            messages: msgs, windowSize: 2, summarizedThrough: nil)
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.isSystemSeed }, "the seed must never be folded")
        XCTAssertEqual(result.map(\.content), ["hi", "hi"])
    }

    // MARK: - Consolidation JSON parsing

    func testParseValidJSON() {
        let raw = #"{"notes": "Likes oatmeal.", "summary": "Doing well this week."}"#
        let result = CoachMemoryService.parse(raw, fallbackNotes: "OLD N", fallbackSummary: "OLD S")
        XCTAssertEqual(result?.profileNotes, "Likes oatmeal.")
        XCTAssertEqual(result?.conversationSummary, "Doing well this week.")
    }

    func testParseStripsCodeFences() {
        let raw = """
        ```json
        {"notes": "Prefers tea.", "summary": "Back from vacation."}
        ```
        """
        let result = CoachMemoryService.parse(raw, fallbackNotes: "", fallbackSummary: "")
        XCTAssertEqual(result?.profileNotes, "Prefers tea.")
        XCTAssertEqual(result?.conversationSummary, "Back from vacation.")
    }

    func testParseKeepsFallbackForMissingField() {
        // Only "notes" returned → summary must fall back to the prior value, not blank out.
        let raw = #"{"notes": "New fact."}"#
        let result = CoachMemoryService.parse(raw, fallbackNotes: "old", fallbackSummary: "KEEP ME")
        XCTAssertEqual(result?.profileNotes, "New fact.")
        XCTAssertEqual(result?.conversationSummary, "KEEP ME")
    }

    func testParseEmptyFieldFallsBackNotWipes() {
        // The model returning "" for notes must NOT wipe durable memory — keep the prior value.
        let raw = #"{"notes": "  ", "summary": "fresh recap"}"#
        let result = CoachMemoryService.parse(raw, fallbackNotes: "KEEP", fallbackSummary: "old")
        XCTAssertEqual(result?.profileNotes, "KEEP")
        XCTAssertEqual(result?.conversationSummary, "fresh recap")
    }

    func testParseReturnsNilOnGarbage() {
        XCTAssertNil(CoachMemoryService.parse("not json at all",
                                              fallbackNotes: "n", fallbackSummary: "s"))
        // Valid JSON but neither expected key → treat as failure (don't clobber memory).
        XCTAssertNil(CoachMemoryService.parse(#"{"foo": "bar"}"#,
                                              fallbackNotes: "n", fallbackSummary: "s"))
    }

    func testParseClampsOverlongFields() {
        let longNotes = String(repeating: "a", count: CoachMemoryService.notesCharBudget + 500)
        let raw = "{\"notes\": \"\(longNotes)\", \"summary\": \"ok\"}"
        let result = CoachMemoryService.parse(raw, fallbackNotes: "", fallbackSummary: "")
        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(result!.profileNotes.count,
                                 CoachMemoryService.notesCharBudget + 1, // +1 for the trailing …
                                 "overlong notes must be clamped to the budget")
    }

    // MARK: - App-owned figures are not stored (EVAL_REPORT 36)

    /// Sentences claude-haiku-5-5 wrote in the MemoryFold run of 2026-11-24 (Evals/runs/
    /// 20261124-212339-MemoryFold): each states a figure the app owns and must not be stored.
    func testSentencesThatStateAnAppOwnedFigureAreRemoved() {
        let recorded = [
            "Sam asked about the daily calorie range, which Vita gave as centred around 1,650 kcal.",
            "Alex confirmed the current calorie target is 2,750 kcal a day.",
            "Alex's current calorie target of 2,750 kcal/day was confirmed.",
            "Sam logged a weight of 156.8 and the trend is easing down steadily.",
            "Alex asked about the 3,000 kcal daily target, which is app-owned and was not stored here.",
        ]
        for sentence in recorded {
            XCTAssertTrue(CoachMemoryService.statesAnAppOwnedFigure(sentence), sentence)
            XCTAssertEqual(CoachMemoryService.removingAppOwnedFigures(sentence), "", sentence)
        }
        for sentence in ["Hit 10,000 steps on Sunday.", "Aims for 120 g of protein.", "Weighed 72.4 kg at the gym.",
                         "Her calorie target is 2000.", "Down to 181 lbs.", "The scale said 160 this morning."] {
            XCTAssertTrue(CoachMemoryService.statesAnAppOwnedFigure(sentence), sentence)
        }
    }

    /// Lines from the same run that hold a number which is not the app's: times and counts.
    func testTimesCountsAndYearsAreKept() {
        let kept = [
            "• Eats chicken and fish; tried vegetarian for 4 days but returned to including meat",
            "- Has daycare pickup duty on weekdays; can't train before 7 PM on those days",
            "- Salmon is favourite dinner; happy to eat 3x weekly",
            "- Teacher; lunch at 11:30 during term",
            "- Works at a bakery starting at 4 a.m.; in bed by 8 p.m.",
            "Lost weight before the 2019 wedding and wants to again.",
            "Works 12-hour shifts on the ward.",
            "Lifting weights 3x a week for 1.5 hours.",
        ]
        for line in kept {
            XCTAssertFalse(CoachMemoryService.statesAnAppOwnedFigure(line), line)
            XCTAssertEqual(CoachMemoryService.removingAppOwnedFigures(line), line, line)
        }
    }

    func testOnlyTheSentenceWithTheFigureGoes() {
        let summary = "Alex works a 4 a.m. bakery shift. Alex confirmed the 2,750 kcal target stays in place. "
            + "Soy is out of every plan."
        XCTAssertEqual(CoachMemoryService.removingAppOwnedFigures(summary),
                       "Alex works a 4 a.m. bakery shift. Soy is out of every plan.")
    }

    func testABulletKeepsItsMarkerOrGoesWhole() {
        let notes = """
        - Allergic to shellfish
        - Target is 1,700 kcal a day
        - Weighed 156.8 this week. Prefers walks to runs.
        1. Calorie target 2,100. Likes oats.
        """
        XCTAssertEqual(CoachMemoryService.removingAppOwnedFigures(notes), """
        - Allergic to shellfish
        - Prefers walks to runs.
        1. Likes oats.
        """)
    }

    func testTheGuardIsIdempotentAndLeavesCleanTextByteForByte() {
        let clean = "- Likes oats  \n•  Pilates Tue/Fri at 7am\n\nBusy term ahead."
        XCTAssertEqual(CoachMemoryService.removingAppOwnedFigures(clean), clean)
        let dirty = "Sam logged a weight of 156.8. Pilates is going well.\n- Target 1,650 kcal\n- Likes tea"
        let once = CoachMemoryService.removingAppOwnedFigures(dirty)
        XCTAssertEqual(once, "Pilates is going well.\n- Likes tea")
        XCTAssertEqual(CoachMemoryService.removingAppOwnedFigures(once), once)
    }

    func testParseRemovesFiguresFromBothFields() {
        let raw = #"{"notes": "- Likes tea\n- Target 1,650 kcal", "summary": "Sam weighed 156.8. Busy week."}"#
        let result = CoachMemoryService.parse(raw, fallbackNotes: "", fallbackSummary: "")
        XCTAssertEqual(result?.profileNotes, "- Likes tea")
        XCTAssertEqual(result?.conversationSummary, "Busy week.")
    }

    /// A field that held nothing but a figure counts as not provided: the memory keeps its
    /// prior value instead of being wiped, as it does for an empty field.
    func testAFieldThatWasOnlyAFigureFallsBackNotWipes() {
        let raw = #"{"notes": "New: allergic to soy.", "summary": "Alex confirmed the 2,750 kcal target."}"#
        let result = CoachMemoryService.parse(raw, fallbackNotes: "old", fallbackSummary: "KEEP ME")
        XCTAssertEqual(result?.profileNotes, "New: allergic to soy.")
        XCTAssertEqual(result?.conversationSummary, "KEEP ME")
        // Both fields only figures: the reply still counts (the batch is folded, not sent again),
        // and the memory stays as it was.
        let onlyFigures = CoachMemoryService.parse(#"{"notes": "Target 1,700 kcal.", "summary": "Weighed 150.2."}"#,
                                                   fallbackNotes: "n", fallbackSummary: "s")
        XCTAssertEqual(onlyFigures?.profileNotes, "n")
        XCTAssertEqual(onlyFigures?.conversationSummary, "s")
    }

    /// The prior memory passed back as a fallback is held to the same rule: memory written
    /// before the guard existed loses its figures the next time it is folded.
    func testTheFallbackIsCleanedToo() {
        let raw = #"{"notes": "Likes tea."}"#
        let result = CoachMemoryService.parse(raw, fallbackNotes: "", fallbackSummary: "Goal check. Target is 1,700 kcal.")
        XCTAssertEqual(result?.conversationSummary, "Goal check.")
    }
}
