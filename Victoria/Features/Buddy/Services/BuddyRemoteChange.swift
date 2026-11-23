import Foundation

/// Where a CloudKit push meets whoever shows buddy data. `AppDelegate` calls `deliver`
/// when a remote notification arrives; a `BuddyViewModel` registers a refresh.
@MainActor
final class BuddyRemoteChangeCenter {
    static let shared = BuddyRemoteChangeCenter()

    /// What a delivery came to.
    enum Outcome: Equatable {
        /// Every registered refresh ran to its end.
        case refreshed
        /// Nothing is showing buddy data, so there was nothing to refresh.
        case noObservers
        /// The refreshes were still running when the time allowed ran out.
        case timedOut
    }

    /// A refresh. Returns `false` when its owner is gone, which unregisters it.
    typealias Handler = @MainActor () async -> Bool

    private var handlers: [UUID: Handler] = [:]

    init() {}

    @discardableResult
    func addObserver(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        handlers[id] = nil
    }

    var observerCount: Int { handlers.count }

    /// The time a delivery may take: iOS gives a background push about 30 seconds.
    nonisolated static let defaultTimeout: @Sendable () async -> Void = {
        try? await Task.sleep(for: .seconds(20))
    }

    /// Tell every observer the buddy's data may have changed.
    func deliver(timeout: @escaping @Sendable () async -> Void = BuddyRemoteChangeCenter.defaultTimeout) async -> Outcome {
        for (id, handler) in handlers {
            Task { @MainActor in
                if await handler() == false { self.handlers[id] = nil }
            }
        }
        return .refreshed
    }
}
