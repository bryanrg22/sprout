import XCTest
@testable import Sprout

/// The paging arithmetic of the chat (`ChatWindow`) and the scroll rules beside it
/// (`ChatScrollBox`). Pure: the "store" is an array, and time is whatever the test says.
final class ChatWindowTests: XCTestCase {

    private struct Item: ChatWindowItem, Equatable {
        let id: UUID
        let createdAt: Date
        let isUser: Bool
        let name: String
    }

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// `count` messages one minute apart, oldest first, alternating from the coach's welcome.
    private func conversation(_ count: Int) -> [Item] {
        (0..<count).map { index in
            Item(id: UUID(), createdAt: base.addingTimeInterval(TimeInterval(index) * 60),
                 isUser: index % 2 == 1, name: "m\(index)")
        }
    }

    /// What a store answers for a request: newest first, at or before `before`, limited.
    private func answer(_ request: ChatWindow<Item>.Request, from store: [Item]) -> [Item] {
        let eligible = store.filter { item in request.before.map { item.createdAt <= $0 } ?? true }
        return Array(eligible.sorted { $0.createdAt > $1.createdAt }.prefix(request.limit))
    }

    private func opened(_ store: [Item], pageSize: Int) -> ChatWindow<Item> {
        var window = ChatWindow<Item>(pageSize: pageSize)
        let request = window.latestRequest
        window.load(newestFirst: answer(request, from: store), for: request)
        return window
    }

    @discardableResult
    private func loadEarlier(_ window: inout ChatWindow<Item>, from store: [Item]) -> UUID? {
        guard let request = window.beginLoadingEarlier() else { return nil }
        return window.finishLoadingEarlier(newestFirst: answer(request, from: store))
    }

    // MARK: - Opening

    func testDefaultPageSizeAndTheOpeningRequest() {
        let window = ChatWindow<Item>()
        XCTAssertEqual(window.pageSize, 40)
        XCTAssertEqual(window.latestRequest, .init(before: nil, limit: 41),
                       "one more than a page, only to learn whether anything older exists")
        XCTAssertTrue(window.items.isEmpty)
        XCTAssertFalse(window.hasEarlier)
        XCTAssertTrue(window.isAtBottom)
        XCTAssertFalse(window.showsJumpToLatest, "an empty chat has nowhere to jump")
        XCTAssertEqual(ChatWindow<Item>(pageSize: 0).pageSize, 1, "a page is never empty")
    }

    func testAnEmptyConversation() {
        var window = opened([], pageSize: 10)
        XCTAssertTrue(window.items.isEmpty)
        XCTAssertFalse(window.hasEarlier)
        XCTAssertNil(window.beginLoadingEarlier())
        XCTAssertNil(window.newestLoaded)
        XCTAssertFalse(window.showsTimestamp(at: 0))
    }

    func testOnlyTheWelcomeSeed() {
        let store = conversation(1)
        var window = opened(store, pageSize: 10)
        XCTAssertEqual(window.items, store)
        XCTAssertFalse(window.hasEarlier)
        XCTAssertNil(window.beginLoadingEarlier())
        XCTAssertTrue(window.showsTimestamp(at: 0), "the first loaded message carries a timestamp")
    }

    func testOpeningLoadsTheNewestPageOldestFirst() {
        let store = conversation(95)
        let window = opened(store, pageSize: 40)
        XCTAssertEqual(window.items.count, 40, "a window, not the conversation")
        XCTAssertEqual(window.items.first?.name, "m55")
        XCTAssertEqual(window.items.last?.name, "m94")
        XCTAssertTrue(window.hasEarlier)
        XCTAssertEqual(window.items, Array(store.suffix(40)), "oldest first, in order")
    }

    func testExactlyOnePageHasNothingEarlier() {
        let store = conversation(40)
        var window = opened(store, pageSize: 40)
        XCTAssertEqual(window.items.count, 40)
        XCTAssertFalse(window.hasEarlier, "the extra row asked for did not come back")
        XCTAssertNil(window.beginLoadingEarlier())

        window = opened(conversation(41), pageSize: 40)
        XCTAssertEqual(window.items.count, 40)
        XCTAssertTrue(window.hasEarlier, "one message more than a page is an earlier page")
        XCTAssertEqual(window.items.first?.name, "m1")
    }

    // MARK: - Earlier pages

    func testEarlierPagesArePrependedUntilTheBeginning() {
        let store = conversation(95)
        var window = opened(store, pageSize: 40)

        var anchor = loadEarlier(&window, from: store)
        XCTAssertEqual(anchor, store[55].id, "the row to hold in place is the one that was oldest")
        XCTAssertEqual(window.items.count, 80)
        XCTAssertEqual(window.items.first?.name, "m15")
        XCTAssertTrue(window.hasEarlier)
        XCTAssertFalse(window.isLoadingEarlier)

        anchor = loadEarlier(&window, from: store)
        XCTAssertEqual(anchor, store[15].id)
        XCTAssertEqual(window.items, store, "every message, once, in order")
        XCTAssertFalse(window.hasEarlier, "the last page was a short one")

        XCTAssertNil(loadEarlier(&window, from: store), "nothing left to load")
        XCTAssertEqual(window.items.count, 95)
    }

    func testALastPageOfExactlyOnePageEndsThePaging() {
        let store = conversation(80)
        var window = opened(store, pageSize: 40)
        XCTAssertTrue(window.hasEarlier)
        loadEarlier(&window, from: store)
        XCTAssertEqual(window.items, store)
        XCTAssertFalse(window.hasEarlier)
    }

    func testOnlyOneEarlierLoadRunsAtATime() {
        let store = conversation(95)
        var window = opened(store, pageSize: 40)
        let first = window.beginLoadingEarlier()
        XCTAssertNotNil(first)
        XCTAssertTrue(window.isLoadingEarlier)
        XCTAssertNil(window.beginLoadingEarlier(), "a second scroll to the top while loading asks for nothing")

        window.cancelLoadingEarlier()
        XCTAssertFalse(window.isLoadingEarlier)
        XCTAssertEqual(window.items.count, 40, "a cancelled load changes nothing")
        XCTAssertNotNil(window.beginLoadingEarlier(), "and the next scroll to the top may try again")
    }

    func testAPageThatArrivesWithoutARequestIsIgnored() {
        let store = conversation(95)
        var window = opened(store, pageSize: 40)
        XCTAssertNil(window.finishLoadingEarlier(newestFirst: Array(store.prefix(40).reversed())))
        XCTAssertEqual(window.items.count, 40)
    }

    func testMessagesThatShareATimestampAreNeitherLostNorDuplicatedAcrossAPageBoundary() {
        // Twelve messages, where four in the middle were stored with the same timestamp
        // (an import, or a burst within one clock tick).
        var store = conversation(12)
        let shared = store[5].createdAt
        for index in 4...7 {
            store[index] = Item(id: store[index].id, createdAt: shared, isUser: store[index].isUser, name: store[index].name)
        }
        var window = opened(store, pageSize: 5)   // m7…m11: the boundary cuts through the tie
        XCTAssertEqual(window.items.count, 5)

        let request = window.beginLoadingEarlier()
        XCTAssertEqual(request?.before, shared, "at or before the oldest loaded timestamp")
        XCTAssertEqual(request?.limit, 5 + 1 + 1, "widened by the loaded message that shares it")
        window.cancelLoadingEarlier()

        while window.hasEarlier { loadEarlier(&window, from: store) }
        XCTAssertEqual(Set(window.items.map(\.id)), Set(store.map(\.id)), "every message is loaded")
        XCTAssertEqual(window.items.count, store.count, "and none twice")
    }

    // MARK: - New messages

    func testAMessageThatArrivesAtTheBottomIsFollowed() {
        var store = conversation(10)
        var window = opened(store, pageSize: 40)
        let reply = Item(id: UUID(), createdAt: base.addingTimeInterval(3600), isUser: false, name: "reply")
        store.append(reply)

        XCTAssertTrue(window.append(oldestFirst: [reply]), "at the bottom: scroll to the new message")
        XCTAssertEqual(window.items.last, reply)
        XCTAssertEqual(window.unseenCount, 0)
        XCTAssertFalse(window.append(oldestFirst: [reply]), "the same row again adds nothing")
        XCTAssertEqual(window.items.count, 11)
    }

    func testAReplyThatArrivesWhileTheReaderIsScrolledUpIsCountedNotFollowed() {
        var window = opened(conversation(60), pageSize: 40)
        window.setAtBottom(false)
        XCTAssertTrue(window.showsJumpToLatest)

        let first = Item(id: UUID(), createdAt: base.addingTimeInterval(7200), isUser: false, name: "r1")
        let second = Item(id: UUID(), createdAt: base.addingTimeInterval(7201), isUser: false, name: "r2")
        XCTAssertFalse(window.append(oldestFirst: [first]), "the reader is left where they are")
        XCTAssertEqual(window.unseenCount, 1)
        XCTAssertFalse(window.append(oldestFirst: [first, second]), "the tail fetch may return a loaded row again")
        XCTAssertEqual(window.unseenCount, 2)
        XCTAssertEqual(window.items.suffix(2).map(\.name), ["r1", "r2"])

        window.setAtBottom(true)
        XCTAssertEqual(window.unseenCount, 0, "reaching the newest message clears the count")
        XCTAssertFalse(window.showsJumpToLatest)
    }

    func testTheUsersOwnMessageAlwaysScrollsToTheBottom() {
        var window = opened(conversation(60), pageSize: 40)
        window.setAtBottom(false)
        let pending = Item(id: UUID(), createdAt: base.addingTimeInterval(7000), isUser: false, name: "unseen")
        window.append(oldestFirst: [pending])
        XCTAssertEqual(window.unseenCount, 1)

        let mine = Item(id: UUID(), createdAt: base.addingTimeInterval(7300), isUser: true, name: "mine")
        XCTAssertTrue(window.append(oldestFirst: [mine]), "sending shows what was sent")
        XCTAssertEqual(window.unseenCount, 0)
    }

    func testANewMessageDoesNotDisturbThePaging() {
        var store = conversation(95)
        var window = opened(store, pageSize: 40)
        let reply = Item(id: UUID(), createdAt: base.addingTimeInterval(99_999), isUser: false, name: "reply")
        store.append(reply)
        window.append(oldestFirst: [reply])
        XCTAssertTrue(window.hasEarlier)

        loadEarlier(&window, from: store)
        XCTAssertEqual(window.items.count, 81)
        XCTAssertEqual(window.items.first?.name, "m15", "the earlier page starts where it would have")
        XCTAssertEqual(Set(window.items.map(\.id)).count, 81)
    }

    // MARK: - Deletion

    func testDeletionDropsLoadedRowsOnly() {
        let store = conversation(95)
        var window = opened(store, pageSize: 40)
        window.setAtBottom(false)
        window.append(oldestFirst: [Item(id: UUID(), createdAt: base.addingTimeInterval(99_999), isUser: false, name: "r")])
        XCTAssertEqual(window.unseenCount, 1)

        window.remove(ids: [store[60].id, store[94].id, UUID()])
        XCTAssertEqual(window.items.count, 39)
        XCTAssertFalse(window.items.contains { $0.name == "m60" || $0.name == "m94" })
        XCTAssertTrue(window.hasEarlier, "deleting a loaded row loads and unloads nothing")
        XCTAssertEqual(window.unseenCount, 1)

        window.remove(ids: [])
        XCTAssertEqual(window.items.count, 39)

        window.remove(ids: Set(window.items.map(\.id)))
        XCTAssertTrue(window.items.isEmpty)
        XCTAssertEqual(window.unseenCount, 0)
        XCTAssertFalse(window.showsJumpToLatest)
        XCTAssertNil(window.beginLoadingEarlier(), "with nothing loaded there is no cursor to page from")
    }

    func testPagingContinuesCorrectlyAfterTheOldestLoadedRowIsDeleted() {
        var store = conversation(95)
        var window = opened(store, pageSize: 40)
        let oldest = store[55]
        store.remove(at: 55)
        window.remove(ids: [oldest.id])
        loadEarlier(&window, from: store)
        XCTAssertEqual(window.items.count, 79)
        XCTAssertEqual(window.items, Array(store.suffix(79)))
    }

    // MARK: - Reload

    func testReloadKeepsEverythingThatWasLoadedAndPicksUpWhatChanged() {
        var store = conversation(95)
        var window = opened(store, pageSize: 40)
        loadEarlier(&window, from: store)
        XCTAssertEqual(window.reloadRequest, .init(before: nil, limit: 81))

        // While the app was away another device added two messages and one was deleted.
        store.append(Item(id: UUID(), createdAt: base.addingTimeInterval(90_000), isUser: true, name: "n1"))
        store.append(Item(id: UUID(), createdAt: base.addingTimeInterval(90_060), isUser: false, name: "n2"))
        store.remove(at: 30)
        let request = window.reloadRequest
        window.load(newestFirst: answer(request, from: store), for: request)

        XCTAssertEqual(window.items.count, 80)
        XCTAssertEqual(window.items.last?.name, "n2")
        XCTAssertFalse(window.items.contains { $0.name == "m30" })
        XCTAssertTrue(window.hasEarlier)

        let small = opened(conversation(3), pageSize: 40)
        XCTAssertEqual(small.reloadRequest.limit, 41, "never fewer than a page")
    }

    // MARK: - Timestamps

    func testATimestampAfterAGapOfMoreThanFiveMinutes() {
        let times: [TimeInterval] = [0, 60, 360, 661, 662]
        let store = times.enumerated().map { index, offset in
            Item(id: UUID(), createdAt: base.addingTimeInterval(offset), isUser: index % 2 == 1, name: "m\(index)")
        }
        let window = opened(store, pageSize: 40)
        XCTAssertEqual((0..<5).map(window.showsTimestamp(at:)), [true, false, false, true, false],
                       "exactly five minutes is not a gap; five minutes and a second is")
        XCTAssertFalse(window.showsTimestamp(at: 5))
        XCTAssertFalse(window.showsTimestamp(at: -1))
    }

    /// The oldest loaded message is compared with the one just older than the window, so a
    /// page arriving above it never adds or removes its timestamp (a row on screen changing
    /// height is a jump: it moved the held bubble 27 pt, EVAL_REPORT 32).
    func testTheOldestLoadedMessageKeepsItsTimestampWhenThePageBeforeItArrives() {
        let store = conversation(95)   // one minute apart: no gaps anywhere
        var window = opened(store, pageSize: 40)
        XCTAssertEqual(window.items.first?.name, "m55")
        XCTAssertEqual(window.earlierBoundary, store[54].createdAt)
        XCTAssertFalse(window.showsTimestamp(at: 0), "m54 is a minute before m55: no timestamp, even before it is loaded")

        loadEarlier(&window, from: store)
        let m55 = window.items.firstIndex { $0.name == "m55" }!
        XCTAssertFalse(window.showsTimestamp(at: m55), "unchanged by the page above it")
        XCTAssertEqual(window.items.first?.name, "m15")
        XCTAssertFalse(window.showsTimestamp(at: 0))

        loadEarlier(&window, from: store)
        XCTAssertEqual(window.items.first?.name, "m0")
        XCTAssertFalse(window.hasEarlier)
        XCTAssertNil(window.earlierBoundary)
        XCTAssertTrue(window.showsTimestamp(at: 0), "the first message of the conversation carries one")
    }

    func testAGapJustBeforeTheWindowIsATimestampBeforeAndAfterTheLoad() {
        var store = conversation(95)
        // m55 and everything after it come ten minutes later.
        store = store.enumerated().map { index, item in
            index < 55 ? item : Item(id: item.id, createdAt: item.createdAt.addingTimeInterval(600),
                                     isUser: item.isUser, name: item.name)
        }
        var window = opened(store, pageSize: 40)
        XCTAssertTrue(window.showsTimestamp(at: 0))
        loadEarlier(&window, from: store)
        XCTAssertTrue(window.showsTimestamp(at: window.items.firstIndex { $0.name == "m55" }!))
    }

    func testReloadingKeepsTheBoundary() {
        let store = conversation(95)
        var window = opened(store, pageSize: 40)
        let request = window.reloadRequest
        window.load(newestFirst: answer(request, from: store), for: request)
        XCTAssertEqual(window.earlierBoundary, store[54].createdAt)
        XCTAssertFalse(window.showsTimestamp(at: 0))
    }

    // MARK: - Scroll rules

    // The list is flipped: the newest message is the START of the content (offset
    // `-startInset` there) and the oldest loaded one is its END (offset
    // `contentHeight + endInset - viewHeight` there). The numbers are a view 874 pt tall with
    // insets of 116 and 193 pt around 16 235 pt of content.

    func testNearTheNewestMessage() {
        XCTAssertTrue(ChatScrollBox.nearNewest(startInset: 116, offset: -116, viewHeight: 874), "at the newest message")
        XCTAssertTrue(ChatScrollBox.nearNewest(startInset: 116, offset: -116 + 119, viewHeight: 874))
        XCTAssertFalse(ChatScrollBox.nearNewest(startInset: 116, offset: -116 + 120, viewHeight: 874),
                       "120 pt away is no longer at the newest (about two short bubbles)")
        XCTAssertTrue(ChatScrollBox.nearNewest(startInset: 0, offset: 9_000, viewHeight: 0),
                      "before the view has a size the chat counts as at the newest, where it opens")
    }

    func testDistanceFromTheNewestMessage() {
        XCTAssertEqual(ChatScrollBox.distanceFromNewest(startInset: 116, offset: -116, viewHeight: 874), 0)
        XCTAssertEqual(ChatScrollBox.distanceFromNewest(startInset: 116, offset: -16, viewHeight: 874), 100)
        XCTAssertEqual(ChatScrollBox.distanceFromNewest(startInset: 116, offset: 5_000, viewHeight: 0), 0)
    }

    func testNearTheOldestLoadedMessage() {
        let end: CGFloat = 16_235 + 193 - 874   // the offset at the end of the content
        XCTAssertTrue(ChatScrollBox.nearOldest(contentHeight: 16_235, endInset: 193, offset: end, viewHeight: 874))
        XCTAssertTrue(ChatScrollBox.nearOldest(contentHeight: 16_235, endInset: 193, offset: end - 239, viewHeight: 874))
        XCTAssertFalse(ChatScrollBox.nearOldest(contentHeight: 16_235, endInset: 193, offset: end - 240, viewHeight: 874))
        XCTAssertFalse(ChatScrollBox.nearOldest(contentHeight: 16_235, endInset: 193, offset: -116, viewHeight: 874),
                       "at the newest message, nowhere near the oldest")
        XCTAssertFalse(ChatScrollBox.nearOldest(contentHeight: 26, endInset: 0, offset: 0, viewHeight: 0),
                       "the first layout passes run with no size; they must not load a page")
        XCTAssertFalse(ChatScrollBox.nearOldest(contentHeight: 300, endInset: 193, offset: -116, viewHeight: 874),
                       "content that does not fill the view has nothing to scroll to")
    }

    // MARK: - VoiceOver's reading order (issue #7)

    /// Higher is read first: the top row, then the messages oldest to newest, then what sits
    /// under the newest message going down the screen.
    func testTheReadingOrderIsTheDrawnOrderTopToBottom() {
        let count = 40
        let order = [ChatReadingOrder.top(messages: count)]
            + (0..<count).map { ChatReadingOrder.message(at: $0, of: count) }
            + [ChatReadingOrder.typing, ChatReadingOrder.confirm, ChatReadingOrder.failure]
        XCTAssertEqual(order, order.sorted(by: >), "strictly from first read to last")
        XCTAssertEqual(Set(order).count, order.count, "no two rows share a place")
        XCTAssertEqual(ChatReadingOrder.message(at: count - 1, of: count), 1, "the newest message is above zero")
    }
}
