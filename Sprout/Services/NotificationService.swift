import Foundation
import UserNotifications

/// Schedules the gentle local reminders (weigh-in, meals, gym).
///
/// Design principles:
/// - **Kind, never guilt-inducing.** Copy invites, it doesn't scold. A missed
///   nudge is fine — these are optional taps on the shoulder, not deadlines.
/// - **Idempotent rescheduling.** `rescheduleAll(for:)` wipes every pending
///   request and rebuilds from the profile, so toggling a setting can never
///   leave a stale reminder behind. Identifiers are stable for clarity/debugging.
/// - **Local only.** Everything uses `UNCalendarNotificationTrigger` with
///   `repeats: true`; no server, no network, no background work.
enum NotificationService {

    // MARK: Stable identifiers
    /// Stable request identifiers. Reusing them means a reschedule cleanly
    /// replaces the previous request rather than stacking duplicates.
    private enum ID {
        static let weighIn   = "sprout.reminder.weighIn"
        static let breakfast = "sprout.reminder.meal.breakfast"
        static let lunch     = "sprout.reminder.meal.lunch"
        static let dinner    = "sprout.reminder.meal.dinner"
        /// The opt-in once-a-day warm check-in from Vita.
        static let checkIn   = "sprout.reminder.checkIn"
        /// Gym needs one request per weekday (a single calendar trigger can
        /// only match one weekday), so we suffix with the weekday number.
        static func gym(weekday: Int) -> String { "sprout.reminder.gym.\(weekday)" }
    }

    // MARK: Daily check-in opt-in (UserDefaults — UserProfile is intentionally untouched)

    /// Whether the gentle once-a-day check-in is enabled. **Opt-in:** defaults to
    /// `false`, so nothing extra is scheduled until the user turns it on. Persisted in
    /// `UserDefaults` (not on `UserProfile`) so this feature adds no model changes.
    ///
    /// Toggling this is enough on its own — `rescheduleAll` reads it and rebuilds, and
    /// it's already called on launch and after any reminder change.
    enum CheckIn {
        // Stored settings: these keys keep the name they shipped under, or the person's
        // check-in choice would reset. (Request ids above are not stored: every reschedule
        // removes all pending requests first, so they could be renamed.)
        private static let enabledKey = "victoria.checkIn.enabled"
        private static let hourKey    = "victoria.checkIn.hour"
        private static let defaultHour = 11   // late morning: a calm, non-mealtime moment

        /// Master opt-in flag. Read by `rescheduleAll`; write it from a Settings toggle.
        static var isEnabled: Bool {
            get { UserDefaults.standard.bool(forKey: enabledKey) }
            set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
        }

        /// Hour of day (0...23) for the check-in. Stored separately so it survives
        /// even while the feature is off.
        static var hour: Int {
            get {
                guard UserDefaults.standard.object(forKey: hourKey) != nil else { return defaultHour }
                return min(max(UserDefaults.standard.integer(forKey: hourKey), 0), 23)
            }
            set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: hourKey) }
        }
    }

    // MARK: Authorization

    /// Ask for permission to show alerts, play sounds, and set the badge.
    /// Safe to call repeatedly — iOS only prompts the first time; afterward it
    /// resolves immediately with the user's standing choice.
    /// - Returns: `true` if notifications are allowed (or already authorized).
    @discardableResult
    static func requestAuthorization() async -> Bool {
        // UI smoke flows: no system alert over the screen under test (reads as "not granted").
        guard !UITestHooks.isActive else { return false }
        #if DEBUG
        // A screenshot run cannot tap the system prompt away, and the prompt covers the screen.
        if CommandLine.arguments.contains("--demo-no-notification-prompt")
            || CommandLine.arguments.contains("--no-notification-prompt") { return false }
        #endif
        return await SystemReminderCenter().requestAuthorization()
    }

    /// The current authorization status, e.g. to decide whether to show an
    /// in-app hint nudging the user toward Settings.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: Scheduling

    /// Tear down every pending Sprout reminder and rebuild from the profile.
    ///
    /// Call this any time a reminder preference changes, and once on launch /
    /// after onboarding so the schedule reflects the latest settings. Because we
    /// `removeAllPendingNotificationRequests()` first, disabled categories
    /// simply aren't re-added — there's nothing to "turn off" separately.
    static func rescheduleAll(for profile: UserProfile, center: any ReminderCenter = SystemReminderCenter()) {
        center.removeAllPending()

        // Weigh-in — a calm morning trend check.
        if profile.weighInReminderEnabled {
            schedule(
                id: ID.weighIn,
                title: "Good morning 🌤️",
                body: "A quick weigh-in keeps your trend honest — remember, daily wobbles are totally normal.",
                hour: profile.weighInHour,
                on: center
            )
        }

        // Meals — light "want to log it?" nudges.
        if profile.mealRemindersEnabled {
            schedule(
                id: ID.breakfast,
                title: "Breakfast time 🍳",
                body: "Whenever you're ready — a quick log now makes the rest of the day easier.",
                hour: profile.breakfastHour,
                on: center
            )
            schedule(
                id: ID.lunch,
                title: "Lunchtime 🥗",
                body: "Want to log it while it's fresh? No stress if later works better.",
                hour: profile.lunchHour,
                on: center
            )
            schedule(
                id: ID.dinner,
                title: "Dinner 🍲",
                body: "Rounding out the day — log what feels right. Progress over perfection.",
                hour: profile.dinnerHour,
                on: center
            )
        }

        // Gym — encouraging, low-bar movement reminders on chosen weekdays.
        if profile.gymReminderEnabled {
            for weekday in Set(profile.gymWeekdays) where (1...7).contains(weekday) {
                schedule(
                    id: ID.gym(weekday: weekday),
                    title: "Gym day 💪",
                    body: "Even 20 minutes counts. You've got this.",
                    hour: profile.gymHour,
                    weekday: weekday,
                    on: center
                )
            }
        }

        // Daily check-in — a single, opt-in, warm "thinking of you" once a day.
        // Off by default; one request only (the calendar trigger fires once/day), so
        // it can never become naggy. Copy rotates by weekday for a little freshness.
        if CheckIn.isEnabled {
            schedule(
                id: ID.checkIn,
                title: "\(profile.coachName) 💛",
                body: checkInLine(for: profile),
                hour: CheckIn.hour,
                on: center
            )
        }
    }

    /// Remove every pending Sprout reminder (and clear any delivered ones).
    static func cancelAll(center: any ReminderCenter = SystemReminderCenter()) {
        center.removeAllPending()
        center.removeAllDelivered()
    }

    /// Ask for permission (a no-op prompt if already decided) and (re)build the schedule
    /// in one call. Honors the user's choice — if permission is denied, nothing is scheduled.
    /// Called by `ReminderBootstrap` the first time there is an onboarded profile.
    static func refreshOnLaunch(for profile: UserProfile, center: any ReminderCenter = SystemReminderCenter()) async {
        // UI smoke flows: leave this device's real reminder schedule alone.
        guard !UITestHooks.isActive else { return }
        #if DEBUG
        // A screenshot run cannot tap the system prompt away, and the prompt covers the screen.
        if CommandLine.arguments.contains("--demo-no-notification-prompt")
            || CommandLine.arguments.contains("--no-notification-prompt") { return }
        #endif
        let granted = await center.requestAuthorization()
        guard granted else {
            cancelAll(center: center)
            return
        }
        rescheduleAll(for: profile, center: center)
    }

    // MARK: Helpers

    /// A warm, evergreen line for the daily check-in, in the same caring,
    /// anti-restriction voice as `DailyInsightEngine`'s templates (it celebrates
    /// showing up, fuel, and hydration — never eating less). A repeating calendar
    /// trigger fixes its text at schedule time, so we rotate by weekday for a little
    /// variety across the week; `rescheduleAll` (called on launch) refreshes it.
    private static func checkInLine(for profile: UserProfile) -> String {
        // Mirrors the gentle, unconditional-kindness tone of the insight engine.
        let lines = [
            "How are you feeling today? A quick log keeps us learning your body together. 💛",
            "Checking in 🌤️ Even one small thing today counts — fuel, water, or a few steps.",
            "Thinking of you. Eating enough and staying hydrated is the whole game — you've got this. 💚",
            "A gentle hello 👋 Whenever you're ready, I'm here to cheer you on.",
            "Showing up beats being perfect. Proud of you for being here. ✨",
            "Stay fueled and hydrated today 💧 small things, big difference for how you feel.",
            "New day, no pressure. Let's keep it kind and steady together. 🌱",
        ]
        let weekday = Calendar.current.component(.weekday, from: .now)   // 1...7
        return lines[(weekday - 1) % lines.count]
    }

    /// Schedule one repeating calendar notification.
    /// - Parameters:
    ///   - hour: hour of day, 0...23. Minute is fixed to `:00`.
    ///   - weekday: optional 1=Sun…7=Sat. When `nil`, repeats daily; when set,
    ///     repeats weekly on that weekday.
    private static func schedule(
        id: String,
        title: String,
        body: String,
        hour: Int,
        weekday: Int? = nil,
        on center: any ReminderCenter
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = 0
        if let weekday { components.weekday = weekday }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }
}

// MARK: - The notification centre, as the reminders use it

/// What the app asks of the system notification centre. A protocol so the schedule can be
/// tested without the system prompt (`SystemReminderCenter` is the app's).
protocol ReminderCenter: Sendable {
    /// Ask to show alerts, play sounds and set the badge. iOS prompts only the first time.
    func requestAuthorization() async -> Bool
    func removeAllPending()
    func removeAllDelivered()
    func add(_ request: UNNotificationRequest)
    /// Set the number on the app icon; 0 removes it.
    func setBadgeCount(_ count: Int)
}

struct SystemReminderCenter: ReminderCenter {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func removeAllPending() { center.removeAllPendingNotificationRequests() }
    func removeAllDelivered() { center.removeAllDeliveredNotifications() }
    func add(_ request: UNNotificationRequest) { center.add(request) }
    func setBadgeCount(_ count: Int) { center.setBadgeCount(max(count, 0)) }
}

// MARK: - When the reminders are first scheduled

/// Decides when the permission prompt and the first schedule happen: the first time
/// there is an onboarded profile. That can be at launch, at the end of onboarding, or
/// when a profile arrives from iCloud after a reinstall; `RootView` reports the profile
/// whenever "there is an onboarded profile" changes, and this asks once per appearance.
///
/// It used to be decided once, in the root view's launch task: a profile that became
/// onboarded after that got no prompt and no reminders until the next cold launch.
@MainActor
final class ReminderBootstrap {
    static let shared = ReminderBootstrap()

    /// True once the reminders were scheduled for the profile now on screen.
    private var scheduled = false

    init() {}

    func profileChanged(_ profile: UserProfile?, center: any ReminderCenter = SystemReminderCenter()) async {
        guard let profile, profile.onboardingComplete else {
            scheduled = false   // nobody to remind (yet, or any more)
            return
        }
        guard !scheduled else { return }   // the root view was rebuilt; nothing changed
        scheduled = true
        #if DEBUG
        // DEBUG: `--no-reminder-prompt` keeps the system permission alert off the screen
        // for a screenshot run, where nothing can tap it away.
        if CommandLine.arguments.contains("--no-reminder-prompt") { return }
        #endif
        await NotificationService.refreshOnLaunch(for: profile, center: center)
    }
}
