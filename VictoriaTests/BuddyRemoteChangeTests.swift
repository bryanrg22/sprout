import XCTest
@testable import Victoria

/// The silent-push path (D-V14): `AppDelegate` hands a remote notification to
/// `BuddyRemoteChangeCenter.deliver` and returns its answer to iOS, which ends the
/// background window. So `deliver` must not return while a refresh is still running, and
/// must return anyway when one never finishes. Ordering is set with gates; no test waits.
@MainActor
final class BuddyRemoteChangeTests: XCTestCase {

    /// A timeout that never fires unless the test opens it.
    private func timeout(_ gate: TestGate) -> @Sendable () async -> Void {
        { await gate.pass() }
    }

    func testDeliverReturnsOnlyAfterTheRefreshFinished() async {
        let center = BuddyRemoteChangeCenter()
        let refresh = TestGate()
        var refreshed = false
        center.addObserver {
            await refresh.pass()       // the fetch from CloudKit, still in flight
            refreshed = true
            return true
        }

        var returned = false
        let delivery = Task { @MainActor () -> BuddyRemoteChangeCenter.Outcome in
            let outcome = await center.deliver(timeout: self.timeout(TestGate()))
            returned = true
            return outcome
        }
        await refresh.waitForArrival()  // the refresh has started and is waiting

        XCTAssertFalse(returned, "returning here tells iOS the work is done before it has run")

        refresh.open()
        let outcome = await delivery.value
        XCTAssertEqual(outcome, .refreshed)
        XCTAssertTrue(refreshed)
    }

    func testDeliverWaitsForEveryObserver() async {
        let center = BuddyRemoteChangeCenter()
        let slow = TestGate()
        var finished: [String] = []
        center.addObserver { finished.append("fast"); return true }
        center.addObserver { await slow.pass(); finished.append("slow"); return true }

        let delivery = Task { @MainActor in await center.deliver(timeout: self.timeout(TestGate())) }
        await slow.waitForArrival()
        slow.open()
        let outcome = await delivery.value

        XCTAssertEqual(outcome, .refreshed)
        XCTAssertEqual(Set(finished), ["fast", "slow"])
    }

    func testDeliverGivesUpWhenTheTimeAllowedRunsOut() async {
        let center = BuddyRemoteChangeCenter()
        let stuck = TestGate()          // a refresh that never comes back
        let clock = TestGate()
        center.addObserver { await stuck.pass(); return true }

        let delivery = Task { @MainActor in await center.deliver(timeout: self.timeout(clock)) }
        await stuck.waitForArrival()
        await clock.waitForArrival()
        clock.open()                    // the time allowed is up
        let outcome = await delivery.value

        XCTAssertEqual(outcome, .timedOut)
        stuck.open()                    // let the abandoned refresh end
    }

    func testDeliverWithNothingShowingBuddyDataSaysSo() async {
        let outcome = await BuddyRemoteChangeCenter().deliver(timeout: timeout(TestGate()))
        XCTAssertEqual(outcome, .noObservers)
    }

    func testAnObserverWhoseOwnerIsGoneIsDropped() async {
        let center = BuddyRemoteChangeCenter()
        center.addObserver { false }
        XCTAssertEqual(center.observerCount, 1)

        _ = await center.deliver(timeout: timeout(TestGate()))

        XCTAssertEqual(center.observerCount, 0)
        let again = await center.deliver(timeout: timeout(TestGate()))
        XCTAssertEqual(again, .noObservers)
    }

    func testALinkedModelRefreshesBeforeDeliverReturns() async {
        let world = BuddyTestWorld()
        defer { world.tearDown() }
        let alexPhone = world.makeDefaults()
        let sam = world.model(BuddyTestWorld.samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        // This model registers with the shared centre, as the hub's does.
        let alex = BuddyViewModel(service: world.service(BuddyTestWorld.alexID, defaults: alexPhone),
                                  myUserID: BuddyTestWorld.alexID, defaults: alexPhone,
                                  observePushes: true, now: { world.now }, calendar: world.calendar.calendar)
        await alex.link(usingCode: sam.myPairingCode)
        await sam.refresh()
        XCTAssertNil(alex.buddySnapshot)

        // Sam logs; CloudKit's silent push arrives on Alex's phone.
        await sam.publishIfLinked(world.quietDay(name: "Sam", streak: 3))
        let outcome = await BuddyRemoteChangeCenter.shared.deliver(timeout: timeout(TestGate()))

        XCTAssertEqual(outcome, .refreshed)
        XCTAssertEqual(alex.buddySnapshot?.dayStreak, 3, "the snapshot is in hand when the handler returns")
    }
}
