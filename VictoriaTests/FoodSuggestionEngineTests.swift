import XCTest
@testable import Victoria

/// Tests for the PURE Smart-Suggestions engine — the code-owned half of the feature.
/// The load-bearing guarantees:
/// (1) meal slot is derived correctly from the hour (boundaries pinned),
/// (2) "remaining" (room to add) clamps at zero and matches target − eaten,
/// (3) top-foods ranks by frequency, then recency, with case-insensitive grouping,
/// (4) the under-protein trend needs enough data and respects the tolerance,
/// (5) empty history is detected (so the UI can show its tailoring prompt), and
/// (6) the rendered prompt stays factual and free of banned therapy/restriction framing.
///
/// Every expected value is computed independently by hand from the engine's documented rules.
final class FoodSuggestionEngineTests: XCTestCase {

    private let day: TimeInterval = 86_400

    /// A fixed "now" so windowing + recency are deterministic.
    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    /// Build a `FoodEntry` at `daysAgo` days before `now()`, with a name + protein.
    private func food(_ name: String, daysAgo: Double, protein: Double = 0, calories: Double = 0) -> FoodEntry {
        FoodEntry(date: now().addingTimeInterval(-daysAgo * day),
                  name: name,
                  calories: calories,
                  proteinG: protein)
    }

    // MARK: - Meal slot from hour

    func testMealSlotBoundaries() {
        // Breakfast 4–11
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 4), .breakfast)
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 10), .breakfast)
        // Lunch 11–15
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 11), .lunch)
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 14), .lunch)
        // Afternoon snack 15–17
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 15), .snack)
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 16), .snack)
        // Dinner 17–22
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 17), .dinner)
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 21), .dinner)
        // Late night / pre-dawn → snack
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 22), .snack)
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 2), .snack)
        XCTAssertEqual(FoodSuggestionEngine.mealSlot(hourOfDay: 0), .snack)
    }

    func testMealSlotMapsToMealType() {
        XCTAssertEqual(FoodSuggestionEngine.MealSlot.breakfast.mealType, .breakfast)
        XCTAssertEqual(FoodSuggestionEngine.MealSlot.lunch.mealType, .lunch)
        XCTAssertEqual(FoodSuggestionEngine.MealSlot.dinner.mealType, .dinner)
        XCTAssertEqual(FoodSuggestionEngine.MealSlot.snack.mealType, .snack)
    }

    // MARK: - Protein / calorie gap math (via makeContext)

    func testRemainingIsTargetMinusEaten() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 1100, proteinEatenToday: 60,
            foods: [], now: now())
        XCTAssertEqual(ctx.caloriesRemaining, 700)   // 1800 − 1100
        XCTAssertEqual(ctx.proteinRemaining, 70)     // 130 − 60
        XCTAssertEqual(ctx.calorieTarget, 1800)
        XCTAssertEqual(ctx.proteinEaten, 60)
    }

    func testRemainingClampsAtZeroWhenOver() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "V", direction: .maintain,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 2000, proteinEatenToday: 150,
            foods: [], now: now())
        XCTAssertEqual(ctx.caloriesRemaining, 0)     // never negative
        XCTAssertEqual(ctx.proteinRemaining, 0)
    }

    func testContextRoundsToWholeUnits() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1799.6, proteinTarget: 129.4,
            caloriesEatenToday: 1100.5, proteinEatenToday: 60.5,
            foods: [], now: now())
        XCTAssertEqual(ctx.calorieTarget, 1800)      // rounded
        XCTAssertEqual(ctx.proteinTarget, 129)
        XCTAssertEqual(ctx.caloriesEaten, 1101)      // .5 rounds up
        XCTAssertEqual(ctx.proteinEaten, 61)
    }

    // MARK: - Top foods (frequency)

    func testTopFoodsRanksByFrequency() {
        let foods = [
            food("Chicken bowl", daysAgo: 1, protein: 40),
            food("Chicken bowl", daysAgo: 2, protein: 40),
            food("Chicken bowl", daysAgo: 3, protein: 40),
            food("Latte", daysAgo: 1, protein: 8),
            food("Latte", daysAgo: 2, protein: 8),
            food("Apple", daysAgo: 1, protein: 0),
        ]
        let top = FoodSuggestionEngine.topFoods(foods, now: now())
        XCTAssertEqual(top.map(\.name), ["Chicken bowl", "Latte", "Apple"])
        XCTAssertEqual(top.first?.count, 3)
        XCTAssertEqual(top.first?.avgProteinG ?? 0, 40, accuracy: 0.0001)
    }

    func testTopFoodsCaseInsensitiveGrouping() {
        let foods = [
            food("Greek yogurt", daysAgo: 1, protein: 18),
            food("greek yogurt ", daysAgo: 2, protein: 20),   // trailing space + lowercase
            food("GREEK YOGURT", daysAgo: 3, protein: 22),
        ]
        let top = FoodSuggestionEngine.topFoods(foods, now: now())
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top.first?.count, 3)
        // avg protein = (18+20+22)/3 = 20
        XCTAssertEqual(top.first?.avgProteinG ?? 0, 20, accuracy: 0.0001)
    }

    func testTopFoodsTieBreaksByRecency() {
        // Both logged twice; "Salad" most recently → it should rank first.
        let foods = [
            food("Oatmeal", daysAgo: 5, protein: 10),
            food("Oatmeal", daysAgo: 6, protein: 10),
            food("Salad", daysAgo: 1, protein: 12),
            food("Salad", daysAgo: 4, protein: 12),
        ]
        let top = FoodSuggestionEngine.topFoods(foods, now: now())
        XCTAssertEqual(top.map(\.name), ["Salad", "Oatmeal"])
    }

    func testTopFoodsRespectsWindow() {
        // Outside the 14-day window → excluded.
        let foods = [
            food("Old meal", daysAgo: 30, protein: 30),
            food("Recent meal", daysAgo: 2, protein: 20),
        ]
        let top = FoodSuggestionEngine.topFoods(foods, days: 14, now: now())
        XCTAssertEqual(top.map(\.name), ["Recent meal"])
    }

    func testTopFoodsRespectsLimit() {
        let foods = (0..<10).map { food("Food\($0)", daysAgo: Double($0) + 1, protein: 5) }
        let top = FoodSuggestionEngine.topFoods(foods, limit: 3, now: now())
        XCTAssertEqual(top.count, 3)
    }

    func testTopFoodsIgnoresBlankNames() {
        let foods = [
            food("   ", daysAgo: 1, protein: 10),
            food("", daysAgo: 1, protein: 10),
            food("Eggs", daysAgo: 1, protein: 12),
        ]
        let top = FoodSuggestionEngine.topFoods(foods, now: now())
        XCTAssertEqual(top.map(\.name), ["Eggs"])
    }

    func testTopFoodsEmptyWhenNoHistory() {
        XCTAssertTrue(FoodSuggestionEngine.topFoods([], now: now()).isEmpty)
    }

    // MARK: - Under-protein trend

    func testUnderProteinTrendTrueWhenConsistentlyLow() {
        // 3 distinct days, each well under a 130 g target → under.
        let foods = [
            food("a", daysAgo: 0, protein: 60),
            food("b", daysAgo: 1, protein: 70),
            food("c", daysAgo: 2, protein: 65),
        ]
        XCTAssertEqual(FoodSuggestionEngine.isUnderProteinTrend(foods, proteinTarget: 130, now: now()), true)
    }

    func testUnderProteinTrendFalseWhenHittingTarget() {
        let foods = [
            food("a", daysAgo: 0, protein: 135),
            food("b", daysAgo: 1, protein: 140),
            food("c", daysAgo: 2, protein: 132),
        ]
        XCTAssertEqual(FoodSuggestionEngine.isUnderProteinTrend(foods, proteinTarget: 130, now: now()), false)
    }

    func testUnderProteinTrendNilWithTooFewDays() {
        // Only 2 logged days < minDays(3) → unknown (nil), not a false "fine".
        let foods = [
            food("a", daysAgo: 0, protein: 40),
            food("b", daysAgo: 1, protein: 50),
        ]
        XCTAssertNil(FoodSuggestionEngine.isUnderProteinTrend(foods, proteinTarget: 130, now: now()))
    }

    func testUnderProteinTrendSumsWithinADay() {
        // Two logs the SAME day should sum (120 total on day 0), so across 3 days she's
        // actually hitting ~target → false, not true.
        let foods = [
            food("a", daysAgo: 0, protein: 70),
            food("b", daysAgo: 0, protein: 70),   // day 0 total = 140
            food("c", daysAgo: 1, protein: 130),
            food("d", daysAgo: 2, protein: 135),
        ]
        XCTAssertEqual(FoodSuggestionEngine.isUnderProteinTrend(foods, proteinTarget: 130, now: now()), false)
    }

    func testUnderProteinTrendNilWhenNoTarget() {
        let foods = [food("a", daysAgo: 0, protein: 40)]
        XCTAssertNil(FoodSuggestionEngine.isUnderProteinTrend(foods, proteinTarget: 0, now: now()))
    }

    func testUnderProteinToleranceLetsSlightMissCount() {
        // 3 days at exactly 120 vs 130 target. 120 / 130 = 0.923 > 0.9 tolerance → NOT under.
        let foods = (0..<3).map { food("d\($0)", daysAgo: Double($0), protein: 120) }
        XCTAssertEqual(FoodSuggestionEngine.isUnderProteinTrend(foods, proteinTarget: 130, now: now()), false)
        // But 3 days at 110 → 110/130 = 0.846 < 0.9 → under.
        let lower = (0..<3).map { food("e\($0)", daysAgo: Double($0), protein: 110) }
        XCTAssertEqual(FoodSuggestionEngine.isUnderProteinTrend(lower, proteinTarget: 130, now: now()), true)
    }

    // MARK: - Context: history detection

    func testHasEnoughHistoryReflectsTopFoods() {
        let empty = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 0, proteinEatenToday: 0,
            foods: [], now: now())
        XCTAssertFalse(empty.hasEnoughHistory)

        let withHistory = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 0, proteinEatenToday: 0,
            foods: [food("Eggs", daysAgo: 1, protein: 12)], now: now())
        XCTAssertTrue(withHistory.hasEnoughHistory)
    }

    // MARK: - Prompt rendering

    func testPromptIncludesCoreFacts() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "Victoria", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 1100, proteinEatenToday: 60,
            foods: [
                food("Chicken bowl", daysAgo: 1, protein: 40),
                food("Chicken bowl", daysAgo: 2, protein: 40),
            ],
            now: now())
        let p = FoodSuggestionEngine.renderPrompt(ctx)
        XCTAssertTrue(p.contains("Victoria"))
        XCTAssertTrue(p.contains("700"))            // calorie room to add
        XCTAssertTrue(p.contains("70"))             // protein still to hit
        XCTAssertTrue(p.contains("Chicken bowl"))   // her real food, by name
    }

    func testPromptReferencesNearbyWhenProvided() {
        let place = FoodSuggestionEngine.NearbyPlace(name: "Whole Foods", category: "grocery")
        let ctx = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 0, proteinEatenToday: 0,
            foods: [food("Eggs", daysAgo: 1, protein: 12)],
            nearbyPlace: place, now: now())
        XCTAssertTrue(FoodSuggestionEngine.renderPrompt(ctx).contains("Whole Foods"))
    }

    func testPromptOmitsNearbyWhenAbsent() {
        // Location off → no nearby place → prompt must not invent one.
        let ctx = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 0, proteinEatenToday: 0,
            foods: [food("Eggs", daysAgo: 1, protein: 12)],
            nearbyPlace: nil, now: now())
        let p = FoodSuggestionEngine.renderPrompt(ctx)
        XCTAssertFalse(p.lowercased().contains("nearby"))
    }

    /// The prompt steers tone but must NOT itself carry the banned therapy/restriction
    /// vocabulary the tone constraint forbids.
    func testPromptHasNoBannedFraming() {
        let banned = ["no food is bad", "be kind to yourself", "no rush",
                      "cheat", "guilty", "burn it off", "cut back", "eat less"]
        // Sweep direction + protein-trend + nearby combinations.
        for direction in [FoodSuggestionEngine.Direction.lose, .maintain, .gain] {
            for proteins in [40.0, 135.0] {       // drives under vs. hitting protein
                let foods = (0..<3).map { food("d\($0)", daysAgo: Double($0), protein: proteins) }
                let ctx = FoodSuggestionEngine.makeContext(
                    name: "V", direction: direction,
                    calorieTarget: 1800, proteinTarget: 130,
                    caloriesEatenToday: 900, proteinEatenToday: 40,
                    foods: foods, now: now())
                let p = FoodSuggestionEngine.renderPrompt(ctx).lowercased()
                for phrase in banned {
                    XCTAssertFalse(p.contains(phrase), "Prompt contained banned phrase '\(phrase)'")
                }
            }
        }
    }

    func testPromptHandlesEmptyHistoryGracefully() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 0, proteinEatenToday: 0,
            foods: [], now: now())
        let p = FoodSuggestionEngine.renderPrompt(ctx)
        // Neutral name fallback, and no crash / no go-to foods list.
        XCTAssertTrue(p.contains("The user"))
        XCTAssertTrue(p.lowercased().contains("no clear pattern"))
    }

    // MARK: - "Already eaten today" (stops the 2nd-Muscle-Milk repeat)

    func testEatenTodayCapturesOnlyTodaysItems() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "Bryan", direction: .gain,
            calorieTarget: 2700, proteinTarget: 100,
            caloriesEatenToday: 200, proteinEatenToday: 40,
            foods: [
                food("Muscle Milk", daysAgo: 0, protein: 40),   // today → eaten
                food("Chicken bowl", daysAgo: 1, protein: 40),  // yesterday → NOT eaten today
            ],
            now: now())
        XCTAssertEqual(ctx.eatenToday, ["Muscle Milk"])
        let p = FoodSuggestionEngine.renderPrompt(ctx)
        XCTAssertTrue(p.contains("ALREADY eaten these today: Muscle Milk"))
        XCTAssertTrue(p.lowercased().contains("do not re-suggest"))
    }

    func testEatenTodayDedupesCaseInsensitively() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 300, proteinEatenToday: 30,
            foods: [
                food("Eggs", daysAgo: 0, protein: 12),
                food("eggs", daysAgo: 0, protein: 12),   // same day, different case
            ],
            now: now())
        XCTAssertEqual(ctx.eatenToday.count, 2)                       // raw list keeps both
        let p = FoodSuggestionEngine.renderPrompt(ctx)
        XCTAssertTrue(p.contains("ALREADY eaten these today:"))
        XCTAssertFalse(p.lowercased().contains("eggs, eggs"))         // collapsed to one
    }

    func testNoEatenTodayLineWhenNothingLoggedToday() {
        let ctx = FoodSuggestionEngine.makeContext(
            name: "V", direction: .lose,
            calorieTarget: 1800, proteinTarget: 130,
            caloriesEatenToday: 0, proteinEatenToday: 0,
            foods: [food("Latte", daysAgo: 2, protein: 8)],   // only old history
            now: now())
        XCTAssertTrue(ctx.eatenToday.isEmpty)
        XCTAssertFalse(FoodSuggestionEngine.renderPrompt(ctx).contains("ALREADY eaten"))
    }
}
