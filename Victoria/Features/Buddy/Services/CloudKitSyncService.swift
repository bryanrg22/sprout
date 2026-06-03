import Foundation
import CloudKit

/// A **real, minimal** CloudKit implementation of `BuddySyncService` for cross-device
/// buddy sync. It is wired against the current CloudKit async APIs and *degrades
/// gracefully*: every networked operation first checks that iCloud is actually usable
/// (`ensureAvailable()`) and throws `BuddySyncError.cloudKitUnavailable` when it isn't —
/// so nothing here can crash or hang the app, even before the backend is fully set up.
///
/// The CloudKit container `iCloud.com.bryanram.victoria` and the CloudKit service are
/// already declared in the app's entitlements / `project.yml`, and `Self.containerIdentifier`
/// matches them. What remains to take this LIVE is human-only (no code changes):
///
/// ┌─────────────────────────────────────────────────────────────────────────────────┐
/// │ REMAINING HUMAN STEPS TO GO LIVE (all done by a person; not code):                │
/// │                                                                                   │
/// │  1. SIGNING. Set `DEVELOPMENT_TEAM` in Xcode → Signing & Capabilities for a PAID   │
/// │     Apple Developer team (CloudKit containers require a paid membership; it is     │
/// │     blank in `project.yml` today).                                                 │
/// │  2. CONTAINER. Let Xcode create / register the `iCloud.com.bryanram.victoria`      │
/// │     container under that team (the iCloud capability + id are already declared;    │
/// │     Xcode just needs to provision it on the portal).                              │
/// │  3. iCLOUD SIGN-IN on BOTH physical devices (Settings → Apple ID) with DIFFERENT   │
/// │     iCloud accounts. `accountStatus()` returns `.available` only when signed in;   │
/// │     until then this service self-degrades to `.cloudKitUnavailable`. NOTE: the     │
/// │     Simulator can't sign in to iCloud, which is exactly why `BuddySync` routes the │
/// │     Simulator to `LocalMockSyncService`.                                            │
/// │  4. CLOUDKIT DASHBOARD — INDEXES. On first save CloudKit auto-creates the record    │
/// │     types in the *Development* environment, but custom fields are NOT queryable/    │
/// │     sortable by default. The ONLY query this service runs is the inbox fetch, so    │
/// │     in the PUBLIC database schema add:                                              │
/// │       - QUERYABLE index on `Nudge.toUserID`   (the inbox `records(matching:)` query)│
/// │       - SORTABLE  index on `Nudge.createdAt`  (the inbox sort)                      │
/// │     Pairing + snapshot records are addressed by deterministic record ID (no query), │
/// │     so `pairingCode` / `ownerUserID` do NOT need indexes unless a future query-     │
/// │     based lookup is reintroduced. Without the two `Nudge` indexes, the inbox query  │
/// │     fails (mapped here to `.cloudKitUnavailable`).                                  │
/// │  5. DEPLOY the schema from Development to PRODUCTION in the CloudKit Dashboard      │
/// │     before shipping a Release/TestFlight build (Development schema is not visible   │
/// │     to production builds).                                                          │
/// └─────────────────────────────────────────────────────────────────────────────────┘
///
/// HARDENING TODO (future, not required to go live): the pairing rendezvous below uses
/// the PUBLIC database keyed on a short `pairingCode` (simple, no share-acceptance UI,
/// fine for a tiny 2-person link). A stronger model would move buddy data into a CKShare
/// / shared zone so only the two intended iCloud users can see each other's records
/// rather than relying on a public, guessable code. See the TODO at `link`.
///
/// **Isolation & Sendability:** `@MainActor final class` (same rationale as
/// `LocalMockSyncService` — `Nudge` @Model objects are bound to the main-actor
/// `ModelContext` and must never cross an actor boundary). The CloudKit `await` calls
/// suspend off-main internally and resume on the main actor, so this stays fully
/// async/non-blocking. Because a `Nudge` (and CloudKit's own non-`Sendable` types) must
/// not be live across those suspensions, every method reads a `Nudge`'s fields into a
/// `Sendable` `NudgeWire` **synchronously before** the first `await`, and rebuilds any
/// returned `[Nudge]` from `NudgeWire`s **after** the awaits — see `sendNudge`/`fetchInbox`.
@MainActor
final class CloudKitSyncService: BuddySyncService {

    // MARK: Configuration

    // The iCloud container id. This MATCHES the value already declared in the app's
    // entitlements / `project.yml` (`com.apple.developer.icloud-container-identifiers`),
    // which is "iCloud." + the bundle id `com.bryanram.victoria`. Keep these in sync if
    // the bundle id ever changes.
    private static let containerIdentifier = "iCloud.com.bryanram.victoria"

    // CloudKit record types. These get auto-created in the Development environment on
    // first save; remember to add the queryable/sortable indexes (see step 4 above).
    private enum RecordType {
        static let pairing  = "BuddyPairing"
        static let nudge    = "Nudge"
        static let snapshot = "BuddySnapshot"
    }

    // Field keys (kept in one place so the schema is easy to audit).
    private enum Field {
        // Pairing
        static let pairingCode      = "pairingCode"
        static let ownerUserID      = "ownerUserID"
        static let buddyUserID      = "buddyUserID"
        static let displayName      = "displayName"
        // Nudge
        static let fromUserID       = "fromUserID"
        static let toUserID         = "toUserID"
        static let kindRaw          = "kindRaw"
        static let text             = "text"
        static let createdAt        = "createdAt"
        static let isRead           = "isRead"
        // Snapshot
        static let dayStreak        = "dayStreak"
        static let characterMoodRaw = "characterMoodRaw"
        static let loggedToday      = "loggedToday"
        static let lastActive       = "lastActive"
        // Snapshot — safe daily activity for the face-off (movement/hydration only;
        // NO weight, NO calories). `workedOutToday` is stored Bool-as-Int like `loggedToday`.
        static let stepsToday       = "stepsToday"
        static let stepGoal         = "stepGoal"
        static let waterToday       = "waterToday"
        static let waterGoal        = "waterGoal"
        static let workedOutToday   = "workedOutToday"
        // Snapshot — FULL shared data (OPT-IN: weight / calories / food). Only carries
        // meaning when `sharesFullData` is true (the owner opted in via
        // `UserProfile.shareFullStatsWithBuddy`). `sharesFullData` is stored Bool-as-Int
        // like `loggedToday`. Addressed by record ID (no query), so none of these need a
        // Dashboard index. Absent on older snapshot records → decoded as 0/false/"".
        static let sharesFullData   = "sharesFullData"
        static let trendWeightLbs   = "trendWeightLbs"
        static let goalWeightLbs    = "goalWeightLbs"
        static let weeklyRateLbs    = "weeklyRateLbs"
        static let caloriesEaten    = "caloriesEaten"
        static let calorieTarget    = "calorieTarget"
        static let proteinEaten     = "proteinEaten"
        static let proteinTarget    = "proteinTarget"
        static let todayFoods       = "todayFoods"
    }

    // MARK: Identity / cached pairing
    //
    // In a full build these come from the local `BuddyLink`. The service caches them so
    // it can address records without a SwiftData dependency. They're set by `link`.

    private let myUserID: String
    /// The linked buddy's id. Persisted to `UserDefaults` on every change (see `didSet`) and
    /// restored in `init`, so a pairing SURVIVES app relaunch instead of resetting to the
    /// pairing screen. (Previously this lived only in memory — the cause of "we keep getting
    /// un-paired after closing the app.")
    private var buddyUserID: String? {
        didSet { Self.persistLinkedBuddy(buddyUserID, myUserID: myUserID) }
    }
    /// The pairing code I've announced (owner side) — lets me poll the record to discover a
    /// buddy who claims it. Set by `publishMyPairingCode`.
    private var myPublishedCode: String?

    // MARK: CloudKit handles

    /// The container. Constructing a `CKContainer` is cheap and never throws even if the
    /// identifier isn't actually provisioned — the failure shows up later as a non-
    /// `.available` account status or a query error, both of which we map to
    /// `.cloudKitUnavailable`. So this initializer is safe to call today.
    private let container: CKContainer

    /// We use the PUBLIC database for the rendezvous-by-code approach (see the HARDENING
    /// TODO in the header and the detailed note at `link`).
    private var database: CKDatabase { container.publicCloudDatabase }

    // MARK: Init

    /// - Parameter myUserID: this device's stable user id (from `BuddyLink.myUserID`).
    init(myUserID: String) {
        self.myUserID = myUserID
        self.container = CKContainer(identifier: Self.containerIdentifier)
        // Restore a previously-linked buddy so the pairing survives app relaunch.
        // (Property observers don't fire during init, so this read won't re-persist.)
        self.buddyUserID = UserDefaults.standard.string(forKey: Self.linkKey(myUserID))
    }

    // MARK: - Link persistence (survives relaunch)

    private nonisolated static func linkKey(_ myUserID: String) -> String { "buddy.ck.linkedTo.\(myUserID)" }

    private nonisolated static func persistLinkedBuddy(_ id: String?, myUserID: String) {
        let key = linkKey(myUserID)
        if let id, !id.isEmpty { UserDefaults.standard.set(id, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// The linked buddy id, read straight from local persistence — `nil` ⇒ not linked.
    /// `nonisolated` so the UI can check it synchronously at launch to restore the paired
    /// state without a network round-trip.
    nonisolated var linkedBuddyID: String? {
        UserDefaults.standard.string(forKey: Self.linkKey(myUserID))
    }

    // MARK: Availability gate

    /// Throws `.cloudKitUnavailable` unless iCloud is signed in AND reachable. Every
    /// network method funnels through here first so the service can never hard-fail.
    private func ensureAvailable() async throws {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            // No entitlement / not provisioned / offline → treat as unavailable, softly.
            throw BuddySyncError.cloudKitUnavailable
        }
        guard status == .available else {
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    // MARK: BuddySyncService

    nonisolated func generatePairingCode() -> String {
        // Same generator as the mock so codes look identical regardless of backend.
        LocalMockSyncService.makePairingCode()
    }

    func publishMyPairingCode(_ code: String) async throws {
        try await ensureAvailable()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw BuddySyncError.invalidPairingCode }
        myPublishedCode = trimmed
        let recordID = CKRecord.ID(recordName: "pairing-\(trimmed)")
        do {
            // Already there: if I own it and a buddy has claimed, learn them now.
            let existing = try await database.record(for: recordID)
            if (existing[Field.ownerUserID] as? String) == myUserID,
               let claimant = existing[Field.buddyUserID] as? String, !claimant.isEmpty {
                buddyUserID = claimant
            }
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // First arrival: publish myself as owner so a code-typer has something to claim.
            let record = CKRecord(recordType: RecordType.pairing, recordID: recordID)
            record[Field.pairingCode] = trimmed as CKRecordValue
            record[Field.ownerUserID] = myUserID as CKRecordValue
            do { _ = try await database.save(record) }
            catch { throw BuddySyncError.cloudKitUnavailable }
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    /// Owner-side discovery: if I announced a code but don't yet know my buddy, re-read the
    /// pairing record to see whether someone has claimed it.
    private func resolveBuddyIfNeeded() async {
        guard buddyUserID == nil, let code = myPublishedCode else { return }
        let recordID = CKRecord.ID(recordName: "pairing-\(code)")
        if let record = try? await database.record(for: recordID),
           let claimant = record[Field.buddyUserID] as? String,
           !claimant.isEmpty, claimant != myUserID {
            buddyUserID = claimant
        }
    }

    /// One-time: subscribe to "a Nudge addressed to me was just created" so CloudKit
    /// pushes a notification to this device the moment a buddy nudges — even with the app
    /// closed. Best-effort + idempotent (guarded by a per-user flag). Requires the push
    /// entitlement + a signed-in iCloud account to actually deliver (see header steps);
    /// until then it just no-ops and retries. Dashboard: the `Nudge.toUserID` field must
    /// be QUERYABLE for the subscription's predicate (same index the inbox query needs).
    private func ensureNudgeSubscription() async {
        // v2 bumps the subscription so devices that had the old static-text one recreate it
        // with the DYNAMIC body below ("Victoria: You've got this 💚" / "🎉 Victoria hit her
        // goal!") pulled from the nudge's own `text` field, instead of a generic line.
        let key = "buddy.ck.subscribed.v2.\(myUserID)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        // Remove the old static-text subscription first, so a nudge can't double-notify.
        try? await database.deleteSubscription(withID: "nudges-to-\(myUserID)")

        let predicate = NSPredicate(format: "%K == %@", Field.toUserID, myUserID)
        let subscription = CKQuerySubscription(
            recordType: RecordType.nudge,
            predicate: predicate,
            subscriptionID: "nudges-to-\(myUserID)-v2",
            options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.title = "Vita 💛"
        // Show the ACTUAL nudge message on the lock screen. `alertLocalizationKey "%@"`
        // with the `text` record field as the arg fills the push body from the nudge itself
        // — so both hand-sent nudges and the auto goal-celebrations read naturally.
        info.alertLocalizationKey = "%@"
        info.alertLocalizationArgs = [Field.text]
        info.soundName = "default"
        info.shouldBadge = true
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
            UserDefaults.standard.set(true, forKey: key)   // created once
        } catch {
            // Best-effort: leave the flag unset so we retry next time (e.g. once iCloud is ready).
        }
    }

    func link(usingCode code: String) async throws {
        try await ensureAvailable()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw BuddySyncError.invalidPairingCode }

        // ── RENDEZVOUS BY SHARED CODE ──────────────────────────────────────────────────
        // The pairing record's name is DERIVED from the code, so both devices address the
        // exact same record without a query (and without depending on a queryable index
        // for the claim). Create-or-claim handshake:
        //   • record absent (`.unknownItem`) → I'm first: create it as owner, await my
        //     buddy to claim. (buddyUserID stays nil until they do.)
        //   • record present, owner ≠ me     → I'm second: claim it (write buddyUserID),
        //     and learn my buddy's id from `ownerUserID`.
        //   • record present, owner == me    → idempotent re-entry: no-op.
        //
        // KNOWN WIRING GAP (must be closed at the ViewModel/protocol layer — NOT reachable
        // from this file, and the protocol is frozen this round): today only the person who
        // *types a code* calls `link`. The person who *generated & shared* their code never
        // calls anything that publishes it. For the real two-device flow the lead must have
        // the code-generator also publish their pairing record (e.g. a `publishPairingCode`
        // step wired into pairing-code generation) so the other side has something to claim.
        // Until then, the first caller simply becomes the owner here (correct + harmless).
        //
        // TODO(CloudKit hardening): move this off the PUBLIC db to a CKShare / shared zone
        // so only the two intended iCloud users can see each other's records, instead of a
        // public (guessable) code. `pairingCode` is still stored on the record for Dashboard
        // visibility; mark it QUERYABLE if you reintroduce a query-based lookup.
        let recordID = CKRecord.ID(recordName: "pairing-\(trimmed)")

        let record: CKRecord
        let isNew: Bool
        do {
            record = try await database.record(for: recordID)
            isNew = false
        } catch let ckError as CKError where ckError.code == .unknownItem {
            record = CKRecord(recordType: RecordType.pairing, recordID: recordID)
            isNew = true
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }

        if isNew {
            // First arrival: publish myself as the owner; no buddy yet.
            record[Field.pairingCode] = trimmed as CKRecordValue
            record[Field.ownerUserID] = myUserID as CKRecordValue
            buddyUserID = nil
        } else {
            let ownerID = record[Field.ownerUserID] as? String
            if ownerID == myUserID {
                // I already own this code. If my buddy has already accepted it, ADOPT them —
                // this is how the code-OWNER links by entering their own code (e.g. after the
                // other person paired first). Without this the owner would no-op and stay
                // unpaired forever.
                if let claimant = record[Field.buddyUserID] as? String,
                   !claimant.isEmpty, claimant != myUserID {
                    buddyUserID = claimant
                }
                return
            }
            // Second arrival: claim the pairing and remember who I'm now linked to.
            record[Field.buddyUserID] = myUserID as CKRecordValue
            buddyUserID = ownerID
        }

        do {
            _ = try await database.save(record)
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    func unlink() async throws {
        // Best-effort and idempotent. If CloudKit is down we still consider the local
        // unlink successful (the caller clears the local `BuddyLink` regardless), so we
        // swallow availability errors here rather than blocking the user from leaving.
        buddyUserID = nil
        // TODO(CloudKit): also delete / detach the shared pairing + snapshot records for
        // this user once the CKShare model (see the HARDENING TODO in the header) is in
        // place. The skeleton no-ops the remote teardown to stay safe before then.
    }

    func sendNudge(_ nudge: Nudge) async throws {
        // SENDABILITY: read everything we need off the @Model `Nudge` into a `Sendable`
        // value *synchronously, on the main actor, BEFORE any `await`* — so the @Model is
        // never live across a CloudKit suspension point. (`init(from:)` is @MainActor.)
        let wire = NudgeWire(from: nudge)

        try await ensureAvailable()
        guard let toUserID = buddyUserID else { throw BuddySyncError.notLinked }

        // Stable record name = the nudge's UUID, so a retried send can't duplicate.
        let recordID = CKRecord.ID(recordName: wire.id.uuidString)
        let record = CKRecord(recordType: RecordType.nudge, recordID: recordID)
        record[Field.fromUserID] = myUserID as CKRecordValue
        record[Field.toUserID]   = toUserID as CKRecordValue
        record[Field.kindRaw]    = wire.kindRaw as CKRecordValue
        record[Field.text]       = wire.text as CKRecordValue
        record[Field.createdAt]  = wire.createdAt as CKRecordValue
        record[Field.isRead]     = (wire.isRead ? 1 : 0) as CKRecordValue

        do {
            _ = try await database.save(record)
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    func fetchInbox() async throws -> [Nudge] {
        try await ensureAvailable()

        // Everything addressed to me. Requires `toUserID` QUERYABLE + `createdAt` SORTABLE.
        let predicate = NSPredicate(format: "%K == %@", Field.toUserID, myUserID)
        let query = CKQuery(recordType: RecordType.nudge, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Field.createdAt, ascending: false)]

        // SENDABILITY: decode the CKRecords into `Sendable` `NudgeWire` values inside the
        // async region (no @Model crosses the suspension), then materialize `[Nudge]` from
        // them on the main actor AFTER the await — so the @Model `Nudge`es are built only
        // once we're safely back on the actor they belong to.
        let wires: [NudgeWire]
        do {
            let (matches, _) = try await database.records(matching: query)
            wires = matches.compactMap { _, result -> NudgeWire? in
                guard case .success(let record) = result else { return nil }
                return Self.nudgeWire(from: record)
            }
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }
        return wires.map { $0.makeModel() }
    }

    func markRead(_ nudgeID: UUID) async throws {
        try await ensureAvailable()
        let recordID = CKRecord.ID(recordName: nudgeID.uuidString)
        do {
            // CKRecord is Sendable (iOS 15+/Xcode 15+), so fetching it here and mutating
            // it across the save `await` is safe. We set the Bool as Int 1 (CloudKit has
            // no Bool type; reads decode `as? Int == 1` — see `nudgeWire(from:)`).
            let record = try await database.record(for: recordID)
            record[Field.isRead] = 1 as CKRecordValue
            _ = try await database.save(record)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // The record is already gone (e.g. deleted on the other side). A read-receipt
            // on a vanished nudge is a harmless no-op success, NOT an availability failure.
            return
        } catch {
            // Genuinely couldn't reach CloudKit — surface as the soft, expected state.
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    func publish(mySnapshot snapshot: BuddySnapshotPayload) async throws {
        try await ensureAvailable()

        // One snapshot record per owner — stable record name keyed on the owner id so
        // each publish overwrites the previous (latest-wins).
        let recordID = CKRecord.ID(recordName: "snapshot-\(snapshot.ownerUserID)")
        // Fetch-then-update if it exists (preserving the server change tag), else create.
        // IMPORTANT: only `.unknownItem` means "doesn't exist yet → create a fresh record".
        // Any *other* fetch error (offline, throttled, …) must NOT fall through to creating
        // a tag-less record — that would race the existing server copy and fail the save.
        // We surface those as `.cloudKitUnavailable` instead.
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            record = CKRecord(recordType: RecordType.snapshot, recordID: recordID)
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }
        record[Field.ownerUserID]      = snapshot.ownerUserID as CKRecordValue
        record[Field.displayName]      = snapshot.displayName as CKRecordValue
        record[Field.dayStreak]        = snapshot.dayStreak as CKRecordValue
        record[Field.characterMoodRaw] = snapshot.characterMoodRaw as CKRecordValue
        record[Field.loggedToday]      = (snapshot.loggedToday ? 1 : 0) as CKRecordValue
        record[Field.lastActive]       = snapshot.lastActive as CKRecordValue
        // Safe daily activity for the face-off (movement/hydration only).
        record[Field.stepsToday]       = snapshot.stepsToday as CKRecordValue
        record[Field.stepGoal]         = snapshot.stepGoal as CKRecordValue
        record[Field.waterToday]       = snapshot.waterToday as CKRecordValue
        record[Field.waterGoal]        = snapshot.waterGoal as CKRecordValue
        record[Field.workedOutToday]   = (snapshot.workedOutToday ? 1 : 0) as CKRecordValue
        // FULL shared data (OPT-IN: weight / calories / food). `sharesFullData` stores
        // Bool-as-Int (CloudKit has no Bool type) like `loggedToday`. The caller only fills
        // these with real values when the owner opted in; otherwise they're 0/"".
        record[Field.sharesFullData]   = (snapshot.sharesFullData ? 1 : 0) as CKRecordValue
        record[Field.trendWeightLbs]   = snapshot.trendWeightLbs as CKRecordValue
        record[Field.goalWeightLbs]    = snapshot.goalWeightLbs as CKRecordValue
        record[Field.weeklyRateLbs]    = snapshot.weeklyRateLbs as CKRecordValue
        record[Field.caloriesEaten]    = snapshot.caloriesEaten as CKRecordValue
        record[Field.calorieTarget]    = snapshot.calorieTarget as CKRecordValue
        record[Field.proteinEaten]     = snapshot.proteinEaten as CKRecordValue
        record[Field.proteinTarget]    = snapshot.proteinTarget as CKRecordValue
        record[Field.todayFoods]       = snapshot.todayFoods as CKRecordValue

        do {
            _ = try await database.save(record)
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    func fetchBuddySnapshot() async throws -> BuddySnapshotPayload? {
        try await ensureAvailable()
        await resolveBuddyIfNeeded()   // owner side: discover a buddy who claimed my code
        await ensureNudgeSubscription() // one-time: push me a notification when a nudge arrives
        guard let buddyUserID else { throw BuddySyncError.notLinked }

        let recordID = CKRecord.ID(recordName: "snapshot-\(buddyUserID)")
        do {
            let record = try await database.record(for: recordID)
            return Self.snapshot(from: record)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // Buddy simply hasn't published yet — that's a `nil`, not a failure.
            return nil
        } catch {
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    #if DEBUG
    // MARK: - Dev-only schema seeder

    /// DEV-ONLY one-tap schema seeder. Writes one record of **every** buddy record type —
    /// carrying **every field the app ever sets** — into the **Development** CloudKit schema,
    /// so all types + fields auto-register. This lets you add the two `Nudge` indexes and
    /// **Deploy Schema Changes → Production** without first needing a live two-device pairing.
    ///
    /// Why this is necessary: CloudKit auto-creates schema on write in *Development* only —
    /// **never** in Production. Production schema arrives solely via a deploy, and a deploy can
    /// only carry fields that already exist in Development. So every field the app writes in
    /// *any* flow must be seeded here, or that write later fails in Production. In particular
    /// `BuddyPairing.buddyUserID` is only written when a buddy *claims* a code — solo use never
    /// writes it, so without this seeder the real claim/save would fail in Production.
    ///
    /// Only the **schema** (types/fields/indexes) deploys to Production — never the records —
    /// so these dummy Development rows need no cleanup and can never reach Production.
    ///
    /// Keep the field list in sync with `publish(mySnapshot:)` / `sendNudge` / `link`.
    func debugSeedSchema() async throws {
        try await ensureAvailable()

        // 1) BuddyPairing — pairingCode + ownerUserID (announce) AND buddyUserID (claim path).
        let pairing = CKRecord(recordType: RecordType.pairing,
                               recordID: CKRecord.ID(recordName: "pairing-SEEDSEED"))
        pairing[Field.pairingCode] = "SEEDSEED" as CKRecordValue
        pairing[Field.ownerUserID] = "seed-owner" as CKRecordValue
        pairing[Field.buddyUserID] = "seed-buddy" as CKRecordValue
        _ = try await database.save(pairing)

        // 2) BuddySnapshot — every field publish(mySnapshot:) writes (typed dummies; the
        //    field TYPE is fixed by this first write, so types must match the real writes).
        let snap = CKRecord(recordType: RecordType.snapshot,
                            recordID: CKRecord.ID(recordName: "snapshot-seed-owner"))
        snap[Field.ownerUserID]      = "seed-owner" as CKRecordValue
        snap[Field.displayName]      = "Seed" as CKRecordValue
        snap[Field.dayStreak]        = 0 as CKRecordValue
        snap[Field.characterMoodRaw] = BuddyCharacterMood.happy.rawValue as CKRecordValue
        snap[Field.loggedToday]      = 0 as CKRecordValue
        snap[Field.lastActive]       = Date(timeIntervalSince1970: 0) as CKRecordValue
        snap[Field.stepsToday]       = 0 as CKRecordValue
        snap[Field.stepGoal]         = 0 as CKRecordValue
        snap[Field.waterToday]       = 0.0 as CKRecordValue
        snap[Field.waterGoal]        = 0.0 as CKRecordValue
        snap[Field.workedOutToday]   = 0 as CKRecordValue
        snap[Field.sharesFullData]   = 0 as CKRecordValue
        snap[Field.trendWeightLbs]   = 0.0 as CKRecordValue
        snap[Field.goalWeightLbs]    = 0.0 as CKRecordValue
        snap[Field.weeklyRateLbs]    = 0.0 as CKRecordValue
        snap[Field.caloriesEaten]    = 0.0 as CKRecordValue
        snap[Field.calorieTarget]    = 0.0 as CKRecordValue
        snap[Field.proteinEaten]     = 0.0 as CKRecordValue
        snap[Field.proteinTarget]    = 0.0 as CKRecordValue
        snap[Field.todayFoods]       = "" as CKRecordValue
        _ = try await database.save(snap)

        // 3) Nudge — the only type needing Dashboard indexes (toUserID Queryable,
        //    createdAt Sortable). Seed all six fields.
        let nudge = CKRecord(recordType: RecordType.nudge,
                             recordID: CKRecord.ID(recordName: "nudge-seed"))
        nudge[Field.fromUserID] = "seed-owner" as CKRecordValue
        nudge[Field.toUserID]   = "seed-buddy" as CKRecordValue
        nudge[Field.kindRaw]    = NudgeKind.cheer.rawValue as CKRecordValue
        nudge[Field.text]       = "seed" as CKRecordValue
        nudge[Field.createdAt]  = Date(timeIntervalSince1970: 0) as CKRecordValue
        nudge[Field.isRead]     = 0 as CKRecordValue
        _ = try await database.save(nudge)
    }

    /// DEV-ONLY CloudKit diagnostic for Settings → "Diagnose CloudKit". Reports the iCloud
    /// account status and attempts a REAL public-DB write + read on this device, surfacing the
    /// EXACT CloudKit error — which the live buddy flow otherwise hides behind a soft
    /// `.cloudKitUnavailable`. `accountStatus` is environment-independent, so a failure here
    /// points at the iCloud account/entitlement regardless of Dev vs Production.
    func debugDiagnose() async -> String {
        var out = "Container:\n\(Self.containerIdentifier)\n\n"

        // 1) iCloud account status — the same gate `ensureAvailable()` checks first.
        do {
            let status = try await container.accountStatus()
            let label: String
            switch status {
            case .available:              label = "✅ available"
            case .noAccount:              label = "❌ NO iCloud account signed in"
            case .restricted:             label = "❌ restricted (parental/MDM)"
            case .couldNotDetermine:      label = "⚠️ could not determine"
            case .temporarilyUnavailable: label = "⚠️ temporarily unavailable"
            @unknown default:             label = "⚠️ unknown (\(status.rawValue))"
            }
            out += "iCloud account: \(label)\n"
            if status != .available {
                out += "\n→ THIS is the blocker. Settings → tap your name → make sure you're "
                     + "signed into iCloud (and iCloud Drive is on), then retry."
                return out
            }
        } catch {
            out += "iCloud account check threw: \(Self.errLine(error))\n"
                 + "→ Likely an entitlement/provisioning issue with the iCloud capability."
            return out
        }

        // 2) Real public-DB write — exactly what publishing a pairing code does.
        let id = CKRecord.ID(recordName: "diag-\(myUserID)")
        let rec = CKRecord(recordType: RecordType.pairing, recordID: id)
        rec[Field.pairingCode] = "DIAG" as CKRecordValue
        rec[Field.ownerUserID] = myUserID as CKRecordValue
        do {
            _ = try await database.save(rec)
            out += "Public DB write: ✅ OK\n"
        } catch {
            out += "Public DB WRITE: ❌ \(Self.errLine(error))\n"
                 + "→ This is why pairing fails — your code can't be published."
            return out
        }

        // 3) Read it back — exactly what claiming a buddy's code does.
        do {
            _ = try await database.record(for: id)
            out += "Public DB read: ✅ OK\n"
        } catch {
            out += "Public DB READ: ❌ \(Self.errLine(error))\n"
                 + "→ Writing works but reading a code doesn't."
            return out
        }

        out += "\n✅ Account + read/write all work on THIS device/environment.\n"
             + "If TestFlight pairing still fails, it's Production-specific — check CloudKit "
             + "Dashboard → Production → Security Roles."
        return out
    }

    /// Compact one-line description of a (possibly CloudKit) error, for diagnostics.
    private static func errLine(_ error: Error) -> String {
        if let ck = error as? CKError {
            return "CKError \(ck.errorCode) (\(ck.code)) — \(ck.localizedDescription)"
        }
        return error.localizedDescription
    }
    #endif

    // MARK: - Record <-> model mapping

    /// Decode a `Nudge` CKRecord into the `Sendable` `NudgeWire` (NOT the @Model). The
    /// caller turns this into a `Nudge` on the main actor. Returns `nil` if the record is
    /// missing required fields. `nonisolated` + pure: it only reads `Sendable` scalars off
    /// the record, so it's safe to run inside the async region.
    private nonisolated static func nudgeWire(from record: CKRecord) -> NudgeWire? {
        guard let from = record[Field.fromUserID] as? String,
              let to   = record[Field.toUserID] as? String else { return nil }
        let kindRaw = record[Field.kindRaw] as? String ?? NudgeKind.cheer.rawValue
        let text    = record[Field.text] as? String ?? ""
        let created = record[Field.createdAt] as? Date ?? .now
        let isRead  = (record[Field.isRead] as? Int ?? 0) == 1
        let id      = UUID(uuidString: record.recordID.recordName) ?? UUID()
        return NudgeWire(id: id,
                         fromUserID: from,
                         toUserID: to,
                         kindRaw: kindRaw,
                         text: text,
                         createdAt: created,
                         isRead: isRead)
    }

    private static func snapshot(from record: CKRecord) -> BuddySnapshotPayload? {
        guard let owner = record[Field.ownerUserID] as? String,
              let name  = record[Field.displayName] as? String else { return nil }
        let streak  = record[Field.dayStreak] as? Int ?? 0
        let moodRaw = record[Field.characterMoodRaw] as? String ?? BuddyCharacterMood.happy.rawValue
        let logged  = (record[Field.loggedToday] as? Int ?? 0) == 1
        let active  = record[Field.lastActive] as? Date ?? .now
        // Safe daily activity (absent on older records → 0/false, which the face-off
        // handles gracefully). `workedOutToday` decodes Bool-as-Int like `loggedToday`.
        let steps   = record[Field.stepsToday] as? Int ?? 0
        let stepGl  = record[Field.stepGoal] as? Int ?? 0
        let water   = record[Field.waterToday] as? Double ?? 0
        let waterGl = record[Field.waterGoal] as? Double ?? 0
        let workout = (record[Field.workedOutToday] as? Int ?? 0) == 1
        // FULL shared data (OPT-IN: weight / calories / food). Absent on older records →
        // 0/false/"" (the display card self-hides when `sharesFullData` is false).
        // `sharesFullData` decodes Bool-as-Int like `loggedToday`.
        let sharesFull = (record[Field.sharesFullData] as? Int ?? 0) == 1
        let trendWt    = record[Field.trendWeightLbs] as? Double ?? 0
        let goalWt     = record[Field.goalWeightLbs] as? Double ?? 0
        let weeklyRate = record[Field.weeklyRateLbs] as? Double ?? 0   // signed
        let calEaten   = record[Field.caloriesEaten] as? Double ?? 0
        let calTarget  = record[Field.calorieTarget] as? Double ?? 0
        let protEaten  = record[Field.proteinEaten] as? Double ?? 0
        let protTarget = record[Field.proteinTarget] as? Double ?? 0
        let foods      = record[Field.todayFoods] as? String ?? ""
        return BuddySnapshotPayload(ownerUserID: owner,
                                    displayName: name,
                                    dayStreak: streak,
                                    characterMood: BuddyCharacterMood(rawValue: moodRaw) ?? .happy,
                                    loggedToday: logged,
                                    lastActive: active,
                                    stepsToday: steps,
                                    stepGoal: stepGl,
                                    waterToday: water,
                                    waterGoal: waterGl,
                                    workedOutToday: workout,
                                    sharesFullData: sharesFull,
                                    trendWeightLbs: trendWt,
                                    goalWeightLbs: goalWt,
                                    weeklyRateLbs: weeklyRate,
                                    caloriesEaten: calEaten,
                                    calorieTarget: calTarget,
                                    proteinEaten: protEaten,
                                    proteinTarget: protTarget,
                                    todayFoods: foods)
    }
}
