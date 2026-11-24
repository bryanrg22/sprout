import XCTest

/// s. The week card on Workouts (EVAL_REPORT 28): it counts active days, a tap on a day opens
/// that day below, and the arrows move between weeks. The seeded profile has logged workouts
/// today and 1, 2 and 3 days ago, and tracked ones today, 2 and 4 days ago, so the dates
/// below are relative to today and the flow passes on any weekday.
final class WorkoutWeekFlowTests: SproutUITestCase {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))!
    }

    private func cell(_ offset: Int) -> XCUIElement {
        app.buttons[AccessibilityID.Workouts.weekDay(day(offset))]
    }

    /// Show the week holding `offset` days from today, going back a week at a time.
    private func showWeek(containing offset: Int, file: StaticString = #filePath, line: UInt = #line) {
        var tries = 0
        while !cell(offset).exists, tries < 3 {
            tap(app.buttons, AccessibilityID.Workouts.weekPrevious, file: file, line: line)
            _ = cell(offset).waitForExistence(timeout: 3)
            tries += 1
        }
        XCTAssertTrue(cell(offset).exists, "the week holding day \(offset) is showing", file: file, line: line)
    }

    func testTheWeekCountsActiveDaysAndOpensADayWhenTapped() throws {
        launch(tab: "workouts")
        waitForWorkouts()
        let active = waitShown(app.descendants(matching: .any), AccessibilityID.Workouts.weekActiveDays)
        let count = try XCTUnwrap(firstInteger(in: active.label), active.label)
        XCTAssertGreaterThanOrEqual(count, 1, "today has a workout: \"\(active.label)\"")
        XCTAssertLessThanOrEqual(count, 7)
        XCTAssertTrue(cell(0).label.contains("active"), cell(0).label)

        // A day with a logged workout: yesterday.
        showWeek(containing: -1)
        cell(-1).tap()
        wait("yesterday's logged workout") { self.app.buttons[AccessibilityID.Workouts.sessionRow].exists }
        XCTAssertTrue(cell(-1).isSelected, "the tapped day is marked")

        // A day only the tracker saw: four days ago.
        showWeek(containing: -4)
        XCTAssertTrue(cell(-4).label.contains("1 tracked"), cell(-4).label)
        cell(-4).tap()
        wait("the tracked workout") {
            self.app.descendants(matching: .any)[AccessibilityID.Workouts.detectedRow].exists
        }
        XCTAssertFalse(app.buttons[AccessibilityID.Workouts.sessionRow].exists, "nothing was logged that day")

        // Back to this week with the forward arrow, and no further.
        while !cell(0).exists, app.buttons[AccessibilityID.Workouts.weekNext].isEnabled {
            app.buttons[AccessibilityID.Workouts.weekNext].tap()
            _ = cell(0).waitForExistence(timeout: 3)
        }
        XCTAssertTrue(cell(0).exists, "the forward arrow comes back to this week")
        XCTAssertFalse(app.buttons[AccessibilityID.Workouts.weekNext].isEnabled, "there is no week after this one")
    }
}
