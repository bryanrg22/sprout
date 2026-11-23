import XCTest
import UserNotifications
@testable import Victoria

/// A notification centre that records what the reminders ask of it. The system one shows a
/// permission prompt, which no test can answer.
final class FakeReminderCenter: ReminderCenter, @unchecked Sendable {
    var grant = true
    private(set) var authorizationRequests = 0
    private(set) var pending: [UNNotificationRequest] = []
    private(set) var clearedPending = 0
    private(set) var clearedDelivered = 0
    private(set) var badges: [Int] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return grant
    }
    func removeAllPending() { clearedPending += 1; pending = [] }
    func removeAllDelivered() { clearedDelivered += 1 }
    func add(_ request: UNNotificationRequest) { pending.append(request) }
    func setBadgeCount(_ count: Int) { badges.append(count) }

    var pendingIDs: Set<String> { Set(pending.map(\.identifier)) }
}

/// When the permission prompt and the first schedule happen (L-B12): as soon as there is
/// an onboarded profile, whether it was there at launch, appeared when onboarding finished,
/// or arrived from iCloud afterwards.
@MainActor
final class ReminderBootstrapTests: XCTestCase {

    private func onboarded() -> UserProfile {
        let profile = UserProfile()
        profile.onboardingComplete = true
        return profile
    }

    private let defaultReminders: Set<String> = [
        "victoria.reminder.weighIn",
        "victoria.reminder.meal.breakfast", "victoria.reminder.meal.lunch", "victoria.reminder.meal.dinner",
    ]

    func testFinishingOnboardingSchedulesInTheSameLaunch() async {
        let bootstrap = ReminderBootstrap()
        let center = FakeReminderCenter()

        // Launch on a fresh install: no profile yet.
        await bootstrap.profileChanged(nil, center: center)
        XCTAssertEqual(center.authorizationRequests, 0, "no prompt before there is anyone to remind")
        XCTAssertTrue(center.pending.isEmpty)

        // Onboarding in progress: a profile may exist, not complete.
        await bootstrap.profileChanged(UserProfile(), center: center)
        XCTAssertEqual(center.authorizationRequests, 0)

        // Onboarding finishes. No relaunch.
        await bootstrap.profileChanged(onboarded(), center: center)

        XCTAssertEqual(center.authorizationRequests, 1, "the permission prompt appears now, not at the next launch")
        XCTAssertEqual(center.pendingIDs, defaultReminders,
                       "weigh-in and meal reminders are on by default and must be scheduled")
    }

    func testAProfileThatArrivesFromICloudAfterLaunchIsScheduled() async {
        let bootstrap = ReminderBootstrap()
        let center = FakeReminderCenter()
        await bootstrap.profileChanged(nil, center: center)

        await bootstrap.profileChanged(onboarded(), center: center)

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(center.pendingIDs, defaultReminders)
    }

    func testAnOnboardedProfileAtLaunchIsScheduledOnce() async {
        let bootstrap = ReminderBootstrap()
        let center = FakeReminderCenter()
        let profile = onboarded()

        await bootstrap.profileChanged(profile, center: center)
        // The root view is rebuilt (a theme change) and reports the same profile again.
        await bootstrap.profileChanged(profile, center: center)
        await bootstrap.profileChanged(profile, center: center)

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(center.clearedPending, 1, "one schedule, not one per rebuild")
        XCTAssertEqual(center.pendingIDs, defaultReminders)
    }

    func testPermissionDeniedSchedulesNothing() async {
        let bootstrap = ReminderBootstrap()
        let center = FakeReminderCenter()
        center.grant = false

        await bootstrap.profileChanged(onboarded(), center: center)

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.clearedDelivered, 1)
    }

    func testAProfileThatGoesAwayAndComesBackIsScheduledAgain() async {
        let bootstrap = ReminderBootstrap()
        let center = FakeReminderCenter()
        await bootstrap.profileChanged(onboarded(), center: center)

        await bootstrap.profileChanged(nil, center: center)          // all data deleted
        await bootstrap.profileChanged(onboarded(), center: center)  // onboarded again

        XCTAssertEqual(center.authorizationRequests, 2)
        XCTAssertEqual(center.pendingIDs, defaultReminders)
    }

    func testTheScheduleFollowsTheProfile() {
        let center = FakeReminderCenter()
        let profile = onboarded()
        profile.mealRemindersEnabled = false
        profile.weighInReminderEnabled = true
        profile.weighInHour = 6
        profile.gymReminderEnabled = true
        profile.gymWeekdays = [2, 4, 9]          // 9 is not a weekday
        profile.gymHour = 30                     // out of range: clamped

        NotificationService.rescheduleAll(for: profile, center: center)

        XCTAssertEqual(center.pendingIDs,
                       ["victoria.reminder.weighIn", "victoria.reminder.gym.2", "victoria.reminder.gym.4"])
        let weighIn = center.pending.first { $0.identifier == "victoria.reminder.weighIn" }
        let trigger = weighIn?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 6)
        XCTAssertEqual(trigger?.repeats, true)
        let gym = center.pending.first { $0.identifier == "victoria.reminder.gym.2" }
        XCTAssertEqual((gym?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 23)
        XCTAssertEqual((gym?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday, 2)
    }
}
