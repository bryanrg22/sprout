import XCTest

/// The Home | Gym switch: what each side shows, that the choice survives a relaunch, and
/// that the side left behind is as it was (flows c and d).
final class ModeSwitchFlowTests: SproutUITestCase {

    /// c. Gym shows Workouts with no tab bar; Home brings Today and the tab bar back; the
    /// app reopens in the mode it was left in.
    func testSwitchingBetweenHomeAndGymAndReopeningInGym() throws {
        addTeardownBlock { self.leaveStoredModeAtHome() }
        launch()
        waitForToday()
        waitForTabBar()
        XCTAssertFalse(isShown(app.scrollViews, AccessibilityID.Workouts.root))

        switchMode(to: AccessibilityID.Mode.gym)
        waitForWorkouts()
        waitHidden(app.scrollViews, AccessibilityID.Today.root)
        waitForNoTabBar()

        expectKnownDefect("""
            In Gym, XCUITest still finds Home's tab bar button. The content of both surfaces \
            is now hidden from accessibility when not showing (the audit finds none of it, \
            EVAL_REPORT 29), and the tab bar is hidden with `.toolbar(.hidden, for: .tabBar)`; \
            whether VoiceOver can still land on this one button is not known. \
            Sprout/App/RootView.swift, `SurfaceContent`
            """) {
            XCTAssertFalse(app.tabBars.buttons[AccessibilityID.Tab.today].exists,
                           "Home's tab bar must not be reachable by assistive technology while Gym is showing")
        }

        switchMode(to: AccessibilityID.Mode.home)
        waitForToday()
        waitHidden(app.scrollViews, AccessibilityID.Workouts.root)
        waitForTabBar()

        // Leave in Gym, quit, and reopen with no --demo-tab: the stored mode decides.
        switchMode(to: AccessibilityID.Mode.gym)
        waitForWorkouts()
        XCUIDevice.shared.press(.home)
        wait("the app to leave the foreground") { self.app.state != .runningForeground }
        app.terminate()

        launch(tab: nil)
        waitForWorkouts()
        waitForNoTabBar()
        XCTAssertFalse(isShown(app.scrollViews, AccessibilityID.Today.root))

        try auditAccessibility("Workouts (Gym)", knownIssues: Self.workoutsAuditIssues)
    }

    /// d. What was left in Home is still there after a trip to Gym and back: the scroll
    /// position of a tab and a half-typed message.
    func testHomeStateSurvivesATripToGym() {
        addTeardownBlock { self.leaveStoredModeAtHome() }
        launch()
        waitForToday()

        // Leave Nutrients scrolled down.
        openTab(AccessibilityID.Tab.nutrients)
        let nutrients = waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
        let dayLabel = app.buttons[AccessibilityID.Nutrients.dayLabel]
        let restingY = dayLabel.frame.minY
        nutrients.swipeUp()
        // Scrolled, and at rest: two samples in a row at the same place.
        var previousY = restingY
        wait("Nutrients to settle after the scroll") {
            let y = dayLabel.frame.minY
            defer { previousY = y }
            return y < restingY - 50 && abs(y - previousY) < 0.5
        }
        let scrolledY = dayLabel.frame.minY

        // Leave a half-typed message with the coach.
        openCoach()
        let draft = "half typed"
        type(draft, into: AccessibilityID.Coach.input)
        dismissKeyboard()
        XCTAssertEqual(app.textFields[AccessibilityID.Coach.input].value as? String, draft)

        // To Gym and back. The switch sits on Today.
        openTab(AccessibilityID.Tab.today)
        waitForToday()
        switchMode(to: AccessibilityID.Mode.gym)
        waitForWorkouts()
        waitForNoTabBar()
        switchMode(to: AccessibilityID.Mode.home)
        waitForToday()
        XCTAssertTrue(app.tabBars.buttons[AccessibilityID.Tab.today].isSelected, "Home returns on the tab it was left on")

        openTab(AccessibilityID.Tab.coach)
        XCTAssertEqual(waitShown(app.textFields, AccessibilityID.Coach.input).value as? String, draft,
                       "the half-typed message is still in the field")
        XCTAssertEqual(userMessages(saying: draft).count, 0, "and it was not sent")

        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
        XCTAssertEqual(dayLabel.frame.minY, scrolledY, accuracy: 1, "Nutrients is scrolled where it was left")
    }
}

extension SproutUITestCase {
    /// What the accessibility audit reports on the Workouts screen (flows c and h).
    static let workoutsAuditIssues = """
        About 29 issues (14 contrast, 13 Dynamic Type, 2 clipped text; counts are from one run and \
        move by one or two between runs). None are on the hidden Home \
        surface any more (EVAL_REPORT 29). On screen: partial Dynamic Type and, for the dates and \
        the summary line, contrast on the week card (Features/Workouts/ActivityWeek.swift); contrast on the white Log a workout label over the brand gradient \
        (WorkoutsView.swift:307) and on the session summary (WorkoutsView.swift:454); the Home | Gym capsule has a fixed height \
        (Features/AppMode/AppMode.swift:81); a session title is clipped at one line (WorkoutsView.swift:446).
        """

    /// The Home | Gym choice is stored in UserDefaults, which outlives the in-memory
    /// store. A flow that can leave Gym stored puts Home back when it ends (pass or
    /// fail), so the next launch on this simulator does not inherit it.
    func leaveStoredModeAtHome() {
        if app.state != .runningForeground || !isShown(app.buttons, AccessibilityID.Mode.home) {
            launch()   // `--demo-tab today` stores Home
        } else if !tabBarIsShown {
            switchMode(to: AccessibilityID.Mode.home)
        }
        waitForToday()
        // Leave the foreground so the stored value is written out before the app is terminated.
        XCUIDevice.shared.press(.home)
        wait("the app to leave the foreground") { self.app.state != .runningForeground }
    }
}
