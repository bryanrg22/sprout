import Foundation

/// A fully local implementation of `BuddySyncService` with a simulated buddy, "Sam", so
/// the buddy screens can be used in the Simulator, which cannot sign in to iCloud.
///
/// What is real and what is simulated:
/// - **Pairing is the real handshake** (`BuddyPairingEngine`) over an in-memory store that
///   holds two records: Sam's code `VITA-SAM2`, waiting to be typed, and `VITA-TAKN`,
///   already paired with someone else. Typing Sam's code connects; anything else fails
///   the way it would on a device, with the same message.
/// - **Sam's snapshot is made up**: a streak, activity around the goals, opted-in full
///   stats. The values drift a little between calls so it does not look frozen.
/// - **Nudges get a reply**: a few seconds after you send one, Sam "writes back".
///
/// **Isolation.** A `@MainActor final class`, like the CloudKit service: the `Nudge`
/// models that pass through are bound to the main-actor `ModelContext`.
///
/// **State.** The link and inbox are in `UserDefaults`; the pairing records and pending
/// replies are in memory and rebuilt at launch from the persisted link.
@MainActor
final class LocalMockSyncService: BuddySyncService {

    // MARK: Identity

    /// A stable id for "me" in the mock world, persisted so it's consistent across launches.
    private let myUserID: String

    /// The simulated buddy.
    nonisolated static let buddyUserID = "mock.buddy.sam"
    nonisolated static let buddyDisplayName = "Sam"
    /// The code the simulated buddy is showing. Typing it pairs.
    nonisolated static let buddyCode = "VITA-SAM2"
    /// A code someone else has already paired through.
    nonisolated static let claimedCode = "VITA-TAKN"
    private var mockBuddyUserID: String { Self.buddyUserID }
    private var mockBuddyDisplayName: String { Self.buddyDisplayName }

    private let engine: BuddyPairingEngine
    private let storage: BuddyLinkStorage

    // MARK: Persistence keys

    private let defaults: UserDefaults
    private enum Key {
        static let myUserID    = "buddy.mock.myUserID"
        static let legacyCode  = "buddy.mock.linkedCode"   // how builds before the engine marked "linked"
        static let inbox       = "buddy.mock.inbox"        // [Nudge wire dto] JSON
        static let buddyStreak = "buddy.mock.buddyStreak"  // persisted so it grows believably
    }

    // MARK: In-memory state

    /// Pending "buddy replies" we'll deliver into the inbox once their fire date passes.
    /// In-memory only — see the class note.
    private var pendingReplies: [PendingNudge] = []

    // MARK: Init

    /// - Parameter myUserID: the app's own id for this user, so the link and "which code is
    ///   mine" are stored under the same id the view model uses. Without one (a preview),
    ///   the mock keeps an id of its own.
    /// - Parameter applyDemoLink: whether a DEBUG demo argument may set or clear the link
    ///   now. The app passes true for the first service of a launch only: SwiftUI builds a
    ///   view model (and so a service) every time it re-creates the view that owns one, and
    ///   applying it again would pair the user right after they unpaired.
    init(myUserID: String? = nil,
         defaults: UserDefaults = .standard,
         arguments: [String] = CommandLine.arguments,
         applyDemoLink: Bool = true) {
        self.defaults = defaults
        let me: String
        if let myUserID {
            me = myUserID
        } else if let existing = defaults.string(forKey: Key.myUserID) {
            me = existing
        } else {
            me = "me-" + UUID().uuidString.prefix(8)
            defaults.set(me, forKey: Key.myUserID)
        }
        self.myUserID = me
        let storage = BuddyLinkStorage(myUserID: me, namespace: "buddy.mock", defaults: defaults)
        self.storage = storage

        // A link stored by a build from before the engine: keep it.
        if defaults.string(forKey: Key.legacyCode)?.isEmpty == false {
            if storage.buddyUserID == nil {
                storage.setLinked(buddyUserID: Self.buddyUserID,
                                  via: .init(code: Self.buddyCode, role: .claimant))
            }
            defaults.removeObject(forKey: Key.legacyCode)
        }
        #if DEBUG
        // DEBUG: `--demo-buddy` starts already paired, so the linked hub can be shown
        // without typing a code; `--demo-buddy-state unpaired` starts with no buddy.
        let demo = DemoState(arguments: arguments)
        self.demoState = demo
        if applyDemoLink {
            if demo == .unpaired {
                storage.clear()
            } else if arguments.contains("--demo-buddy") || demo != nil {
                storage.setLinked(buddyUserID: Self.buddyUserID,
                                  via: .init(code: Self.buddyCode, role: .claimant))
            }
        }
        #endif

        // The "server": Sam's record (claimed by me if this phone is paired) and one that
        // is taken. In memory, so it is rebuilt to agree with the persisted link.
        let backend = InMemoryPairingStore.Backend()
        let paired = storage.buddyUserID == Self.buddyUserID
        backend.seed(BuddyPairingRecord(code: Self.buddyCode, ownerUserID: Self.buddyUserID,
                                        claimantUserID: paired ? me : nil))
        backend.seed(BuddyPairingRecord(code: Self.claimedCode, ownerUserID: "mock.someone",
                                        claimantUserID: "mock.someone.else"))
        self.engine = BuddyPairingEngine(myUserID: me,
                                         store: InMemoryPairingStore(backend: backend),
                                         storage: storage)

        #if DEBUG
        if arguments.contains("--demo-buddy"), loadInbox().isEmpty {
            let n1 = Nudge(fromUserID: mockBuddyUserID, toUserID: me,
                           kind: .proudOfYou, text: "So proud of you today! 🙌")
            let n2 = Nudge(fromUserID: mockBuddyUserID, toUserID: me,
                           kind: .cheer, text: "We're both crushing it 💚")
            saveInbox([n1.wireDTO, n2.wireDTO])
        }
        #endif
    }

    #if DEBUG
    /// DEBUG: `--demo-buddy-state <stale|silent|unpaired>` puts the simulated buddy in a
    /// state that otherwise takes days to reach, for looking at the screen that shows it.
    enum DemoState: String {
        /// Sam last published nine days ago.
        case stale
        /// Paired, and Sam has never published.
        case silent
        /// No buddy.
        case unpaired

        init?(arguments: [String]) {
            guard let i = arguments.firstIndex(of: "--demo-buddy-state"), i + 1 < arguments.count,
                  let state = DemoState(rawValue: arguments[i + 1]) else { return nil }
            self = state
        }
    }
    private var demoState: DemoState?
    #endif

    // MARK: BuddySyncService

    nonisolated func generatePairingCode() -> String {
        BuddyPairingCode.make()
    }

    func link(usingCode code: String) async throws {
        try await engine.claim(code: code)
        // Seed a warm opening message so the inbox isn't empty on first connect.
        if loadInbox().isEmpty {
            let hello = Nudge(fromUserID: mockBuddyUserID,
                              toUserID: myUserID,
                              kind: .cheer,
                              text: "Yay, we're connected! Let's keep each other going. 💚")
            saveInbox([hello.wireDTO])
        }
    }

    func publishMyPairingCode(_ code: String) async throws {
        try await engine.announce(code: code)
    }

    func unlink() async throws {
        // Idempotent: clearing when already unlinked is fine.
        await engine.unlink()
        defaults.removeObject(forKey: Key.inbox)
        defaults.removeObject(forKey: Key.buddyStreak)
        pendingReplies.removeAll()
    }

    func sendNudge(_ nudge: Nudge) async throws {
        try requireLinked()
        // In the mock, "sending" just means the buddy receives it (we don't store the
        // outbound copy here — the caller owns that). What we DO simulate is a reply:
        // the buddy warmly nudges back a few moments later so the loop is demoable.
        let reply = Nudge(fromUserID: mockBuddyUserID,
                          toUserID: myUserID,
                          kind: Self.replyKind(to: nudge.kind),
                          text: Self.replyText(to: nudge.kind))
        let fireAt = Date.now.addingTimeInterval(Self.replyDelaySeconds)
        pendingReplies.append(PendingNudge(nudge: reply.wireDTO, fireAt: fireAt))
    }

    func fetchInbox() async throws -> [Nudge] {
        try requireLinked()
        deliverDueReplies()
        // Most-recent first.
        return loadInbox()
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.model)
    }

    func markRead(_ nudgeID: UUID) async throws {
        try requireLinked()
        var inbox = loadInbox()
        if let i = inbox.firstIndex(where: { $0.id == nudgeID }) {
            inbox[i].isRead = true
            saveInbox(inbox)
        }
    }

    func publish(mySnapshot snapshot: BuddySnapshotPayload) async throws {
        try requireLinked()
        // Nothing to persist on a "remote" in the mock — my buddy can't actually see it.
        // The call is accepted so the publish path is exercised end-to-end. (No-op.)
        _ = snapshot
    }

    func fetchBuddySnapshot() async throws -> BuddySnapshotPayload? {
        guard isLinked else { throw BuddySyncError.notLinked }
        try await engine.verifyLink()
        deliverDueReplies() // keep the world ticking when the UI polls

        #if DEBUG
        if demoState == .silent { return nil }
        if demoState == .stale {
            // Nine days without a publish: what a buddy who reinstalled leaves behind.
            return BuddySnapshotPayload(ownerUserID: mockBuddyUserID,
                                        displayName: mockBuddyDisplayName,
                                        dayStreak: 6,
                                        characterMood: .happy,
                                        loggedToday: true,
                                        lastActive: Date.now.addingTimeInterval(-9 * 86_400),
                                        stepsToday: 8_400, stepGoal: 10_000,
                                        waterToday: 80, waterGoal: 96,
                                        workedOutToday: true, workoutSummary: "Chest · Arms")
        }
        #endif

        // A believable, *encouraging* buddy: a healthy streak that nudges upward a touch
        // each calendar day, a positive mood, usually-logged, recently active.
        let streak = bumpedBuddyStreak()
        let mood: BuddyCharacterMood = streak >= 7 ? .thriving : .happy
        // Pretend they were active sometime in the last couple of hours.
        let lastActive = Date.now.addingTimeInterval(-Double.random(in: 300...7200))

        // Believable daily ACTIVITY for the face-off. The simulated buddy has their own
        // goals (10k steps, 96 oz of water); the numbers land around them, sometimes above
        // and sometimes a little below, and are scored as a share of THEIR goal.
        let buddyStepGoal = 10_000
        let buddyWaterGoal = 96.0
        let buddySteps = Int(Double(buddyStepGoal) * Double.random(in: 0.7...1.15))
        let buddyWater = (buddyWaterGoal * Double.random(in: 0.65...1.2)).rounded()
        let buddyWorkedOut = Double.random(in: 0...1) < 0.7   // usually moves, not always

        // OPT-IN full data (weight / calories / food). The simulated buddy has opted in, so
        // the full-stats part of the card is visible in the Simulator. Fixed sample numbers.
        return BuddySnapshotPayload(ownerUserID: mockBuddyUserID,
                                    displayName: mockBuddyDisplayName,
                                    dayStreak: streak,
                                    characterMood: mood,
                                    loggedToday: true,
                                    lastActive: lastActive,
                                    stepsToday: buddySteps,
                                    stepGoal: buddyStepGoal,
                                    waterToday: buddyWater,
                                    waterGoal: buddyWaterGoal,
                                    workedOutToday: buddyWorkedOut,
                                    workoutSummary: buddyWorkedOut ? "Chest · Arms" : "",
                                    sharesFullData: true,
                                    trendWeightLbs: 153.8,
                                    goalWeightLbs: 140,
                                    weeklyRateLbs: -1.2,
                                    caloriesEaten: 1355,
                                    calorieTarget: 1741,
                                    proteinEaten: 98,
                                    proteinTarget: 126,
                                    todayFoods: "Greek yogurt & berries, Grilled chicken salad, Trail mix")
    }

    // MARK: - Linked-state helpers

    /// Protocol: the linked buddy id, read from persistence so the UI restores the paired
    /// state at launch.
    nonisolated var linkedBuddyID: String? { storage.buddyUserID }

    private var isLinked: Bool { storage.buddyUserID != nil }

    private func requireLinked() throws {
        if !isLinked { throw BuddySyncError.notLinked }
    }

    // MARK: - Reply delivery

    /// Move any pending buddy replies whose time has come into the persisted inbox.
    private func deliverDueReplies() {
        guard !pendingReplies.isEmpty else { return }
        let now = Date.now
        let (due, stillPending) = pendingReplies.partitioned { $0.fireAt <= now }
        guard !due.isEmpty else { return }
        var inbox = loadInbox()
        inbox.append(contentsOf: due.map(\.nudge))
        saveInbox(inbox)
        pendingReplies = stillPending
    }

    // MARK: - Buddy streak (persisted, grows believably)

    /// Returns the buddy's day-streak, nudging it up by 1 the first time it's read on a
    /// new calendar day so the simulated buddy feels alive without runaway growth.
    private func bumpedBuddyStreak() -> Int {
        let stored = defaults.object(forKey: Key.buddyStreak) as? [String: Any]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        var streak = (stored?["streak"] as? Int) ?? 5   // start at a warm, healthy 5
        if let lastBumpInterval = stored?["lastBump"] as? Double {
            let lastBump = calendar.startOfDay(for: Date(timeIntervalSince1970: lastBumpInterval))
            if today > lastBump { streak += 1 }          // a new day → +1
        }
        defaults.set(["streak": streak, "lastBump": today.timeIntervalSince1970],
                     forKey: Key.buddyStreak)
        return streak
    }

    // MARK: - Inbox persistence (JSON in UserDefaults)

    private func loadInbox() -> [NudgeDTO] {
        guard let data = defaults.data(forKey: Key.inbox),
              let decoded = try? JSONDecoder().decode([NudgeDTO].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveInbox(_ inbox: [NudgeDTO]) {
        guard let data = try? JSONEncoder().encode(inbox) else { return }
        defaults.set(data, forKey: Key.inbox)
    }

    // MARK: - Reply tone (always kind)

    private static let replyDelaySeconds: TimeInterval = 4

    /// Pick a warm reply intent for an incoming nudge. Every branch is health-positive.
    private static func replyKind(to incoming: NudgeKind) -> NudgeKind {
        switch incoming {
        case .cheer:      return .proudOfYou
        case .checkIn:    return .checkIn
        case .flex:       return .cheer
        case .proudOfYou: return .proudOfYou
        case .letsMove:   return .letsMove
        }
    }

    private static func replyText(to incoming: NudgeKind) -> String {
        switch incoming {
        case .cheer:      return "Aw, thank you! Right back at you — you're crushing it. 💚"
        case .checkIn:    return "Doing good! Just thinking about you. How are you holding up?"
        case .flex:       return "Heck yes! 🎉 So happy for you."
        case .proudOfYou: return "That means a lot. I'm proud of you too. 🙌"
        case .letsMove:   return "I'm in! Let's both get a little movement in today. 🚶"
        }
    }
}

// MARK: - Wire DTOs (Codable; independent of SwiftData)

/// Plain `Codable` form of a `Nudge` for JSON persistence in the mock. Kept separate
/// from the SwiftData @Model (which isn't `Codable`).
private struct NudgeDTO: Codable {
    var id: UUID
    var fromUserID: String
    var toUserID: String
    var kindRaw: String
    var text: String
    var createdAt: Date
    var isRead: Bool

    /// Rebuild a (detached) @Model from this DTO for returning to callers.
    var model: Nudge {
        Nudge(id: id,
              fromUserID: fromUserID,
              toUserID: toUserID,
              kind: NudgeKind(rawValue: kindRaw) ?? .cheer,
              text: text,
              createdAt: createdAt,
              isRead: isRead)
    }
}

private extension Nudge {
    /// Snapshot this @Model into a `Codable` DTO for persistence.
    var wireDTO: NudgeDTO {
        NudgeDTO(id: id,
                 fromUserID: fromUserID,
                 toUserID: toUserID,
                 kindRaw: kindRaw,
                 text: text,
                 createdAt: createdAt,
                 isRead: isRead)
    }
}

/// A buddy reply queued to be delivered into the inbox once `fireAt` passes.
private struct PendingNudge {
    var nudge: NudgeDTO
    var fireAt: Date
}

// MARK: - Small utilities

private extension Array {
    /// Split into (matching, rest) preserving order — used for due-reply delivery.
    func partitioned(_ belongsInFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for el in self {
            if belongsInFirst(el) { first.append(el) } else { second.append(el) }
        }
        return (first, second)
    }
}
