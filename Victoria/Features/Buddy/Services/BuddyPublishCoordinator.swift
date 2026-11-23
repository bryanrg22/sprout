import Foundation
import Observation

/// One publish at a time for this user, whoever asks.
///
/// Two view models publish the same snapshot record: the Buddy screen's and the always-on
/// `BuddyAutoPublisher`'s. When the app goes to the background with the Buddy screen open,
/// both fire. A publish is a fetch-modify-save of one CloudKit record, so two at once end
/// with one of them refused for an out-of-date change tag, and sync reported as failing
/// when it is not. Every publish therefore goes through the one shared coordinator: while
/// one job runs, a newer one waits (only the newest is kept, since a snapshot is the whole
/// state) and runs after it.
///
/// It also holds the sync health both models report, so the Buddy screen's footer shows a
/// failure of the auto-publisher's publish and the next success clears it everywhere.
@MainActor
@Observable
final class BuddyPublishCoordinator {
    /// The app's. A test makes one per simulated phone.
    static let shared = BuddyPublishCoordinator()

    /// When my snapshot last reached the backend.
    var lastPublishAt: Date?
    /// True when the most recent publish attempt failed; cleared by the next success.
    var lastPublishFailed = false

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var waiting: (@MainActor () async -> Void)?

    init() {}

    /// Run `job` now, or after the one in flight. Returns when `job` has run, or at once
    /// when it was parked behind another (whose caller then runs it).
    func submit(_ job: @escaping @MainActor () async -> Void) async {
        guard !isRunning else {
            waiting = job   // newest wins
            return
        }
        isRunning = true
        var next: (@MainActor () async -> Void)? = job
        while let run = next {
            await run()
            next = waiting
            waiting = nil
        }
        isRunning = false
    }
}
