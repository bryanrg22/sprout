import Foundation

// The pairing handshake, separated from where its records live.
//
// Two people pair through one record, named after a short code: the person who SHOWS the
// code owns the record, the person who TYPES it claims it. `BuddyPairingEngine` holds every
// decision of that handshake; `BuddyPairingStore` is the only part that differs between
// CloudKit (`CloudKitPairingStore`), the simulator (`InMemoryPairingStore`) and a test.
// The sequence, each failure and what the user sees are written down in `docs/buddy-sync.md`.

/// A pairing code: "VITA-" and four characters from an alphabet without 0/O/1/I/L.
enum BuddyPairingCode {
    static let prefix = "VITA-"
    static let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    static let suffixLength = 4

    /// What the user typed, as the record is named: trimmed and upper-cased.
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Whether `code` (already normalized) could have been minted by `make()`. A code that
    /// fails this was mistyped, and no backend needs to be asked.
    static func isWellFormed(_ code: String) -> Bool {
        guard code.hasPrefix(prefix) else { return false }
        let suffix = code.dropFirst(prefix.count)
        return suffix.count == suffixLength && suffix.allSatisfy { alphabet.contains($0) }
    }

    static func make() -> String {
        let letters = Array(alphabet)
        return prefix + String((0..<suffixLength).map { _ in letters.randomElement()! })
    }
}

/// The pairing record as the handshake reads and writes it.
struct BuddyPairingRecord: Equatable, Sendable {
    var code: String
    var ownerUserID: String
    /// Who typed the code. `nil` while nobody has.
    var claimantUserID: String?

    init(code: String, ownerUserID: String, claimantUserID: String? = nil) {
        self.code = code
        self.ownerUserID = ownerUserID
        self.claimantUserID = (claimantUserID?.isEmpty == false) ? claimantUserID : nil
    }
}

/// What a store reports besides "could not be reached" (which it throws as a `BuddySyncError`).
enum BuddyPairingStoreError: Error, Equatable {
    /// `create` found a record already under that code.
    case alreadyExists
    /// `update` found the record changed (or gone) since this store last fetched it.
    case changedSinceFetch
}

/// Where pairing records live.
@MainActor
protocol BuddyPairingStore: AnyObject {
    /// The record under `code`, or `nil` when there is none.
    func fetch(code: String) async throws -> BuddyPairingRecord?
    /// Write a record that must not exist yet. Throws `.alreadyExists` when it does.
    func create(_ record: BuddyPairingRecord) async throws
    /// Overwrite the record this store last fetched under `record.code`. Throws
    /// `.changedSinceFetch` when someone else wrote it in between.
    func update(_ record: BuddyPairingRecord) async throws
    /// Remove the record under `code`. Removing one that is not there is not an error.
    func delete(code: String) async throws
}

/// What this device remembers about its pairing, in `UserDefaults`.
///
/// The buddy id stays under the key earlier builds used, so a pairing made before this
/// file existed is still read. `via` (which code, and which side this device was) is only
/// known for pairings made since; an older pairing has none.
struct BuddyLinkStorage: Sendable {
    enum Role: String, Sendable { case owner, claimant }
    struct Via: Equatable, Sendable {
        var code: String
        var role: Role
    }

    let myUserID: String
    /// Key prefix: "buddy.ck" for CloudKit, "buddy.mock" for the simulator's stand-in.
    let namespace: String
    // `UserDefaults` is documented thread-safe; the struct only ever reads and writes it.
    nonisolated(unsafe) let defaults: UserDefaults

    init(myUserID: String, namespace: String = "buddy.ck", defaults: UserDefaults = .standard) {
        self.myUserID = myUserID
        self.namespace = namespace
        self.defaults = defaults
    }

    private var buddyKey: String { "\(namespace).linkedTo.\(myUserID)" }
    private var viaCodeKey: String { "\(namespace).linkedVia.code.\(myUserID)" }
    private var viaRoleKey: String { "\(namespace).linkedVia.role.\(myUserID)" }
    /// Written by `BuddyViewModel.resolveMyPairingCode`; read here so the service knows
    /// which code is this user's own.
    private var myCodeKey: String { "buddy.myPairingCode.\(myUserID)" }

    var buddyUserID: String? {
        let id = defaults.string(forKey: buddyKey)
        return (id?.isEmpty == false) ? id : nil
    }

    var via: Via? {
        guard let code = defaults.string(forKey: viaCodeKey), !code.isEmpty,
              let role = defaults.string(forKey: viaRoleKey).flatMap(Role.init(rawValue:)) else { return nil }
        return Via(code: code, role: role)
    }

    var myCode: String? {
        let code = defaults.string(forKey: myCodeKey).map(BuddyPairingCode.normalize)
        return (code?.isEmpty == false) ? code : nil
    }

    func setLinked(buddyUserID: String, via: Via?) {
        defaults.set(buddyUserID, forKey: buddyKey)
        if let via {
            defaults.set(via.code, forKey: viaCodeKey)
            defaults.set(via.role.rawValue, forKey: viaRoleKey)
        } else {
            defaults.removeObject(forKey: viaCodeKey)
            defaults.removeObject(forKey: viaRoleKey)
        }
    }

    func clear() {
        defaults.removeObject(forKey: buddyKey)
        defaults.removeObject(forKey: viaCodeKey)
        defaults.removeObject(forKey: viaRoleKey)
    }

    /// Forget my pairing code, so the next time it is asked for a new one is minted
    /// (`BuddyViewModel.resolveMyPairingCode`). The code an ex-buddy holds stops being mine.
    func retireMyCode() {
        defaults.removeObject(forKey: myCodeKey)
    }
}

/// The handshake. One per `BuddySyncService` instance; holds no pairing state of its own —
/// the link is read from `storage` every time, so two instances for the same user agree.
///
/// The rules, each with a test in `BuddyPairingTests`:
/// - Only the owner of a code creates its record. Typing a code never creates anything.
/// - A code connects only when its record exists, belongs to someone else, and is unclaimed
///   (or already claimed by me).
/// - The device is told it is linked only after the claim is saved.
/// - Unpairing forgets the link on this device first, then tells the backend if it can.
@MainActor
final class BuddyPairingEngine {
    let myUserID: String
    private let store: any BuddyPairingStore
    let storage: BuddyLinkStorage

    init(myUserID: String, store: any BuddyPairingStore, storage: BuddyLinkStorage) {
        self.myUserID = myUserID
        self.store = store
        self.storage = storage
    }

    var linkedBuddyID: String? { storage.buddyUserID }

    // MARK: Owner side

    /// Put my code where a buddy who types it will find it; if someone already typed it,
    /// learn who.
    /// - Throws: `.pairingCodeTaken` when the record under my code belongs to someone else
    ///   (two users minted the same code, or a record left by a build that let the typer
    ///   create one). The caller mints a new code and announces that.
    func announce(code raw: String) async throws {
        let code = BuddyPairingCode.normalize(raw)
        guard !code.isEmpty else { throw BuddySyncError.malformedPairingCode }
        if let existing = try await store.fetch(code: code) {
            guard existing.ownerUserID == myUserID else { throw BuddySyncError.pairingCodeTaken }
            adoptClaimant(of: existing)
            return
        }
        do {
            try await store.create(BuddyPairingRecord(code: code, ownerUserID: myUserID))
        } catch BuddyPairingStoreError.alreadyExists {
            // Someone created it between my read and my write. Mine, from another launch?
            guard let now = try await store.fetch(code: code), now.ownerUserID == myUserID else {
                throw BuddySyncError.pairingCodeTaken
            }
            adoptClaimant(of: now)
        }
    }

    /// Has someone typed my code since I last looked? Quiet: a failed read changes nothing.
    func resolveClaimant() async {
        guard storage.buddyUserID == nil, let code = storage.myCode else { return }
        if let record = try? await store.fetch(code: code), record.ownerUserID == myUserID {
            adoptClaimant(of: record)
        }
    }

    /// The owner is linked by being claimed: a claimant on my own record is my buddy.
    private func adoptClaimant(of record: BuddyPairingRecord) {
        guard storage.buddyUserID == nil,
              let claimant = record.claimantUserID, claimant != myUserID else { return }
        storage.setLinked(buddyUserID: claimant, via: .init(code: record.code, role: .owner))
    }

    // MARK: Typer side

    /// Connect to whoever shared `code`. Returns only once the claim is saved.
    func claim(code raw: String) async throws {
        let code = BuddyPairingCode.normalize(raw)
        guard BuddyPairingCode.isWellFormed(code) else { throw BuddySyncError.malformedPairingCode }
        try await claim(code, mayRetry: true)
    }

    private func claim(_ code: String, mayRetry: Bool) async throws {
        let found = try await store.fetch(code: code)

        if code == storage.myCode || found?.ownerUserID == myUserID {
            // My own code. If my buddy already typed it, that is a real pairing and I adopt
            // it; otherwise there is nobody on the other end.
            if let found, found.ownerUserID == myUserID { adoptClaimant(of: found) }
            if let buddy = storage.buddyUserID, buddy == found?.claimantUserID { return }
            throw BuddySyncError.ownPairingCode
        }
        guard var record = found, !record.ownerUserID.isEmpty else {
            // Nothing under that code. The owner's phone creates the record, never the typer's:
            // creating it here is what used to answer a typo with "You're connected!".
            throw BuddySyncError.invalidPairingCode
        }
        if let claimant = record.claimantUserID {
            guard claimant == myUserID else { throw BuddySyncError.pairingCodeAlreadyClaimed }
            // I hold this claim already (typed twice, or the device lost the link): no write.
            storage.setLinked(buddyUserID: record.ownerUserID, via: .init(code: code, role: .claimant))
            return
        }

        record.claimantUserID = myUserID
        do {
            try await store.update(record)
        } catch BuddyPairingStoreError.changedSinceFetch {
            // Someone wrote the record after I read it. Read again: it may be claimed now.
            guard mayRetry else { throw BuddySyncError.cloudKitUnavailable }
            try await claim(code, mayRetry: false)
            return
        }
        // Only now, with the claim saved, does this device consider itself linked.
        storage.setLinked(buddyUserID: record.ownerUserID, via: .init(code: code, role: .claimant))
    }

    // MARK: Both sides

    /// Does the pairing record still name the two of us? If it was read and does not, the
    /// buddy ended the pairing: the link is cleared and `.unpairedByBuddy` is thrown.
    ///
    /// Only a pairing whose record is known (`storage.via`) can be checked; one made by an
    /// earlier build is left alone. A read that fails proves nothing and changes nothing.
    func verifyLink() async throws {
        guard let buddy = storage.buddyUserID, let via = storage.via else { return }
        let record: BuddyPairingRecord?
        do { record = try await store.fetch(code: via.code) } catch { return }
        let stillPaired: Bool
        switch via.role {
        case .owner:
            stillPaired = record?.ownerUserID == myUserID && record?.claimantUserID == buddy
        case .claimant:
            stillPaired = record?.ownerUserID == buddy && record?.claimantUserID == myUserID
        }
        guard !stillPaired else { return }
        storage.clear()
        throw BuddySyncError.unpairedByBuddy
    }

    /// End the pairing. Returns who the buddy was, or nil when there was none.
    ///
    /// This device forgets the link first. Then, best-effort: my claim comes off the buddy's
    /// record (when I was the one who typed), and my own code is retired: its record is
    /// removed and the code forgotten, so the code that was shared stops working. Either
    /// write is how the other side finds out (`verifyLink`); if neither goes through, the
    /// other side keeps a link that will show as stale.
    ///
    /// One exception keeps my code: someone OTHER than the buddy I am leaving has typed it
    /// and is waiting. That is the buddy who reinstalled, came back under a new id and
    /// typed my code while my phone was still linked to their old one. Their claim stands,
    /// and I am paired with them the next time I look (`resolveClaimant`).
    @discardableResult
    func unlink() async -> String? {
        guard let buddy = storage.buddyUserID else { return nil }
        let via = storage.via
        let myCode = storage.myCode
        storage.clear()

        if let via, via.role == .claimant,
           var record = try? await store.fetch(code: via.code),
           record.ownerUserID == buddy, record.claimantUserID == myUserID {
            record.claimantUserID = nil
            try? await store.update(record)
        }

        var someoneIsWaiting = false
        if let myCode,
           let mine = try? await store.fetch(code: myCode), mine.ownerUserID == myUserID {
            if let waiting = mine.claimantUserID, waiting != buddy, waiting != myUserID {
                someoneIsWaiting = true
            } else {
                try? await store.delete(code: myCode)
            }
        }
        if !someoneIsWaiting { storage.retireMyCode() }
        return buddy
    }
}

/// Pairing records in memory: the simulator's stand-in backend, and the base of the test
/// doubles. Each "phone" gets its own store over one shared `Backend`, and remembers the
/// version of what it last fetched, so a write that lost a race is refused the way
/// CloudKit refuses a save whose change tag is out of date.
@MainActor
final class InMemoryPairingStore: BuddyPairingStore {
    @MainActor
    final class Backend {
        fileprivate var records: [String: (record: BuddyPairingRecord, version: Int)] = [:]
        fileprivate var nextVersion = 1
        init() {}

        /// Put a record in place directly, as another device would have.
        func seed(_ record: BuddyPairingRecord) {
            records[record.code] = (record, nextVersion)
            nextVersion += 1
        }

        func record(code: String) -> BuddyPairingRecord? { records[code]?.record }
        var allRecords: [BuddyPairingRecord] { records.values.map(\.record) }
    }

    let backend: Backend
    private var fetchedVersion: [String: Int] = [:]

    init(backend: Backend? = nil) {
        self.backend = backend ?? Backend()
    }

    func fetch(code: String) async throws -> BuddyPairingRecord? {
        guard let entry = backend.records[code] else {
            fetchedVersion[code] = nil
            return nil
        }
        fetchedVersion[code] = entry.version
        return entry.record
    }

    func create(_ record: BuddyPairingRecord) async throws {
        guard backend.records[record.code] == nil else { throw BuddyPairingStoreError.alreadyExists }
        backend.seed(record)
    }

    func update(_ record: BuddyPairingRecord) async throws {
        guard let current = backend.records[record.code],
              fetchedVersion[record.code] == current.version else {
            throw BuddyPairingStoreError.changedSinceFetch
        }
        backend.seed(record)
    }

    func delete(code: String) async throws {
        backend.records[code] = nil
        fetchedVersion[code] = nil
    }
}
