import Foundation
import CloudKit

/// Where a CloudKit push meets whoever shows buddy data. `AppDelegate` calls `deliver`
/// when a remote notification arrives and gives iOS the answer only once it returns; a
/// `BuddyViewModel` registers its refresh as an observer.
///
/// iOS ends the app's background time when the handler returns. The handler used to post
/// a notification and return at once, so the refresh it started was not guaranteed to run.
/// `deliver` returns when every refresh has finished, or when the time allowed runs out.
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

    /// - Parameter id: the caller's own, when it needs to know it before it can register.
    @discardableResult
    func addObserver(id: UUID = UUID(), _ handler: @escaping Handler) -> UUID {
        handlers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        handlers[id] = nil
    }

    var observerCount: Int { handlers.count }

    /// The time a delivery may take. iOS allows a background push about 30 seconds in all.
    nonisolated static let defaultTimeout: @Sendable () async -> Void = {
        try? await Task.sleep(for: .seconds(20))
    }

    /// Tell every observer the buddy's data may have changed, and wait for them.
    /// - Parameter timeout: returns when the time allowed is up. A test passes one it
    ///   controls; nothing here reads a clock.
    func deliver(timeout: @escaping @Sendable () async -> Void = BuddyRemoteChangeCenter.defaultTimeout) async -> Outcome {
        let current = handlers
        guard !current.isEmpty else { return .noObservers }

        // Whichever ends first, the refreshes or the timeout, answers; the other is left
        // to end on its own (a refresh that is stuck must not hold the answer back).
        let race = Race()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            race.work = Task { @MainActor in
                var alive = 0
                await withTaskGroup(of: (UUID, Bool).self) { group in
                    for (id, handler) in current {
                        group.addTask { @MainActor in (id, await handler()) }
                    }
                    for await (id, isAlive) in group {
                        if isAlive { alive += 1 } else { self.handlers[id] = nil }
                    }
                }
                guard !race.answered else { return }
                race.answered = true
                race.timer?.cancel()
                continuation.resume(returning: alive > 0 ? .refreshed : .noObservers)
            }
            race.timer = Task { @MainActor in
                await timeout()
                guard !race.answered else { return }
                race.answered = true
                race.work?.cancel()
                continuation.resume(returning: .timedOut)
            }
        }
    }

    /// The two halves of one delivery and which of them answered.
    private final class Race {
        var answered = false
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?
    }
}

/// What a remote notification is about, read from its payload.
enum BuddyPush: Equatable {
    /// A nudge addressed to me was created (`nudges-to-<me>-v2`).
    case nudge
    /// My buddy's snapshot changed (`buddy-snapshot-<me>-from-<buddy>`).
    case snapshot
    /// A database or zone change: the SwiftData private-database mirror's own push. It
    /// says nothing about the buddy.
    case privateMirror
    /// Could not be told. Treated as possibly about the buddy, so nothing that used to
    /// refresh stops refreshing.
    case unknown

    /// A query subscription is one of this app's two, named in
    /// `CloudKitSyncService.ensureNudgeSubscription` / `ensureSnapshotSubscription`.
    static func kind(querySubscriptionID id: String?) -> BuddyPush {
        guard let id else { return .unknown }
        if id.hasPrefix("nudges-to-") { return .nudge }
        if id.hasPrefix("buddy-snapshot-") { return .snapshot }
        return .unknown
    }

    /// Parses the payload with CloudKit's own parser. No network: this only reads the dictionary.
    static func kind(userInfo: [AnyHashable: Any]) -> BuddyPush {
        guard let dictionary = userInfo as? [String: NSObject],
              let notification = CKNotification(fromRemoteNotificationDictionary: dictionary) else { return .unknown }
        switch notification.notificationType {
        case .query:                 return kind(querySubscriptionID: notification.subscriptionID)
        case .database, .recordZone: return .privateMirror
        default:                     return .unknown
        }
    }

    /// Whether a refresh of buddy data is worth the background time.
    var concernsBuddy: Bool { self != .privateMirror }
}
