import Foundation

/// Entry point for getting the app's `BuddySyncService`. Centralizing the choice here
/// means the rest of the app never names a concrete backend.
///
/// - **A device** → `CloudKitSyncService` (the CloudKit public database).
/// - **The Simulator** → `LocalMockSyncService`: it cannot sign in to iCloud, so it gets a
///   simulated buddy and an in-memory pairing store. Debug or Release makes no difference.
enum BuddySync {

    /// Whether a service has been made in this launch (see `LocalMockSyncService.init`).
    @MainActor private static var madeOne = false

    /// `@MainActor` because the concrete services are main-actor-isolated (they touch
    /// SwiftData `@Model` objects); they must be constructed on the main actor.
    @MainActor
    static func makeDefault(myUserID: String) -> any BuddySyncService {
        #if targetEnvironment(simulator)
        let first = !madeOne
        madeOne = true
        return LocalMockSyncService(myUserID: myUserID, applyDemoLink: first)
        #else
        // Degrades to a `BuddySyncError` when the account or container is not ready, so
        // this never crashes or hangs.
        return CloudKitSyncService(myUserID: myUserID)
        #endif
    }
}
