import SwiftUI
import SwiftData
import CloudKit
import CoreData

/// What the app shows at launch, decided in one place so a person who already has data is
/// never sent through onboarding again (EVAL_REPORT 27).
///
/// Three ways that used to happen, and what this does about each:
/// 1. **An update that cannot open the store.** The app fell back to an empty in-memory
///    store, which has no profile, so it showed onboarding; anything entered there was gone
///    at the next launch. Now the launch shows `StoreUnavailableView`: the data is still on
///    the phone, untouched, and the screen says so and says not to delete the app.
/// 2. **A reinstall.** The profile comes back from iCloud a few seconds after launch, if it
///    comes back at all. Onboarding showed at once and could be finished before it arrived.
///    Now a launch with no profile waits for iCloud first (`ICloudRestoreWatch`), and
///    onboarding is shown only when iCloud has had its chance.
/// 3. **Two profiles** (one restored from iCloud, one made by onboarding before it
///    arrived). Views took `profiles.first`, which is in no particular order. Now every view
///    takes `UserProfile.primary(of:)`: the oldest finished profile.
///
/// An update installed over the old app keeps everything and needs none of this: build 15
/// to build 16 was measured to keep every value of every table (EVAL_REPORT 27).
enum LaunchRoute: Equatable {
    /// The store did not open. Never onboarding, never an empty app.
    case storeUnavailable
    /// No profile yet, and iCloud may still bring one back.
    case restoringFromICloud
    case onboarding
    case main

    /// `storeOpened`: the on-disk store opened (a `--ui-testing` launch counts as opened).
    /// `hasFinishedProfile` / `hasAnyProfile`: what the store holds right now.
    /// `restoreSettled`: iCloud has had its chance (or is not in play), see `ICloudRestoreWatch`.
    static func decide(storeOpened: Bool, hasFinishedProfile: Bool, hasAnyProfile: Bool,
                       restoreSettled: Bool) -> LaunchRoute {
        guard storeOpened else { return .storeUnavailable }
        if hasFinishedProfile { return .main }
        // A profile that exists but is not finished is an onboarding in progress on this
        // phone: carry on with it rather than waiting again.
        if hasAnyProfile { return .onboarding }
        return restoreSettled ? .onboarding : .restoringFromICloud
    }
}

extension UserProfile {
    /// The profile the app runs on when the store holds more than one: a finished one before
    /// an unfinished one, then the oldest. The oldest is the one that came first on this
    /// phone or in iCloud, so a profile restored from iCloud wins over one made by an
    /// onboarding that ran before it arrived. Ties (the same creation date) are broken by
    /// name, then start weight, so the choice never depends on fetch order.
    static func primary(of profiles: [UserProfile]) -> UserProfile? {
        profiles.min { a, b in
            if a.onboardingComplete != b.onboardingComplete { return a.onboardingComplete }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            if a.name != b.name { return a.name < b.name }
            return a.startWeightLbs < b.startWeightLbs
        }
    }
}

/// Whether the on-disk store opened at launch. Set once, by `VictoriaApp.init`, before any
/// view exists.
enum StoreStatus {
    private(set) static var openError: String?
    static var opened: Bool { openError == nil }

    static func recordOpenFailure(_ error: Error) { openError = String(describing: error) }

    #if DEBUG
    /// Tests only: put the status back.
    static func resetForTesting() { openError = nil }
    #endif
}

/// Waits, once, for iCloud to bring back a profile on a launch that has none.
///
/// There is no API that says "the first import is complete" (Apple's developer forums,
/// threads 776219 and 763876); an import event says one operation ended. So this settles
/// on the first of: iCloud is not available on this phone, an import operation ends, a
/// profile appears (the view stops asking), or `timeout` passes. The person can also
/// choose to start fresh at any point after `skipAfter`.
@MainActor @Observable
final class ICloudRestoreWatch {
    enum Reason: String, Equatable {
        case noAccount, importEnded, timedOut, personChoseToStart, notApplicable
    }

    static let defaultTimeout: Duration = .seconds(20)
    static let defaultSkipAfter: Duration = .seconds(4)
    private let timeout: Duration
    private let skipAfter: Duration

    private(set) var settled = false
    private(set) var reason: Reason?
    private(set) var canSkip = false
    private var started = false
    private var observer: NSObjectProtocol?

    /// Not applicable: settled from the start (a `--ui-testing` launch, a store that is not
    /// synced, a launch that already has a profile).
    init(applicable: Bool, timeout: Duration = ICloudRestoreWatch.defaultTimeout,
         skipAfter: Duration = ICloudRestoreWatch.defaultSkipAfter) {
        self.timeout = timeout
        self.skipAfter = skipAfter
        if !applicable { settle(.notApplicable) }
    }

    func settle(_ why: Reason) {
        guard !settled else { return }
        settled = true
        reason = why
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        Diagnostics.shared.log("launch: iCloud restore wait ended (\(why.rawValue))", .app)
    }

    /// Start waiting. Safe to call more than once; only the first call does anything.
    func start(accountStatus: @escaping @Sendable () async -> CKAccountStatus? = ICloudRestoreWatch.liveAccountStatus) {
        guard !settled, !started else { return }
        started = true
        Diagnostics.shared.log("launch: no profile yet; waiting for iCloud", .app)
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated { self?.settle(.importEnded) }
        }
        Task { [weak self] in
            let status = await accountStatus()
            if status != .available { self?.settle(.noAccount) }
        }
        Task { [weak self] in
            guard let wait = self?.skipAfter else { return }
            try? await Task.sleep(for: wait)
            self?.canSkip = true
        }
        Task { [weak self] in
            guard let wait = self?.timeout else { return }
            try? await Task.sleep(for: wait)
            self?.settle(.timedOut)
        }
    }

    nonisolated static func liveAccountStatus() async -> CKAccountStatus? {
        try? await CKContainer(identifier: CloudKitSyncService.containerIdentifier).accountStatus()
    }
}

/// Shown while a launch with no profile gives iCloud its chance to bring one back.
struct RestoringFromICloudView: View {
    let watch: ICloudRestoreWatch

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            VStack(spacing: Theme.Space.sm) {
                Text("Looking for your data in iCloud")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("If you've used Sprout before, your profile comes back in a moment.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            if watch.canSkip {
                Button("I'm new here — set me up") { watch.settle(.personChoseToStart) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier(AccessibilityID.Launch.startFresh)
                    .transition(.opacity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeInOut, value: watch.canSkip)
        .accessibilityIdentifier(AccessibilityID.Launch.restoring)
    }
}

/// Shown instead of onboarding when the store did not open. Nothing is written anywhere
/// while it is showing, so the next build can open the same file.
struct StoreUnavailableView: View {
    let detail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.brand)
                Text("Sprout couldn't open your data")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your data is still on this phone and nothing has been deleted. This version of the app couldn't read it, so it hasn't shown you anything rather than start you over.")
                    .foregroundStyle(Theme.textPrimary)
                Text("Please don't delete the app. Send the report below to whoever gave you Sprout; an update will open it.")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                ShareLink(item: report) {
                    Label("Send the report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier(AccessibilityID.Launch.sendReport)
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .accessibilityIdentifier(AccessibilityID.Launch.storeUnavailable)
    }

    private var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Sprout \(version) (\(build)) could not open its store.\n\n\(detail)\n\n" + Diagnostics.shared.dump()
    }
}
