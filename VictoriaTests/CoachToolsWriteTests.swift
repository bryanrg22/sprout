import XCTest
import SwiftData
@testable import Victoria

/// Tests for the AI coach's agentic WRITE tools (`CoachTools`): the data-logging and
/// edit/delete/goal layer that lets Vita modify the user's real data, all validated in
/// Swift. The load-bearing guarantees:
///
///  - `parse(...)` is pure: it validates inputs against the profile + today's entries and
///    returns a friendly `.invalid` on anything bad (missing/negative/out-of-range, an
///    unknown meal, a not-found or ambiguous food name) — never a crash, never a silent
///    bad write.
///  - `apply(...)` performs the SAME model writes the manual UI does (FoodEntry like
///    AddFoodSheet, a WaterEntry added like the dashboard +, a WeightEntry like the weigh-in
///    sheet), into a fresh in-memory store.
///  - The safety contract holds: there is NO tool to lower a loss user's calorie/macro
///    target below the computed safe floor, and a NutritionSanity-flagged food still logs
///    (with a note) rather than being blocked.
///  - `requiresConfirm` encodes the risk policy correctly (quick logs auto-apply; destructive
///    or goal-changing actions confirm first).
@MainActor
final class CoachToolsWriteTests: XCTestCase {

    // MARK: - Helpers

    /// A fresh in-memory context holding every model the write tools touch.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([UserProfile.self, FoodEntry.self, WaterEntry.self, WeightEntry.self, CoachMemory.self, WorkoutEntry.self, WorkoutSession.self, ExerciseEntry.self, CoachPlan.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    /// The loss profile (the app's default user): female, light, relaxed loss.
    private func lossProfile() -> UserProfile {
        let p = UserProfile()
        p.sex = .female
        p.heightCm = NutritionMath.inToCm(65)
        p.activityLevel = .light
        p.pace = .relaxed                 // a loss pace
        p.startWeightLbs = 158
        p.goalWeightLbs = 140
        p.unitSystem = .imperial
        p.waterContainerOz = 16.9
        p.waterContainerLabel = "bottle"
        return p
    }

    /// A gain profile (Bryan), to exercise the direction-aware goal-weight guard.
    private func gainProfile() -> UserProfile {
        let p = UserProfile()
        p.sex = .male
        p.pace = .leanGain
        p.startWeightLbs = 150
        p.goalWeightLbs = 165
        return p
    }

    /// Convenience: parse and assert we got `.ok`, returning the request (or fail).
    private func expectOK(_ name: CoachTools.Name,
                          _ input: [String: Any],
                          profile: UserProfile,
                          todaysFoods: [FoodEntry] = [],
                          _ message: String = "",
                          file: StaticString = #filePath, line: UInt = #line) -> CoachTools.ParsedRequest? {
        switch CoachTools.parse(name: name.rawValue, input: input, profile: profile, todaysFoods: todaysFoods) {
        case .ok(let req): return req
        case .invalid(let why):
            XCTFail("expected .ok for \(name.rawValue) \(message) but got .invalid: \(why)", file: file, line: line)
            return nil
        }
    }

    /// Convenience: parse and assert we got `.invalid`, returning the reason (or fail).
    @discardableResult
    private func expectInvalid(_ name: CoachTools.Name,
                               _ input: [String: Any],
                               profile: UserProfile,
                               todaysFoods: [FoodEntry] = [],
                               _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) -> String {
        switch CoachTools.parse(name: name.rawValue, input: input, profile: profile, todaysFoods: todaysFoods) {
        case .ok(let req):
            XCTFail("expected .invalid for \(name.rawValue) \(message) but got .ok: \(req.confirmSummary)", file: file, line: line)
            return ""
        case .invalid(let why):
            return why
        }
    }

    // MARK: - log_workout (Vita writes the rich Workouts-tab model: WorkoutSession + ExerciseEntry)

    /// A full gym day: kind + focuses + an exercises list. One WorkoutSession is written, plus one
    /// ExerciseEntry per move, with known machines resolved to their catalog key/icon and an unknown
    /// move slugged with the dumbbell fallback. Undo removes the session AND every exercise.
    func testLogWorkoutGymWritesSessionAndExercisesWithUndo() throws {
        let ctx = try makeContext()
        let profile = lossProfile()
        guard let req = expectOK(.logWorkout, [
            "kind": "gym",
            "minutes": 50,
            "focuses": ["chest", "arms"],
            "notes": "felt strong",
            "exercises": [
                ["name": "Chest press", "weight_lbs": 90, "reps": 10, "sets": 3],
                ["name": "Incline dumbbell press", "weight_lbs": 50],   // reps/sets default 10/3
                ["name": "Cable tricep thingy"],                        // off-catalog → slug + fallback
            ],
        ], profile: profile) else { return }
        XCTAssertFalse(req.requiresConfirm)   // quick, reversible log → auto-apply with Undo

        let applied = CoachTools.applyReturningUndo(req, to: profile, context: ctx)

        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.kind, .gym)
        XCTAssertEqual(session.focuses, [.chest, .arms])
        XCTAssertEqual(session.durationMinutes, 50)
        XCTAssertEqual(session.notes, "felt strong")

        let exercises = try ctx.fetch(FetchDescriptor<ExerciseEntry>()).filter { $0.sessionID == session.id }
        XCTAssertEqual(exercises.count, 3)
        // Known machine resolves to its catalog key + icon.
        let chest = try XCTUnwrap(exercises.first { $0.displayName == "Chest press" })
        XCTAssertEqual(chest.machineKey, "chest_press")
        XCTAssertEqual(chest.weightLbs, 90)
        XCTAssertEqual(chest.reps, 10)
        XCTAssertEqual(chest.sets, 3)
        // Defaults applied where weight/reps/sets weren't given.
        let incline = try XCTUnwrap(exercises.first { $0.displayName == "Incline dumbbell press" })
        XCTAssertEqual(incline.machineKey, "incline_db_press")
        XCTAssertEqual(incline.weightLbs, 50)
        XCTAssertEqual(incline.reps, 10)
        XCTAssertEqual(incline.sets, 3)
        // Off-catalog move → slugged key + dumbbell fallback icon.
        let custom = try XCTUnwrap(exercises.first { $0.displayName == "Cable tricep thingy" })
        XCTAssertEqual(custom.machineKey, "cable_tricep_thingy")
        XCTAssertEqual(custom.iconName, "dumbbell.fill")

        applied.undo?()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WorkoutSession>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<ExerciseEntry>()).count, 0)
    }

    /// A bare cardio log (kind only) writes a session with no exercises; the legacy `type` key is
    /// still accepted and mapped onto a WorkoutKind, and cardio never carries focuses/exercises.
    func testLogWorkoutKindOnlyAndLegacyTypeFallback() throws {
        let ctx = try makeContext()
        let profile = lossProfile()

        guard let run = expectOK(.logWorkout, ["kind": "run"], profile: profile) else { return }
        _ = CoachTools.applyReturningUndo(run, to: profile, context: ctx)
        // Legacy `type: "strength"` maps to the gym kind; focuses on a cardio kind are ignored.
        guard let legacy = expectOK(.logWorkout, ["type": "strength"], profile: profile) else { return }
        _ = CoachTools.applyReturningUndo(legacy, to: profile, context: ctx)
        guard let walkWithStrayFocus = expectOK(.logWorkout, ["kind": "walk", "focuses": ["legs"]], profile: profile) else { return }
        _ = CoachTools.applyReturningUndo(walkWithStrayFocus, to: profile, context: ctx)

        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>()).sorted { $0.date < $1.date }
        XCTAssertEqual(sessions.map(\.kind), [.run, .gym, .walk])
        XCTAssertEqual(sessions[0].durationMinutes, 0)   // minutes optional → 0
        XCTAssertTrue(sessions.last?.focuses.isEmpty ?? false)   // cardio focuses dropped
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<ExerciseEntry>()).count, 0)   // no exercises on cardio
    }

    /// Back-dating: a `date` of "yesterday" lands the session (and any exercises) on yesterday.
    func testLogWorkoutBackdatesToYesterday() throws {
        let ctx = try makeContext()
        let profile = lossProfile()
        guard let req = expectOK(.logWorkout, [
            "kind": "gym", "date": "yesterday",
            "exercises": [["name": "Leg press"]],
        ], profile: profile) else { return }
        _ = CoachTools.applyReturningUndo(req, to: profile, context: ctx)

        let cal = Calendar.current
        let session = try XCTUnwrap(ctx.fetch(FetchDescriptor<WorkoutSession>()).first)
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        XCTAssertTrue(cal.isDate(session.date, inSameDayAs: yesterday))
        let entry = try XCTUnwrap(ctx.fetch(FetchDescriptor<ExerciseEntry>()).first)
        XCTAssertTrue(cal.isDate(entry.date, inSameDayAs: yesterday))   // entry date denormalized from session
    }

    func testLogWorkoutRejectsUnknownKindAndAbsurdDuration() {
        _ = expectInvalid(.logWorkout, ["kind": "underwater-basket-weaving"], profile: lossProfile())
        _ = expectInvalid(.logWorkout, ["kind": "gym", "minutes": 99999], profile: lossProfile())
    }

    // MARK: - edit_plan + forget_about_user (Vita edits the plan + profile docs)

    func testEditPlanUpdatesOnlyGivenFieldsWithUndo() throws {
        let ctx = try makeContext()
        let profile = lossProfile()
        let plan = CoachPlan(headline: "Old", calorieMin: 1600, calorieMax: 1750, proteinTarget: 120)
        ctx.insert(plan); try? ctx.save()

        guard let req = expectOK(.editPlan,
                                 ["protein_target": 150, "calorie_max": 1800, "change_note": "Bumped protein + ceiling"],
                                 profile: profile) else { return }
        XCTAssertTrue(req.requiresConfirm, "a target change confirms like the other goal tools")
        let applied = CoachTools.applyReturningUndo(req, to: profile, context: ctx)

        let updated = try XCTUnwrap(CoachPlan.current(in: ctx))
        XCTAssertEqual(updated.proteinTarget, 150)
        XCTAssertEqual(updated.calorieMax, 1800)
        XCTAssertEqual(updated.calorieMin, 1600)                                  // untouched
        XCTAssertTrue(updated.changelog.last?.summary.contains("Bumped protein") ?? false)

        applied.undo?()
        let reverted = try XCTUnwrap(CoachPlan.current(in: ctx))
        XCTAssertEqual(reverted.proteinTarget, 120)
        XCTAssertEqual(reverted.calorieMax, 1750)
    }

    func testSetProteinGoalWithPlanWritesToPlanSoItSticks() throws {
        // P2 fix: when a Plan exists, set_protein_goal must write the target ONTO the plan (not just
        // the profile override) — else RootView.syncPlanTargets re-derives the override from the
        // unchanged plan on the next launch and silently reverts it. Verify the plan carries the goal.
        let ctx = try makeContext()
        let profile = lossProfile()
        let plan = CoachPlan(headline: "Old", calorieMin: 1600, calorieMax: 1750, proteinTarget: 120)
        ctx.insert(plan); try? ctx.save()

        guard let req = expectOK(.setProteinGoal, ["grams": 140], profile: profile) else { return }
        let applied = CoachTools.applyReturningUndo(req, to: profile, context: ctx)

        let updated = try XCTUnwrap(CoachPlan.current(in: ctx))
        XCTAssertEqual(updated.proteinTarget, 140, "goal must be written onto the plan so a re-sync keeps it")
        XCTAssertEqual(profile.proteinTargetOverride, 140, "override mirrors the plan value immediately")

        applied.undo?()
        let reverted = try XCTUnwrap(CoachPlan.current(in: ctx))
        XCTAssertEqual(reverted.proteinTarget, 120, "undo restores the plan's protein target")
        // The override reverts to its pre-apply value (0 here — RootView.syncPlanTargets, which would
        // have mirrored the plan's 120 onto it for a real plan-user, doesn't run in a unit test).
        XCTAssertEqual(profile.proteinTargetOverride, 0)
    }

    func testSetProteinGoalWithNoPlanWritesOverrideDirectly() throws {
        let ctx = try makeContext()
        let profile = lossProfile()
        let original = profile.proteinTargetOverride
        guard let req = expectOK(.setProteinGoal, ["grams": 130], profile: profile) else { return }
        let applied = CoachTools.applyReturningUndo(req, to: profile, context: ctx)
        XCTAssertEqual(profile.proteinTargetOverride, 130)
        XCTAssertNil(CoachPlan.current(in: ctx), "no plan should have been created")
        applied.undo?()
        XCTAssertEqual(profile.proteinTargetOverride, original)
    }

    func testEditPlanRejectsInvertedRange() {
        _ = expectInvalid(.editPlan, ["calorie_min": 2000, "calorie_max": 1500, "change_note": "x"], profile: lossProfile())
    }

    /// A target change (calorie/protein) must show the Yes/Not-now card, and the card names the new
    /// number — matching set_water_goal / set_weight_goal.
    func testEditPlanTargetChangeConfirmsAndNamesTheTarget() {
        let req = expectOK(.editPlan, ["protein_target": 150, "change_note": "x"], profile: lossProfile())
        XCTAssertEqual(req?.requiresConfirm, true)
        XCTAssertTrue(req?.confirmSummary.contains("150") ?? false, "card should name the new target")
    }

    /// A prose-only tweak (no targets) stays a quick auto-apply with Undo — no confirm card.
    func testEditPlanProseOnlyTweakAutoApplies() {
        let req = expectOK(.editPlan, ["headline": "Fresh start", "change_note": "reworded the read"],
                           profile: lossProfile())
        XCTAssertEqual(req?.requiresConfirm, false)
    }

    func testEditPlanWithNoPlanIsGracious() throws {
        let ctx = try makeContext()
        guard let req = expectOK(.editPlan, ["protein_target": 150, "change_note": "x"], profile: lossProfile()) else { return }
        let applied = CoachTools.applyReturningUndo(req, to: lossProfile(), context: ctx)
        XCTAssertTrue(applied.message.contains("doesn't have a plan yet"))
        XCTAssertNil(applied.undo)
    }

    func testForgetRemovesMatchingProfileNoteWithUndo() throws {
        let ctx = try makeContext()
        let profile = lossProfile()
        let memory = CoachMemory.fetchOrCreate(in: ctx, profile: profile)
        memory.profileNotes = "Takes creatine\nWorks at NVIDIA 9-5\nVegetarian"
        try? ctx.save()

        guard let req = expectOK(.forgetFact, ["fact": "creatine"], profile: profile) else { return }
        let applied = CoachTools.applyReturningUndo(req, to: profile, context: ctx)
        let m = CoachMemory.fetchOrCreate(in: ctx, profile: profile)
        XCTAssertFalse(m.profileNotes.contains("creatine"))
        XCTAssertTrue(m.profileNotes.contains("NVIDIA"))                          // other notes survive

        applied.undo?()
        XCTAssertTrue(CoachMemory.fetchOrCreate(in: ctx, profile: profile).profileNotes.contains("creatine"))
    }

    func testForgetWhenNothingMatchesIsGracious() throws {
        let ctx = try makeContext()
        let profile = lossProfile()
        let memory = CoachMemory.fetchOrCreate(in: ctx, profile: profile)
        memory.profileNotes = "Vegetarian"
        try? ctx.save()
        guard let req = expectOK(.forgetFact, ["fact": "creatine"], profile: profile) else { return }
        let applied = CoachTools.applyReturningUndo(req, to: profile, context: ctx)
        XCTAssertTrue(applied.message.contains("didn't find"))
        XCTAssertNil(applied.undo)
    }

    /// A too-broad `fact` ("i") is rejected at parse time before it can match — and wipe — every note.
    func testForgetRejectsTooVagueFact() {
        let why = expectInvalid(.forgetFact, ["fact": "i"], profile: lossProfile())
        XCTAssertTrue(why.lowercased().contains("specific") || why.lowercased().contains("broad"))
    }

    /// Insert a food entry into the context for today (so lookup tools can find it).
    @discardableResult
    private func seedFood(_ name: String,
                          meal: MealType = .lunch,
                          calories: Double = 400,
                          protein: Double = 30,
                          carbs: Double = 40,
                          fat: Double = 12,
                          in context: ModelContext) -> FoodEntry {
        let e = FoodEntry(date: .now, mealType: meal, name: name,
                          calories: calories, proteinG: protein, carbsG: carbs, fatG: fat)
        context.insert(e)
        try? context.save()
        return e
    }

    // MARK: - Unknown tool / existing tools unchanged

    func testUnknownToolIsInvalid() {
        switch CoachTools.parse(name: "definitely_not_a_tool", input: [:], profile: lossProfile()) {
        case .invalid(let why): XCTAssertTrue(why.contains("Unknown tool"))
        case .ok: XCTFail("an unknown tool must be .invalid")
        }
    }

    func testSchemasIncludeAllToolsExactlyOnce() {
        let schemas = CoachTools.schemas(for: lossProfile())
        let names = schemas.compactMap { $0["name"] as? String }
        // Every case in the enum should be advertised, with no dupes.
        for tool in CoachTools.Name.allCases {
            XCTAssertTrue(names.contains(tool.rawValue), "schema missing for \(tool.rawValue)")
        }
        XCTAssertEqual(Set(names).count, names.count, "no duplicate tool schemas")
        XCTAssertEqual(names.count, CoachTools.Name.allCases.count, "schema count should equal tool count")
    }

    /// Regression: the original three settings tools still parse + apply as before.
    func testExistingStepGoalToolStillWorks() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let req = try XCTUnwrap(expectOK(.setStepGoal, ["steps": 12000], profile: p))
        XCTAssertTrue(req.action.isStepGoal12k)
        XCTAssertTrue(req.requiresConfirm, "a goal change must require confirm")
        _ = CoachTools.apply(req, to: p, context: ctx)
        XCTAssertEqual(p.dailyStepGoal, 12000)
    }

    // MARK: - log_food

    func testLogFoodParsesAndAppliesLikeManualAdd() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let input: [String: Any] = [
            "name": "Chicken bowl", "meal": "lunch",
            "calories": 600, "protein_g": 45, "carbs_g": 50, "fat_g": 20, "quantity": 1,
        ]
        let req = try XCTUnwrap(expectOK(.logFood, input, profile: p))
        XCTAssertFalse(req.requiresConfirm, "a quick food log should auto-apply (Undo)")

        let result = CoachTools.apply(req, to: p, context: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(foods.count, 1)
        let e = foods[0]
        XCTAssertEqual(e.name, "Chicken bowl")
        XCTAssertEqual(e.mealType, .lunch)
        XCTAssertEqual(e.calories, 600, accuracy: 0.001)
        XCTAssertEqual(e.proteinG, 45, accuracy: 0.001)
        XCTAssertEqual(e.source, .manual, "coach-logged food is recorded as a manual add")
        XCTAssertTrue(Calendar.current.isDateInToday(e.date))
        XCTAssertNil(e.notes, "a plausible item carries no sanity note")
        XCTAssertTrue(result.contains("Logged"))
    }

    func testLogFoodDefaultsQuantityToOneWhenOmitted() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let input: [String: Any] = [
            "name": "Apple", "meal": "snack",
            "calories": 95, "protein_g": 0, "carbs_g": 25, "fat_g": 0,
        ]
        let req = try XCTUnwrap(expectOK(.logFood, input, profile: p))
        _ = CoachTools.apply(req, to: p, context: ctx)
        let e = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(e.quantity, 1, "omitted quantity defaults to 1")
    }

    /// Regression for the review's HIGH finding: calories/macros are PER SERVING and quantity
    /// multiplies them — so "two bowls, 600 cal each" is 1200 total, NOT 2400 (no double-count),
    /// and the confirm summary the user sees reports the real total.
    func testLogFoodQuantityIsPerServingNotDoubleCounted() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let req = try XCTUnwrap(expectOK(.logFood,
            ["name": "Chicken bowl", "meal": "lunch",
             "calories": 600, "protein_g": 45, "carbs_g": 50, "fat_g": 20, "quantity": 2],
            profile: p))
        XCTAssertTrue(req.confirmSummary.contains("1200"), "summary shows the TOTAL; got: \(req.confirmSummary)")
        XCTAssertTrue(req.confirmSummary.contains("×2"))
        _ = CoachTools.apply(req, to: p, context: ctx)
        let e = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(e.calories, 600, accuracy: 0.001, "stored calories stay per-serving")
        XCTAssertEqual(e.quantity, 2, accuracy: 0.001)
        XCTAssertEqual(e.totalCalories, 1200, accuracy: 0.001, "total = per-serving × quantity")
        XCTAssertEqual(e.totalProteinG, 90, accuracy: 0.001)
    }

    func testLogFoodMissingNameIsInvalid() {
        let why = expectInvalid(.logFood,
                                ["meal": "lunch", "calories": 300, "protein_g": 10, "carbs_g": 30, "fat_g": 5],
                                profile: lossProfile())
        XCTAssertTrue(why.lowercased().contains("name"))
    }

    func testLogFoodBadMealIsInvalid() {
        expectInvalid(.logFood,
                      ["name": "X", "meal": "brunch", "calories": 300, "protein_g": 10, "carbs_g": 30, "fat_g": 5],
                      profile: lossProfile(), "an unknown meal must be rejected")
    }

    func testLogFoodNegativeMacroIsInvalid() {
        expectInvalid(.logFood,
                      ["name": "X", "meal": "lunch", "calories": 300, "protein_g": -10, "carbs_g": 30, "fat_g": 5],
                      profile: lossProfile(), "a negative macro must be rejected")
    }

    /// A NutritionSanity-flagged item (macros wildly disagree with calories) STILL logs,
    /// but the entry + the tool_result both carry a note. This is the key "don't block" rule.
    func testLogFoodFlaggedByNutritionSanityStillLogsWithNote() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        // 100 kcal stated, but 50g protein + 50g carbs + 30g fat ≈ 670 kcal → way off.
        let input: [String: Any] = [
            "name": "Mystery plate", "meal": "dinner",
            "calories": 100, "protein_g": 50, "carbs_g": 50, "fat_g": 30,
        ]
        let req = try XCTUnwrap(expectOK(.logFood, input, profile: p))
        let result = CoachTools.apply(req, to: p, context: ctx)

        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(foods.count, 1, "a flagged item must STILL be logged, never blocked")
        XCTAssertNotNil(foods[0].notes, "the flagged entry should carry a note")
        XCTAssertTrue(result.contains("Note:"), "the tool_result should surface the sanity note")
    }

    func testNutritionSanityPassesAConsistentItem() {
        // 600 kcal vs 45·4 + 50·4 + 20·9 = 560 kcal → within the loose tolerance.
        let c = NutritionSanity.check(calories: 600, protein: 45, carbs: 50, fat: 20)
        XCTAssertFalse(c.isSuspicious)
        XCTAssertNil(c.reason)
    }

    func testNutritionSanityFlagsCalorieMacroMismatch() {
        let c = NutritionSanity.check(calories: 100, protein: 50, carbs: 50, fat: 30)
        XCTAssertTrue(c.isSuspicious)
        XCTAssertNotNil(c.reason)
    }

    func testNutritionSanityAllowsPlainQuickAddNoMacros() {
        // "100 kcal, no macros" (a quick add) must not be flagged — nothing to compare.
        let c = NutritionSanity.check(calories: 100, protein: 0, carbs: 0, fat: 0)
        XCTAssertFalse(c.isSuspicious)
    }

    // MARK: - edit_food

    func testEditFoodUpdatesTheRightEntry() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let latte = seedFood("Latte", meal: .breakfast, calories: 190, protein: 8, carbs: 18, fat: 7, in: ctx)
        _ = seedFood("Salad", meal: .lunch, in: ctx)  // a decoy that must NOT change

        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let req = try XCTUnwrap(expectOK(.editFood,
                                         ["name": "latte", "calories": 250],
                                         profile: p, todaysFoods: foods))
        XCTAssertFalse(req.requiresConfirm, "an edit should auto-apply (Undo)")
        _ = CoachTools.apply(req, to: p, context: ctx)

        XCTAssertEqual(latte.calories, 250, accuracy: 0.001, "only the matched entry changes")
        let salad = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FoodEntry>()).first { $0.name == "Salad" })
        XCTAssertEqual(salad.calories, 400, accuracy: 0.001, "the decoy must be untouched")
    }

    func testEditFoodCanChangeNameAndMeal() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let e = seedFood("Burrito", meal: .dinner, in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let req = try XCTUnwrap(expectOK(.editFood,
                                         ["name": "Burrito", "new_name": "Burrito bowl", "meal": "lunch"],
                                         profile: p, todaysFoods: foods))
        _ = CoachTools.apply(req, to: p, context: ctx)
        XCTAssertEqual(e.name, "Burrito bowl")
        XCTAssertEqual(e.mealType, .lunch)
    }

    func testEditFoodNotFoundIsInvalid() throws {
        let ctx = try makeContext()
        _ = seedFood("Latte", in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let why = expectInvalid(.editFood, ["name": "pizza", "calories": 500],
                                profile: lossProfile(), todaysFoods: foods)
        XCTAssertTrue(why.lowercased().contains("couldn't find"))
    }

    func testEditFoodAmbiguousNameIsInvalid() throws {
        let ctx = try makeContext()
        seedFood("Coffee", in: ctx)
        seedFood("Coffee", in: ctx)   // two exact matches → ambiguous
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let why = expectInvalid(.editFood, ["name": "coffee", "calories": 50],
                                profile: lossProfile(), todaysFoods: foods)
        XCTAssertTrue(why.lowercased().contains("which one"))
    }

    func testEditFoodNoChangesIsInvalid() throws {
        let ctx = try makeContext()
        seedFood("Toast", in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        // Found the item, but no editable field supplied → a no-op edit is rejected.
        let why = expectInvalid(.editFood, ["name": "Toast"], profile: lossProfile(), todaysFoods: foods)
        XCTAssertTrue(why.lowercased().contains("what to change"))
    }

    func testEditFoodEmptyTodayIsInvalid() {
        let why = expectInvalid(.editFood, ["name": "anything", "calories": 100],
                                profile: lossProfile(), todaysFoods: [])
        XCTAssertTrue(why.lowercased().contains("nothing"))
    }

    func testEditFoodNegativeValueIsInvalid() throws {
        let ctx = try makeContext()
        seedFood("Rice", in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        expectInvalid(.editFood, ["name": "Rice", "protein_g": -5],
                      profile: lossProfile(), todaysFoods: foods, "negative edit rejected")
    }

    // MARK: - delete_food

    func testDeleteFoodRemovesTheRightEntry() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        seedFood("Fries", in: ctx)
        seedFood("Burger", in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let req = try XCTUnwrap(expectOK(.deleteFood, ["name": "Fries"], profile: p, todaysFoods: foods))
        XCTAssertTrue(req.requiresConfirm, "delete is destructive → must confirm")
        _ = CoachTools.apply(req, to: p, context: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.name, "Burger", "only the named item is removed")
    }

    func testDeleteFoodNotFoundIsInvalid() throws {
        let ctx = try makeContext()
        seedFood("Soup", in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        expectInvalid(.deleteFood, ["name": "steak"], profile: lossProfile(), todaysFoods: foods,
                      "deleting a missing item must be invalid")
    }

    // MARK: - log_water

    func testLogWaterByContainersConvertsToOzAndAdds() throws {
        let ctx = try makeContext()
        let p = lossProfile()   // container = 16.9 oz
        let req = try XCTUnwrap(expectOK(.logWater, ["containers": 2], profile: p))
        XCTAssertFalse(req.requiresConfirm)
        _ = CoachTools.apply(req, to: p, context: ctx)
        let waters = try ctx.fetch(FetchDescriptor<WaterEntry>())
        XCTAssertEqual(waters.count, 1)
        XCTAssertEqual(waters[0].amountOz, 2 * 16.9, accuracy: 0.001, "2 bottles → 33.8 oz")
    }

    func testLogWaterByOzAddsThatAmount() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let req = try XCTUnwrap(expectOK(.logWater, ["oz": 20], profile: p))
        _ = CoachTools.apply(req, to: p, context: ctx)
        let waters = try ctx.fetch(FetchDescriptor<WaterEntry>())
        XCTAssertEqual(waters[0].amountOz, 20, accuracy: 0.001)
    }

    func testLogWaterAddsRatherThanReplaces() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        // Pre-existing water today; a new log must ADD a second entry (the app aggregates).
        ctx.insert(WaterEntry(amountOz: 16.9))
        try ctx.save()
        let req = try XCTUnwrap(expectOK(.logWater, ["oz": 8], profile: p))
        _ = CoachTools.apply(req, to: p, context: ctx)
        let waters = try ctx.fetch(FetchDescriptor<WaterEntry>())
        XCTAssertEqual(waters.count, 2, "logging water adds an entry, never overwrites")
        XCTAssertEqual(waters.reduce(0) { $0 + $1.amountOz }, 24.9, accuracy: 0.001)
    }

    func testLogWaterWithNeitherInputIsInvalid() {
        expectInvalid(.logWater, [:], profile: lossProfile(), "needs containers or oz")
    }

    func testLogWaterOutOfRangeOzIsInvalid() {
        expectInvalid(.logWater, ["oz": 9999], profile: lossProfile(), "absurd oz rejected")
    }

    // MARK: - log_weight

    func testLogWeightCreatesEntryStoredAsEntered() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let req = try XCTUnwrap(expectOK(.logWeight, ["weight": 152.4], profile: p))
        XCTAssertFalse(req.requiresConfirm, "a weigh-in auto-applies (Undo)")
        _ = CoachTools.apply(req, to: p, context: ctx)
        let weights = try ctx.fetch(FetchDescriptor<WeightEntry>())
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual(weights[0].weightLbs, 152.4, accuracy: 0.001, "stored as the entered number")
        XCTAssertEqual(weights[0].source, "manual")
    }

    func testLogWeightOutOfRangeIsInvalid() {
        expectInvalid(.logWeight, ["weight": 12], profile: lossProfile(), "below the floor is rejected")
        expectInvalid(.logWeight, ["weight": 900], profile: lossProfile(), "above the ceiling is rejected")
    }

    func testLogWeightMissingValueIsInvalid() {
        expectInvalid(.logWeight, [:], profile: lossProfile())
    }

    // MARK: - set_weight_goal (direction-aware, target only)

    func testSetWeightGoalLossMustBeBelowCurrent() throws {
        let ctx = try makeContext()
        let p = lossProfile()  // start 158, losing
        let req = try XCTUnwrap(expectOK(.setWeightGoal, ["weight": 145], profile: p))
        XCTAssertTrue(req.requiresConfirm, "a goal change must confirm")
        _ = CoachTools.apply(req, to: p, context: ctx)
        XCTAssertEqual(p.goalWeightLbs, 145, accuracy: 0.001)
    }

    func testSetWeightGoalLossAboveCurrentIsInvalid() {
        let p = lossProfile()  // start 158, losing
        let why = expectInvalid(.setWeightGoal, ["weight": 170], profile: p)
        XCTAssertTrue(why.lowercased().contains("below"), "a loss goal above current is contradictory")
    }

    func testSetWeightGoalGainMustBeAboveCurrent() throws {
        let ctx = try makeContext()
        let p = gainProfile()  // start 150, gaining
        let req = try XCTUnwrap(expectOK(.setWeightGoal, ["weight": 170], profile: p))
        _ = CoachTools.apply(req, to: p, context: ctx)
        XCTAssertEqual(p.goalWeightLbs, 170, accuracy: 0.001)
    }

    func testSetWeightGoalGainBelowCurrentIsInvalid() {
        let p = gainProfile()
        let why = expectInvalid(.setWeightGoal, ["weight": 130], profile: p)
        XCTAssertTrue(why.lowercased().contains("above"))
    }

    func testSetWeightGoalOutOfBoundsIsInvalid() {
        expectInvalid(.setWeightGoal, ["weight": 20], profile: lossProfile(), "absurd goal rejected")
    }

    // MARK: - The safety floor: NO tool can drop a loss user's intake below the floor

    /// The computed calorie target for a loss user is held at the safe floor; nothing in the
    /// tool surface lets the coach push it lower. We assert (a) the floor holds in the math
    /// the targets read, and (b) there is deliberately no calorie/macro-target tool to bypass it.
    func testNoToolCanLowerLossTargetBelowSafeFloor() {
        // (a) A petite, sedentary, ambitious dieter still floors at 1200 (female).
        let p = UserProfile()
        p.sex = .female
        p.heightCm = NutritionMath.inToCm(60)
        p.activityLevel = .sedentary
        p.pace = .ambitious
        p.startWeightLbs = 110
        let goal = p.calorieGoal(weightLbs: 110)
        XCTAssertGreaterThanOrEqual(goal.dailyCalories, 1200, "female safe floor must hold")
        XCTAssertTrue(goal.wasClampedToFloor, "the requested deficit was clamped to the floor")

        // (b) No tool name targets calories/macros — the only intake lever is pace, which is
        // itself floor-protected by the same computation above.
        let toolNames = CoachTools.Name.allCases.map { $0.rawValue }
        XCTAssertFalse(toolNames.contains { $0.contains("calorie") || $0.contains("macro") },
                       "there must be NO calorie/macro-target tool (no eat-less lever)")
    }

    /// `set_pace` can only ever offer paces in the user's own direction (plus Maintain), so a
    /// loss user can't be flipped onto a gain pace — and every offered pace stays floored by
    /// the calorie math. A pace from the wrong direction is rejected.
    func testSetPaceCannotCrossDirection() {
        let p = lossProfile()  // a loss user
        expectInvalid(.setPace, ["pace": GoalPace.leanGain.rawValue], profile: p,
                      "a gain pace must be rejected for a loss user")
        // And a valid in-direction pace is accepted.
        _ = expectOK(.setPace, ["pace": GoalPace.steady.rawValue], profile: p)
    }

    // MARK: - requiresConfirm mapping (one assertion per tool)

    func testRequiresConfirmMappingIsCorrect() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let food = seedFood("Latte", in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())

        // Auto-apply (false): quick, reversible logs.
        XCTAssertEqual(expectOK(.logFood,
                                ["name": "X", "meal": "snack", "calories": 100, "protein_g": 0, "carbs_g": 25, "fat_g": 0],
                                profile: p)?.requiresConfirm, false)
        XCTAssertEqual(expectOK(.editFood, ["name": "Latte", "calories": 200], profile: p, todaysFoods: foods)?.requiresConfirm, false)
        XCTAssertEqual(expectOK(.logWater, ["containers": 1], profile: p)?.requiresConfirm, false)
        XCTAssertEqual(expectOK(.logWeight, ["weight": 150], profile: p)?.requiresConfirm, false)

        // Confirm-first (true): destructive or goal-changing.
        XCTAssertEqual(expectOK(.deleteFood, ["name": "Latte"], profile: p, todaysFoods: foods)?.requiresConfirm, true)
        XCTAssertEqual(expectOK(.setPace, ["pace": GoalPace.steady.rawValue], profile: p)?.requiresConfirm, true)
        XCTAssertEqual(expectOK(.setStepGoal, ["steps": 9000], profile: p)?.requiresConfirm, true)
        XCTAssertEqual(expectOK(.setWaterGoalContainers, ["count": 8], profile: p)?.requiresConfirm, true)
        XCTAssertEqual(expectOK(.setWeightGoal, ["weight": 150], profile: p)?.requiresConfirm, true)

        _ = food  // silence unused in case the seed is optimized
    }

    // MARK: - Undo (applyReturningUndo exactly reverses the auto-applied write)

    func testUndoLogFoodDeletesTheEntry() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let req = try XCTUnwrap(expectOK(.logFood,
            ["name": "Bagel", "meal": "breakfast", "calories": 280, "protein_g": 10, "carbs_g": 55, "fat_g": 2],
            profile: p))
        let applied = CoachTools.applyReturningUndo(req, to: p, context: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).count, 1)
        let undo = try XCTUnwrap(applied.undo, "a food log must be undoable")
        undo()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).count, 0, "undo removes the logged entry")
    }

    func testUndoEditFoodRestoresPriorValues() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let e = seedFood("Latte", meal: .breakfast, calories: 190, protein: 8, in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let req = try XCTUnwrap(expectOK(.editFood, ["name": "Latte", "calories": 250, "meal": "lunch"],
                                         profile: p, todaysFoods: foods))
        _ = CoachTools.applyReturningUndo(req, to: p, context: ctx).undo.map { undo in
            XCTAssertEqual(e.calories, 250, accuracy: 0.001)   // change applied
            XCTAssertEqual(e.mealType, .lunch)
            undo()                                              // then reversed
        }
        XCTAssertEqual(e.calories, 190, accuracy: 0.001, "undo restores the old calories")
        XCTAssertEqual(e.mealType, .breakfast, "undo restores the old meal")
    }

    func testUndoLogWaterDeletesTheEntry() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let req = try XCTUnwrap(expectOK(.logWater, ["oz": 16], profile: p))
        let applied = CoachTools.applyReturningUndo(req, to: p, context: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WaterEntry>()).count, 1)
        try XCTUnwrap(applied.undo)()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WaterEntry>()).count, 0, "undo removes the water entry")
    }

    func testDeleteFoodHasNoUndoBanner() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        seedFood("Fries", in: ctx)
        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let req = try XCTUnwrap(expectOK(.deleteFood, ["name": "Fries"], profile: p, todaysFoods: foods))
        XCTAssertNil(CoachTools.applyReturningUndo(req, to: p, context: ctx).undo,
                     "delete is confirm-gated, so it offers no auto-Undo")
    }

    // MARK: - remember_about_user (durable profile memory — the "update my profile" fix)

    func testRememberFactWritesToDurableNotes() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let req = try XCTUnwrap(expectOK(.rememberFact, ["note": "takes creatine daily"], profile: p))
        XCTAssertFalse(req.requiresConfirm, "saving a note auto-applies (no confirm)")
        _ = CoachTools.apply(req, to: p, context: ctx)
        let mem = CoachMemory.fetchOrCreate(in: ctx, profile: p)
        XCTAssertTrue(mem.profileNotes.contains("takes creatine daily"),
                      "the fact persists to durable notes; got: \(mem.profileNotes)")
    }

    func testRememberFactBlankIsInvalid() {
        expectInvalid(.rememberFact, ["note": "   "], profile: lossProfile(), "a blank note is rejected")
    }

    func testRememberFactUndoRestoresNotes() throws {
        let ctx = try makeContext()
        let p = lossProfile()
        let mem0 = CoachMemory.fetchOrCreate(in: ctx, profile: p)
        mem0.profileNotes = "- prior note"
        try ctx.save()
        let req = try XCTUnwrap(expectOK(.rememberFact, ["note": "on creatine"], profile: p))
        let applied = CoachTools.applyReturningUndo(req, to: p, context: ctx)
        XCTAssertTrue(CoachMemory.fetchOrCreate(in: ctx, profile: p).profileNotes.contains("on creatine"))
        try XCTUnwrap(applied.undo)()
        let after = CoachMemory.fetchOrCreate(in: ctx, profile: p).profileNotes
        XCTAssertFalse(after.contains("on creatine"), "undo removes the just-added note")
        XCTAssertTrue(after.contains("prior note"), "the prior note is preserved")
    }

    // MARK: - forget_about_user: surgical removal (no collateral damage)

    func testRemovingFactDropsOnlyTheMatchingBulletLine() {
        let notes = "- takes creatine daily\n- sees a nutritionist\n- works night shifts"
        XCTAssertEqual(CoachTools.removingFact("creatine", from: notes),
                       "- sees a nutritionist\n- works night shifts")
    }

    /// The onboarding seed is a SINGLE comma-joined line — forgetting one fact must strip only that
    /// clause, not annihilate the whole line (the original substring filter did the latter).
    func testRemovingFactStripsOneClauseFromCommaJoinedSeed() throws {
        let seed = "From her onboarding note: vegetarian, has two kids, allergic to peanuts"
        let out = try XCTUnwrap(CoachTools.removingFact("peanuts", from: seed))
        XCTAssertFalse(out.contains("peanuts"))
        XCTAssertTrue(out.contains("has two kids"))     // siblings survive
        XCTAssertTrue(out.contains("vegetarian"))
    }

    /// Whole-word matching: "art" must NOT delete "startup" (raw substring containment would have).
    func testRemovingFactUsesWordBoundariesNotSubstring() {
        let notes = "- works at a startup\n- training for a marathon"
        XCTAssertNil(CoachTools.removingFact("art", from: notes))
    }

    /// Inflection tolerance (found live): "desk job" must match a stored "desk jobs" (plural), while
    /// the unrelated "startup" line is left untouched. This is the desk-job/desk-jobs miss.
    func testRemovingFactToleratesPluralInflection() throws {
        let notes = "- I work a 9 to 5 desk jobs and train after\n- runs a startup on the side"
        let out = try XCTUnwrap(CoachTools.removingFact("desk job", from: notes))
        XCTAssertFalse(out.lowercased().contains("desk job"))   // the plural form was matched + removed
        XCTAssertTrue(out.contains("startup"), "unrelated line must survive")
    }

    func testRemovingFactReturnsNilWhenAbsentEmptyOrTooVague() {
        let notes = "- vegetarian\n- two cats"
        XCTAssertNil(CoachTools.removingFact("skydiving", from: notes))  // not present
        XCTAssertNil(CoachTools.removingFact("a", from: notes))          // too short to match safely
        XCTAssertNil(CoachTools.removingFact("creatine", from: ""))      // empty notes
    }

    /// A present-but-broad word removes only its own line — never wipes everything (the old filter
    /// would delete every line containing the substring).
    func testRemovingFactNeverWipesUnrelatedLines() {
        let notes = "- likes spin class\n- dislikes running\n- vegetarian"
        XCTAssertEqual(CoachTools.removingFact("running", from: notes),
                       "- likes spin class\n- vegetarian")
    }
}

// MARK: - Small test-only conveniences

private extension CoachTools.ParsedRequest.Action {
    /// True iff this is a `stepGoal(12000)` — used by the existing-tool regression test.
    var isStepGoal12k: Bool {
        if case .stepGoal(let n) = self { return n == 12000 }
        return false
    }
}
