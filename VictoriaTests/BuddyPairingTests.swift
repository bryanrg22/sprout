import XCTest
@testable import Victoria

/// Pairing, from the view model down through the handshake (`BuddyPairingEngine`) to a
/// fake server in this process. Two phones, "Alex" and "Sam"; nothing leaves the process.
///
/// What is pinned: a code connects only when it resolves to another user's pairing record
/// (D-V2); the link is written to the device only after the claim was saved (D-V3); and a
/// pairing can be ended from either side, with the other side finding out (D-V4).
@MainActor
final class BuddyPairingTests: XCTestCase {

    private var world: BuddyTestWorld!
    private let alexID = BuddyTestWorld.alexID
    private let samID = BuddyTestWorld.samID
    private let connected = "You're connected! 💚"

    override func setUp() async throws {
        world = BuddyTestWorld()
    }

    override func tearDown() async throws {
        world.tearDown()
        world = nil
    }

    /// What a fresh service instance on that phone reads back: the persisted link.
    private func persistedBuddy(_ userID: String, _ defaults: UserDefaults) -> String? {
        world.service(userID, defaults: defaults).linkedBuddyID
    }

    /// A well-formed code that is neither of the two given.
    private func otherCode(than taken: [String]) -> String {
        ["VITA-2222", "VITA-3333", "VITA-4444"].first { !taken.contains($0) }!
    }

    // MARK: - D-V2: a code connects only when it is another user's

    func testTheRightCodeConnectsBothSides() async {
        let alexPhone = world.makeDefaults(), samPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: samPhone)
        await sam.announceMyCode()

        await alex.link(usingCode: sam.myPairingCode)

        XCTAssertTrue(alex.isLinked)
        XCTAssertEqual(alex.banner?.text, connected)
        XCTAssertNil(alex.linkError)
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), samID)
        XCTAssertEqual(world.backend.pairing.record(code: sam.myPairingCode)?.claimantUserID, alexID)

        await sam.refresh()
        XCTAssertTrue(sam.isLinked, "the owner learns who typed the code")
        XCTAssertEqual(persistedBuddy(samID, samPhone), alexID)
    }

    func testACodeIsAcceptedInLowerCaseWithSpacesAround() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()

        await alex.link(usingCode: "  \(sam.myPairingCode.lowercased())\n")

        XCTAssertTrue(alex.isLinked)
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), samID)
    }

    func testAMistypedCodeDoesNotConnect() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        await alex.announceMyCode()
        let wrong = otherCode(than: [sam.myPairingCode, alex.myPairingCode])

        await alex.link(usingCode: wrong)

        XCTAssertFalse(alex.isLinked, "a code nobody shared must not connect")
        XCTAssertNotEqual(alex.banner?.text, connected)
        XCTAssertNotNil(alex.linkError)
        XCTAssertNil(persistedBuddy(alexID, alexPhone), "nothing is persisted on failure")
        XCTAssertNil(world.backend.pairing.record(code: wrong),
                     "the person who types a code never creates its record")

        // The owner's own record is untouched, and no later poll turns the failure into a link.
        await alex.refresh()
        await sam.refresh()
        XCTAssertFalse(alex.isLinked)
        XCTAssertFalse(sam.isLinked)
        XCTAssertNil(world.backend.pairing.record(code: sam.myPairingCode)?.claimantUserID)
    }

    func testSomethingThatCannotBeACodeIsRefusedWithoutAskingTheServer() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let fetchesBefore = world.backend.pairingFetches
        let writesBefore = world.backend.pairingWrites

        // O, 0, 1, I and L are not in the alphabet; neither is a five-character suffix.
        for typed in ["VITA-10OL", "VITA-ABCDE", "SAM", "VITA-", "VITA 2345"] {
            await alex.link(usingCode: typed)
            XCTAssertFalse(alex.isLinked, typed)
            XCTAssertNotNil(alex.linkError, typed)
        }
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertEqual(world.backend.pairingFetches, fetchesBefore)
        XCTAssertEqual(world.backend.pairingWrites, writesBefore)
    }

    func testMyOwnCodeDoesNotConnect() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)

        // Before my code is uploaded, and after: the answer is the same.
        await alex.link(usingCode: alex.myPairingCode)
        XCTAssertFalse(alex.isLinked)
        let before = alex.linkError

        await alex.announceMyCode()
        await alex.link(usingCode: alex.myPairingCode)
        XCTAssertFalse(alex.isLinked)
        XCTAssertNotEqual(alex.banner?.text, connected)
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertNotNil(alex.linkError)
        XCTAssertEqual(alex.linkError, before)
        XCTAssertNil(world.backend.pairing.record(code: alex.myPairingCode)?.claimantUserID,
                     "I must not become the claimant of my own code")
    }

    func testACodeNotYetUploadedDoesNotConnectAndWorksOnceItIs() async {
        let alexPhone = world.makeDefaults(), samPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: samPhone)   // shows a code, has not uploaded it

        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertFalse(alex.isLinked)
        XCTAssertNotEqual(alex.banner?.text, connected)
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertNil(world.backend.pairing.record(code: sam.myPairingCode),
                     "typing a code early must not take the record its owner is about to create")

        // Sam's phone uploads; nothing stands in its way.
        await sam.announceMyCode()
        XCTAssertEqual(world.backend.pairing.record(code: sam.myPairingCode)?.ownerUserID, samID)

        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertTrue(alex.isLinked)
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), samID)
        await sam.refresh()
        XCTAssertTrue(sam.isLinked)
        XCTAssertEqual(persistedBuddy(samID, samPhone), alexID)
    }

    func testACodeAlreadyClaimedBySomeoneElseDoesNotConnect() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        let third = world.service("user-third", defaults: world.makeDefaults())
        try? await third.link(usingCode: sam.myPairingCode)
        XCTAssertEqual(world.backend.pairing.record(code: sam.myPairingCode)?.claimantUserID, "user-third")

        await alex.link(usingCode: sam.myPairingCode)

        XCTAssertFalse(alex.isLinked)
        XCTAssertNotEqual(alex.banner?.text, connected)
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertEqual(world.backend.pairing.record(code: sam.myPairingCode)?.claimantUserID, "user-third",
                       "a second claim must not replace the first")
    }

    func testEachFailureHasItsOwnMessage() async {
        let alex = world.model(alexID, defaults: world.makeDefaults())
        let sam = world.model(samID, defaults: world.makeDefaults())
        await alex.announceMyCode()

        await alex.link(usingCode: "VITA-10OL")
        let malformed = alex.linkError
        await alex.link(usingCode: alex.myPairingCode)
        let own = alex.linkError
        await alex.link(usingCode: sam.myPairingCode)          // Sam has not uploaded it yet
        let notFound = alex.linkError
        await sam.announceMyCode()
        try? await world.service("user-third", defaults: world.makeDefaults()).link(usingCode: sam.myPairingCode)
        await alex.link(usingCode: sam.myPairingCode)
        let claimed = alex.linkError
        world.backend.unavailable = .cloudKitUnavailable
        await alex.link(usingCode: otherCode(than: [sam.myPairingCode, alex.myPairingCode]))
        let offline = alex.linkError

        let messages = [malformed, own, notFound, claimed, offline]
        XCTAssertFalse(messages.contains(nil), "\(messages)")
        XCTAssertEqual(Set(messages.compactMap { $0 }).count, 5, "\(messages)")
        XCTAssertFalse(alex.isLinked)

        XCTAssertTrue(own?.localizedCaseInsensitiveContains("your own code") == true, own ?? "")
        XCTAssertTrue(claimed?.localizedCaseInsensitiveContains("already") == true, claimed ?? "")
        // A typo in a well-formed code and a code not uploaded yet look the same from here,
        // so the one message has to say both.
        XCTAssertTrue(notFound?.localizedCaseInsensitiveContains("upload") == true, notFound ?? "")
        XCTAssertTrue(notFound?.localizedCaseInsensitiveContains("check") == true, notFound ?? "")
    }

    func testTheSecondOfTwoClaimsThatRaceIsRefused() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        let code = sam.myPairingCode
        let third = world.service("user-third", defaults: world.makeDefaults())

        // Alex's claim has read the record as unclaimed; before it writes, the third
        // user's claim lands.
        world.backend.beforePairingWrite = { try? await third.link(usingCode: code) }
        await alex.link(usingCode: code)

        XCTAssertEqual(world.backend.pairing.record(code: code)?.claimantUserID, "user-third")
        XCTAssertFalse(alex.isLinked)
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertTrue(alex.linkError?.localizedCaseInsensitiveContains("already") == true, alex.linkError ?? "")
    }

    func testTypingACodeTwiceIsHarmless() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()

        await alex.link(usingCode: sam.myPairingCode)
        let writes = world.backend.pairingWrites
        await alex.link(usingCode: sam.myPairingCode)

        XCTAssertTrue(alex.isLinked)
        XCTAssertNil(alex.linkError)
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), samID)
        XCTAssertEqual(world.backend.pairingWrites, writes, "a claim I already hold is not written again")
    }

    // MARK: - D-V3: persist only after the claim was saved

    func testAFailedClaimLeavesTheUserUnpairedAndAbleToRetry() async {
        let alexPhone = world.makeDefaults(), samPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: samPhone)
        await sam.announceMyCode()

        world.backend.failNextPairingWrites = 1
        await alex.link(usingCode: sam.myPairingCode)

        XCTAssertFalse(alex.isLinked)
        XCTAssertNil(persistedBuddy(alexID, alexPhone), "the link is written only after the claim is saved")
        XCTAssertNil(world.backend.pairing.record(code: sam.myPairingCode)?.claimantUserID)
        XCTAssertNotNil(alex.linkError)

        // The next poll must not promote the failed attempt to a link, on either phone.
        await alex.refresh()
        await sam.refresh()
        XCTAssertFalse(alex.isLinked)
        XCTAssertFalse(sam.isLinked)
        XCTAssertNotEqual(alex.banner?.text, "They got your code — you're connected! 💚")

        // A relaunch (a new model over the same phone) comes up unpaired too.
        XCTAssertFalse(world.model(alexID, defaults: alexPhone).isLinked)

        // And the retry goes through.
        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertTrue(alex.isLinked)
        XCTAssertNil(alex.linkError)
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), samID)
        await sam.refresh()
        XCTAssertEqual(persistedBuddy(samID, samPhone), alexID)
    }

    func testNothingIsPersistedWhenTheServerCannotBeReached() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()

        world.backend.unavailable = .cloudKitUnavailable
        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertFalse(alex.isLinked)
        XCTAssertNil(persistedBuddy(alexID, alexPhone))

        world.backend.failNextPairingFetches = 1
        world.backend.unavailable = nil
        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertFalse(alex.isLinked, "a read that failed is not a missing record")
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertNil(world.backend.pairing.record(code: sam.myPairingCode)?.claimantUserID)
    }

    // MARK: - D-V4: a way out, and the other side finds out

    func testUnpairUnlinksThisPhoneAndTheOtherSideFindsOut() async {
        let (alex, sam) = await world.pairedModels()
        XCTAssertTrue(alex.isLinked)
        XCTAssertTrue(sam.isLinked)

        await alex.unpair()   // Alex typed Sam's code: the claimant leaves

        XCTAssertFalse(alex.isLinked)
        XCTAssertNil(alex.buddySnapshot)
        XCTAssertTrue(alex.inbox.isEmpty)

        await sam.refresh()
        XCTAssertFalse(sam.isLinked, "the owner's next refresh reads that the claim is gone")
        XCTAssertNil(sam.buddySnapshot)
        XCTAssertTrue(sam.banner?.text.localizedCaseInsensitiveContains("ended the pairing") == true,
                      sam.banner?.text ?? "no banner")
    }

    /// The contract of `unlink()`, held here against the test double. The CloudKit delete
    /// that implements it (`CloudKitSyncService.unlink`) is not run by any test.
    func testUnpairTakesWhatIPublishedOutOfTheServer() async {
        let (alex, sam) = await world.pairedModels()
        var day = world.quietDay()
        day.sharesFullData = true
        day.trendWeightLbs = 181.4
        day.todayFoods = "Oatmeal"
        await alex.publishIfLinked(day)
        await sam.publishIfLinked(world.quietDay(name: "Sam"))
        XCTAssertEqual(world.backend.snapshot(of: alexID)?.todayFoods, "Oatmeal")

        await alex.unpair()

        XCTAssertNil(world.backend.snapshot(of: alexID), "what I shared was for that buddy; it does not stay published")
        XCTAssertNotNil(world.backend.snapshot(of: samID), "the other user's record is not mine to remove")
    }

    func testUnpairByTheOwnerIsSeenByTheOneWhoTypedTheCode() async {
        let (alex, sam) = await world.pairedModels()

        await sam.unpair()    // Sam showed the code: the owner leaves

        XCTAssertFalse(sam.isLinked)
        await alex.refresh()
        XCTAssertFalse(alex.isLinked)
        XCTAssertTrue(alex.banner?.text.localizedCaseInsensitiveContains("ended the pairing") == true,
                      alex.banner?.text ?? "no banner")
    }

    func testUnpairSurvivesARelaunchOnBothPhones() async {
        let alexPhone = world.makeDefaults(), samPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: samPhone)
        await sam.announceMyCode()
        await alex.link(usingCode: sam.myPairingCode)
        await sam.refresh()

        await alex.unpair()
        await sam.refresh()

        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertNil(persistedBuddy(samID, samPhone))
        XCTAssertFalse(world.model(alexID, defaults: alexPhone).isLinked)
        XCTAssertFalse(world.model(samID, defaults: samPhone).isLinked)
    }

    func testUnpairWithNoConnectionStillUnlinksThisPhone() async {
        let alexPhone = world.makeDefaults(), samPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: samPhone)
        await sam.announceMyCode()
        await alex.link(usingCode: sam.myPairingCode)
        await sam.refresh()

        world.backend.unavailable = .cloudKitUnavailable
        await alex.unpair()

        XCTAssertFalse(alex.isLinked, "leaving must never wait for the network")
        XCTAssertNil(persistedBuddy(alexID, alexPhone))

        // The other side could not be told. It stays linked until it unpairs itself, which
        // is what the stale-buddy state offers (BuddyFreshnessTests).
        world.backend.unavailable = nil
        await sam.refresh()
        XCTAssertTrue(sam.isLinked)
        XCTAssertEqual(persistedBuddy(samID, samPhone), alexID)
    }

    func testAfterUnpairTheOldCodeIsDeadAndANewOnePairsAgain() async {
        let (alex, sam) = await world.pairedModels()
        let oldCode = sam.myPairingCode

        await sam.unpair()
        await alex.refresh()
        XCTAssertFalse(alex.isLinked)

        XCTAssertNotEqual(sam.myPairingCode, oldCode, "unpairing retires the code that was shared")
        XCTAssertNil(world.backend.pairing.record(code: oldCode))
        await alex.link(usingCode: oldCode)
        XCTAssertFalse(alex.isLinked, "the retired code no longer pairs")

        await sam.announceMyCode()
        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertTrue(alex.isLinked)
        await sam.refresh()
        XCTAssertTrue(sam.isLinked)
    }

    func testUnpairWhenNotPairedDoesNothing() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        await alex.announceMyCode()
        let code = alex.myPairingCode

        await alex.unpair()

        XCTAssertFalse(alex.isLinked)
        XCTAssertEqual(alex.myPairingCode, code, "a code nobody used is kept")
        XCTAssertEqual(world.backend.pairing.record(code: code)?.ownerUserID, alexID)
    }

    // MARK: - What surrounds the handshake

    func testACodeThatBelongsToSomeoneElseIsReplacedWhenAnnounced() async {
        // A record under my code that I do not own: two users minted the same code, or it
        // was left by a build in which typing an unknown code created its record.
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let taken = alex.myPairingCode
        world.backend.pairing.seed(BuddyPairingRecord(code: taken, ownerUserID: "user-third"))

        await alex.announceMyCode()

        XCTAssertNotEqual(alex.myPairingCode, taken, "a code I cannot own is no use to share")
        XCTAssertEqual(world.backend.pairing.record(code: alex.myPairingCode)?.ownerUserID, alexID)
        XCTAssertEqual(world.backend.pairing.record(code: taken)?.ownerUserID, "user-third", "the other record is left alone")
        // The new code is the one a relaunch shows.
        XCTAssertEqual(world.model(alexID, defaults: alexPhone).myPairingCode, alex.myPairingCode)

        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.link(usingCode: alex.myPairingCode)
        XCTAssertTrue(sam.isLinked)
    }

    func testAPairingMadeByAnEarlierBuildIsNeverUnlinkedByTheCheck() async {
        // An earlier build stored only the buddy's id: which record the pairing went
        // through is unknown, so there is nothing to check it against and it is left alone.
        let alexPhone = world.makeDefaults()
        BuddyLinkStorage(myUserID: alexID, namespace: "buddy.test", defaults: alexPhone)
            .setLinked(buddyUserID: samID, via: nil)
        let alex = world.model(alexID, defaults: alexPhone)
        XCTAssertTrue(alex.isLinked)

        for _ in 0..<3 { await alex.refresh() }

        XCTAssertTrue(alex.isLinked)
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), samID)

        // It can still be ended from this phone.
        await alex.unpair()
        XCTAssertFalse(alex.isLinked)
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
    }

    func testAFailedReadOfThePairingRecordUnlinksNobody() async {
        let (alex, sam) = await world.pairedModels()

        world.backend.failNextPairingFetches = 4
        await alex.refresh()
        await sam.refresh()

        XCTAssertTrue(alex.isLinked, "not being able to ask is not an answer")
        XCTAssertTrue(sam.isLinked)
    }

    func testSignedOutOfICloudSaysSoAndKeepsSayingSo() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        world.backend.unavailable = .iCloudAccountMissing

        await alex.refresh()                                  // the pairing screen's poll
        XCTAssertTrue(alex.accountProblem?.contains("Sign in to iCloud") == true, alex.accountProblem ?? "nil")

        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertFalse(alex.isLinked)
        XCTAssertNil(persistedBuddy(alexID, alexPhone))
        XCTAssertTrue(alex.linkError?.contains("Sign in to iCloud") == true, alex.linkError ?? "nil")

        // Signed in again: the notice goes and pairing works.
        world.backend.unavailable = nil
        await alex.refresh()
        XCTAssertNil(alex.accountProblem)
        await alex.link(usingCode: sam.myPairingCode)
        XCTAssertTrue(alex.isLinked)
    }

    func testAnOutageIsAnnouncedOnceAndTheNotesOnScreenAreKept() async {
        let (alex, sam) = await world.pairedModels()
        await sam.send(.cheer)
        await alex.refresh()
        XCTAssertEqual(alex.inbox.count, 1)
        var badges: [Int] = []
        alex.setBadge = { badges.append($0) }

        world.backend.unavailable = .cloudKitUnavailable
        alex.banner = nil
        await alex.refresh()
        XCTAssertTrue(alex.banner?.text.contains("Can't reach iCloud") == true, alex.banner?.text ?? "nil")
        XCTAssertEqual(alex.inbox.count, 1, "an unreachable server does not empty the inbox")
        XCTAssertEqual(badges, [], "nor touch the badge")
        XCTAssertTrue(alex.isLinked)

        alex.banner = nil
        await alex.refresh()                                  // the next poll, still offline
        XCTAssertNil(alex.banner, "said once per outage, not every twenty seconds")

        world.backend.unavailable = nil
        await alex.refresh()
        world.backend.unavailable = .cloudKitUnavailable
        await alex.refresh()
        XCTAssertNotNil(alex.banner, "a new outage is announced again")
    }

    // MARK: - The Simulator's stand-in pairs by the same rules

    func testTheSimulatorBuddyPairsOnlyThroughItsOwnCode() async {
        let phone = world.makeDefaults()
        let mock = LocalMockSyncService(myUserID: alexID, defaults: phone, arguments: [])
        let alex = BuddyViewModel(service: mock, myUserID: alexID, defaults: phone, observePushes: false)
        await alex.announceMyCode()

        await alex.link(usingCode: "VITA-9999")
        XCTAssertFalse(alex.isLinked, "the stand-in used to connect on any text at all")
        XCTAssertEqual(alex.linkError, BuddyViewModel.message(for: .invalidPairingCode))

        await alex.link(usingCode: alex.myPairingCode)
        XCTAssertEqual(alex.linkError, BuddyViewModel.message(for: .ownPairingCode))

        await alex.link(usingCode: LocalMockSyncService.claimedCode)
        XCTAssertEqual(alex.linkError, BuddyViewModel.message(for: .pairingCodeAlreadyClaimed))

        await alex.link(usingCode: "sam")
        XCTAssertEqual(alex.linkError, BuddyViewModel.message(for: .malformedPairingCode))
        XCTAssertFalse(alex.isLinked)
        XCTAssertNil(mock.linkedBuddyID)

        await alex.link(usingCode: LocalMockSyncService.buddyCode)
        XCTAssertTrue(alex.isLinked)
        XCTAssertEqual(mock.linkedBuddyID, LocalMockSyncService.buddyUserID)
        XCTAssertEqual(alex.buddySnapshot?.displayName, LocalMockSyncService.buddyDisplayName)

        // A relaunch: a new stand-in over the same phone is still paired, and stays so.
        let relaunched = LocalMockSyncService(myUserID: alexID, defaults: phone, arguments: [])
        let again = BuddyViewModel(service: relaunched, myUserID: alexID, defaults: phone, observePushes: false)
        XCTAssertTrue(again.isLinked)
        await again.refresh()
        XCTAssertTrue(again.isLinked)

        await again.unpair()
        XCTAssertFalse(again.isLinked)
        XCTAssertNil(relaunched.linkedBuddyID)
        XCTAssertFalse(BuddyViewModel(service: LocalMockSyncService(myUserID: alexID, defaults: phone, arguments: []),
                                      myUserID: alexID, defaults: phone, observePushes: false).isLinked)
    }

    func testTheSimulatorDemoStates() async {
        let phone = world.makeDefaults()
        func model(_ arguments: [String]) -> BuddyViewModel {
            BuddyViewModel(service: LocalMockSyncService(myUserID: alexID, defaults: phone, arguments: arguments),
                           myUserID: alexID, defaults: phone, observePushes: false)
        }

        let stale = model(["--demo-buddy-state", "stale"])
        await stale.refresh()
        XCTAssertTrue(stale.isLinked)
        XCTAssertTrue(stale.buddyFreshness.isStale)

        let silent = model(["--demo-buddy-state", "silent"])
        await silent.refresh()
        XCTAssertTrue(silent.isLinked)
        XCTAssertEqual(silent.buddyFreshness, .neverPublished)

        let unpaired = model(["--demo-buddy-state", "unpaired"])
        await unpaired.refresh()
        XCTAssertFalse(unpaired.isLinked)

        let paired = model(["--demo-buddy"])
        await paired.refresh()
        XCTAssertTrue(paired.isLinked)
        XCTAssertFalse(paired.buddyFreshness.isStale)
    }

    // MARK: - L-B11: the partner reinstalled

    func testAfterAReinstallThePartnerSeesStaleNotCurrentAndCanPairAgain() async {
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        await alex.link(usingCode: sam.myPairingCode)
        await sam.refresh()
        await sam.publishIfLinked(world.quietDay(name: "Sam", streak: 4))
        let lastPublish = world.now
        await alex.refresh()
        XCTAssertEqual(alex.buddyFreshness, .current)

        // Sam deletes the app and installs it again: a new id, a new code, no link. The old
        // id never publishes again.
        let reinstalled = world.model("user-sam-reinstalled", defaults: world.makeDefaults())
        await reinstalled.announceMyCode()
        XCTAssertFalse(reinstalled.isLinked)

        world.now = world.calendar.calendar.date(byAdding: .day, value: 9, to: world.now)!
        await alex.refresh()
        XCTAssertTrue(alex.isLinked, "nothing tells Alex's phone; the record still names the old id")
        XCTAssertEqual(alex.buddyFreshness,
                       .stale(since: lastPublish, days: 9),
                       "nine-day-old data is shown as that, not as today's")

        // The way out the screen offers: unpair, then pair with the new code.
        await alex.unpair()
        XCTAssertFalse(alex.isLinked)
        await alex.link(usingCode: reinstalled.myPairingCode)
        XCTAssertTrue(alex.isLinked)
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), "user-sam-reinstalled")
        await reinstalled.refresh()
        XCTAssertTrue(reinstalled.isLinked)
    }

    func testABuddyWhoCameBackAndTypedMyCodeIsWhoIAmPairedWithOnceIUnpair() async {
        // The other arrangement of the same story: this time the reinstalled buddy types
        // MY code while my phone is still linked to their old id.
        let alexPhone = world.makeDefaults()
        let alex = world.model(alexID, defaults: alexPhone)
        await alex.announceMyCode()                      // done while unpaired, as the app does
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        await alex.link(usingCode: sam.myPairingCode)
        await sam.refresh()
        let alexCode = alex.myPairingCode

        let reinstalled = world.model("user-sam-reinstalled", defaults: world.makeDefaults())
        await reinstalled.link(usingCode: alexCode)
        XCTAssertTrue(reinstalled.isLinked, "Alex's own code was never claimed, so it pairs")
        await alex.refresh()
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), samID, "Alex's phone does not switch buddies by itself")

        await alex.unpair()

        XCTAssertTrue(alex.isLinked, "the buddy waiting on my code is who I am paired with now")
        XCTAssertEqual(persistedBuddy(alexID, alexPhone), "user-sam-reinstalled")
        XCTAssertEqual(alex.myPairingCode, alexCode, "a code someone is waiting on is not retired")
        await reinstalled.refresh()
        XCTAssertTrue(reinstalled.isLinked, "and their claim was not thrown away by my unpairing")
    }
}
