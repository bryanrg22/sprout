import SwiftUI
import Observation

/// Drives every Buddy screen. Owns the `BuddySyncService` and turns its async, throwing
/// calls into observable state and plain sentences (never a crash, never an alert).
///
/// **Identity.** A per-install user id is minted once into `UserDefaults` under
/// `"buddyMyUserID"`. It does not survive deleting the app: see `docs/buddy-identity.md`.
///
/// **Linked state.** `isLinked` mirrors the service's persisted link
/// (`service.linkedBuddyID`), which the service writes only once a pairing is real. It is
/// re-read at every trigger (`refreshLinkState`), because more than one model exists per
/// phone: the Buddy screen's and the always-on `BuddyAutoPublisher`'s.
@MainActor
@Observable
final class BuddyViewModel {

    // MARK: Persisted identity

    /// UserDefaults key for this install's stable buddy user id (spec-mandated name).
    static let myUserIDKey = "buddyMyUserID"

    /// Returns the persisted id, minting + storing a fresh UUID string the first time.
    static func resolveMyUserID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: myUserIDKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: myUserIDKey)
        return fresh
    }

    private static func pairingCodeKey(_ myUserID: String) -> String { "buddy.myPairingCode.\(myUserID)" }

    /// The user's pairing code: generated once and kept, so the record the owner announced
    /// is the one a buddy claims however many times the app is relaunched. It changes in
    /// two cases only: unpairing retires it, and a code found to belong to someone else is
    /// replaced (`rotateMyPairingCode`).
    static func resolveMyPairingCode(myUserID: String,
                                     service: any BuddySyncService,
                                     defaults: UserDefaults = .standard) -> String {
        let key = pairingCodeKey(myUserID)
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let fresh = service.generatePairingCode()
        defaults.set(fresh, forKey: key)
        return fresh
    }

    // MARK: Dependencies

    let myUserID: String
    private let service: any BuddySyncService
    /// Where this model keeps what must survive a relaunch (my code, last publish, which
    /// milestones were sent). Injected so a test never touches the app's own defaults.
    private let defaults: UserDefaults
    /// The clock. Injected: nothing below reads the wall clock directly.
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    /// Serialises publishes for this user across models, and holds their shared health.
    private let publishing: BuddyPublishCoordinator
    /// One line to the field Diagnostics log. A test replaces it to read what is written.
    var log: (String) -> Void = { Diagnostics.shared.log($0, .sync) }
    /// Sets the app-icon badge. A test replaces it to read what was set.
    var setBadge: (Int) -> Void = { SystemReminderCenter().setBadgeCount($0) }
    /// Keeps a failure that repeats on every poll from being written every time.
    private var logFilter = RepeatedLineFilter()

    // MARK: Observable state

    /// Whether this phone is paired. Mirrors the service's persisted link.
    private(set) var isLinked = false
    /// The buddy's latest published day. Its full-stats fields are blank unless the buddy
    /// opted in to sharing them.
    private(set) var buddySnapshot: BuddySnapshotPayload?
    /// Received nudges, most-recent first.
    private(set) var inbox: [Nudge] = []

    /// My pairing code to share.
    private(set) var myPairingCode: String = ""

    /// A kind, transient banner message (small successes, soft failures). Cleared by the UI.
    var banner: BuddyBanner?

    /// Why the last attempt to connect failed, in words for the pairing screen. Stays until
    /// the next attempt or until the code is edited (a banner is gone in three seconds;
    /// this has to be read and acted on).
    private(set) var linkError: String?

    /// True while a link attempt is in flight (disables the button, shows progress).
    private(set) var isLinking = false

    /// Consecutive failed link attempts — after 2, the pairing screen surfaces a "check the
    /// connection" diagnostic path instead of letting the user blame their typing forever.
    private(set) var linkFailureCount = 0

    /// True while an unpair is in flight.
    private(set) var isUnpairing = false

    /// Set while this device has no usable iCloud account: the sentence that says so and
    /// what to do. Shown where it matters (the pairing screen, the hub's footer) for as long
    /// as it is true, because nothing here works until the user signs in.
    private(set) var accountProblem: String?
    /// True while the backend cannot be reached, so "can't reach iCloud" is said once per
    /// outage instead of at every poll.
    private var unreachable = false

    /// Bumped to fire a celebratory `ConfettiBurst` when a nudge is sent.
    private(set) var sendConfetti = 0
    /// The kind most recently sent — lets the UI pop a tiny confirmation chip.
    private(set) var lastSentKind: NudgeKind?

    // MARK: Sync health (what makes silent failures visible)

    /// When MY snapshot last reached the backend, from any model on this phone.
    var lastPublishAt: Date? { publishing.lastPublishAt }
    /// True when the most recent publish attempt failed (cleared by the next success). The
    /// auto-publisher uses it to retry on foreground; the hub uses it to show a soft warning.
    var lastPublishFailed: Bool { publishing.lastPublishFailed }
    /// When the buddy's snapshot was last fetched successfully (even if unchanged) — lets the
    /// UI distinguish "their data is old" from "I can't reach CloudKit at all".
    private(set) var lastBuddyFetchAt: Date?

    private static func lastPublishKey(_ id: String) -> String { "buddy.lastPublishOK.\(id)" }

    // MARK: Init

    /// - Parameter observePushes: refresh when a CloudKit push arrives. The Buddy hub wants
    ///   this; the always-on `BuddyAutoPublisher` (which only publishes, never displays)
    ///   passes `false`.
    convenience init(defaults: UserDefaults = .standard, observePushes: Bool = true) {
        let myUserID = Self.resolveMyUserID(defaults: defaults)
        self.init(service: BuddySync.makeDefault(myUserID: myUserID),
                  myUserID: myUserID,
                  defaults: defaults,
                  observePushes: observePushes,
                  publishing: .shared)
        // Publish the pairing code EAGERLY, not lazily on the first refresh: otherwise a
        // buddy who types it seconds after seeing it finds nothing there yet.
        if !isLinked {
            Task { await self.announceMyCode() }
        }
    }

    /// The designated init, and the seam for tests and previews: a specific service and id,
    /// and for a test its own defaults, clock and publish coordinator.
    init(service: any BuddySyncService,
         myUserID: String,
         defaults: UserDefaults = .standard,
         observePushes: Bool = true,
         now: @escaping @MainActor () -> Date = { .now },
         calendar: Calendar = .current,
         publishing: BuddyPublishCoordinator? = nil) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.publishing = publishing ?? BuddyPublishCoordinator()
        self.myUserID = myUserID
        self.service = service
        self.myPairingCode = Self.resolveMyPairingCode(myUserID: myUserID, service: service, defaults: defaults)
        // Restore the paired state at launch from the service's persisted link, so the
        // pairing screen does not flash every time the app reopens.
        self.isLinked = (service.linkedBuddyID != nil)
        if self.publishing.lastPublishAt == nil {
            self.publishing.lastPublishAt = defaults.object(forKey: Self.lastPublishKey(myUserID)) as? Date
        }
        let observerID = UUID()
        self.pushObserver = observePushes ? observerID : nil
        if observePushes { observeRemotePushes(as: observerID) }
    }

    /// Refresh the buddy data when a CloudKit push says it may have changed (the snapshot
    /// subscription fires a silent wake-up the moment the buddy logs). The handler holds
    /// this model weakly and reports `false` once it is gone, which unregisters it.
    private func observeRemotePushes(as id: UUID) {
        BuddyRemoteChangeCenter.shared.addObserver(id: id) { [weak self] in
            guard let self else { return false }
            if self.refreshLinkState() { await self.refresh() }
            return true
        }
    }

    /// This model's registration with `BuddyRemoteChangeCenter`, or nil when it does not
    /// listen for pushes. A constant, so `deinit` (which is nonisolated) can read it.
    private let pushObserver: UUID?

    deinit {
        // SwiftUI makes and drops a model each time it re-creates the view that owns one;
        // without this every dropped model would leave its observer behind until the next push.
        if let pushObserver {
            Task { @MainActor in BuddyRemoteChangeCenter.shared.removeObserver(pushObserver) }
        }
    }

    /// Bring `isLinked` in line with the service's persisted link, and return it. Called at
    /// every trigger rather than trusted from init: the pairing (or unpairing) may have been
    /// done by another model on this phone since.
    @discardableResult
    func refreshLinkState() -> Bool {
        let linked = service.linkedBuddyID != nil
        if linked != isLinked {
            isLinked = linked
            if !linked { clearBuddyState() }
        }
        return linked
    }

    private func clearBuddyState() {
        buddySnapshot = nil
        inbox = []
        lastBuddyFetchAt = nil
    }

    // MARK: - Derived UI values

    /// Combined state for the SHARED panda: thriving when BOTH of us logged today,
    /// gentler when one of us hasn't, sleepy when nobody has yet. Never punitive.
    /// - Parameter myLoggedToday: whether *I've* logged anything today (the caller reads
    ///   this from the dashboard's data; defaults to `true` so a missing read errs warm).
    func sharedState(myLoggedToday: Bool) -> SharedPandaPlaceholder.CombinedState {
        // Freshness-gated: a buddy snapshot synced yesterday must not feed the panda as if they
        // logged "today" (otherwise it shows "both thriving" off last night's stale snapshot).
        let buddyLogged = buddySnapshot?.loggedTodayEffective ?? false
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let lastFedKey = "buddy.panda.lastFed.\(myUserID)"
        let defaults = UserDefaults.standard

        // Fed today (either of us logged) → record it and show the happy tiers.
        if myLoggedToday || buddyLogged {
            defaults.set(today, forKey: lastFedKey)
            return (myLoggedToday && buddyLogged) ? .thriving : .okay
        }

        // Nobody's logged yet today — how long since the last feed decides the stakes.
        guard let lastFed = (defaults.object(forKey: lastFedKey) as? Date).map({ cal.startOfDay(for: $0) }) else {
            return .sleepy   // no record yet → just waiting, never START fainted
        }
        // `gap` counts whole days since the last feed; today isn't over so it doesn't count yet.
        let gap = cal.dateComponents([.day], from: lastFed, to: today).day ?? 0
        switch max(0, gap - 1) {       // full missed days
        case 0:     return .sleepy     // fed yesterday — just waiting on today
        case 1...2: return .hungry     // a couple quiet days — drooping
        default:    return .fainted    // 3+ neglected days — keeled over (any log revives it)
        }
    }

    /// How old the buddy's last published day is, by this model's clock.
    var buddyFreshness: BuddyFreshness {
        BuddyFreshness.evaluate(lastPublished: buddySnapshot?.lastActive, now: now(), calendar: calendar)
    }

    /// The buddy's first name, or "your buddy" before they have published one.
    var buddyFirstName: String {
        let name = buddySnapshot?.displayName ?? ""
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        return (first.isEmpty || name == "Your buddy") ? "your buddy" : first
    }

    /// The same, to begin a sentence with: "Sam" or "Your buddy".
    var buddyFirstNameCapitalized: String {
        let name = buddyFirstName
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Count of unread nudges, for a small inbox badge.
    var unreadCount: Int { inbox.filter { !$0.isRead }.count }

    // MARK: - Actions (every BuddySyncError becomes a sentence)

    /// Recover linked state + load data when a screen appears. Safe to call repeatedly.
    func refresh() async {
        let wasLinked = refreshLinkState()
        if !wasLinked { await announceMyCode() }   // owner side: put my code where a buddy can claim it
        await loadSnapshot()
        await loadInbox()
        // The owner's "it worked" moment: the service found a claimant on my code. The one
        // who typed got "You're connected!" at once; without this the owner's screen would
        // just change.
        if !wasLinked, refreshLinkState() {
            banner = .init(text: "They got your code — you're connected! 💚", tone: .success)
        }
    }

    /// Announce my pairing code so a buddy who types it can find + claim me (the
    /// code-generator side of the handshake). Idempotent.
    func announceMyCode() async {
        guard !myPairingCode.isEmpty else { return }
        do {
            try await service.publishMyPairingCode(myPairingCode)
            noteReached()
        } catch BuddySyncError.pairingCodeTaken {
            // The record under my code is someone else's. Take a new code and announce that.
            logQuietly(BuddySyncError.pairingCodeTaken, "announce code")
            rotateMyPairingCode()
            do { try await service.publishMyPairingCode(myPairingCode) }
            catch { logQuietly(error, "announce code") }
        } catch {
            noteFailure(error)
            logQuietly(error, "announce code")
        }
    }

    /// A call reached the backend: whatever stood in the way is gone.
    private func noteReached() {
        accountProblem = nil
        unreachable = false
    }

    /// A background call failed. Says so once per outage; a missing iCloud account also
    /// stays on screen (`accountProblem`) until a call gets through.
    private func noteFailure(_ error: Error) {
        guard let error = error as? BuddySyncError else { return }
        switch error {
        case .iCloudAccountMissing:
            accountProblem = Self.message(for: .iCloudAccountMissing)
        case .cloudKitUnavailable, .backendFailure:
            if !unreachable {
                banner = .init(text: "Can't reach iCloud right now. What you see here may be out of date; it will catch up on its own.",
                               tone: .info)
            }
            unreachable = true
        default:
            break
        }
    }

    /// Replace my pairing code with a new one (the old one turned out to belong to
    /// someone else, or was retired by unpairing).
    private func rotateMyPairingCode() {
        var fresh = service.generatePairingCode()
        while fresh == myPairingCode { fresh = service.generatePairingCode() }
        myPairingCode = fresh
        defaults.set(fresh, forKey: Self.pairingCodeKey(myUserID))
    }

    /// Fetch the buddy's snapshot, and learn from the answer whether we are still paired.
    func loadSnapshot() async {
        do {
            let snap = try await service.fetchBuddySnapshot()
            buddySnapshot = snap
            lastBuddyFetchAt = now()
            noteReached()
            refreshLinkState()
        } catch BuddySyncError.unpairedByBuddy {
            // The pairing record shows the buddy ended it; the service has cleared the link.
            let name = buddyFirstNameCapitalized
            isLinked = false
            clearBuddyState()
            setBadge(0)
            banner = .init(text: "\(name) ended the pairing. You can pair again whenever you both like.",
                           tone: .info)
            log("buddy: the buddy ended the pairing")
        } catch BuddySyncError.notLinked {
            // No buddy: the expected state on the pairing screen, not a failure to record.
            refreshLinkState()
        } catch {
            // Keep whatever we had; the footer and the stale state say how old it is.
            noteFailure(error)
            logQuietly(error, "snapshot fetch")
        }
    }

    /// Connect using a buddy's code. Connected means the service saved the claim and
    /// persisted the link; every other outcome leaves the user unpaired, says why in
    /// `linkError`, and can be retried.
    func link(usingCode code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            banner = .init(text: "Pop in your buddy's code to connect 💛", tone: .info)
            return
        }
        isLinking = true
        linkError = nil
        defer { isLinking = false }
        do {
            try await service.link(usingCode: trimmed)
            guard refreshLinkState() else {
                // The service returned without a link: treat it as the failure it is.
                linkFailureCount += 1
                linkError = Self.message(for: .backendFailure("no link"))
                return
            }
            linkFailureCount = 0
            banner = .init(text: "You're connected! 💚", tone: .success)
            // The screen publishes my real day next (`PairingView.onLinked`); pull theirs.
            await refresh()
        } catch let err as BuddySyncError {
            linkFailureCount += 1
            linkError = Self.message(for: err)
        } catch {
            linkFailureCount += 1
            linkError = Self.message(for: .backendFailure("unexpected"))
        }
    }

    /// The pairing screen clears the last failure when the code is edited.
    func clearLinkError() {
        linkError = nil
    }

    /// End the pairing from this phone. The link is forgotten here whether or not the
    /// backend can be reached; when it can, the other side finds out at its next refresh.
    /// The code that was shared is retired and a new one announced, unless a different
    /// buddy has already typed it, in which case they are who I am paired with next.
    func unpair() async {
        guard refreshLinkState(), !isUnpairing else { return }
        isUnpairing = true
        defer { isUnpairing = false }
        let name = buddyFirstName
        do { try await service.unlink() }
        catch { logQuietly(error, "unlink") }
        log("buddy: unpaired from this phone")
        // The service retires my code unless someone else is already waiting on it.
        if defaults.string(forKey: Self.pairingCodeKey(myUserID)) != myPairingCode {
            rotateMyPairingCode()
        }
        isLinked = false
        clearBuddyState()
        setBadge(0)
        banner = .init(text: "You're no longer paired with \(name).", tone: .info)
        // Announce my code, and if someone was waiting on it, this is where we pair.
        await refresh()
    }

    #if DEBUG
    /// DEV-ONLY one-tap CloudKit schema seed (see `CloudKitSyncService.debugSeedSchema`).
    /// Returns a human-readable status for the Settings "Seed CloudKit Schema" button.
    /// No-ops with a clear message when the active backend isn't CloudKit (the Simulator
    /// routes to the local mock), so it only does real work on a signed-in physical device.
    func seedCloudKitSchemaForDev() async -> String {
        guard let ck = service as? CloudKitSyncService else {
            return "⚠️ Not on CloudKit here — the Simulator uses a local mock. Run this on a real iPhone."
        }
        do {
            try await ck.debugSeedSchema()
            return "✅ Seeded CloudKit Development.\nNext, in CloudKit Dashboard: add indexes on Nudge.toUserID (Queryable), Nudge.createdAt (Sortable), and BuddySnapshot.ownerUserID (Queryable — the snapshot push needs it), then Deploy Schema Changes to Production."
        } catch {
            return "⚠️ Couldn't reach CloudKit. Check you're signed into iCloud on this device, then tap again."
        }
    }
    #endif

    /// CloudKit diagnostic (see `CloudKitSyncService.diagnose`). Available in RELEASE — the
    /// hidden Diagnostics screen exposes it so a TestFlight device can report the EXACT error
    /// the live buddy flow hides behind "cloudKitUnavailable."
    func diagnoseCloudKit() async -> String {
        guard let ck = service as? CloudKitSyncService else {
            return "Simulator uses a local mock — run this on a real iPhone to test CloudKit."
        }
        return await ck.diagnose()
    }

    /// Who a nudge goes to: the buddy this phone is paired with. Known from the link, so a
    /// buddy who has not published anything yet can still be cheered.
    private var nudgeRecipient: String? {
        buddySnapshot?.ownerUserID ?? service.linkedBuddyID
    }

    /// Send a one-tap nudge (uses the kind's friendly default copy). Fires confetti.
    func send(_ kind: NudgeKind) async {
        guard let buddyID = nudgeRecipient else {
            // Not linked yet — nudge the user gently toward pairing instead of erroring.
            banner = .init(text: "Pair with a buddy first, then cheer them on 💛", tone: .info)
            return
        }
        let nudge = Nudge(fromUserID: myUserID, toUserID: buddyID, kind: kind)
        do {
            try await service.sendNudge(nudge)
            lastSentKind = kind
            sendConfetti &+= 1
            banner = .init(text: "Sent \(kind.label.lowercased()) 💛", tone: .success)
        } catch let err as BuddySyncError {
            banner = .init(text: Self.message(for: err), tone: .info)
        } catch {
            banner = .init(text: "Couldn't send that just now — try again in a bit.", tone: .info)
        }
    }

    /// Maximum length of a hand-written buddy note. Short by design — a warm tap on the
    /// shoulder, not a letter — and a guard so an over-long string can't reach the wire.
    static let maxCustomNoteLength = 120

    /// Send a hand-written note to the buddy, reusing the existing `Nudge` `text` field (no
    /// model/service change). The text is trimmed + clamped to `maxCustomNoteLength`; an
    /// empty note falls back to the chosen kind's warm default (mirrors `Nudge`'s own rule),
    /// so a send can never produce a blank message. Fires the same confetti + kind
    /// confirmation as the preset chips. `kind` stays a health-POSITIVE intent (default
    /// `.cheer`) so the note carries a warm icon/label in the buddy's inbox.
    func send(text: String, kind: NudgeKind = .cheer) async {
        guard let buddyID = nudgeRecipient else {
            banner = .init(text: "Pair with a buddy first, then cheer them on 💛", tone: .info)
            return
        }
        let trimmed = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxCustomNoteLength)
        )
        // `Nudge.init` already substitutes the kind's default copy when `text` is empty.
        let nudge = Nudge(fromUserID: myUserID, toUserID: buddyID, kind: kind, text: trimmed)
        do {
            try await service.sendNudge(nudge)
            lastSentKind = kind
            sendConfetti &+= 1
            banner = .init(text: "Your note's on its way 💛", tone: .success)
        } catch let err as BuddySyncError {
            banner = .init(text: Self.message(for: err), tone: .info)
        } catch {
            banner = .init(text: "Couldn't send that just now — try again in a bit.", tone: .info)
        }
    }

    /// Load received nudges (most-recent first), and set the app-icon badge to how many are
    /// unread. A fetch that fails leaves the inbox and the badge as they were.
    func loadInbox() async {
        // Notes are between me and my buddy: with no buddy there is no inbox to show, and
        // nothing that should put a number on the app icon.
        guard refreshLinkState() else {
            inbox = []
            return
        }
        do {
            inbox = try await service.fetchInbox()
            noteReached()
            setBadge(unreadCount)
        } catch BuddySyncError.notLinked {
            // Expected before pairing — stay quiet, leave the inbox empty.
            inbox = []
        } catch {
            // The notes already on screen are still the notes: keep them, and the badge.
            noteFailure(error)
            logQuietly(error, "inbox fetch")
        }
    }

    /// Mark one nudge read (optimistic: update locally, then persist).
    /// `Nudge` is a reference type (`@Model`), so we mutate it *and* reassign `inbox` to
    /// guarantee `@Observable` notices and the "new" dot clears.
    func markRead(_ id: UUID) async {
        if let i = inbox.firstIndex(where: { $0.id == id }), !inbox[i].isRead {
            inbox[i].isRead = true
            let snapshot = inbox
            inbox = snapshot
            setBadge(unreadCount)
        }
        do {
            try await service.markRead(id)
        } catch {
            logQuietly(error, "mark read") // a read-receipt failure should never bother the user
        }
    }

    /// Mark every currently-unread nudge as read (called when the inbox is opened).
    func markAllRead() async {
        let unread = inbox.filter { !$0.isRead }.map(\.id)
        for id in unread { await markRead(id) }
    }

    // MARK: - Publishing my day

    /// Publish my day, then cheer the buddy for any goal just crossed. The one entry point
    /// for both publishers (the hub and the always-on `BuddyAutoPublisher`).
    ///
    /// Does nothing while unpaired, and asks the service, not a flag set at init: the
    /// pairing may have been made by another model a moment ago. Runs through the shared
    /// coordinator, so two models never publish at once and a milestone is sent by one of them.
    func publishIfLinked(_ s: MyBuddyState) async {
        guard refreshLinkState() else { return }
        await publishing.submit { [self] in await self.publishAndCelebrate(s) }
    }

    /// A successful publish older than this is repeated when the app comes back to the front.
    static let republishAfter: TimeInterval = 6 * 3600

    /// Whether coming back to the app should publish again: paired, and either the last
    /// attempt failed (it used to be lost for good) or the last success is old enough that
    /// the buddy would be looking at an earlier me.
    func needsPublishOnForeground() -> Bool {
        guard refreshLinkState() else { return false }
        if lastPublishFailed { return true }
        guard let last = lastPublishAt else { return true }
        return now().timeIntervalSince(last) > Self.republishAfter
    }

    private func publishAndCelebrate(_ s: MyBuddyState) async {
        guard refreshLinkState() else { return }   // unpaired while this waited its turn
        await publish(makePayload(s))

        let input = BuddyMilestoneInput(
            caloriesEaten: s.caloriesEaten, calorieTarget: s.calorieTarget,
            proteinEaten: s.proteinEaten, proteinTarget: s.proteinTarget,
            steps: s.stepsToday, stepGoal: s.stepGoal,
            waterOz: s.waterToday, waterGoal: s.waterGoal,
            dayStreak: s.dayStreak)
        let day = now()
        let pending = BuddyMilestones.pending(input, myUserID: myUserID, day: day,
                                              calendar: calendar, defaults: defaults)
        for milestone in pending.sorted(by: { $0.rawValue < $1.rawValue }) {
            let text = milestone.message(name: s.displayName, dayStreak: s.dayStreak)
            // Marked sent only once it was: one that fails here is tried at the next publish.
            if await sendCelebration(milestone, text: text) {
                BuddyMilestones.markSent(milestone, input: input, myUserID: myUserID, day: day,
                                         calendar: calendar, defaults: defaults)
            }
        }
    }

    /// Send the cheer for one milestone. Silent on failure for the user (a missed cheer
    /// must never nag); the failure is in the log and the caller retries later.
    private func sendCelebration(_ milestone: BuddyMilestone, text: String) async -> Bool {
        guard let buddyID = nudgeRecipient else { return false }
        let nudge = Nudge(fromUserID: myUserID, toUserID: buddyID, kind: .flex, text: text)
        do {
            try await service.sendNudge(nudge)
            log("buddy: auto-celebrate \(milestone.rawValue)")
            return true
        } catch {
            logQuietly(error, "auto-celebrate \(milestone.rawValue)")
            return false
        }
    }

    /// My snapshot as it leaves the device. Built through `BuddySnapshotPayload.init`, which
    /// blanks every full-stats field unless I opted in to sharing them; the numbers are
    /// cleaned of anything non-finite first.
    func makePayload(_ s: MyBuddyState) -> BuddySnapshotPayload {
        let mood: BuddyCharacterMood = s.dayStreak >= 7 ? .thriving : (s.loggedToday ? .happy : .sleepy)
        return BuddySnapshotPayload(
            ownerUserID: myUserID,
            // The name my BUDDY sees for me — my real name, not the literal "You".
            displayName: s.displayName,
            dayStreak: max(s.dayStreak, 0),
            characterMood: mood,
            loggedToday: s.loggedToday,
            lastActive: now(),
            stepsToday: max(s.stepsToday, 0),
            stepGoal: max(s.stepGoal, 0),
            waterToday: Self.fin(s.waterToday),
            waterGoal: Self.fin(s.waterGoal),
            workedOutToday: s.workedOutToday,
            workoutSummary: s.workoutSummary,
            sharesFullData: s.sharesFullData,
            trendWeightLbs: Self.fin(s.trendWeightLbs),
            goalWeightLbs: Self.fin(s.goalWeightLbs),
            weeklyRateLbs: Self.finSigned(s.weeklyRateLbs),   // SIGNED — keep sign, strip ∞/NaN
            caloriesEaten: Self.fin(s.caloriesEaten),
            calorieTarget: Self.fin(s.calorieTarget),
            proteinEaten: Self.fin(s.proteinEaten),
            proteinTarget: Self.fin(s.proteinTarget),
            carbsEaten: Self.fin(s.carbsEaten),
            carbTarget: Self.fin(s.carbTarget),
            fatEaten: Self.fin(s.fatEaten),
            fatTarget: Self.fin(s.fatTarget),
            todayFoods: s.todayFoods,
            competitionWeeks: s.competitionWeeks
        )
    }

    private func publish(_ payload: BuddySnapshotPayload) async {
        do {
            try await service.publish(mySnapshot: payload)
            let at = now()
            publishing.lastPublishAt = at
            publishing.lastPublishFailed = false
            defaults.set(at, forKey: Self.lastPublishKey(myUserID))
            log("buddy: snapshot published OK")
        } catch {
            publishing.lastPublishFailed = true
            logQuietly(error, "snapshot publish")
        }
    }

    /// Strip any non-finite garbage (∞ / NaN — e.g. a stray sentinel) before it reaches a CloudKit
    /// record and shows up as "a million calories" on the buddy's screen. Non-negative.
    private static func fin(_ v: Double) -> Double { v.isFinite ? max(v, 0) : 0 }
    /// Finite but sign-preserving (weekly rate can be negative = losing).
    private static func finSigned(_ v: Double) -> Double { v.isFinite ? v : 0 }

    // MARK: - Error → words

    /// What the user reads for each failure. One sentence each, saying what happened and
    /// what to do; no two failures share one.
    static func message(for error: BuddySyncError) -> String {
        switch error {
        case .notLinked:
            return "Pair with a buddy first, then you two can cheer each other on 💛"
        case .malformedPairingCode:
            return "That doesn't look like a pairing code. A code is VITA- and four more characters, like VITA-7F3K; codes never use 0, O, 1, I or L."
        case .invalidPairingCode:
            return "Nobody has shared that code. Check the letters with your buddy. If they opened their pairing screen only a moment ago, their phone may still be uploading it: wait a few seconds and try again."
        case .ownPairingCode:
            return "That's your own code. Share it with your buddy, and type theirs here."
        case .pairingCodeAlreadyClaimed:
            return "That code is already paired with someone else. If your buddy was paired before, ask them to tap Unpair on their Buddy screen, then use the new code they see."
        case .pairingCodeTaken:
            return "That code is in use. Open this screen again for a new one."
        case .unpairedByBuddy:
            return "Your buddy ended the pairing. You can pair again whenever you both like."
        case .iCloudAccountMissing:
            return "Buddy needs iCloud. Sign in to iCloud in the Settings app (your name at the top), then come back and try again."
        case .cloudKitUnavailable:
            return "Couldn't reach iCloud just now. Nothing was changed; check your connection and try again."
        case .backendFailure:
            return "That didn't go through just now. Nothing was changed; try again in a moment."
        }
    }

    /// For failures the user shouldn't be bothered by (read-receipts, background probes).
    /// "Quiet" means no banner — NOT no trace: the failure is written to the field
    /// Diagnostics log, because invisible sync failures are exactly how a buddy's snapshot
    /// froze for a month with nobody able to say why. Two things are kept out of it: not
    /// being paired, which is a state and not a failure, and the same line again within
    /// five minutes, which is counted instead (`RepeatedLineFilter`).
    private func logQuietly(_ error: Error, _ op: String) {
        if (error as? BuddySyncError) == .notLinked { return }
        let line = "buddy: \(op) failed quietly — \(error.localizedDescription)"
        if let out = logFilter.admit(line, at: now()) { log(out) }
    }
}

/// A small, transient banner. Always kind — `tone` only changes the accent, never the
/// warmth of the copy.
struct BuddyBanner: Identifiable, Equatable {
    enum Tone { case success, info }
    let id = UUID()
    var text: String
    var tone: Tone

    var tint: Color {
        switch tone {
        case .success: return Theme.positive
        case .info:    return Theme.brand
        }
    }
    var systemImage: String {
        switch tone {
        case .success: return "checkmark.circle.fill"
        case .info:    return "sparkles"
        }
    }
}
