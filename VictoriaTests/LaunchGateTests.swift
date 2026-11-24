import XCTest
import SwiftData
import CloudKit
import CoreData
@testable import Victoria

/// A person who already has data is never sent through onboarding again (EVAL_REPORT 27).
@MainActor
final class LaunchGateTests: XCTestCase {

    override func tearDown() {
        StoreStatus.resetForTesting()
        super.tearDown()
    }

    // MARK: - The route

    func testEveryCombinationGoesWhereItShould() {
        for opened in [true, false] {
            for finished in [true, false] {
                for any in [true, false] where !(finished && !any) {   // a finished profile is a profile
                    for settled in [true, false] {
                        let route = LaunchRoute.decide(storeOpened: opened, hasFinishedProfile: finished,
                                                       hasAnyProfile: any, restoreSettled: settled)
                        let expected: LaunchRoute
                        if !opened { expected = .storeUnavailable }
                        else if finished { expected = .main }
                        else if any { expected = .onboarding }
                        else { expected = settled ? .onboarding : .restoringFromICloud }
                        XCTAssertEqual(route, expected, "opened \(opened) finished \(finished) any \(any) settled \(settled)")
                    }
                }
            }
        }
    }

    func testAStoreThatDidNotOpenNeverShowsOnboardingOrTheApp() {
        // The case that started this: the fallback store is empty, so it has no profile.
        XCTAssertEqual(LaunchRoute.decide(storeOpened: false, hasFinishedProfile: false, hasAnyProfile: false,
                                          restoreSettled: true), .storeUnavailable)
        XCTAssertEqual(LaunchRoute.decide(storeOpened: false, hasFinishedProfile: true, hasAnyProfile: true,
                                          restoreSettled: true), .storeUnavailable)
    }

    func testAnOnboardingAlreadyUnderWayIsNotMadeToWaitAgain() {
        XCTAssertEqual(LaunchRoute.decide(storeOpened: true, hasFinishedProfile: false, hasAnyProfile: true,
                                          restoreSettled: false), .onboarding)
    }

    func testTheStoreStatusRecordsAFailureAndItsText() {
        XCTAssertTrue(StoreStatus.opened, "the test host's store opened")
        StoreStatus.recordOpenFailure(UITestHooks.SimulatedStoreFailure())
        XCTAssertFalse(StoreStatus.opened)
        XCTAssertEqual(StoreStatus.openError, "simulated by --ui-test-store-failure")
    }

    // MARK: - Which profile

    private func profile(_ name: String, finished: Bool, created: TimeInterval, start: Double = 150) -> UserProfile {
        let p = UserProfile()
        p.name = name
        p.onboardingComplete = finished
        p.createdAt = Date(timeIntervalSince1970: created)
        p.startWeightLbs = start
        return p
    }

    func testTheRestoredFinishedProfileWinsOverOneMadeByAccident() {
        let restored = profile("Sam", finished: true, created: 1_000)
        let accidental = profile("Sam", finished: true, created: 9_000)
        XCTAssertTrue(UserProfile.primary(of: [accidental, restored]) === restored)
        XCTAssertTrue(UserProfile.primary(of: [restored, accidental]) === restored, "order of the fetch does not matter")
    }

    func testAFinishedProfileWinsOverAnOlderUnfinishedOne() {
        let unfinished = profile("", finished: false, created: 1)
        let finished = profile("Alex", finished: true, created: 5)
        XCTAssertTrue(UserProfile.primary(of: [unfinished, finished]) === finished)
    }

    func testTiesAreBrokenWithoutDependingOnOrder() {
        let a = profile("Alex", finished: true, created: 7)
        let b = profile("Sam", finished: true, created: 7)
        XCTAssertTrue(UserProfile.primary(of: [b, a]) === a)
        XCTAssertTrue(UserProfile.primary(of: [a, b]) === a)
        let lighter = profile("Alex", finished: true, created: 7, start: 140)
        XCTAssertTrue(UserProfile.primary(of: [a, lighter]) === lighter)
        XCTAssertTrue(UserProfile.primary(of: [lighter, a]) === lighter)
    }

    func testNoProfilesIsNoProfileAndOneIsThatOne() {
        XCTAssertNil(UserProfile.primary(of: []))
        let only = profile("Sam", finished: false, created: 3)
        XCTAssertTrue(UserProfile.primary(of: [only]) === only)
    }

    func testTheRuleHoldsForProfilesReadBackFromAStore() throws {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(schema: AppSchema.schema,
                                                                              isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.insert(profile("Sam", finished: true, created: 9_000, start: 170))
        context.insert(profile("Sam", finished: true, created: 1_000, start: 158))
        context.insert(profile("", finished: false, created: 500))
        try context.save()
        let fetched = try ModelContext(container).fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(UserProfile.primary(of: fetched)?.startWeightLbs, 158)
    }

    // MARK: - Waiting for iCloud

    func testNotApplicableIsSettledFromTheStart() {
        let watch = ICloudRestoreWatch(applicable: false)
        XCTAssertTrue(watch.settled)
        XCTAssertEqual(watch.reason, .notApplicable)
        watch.start(accountStatus: { XCTFail("must not ask"); return nil })
    }

    func testNoICloudAccountSettlesAtOnce() async {
        let watch = ICloudRestoreWatch(applicable: true, timeout: .seconds(30), skipAfter: .seconds(30))
        XCTAssertFalse(watch.settled)
        watch.start(accountStatus: { .noAccount })
        await waitUntil { watch.settled }
        XCTAssertEqual(watch.reason, .noAccount)
    }

    func testAnAccountWhoseStatusCannotBeReadDoesNotWaitForNothing() async {
        let watch = ICloudRestoreWatch(applicable: true, timeout: .seconds(30), skipAfter: .seconds(30))
        watch.start(accountStatus: { nil })
        await waitUntil { watch.settled }
        XCTAssertEqual(watch.reason, .noAccount)
    }

    func testWithAnAccountItWaitsThenOffersToSkipThenTimesOut() async {
        let watch = ICloudRestoreWatch(applicable: true, timeout: .milliseconds(600), skipAfter: .milliseconds(150))
        watch.start(accountStatus: { .available })
        XCTAssertFalse(watch.settled)
        XCTAssertFalse(watch.canSkip)
        await waitUntil { watch.canSkip }
        XCTAssertFalse(watch.settled, "skipping is offered before the wait is over")
        await waitUntil { watch.settled }
        XCTAssertEqual(watch.reason, .timedOut)
    }

    func testChoosingToStartEndsTheWaitAndNothingLaterChangesTheReason() async {
        let watch = ICloudRestoreWatch(applicable: true, timeout: .milliseconds(300), skipAfter: .milliseconds(10))
        watch.start(accountStatus: { .available })
        watch.settle(.personChoseToStart)
        try? await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(watch.reason, .personChoseToStart)
    }

    func testANotificationWithoutAnImportEventIsIgnored() async {
        let watch = ICloudRestoreWatch(applicable: true, timeout: .seconds(30), skipAfter: .seconds(30))
        watch.start(accountStatus: { .available })
        NotificationCenter.default.post(name: NSPersistentCloudKitContainer.eventChangedNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(watch.settled)
    }

    func testStartingTwiceStartsOnce() async {
        var asked = 0
        let watch = ICloudRestoreWatch(applicable: true, timeout: .seconds(30), skipAfter: .seconds(30))
        watch.start(accountStatus: { await MainActor.run { asked += 1 }; return .available })
        watch.start(accountStatus: { await MainActor.run { asked += 1 }; return .available })
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(asked, 1)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, seconds: Double = 3) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "timed out")
    }
}
