import XCTest

/// Onboarding driven from a fresh install: every step in order with nothing filled in,
/// back and forward, steps passed by swiping instead of the button, and leaving the app
/// in the middle (GOALS G6: "what happens if you do one step in front of the other, what
/// happens if you manage to skip a step").
///
/// Each launch is `--ui-testing` with no seed, so the store is empty and in memory, there
/// is no key, and no permission prompt can appear. What these flows prove is that the
/// thirteen steps can be walked and left in these orders and still end on a working
/// Today. They do not check the numbers of the plan onboarding computes (the unit tests
/// of `NutritionMath` and the settings matrix do), and they fill nothing in, so a typed
/// name, weight or note is not covered here.
final class OnboardingFlowTests: SproutUITestCase {

    /// The number of onboarding steps, read from the step indicator ("Step 1 of 13").
    private func stepCount(file: StaticString = #filePath, line: UInt = #line) -> Int {
        let label = waitShown(app.otherElements, AccessibilityID.Onboarding.steps, file: file, line: line).label
        let numbers = label.split { !$0.isNumber }.compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 2, "the indicator reads \"Step n of m\": \"\(label)\"", file: file, line: line)
        return numbers.last ?? 0
    }

    private func currentStep() -> Int? {
        shown(app.otherElements, AccessibilityID.Onboarding.steps).flatMap { firstInteger(in: $0.label) }
    }

    private func waitForStep(_ step: Int, file: StaticString = #filePath, line: UInt = #line) {
        wait("onboarding step \(step) (showing \(currentStep().map(String.init) ?? "nothing"))",
             file: file, line: line) { self.currentStep() == step }
    }

    /// Tap the footer's forward button and wait for the next step.
    private func next(from step: Int, file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons, AccessibilityID.Onboarding.next, file: file, line: line)
        waitForStep(step + 1, file: file, line: line)
    }

    private func start(file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons, AccessibilityID.Onboarding.start, file: file, line: line)
        waitForToday(file: file, line: line)
        waitForTabBar(file: file, line: line)
        XCTAssertFalse(isShown(app.otherElements, AccessibilityID.Onboarding.steps),
                       "onboarding is gone once it is finished", file: file, line: line)
    }

    /// Today as a person who logged nothing sees it: nothing eaten, and the rest of the app reachable.
    private func assertAnEmptyWorkingToday(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(figure(app.staticTexts, AccessibilityID.Today.caloriesEaten, file: file, line: line), 0,
                       "a new profile has eaten nothing", file: file, line: line)
        XCTAssertTrue(isShown(app.buttons, AccessibilityID.Mode.gym), "the Home | Gym switch is there",
                      file: file, line: line)
        // Seen once, by eye: a profile made seconds ago was told "28 days of showing up in a
        // row", a brief cached by an earlier seeded launch (see `--ui-test-fresh-defaults`).
        let streakClaim = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "in a row")).firstMatch
        XCTAssertFalse(streakClaim.exists,
                       "a new profile is told about a run of days: \"\(streakClaim.exists ? streakClaim.label : "")\"",
                       file: file, line: line)
    }

    // MARK: - m. Every step in order, nothing filled in

    /// m. Tap the forward button on every step without entering anything, then start.
    /// Every optional step is skipped and every required one is left at its default.
    func testEveryStepInOrderWithNothingFilledInEndsOnToday() throws {
        launch(seeded: false, tab: nil)
        let count = stepCount()
        XCTAssertGreaterThanOrEqual(count, 10, "the whole flow, not a shortened one")
        waitForStep(1)
        XCTAssertFalse(isShown(app.buttons, AccessibilityID.Onboarding.back), "there is nothing before the first step")

        for step in 1..<count {
            XCTAssertFalse(isShown(app.buttons, AccessibilityID.Onboarding.start),
                           "step \(step) of \(count) must not offer to finish")
            next(from: step)
        }
        XCTAssertFalse(isShown(app.buttons, AccessibilityID.Onboarding.next), "the last step has no further step")
        XCTAssertTrue(isShown(app.buttons, AccessibilityID.Onboarding.back))

        start()
        assertAnEmptyWorkingToday()
    }

    // MARK: - n. Back and forward

    /// n. Going back and forward does not lose the place, and a step visited three times
    /// is still one step.
    func testGoingBackAndForwardKeepsThePlace() {
        launch(seeded: false, tab: nil)
        let count = stepCount()
        waitForStep(1)
        next(from: 1)
        next(from: 2)
        next(from: 3)

        tap(app.buttons, AccessibilityID.Onboarding.back)
        waitForStep(3)
        tap(app.buttons, AccessibilityID.Onboarding.back)
        waitForStep(2)
        next(from: 2)
        tap(app.buttons, AccessibilityID.Onboarding.back)
        waitForStep(2)
        next(from: 2)
        XCTAssertEqual(stepCount(), count, "going back and forward adds or removes no step")

        // All the way back to the start, then the whole way through.
        for step in stride(from: 3, to: 1, by: -1) {
            tap(app.buttons, AccessibilityID.Onboarding.back)
            waitForStep(step - 1)
        }
        XCTAssertFalse(isShown(app.buttons, AccessibilityID.Onboarding.back))
        for step in 1..<count { next(from: step) }
        start()
        assertAnEmptyWorkingToday()
    }

    // MARK: - o. Steps passed without the button

    /// o. The pages can be swiped. Swipe from the first step to the last without ever
    /// tapping the forward button, and finish: no step's own button was used, so anything
    /// a step set up only when its button was tapped would be missing here.
    func testSwipingPastEveryStepThenFinishingStillEndsOnAWorkingToday() {
        launch(seeded: false, tab: nil)
        let count = stepCount()
        waitForStep(1)

        var swipes = 0
        while (currentStep() ?? count) < count, swipes < count * 3 {
            let before = currentStep() ?? 0
            // Drag across the top of the page, where every step has its heading. A swipe
            // through the middle of the screen lands on a wheel picker on the "about you"
            // step and turns the wheel instead of the page (seen: it stopped there).
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.17))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.17))
            from.press(forDuration: 0.05, thenDragTo: to)
            swipes += 1
            let deadline = Date().addingTimeInterval(2)
            while (currentStep() ?? 0) == before, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        XCTAssertEqual(currentStep(), count,
                       "swiping reached step \(currentStep() ?? 0) of \(count) in \(swipes) swipes")
        start()
        assertAnEmptyWorkingToday()
    }

    // MARK: - p. Leaving in the middle

    /// p. Leave the app half way through and come back: the same step is showing, and the
    /// rest of the flow still finishes.
    func testLeavingInTheMiddleAndComingBackKeepsTheStep() {
        launch(seeded: false, tab: nil)
        let count = stepCount()
        waitForStep(1)
        let middle = count / 2
        for step in 1..<middle { next(from: step) }

        backgroundAndReturn()
        waitForStep(middle)
        XCTAssertFalse(app.scrollViews[AccessibilityID.Today.root].exists, "an unfinished onboarding is not skipped")

        for step in middle..<count { next(from: step) }
        start()
        assertAnEmptyWorkingToday()
    }

    /// p. Quit half way through and open the app again: onboarding starts again from its
    /// first step, and the main UI is not shown for a profile that was never finished.
    func testQuittingInTheMiddleStartsOnboardingAgain() {
        launch(seeded: false, tab: nil)
        waitForStep(1)
        next(from: 1)
        next(from: 2)
        next(from: 3)

        app.terminate()
        launch(seeded: false, tab: nil)
        waitForStep(1)
        waitForNoTabBar()
        XCTAssertFalse(app.scrollViews[AccessibilityID.Today.root].exists)
    }
}
