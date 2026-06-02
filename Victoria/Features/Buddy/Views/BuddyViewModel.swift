import SwiftUI
import Observation

/// Drives every Buddy screen. Owns the `BuddySyncService` and translates its async,
/// throwing calls into simple, observable UI state — always degrading to *kind* inline
/// messages (never crashes, never scary alerts).
///
/// **Identity.** A stable per-install user id is persisted in `UserDefaults` under
/// `"buddyMyUserID"` (minted once) and handed to `BuddySync.makeDefault(myUserID:)`.
///
/// **Linked state.** The mock's `link(usingCode:)` only records a code; the buddy's
/// name + presence arrive via `fetchBuddySnapshot()`. So we treat "linked" as
/// "`fetchBuddySnapshot()` returned a snapshot" — and remember it across the session.
/// On first appear we probe the snapshot to recover linked state after a relaunch.
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

    // MARK: Dependencies

    let myUserID: String
    private let service: any BuddySyncService

    // MARK: Observable state

    /// Whether we're connected to a buddy. Seeded from a snapshot probe on appear and
    /// flipped on a successful `link` / `unlink`.
    private(set) var isLinked = false
    /// The buddy's latest low-stakes snapshot (name, streak, mood, presence). Never
    /// carries weight/calorie numbers — see `BuddySnapshot`.
    private(set) var buddySnapshot: BuddySnapshotPayload?
    /// Received nudges, most-recent first.
    private(set) var inbox: [Nudge] = []

    /// My pairing code to share. Generated lazily so it's stable for the screen's life.
    private(set) var myPairingCode: String = ""

    /// A kind, transient banner message (errors *and* small successes). Cleared by the UI.
    var banner: BuddyBanner?

    /// True while a link attempt is in flight (disables the button, shows progress).
    private(set) var isLinking = false

    /// Bumped to fire a celebratory `ConfettiBurst` when a nudge is sent.
    private(set) var sendConfetti = 0
    /// The kind most recently sent — lets the UI pop a tiny confirmation chip.
    private(set) var lastSentKind: NudgeKind?

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.myUserID = Self.resolveMyUserID(defaults: defaults)
        self.service = BuddySync.makeDefault(myUserID: myUserID)
        self.myPairingCode = service.generatePairingCode()
    }

    /// Test / preview seam: inject a specific service + id.
    init(service: any BuddySyncService, myUserID: String) {
        self.myUserID = myUserID
        self.service = service
        self.myPairingCode = service.generatePairingCode()
    }

    // MARK: - Derived UI values

    /// Combined state for the SHARED panda: thriving when BOTH of us logged today,
    /// gentler when one of us hasn't, sleepy when nobody has yet. Never punitive.
    /// - Parameter myLoggedToday: whether *I've* logged anything today (the caller reads
    ///   this from the dashboard's data; defaults to `true` so a missing read errs warm).
    func sharedState(myLoggedToday: Bool) -> SharedPandaPlaceholder.CombinedState {
        let buddyLogged = buddySnapshot?.loggedToday ?? false
        switch (myLoggedToday, buddyLogged) {
        case (true, true):   return .thriving
        case (false, false): return .sleepy
        default:             return .okay
        }
    }

    /// Count of unread nudges, for a small inbox badge.
    var unreadCount: Int { inbox.filter { !$0.isRead }.count }

    // MARK: - Actions (all swallow BuddySyncError into kind banners)

    /// Recover linked state + load data when a screen appears. Safe to call repeatedly.
    func refresh() async {
        if !isLinked { await announceMyCode() }   // owner side: publish my code so a buddy can claim it
        await loadSnapshot()
        await loadInbox()
    }

    /// Announce my pairing code so a buddy who types it can find + claim me (the
    /// code-generator side of the handshake). Idempotent; a no-op on the mock.
    func announceMyCode() async {
        guard !myPairingCode.isEmpty else { return }
        do { try await service.publishMyPairingCode(myPairingCode) }
        catch { handleSilently(error) }
    }

    /// Probe the buddy snapshot; a non-nil result means we're linked.
    func loadSnapshot() async {
        do {
            let snap = try await service.fetchBuddySnapshot()
            buddySnapshot = snap
            if snap != nil { isLinked = true }
        } catch {
            // A snapshot failure is a soft state — keep whatever we had, stay quiet here
            // (the home screen's empty state already covers "not connected").
            handleSilently(error)
        }
    }

    /// Connect using a buddy's code. Trims input, shows kind errors, celebrates success.
    func link(usingCode code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            banner = .init(text: "Pop in your buddy's code to connect 💛", tone: .info)
            return
        }
        isLinking = true
        defer { isLinking = false }
        do {
            try await service.link(usingCode: trimmed)
            isLinked = true
            banner = .init(text: "You're connected! 💚", tone: .success)
            // Publish a first snapshot so the loop is warmed up, then pull state.
            await publishMine(loggedToday: true, dayStreak: 0)
            await refresh()
        } catch let err as BuddySyncError {
            banner = .init(text: kindMessage(for: err), tone: .info)
        } catch {
            banner = .init(text: "That didn't go through — let's try again in a moment.", tone: .info)
        }
    }

    /// Send a one-tap nudge (uses the kind's friendly default copy). Fires confetti.
    func send(_ kind: NudgeKind) async {
        guard let buddyID = buddySnapshot?.ownerUserID else {
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
            banner = .init(text: kindMessage(for: err), tone: .info)
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
        guard let buddyID = buddySnapshot?.ownerUserID else {
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
            banner = .init(text: kindMessage(for: err), tone: .info)
        } catch {
            banner = .init(text: "Couldn't send that just now — try again in a bit.", tone: .info)
        }
    }

    /// Load received nudges (most-recent first).
    func loadInbox() async {
        do {
            inbox = try await service.fetchInbox()
        } catch let err as BuddySyncError {
            // `.notLinked` is expected before pairing — stay quiet, leave inbox empty.
            if err != .notLinked { banner = .init(text: kindMessage(for: err), tone: .info) }
            inbox = []
        } catch {
            inbox = []
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
        }
        do {
            try await service.markRead(id)
        } catch {
            handleSilently(error) // a read-receipt failure should never bother the user
        }
    }

    /// Mark every currently-unread nudge as read (called when the inbox is opened).
    func markAllRead() async {
        let unread = inbox.filter { !$0.isRead }.map(\.id)
        for id in unread { await markRead(id) }
    }

    /// Publish my own low-stakes snapshot so my buddy can feel my presence — and, for the
    /// FAIR face-off, my SAFE daily activity (steps / water / movement) alongside MY OWN
    /// goals. Mood still mirrors the local-companion tiers.
    ///
    /// **Full data (opt-in).** When the user has chosen to share everything with their
    /// buddy (`UserProfile.shareFullStatsWithBuddy`), the caller also passes the FULL daily
    /// picture — weight trend, calorie + protein progress, today's food names — via the
    /// `sharesFullData` + full-data parameters below, and we forward it on the snapshot.
    /// These all default to "not sharing / no data", so existing callers (e.g. the
    /// just-linked warm-up publish) keep compiling and simply omit the full data — and when
    /// `sharesFullData` is false those fields stay 0/"" and never leave the device with
    /// meaning. This is ADDITIVE; the activity-only contract is unchanged.
    /// - Parameters:
    ///   - stepsToday/stepGoal:  my step total + my own step goal (scored as % of mine).
    ///   - waterToday/waterGoal: my water (oz) + my own water goal (scored as % of mine).
    ///   - workedOutToday:       whether I got movement in today (a simple "showed up").
    ///   - sharesFullData:       did I opt in to sharing the full picture below?
    ///   - trendWeightLbs:       my smoothed weight trend (lbs).
    ///   - goalWeightLbs:        my goal weight (lbs).
    ///   - weeklyRateLbs:        my weekly rate of change (lbs), SIGNED (negative = losing).
    ///   - caloriesEaten/calorieTarget: today's calories eaten + my daily target.
    ///   - proteinEaten/proteinTarget:  today's protein (g) eaten + my daily target.
    ///   - todayFoods:           comma-joined names of what I logged today.
    func publishMine(loggedToday: Bool,
                     dayStreak: Int,
                     stepsToday: Int = 0,
                     stepGoal: Int = 0,
                     waterToday: Double = 0,
                     waterGoal: Double = 0,
                     workedOutToday: Bool = false,
                     sharesFullData: Bool = false,
                     trendWeightLbs: Double = 0,
                     goalWeightLbs: Double = 0,
                     weeklyRateLbs: Double = 0,
                     caloriesEaten: Double = 0,
                     calorieTarget: Double = 0,
                     proteinEaten: Double = 0,
                     proteinTarget: Double = 0,
                     todayFoods: String = "") async {
        let mood: BuddyCharacterMood = dayStreak >= 7 ? .thriving : (loggedToday ? .happy : .sleepy)
        let payload = BuddySnapshotPayload(
            ownerUserID: myUserID,
            displayName: "You",
            dayStreak: max(dayStreak, 0),
            characterMood: mood,
            loggedToday: loggedToday,
            lastActive: .now,
            stepsToday: max(stepsToday, 0),
            stepGoal: max(stepGoal, 0),
            waterToday: max(waterToday, 0),
            waterGoal: max(waterGoal, 0),
            workedOutToday: workedOutToday,
            sharesFullData: sharesFullData,
            trendWeightLbs: max(trendWeightLbs, 0),
            goalWeightLbs: max(goalWeightLbs, 0),
            weeklyRateLbs: weeklyRateLbs,                 // SIGNED — do not clamp
            caloriesEaten: max(caloriesEaten, 0),
            calorieTarget: max(calorieTarget, 0),
            proteinEaten: max(proteinEaten, 0),
            proteinTarget: max(proteinTarget, 0),
            todayFoods: todayFoods
        )
        do {
            try await service.publish(mySnapshot: payload)
        } catch {
            handleSilently(error)
        }
    }

    // MARK: - Error → kind copy

    /// Map a sync error to warm, non-shaming language. (The errors already have decent
    /// `errorDescription`s; we lean on those but keep `.notLinked` extra-gentle.)
    private func kindMessage(for error: BuddySyncError) -> String {
        switch error {
        case .notLinked:
            return "Pair with a buddy first, then you two can cheer each other on 💛"
        case .invalidPairingCode:
            return "Hmm, that code didn't match. Double-check it and try again 💛"
        case .cloudKitUnavailable:
            return "Buddy sync will catch up once you're back online — nothing lost 💛"
        case .backendFailure:
            return "That didn't go through just now. Let's try again in a moment 💛"
        }
    }

    /// For failures the user shouldn't be bothered by (read-receipts, background probes).
    private func handleSilently(_ error: Error) { _ = error }
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
