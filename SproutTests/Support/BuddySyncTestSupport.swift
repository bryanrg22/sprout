import Foundation
import XCTest
@testable import Sprout

// Test doubles for buddy sync. Nothing here reaches CloudKit or the network: the "server"
// is `FakeBuddyBackend`, an object in this process, and each "phone" is a
// `FakeBuddySyncService` over it. Pairing runs through the app's own `BuddyPairingEngine`,
// so what these tests decide about pairing is decided by the code that ships.

/// A door a test opens by hand. Whoever calls `pass()` waits until `open()`; a test waits
/// for someone to arrive with `waitForArrival()`. This is how an ordering between two
/// concurrent calls is made explicit instead of being left to timing.
@MainActor
final class TestGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrivals = 0
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init() {}

    func pass() async {
        arrivals += 1
        let ready = arrivalWaiters.filter { $0.count <= arrivals }
        arrivalWaiters.removeAll { $0.count <= arrivals }
        ready.forEach { $0.continuation.resume() }
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Returns once `count` callers have reached the gate.
    func waitForArrival(count: Int = 1) async {
        if arrivals >= count { return }
        await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
    }

    func open() {
        isOpen = true
        let all = waiting
        waiting = []
        all.forEach { $0.resume() }
    }
}

/// The server both fake phones talk to: pairing records, published snapshots, nudges, and
/// the switches a test uses to make a call fail or wait.
@MainActor
final class FakeBuddyBackend {
    let pairing = InMemoryPairingStore.Backend()
    private(set) var snapshots: [String: BuddySnapshotPayload] = [:]
    private(set) var nudges: [NudgeWire] = []

    /// When set, every call throws it (signed out of iCloud, offline).
    var unavailable: BuddySyncError?

    // Pairing
    var failNextPairingFetches = 0
    var failNextPairingWrites = 0
    /// Runs after a claim has read the record and before it writes: where another phone's
    /// write is placed to make a race real.
    var beforePairingWrite: (() async -> Void)?
    private(set) var pairingWrites = 0
    fileprivate(set) var pairingFetches = 0

    // Snapshots
    var failNextPublishes = 0
    /// When set, a publish waits here before it lands.
    var publishGate: TestGate?
    private(set) var publishCount = 0
    private var publishesInFlight: Set<String> = []
    /// Publishes that arrived while another was still in flight for the same owner, which
    /// CloudKit refuses with a change-tag conflict.
    private(set) var overlappingPublishes = 0

    // Nudges
    var failNextNudgeSends = 0
    private(set) var nudgeSendAttempts = 0

    init() {}

    func snapshot(of userID: String) -> BuddySnapshotPayload? { snapshots[userID] }

    /// Put a snapshot in place directly, as the other phone would have.
    func seedSnapshot(_ payload: BuddySnapshotPayload) { snapshots[payload.ownerUserID] = payload }

    func nudges(to userID: String) -> [NudgeWire] { nudges.filter { $0.toUserID == userID } }

    fileprivate func checkAvailable() throws {
        if let unavailable { throw unavailable }
    }

    fileprivate func publish(_ payload: BuddySnapshotPayload) async throws {
        try checkAvailable()
        let owner = payload.ownerUserID
        if publishesInFlight.contains(owner) {
            overlappingPublishes += 1
            throw BuddySyncError.cloudKitUnavailable
        }
        publishesInFlight.insert(owner)
        defer { publishesInFlight.remove(owner) }
        if let publishGate { await publishGate.pass() }
        if failNextPublishes > 0 {
            failNextPublishes -= 1
            throw BuddySyncError.cloudKitUnavailable
        }
        publishCount += 1
        snapshots[payload.ownerUserID] = payload
    }

    fileprivate func send(_ wire: NudgeWire) throws {
        try checkAvailable()
        nudgeSendAttempts += 1
        if failNextNudgeSends > 0 {
            failNextNudgeSends -= 1
            throw BuddySyncError.cloudKitUnavailable
        }
        nudges.append(wire)
    }

    fileprivate func markRead(_ id: UUID) throws {
        try checkAvailable()
        if let i = nudges.firstIndex(where: { $0.id == id }) { nudges[i].isRead = true }
    }

    fileprivate func noteWrite() { pairingWrites += 1 }

    /// Best-effort, like the delete it stands for: nothing happens while unreachable.
    fileprivate func removeSnapshot(of userID: String) {
        guard unavailable == nil else { return }
        snapshots[userID] = nil
    }
}

/// The in-memory pairing store with a test's switches in front of it.
@MainActor
final class ScriptedPairingStore: BuddyPairingStore {
    private let backend: FakeBuddyBackend
    private let inner: InMemoryPairingStore

    init(backend: FakeBuddyBackend) {
        self.backend = backend
        self.inner = InMemoryPairingStore(backend: backend.pairing)
    }

    func fetch(code: String) async throws -> BuddyPairingRecord? {
        try backend.checkAvailable()
        backend.pairingFetches += 1
        if backend.failNextPairingFetches > 0 {
            backend.failNextPairingFetches -= 1
            throw BuddySyncError.cloudKitUnavailable
        }
        return try await inner.fetch(code: code)
    }

    private func beforeWrite() async throws {
        try backend.checkAvailable()
        if let hook = backend.beforePairingWrite {
            backend.beforePairingWrite = nil   // once: the other phone's write must not recurse
            await hook()
        }
        if backend.failNextPairingWrites > 0 {
            backend.failNextPairingWrites -= 1
            throw BuddySyncError.cloudKitUnavailable
        }
    }

    func create(_ record: BuddyPairingRecord) async throws {
        try await beforeWrite()
        try await inner.create(record)
        backend.noteWrite()
    }

    func update(_ record: BuddyPairingRecord) async throws {
        try await beforeWrite()
        try await inner.update(record)
        backend.noteWrite()
    }

    func delete(code: String) async throws {
        try await beforeWrite()
        try await inner.delete(code: code)
        backend.noteWrite()
    }
}

/// One phone's `BuddySyncService` over the fake server. It behaves the way
/// `CloudKitSyncService` does where the two could differ: `fetchBuddySnapshot` throws
/// `.notLinked` when there is no buddy, and a nudge is addressed by the service.
@MainActor
final class FakeBuddySyncService: BuddySyncService {
    let myUserID: String
    private let backend: FakeBuddyBackend
    private let engine: BuddyPairingEngine
    private let storage: BuddyLinkStorage

    init(myUserID: String, backend: FakeBuddyBackend, defaults: UserDefaults) {
        self.myUserID = myUserID
        self.backend = backend
        let storage = BuddyLinkStorage(myUserID: myUserID, namespace: "buddy.test", defaults: defaults)
        self.storage = storage
        self.engine = BuddyPairingEngine(myUserID: myUserID,
                                         store: ScriptedPairingStore(backend: backend),
                                         storage: storage)
    }

    nonisolated func generatePairingCode() -> String { BuddyPairingCode.make() }

    nonisolated var linkedBuddyID: String? { storage.buddyUserID }

    func publishMyPairingCode(_ code: String) async throws {
        try backend.checkAvailable()
        try await engine.announce(code: code)
    }

    func link(usingCode code: String) async throws {
        try backend.checkAvailable()
        try await engine.claim(code: code)
    }

    func unlink() async throws {
        guard await engine.unlink() != nil else { return }
        backend.removeSnapshot(of: myUserID)
    }

    func sendNudge(_ nudge: Nudge) async throws {
        var wire = NudgeWire(from: nudge)
        guard let buddy = storage.buddyUserID else { throw BuddySyncError.notLinked }
        wire.toUserID = buddy
        wire.fromUserID = myUserID
        try backend.send(wire)
    }

    func fetchInbox() async throws -> [Nudge] {
        try backend.checkAvailable()
        return backend.nudges(to: myUserID)
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.makeModel() }
    }

    func markRead(_ nudgeID: UUID) async throws {
        try backend.markRead(nudgeID)
    }

    func publish(mySnapshot snapshot: BuddySnapshotPayload) async throws {
        try await backend.publish(snapshot.sharesFullData ? snapshot : snapshot.withoutFullData)
    }

    func fetchBuddySnapshot() async throws -> BuddySnapshotPayload? {
        try backend.checkAvailable()
        await engine.resolveClaimant()
        try await engine.verifyLink()
        guard let buddy = storage.buddyUserID else { throw BuddySyncError.notLinked }
        return backend.snapshot(of: buddy)
    }
}

/// Two phones, "Alex" and "Sam", over one fake server, each with its own defaults suite
/// (a phone's `UserDefaults`) and a clock the test moves.
@MainActor
final class BuddyTestWorld {
    let backend = FakeBuddyBackend()
    let calendar = FixedCalendar()
    var now: Date

    static let alexID = "user-alex"
    static let samID = "user-sam"

    private var suites: [String] = []
    /// One publish coordinator per phone, as the app has one per process. Holding the
    /// defaults object keeps its identity from being reused by another phone.
    private var coordinators: [ObjectIdentifier: (defaults: UserDefaults, coordinator: BuddyPublishCoordinator)] = [:]

    func coordinator(for defaults: UserDefaults) -> BuddyPublishCoordinator {
        let key = ObjectIdentifier(defaults)
        if let existing = coordinators[key] { return existing.coordinator }
        let fresh = BuddyPublishCoordinator()
        coordinators[key] = (defaults, fresh)
        return fresh
    }

    init() {
        now = FixedCalendar().at(2026, 11, 20, 9, 0)
    }

    /// A fresh, empty defaults suite: one phone's storage.
    func makeDefaults() -> UserDefaults {
        let name = "buddy-test-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    func tearDown() {
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        suites = []
        coordinators = [:]
    }

    func service(_ userID: String, defaults: UserDefaults) -> FakeBuddySyncService {
        FakeBuddySyncService(myUserID: userID, backend: backend, defaults: defaults)
    }

    /// A view model for one phone. Two models made with the same `defaults` are two models
    /// on the same phone (the hub's and the auto-publisher's): each has its own service
    /// instance and they share the phone's publish coordinator, as in the app.
    func model(_ userID: String, defaults: UserDefaults) -> BuddyViewModel {
        BuddyViewModel(service: service(userID, defaults: defaults),
                       myUserID: userID,
                       defaults: defaults,
                       observePushes: false,
                       now: { [unowned self] in self.now },
                       calendar: calendar.calendar,
                       publishing: coordinator(for: defaults))
    }

    /// Alex and Sam paired the real way: Sam shows a code, Alex types it.
    func pairedModels() async -> (alex: BuddyViewModel, sam: BuddyViewModel) {
        let alex = model(Self.alexID, defaults: makeDefaults())
        let sam = model(Self.samID, defaults: makeDefaults())
        await sam.announceMyCode()
        await alex.link(usingCode: sam.myPairingCode)
        await sam.refresh()
        return (alex, sam)
    }

    /// A day's state with nothing reached, for publishes that should not cheer.
    func quietDay(name: String = "Alex", streak: Int = 0) -> MyBuddyState {
        MyBuddyState(loggedToday: true, dayStreak: streak,
                     stepsToday: 0, stepGoal: 0, waterToday: 0, waterGoal: 0,
                     workedOutToday: false, workoutSummary: "",
                     sharesFullData: false,
                     trendWeightLbs: 0, goalWeightLbs: 0, weeklyRateLbs: 0,
                     caloriesEaten: 0, calorieTarget: 0, proteinEaten: 0, proteinTarget: 0,
                     carbsEaten: 0, carbTarget: 0, fatEaten: 0, fatTarget: 0,
                     todayFoods: "", displayName: name)
    }
}
