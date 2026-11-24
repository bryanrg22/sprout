import XCTest
import SwiftData
@testable import Sprout

/// G4, "the store returns what was put in", part (b), first half: the models the user and the
/// coach write (profile, weigh-ins, food, water, workouts, chat, memory, plan, checklist).
/// Each is built through its real initializer, saved, then read back through a NEW
/// `ModelContext` (a fetch from the store, never the writer's objects), and every stored
/// property is compared with the literal that was written. The tracker and buddy models are
/// in `StoreVerificationRoundTripTrackerBuddyTests.swift`.
///
/// Each test declares one field per stored property (`wrote` = the initializer wrote it,
/// `assigned` = set after init, `decoded` = JSON text compared after decoding). The harness
/// (`assertRoundTrip`, in `Support/StoreTestSupport.swift`) refuses a table that does not name
/// exactly the properties the schema stores, so a property added to a model without a row
/// here fails the test; and it refuses a written value equal to the model's default, so a
/// column that silently drops its value cannot pass. Models with optionals save a second,
/// sparse row and check that each optional reads back nil.
@MainActor
final class StoreVerificationRoundTripTests: XCTestCase {

    private let fx = FixedCalendar()

    func test_b_roundTrip_UserProfile() throws {
        let birth = fx.at(1999, 7, 4)
        let created = fx.at(2026, 1, 15, 8, 30, 12).addingTimeInterval(0.25)
        let gag = fx.at(2026, 2, 19, 21, 45, 3)
        // The custom character: a PNG signature and a few bytes are enough to prove the
        // externally stored blob comes back byte for byte.
        let avatarPNG: Data? = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03])
        try assertRoundTrip(
            full: { UserProfile() },
            blank: { UserProfile() },
            fields: [
                assigned("id", \.id, fixedUUID(1)),
                assigned("name", \.name, "Sam Rivera"),
                assigned("sexRaw", \.sexRaw, "male"),
                assigned("birthDate", \.birthDate, birth),
                assigned("heightCm", \.heightCm, 178.5),
                assigned("activityLevelRaw", \.activityLevelRaw, "veryActive"),
                assigned("paceRaw", \.paceRaw, "leanGain"),
                assigned("startWeightLbs", \.startWeightLbs, 158.4),
                assigned("goalWeightLbs", \.goalWeightLbs, 172.2),
                assigned("unitSystemRaw", \.unitSystemRaw, "metric"),
                assigned("coachName", \.coachName, "Juno"),
                assigned("dailyStepGoal", \.dailyStepGoal, 11_500),
                assigned("stepsAdjustCalories", \.stepsAdjustCalories, true),
                assigned("onboardingComplete", \.onboardingComplete, true),
                assigned("createdAt", \.createdAt, created),
                assigned("onboardingNote", \.onboardingNote, "Lifts four days a week; dislikes mushrooms."),
                assigned("waterGoalOzOverride", \.waterGoalOzOverride, 96.5),
                assigned("waterContainerOz", \.waterContainerOz, 24.0),
                assigned("waterContainerLabel", \.waterContainerLabel, "flask"),
                assigned("waterUnitRaw", \.waterUnitRaw, "ml"),
                assigned("calorieTargetOverride", \.calorieTargetOverride, 2_650.0),
                assigned("proteinTargetOverride", \.proteinTargetOverride, 165.0),
                assigned("calorieMaxOverride", \.calorieMaxOverride, 2_900.0),
                assigned("shareFullStatsWithBuddy", \.shareFullStatsWithBuddy, false),
                assigned("companionName", \.companionName, "Pip"),
                assigned("companionAvatarRaw", \.companionAvatarRaw, "bryan"),
                assigned("customAvatarPNG", \.customAvatarPNG, avatarPNG),
                assigned("lastAlejandroGagDate", \.lastAlejandroGagDate, gag),
                assigned("themeStyleRaw", \.themeStyleRaw, "cool"),
                assigned("weighInReminderEnabled", \.weighInReminderEnabled, false),
                assigned("weighInHour", \.weighInHour, 6),
                assigned("mealRemindersEnabled", \.mealRemindersEnabled, false),
                assigned("breakfastHour", \.breakfastHour, 7),
                assigned("lunchHour", \.lunchHour, 12),
                assigned("dinnerHour", \.dinnerHour, 20),
                assigned("gymReminderEnabled", \.gymReminderEnabled, true),
                assigned("gymHour", \.gymHour, 18),
                assigned("gymWeekdays", \.gymWeekdays, [1, 3, 5, 7]),
                assigned("aiModelFood", \.aiModelFood, "model-food-x"),
                assigned("aiModelChat", \.aiModelChat, "model-chat-y"),
                assigned("homeGymRaw", \.homeGymRaw, "twentyFourHour"),
            ],
            // A profile that never made a character: the optional blob reads back nil.
            sparse: { UserProfile() },
            sparseFields: [wrote("customAvatarPNG", \.customAvatarPNG, nil)],
            typed: { profile in
                XCTAssertEqual(profile.sex, .male)
                XCTAssertEqual(profile.activityLevel, .veryActive)
                XCTAssertEqual(profile.pace, .leanGain)
                XCTAssertEqual(profile.unitSystem, .metric)
                XCTAssertEqual(profile.themeStyle, .cool)
                XCTAssertEqual(profile.companionAvatar, .bryan)
                XCTAssertEqual(profile.homeGym, .twentyFourHour)
            })
    }

    func test_b_roundTrip_WeightEntry() throws {
        let date = fx.at(2026, 2, 20, 7, 5, 9).addingTimeInterval(0.125)
        let created = fx.at(2026, 2, 20, 7, 6)
        try assertRoundTrip(
            full: { WeightEntry(date: date, weightLbs: 151.4, note: "after a run",
                                source: "healthkit", healthKitUUID: "HK-WEIGHT-1") },
            blank: { WeightEntry(weightLbs: 0) },
            fields: [
                assigned("id", \.id, fixedUUID(2)),
                wrote("date", \.date, date),
                wrote("weightLbs", \.weightLbs, 151.4),
                wrote("note", \.note, "after a run"),
                wrote("source", \.source, "healthkit"),
                wrote("healthKitUUID", \.healthKitUUID, "HK-WEIGHT-1"),
                assigned("createdAt", \.createdAt, created),
            ],
            sparse: { WeightEntry(date: date, weightLbs: 150.2) },
            sparseFields: [wrote("note", \.note, nil), wrote("healthKitUUID", \.healthKitUUID, nil)])
    }

    func test_b_roundTrip_FoodEntry() throws {
        let date = fx.at(2026, 2, 20, 12, 45, 30)
        let created = fx.at(2026, 2, 20, 12, 46, 1)
        let cover = Data([0xFF, 0xD8, 0x01, 0x02, 0x03])
        let extras = [Data([0x0A, 0x0B]), Data([0x0C])]
        try assertRoundTrip(
            full: { FoodEntry(date: date, mealType: .dinner, name: "Chicken bowl",
                              servingDescription: "1 bowl", quantity: 1.5,
                              calories: 480, proteinG: 40.5, carbsG: 50.25, fatG: 12.75,
                              caloriesLow: 430, caloriesHigh: 540,
                              source: .photo, confidence: .medium,
                              notes: "assumed cooked in oil", barcode: "0123456789012",
                              photoData: cover, additionalPhotoData: extras, isFavorite: true,
                              detail: NutrientDetail([.saturatedFat: 3.5, .transFat: 0.25, .cholesterol: 95,
                                                      .sodium: 880.5, .fiber: 6.25, .sugars: 7.5,
                                                      .addedSugars: 2.5, .vitaminD: 1.75, .calcium: 120,
                                                      .iron: 2.4, .potassium: 610])) },
            blank: { FoodEntry(name: "") },
            fields: [
                assigned("id", \.id, fixedUUID(3)),
                wrote("date", \.date, date),
                wrote("mealTypeRaw", \.mealTypeRaw, "dinner"),
                wrote("name", \.name, "Chicken bowl"),
                wrote("servingDescription", \.servingDescription, "1 bowl"),
                wrote("quantity", \.quantity, 1.5),
                wrote("calories", \.calories, 480),
                wrote("proteinG", \.proteinG, 40.5),
                wrote("carbsG", \.carbsG, 50.25),
                wrote("fatG", \.fatG, 12.75),
                wrote("caloriesLow", \.caloriesLow, 430),
                wrote("caloriesHigh", \.caloriesHigh, 540),
                wrote("sourceRaw", \.sourceRaw, "photo"),
                wrote("confidenceRaw", \.confidenceRaw, "medium"),
                wrote("notes", \.notes, "assumed cooked in oil"),
                wrote("barcode", \.barcode, "0123456789012"),
                wrote("photoData", \.photoData, cover),
                wrote("additionalPhotoData", \.additionalPhotoData, extras),
                wrote("isFavorite", \.isFavorite, true),
                assigned("createdAt", \.createdAt, created),
                // The label nutrients: eleven distinct literals, so two columns swapped or
                // aliased cannot pass.
                wrote("saturatedFatG", \.saturatedFatG, 3.5),
                wrote("transFatG", \.transFatG, 0.25),
                wrote("cholesterolMg", \.cholesterolMg, 95),
                wrote("sodiumMg", \.sodiumMg, 880.5),
                wrote("fiberG", \.fiberG, 6.25),
                wrote("sugarsG", \.sugarsG, 7.5),
                wrote("addedSugarsG", \.addedSugarsG, 2.5),
                wrote("vitaminDMcg", \.vitaminDMcg, 1.75),
                wrote("calciumMg", \.calciumMg, 120),
                wrote("ironMg", \.ironMg, 2.4),
                wrote("potassiumMg", \.potassiumMg, 610),
            ],
            // A food logged without any of them: every one reads back nil (not known), not 0.
            sparse: { FoodEntry(date: date, name: "Black coffee") },
            sparseFields: [
                wrote("saturatedFatG", \.saturatedFatG, nil),
                wrote("transFatG", \.transFatG, nil),
                wrote("cholesterolMg", \.cholesterolMg, nil),
                wrote("sodiumMg", \.sodiumMg, nil),
                wrote("fiberG", \.fiberG, nil),
                wrote("sugarsG", \.sugarsG, nil),
                wrote("addedSugarsG", \.addedSugarsG, nil),
                wrote("vitaminDMcg", \.vitaminDMcg, nil),
                wrote("calciumMg", \.calciumMg, nil),
                wrote("ironMg", \.ironMg, nil),
                wrote("potassiumMg", \.potassiumMg, nil),
                wrote("caloriesLow", \.caloriesLow, nil),
                wrote("caloriesHigh", \.caloriesHigh, nil),
                wrote("confidenceRaw", \.confidenceRaw, nil),
                wrote("notes", \.notes, nil),
                wrote("barcode", \.barcode, nil),
                wrote("photoData", \.photoData, nil),
                wrote("additionalPhotoData", \.additionalPhotoData, nil),
            ],
            typed: { food in
                XCTAssertEqual(food.mealType, .dinner)
                XCTAssertEqual(food.source, .photo)
                XCTAssertEqual(food.confidence, .medium)
                // The totals every screen sums: per-serving value x quantity 1.5.
                XCTAssertEqual(food.totalCalories, 720)      // 480 x 1.5
                XCTAssertEqual(food.totalProteinG, 60.75)    // 40.5 x 1.5
                XCTAssertEqual(food.totalCarbsG, 75.375)     // 50.25 x 1.5
                XCTAssertEqual(food.totalFatG, 19.125)       // 12.75 x 1.5
                // The label nutrients as one value, and what the day view sums from them.
                XCTAssertEqual(food.detail.known, Nutrient.allCases)
                XCTAssertEqual(food.detail.sodiumMg, 880.5)
                let totals = NutrientTotals([food])
                XCTAssertEqual(totals[.sodium].total, 1_320.75)   // 880.5 x 1.5
                XCTAssertEqual(totals[.fiber].total, 9.375)       // 6.25 x 1.5
                XCTAssertTrue(totals[.fiber].isComplete)
            },
            typedSparse: { food in
                XCTAssertNil(food.confidence)
                XCTAssertEqual(food.mealType, .snack)
                XCTAssertEqual(food.source, .manual)
                XCTAssertTrue(food.detail.isEmpty)
                XCTAssertNil(NutrientTotals([food])[.sodium].total, "not known reads back as not known")
            })
    }

    /// The other half of "not known is never zero": a zero that WAS stated has to come back
    /// as zero, not as nil. One row with every label nutrient 0, one with none.
    func test_b_roundTrip_FoodEntry_statedZeroAndNotKnownStayDistinct() throws {
        let container = try TestStore.makeContainer()
        let writer = ModelContext(container)
        var zeros = NutrientDetail()
        for nutrient in Nutrient.allCases { zeros[nutrient] = 0 }
        writer.insert(FoodEntry(date: fx.at(2026, 2, 20, 9), name: "Sparkling water", calories: 0, detail: zeros))
        writer.insert(FoodEntry(date: fx.at(2026, 2, 20, 13), name: "Soup", calories: 180))
        try writer.save()

        let read = try TestStore.fetchAll(FoodEntry.self, in: container, sortBy: [SortDescriptor(\.date)])
        XCTAssertEqual(read.map(\.name), ["Sparkling water", "Soup"])
        for nutrient in Nutrient.allCases {
            XCTAssertEqual(read[0].detail[nutrient], 0, "\(nutrient): a stated zero is stored as 0")
            XCTAssertNil(read[1].detail[nutrient], "\(nutrient): never stated, so stored as nil")
        }
        let totals = NutrientTotals(read)
        XCTAssertEqual(totals[.sodium].total, 0)
        XCTAssertEqual(totals[.sodium].known, 1)
        XCTAssertEqual(totals[.sodium].coverageNote, "from 1 of 2 foods")
    }

    func test_b_roundTrip_WorkoutEntry() throws {
        let date = fx.at(2026, 2, 19, 18, 15)
        let created = fx.at(2026, 2, 19, 19, 2, 44)
        try assertRoundTrip(
            full: { WorkoutEntry(date: date, type: .hiit, title: "Intervals", durationMinutes: 35,
                                 caloriesBurned: 412.5, focus: .fullBody, notes: "new shoes") },
            blank: { WorkoutEntry() },
            fields: [
                assigned("id", \.id, fixedUUID(4)),
                wrote("date", \.date, date),
                wrote("typeRaw", \.typeRaw, "hiit"),
                wrote("title", \.title, "Intervals"),
                wrote("durationMinutes", \.durationMinutes, 35),
                wrote("caloriesBurned", \.caloriesBurned, 412.5),
                wrote("focusRaw", \.focusRaw, "fullBody"),
                wrote("notes", \.notes, "new shoes"),
                assigned("createdAt", \.createdAt, created),
            ],
            sparse: { WorkoutEntry(date: date, type: .walk, title: "Walk") },
            sparseFields: [
                wrote("caloriesBurned", \.caloriesBurned, nil),
                wrote("focusRaw", \.focusRaw, nil),
                wrote("notes", \.notes, nil),
            ],
            typed: { workout in
                XCTAssertEqual(workout.type, .hiit)
                XCTAssertEqual(workout.focus, .fullBody)
            },
            typedSparse: { workout in
                XCTAssertEqual(workout.type, .walk)
                XCTAssertNil(workout.focus)
            })
    }

    func test_b_roundTrip_WaterEntry() throws {
        let date = fx.at(2026, 2, 20, 9, 0, 1)
        let created = fx.at(2026, 2, 20, 9, 0, 2)
        try assertRoundTrip(
            full: { WaterEntry(date: date, amountOz: 16.9) },
            blank: { WaterEntry(amountOz: 0) },
            fields: [
                assigned("id", \.id, fixedUUID(5)),
                wrote("date", \.date, date),
                wrote("amountOz", \.amountOz, 16.9),
                assigned("createdAt", \.createdAt, created),
            ])
    }

    func test_b_roundTrip_ChatMessage() throws {
        let created = fx.at(2026, 2, 20, 10, 11, 12).addingTimeInterval(0.5)
        let image = Data([0x89, 0x50, 0x4E, 0x47])
        try assertRoundTrip(
            full: { ChatMessage(role: "user", content: "Set my step goal to 12,000", imageData: image,
                                createdAt: created, isSystemSeed: true,
                                decisionSummary: "set your daily step goal to 12,000 steps",
                                decisionAccepted: false) },
            blank: { ChatMessage(role: "assistant", content: "") },
            fields: [
                assigned("id", \.id, fixedUUID(6)),
                wrote("roleRaw", \.roleRaw, "user"),
                wrote("content", \.content, "Set my step goal to 12,000"),
                wrote("imageData", \.imageData, image),
                wrote("createdAt", \.createdAt, created),
                wrote("isSystemSeed", \.isSystemSeed, true),
                wrote("decisionSummary", \.decisionSummary, "set your daily step goal to 12,000 steps"),
                wrote("decisionAccepted", \.decisionAccepted, false),
            ],
            sparse: { ChatMessage(role: "assistant", content: "Hi", createdAt: created) },
            sparseFields: [
                wrote("imageData", \.imageData, nil),
                wrote("decisionSummary", \.decisionSummary, nil),
                wrote("decisionAccepted", \.decisionAccepted, nil),
            ],
            typed: { message in
                XCTAssertTrue(message.isUser)
                XCTAssertTrue(message.isDecision)
            },
            typedSparse: { message in
                XCTAssertFalse(message.isUser)
                XCTAssertFalse(message.isDecision)
            })
    }

    func test_b_roundTrip_CoachMemory() throws {
        let through = fx.at(2026, 2, 18, 22, 0, 30)
        let updated = fx.at(2026, 2, 19, 6, 15)
        try assertRoundTrip(
            full: { CoachMemory(profileNotes: "- prefers morning workouts",
                                conversationSummary: "Talked about meal prep on Sundays.",
                                summarizedThroughDate: through, updatedAt: updated) },
            blank: { CoachMemory() },
            fields: [
                assigned("id", \.id, fixedUUID(7)),
                wrote("profileNotes", \.profileNotes, "- prefers morning workouts"),
                wrote("conversationSummary", \.conversationSummary, "Talked about meal prep on Sundays."),
                wrote("summarizedThroughDate", \.summarizedThroughDate, through),
                wrote("updatedAt", \.updatedAt, updated),
            ],
            sparse: { CoachMemory(profileNotes: "x", updatedAt: updated) },
            sparseFields: [wrote("summarizedThroughDate", \.summarizedThroughDate, nil)])
    }

    func test_b_roundTrip_CoachPlan() throws {
        let created = fx.at(2026, 2, 1, 9)
        let updated = fx.at(2026, 2, 15, 9, 30, 45)
        let insight = PlanInsight(id: fixedUUID(81), title: "Protein is steady", body: "Five of seven days.", tone: .win)
        let change = PlanChange(id: fixedUUID(82), date: fx.at(2026, 2, 15, 9, 30), summary: "Raised the floor by 100")
        try assertRoundTrip(
            full: { CoachPlan(headline: "On track for 172 by June", assessment: "**Good** pace.",
                              strategy: "Eat more on lifting days.", calorieMin: 2_600, calorieMax: 2_850,
                              proteinTarget: 165, goalSummary: "Lean gain to 172", timeframe: "16 weeks",
                              dataPointsAtBuild: 12, insights: [insight], changelog: [change],
                              createdAt: created, updatedAt: updated) },
            blank: { CoachPlan() },
            fields: [
                assigned("id", \.id, fixedUUID(8)),
                wrote("headline", \.headline, "On track for 172 by June"),
                wrote("assessment", \.assessment, "**Good** pace."),
                wrote("strategy", \.strategy, "Eat more on lifting days."),
                wrote("calorieMin", \.calorieMin, 2_600),
                wrote("calorieMax", \.calorieMax, 2_850),
                wrote("proteinTarget", \.proteinTarget, 165),
                wrote("goalSummary", \.goalSummary, "Lean gain to 172"),
                wrote("timeframe", \.timeframe, "16 weeks"),
                assigned("researchNotes", \.researchNotes, "Based on two position stands."),
                wrote("dataPointsAtBuild", \.dataPointsAtBuild, 12),
                // JSON text: compared after decoding, so key order cannot matter.
                decoded("insightsJSON") { $0.insights == [insight] ? nil : "insightsJSON: \($0.insightsJSON)" },
                decoded("changelogJSON") { $0.changelog == [change] ? nil : "changelogJSON: \($0.changelogJSON)" },
                wrote("createdAt", \.createdAt, created),
                wrote("updatedAt", \.updatedAt, updated),
            ],
            typed: { plan in
                // The JSON-backed arrays decode to the values that were written.
                XCTAssertEqual(plan.insights, [insight])
                XCTAssertEqual(plan.changelog, [change])
                XCTAssertTrue(plan.hasRange)
                XCTAssertFalse(plan.isEarlyRead)   // 12 data points, threshold is 7
            })
    }

    func test_b_roundTrip_ChecklistItem() throws {
        // `init` rounds `day` with the device calendar, so the fixed day is assigned after it.
        let day = fx.at(2026, 2, 20)
        try assertRoundTrip(
            full: { ChecklistItem(title: "Evening walk", systemIcon: "figure.walk", done: true, sortOrder: 3) },
            blank: { ChecklistItem() },
            fields: [
                wrote("title", \.title, "Evening walk"),
                wrote("systemIcon", \.systemIcon, "figure.walk"),
                assigned("day", \.day, day),
                wrote("done", \.done, true),
                wrote("sortOrder", \.sortOrder, 3),
            ])
    }

    func test_b_roundTrip_WorkoutSession() throws {
        let date = fx.at(2026, 2, 18, 17, 20, 40)
        try assertRoundTrip(
            full: { WorkoutSession(id: fixedUUID(19), date: date, kind: .swim, focuses: [.chest, .arms],
                                   durationMinutes: 50, notes: "felt strong") },
            blank: { WorkoutSession() },
            fields: [
                wrote("id", \.id, fixedUUID(19)),
                wrote("date", \.date, date),
                wrote("typeRaw", \.typeRaw, "swim"),
                wrote("focusesRaw", \.focusesRaw, "chest,arms"),
                wrote("durationMinutes", \.durationMinutes, 50),
                wrote("notes", \.notes, "felt strong"),
            ],
            typed: { session in
                XCTAssertEqual(session.kind, .swim)
                XCTAssertEqual(session.focuses, [.chest, .arms])
            })
    }

    func test_b_roundTrip_ExerciseEntry() throws {
        let date = fx.at(2026, 2, 18, 17, 20, 40)
        try assertRoundTrip(
            full: { ExerciseEntry(id: fixedUUID(20), sessionID: fixedUUID(19), date: date, machineKey: "leg_press",
                                  displayName: "Leg press", iconName: "figure.strengthtraining.traditional",
                                  weightLbs: 182.5, reps: 8, sets: 4) },
            blank: { ExerciseEntry(sessionID: UUID()) },
            fields: [
                wrote("id", \.id, fixedUUID(20)),
                wrote("sessionID", \.sessionID, fixedUUID(19)),
                wrote("date", \.date, date),
                wrote("machineKey", \.machineKey, "leg_press"),
                wrote("displayName", \.displayName, "Leg press"),
                wrote("iconName", \.iconName, "figure.strengthtraining.traditional"),
                wrote("weightLbs", \.weightLbs, 182.5),
                wrote("reps", \.reps, 8),
                wrote("sets", \.sets, 4),
            ])
    }

    /// The app writes these columns through their typed accessors. What a setter stores must
    /// read back as the same case, and clearing an optional one must read back as nil.
    func test_b_typedSettersStoreValuesThatReadBackThroughTheTypedGetters() throws {
        let container = try TestStore.makeContainer()
        let writer = ModelContext(container)

        let profile = UserProfile()
        profile.sex = .male
        profile.activityLevel = .extraActive
        profile.pace = .steadyGain
        profile.unitSystem = .metric
        profile.themeStyle = .cool
        profile.companionAvatar = .bryan
        profile.homeGym = .usc
        let food = FoodEntry(name: "Soup")
        food.mealType = .lunch
        food.source = .barcode
        food.confidence = .high
        let workout = WorkoutEntry()
        workout.type = .yoga
        workout.focus = .core
        let link = BuddyLink(myUserID: "me", pairingCode: "VITA-0000")
        link.status = .linked
        let nudge = Nudge(fromUserID: "them", toUserID: "me")
        nudge.kind = .flex
        let snapshot = BuddySnapshot(ownerUserID: "them", displayName: "Alex")
        snapshot.characterMood = .sleepy
        let session = WorkoutSession()
        session.kind = .cycle
        session.focuses = [.back, .core]
        let plan = CoachPlan()
        let insight = PlanInsight(id: fixedUUID(91), title: "Water is up", body: "Four days in a row.", tone: .nudge)
        plan.insights = [insight]
        let models: [any PersistentModel] = [profile, food, workout, link, nudge, snapshot, session, plan]
        models.forEach { writer.insert($0) }
        try writer.save()

        let reader = ModelContext(container)
        let readProfile = try XCTUnwrap(reader.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual([readProfile.sexRaw, readProfile.activityLevelRaw, readProfile.paceRaw, readProfile.unitSystemRaw,
                        readProfile.themeStyleRaw, readProfile.companionAvatarRaw, readProfile.homeGymRaw],
                       ["male", "extraActive", "steadyGain", "metric", "cool", "bryan", "usc"])
        XCTAssertEqual(readProfile.sex, .male)
        XCTAssertEqual(readProfile.activityLevel, .extraActive)
        XCTAssertEqual(readProfile.pace, .steadyGain)
        XCTAssertEqual(readProfile.unitSystem, .metric)
        XCTAssertEqual(readProfile.themeStyle, .cool)
        XCTAssertEqual(readProfile.companionAvatar, .bryan)
        XCTAssertEqual(readProfile.homeGym, .usc)

        let readFood = try XCTUnwrap(reader.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual([readFood.mealTypeRaw, readFood.sourceRaw, readFood.confidenceRaw], ["lunch", "barcode", "high"])
        XCTAssertEqual(readFood.mealType, .lunch)
        XCTAssertEqual(readFood.source, .barcode)
        XCTAssertEqual(readFood.confidence, .high)

        let readWorkout = try XCTUnwrap(reader.fetch(FetchDescriptor<WorkoutEntry>()).first)
        XCTAssertEqual([readWorkout.typeRaw, readWorkout.focusRaw], ["yoga", "core"])
        XCTAssertEqual(readWorkout.type, .yoga)
        XCTAssertEqual(readWorkout.focus, .core)

        XCTAssertEqual(try XCTUnwrap(reader.fetch(FetchDescriptor<BuddyLink>()).first).status, .linked)
        XCTAssertEqual(try XCTUnwrap(reader.fetch(FetchDescriptor<Nudge>()).first).kind, .flex)
        XCTAssertEqual(try XCTUnwrap(reader.fetch(FetchDescriptor<BuddySnapshot>()).first).characterMood, .sleepy)
        let readSession = try XCTUnwrap(reader.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(readSession.focusesRaw, "back,core")
        XCTAssertEqual(readSession.kind, .cycle)
        XCTAssertEqual(readSession.focuses, [.back, .core])
        XCTAssertEqual(try XCTUnwrap(reader.fetch(FetchDescriptor<CoachPlan>()).first).insights, [insight])

        // Clearing the optional ones, through the rows just read, and reading them a third time.
        readProfile.homeGym = nil
        readFood.confidence = nil
        readWorkout.focus = nil
        try reader.save()
        let third = ModelContext(container)
        let clearedProfile = try XCTUnwrap(third.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(clearedProfile.homeGymRaw, "")
        XCTAssertNil(clearedProfile.homeGym)
        XCTAssertNil(try XCTUnwrap(third.fetch(FetchDescriptor<FoodEntry>()).first).confidenceRaw)
        XCTAssertNil(try XCTUnwrap(third.fetch(FetchDescriptor<WorkoutEntry>()).first).focus)
    }
}
