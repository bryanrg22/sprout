import XCTest
@testable import Victoria

/// Publishing my day and cheering the buddy, through the view model to a fake server in
/// this process. The clock is the test's (`world.now`); an ordering between two concurrent
/// calls is set with a `TestGate`, never by waiting.
///
/// Pinned: a model that did not do the pairing still publishes after it (D-V9); two models
/// on one phone never publish at once (D-V17); a milestone is sent once and only marked
/// sent after the send succeeded (D-V10/11); a nudge needs a buddy, not a snapshot (D-V18);
/// the pairing poll does not flood the diagnostics log (D-V16); the badge follows the
/// unread count (D-V22).
@MainActor
final class BuddyPublishTests: XCTestCase {

    private var world: BuddyTestWorld!
    private let alexID = BuddyTestWorld.alexID
    private let samID = BuddyTestWorld.samID

    override func setUp() async throws {
        world = BuddyTestWorld()
    }

    override func tearDown() async throws {
        world.tearDown()
        world = nil
    }

    private func nextDay() {
        world.now = world.calendar.calendar.date(byAdding: .day, value: 1, to: world.now)!
    }

    /// Nudges Sam received whose text contains `fragment`.
    private func cheers(_ fragment: String) -> [NudgeWire] {
        world.backend.nudges(to: samID).filter { $0.text.contains(fragment) }
    }

    // MARK: - D-V9: the auto-publisher learns about a new link

    func testAModelThatDidNotDoThePairingPublishesAfterIt() async {
        let phone = world.makeDefaults()
        let hub = world.model(alexID, defaults: phone)          // the Buddy screen's model
        let publisher = world.model(alexID, defaults: phone)    // BuddyAutoPublisher's own
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()

        // Before pairing, a publish trigger uploads nothing.
        await publisher.publishIfLinked(world.quietDay(streak: 2))
        XCTAssertNil(world.backend.snapshot(of: alexID))

        await hub.link(usingCode: sam.myPairingCode)
        XCTAssertTrue(hub.isLinked)

        // The next trigger on the other model, in the same launch.
        await publisher.publishIfLinked(world.quietDay(streak: 5))

        XCTAssertEqual(world.backend.snapshot(of: alexID)?.dayStreak, 5,
                       "logging on another tab right after pairing must reach the buddy")
        XCTAssertTrue(publisher.isLinked)
    }

    func testAModelThatDidNotDoTheUnpairingStopsPublishingAfterIt() async {
        let phone = world.makeDefaults()
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        let hub = world.model(alexID, defaults: phone)
        await hub.link(usingCode: sam.myPairingCode)
        let publisher = world.model(alexID, defaults: phone)
        XCTAssertTrue(publisher.isLinked)
        let before = world.backend.publishCount

        await hub.unpair()
        await publisher.publishIfLinked(world.quietDay(streak: 6))

        XCTAssertEqual(world.backend.publishCount, before, "nothing is published once unpaired")
        XCTAssertFalse(publisher.isLinked)
    }

    func testComingBackToTheAppRepublishesAfterAFailureOrSixHoursAndOnlyWhilePaired() async {
        let phone = world.makeDefaults()
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        let hub = world.model(alexID, defaults: phone)
        let publisher = world.model(alexID, defaults: phone)
        XCTAssertFalse(publisher.needsPublishOnForeground(), "not paired: nothing to publish")

        await hub.link(usingCode: sam.myPairingCode)
        XCTAssertTrue(publisher.needsPublishOnForeground(), "paired by the other model and never published")

        await publisher.publishIfLinked(world.quietDay())
        XCTAssertFalse(publisher.needsPublishOnForeground())
        world.now += 6 * 3600 + 1
        XCTAssertTrue(publisher.needsPublishOnForeground(), "six hours on, the buddy is looking at an earlier me")

        await publisher.publishIfLinked(world.quietDay())
        world.backend.failNextPublishes = 1
        await hub.publishIfLinked(world.quietDay())
        XCTAssertTrue(publisher.needsPublishOnForeground(), "a failed publish is retried, whichever model it failed on")

        await hub.unpair()
        XCTAssertFalse(publisher.needsPublishOnForeground())
    }

    func testTurningFullStatsOffIsItselfAReasonToPublish() {
        let cal = world.calendar.calendar
        let now = world.calendar.at(2026, 11, 20, 13)
        let foods = [FoodEntry(date: world.calendar.at(2026, 11, 20, 8), name: "Oatmeal", calories: 300)]
        func signature(sharing: Bool) -> String {
            BuddyAutoPublisher.signature(sharesFullStats: sharing, foods: foods, water: [], steps: [],
                                         sessionCount: 0, weightCount: 2, now: now, calendar: cal)
        }
        XCTAssertNotEqual(signature(sharing: true), signature(sharing: false),
                          "otherwise the last full snapshot stays published until the next log")
        XCTAssertEqual(signature(sharing: true), signature(sharing: true))

        // And a new log still changes it.
        let more = foods + [FoodEntry(date: world.calendar.at(2026, 11, 20, 12), name: "Rice bowl", calories: 520)]
        XCTAssertNotEqual(signature(sharing: true),
                          BuddyAutoPublisher.signature(sharesFullStats: true, foods: more, water: [], steps: [],
                                                       sessionCount: 0, weightCount: 2, now: now, calendar: cal))
    }

    // MARK: - D-V17: one publish at a time per user, across models

    func testTwoModelsOnOnePhoneNeverPublishAtOnce() async {
        let phone = world.makeDefaults()
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        await world.model(alexID, defaults: phone).link(usingCode: sam.myPairingCode)
        // Both models are created already linked, as after a relaunch.
        let hub = world.model(alexID, defaults: phone)
        let publisher = world.model(alexID, defaults: phone)
        let before = world.backend.publishCount

        // The app goes to the background with the hub open: both fire.
        let gate = TestGate()
        world.backend.publishGate = gate
        let first = Task { await hub.publishIfLinked(self.world.quietDay(streak: 1)) }
        await gate.waitForArrival()                       // the first publish is in flight
        let second = Task { await publisher.publishIfLinked(self.world.quietDay(streak: 2)) }
        await second.value                                // parked behind the first, not racing it
        XCTAssertEqual(world.backend.overlappingPublishes, 0)
        gate.open()
        await first.value

        XCTAssertEqual(world.backend.overlappingPublishes, 0,
                       "two fetch-modify-saves of one record at once end in a change-tag conflict")
        XCTAssertFalse(hub.lastPublishFailed)
        XCTAssertFalse(publisher.lastPublishFailed)
        XCTAssertEqual(world.backend.snapshot(of: alexID)?.dayStreak, 2, "the newer state is what ends up published")
        XCTAssertEqual(world.backend.publishCount, before + 2)
        XCTAssertEqual(hub.lastPublishAt, world.now)
        XCTAssertEqual(publisher.lastPublishAt, world.now, "both models report the same sync health")
    }

    func testAFailedPublishIsReportedByEveryModelOnThePhoneAndClearedByTheNextSuccess() async {
        let phone = world.makeDefaults()
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        await world.model(alexID, defaults: phone).link(usingCode: sam.myPairingCode)
        let hub = world.model(alexID, defaults: phone)
        let publisher = world.model(alexID, defaults: phone)

        world.backend.failNextPublishes = 1
        await publisher.publishIfLinked(world.quietDay(streak: 1))
        XCTAssertTrue(publisher.lastPublishFailed)
        XCTAssertTrue(hub.lastPublishFailed, "the hub's footer must show the auto-publisher's failure")

        await hub.publishIfLinked(world.quietDay(streak: 1))
        XCTAssertFalse(hub.lastPublishFailed)
        XCTAssertFalse(publisher.lastPublishFailed)
    }

    // MARK: - D-V10: a streak milestone is sent once

    func testAStreakTierIsCelebratedOnceNotEveryDay() {
        let defaults = world.makeDefaults()
        let cal = world.calendar.calendar
        var day = world.calendar.at(2026, 11, 1, 12)
        var fired: [Int: Set<BuddyMilestone>] = [:]

        // Day 1 of logging is 1 November; the streak grows by one a day.
        for streak in 1...15 {
            fired[streak] = BuddyMilestones.consumeNewlyReached(
                BuddyMilestoneInput(dayStreak: streak), myUserID: alexID, day: day, calendar: cal, defaults: defaults)
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        XCTAssertEqual(fired[3], [.streak3])
        XCTAssertEqual(fired[7], [.streak7])
        XCTAssertEqual(fired[14], [.streak14])
        for quiet in [1, 2, 4, 5, 6, 8, 9, 10, 11, 12, 13, 15] {
            XCTAssertEqual(fired[quiet], [], "day \(quiet) of the streak must not ping the buddy")
        }

        // The streak breaks and a new one reaches three days: that is a new streak.
        day = cal.date(byAdding: .day, value: 5, to: day)!
        XCTAssertEqual(BuddyMilestones.consumeNewlyReached(
            BuddyMilestoneInput(dayStreak: 3), myUserID: alexID, day: day, calendar: cal, defaults: defaults), [.streak3])
    }

    func testADailyGoalIsStillCelebratedOncePerDay() {
        let defaults = world.makeDefaults()
        let cal = world.calendar.calendar
        let day = world.calendar.at(2026, 11, 1, 12)
        let met = BuddyMilestoneInput(steps: 9_000, stepGoal: 8_000)

        XCTAssertEqual(BuddyMilestones.consumeNewlyReached(met, myUserID: alexID, day: day, calendar: cal, defaults: defaults), [.steps])
        XCTAssertEqual(BuddyMilestones.consumeNewlyReached(met, myUserID: alexID, day: day, calendar: cal, defaults: defaults), [])
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day)!
        XCTAssertEqual(BuddyMilestones.consumeNewlyReached(met, myUserID: alexID, day: tomorrow, calendar: cal, defaults: defaults), [.steps])
    }

    func testTheBuddyGetsOneStreakNudgePerTierOverAWeek() async {
        let (alex, _) = await world.pairedModels()

        for streak in 1...8 {
            await alex.publishIfLinked(world.quietDay(streak: streak))
            await alex.publishIfLinked(world.quietDay(streak: streak))   // a second trigger the same day
            nextDay()
        }

        XCTAssertEqual(cheers("streak").count, 2, "\(cheers("streak").map(\.text))")
        XCTAssertEqual(cheers("3-day").count, 1)
        XCTAssertEqual(cheers("7-day").count, 1)
    }

    func testAStreakNudgeSentLateSaysTheRealNumber() async {
        let (alex, _) = await world.pairedModels()

        // Paired on day five of a streak: the three-day tier was never sent.
        await alex.publishIfLinked(world.quietDay(streak: 5))

        XCTAssertEqual(cheers("streak").count, 1)
        XCTAssertEqual(cheers("5-day").count, 1, "\(cheers("streak").map(\.text))")
        XCTAssertEqual(cheers("3-day").count, 0, "day five must not be announced as a 3-day streak")
    }

    // MARK: - D-V11: marked sent only after the send succeeded

    func testAMilestoneWhoseSendFailedIsSentAtTheNextTriggerAndThenNeverAgain() async {
        let (alex, _) = await world.pairedModels()
        var day = world.quietDay()
        day.stepsToday = 9_000
        day.stepGoal = 8_000

        world.backend.failNextNudgeSends = 1          // offline at the moment the goal is crossed
        await alex.publishIfLinked(day)
        XCTAssertEqual(cheers("step goal").count, 0)

        await alex.publishIfLinked(day)               // the next trigger, back online
        XCTAssertEqual(cheers("step goal").count, 1, "a cheer that failed to send is retried")

        await alex.publishIfLinked(day)
        await alex.publishIfLinked(day)
        XCTAssertEqual(cheers("step goal").count, 1, "and once sent, it is not sent again that day")
    }

    func testTwoModelsOnOnePhoneSendAMilestoneOnce() async {
        let phone = world.makeDefaults()
        let sam = world.model(samID, defaults: world.makeDefaults())
        await sam.announceMyCode()
        await world.model(alexID, defaults: phone).link(usingCode: sam.myPairingCode)
        let hub = world.model(alexID, defaults: phone)
        let publisher = world.model(alexID, defaults: phone)
        var day = world.quietDay()
        day.waterToday = 100
        day.waterGoal = 96

        // Both fire as the app goes to the background; the first is held mid-publish.
        let gate = TestGate()
        world.backend.publishGate = gate
        let first = Task { await hub.publishIfLinked(day) }
        await gate.waitForArrival()
        let second = Task { await publisher.publishIfLinked(day) }
        await second.value
        gate.open()
        await first.value

        XCTAssertEqual(cheers("water").count, 1, "\(world.backend.nudges(to: samID).map(\.text))")
    }

    // MARK: - D-V18: a nudge needs a buddy, not a snapshot

    func testANudgeCanBeSentBeforeTheBuddyHasPublishedAnything() async {
        let (alex, _) = await world.pairedModels()
        XCTAssertTrue(alex.isLinked)
        XCTAssertNil(alex.buddySnapshot, "Sam has not published yet")

        await alex.send(.cheer)
        await alex.send(text: "  Proud of you  ")

        let received = world.backend.nudges(to: samID)
        XCTAssertEqual(received.count, 2, alex.banner?.text ?? "")
        XCTAssertEqual(received.last?.text, "Proud of you")
        XCTAssertEqual(received.first?.fromUserID, alexID)
    }

    func testANudgeWithNoBuddyAsksToPairAndSendsNothing() async {
        let alex = world.model(alexID, defaults: world.makeDefaults())

        await alex.send(.cheer)

        XCTAssertEqual(world.backend.nudgeSendAttempts, 0)
        XCTAssertTrue(alex.banner?.text.localizedCaseInsensitiveContains("pair") == true)
    }

    // MARK: - D-V16: the pairing poll does not flood the log

    func testThePairingPollWritesNothingAboutNotBeingLinked() async {
        let alex = world.model(alexID, defaults: world.makeDefaults())
        var lines: [String] = []
        alex.log = { lines.append($0) }

        // The pairing screen polls every four seconds while nobody has typed the code.
        for _ in 0..<25 {
            await alex.refresh()
            world.now += 4
        }

        XCTAssertEqual(lines, [], "being unpaired on the pairing screen is the expected state, not a failure")
    }

    func testARepeatedFailureIsLoggedOnceThenCountedNotRepeated() async {
        let alex = world.model(alexID, defaults: world.makeDefaults())
        var lines: [String] = []
        alex.log = { lines.append($0) }
        world.backend.unavailable = .cloudKitUnavailable

        // Ten minutes on the pairing screen with no connection: 150 passes.
        for _ in 0..<150 {
            await alex.refresh()
            world.now += 4
        }

        let announce = lines.filter { $0.contains("announce code") }
        XCTAssertFalse(announce.isEmpty, "the failure itself must be in the log")
        XCTAssertLessThanOrEqual(lines.count, 8, "150 identical passes must not write 300 lines: \(lines)")
        XCTAssertTrue(lines.contains { $0.contains("repeated") }, "the repeats are counted: \(lines)")
    }

    func testADifferentFailureIsLoggedAtOnce() async {
        let alex = world.model(alexID, defaults: world.makeDefaults())
        var lines: [String] = []
        alex.log = { lines.append($0) }

        world.backend.unavailable = .cloudKitUnavailable
        await alex.refresh()
        world.now += 4
        world.backend.unavailable = .backendFailure("quota")
        await alex.refresh()

        XCTAssertTrue(lines.contains { $0.contains("quota") }, "\(lines)")
    }

    // MARK: - D-V22: the badge follows the unread count

    func testTheBadgeIsSetToTheUnreadCountAndClearedWhenRead() async {
        let (alex, sam) = await world.pairedModels()
        var badges: [Int] = []
        alex.setBadge = { badges.append($0) }

        await sam.send(.cheer)
        await sam.send(.proudOfYou)
        await alex.loadInbox()
        XCTAssertEqual(alex.unreadCount, 2)
        XCTAssertEqual(badges.last, 2)

        await alex.markAllRead()
        XCTAssertEqual(alex.unreadCount, 0)
        XCTAssertEqual(badges.last, 0, "reading the notes clears the app-icon badge")
    }

    func testUnpairingClearsTheBadge() async {
        let (alex, sam) = await world.pairedModels()
        var badges: [Int] = []
        alex.setBadge = { badges.append($0) }
        await sam.send(.cheer)
        await alex.loadInbox()
        XCTAssertEqual(badges.last, 1)

        await alex.unpair()

        XCTAssertEqual(badges.last, 0)
    }

    // MARK: - The opt-in still holds on every path above

    func testWhatIsPublishedCarriesNoFullStatsWithoutTheOptIn() async {
        let (alex, _) = await world.pairedModels()
        var day = world.quietDay()
        day.sharesFullData = false
        day.trendWeightLbs = 181.4
        day.goalWeightLbs = 170
        day.caloriesEaten = 2_100
        day.calorieTarget = 2_400
        day.proteinEaten = 140
        day.todayFoods = "Oatmeal, Chicken rice bowl"

        await alex.publishIfLinked(day)

        let published = world.backend.snapshot(of: alexID)
        XCTAssertNotNil(published)
        XCTAssertEqual(published, published?.withoutFullData)
        XCTAssertEqual(published?.todayFoods, "")
        XCTAssertEqual(published?.trendWeightLbs, 0)
        XCTAssertEqual(published?.caloriesEaten, 0)
    }
}

/// The pieces the buddy flow leans on that need no server at all.
final class BuddyPartsTests: XCTestCase {

    private let la = FixedCalendar()

    // MARK: RepeatedLineFilter (D-V16)

    func testALineIsWrittenOnceThenCountedUntilTheWindowHasPassed() {
        var filter = RepeatedLineFilter(window: 300)
        let start = la.at(2026, 11, 20, 9)

        XCTAssertEqual(filter.admit("snapshot fetch failed", at: start), "snapshot fetch failed")
        for second in stride(from: 4.0, to: 300.0, by: 4.0) {
            XCTAssertNil(filter.admit("snapshot fetch failed", at: start + second))
        }
        XCTAssertEqual(filter.admit("snapshot fetch failed", at: start + 300),
                       "snapshot fetch failed (repeated 74 more times in the last 5 min)")
        XCTAssertNil(filter.admit("snapshot fetch failed", at: start + 304), "and the count starts again")
    }

    func testDifferentLinesDoNotHideEachOther() {
        var filter = RepeatedLineFilter(window: 300)
        let start = la.at(2026, 11, 20, 9)
        XCTAssertNotNil(filter.admit("pairing.fetch: CKError 4", at: start))
        XCTAssertNotNil(filter.admit("pairing.update: CKError 10", at: start + 1),
                        "the one line that says why pairing failed must get through")
        XCTAssertNil(filter.admit("pairing.fetch: CKError 4", at: start + 2))
    }

    func testALineSeenAgainAfterALongSilenceIsWrittenPlainly() {
        var filter = RepeatedLineFilter(window: 300)
        let start = la.at(2026, 11, 20, 9)
        _ = filter.admit("publish.save failed", at: start)
        XCTAssertEqual(filter.admit("publish.save failed", at: start + 3_600), "publish.save failed")
    }

    func testAClockSetBackDoesNotSilenceALineForGood() {
        var filter = RepeatedLineFilter(window: 300)
        let start = la.at(2026, 11, 20, 9)
        _ = filter.admit("publish.save failed", at: start)
        XCTAssertNotNil(filter.admit("publish.save failed", at: start - 86_400))
    }

    func testTheTableOfSeenLinesDoesNotGrowWithoutBound() {
        var filter = RepeatedLineFilter(window: 300)
        let start = la.at(2026, 11, 20, 9)
        for i in 0..<1_000 {
            _ = filter.admit("line \(i)", at: start + Double(i) * 60)
        }
        // A line last seen 16 hours ago has been forgotten, so it is written again, plainly.
        XCTAssertEqual(filter.admit("line 0", at: start + 1_000 * 60), "line 0")
    }

    // MARK: Milestone wording (D-V10)

    func testAStreakTierReachedOnItsDayKeepsItsOwnWording() {
        XCTAssertEqual(BuddyMilestone.streak7.message(name: "Alex", dayStreak: 7),
                       BuddyMilestone.streak7.message(name: "Alex"))
        XCTAssertTrue(BuddyMilestone.streak3.message(name: "Alex", dayStreak: 3).contains("3-day"))
    }

    func testAStreakTierSentLateNamesTheRealStreak() {
        let late = BuddyMilestone.streak3.message(name: "Alex", dayStreak: 5)
        XCTAssertTrue(late.contains("5-day"), late)
        XCTAssertFalse(late.contains("3-day"), late)
        XCTAssertTrue(BuddyMilestone.streak14.message(name: "Sam", dayStreak: 20).contains("20-day"))
    }

    func testADailyGoalMessageIgnoresTheStreak() {
        XCTAssertEqual(BuddyMilestone.water.message(name: "Alex", dayStreak: 40),
                       BuddyMilestone.water.message(name: "Alex"))
    }

    func testAMilestoneIsPendingUntilMarkedSent() {
        let suite = "buddy-parts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let day = la.at(2026, 11, 20, 14)
        let input = BuddyMilestoneInput(proteinEaten: 130, proteinTarget: 120, dayStreak: 3)

        let pending = { BuddyMilestones.pending(input, myUserID: "user-alex", day: day,
                                                calendar: self.la.calendar, defaults: defaults) }
        XCTAssertEqual(pending(), [.protein, .streak3])
        XCTAssertEqual(pending(), [.protein, .streak3], "asking does not consume")

        BuddyMilestones.markSent(.protein, input: input, myUserID: "user-alex", day: day,
                                 calendar: la.calendar, defaults: defaults)
        XCTAssertEqual(pending(), [.streak3])

        // Another user on the same phone's defaults has their own record.
        XCTAssertEqual(BuddyMilestones.pending(input, myUserID: "user-sam", day: day,
                                               calendar: la.calendar, defaults: defaults), [.protein, .streak3])
    }

    // MARK: Pairing codes (D-V2)

    func testEveryMintedCodeIsWellFormed() {
        for _ in 0..<500 {
            let code = BuddyPairingCode.make()
            XCTAssertTrue(BuddyPairingCode.isWellFormed(code), code)
            XCTAssertEqual(BuddyPairingCode.normalize(" \(code.lowercased()) "), code)
        }
    }

    func testWhatIsNotACode() {
        for bad in ["", "VITA-", "VITA-ABC", "VITA-ABCDE", "VITA-AB1D", "VITA-ABOD", "VITA-AB0D",
                    "VITA-ABID", "VITA-ABLD", "VITAABCD", "VITA ABCD", "vita-abcd", "ABCD", "VITA-AB D"] {
            XCTAssertFalse(BuddyPairingCode.isWellFormed(bad), bad)
        }
        XCTAssertTrue(BuddyPairingCode.isWellFormed(LocalMockSyncService.buddyCode))
        XCTAssertTrue(BuddyPairingCode.isWellFormed(LocalMockSyncService.claimedCode))
    }

    // MARK: Signed out of iCloud

    func testNoICloudAccountIsItsOwnFailureNotAnOutage() {
        XCTAssertNil(CloudKitSyncService.failure(for: .available))
        XCTAssertEqual(CloudKitSyncService.failure(for: .noAccount), .iCloudAccountMissing)
        XCTAssertEqual(CloudKitSyncService.failure(for: .restricted), .iCloudAccountMissing)
        XCTAssertEqual(CloudKitSyncService.failure(for: .couldNotDetermine), .cloudKitUnavailable)
        XCTAssertEqual(CloudKitSyncService.failure(for: .temporarilyUnavailable), .cloudKitUnavailable)
    }

    @MainActor
    func testEveryFailureHasASentenceOfItsOwn() {
        let all: [BuddySyncError] = [.cloudKitUnavailable, .iCloudAccountMissing, .notLinked, .malformedPairingCode,
                                     .invalidPairingCode, .ownPairingCode, .pairingCodeAlreadyClaimed,
                                     .pairingCodeTaken, .unpairedByBuddy, .backendFailure("x")]
        let sentences = all.map(BuddyViewModel.message(for:))
        XCTAssertEqual(Set(sentences).count, all.count)
        XCTAssertTrue(BuddyViewModel.message(for: .iCloudAccountMissing).contains("Sign in to iCloud"))
        XCTAssertFalse(BuddyViewModel.message(for: .iCloudAccountMissing).localizedCaseInsensitiveContains("catch up"),
                       "waiting does not fix a missing account")
    }

    // MARK: Which pushes are about the buddy (D-V14)

    func testAQueryPushIsClassifiedByItsSubscription() {
        XCTAssertEqual(BuddyPush.kind(querySubscriptionID: "nudges-to-user-alex-v2"), .nudge)
        XCTAssertEqual(BuddyPush.kind(querySubscriptionID: "buddy-snapshot-user-alex-from-user-sam"), .snapshot)
        XCTAssertEqual(BuddyPush.kind(querySubscriptionID: "something-else"), .unknown)
        XCTAssertEqual(BuddyPush.kind(querySubscriptionID: nil), .unknown)
    }

    func testOnlyAPushKnownToBeThePrivateMirrorsIsLeftAlone() {
        XCTAssertTrue(BuddyPush.nudge.concernsBuddy)
        XCTAssertTrue(BuddyPush.snapshot.concernsBuddy)
        XCTAssertTrue(BuddyPush.unknown.concernsBuddy, "when in doubt, refresh: nothing that used to refresh stops")
        XCTAssertFalse(BuddyPush.privateMirror.concernsBuddy)
        XCTAssertEqual(BuddyPush.kind(userInfo: [:]), .unknown)
        XCTAssertEqual(BuddyPush.kind(userInfo: ["aps": ["content-available": 1] as NSDictionary]), .unknown)
    }
}
