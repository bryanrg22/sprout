import XCTest
import SwiftData
@testable import Victoria

/// G4, "the store returns what was put in", part (b), second half: the passive tracker
/// mirrors (steps, sleep, detected workouts, vitals), the achievement and insight records,
/// and the buddy models. Same contract as `StoreVerificationRoundTripTests.swift`: real
/// initializer, save, read back through a NEW `ModelContext`, every stored property compared
/// with the literal that was written.
///
/// Each test declares one field per stored property (`wrote` = the initializer wrote it,
/// `assigned` = set after init, `decoded` = JSON text compared after decoding). The harness
/// (`assertRoundTrip`, in `Support/StoreTestSupport.swift`) refuses a table that does not name
/// exactly the properties the schema stores, so a property added to a model without a row
/// here fails the test; and it refuses a written value equal to the model's default, so a
/// column that silently drops its value cannot pass. Models with optionals save a second,
/// sparse row and check that each optional reads back nil.
@MainActor
final class StoreVerificationRoundTripTrackerBuddyTests: XCTestCase {

    private let fx = FixedCalendar()

    func test_b_roundTrip_StepsEntry() throws {
        let day = fx.at(2026, 2, 19)
        let created = fx.at(2026, 2, 20, 0, 5)
        try assertRoundTrip(
            full: { StepsEntry(date: day, count: 10_250) },
            blank: { StepsEntry(count: 0) },
            fields: [
                assigned("id", \.id, fixedUUID(9)),
                wrote("date", \.date, day),
                wrote("count", \.count, 10_250),
                assigned("createdAt", \.createdAt, created),
            ])
    }

    func test_b_roundTrip_SleepEntry() throws {
        let day = fx.at(2026, 2, 20)
        let created = fx.at(2026, 2, 20, 8, 1, 2)
        try assertRoundTrip(
            full: { SleepEntry(date: day, asleepMinutes: 432, inBedMinutes: 465, deepMinutes: 81,
                               remMinutes: 104, coreMinutes: 247, awakeMinutes: 19) },
            blank: { SleepEntry(asleepMinutes: 0) },
            fields: [
                assigned("id", \.id, fixedUUID(10)),
                wrote("date", \.date, day),
                wrote("asleepMinutes", \.asleepMinutes, 432),
                wrote("inBedMinutes", \.inBedMinutes, 465),
                wrote("deepMinutes", \.deepMinutes, 81),
                wrote("remMinutes", \.remMinutes, 104),
                wrote("coreMinutes", \.coreMinutes, 247),
                wrote("awakeMinutes", \.awakeMinutes, 19),
                assigned("createdAt", \.createdAt, created),
            ],
            typed: { XCTAssertTrue($0.hasStages) })
    }

    func test_b_roundTrip_DetectedWorkout() throws {
        let start = fx.at(2026, 2, 19, 6, 40, 15)
        let created = fx.at(2026, 2, 19, 8)
        try assertRoundTrip(
            full: { DetectedWorkout(healthKitUUID: "ghealth:exercise/123", date: start, activity: "Running",
                                    durationMinutes: 31, caloriesBurned: 288.5, sourceName: "Fitbit") },
            blank: { DetectedWorkout(healthKitUUID: "", date: .distantPast, activity: "", durationMinutes: 0) },
            fields: [
                assigned("id", \.id, fixedUUID(11)),
                wrote("healthKitUUID", \.healthKitUUID, "ghealth:exercise/123"),
                wrote("date", \.date, start),
                wrote("activity", \.activity, "Running"),
                wrote("durationMinutes", \.durationMinutes, 31),
                wrote("caloriesBurned", \.caloriesBurned, 288.5),
                wrote("sourceName", \.sourceName, "Fitbit"),
                assigned("createdAt", \.createdAt, created),
            ])
    }

    func test_b_roundTrip_VitalsEntry() throws {
        let day = fx.at(2026, 2, 20)
        let created = fx.at(2026, 2, 20, 8, 2)
        try assertRoundTrip(
            full: { VitalsEntry(date: day, restingHeartRate: 57.5, hrvMs: 46.25) },
            blank: { VitalsEntry() },
            fields: [
                assigned("id", \.id, fixedUUID(12)),
                wrote("date", \.date, day),
                wrote("restingHeartRate", \.restingHeartRate, 57.5),
                wrote("hrvMs", \.hrvMs, 46.25),
                assigned("createdAt", \.createdAt, created),
            ])
    }

    func test_b_roundTrip_AchievementUnlock() throws {
        let unlocked = fx.at(2026, 2, 14, 20, 20, 20)
        try assertRoundTrip(
            full: { AchievementUnlock(achievementID: "streak_7", unlockedAt: unlocked) },
            blank: { AchievementUnlock(achievementID: "") },
            fields: [
                wrote("achievementID", \.achievementID, "streak_7"),
                wrote("unlockedAt", \.unlockedAt, unlocked),
            ])
    }

    func test_b_roundTrip_InsightShown() throws {
        let shown = fx.at(2026, 2, 20, 19, 0, 7)
        try assertRoundTrip(
            full: { InsightShown(insightID: "fuel_up", shownAt: shown) },
            blank: { InsightShown(insightID: "") },
            fields: [
                wrote("insightID", \.insightID, "fuel_up"),
                wrote("shownAt", \.shownAt, shown),
            ])
    }

    func test_b_roundTrip_BuddyLink() throws {
        let created = fx.at(2026, 1, 30, 17, 45)
        try assertRoundTrip(
            full: { BuddyLink(myUserID: "user-me", buddyUserID: "user-them", buddyDisplayName: "Alex",
                              pairingCode: "VITA-7F3K", status: .linked, createdAt: created) },
            blank: { BuddyLink(myUserID: "", pairingCode: "") },
            fields: [
                wrote("myUserID", \.myUserID, "user-me"),
                wrote("buddyUserID", \.buddyUserID, "user-them"),
                wrote("buddyDisplayName", \.buddyDisplayName, "Alex"),
                wrote("pairingCode", \.pairingCode, "VITA-7F3K"),
                wrote("statusRaw", \.statusRaw, "linked"),
                wrote("createdAt", \.createdAt, created),
            ],
            sparse: { BuddyLink(myUserID: "user-waiting", pairingCode: "VITA-0000", createdAt: created) },
            sparseFields: [
                wrote("buddyUserID", \.buddyUserID, nil),
                wrote("buddyDisplayName", \.buddyDisplayName, nil),
            ],
            typed: { link in
                XCTAssertEqual(link.status, .linked)
                XCTAssertTrue(link.isLinked)
            },
            typedSparse: { link in
                XCTAssertEqual(link.status, .pending)
                XCTAssertFalse(link.isLinked)
            })
    }

    func test_b_roundTrip_Nudge() throws {
        let created = fx.at(2026, 2, 20, 13, 14, 15)
        try assertRoundTrip(
            full: { Nudge(id: fixedUUID(16), fromUserID: "user-them", toUserID: "user-me", kind: .letsMove,
                          text: "Walk at 6?", createdAt: created, isRead: true) },
            blank: { Nudge(fromUserID: "", toUserID: "") },
            fields: [
                wrote("id", \.id, fixedUUID(16)),
                wrote("fromUserID", \.fromUserID, "user-them"),
                wrote("toUserID", \.toUserID, "user-me"),
                wrote("kindRaw", \.kindRaw, "letsMove"),
                wrote("text", \.text, "Walk at 6?"),
                wrote("createdAt", \.createdAt, created),
                wrote("isRead", \.isRead, true),
            ],
            typed: { XCTAssertEqual($0.kind, .letsMove) })
    }

    func test_b_roundTrip_BuddySnapshot() throws {
        let active = fx.at(2026, 2, 20, 16, 30, 1)
        try assertRoundTrip(
            full: { BuddySnapshot(ownerUserID: "user-them", displayName: "Alex", dayStreak: 9,
                                  characterMood: .thriving, loggedToday: true, lastActive: active,
                                  stepsToday: 8_420, stepGoal: 9_000, waterToday: 52.5, waterGoal: 80,
                                  workedOutToday: true, workoutSummary: "Chest · Arms",
                                  sharesFullData: true, trendWeightLbs: 161.3, goalWeightLbs: 172,
                                  weeklyRateLbs: -0.45, caloriesEaten: 2_140, calorieTarget: 2_650,
                                  proteinEaten: 131.5, proteinTarget: 165, carbsEaten: 240.25, carbTarget: 310,
                                  fatEaten: 71.75, fatTarget: 85, todayFoods: "Oats, Chicken bowl") },
            blank: { BuddySnapshot(ownerUserID: "", displayName: "") },
            fields: [
                wrote("ownerUserID", \.ownerUserID, "user-them"),
                wrote("displayName", \.displayName, "Alex"),
                wrote("dayStreak", \.dayStreak, 9),
                wrote("characterMoodRaw", \.characterMoodRaw, "thriving"),
                wrote("loggedToday", \.loggedToday, true),
                wrote("lastActive", \.lastActive, active),
                wrote("stepsToday", \.stepsToday, 8_420),
                wrote("stepGoal", \.stepGoal, 9_000),
                wrote("waterToday", \.waterToday, 52.5),
                wrote("waterGoal", \.waterGoal, 80),
                wrote("workedOutToday", \.workedOutToday, true),
                wrote("workoutSummary", \.workoutSummary, "Chest · Arms"),
                wrote("sharesFullData", \.sharesFullData, true),
                wrote("trendWeightLbs", \.trendWeightLbs, 161.3),
                wrote("goalWeightLbs", \.goalWeightLbs, 172),
                wrote("weeklyRateLbs", \.weeklyRateLbs, -0.45),
                wrote("caloriesEaten", \.caloriesEaten, 2_140),
                wrote("calorieTarget", \.calorieTarget, 2_650),
                wrote("proteinEaten", \.proteinEaten, 131.5),
                wrote("proteinTarget", \.proteinTarget, 165),
                wrote("carbsEaten", \.carbsEaten, 240.25),
                wrote("carbTarget", \.carbTarget, 310),
                wrote("fatEaten", \.fatEaten, 71.75),
                wrote("fatTarget", \.fatTarget, 85),
                wrote("todayFoods", \.todayFoods, "Oats, Chicken bowl"),
            ],
            typed: { XCTAssertEqual($0.characterMood, .thriving) })
    }
}
