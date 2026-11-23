import Foundation

/// What the paging arithmetic needs to know about a message.
protocol ChatWindowItem {
    var id: UUID { get }
    var createdAt: Date { get }
    var isUser: Bool { get }
}

/// The part of a conversation that is loaded: the newest page, plus every earlier page the
/// user has scrolled up to. Pure arithmetic — no store, no view, no clock — so every rule
/// here is a unit test (`ChatWindowTests`).
///
/// The conversation is opened by asking the store for the newest `pageSize` messages (one
/// more is requested, only to learn whether anything older exists). Scrolling to the top
/// asks for the page before the oldest loaded message and prepends it. A message that
/// arrives is appended. Nothing is ever unloaded, so memory grows with how far back the
/// user has read in this session, not with how long the conversation is.
struct ChatWindow<Item: ChatWindowItem> {

    /// Messages per page. About four screens of short messages: enough that opening the
    /// chat never shows a gap, small enough that the open is the same speed at any length.
    static var defaultPageSize: Int { 40 }

    /// What to ask the store for: the newest `limit` messages created at or before `before`
    /// (nil = from the newest of all), newest first.
    struct Request: Equatable {
        var before: Date?
        var limit: Int
    }

    let pageSize: Int
    /// The loaded messages, oldest first.
    private(set) var items: [Item] = []
    /// Whether the store holds messages older than the oldest loaded one.
    private(set) var hasEarlier = false
    /// True between `beginLoadingEarlier` and `finishLoadingEarlier`.
    private(set) var isLoadingEarlier = false
    /// Whether the newest message is on screen. The view reports it.
    private(set) var isAtBottom = true
    /// Messages that arrived while the user was reading further up.
    private(set) var unseenCount = 0

    init(pageSize: Int = ChatWindow.defaultPageSize) {
        self.pageSize = max(1, pageSize)
    }

    // MARK: - Opening (and reloading)

    /// The request that opens the conversation at its newest message.
    var latestRequest: Request { Request(before: nil, limit: pageSize + 1) }

    /// The request that re-reads everything currently loaded (after the app returns to the
    /// foreground, when another device may have added messages), never fewer than one page.
    var reloadRequest: Request { Request(before: nil, limit: max(items.count, pageSize) + 1) }

    /// Replaces the window with the answer to `latestRequest` or `reloadRequest`. `rows` are
    /// newest first; one row more than the request's page means older messages exist.
    mutating func load(newestFirst rows: [Item], for request: Request) {
        let page = max(1, request.limit - 1)
        hasEarlier = rows.count > page
        items = Array(rows.prefix(page).reversed())
        isLoadingEarlier = false
        unseenCount = 0
    }

    // MARK: - Earlier pages

    /// Starts loading the page before the oldest loaded message. Nil when there is nothing
    /// older, when a load is already running, or when nothing is loaded yet.
    ///
    /// The request is "at or before the oldest loaded timestamp", not "before" it, so two
    /// messages stored with the same timestamp cannot hide one another across a page
    /// boundary; the limit is widened by the loaded messages that share that timestamp.
    mutating func beginLoadingEarlier() -> Request? {
        guard hasEarlier, !isLoadingEarlier, let oldest = items.first else { return nil }
        isLoadingEarlier = true
        let sharingTimestamp = items.prefix { $0.createdAt == oldest.createdAt }.count
        return Request(before: oldest.createdAt, limit: pageSize + sharingTimestamp + 1)
    }

    /// Prepends the answer to the request `beginLoadingEarlier` returned (`rows` newest
    /// first). Returns the id of the message that was the oldest before the page arrived:
    /// the row whose place on screen must not move.
    @discardableResult
    mutating func finishLoadingEarlier(newestFirst rows: [Item]) -> UUID? {
        guard isLoadingEarlier else { return nil }
        isLoadingEarlier = false
        let anchor = items.first?.id
        let loaded = Set(items.map(\.id))
        let fresh = rows.filter { !loaded.contains($0.id) }
        hasEarlier = fresh.count > pageSize
        items.insert(contentsOf: fresh.prefix(pageSize).reversed(), at: 0)
        return anchor
    }

    /// The load failed or was abandoned; the next scroll to the top may try again.
    mutating func cancelLoadingEarlier() {
        isLoadingEarlier = false
    }

    // MARK: - New messages

    /// The timestamp to ask the store for newer messages from ("created at or after"), nil
    /// when nothing is loaded and the conversation should simply be opened.
    var newestLoaded: Date? { items.last?.createdAt }

    /// Appends messages newer than the loaded ones (`rows` oldest first; rows already loaded
    /// are skipped). Returns whether the view should scroll to the newest message: yes when
    /// the user was already there, and yes when one of the new messages is the user's own
    /// (sending always shows what was sent). Otherwise the new messages are counted as
    /// unseen and the reader is left where they are.
    @discardableResult
    mutating func append(oldestFirst rows: [Item]) -> Bool {
        let loaded = Set(items.map(\.id))
        let fresh = rows.filter { !loaded.contains($0.id) }
        guard !fresh.isEmpty else { return false }
        items.append(contentsOf: fresh)
        if isAtBottom || fresh.contains(where: \.isUser) {
            unseenCount = 0
            return true
        }
        unseenCount += fresh.count
        return false
    }

    // MARK: - Deletion

    /// Drops messages that were deleted from the store. Whether older messages exist is
    /// unchanged: deleting a loaded row does not load or unload anything.
    mutating func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        unseenCount = min(unseenCount, items.count)
    }

    // MARK: - Where the reader is

    /// The view reports whether the newest message is on screen. Reaching it clears the
    /// unseen count.
    mutating func setAtBottom(_ atBottom: Bool) {
        isAtBottom = atBottom
        if atBottom { unseenCount = 0 }
    }

    /// Whether to offer "jump to latest": the reader is away from the newest message.
    var showsJumpToLatest: Bool { !isAtBottom && !items.isEmpty }

    /// A timestamp goes above the first loaded message and above any message more than
    /// five minutes after the one before it.
    func showsTimestamp(at index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        return items[index].createdAt.timeIntervalSince(items[index - 1].createdAt) > 5 * 60
    }
}
