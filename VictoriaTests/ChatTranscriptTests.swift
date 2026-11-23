import XCTest
import SwiftData
@testable import Victoria

/// The chat's window on the store (`ChatTranscript`): what is fetched when the conversation
/// opens, when the reader reaches the top, and when a message arrives — against a real
/// in-memory store on the full schema — and the transcript following the turn engine.
@MainActor
final class ChatTranscriptTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    /// A context does not keep its container alive; the test does.
    private var containers: [ModelContainer] = []

    /// A store holding `count` messages one minute apart: the welcome seed, then alternating
    /// user and coach turns named `m1…`.
    private func store(_ count: Int) throws -> (ModelContainer, ModelContext, [ChatMessage]) {
        let container = try TestStore.makeContainer()
        containers.append(container)
        let context = container.mainContext
        var rows: [ChatMessage] = []
        for index in 0..<count {
            let row = ChatMessage(role: index % 2 == 1 ? "user" : "assistant",
                                  content: index == 0 ? "welcome" : "m\(index)",
                                  createdAt: base.addingTimeInterval(TimeInterval(index) * 60),
                                  isSystemSeed: index == 0)
            context.insert(row)
            rows.append(row)
        }
        try context.save()
        return (container, context, rows)
    }

    // MARK: - Opening

    func testOpeningLoadsOnePageNotTheConversation() throws {
        let (_, context, _) = try store(5_000)
        let transcript = ChatTranscript(context: context)
        XCTAssertEqual(transcript.rows.count, 40, "the newest page, whatever the conversation's length")
        XCTAssertEqual(transcript.rows.first?.content, "m4960")
        XCTAssertEqual(transcript.rows.last?.content, "m4999")
        XCTAssertTrue(transcript.window.hasEarlier)
        XCTAssertEqual(transcript.storedCount(), 5_000)
        XCTAssertEqual(transcript.rows.map(\.createdAt), transcript.rows.map(\.createdAt).sorted(), "oldest first")
    }

    func testAShortConversationLoadsWhole() throws {
        let (_, context, _) = try store(3)
        let transcript = ChatTranscript(context: context)
        XCTAssertEqual(transcript.rows.map(\.content), ["welcome", "m1", "m2"])
        XCTAssertFalse(transcript.window.hasEarlier)
        XCTAssertTrue(transcript.rows[0].isSystemSeed)
        XCTAssertNil(transcript.loadEarlier())
    }

    func testAnEmptyStoreAndATranscriptWithNoStore() throws {
        let (_, context, _) = try store(0)
        let transcript = ChatTranscript(context: context)
        XCTAssertTrue(transcript.rows.isEmpty)
        XCTAssertFalse(transcript.window.hasEarlier)

        let detached = ChatTranscript()
        detached.loadLatest()
        detached.appendNewer()
        XCTAssertNil(detached.loadEarlier())
        XCTAssertTrue(detached.rows.isEmpty)
        XCTAssertEqual(detached.storedCount(), 0)
    }

    // MARK: - Earlier pages

    func testScrollingUpLoadsEarlierPagesUntilTheWelcome() throws {
        let (_, context, rows) = try store(95)
        let transcript = ChatTranscript(context: context, pageSize: 40)
        XCTAssertEqual(transcript.loadEarlier(), rows[55].id, "the row to keep in place")
        XCTAssertEqual(transcript.rows.count, 80)
        XCTAssertEqual(transcript.rows.first?.content, "m15")
        XCTAssertNotNil(transcript.loadEarlier())
        XCTAssertEqual(transcript.rows.map(\.id), rows.map(\.id), "the whole conversation, once, in order")
        XCTAssertFalse(transcript.window.hasEarlier)
        XCTAssertNil(transcript.loadEarlier())
    }

    func testRowsStoredWithOneTimestampSurviveAPageBoundary() throws {
        let container = try TestStore.makeContainer()
        containers.append(container)
        let context = container.mainContext
        var ids: Set<UUID> = []
        for index in 0..<12 {
            // Four rows in the middle share a timestamp.
            let offset = (4...7).contains(index) ? 5 : index
            let row = ChatMessage(role: "user", content: "m\(index)", createdAt: base.addingTimeInterval(TimeInterval(offset) * 60))
            context.insert(row)
            ids.insert(row.id)
        }
        try context.save()
        let transcript = ChatTranscript(context: context, pageSize: 5)
        while transcript.window.hasEarlier { transcript.loadEarlier() }
        XCTAssertEqual(Set(transcript.rows.map(\.id)), ids)
        XCTAssertEqual(transcript.rows.count, 12, "no row twice")
    }

    // MARK: - New messages

    func testANewMessageIsAppendedWithOneSmallFetch() throws {
        let (_, context, _) = try store(95)
        let transcript = ChatTranscript(context: context)
        let tick = transcript.scrollToLatestTick

        context.insert(ChatMessage(role: "user", content: "new question", createdAt: base.addingTimeInterval(100_000)))
        try context.save()
        transcript.appendNewer()
        XCTAssertEqual(transcript.rows.count, 41)
        XCTAssertEqual(transcript.rows.last?.content, "new question")
        XCTAssertEqual(transcript.scrollToLatestTick, tick + 1, "the view is told to show it")

        transcript.appendNewer()   // nothing new
        XCTAssertEqual(transcript.rows.count, 41)
        XCTAssertEqual(transcript.scrollToLatestTick, tick + 1)
    }

    func testAReplyWhileScrolledUpIsCountedAndTheUsersOwnMessageJumpsDown() throws {
        let (_, context, _) = try store(95)
        let transcript = ChatTranscript(context: context)
        transcript.setAtBottom(false)
        let tick = transcript.scrollToLatestTick

        context.insert(ChatMessage(role: "assistant", content: "late reply", createdAt: base.addingTimeInterval(100_000)))
        try context.save()
        transcript.appendNewer()
        XCTAssertEqual(transcript.window.unseenCount, 1)
        XCTAssertEqual(transcript.scrollToLatestTick, tick, "the reader is not moved")
        XCTAssertTrue(transcript.window.showsJumpToLatest)

        context.insert(ChatMessage(role: "user", content: "mine", createdAt: base.addingTimeInterval(100_060)))
        try context.save()
        transcript.appendNewer()
        XCTAssertEqual(transcript.scrollToLatestTick, tick + 1)
        XCTAssertEqual(transcript.window.unseenCount, 0)

        transcript.setAtBottom(false)
        transcript.jumpToLatest()
        XCTAssertTrue(transcript.window.isAtBottom)
        XCTAssertEqual(transcript.scrollToLatestTick, tick + 2)
    }

    func testTheFirstMessageOfAnEmptyConversationOpensIt() throws {
        let (_, context, _) = try store(0)
        let transcript = ChatTranscript(context: context)
        context.insert(ChatMessage(role: "assistant", content: "welcome", createdAt: base, isSystemSeed: true))
        try context.save()
        transcript.appendNewer()
        XCTAssertEqual(transcript.rows.map(\.content), ["welcome"])
    }

    // MARK: - Deletion and reload

    func testARowIsAValueAndOutlivesTheStoredMessage() throws {
        let (_, context, rows) = try store(3)
        let transcript = ChatTranscript(context: context)
        let doomed = rows[2]
        let id = doomed.id
        context.delete(doomed)
        try context.save()

        // The stored object is gone; the row that was on screen can still be read.
        XCTAssertEqual(transcript.rows.last?.content, "m2")
        transcript.remove(ids: [id])
        XCTAssertEqual(transcript.rows.map(\.content), ["welcome", "m1"])
    }

    func testReloadPicksUpWhatAnotherDeviceChanged() throws {
        let (_, context, rows) = try store(95)
        let transcript = ChatTranscript(context: context)
        transcript.loadEarlier()
        XCTAssertEqual(transcript.rows.count, 80)

        context.insert(ChatMessage(role: "user", content: "from the other phone", createdAt: base.addingTimeInterval(200_000)))
        context.delete(rows[90])
        try context.save()
        transcript.attach(context: context)   // attaching again re-reads what is loaded

        XCTAssertEqual(transcript.rows.count, 80, "as much as was loaded before")
        XCTAssertEqual(transcript.rows.last?.content, "from the other phone")
        XCTAssertFalse(transcript.rows.contains { $0.content == "m90" })
    }

    // MARK: - Following the engine

    func testTheTranscriptFollowsTheEngineThroughSendCutOffRetryAndDelete() async throws {
        let (_, context, _) = try store(0)
        let profile = UserProfile()
        profile.name = "Sam"
        context.insert(profile)
        try context.save()

        let wire = ChatWire.anthropic
        let transport = TurnTransport([.ok(wire.turn("Half a rep", stop: .cutOff)),
                                       .ok(wire.turn("Here is the whole reply."))])
        let clock = TickingClock()
        var env = CoachTurnEngine.Environment()
        env.now = { clock.now() }
        env.background = RecordingBackgroundTasks()
        env.runtime = wire.runtime(transport)
        env.otherProviderHasKey = { _ in false }
        let engine = CoachTurnEngine(context: context, profile: profile, env: env)
        let transcript = ChatTranscript(context: context)
        engine.onTranscriptChange = { change in
            switch change {
            case .added: transcript.appendNewer()
            case .removed(let ids): transcript.remove(ids: ids)
            }
        }

        engine.seedWelcomeIfNeeded()
        XCTAssertEqual(transcript.rows.count, 1)
        XCTAssertTrue(transcript.rows[0].isSystemSeed)

        await engine.send(text: "hello")?.value
        XCTAssertEqual(transcript.rows.dropFirst().map(\.content), ["hello", "Half a rep"])
        XCTAssertEqual(engine.failure?.error, .cutOff)

        await engine.retry()?.value
        XCTAssertEqual(transcript.rows.dropFirst().map(\.content), ["hello", "Here is the whole reply."],
                       "the partial reply left the screen when Retry replaced it")
        XCTAssertEqual(transcript.rows.map(\.id),
                       try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)])).map(\.id),
                       "what is on screen is what is stored")

        let last = try XCTUnwrap(transcript.rows.last)
        engine.delete(messageID: last.id)
        XCTAssertEqual(transcript.rows.dropFirst().map(\.content), ["hello"])
    }
}
