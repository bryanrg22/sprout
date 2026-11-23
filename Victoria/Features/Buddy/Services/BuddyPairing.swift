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
}

/// The handshake. One per `BuddySyncService` instance; holds no pairing state of its own —
/// the link is read from `storage` every time, so two instances for the same user agree.
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

    /// Owner side: put my code where a buddy who types it will find it, and if someone
    /// already claimed it, learn who.
    func announce(code raw: String) async throws {
        let code = BuddyPairingCode.normalize(raw)
        guard !code.isEmpty else { throw BuddySyncError.invalidPairingCode }
        if let existing = try await store.fetch(code: code) {
            if existing.ownerUserID == myUserID, let claimant = existing.claimantUserID {
                storage.setLinked(buddyUserID: claimant, via: nil)
            }
        } else {
            try await store.create(BuddyPairingRecord(code: code, ownerUserID: myUserID))
        }
    }

    /// Owner side: has someone typed my code since I last looked?
    func resolveClaimant() async {
        guard storage.buddyUserID == nil, let code = storage.myCode else { return }
        if let record = try? await store.fetch(code: code),
           let claimant = record.claimantUserID, claimant != myUserID {
            storage.setLinked(buddyUserID: claimant, via: nil)
        }
    }

    /// Typer side: connect to whoever shared `code`.
    func claim(code raw: String) async throws {
        let code = BuddyPairingCode.normalize(raw)
        guard !code.isEmpty else { throw BuddySyncError.invalidPairingCode }

        guard var record = try await store.fetch(code: code) else {
            // Nobody has published this code: publish myself as its owner and wait.
            storage.clear()
            try await store.create(BuddyPairingRecord(code: code, ownerUserID: myUserID))
            return
        }
        if record.ownerUserID == myUserID {
            if let claimant = record.claimantUserID, claimant != myUserID {
                storage.setLinked(buddyUserID: claimant, via: nil)
            }
            return
        }
        record.claimantUserID = myUserID
        storage.setLinked(buddyUserID: record.ownerUserID, via: nil)
        try await store.update(record)
    }

    /// Forget the pairing on this device. Returns who the buddy was.
    @discardableResult
    func unlink() async -> String? {
        let old = storage.buddyUserID
        storage.clear()
        return old
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
