import Foundation
import Observation
import SwiftData

/// One message as the chat screen shows it: a plain value copied out of a `ChatMessage`.
///
/// The rows on screen never hold the stored object, so a message that is deleted (or
/// replaced by a retry) cannot be read after the store has let go of it, and a row does not
/// re-render because some other property of the store changed.
struct ChatRow: Identifiable, Equatable, ChatWindowItem {
    let id: UUID
    let isUser: Bool
    let content: String
    let imageData: Data?
    let createdAt: Date
    let isSystemSeed: Bool
    let decisionSummary: String?
    let decisionAccepted: Bool?

    /// A settled confirm card, not a message bubble.
    var isDecision: Bool { decisionSummary != nil }

    init(_ message: ChatMessage) {
        id = message.id
        isUser = message.isUser
        content = message.content
        imageData = message.imageData
        createdAt = message.createdAt
        isSystemSeed = message.isSystemSeed
        decisionSummary = message.decisionSummary
        decisionAccepted = message.decisionAccepted
    }

    init(id: UUID = UUID(), isUser: Bool, content: String, imageData: Data? = nil, createdAt: Date,
         isSystemSeed: Bool = false, decisionSummary: String? = nil, decisionAccepted: Bool? = nil) {
        self.id = id
        self.isUser = isUser
        self.content = content
        self.imageData = imageData
        self.createdAt = createdAt
        self.isSystemSeed = isSystemSeed
        self.decisionSummary = decisionSummary
        self.decisionAccepted = decisionAccepted
    }
}

/// The loaded part of the conversation, read from the store a page at a time.
///
/// The chat screen used to hold a `@Query` over every `ChatMessage`, so opening it fetched
/// the whole conversation and every new message re-fetched it. This fetches the newest page
/// with a limit, an earlier page when the reader reaches the top, and only what is newer
/// than the newest loaded row when a message arrives. The arithmetic is `ChatWindow`.
@MainActor
@Observable
final class ChatTranscript {

    private(set) var window = ChatWindow<ChatRow>()
    /// Bumped each time the view should move to the newest message.
    private(set) var scrollToLatestTick = 0
    @ObservationIgnored private var context: ModelContext?

    nonisolated init() {}

    convenience init(context: ModelContext, pageSize: Int = ChatWindow<ChatRow>.defaultPageSize) {
        self.init()
        window = ChatWindow(pageSize: pageSize)
        self.context = context
        loadLatest()
    }

    /// Gives the transcript its store and opens the conversation at the newest message.
    /// Calling it again with the same store re-reads what is loaded.
    func attach(context: ModelContext) {
        if self.context == nil {
            self.context = context
            loadLatest()
        } else {
            reload()
        }
    }

    var rows: [ChatRow] { window.items }

    /// How many messages the store holds in all (a count query, no rows). Diagnostics only.
    func storedCount() -> Int {
        guard let context else { return 0 }
        return (try? context.fetchCount(FetchDescriptor<ChatMessage>())) ?? 0
    }

    // MARK: - Loading

    /// Opens the conversation: the newest page only.
    func loadLatest() {
        let request = window.latestRequest
        window.load(newestFirst: fetch(request), for: request)
    }

    /// Re-reads everything that is loaded, e.g. when the app returns to the foreground.
    func reload() {
        let request = window.reloadRequest
        window.load(newestFirst: fetch(request), for: request)
    }

    /// Loads the page before the oldest loaded message and returns the id of the row that
    /// was the oldest until now (the one whose place on screen should not change). Does
    /// nothing, and returns nil, when there is no earlier page or a load is already running.
    @discardableResult
    func loadEarlier() -> UUID? {
        guard let request = window.beginLoadingEarlier() else { return nil }
        return window.finishLoadingEarlier(newestFirst: fetch(request))
    }

    /// The engine added one or more messages: fetch what is newer than the newest loaded
    /// row and append it.
    func appendNewer() {
        guard let context else { return }
        guard let newest = window.newestLoaded else {
            loadLatest()
            if !window.items.isEmpty { scrollToLatestTick += 1 }
            return
        }
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.createdAt >= newest },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let rows = ((try? context.fetch(descriptor)) ?? []).map(ChatRow.init)
        if window.append(oldestFirst: rows) { scrollToLatestTick += 1 }
    }

    /// The engine deleted these messages.
    func remove(ids: Set<UUID>) {
        window.remove(ids: ids)
    }

    func setAtBottom(_ atBottom: Bool) {
        guard window.isAtBottom != atBottom else { return }
        window.setAtBottom(atBottom)
    }

    /// The reader asked for the newest message.
    func jumpToLatest() {
        window.setAtBottom(true)
        scrollToLatestTick += 1
    }

    private func fetch(_ request: ChatWindow<ChatRow>.Request) -> [ChatRow] {
        guard let context else { return [] }
        var descriptor: FetchDescriptor<ChatMessage>
        if let before = request.before {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.createdAt <= before },
                                         sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        } else {
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        }
        descriptor.fetchLimit = request.limit
        return ((try? context.fetch(descriptor)) ?? []).map(ChatRow.init)
    }
}
