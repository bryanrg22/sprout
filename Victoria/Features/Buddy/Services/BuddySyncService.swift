import Foundation

/// The contract for syncing buddy state (pairing, nudges, daily snapshots) between two
/// people. The app talks ONLY to this protocol; concrete backends are swappable:
///
/// - `CloudKitSyncService`: the real one, on a device (CloudKit public database).
/// - `LocalMockSyncService`: the Simulator's stand-in (it cannot sign in to iCloud), with a
///   simulated buddy. `BuddySync.makeDefault` chooses between the two.
///
/// Pairing is the same code behind both: `BuddyPairingEngine`. The sequence, each failure
/// and what the user sees are in `docs/buddy-sync.md`.
///
/// Any method may throw `BuddySyncError`; the UI turns each case into its own plain
/// sentence, never an alert.
///
/// Snapshot transport uses a plain `Codable` value type (`BuddySnapshotPayload`) rather
/// than the SwiftData `@Model` `BuddySnapshot`, so the wire format is independent of the
/// persistence layer (SwiftData models aren't `Sendable`/`Codable` and shouldn't cross
/// actor or network boundaries).
protocol BuddySyncService: Sendable {

    /// Generate a fresh, human-shareable pairing code (e.g. "VITA-7F3K").
    /// Synchronous + pure: it just mints a string; it does not contact any backend.
    func generatePairingCode() -> String

    /// Announce *my* pairing code on the backend so a buddy who types it can find and
    /// claim me — the code-GENERATOR side of the handshake. Call it whenever the user is
    /// shown their own code. Idempotent; a no-op for backends that don't need it (the mock).
    func publishMyPairingCode(_ code: String) async throws

    /// Connect this user to the buddy who shared `code` (the code-TYPER side). Returns only
    /// when the claim was saved on the backend; `linkedBuddyID` is non-nil from then on and
    /// not before. On any throw nothing was persisted and the user can try again.
    /// - Throws: `.malformedPairingCode` (cannot be a code), `.ownPairingCode`,
    ///   `.invalidPairingCode` (nobody has shared it: a typo, or not uploaded yet),
    ///   `.pairingCodeAlreadyClaimed`, or one of the "could not reach it" cases.
    func link(usingCode code: String) async throws

    /// End the pairing. This device forgets the link first, so leaving never waits for the
    /// network; then, best-effort, the backend is told (my claim is taken off the buddy's
    /// record and my own code's record is removed), which is how the other side finds out,
    /// and the snapshot I published is removed. Idempotent: unlinking when not linked does
    /// nothing.
    func unlink() async throws

    /// Send a kind nudge to the linked buddy.
    /// - Throws: `.notLinked` if there's no buddy yet, `.cloudKitUnavailable` if offline.
    func sendNudge(_ nudge: Nudge) async throws

    /// Fetch nudges addressed to this user (most-recent first is recommended but not
    /// required by the contract). Returns an empty array when there's nothing waiting.
    func fetchInbox() async throws -> [Nudge]

    /// Mark a nudge as read on the backend.
    func markRead(_ nudgeID: UUID) async throws

    /// Publish *my* current snapshot so my buddy can see how I'm doing today.
    func publish(mySnapshot snapshot: BuddySnapshotPayload) async throws

    /// Fetch my buddy's latest snapshot, or `nil` if they haven't published one yet.
    /// - Throws: `.notLinked` when there is no buddy, and `.unpairedByBuddy` when the
    ///   backend shows the buddy ended the pairing (the local link is cleared before it throws).
    func fetchBuddySnapshot() async throws -> BuddySnapshotPayload?

    /// The buddy this device is currently linked to, restored from LOCAL persistence —
    /// `nil` when not linked. Read synchronously (and nonisolated) so the UI can show the
    /// paired state immediately on launch instead of resetting to the pairing screen and
    /// re-discovering over the network. The CloudKit backend persists this in `UserDefaults`;
    /// the mock derives it from its stored linked code.
    var linkedBuddyID: String? { get }
}

/// Plain, `Sendable` + `Codable` transport form of a buddy snapshot. Mirrors the
/// `BuddySnapshot` @Model's fields but carries no SwiftData machinery, so it's safe to
/// pass across actors and (later) encode into a `CKRecord`. Map to/from the @Model at
/// the call site.
struct BuddySnapshotPayload: Codable, Sendable, Equatable {
    var ownerUserID: String
    var displayName: String
    var dayStreak: Int
    /// Raw value of `BuddyCharacterMood` — kept as the wire-stable string.
    var characterMoodRaw: String
    var loggedToday: Bool
    var lastActive: Date

    // Daily activity for the face-off (steps / water / movement + each person's OWN
    // goals). Always shared. Defaulted so the type stays decodable from older payloads.
    var stepsToday: Int = 0
    var stepGoal: Int = 0
    var waterToday: Double = 0
    var waterGoal: Double = 0
    var workedOutToday: Bool = false
    /// Short, SAFE label of today's workout for the face-off ("Chest · Arms", "Run · 30 min").
    /// Empty when no session was logged. Movement only — never weight/reps/intensity.
    var workoutSummary: String = ""

    // Full shared data (OPT-IN — weight / calories / food). Mirrors the matching block on
    // the `BuddySnapshot` @Model. Only meaningful when `sharesFullData` is true (the owner
    // opted in via `UserProfile.shareFullStatsWithBuddy`); otherwise these stay at their
    // 0/"" defaults and the display card renders nothing. ADDITIVE — the activity-only
    // face-off above is unchanged. Defaulted so older payloads (which predate these fields)
    // still decode cleanly.
    var sharesFullData: Bool = false
    var trendWeightLbs: Double = 0
    var goalWeightLbs: Double = 0
    /// Weekly rate of change in lbs, SIGNED (negative = losing).
    var weeklyRateLbs: Double = 0
    var caloriesEaten: Double = 0
    var calorieTarget: Double = 0
    var proteinEaten: Double = 0
    var proteinTarget: Double = 0
    /// Carbs eaten today (g) + daily carb target (opt-in, gated by `sharesFullData`).
    var carbsEaten: Double = 0
    var carbTarget: Double = 0
    /// Fat eaten today (g) + daily fat target (opt-in, gated by `sharesFullData`).
    var fatEaten: Double = 0
    var fatTarget: Double = 0
    /// Today's logged food names, comma-joined.
    var todayFoods: String = ""

    // MARK: - Freshness

    /// True only when this snapshot's data is actually from the current calendar day. A snapshot
    /// last synced yesterday (its `lastActive` is yesterday) must NOT be read as "today" — otherwise
    /// the hub shows last night's totals under a "logged today" label. (Buddy sync is pull-on-open,
    /// so a snapshot can easily be hours old; this is the guard that keeps the display honest.)
    var reflectsToday: Bool { Calendar.current.isDateInToday(lastActive) }

    /// "Logged today", gated on freshness — the meaning every presence / celebration read wants
    /// (the shared panda, the "both logged today" headline, the logged-✓ dots, the card badge).
    var loggedTodayEffective: Bool { loggedToday && reflectsToday }

    init(ownerUserID: String,
         displayName: String,
         dayStreak: Int,
         characterMood: BuddyCharacterMood,
         loggedToday: Bool,
         lastActive: Date,
         stepsToday: Int = 0,
         stepGoal: Int = 0,
         waterToday: Double = 0,
         waterGoal: Double = 0,
         workedOutToday: Bool = false,
         workoutSummary: String = "",
         sharesFullData: Bool = false,
         trendWeightLbs: Double = 0,
         goalWeightLbs: Double = 0,
         weeklyRateLbs: Double = 0,
         caloriesEaten: Double = 0,
         calorieTarget: Double = 0,
         proteinEaten: Double = 0,
         proteinTarget: Double = 0,
         carbsEaten: Double = 0,
         carbTarget: Double = 0,
         fatEaten: Double = 0,
         fatTarget: Double = 0,
         todayFoods: String = "") {
        self.ownerUserID = ownerUserID
        self.displayName = displayName
        self.dayStreak = dayStreak
        self.characterMoodRaw = characterMood.rawValue
        self.loggedToday = loggedToday
        self.lastActive = lastActive
        self.stepsToday = stepsToday
        self.stepGoal = stepGoal
        self.waterToday = waterToday
        self.waterGoal = waterGoal
        self.workedOutToday = workedOutToday
        self.workoutSummary = workoutSummary
        self.sharesFullData = sharesFullData
        self.trendWeightLbs = trendWeightLbs
        self.goalWeightLbs = goalWeightLbs
        self.weeklyRateLbs = weeklyRateLbs
        self.caloriesEaten = caloriesEaten
        self.calorieTarget = calorieTarget
        self.proteinEaten = proteinEaten
        self.proteinTarget = proteinTarget
        self.carbsEaten = carbsEaten
        self.carbTarget = carbTarget
        self.fatEaten = fatEaten
        self.fatTarget = fatTarget
        self.todayFoods = todayFoods
        // The opt-in is enforced HERE, in the one initializer every publish passes through,
        // not left to callers: a snapshot that does not share full data carries none of it.
        if !sharesFullData { self = withoutFullData }
    }

    /// This snapshot with every opt-in field (weight, calories, macros, food names) blanked.
    /// What leaves the device when the owner has not opted in to sharing full stats.
    var withoutFullData: BuddySnapshotPayload {
        var copy = self
        copy.sharesFullData = false
        copy.trendWeightLbs = 0
        copy.goalWeightLbs = 0
        copy.weeklyRateLbs = 0
        copy.caloriesEaten = 0
        copy.calorieTarget = 0
        copy.proteinEaten = 0
        copy.proteinTarget = 0
        copy.carbsEaten = 0
        copy.carbTarget = 0
        copy.fatEaten = 0
        copy.fatTarget = 0
        copy.todayFoods = ""
        return copy
    }

    /// Decoded enum (falls back to `.happy` if an unknown value ever arrives).
    var characterMood: BuddyCharacterMood {
        BuddyCharacterMood(rawValue: characterMoodRaw) ?? .happy
    }
}

// MARK: - Mapping helpers

extension BuddySnapshotPayload {
    /// Build a transport payload from a persisted @Model snapshot.
    init(from model: BuddySnapshot) {
        self.init(ownerUserID: model.ownerUserID,
                  displayName: model.displayName,
                  dayStreak: model.dayStreak,
                  characterMood: model.characterMood,
                  loggedToday: model.loggedToday,
                  lastActive: model.lastActive,
                  stepsToday: model.stepsToday,
                  stepGoal: model.stepGoal,
                  waterToday: model.waterToday,
                  waterGoal: model.waterGoal,
                  workedOutToday: model.workedOutToday,
                  workoutSummary: model.workoutSummary,
                  sharesFullData: model.sharesFullData,
                  trendWeightLbs: model.trendWeightLbs,
                  goalWeightLbs: model.goalWeightLbs,
                  weeklyRateLbs: model.weeklyRateLbs,
                  caloriesEaten: model.caloriesEaten,
                  calorieTarget: model.calorieTarget,
                  proteinEaten: model.proteinEaten,
                  proteinTarget: model.proteinTarget,
                  carbsEaten: model.carbsEaten,
                  carbTarget: model.carbTarget,
                  fatEaten: model.fatEaten,
                  fatTarget: model.fatTarget,
                  todayFoods: model.todayFoods)
    }

    /// Materialize a (detached) @Model snapshot from this payload. The caller decides
    /// whether/where to insert it into a `ModelContext`.
    func makeModel() -> BuddySnapshot {
        BuddySnapshot(ownerUserID: ownerUserID,
                      displayName: displayName,
                      dayStreak: dayStreak,
                      characterMood: characterMood,
                      loggedToday: loggedToday,
                      lastActive: lastActive,
                      stepsToday: stepsToday,
                      stepGoal: stepGoal,
                      waterToday: waterToday,
                      waterGoal: waterGoal,
                      workedOutToday: workedOutToday,
                      workoutSummary: workoutSummary,
                      sharesFullData: sharesFullData,
                      trendWeightLbs: trendWeightLbs,
                      goalWeightLbs: goalWeightLbs,
                      weeklyRateLbs: weeklyRateLbs,
                      caloriesEaten: caloriesEaten,
                      calorieTarget: calorieTarget,
                      proteinEaten: proteinEaten,
                      proteinTarget: proteinTarget,
                      carbsEaten: carbsEaten,
                      carbTarget: carbTarget,
                      fatEaten: fatEaten,
                      fatTarget: fatTarget,
                      todayFoods: todayFoods)
    }
}

// MARK: - Errors

/// The ways buddy sync fails. Each is a state the UI describes in its own words
/// (`BuddyViewModel.message(for:)`), never a crash and never an alert.
enum BuddySyncError: Error, LocalizedError, Equatable {
    /// CloudKit could not be reached or refused the call (offline, throttled, a schema or
    /// permission problem). The exact `CKError` is in the Diagnostics log.
    case cloudKitUnavailable
    /// This device is not signed in to iCloud (or iCloud is restricted on it), so there is
    /// no account to sync with. Waiting does not fix this; signing in does.
    case iCloudAccountMissing
    /// An action needed a buddy, but this user isn't paired with anyone.
    case notLinked
    /// What was typed cannot be a pairing code (wrong shape, or a character codes never use).
    case malformedPairingCode
    /// Nobody has shared that code: a typo, or the buddy's phone has not uploaded it yet.
    /// The typer's device cannot tell which.
    case invalidPairingCode
    /// The code is this user's own.
    case ownPairingCode
    /// Someone else already paired through that code.
    case pairingCodeAlreadyClaimed
    /// Announcing my code found another user's record under it; I need a different code.
    case pairingCodeTaken
    /// The buddy ended the pairing. The local link has already been cleared.
    case unpairedByBuddy
    /// A backend operation failed for some other reason; carries a short reason string.
    case backendFailure(String)

    var errorDescription: String? {
        switch self {
        case .cloudKitUnavailable:
            return "Buddy sync couldn't reach iCloud just now."
        case .iCloudAccountMissing:
            return "This device isn't signed in to iCloud."
        case .notLinked:
            return "You're not connected with a buddy yet."
        case .malformedPairingCode:
            return "That isn't a pairing code."
        case .invalidPairingCode:
            return "Nobody has shared that code."
        case .ownPairingCode:
            return "That's your own code."
        case .pairingCodeAlreadyClaimed:
            return "That code is already paired with someone else."
        case .pairingCodeTaken:
            return "That pairing code belongs to someone else."
        case .unpairedByBuddy:
            return "Your buddy ended the pairing."
        case .backendFailure(let reason):
            return "Something went sideways syncing with your buddy. (\(reason))"
        }
    }
}
