import XCTest

/// Logging by hand: food, water and a workout, each checked where the user reads the
/// result, including a repeated step and a delete (flows e, f, g and h).
final class LoggingFlowTests: SproutUITestCase {

    private let food = "Smoke test oats"
    private let calories = 123

    /// e. A food logged manually from Nutrients appears in the day's list, and the
    /// calories on Today go up by exactly that amount.
    func testLoggingAFoodManuallyChangesTodayByThatAmount() throws {
        launch()
        waitForToday()
        let eatenBefore = caloriesEatenOnToday

        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
        let rowsBefore = app.buttons.matching(identifier: AccessibilityID.Nutrients.foodRow).count
        XCTAssertEqual(foodRows(named: food).count, 0)

        logFoodManually(name: food, calories: calories)

        wait("the new food to be listed") { self.foodRows(named: self.food).count == 1 }
        XCTAssertEqual(app.buttons.matching(identifier: AccessibilityID.Nutrients.foodRow).count, rowsBefore + 1)
        XCTAssertEqual(firstInteger(in: foodRows(named: food).firstMatch.label.replacingOccurrences(of: food, with: "")),
                       calories, "the row shows the calories that were entered")

        openTab(AccessibilityID.Tab.today)
        waitForToday()
        XCTAssertEqual(caloriesEatenOnToday, eatenBefore + calories)

        try auditAccessibility("Today", knownIssues: """
            About 32 issues (19 contrast, 11 Dynamic Type, 2 clipped text; counts are from one run and \
            move by one or two between runs). About 23 are on elements of the hidden \
            Gym surface, which stays in the accessibility tree (Victoria/App/RootView.swift:174, :179). \
            On screen: contrast on the finish-setup card and its Save key button \
            (Features/Dashboard/FinishSetupCard.swift:34, :75), on the widget promo card \
            (Features/Dashboard/WidgetPromoCard.swift:37, :61, :72) and on the weekly reflection text \
            (Features/Dashboard/WeeklyReflectionCard.swift); partial Dynamic Type on the promo card's \
            last line (WidgetPromoCard.swift:72); in some runs the two-line greeting is reported clipped \
            (Features/Dashboard/DashboardView.swift:369).
            """)
    }

    /// f. The same food logged twice, then one deleted: the totals are right both times.
    func testLoggingTwiceThenDeletingOneKeepsTheTotalsRight() throws {
        launch()
        waitForToday()
        let eatenBefore = caloriesEatenOnToday

        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
        let rowsBefore = app.buttons.matching(identifier: AccessibilityID.Nutrients.foodRow).count

        logFoodManually(name: food, calories: calories)
        wait("the first entry to be listed") { self.foodRows(named: self.food).count == 1 }
        logFoodManually(name: food, calories: calories)
        wait("the second entry to be listed") { self.foodRows(named: self.food).count == 2 }
        XCTAssertEqual(app.buttons.matching(identifier: AccessibilityID.Nutrients.foodRow).count, rowsBefore + 2)

        openTab(AccessibilityID.Tab.today)
        waitForToday()
        XCTAssertEqual(caloriesEatenOnToday, eatenBefore + 2 * calories, "both entries count")

        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
        foodRows(named: food).firstMatch.press(forDuration: 1.0)
        // Tap Delete only once the menu has finished appearing: on a slow CI runner a tap
        // the moment the button exists landed during the menu's animation and was lost
        // (main, 2026-11-23: the same code passed on the pull request and locally).
        let delete = app.buttons.matching(identifier: AccessibilityID.Nutrients.foodRowDelete).firstMatch
        wait("the Delete item of the menu to be tappable") { delete.exists && delete.isHittable }
        delete.tap()
        wait("one of the two entries to be gone", timeout: 30) { self.foodRows(named: self.food).count == 1 }
        XCTAssertEqual(app.buttons.matching(identifier: AccessibilityID.Nutrients.foodRow).count, rowsBefore + 1)

        openTab(AccessibilityID.Tab.today)
        waitForToday()
        XCTAssertEqual(caloriesEatenOnToday, eatenBefore + calories, "exactly one entry's calories came off")
    }

    /// g. Water logged from Today changes the water figure, once per tap.
    func testLoggingWaterFromTodayChangesTheWaterFigure() {
        launch()
        waitForToday()
        let containersBefore = waterContainersOnToday
        let amountBefore = waterAmountOnToday

        tap(app.buttons, AccessibilityID.Today.waterAdd)
        wait("the water count to go up by one") { self.waterContainersOnToday == containersBefore + 1 }
        let amountAfterOne = waterAmountOnToday
        XCTAssertGreaterThan(amountAfterOne, amountBefore, "the amount went up with the count")

        tap(app.buttons, AccessibilityID.Today.waterAdd)
        wait("the water count to go up by one more") { self.waterContainersOnToday == containersBefore + 2 }
        let perContainer = amountAfterOne - amountBefore
        XCTAssertEqual(Double(waterAmountOnToday - amountBefore), Double(2 * perContainer), accuracy: 1,
                       "two containers are twice one (the figure is rounded to a whole unit)")
    }

    /// h. A workout logged through the log flow appears on the Workouts screen.
    func testLoggingAWorkoutShowsItOnWorkouts() throws {
        addTeardownBlock { self.leaveStoredModeAtHome() }
        launch()
        waitForToday()
        switchMode(to: AccessibilityID.Mode.gym)
        waitForWorkouts()
        let sessions = app.buttons.matching(identifier: AccessibilityID.Workouts.sessionRow)
        let sessionsBefore = sessions.count
        let minutes = 27
        let withThoseMinutes = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                                AccessibilityID.Workouts.sessionRow, String(minutes)))
        XCTAssertEqual(withThoseMinutes.count, 0)

        tap(app.buttons, AccessibilityID.Workouts.log)
        tap(app.buttons, AccessibilityID.WorkoutLog.kind("run"))
        type(String(minutes), into: AccessibilityID.WorkoutLog.minutes)
        tap(app.buttons, AccessibilityID.WorkoutLog.save)

        wait("the new session to be listed") { sessions.count == sessionsBefore + 1 }
        XCTAssertEqual(withThoseMinutes.count, 1, "the session shows the duration that was entered")
        waitForWorkouts()
        waitForNoTabBar()

        try auditAccessibility("Workouts (Gym), after logging", knownIssues: Self.workoutsAuditIssues)
    }
}
