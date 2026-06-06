import Foundation

/// A fully local, backend-free implementation of `BuddySyncService` that **simulates a
/// warm, present buddy** so the entire accountability-buddy UX is exercisable TODAY —
/// no paid account, no iCloud, no network.
///
/// What it fakes, and how:
/// - **Pairing:** `link(usingCode:)` always "succeeds" against a friendly simulated
///   buddy (default name "Bryan") and remembers that we're linked. `generatePairingCode`
///   mints a real-looking code. `unlink` clears everything.
/// - **A believable buddy snapshot:** `fetchBuddySnapshot()` returns a buddy who's doing
///   well — a healthy streak, "thriving/happy", usually logged today, recently active.
///   The values drift a little over time/calls so it doesn't look frozen.
/// - **Nudges that feel two-way:** when you `sendNudge`, the buddy "writes back" — a
///   warm reply nudge is queued into your own inbox after a short, human-feeling delay,
///   so the loop (send → ding → reply) is demoable end-to-end.
///
/// **Isolation.** This is a `@MainActor final class` (not an `actor`). That's deliberate
/// and matches this codebase's SwiftData convention: the app's `ModelContext` lives on
/// the main actor and `@Model` objects are bound to it, so the `Nudge` models that flow
/// through this service must never cross an actor boundary (see the equivalent note in
/// `HealthKitService`). Running the whole service on the main actor keeps that safe.
/// `@MainActor` types are implicitly `Sendable`, satisfying `BuddySyncService`.
///
/// **State.** The link + inbox are persisted to `UserDefaults` (JSON) so a relaunch
/// keeps your buddy and messages; the "pending replies" timers are in-memory only
/// (a relaunch simply delivers any due replies immediately on the next `fetchInbox`).
///
/// This is the **default sync in DEBUG** (see `BuddySync.makeDefault`).
@MainActor
final class LocalMockSyncService: BuddySyncService {

    // MARK: Identity

    /// A stable id for "me" in the mock world, persisted so it's consistent across launches.
    private let myUserID: String

    /// The simulated buddy's identity.
    private let mockBuddyUserID = "mock.buddy.bryan"
    private let mockBuddyDisplayName = "Bryan"

    // MARK: Persistence keys

    private let defaults: UserDefaults
    private enum Key {
        static let myUserID    = "buddy.mock.myUserID"
        static let linkedCode  = "buddy.mock.linkedCode"   // non-nil => linked
        static let inbox       = "buddy.mock.inbox"        // [Nudge wire dto] JSON
        static let buddyStreak = "buddy.mock.buddyStreak"  // persisted so it grows believably
    }

    // MARK: In-memory state

    /// Pending "buddy replies" we'll deliver into the inbox once their fire date passes.
    /// In-memory only — see the class note.
    private var pendingReplies: [PendingNudge] = []

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let existing = defaults.string(forKey: Key.myUserID) {
            self.myUserID = existing
        } else {
            let fresh = "me-" + UUID().uuidString.prefix(8)
            defaults.set(fresh, forKey: Key.myUserID)
            self.myUserID = fresh
        }
        #if DEBUG
        // DEBUG: `--demo-buddy` starts already linked with a couple of warm notes, so the
        // linked hub (shared panda + status + inbox) can be screenshotted without pairing.
        if CommandLine.arguments.contains("--demo-buddy") {
            defaults.set("VITA-DEMO", forKey: Key.linkedCode)
            if loadInbox().isEmpty {
                let n1 = Nudge(fromUserID: mockBuddyUserID, toUserID: myUserID,
                               kind: .proudOfYou, text: "So proud of you today! 🙌")
                let n2 = Nudge(fromUserID: mockBuddyUserID, toUserID: myUserID,
                               kind: .cheer, text: "We're both crushing it 💚")
                saveInbox([n1.wireDTO, n2.wireDTO])
            }
        }
        #endif
    }

    // MARK: BuddySyncService

    nonisolated func generatePairingCode() -> String {
        Self.makePairingCode()
    }

    func link(usingCode code: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BuddySyncError.invalidPairingCode }
        // The mock is generous: any non-empty code connects you to the friendly buddy.
        defaults.set(trimmed.uppercased(), forKey: Key.linkedCode)
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
        // The simulated buddy is always "waiting", so there's nothing to announce. No-op.
        _ = code
    }

    func unlink() async throws {
        // Idempotent: clearing when already unlinked is fine.
        defaults.removeObject(forKey: Key.linkedCode)
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
        guard isLinked else { return nil }
        deliverDueReplies() // keep the world ticking when the UI polls

        // A believable, *encouraging* buddy: a healthy streak that nudges upward a touch
        // each calendar day, a positive mood, usually-logged, recently active.
        let streak = bumpedBuddyStreak()
        let mood: BuddyCharacterMood = streak >= 7 ? .thriving : .happy
        // Pretend they were active sometime in the last couple of hours.
        let lastActive = Date.now.addingTimeInterval(-Double.random(in: 300...7200))

        // Believable daily ACTIVITY for the face-off (movement/hydration only — never
        // weight/calories). The simulated buddy is "Bryan", so he carries his own goals
        // (a higher 10k step goal, a standard ~96 oz water goal). The numbers land around
        // — sometimes above, sometimes a touch below — his goals so the face-off feels
        // alive and genuinely two-sided (some days he edges you, some days you edge him),
        // and they're scored as % of HIS own goal so it's always fair.
        let buddyStepGoal = 10_000
        let buddyWaterGoal = 96.0
        let buddySteps = Int(Double(buddyStepGoal) * Double.random(in: 0.7...1.15))
        let buddyWater = (buddyWaterGoal * Double.random(in: 0.65...1.2)).rounded()
        let buddyWorkedOut = Double.random(in: 0...1) < 0.7   // usually moves, not always

        // OPT-IN full data (weight / calories / food). The mock buddy "shares everything"
        // so the new BuddyFullStatsCard is visible in the Simulator without a real backend.
        // Fixed, believable sample numbers (a steady loser tracking toward a 140 goal,
        // eating under target with solid protein, a few wholesome foods logged today).
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
    /// state at launch. The mock simulates a single buddy.
    nonisolated var linkedBuddyID: String? {
        (defaults.string(forKey: Key.linkedCode)?.isEmpty == false) ? "mock-buddy" : nil
    }

    private var isLinked: Bool {
        (defaults.string(forKey: Key.linkedCode)?.isEmpty == false)
    }

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

    // MARK: - Pairing code generation (shared with CloudKit service)

    /// "VITA-XXXX" with an unambiguous alphabet (no 0/O/1/I/L) so it's easy to read aloud.
    /// `nonisolated` (pure, no state) so it can be called from the non-isolated
    /// `generatePairingCode()` requirement in both backends.
    nonisolated static func makePairingCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let suffix = String((0..<4).map { _ in alphabet.randomElement()! })
        return "VITA-\(suffix)"
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
