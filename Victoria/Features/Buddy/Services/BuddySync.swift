import Foundation

/// Entry point for getting the app's `BuddySyncService`. Centralizing the choice here
/// means the rest of the app never names a concrete backend.
///
/// - **DEBUG** → `LocalMockSyncService`: the buddy UX is fully exercisable today with a
///   simulated, friendly buddy and no backend.
/// - **RELEASE** → still the mock for now, because CloudKit isn't wired up yet (no paid
///   account / entitlement / container — see `CloudKitSyncService` header). Flipping to
///   real sync later is a one-line change here once those steps are done.
enum BuddySync {

    /// The default service for the app. Swap the RELEASE branch to `CloudKitSyncService`
    /// once CloudKit is provisioned.
    ///
    /// `@MainActor` because the concrete services are main-actor-isolated (they touch
    /// SwiftData `@Model` objects); they must be constructed on the main actor.
    @MainActor
    static func makeDefault(myUserID: String) -> any BuddySyncService {
        // The Simulator can't sign in to iCloud, so it always uses the fully-working
        // local mock — the buddy UX stays demoable with no backend. REAL DEVICES use
        // CloudKit for true cross-device sync between Bryan & Victoria. CloudKitSync
        // self-degrades to a clear error if the account/container isn't ready yet, so
        // this never crashes or hangs.
        #if targetEnvironment(simulator)
        _ = myUserID
        return LocalMockSyncService()
        #else
        return CloudKitSyncService(myUserID: myUserID)
        #endif
    }
}
