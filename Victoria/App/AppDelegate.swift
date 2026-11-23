import UIKit
import UserNotifications

/// Bridges the bits of UIKit we still need under SwiftUI: registering for remote
/// notifications (so CloudKit can push a buddy's nudge to this device) and showing
/// notifications while the app is foregrounded.
///
/// CloudKit owns the actual push — we never manage a device token or run our own
/// server. We just (1) register for remote notifications (requires the
/// `aps-environment` entitlement) and (2) let the buddy's CloudKit subscription
/// (see `CloudKitSyncService.ensureNudgeSubscription`) deliver an alert. Everything
/// here soft-fails (e.g. on the Simulator, or before the dev account is wired) so it
/// can never crash or block launch.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Safe to call early; CloudKit pushes only arrive once the user has granted
        // notification permission (NotificationService asks) + iCloud is available.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit manages its own push routing — nothing to send to our own backend.
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Soft-fail: push just won't arrive (Simulator / no entitlement yet). Not fatal.
    }

    /// Show a buddy nudge as a banner even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// CloudKit pushes land here: a nudge alert OR a SILENT snapshot-changed wake-up
    /// (`ensureSnapshotSubscription`). Either way it means "buddy data moved": whoever is
    /// showing it refreshes (`BuddyRemoteChangeCenter`).
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        _ = await BuddyRemoteChangeCenter.shared.deliver()
        return .newData
    }
}
