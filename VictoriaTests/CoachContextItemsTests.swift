import XCTest
@testable import Victoria

/// Pins the fix for "I can't see the specific food items you've logged" — Vita's context now
/// carries the ACTUAL items (names, meal, quantity-correct macros) and a per-day week view,
/// not just running totals. Without this the model only ever had a count.
final class CoachContextItemsTests: XCTestCase {

    /// A fixed "now" so the helper tests are deterministic.
    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    // MARK: - itemLines (per-item detail)

    func testItemLinesShowNameMealMacrosNewestFirst() {
        let foods = [
            FoodEntry(date: now(), mealType: .breakfast, name: "Muscle Milk",
                      calories: 160, proteinG: 40, carbsG: 9, fatG: 2.5),
            FoodEntry(date: now().addingTimeInterval(-600), mealType: .snack, name: "Apple",
                      quantity: 2, calories: 95, proteinG: 0.5, carbsG: 25, fatG: 0.3),
        ]
        let lines = CoachContext.itemLines(foods)
        XCTAssertEqual(lines.count, 2)
        // Newest first → Muscle Milk before Apple.
        XCTAssertTrue(lines[0].contains("Muscle Milk"))
        XCTAssertTrue(lines[0].contains("(Breakfast)"))
        XCTAssertTrue(lines[0].contains("160 kcal"))
        XCTAssertTrue(lines[0].contains("40g P"))
        // Apple logged ×2 → shows the multiplier AND the quantity-correct totals (95×2, 25×2).
        let apple = try! XCTUnwrap(lines.first { $0.contains("Apple") })
        XCTAssertTrue(apple.contains("×2"))
        XCTAssertTrue(apple.contains("190 kcal"))   // 95 × 2
        XCTAssertTrue(apple.contains("50g C"))      // 25 × 2
    }

    func testItemLinesCapWithOverflowTail() {
        let foods = (0..<20).map {
            FoodEntry(date: now().addingTimeInterval(-Double($0)), name: "Item\($0)", calories: 100)
        }
        let lines = CoachContext.itemLines(foods, limit: 15)
        XCTAssertEqual(lines.count, 16)                      // 15 items + 1 tail
        XCTAssertTrue(lines.last!.contains("and 5 more"))    // 20 − 15
    }

    func testItemLinesHandlesBlankName() {
        let lines = CoachContext.itemLines([FoodEntry(date: now(), name: "   ", calories: 50)])
        XCTAssertTrue(lines[0].contains("Unnamed item"))
    }

    /// THE McDonald's bug: a scanned multi-item meal stores its component breakdown in `notes`.
    /// Vita's context must now surface those (and the serving), so she sees the "+ 3 more" items
    /// instead of saying she can't.
    func testItemLinesIncludesNotesSoVitaSeesMealComponents() {
        let f = FoodEntry(date: now(), mealType: .dinner,
                          name: "McDonald's 10 pc. Chicken McNuggets + 3 more",
                          calories: 1910, proteinG: 49, carbsG: 277, fatG: 73)
        f.servingDescription = "1 meal"
        f.notes = "10 pc McNuggets, large fries, large Coke, OREO McFlurry"
        let line = CoachContext.itemLines([f]).joined()
        XCTAssertTrue(line.contains("large fries"), "context must carry the meal's component notes")
        XCTAssertTrue(line.contains("OREO McFlurry"))
    }

    // MARK: - weeklyTotalLines (per-day week view)

    func testWeeklyTotalLinesLabelsAndSums() {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: now())!
        let old = cal.date(byAdding: .day, value: -30, to: now())!
        let foods = [
            FoodEntry(date: now(), mealType: .lunch, name: "T", calories: 500, proteinG: 30),
            FoodEntry(date: yesterday, mealType: .lunch, name: "Y1", calories: 300, proteinG: 20),
            FoodEntry(date: yesterday, mealType: .dinner, name: "Y2", calories: 400, proteinG: 10),
            FoodEntry(date: old, name: "Old", calories: 999),   // outside the 7-day window
        ]
        let lines = CoachContext.weeklyTotalLines(foods, days: 7, now: now())
        XCTAssertEqual(lines.count, 2)                       // today + yesterday only
        XCTAssertTrue(lines[0].contains("Today"))
        XCTAssertTrue(lines[0].contains("500 kcal"))
        XCTAssertTrue(lines[1].contains("Yesterday"))
        XCTAssertTrue(lines[1].contains("700 kcal"))         // 300 + 400 summed
        XCTAssertTrue(lines[1].contains("(2 items)"))
    }

    func testWeeklyTotalLinesEmptyWithNoFood() {
        XCTAssertTrue(CoachContext.weeklyTotalLines([], now: now()).isEmpty)
    }

    // MARK: - summary integration

    func testSummaryNamesTheActualFoodsAndWeekSection() {
        let p = UserProfile()
        p.name = "Victoria"
        // Real .now so it lands on "today" inside summary() (which uses .now internally).
        let foods = [
            FoodEntry(date: .now, mealType: .snack, name: "In-N-Out Double Double",
                      calories: 670, proteinG: 37, carbsG: 39, fatG: 41),
        ]
        let s = CoachContext.summary(profile: p, foods: foods, weights: [])
        XCTAssertTrue(s.contains("In-N-Out Double Double"))            // the item, not just "1 item"
        XCTAssertTrue(s.contains("The exact foods logged today"))
        XCTAssertTrue(s.contains("This week's daily food totals"))
        XCTAssertTrue(s.contains("g carbs"))                          // carbs/fat now in totals line
        XCTAssertTrue(s.contains("g fat"))
    }

    func testSummaryUnchangedWhenNothingLogged() {
        let p = UserProfile()
        let s = CoachContext.summary(profile: p, foods: [], weights: [])
        XCTAssertTrue(s.contains("nothing logged yet"))
        XCTAssertFalse(s.contains("The exact foods logged today"))
        XCTAssertFalse(s.contains("This week's daily food totals"))
    }

    // MARK: - Comeback gap awareness

    /// After a two-week break, the summary must tell Vita the user was AWAY — otherwise a
    /// returning user is indistinguishable from a brand-new one and the model reads the gap
    /// as under-eating / lost progress.
    func testSummaryFlagsAReturnAfterAGap() {
        let p = UserProfile()
        let foods = [
            FoodEntry(date: .now, name: "Comeback bowl", calories: 500),
            FoodEntry(date: Calendar.current.date(byAdding: .day, value: -14, to: .now)!,
                      name: "Old meal", calories: 600),
        ]
        let s = CoachContext.summary(profile: p, foods: foods, weights: [])
        XCTAssertTrue(s.contains("coming back after 14 days away"))
        XCTAssertTrue(s.contains("NOT that the user wasn't eating"))
    }

    /// No gap (logged yesterday) and brand-new user (first log today): no away note.
    func testSummaryHasNoGapNoteWithoutARealGap() {
        let p = UserProfile()
        let recent = [
            FoodEntry(date: .now, name: "Lunch", calories: 500),
            FoodEntry(date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
                      name: "Dinner", calories: 600),
        ]
        XCTAssertFalse(CoachContext.summary(profile: p, foods: recent, weights: [])
            .contains("days away from the app"))
        let firstEver = [FoodEntry(date: .now, name: "First log", calories: 500)]
        XCTAssertFalse(CoachContext.summary(profile: p, foods: firstEver, weights: [])
            .contains("days away from the app"))
    }
}
