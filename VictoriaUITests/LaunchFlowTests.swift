import XCTest

/// What a launch shows: onboarding on a fresh install, the main UI on a seeded one, and
/// that the first thing a person opens can be anything (flows a, b and l).
final class LaunchFlowTests: SproutUITestCase {

    /// a. A fresh install with no seed shows the first onboarding screen, not the main UI.
    func testFreshInstallShowsTheFirstOnboardingScreen() {
        launch(seeded: false, tab: nil)

        let steps = waitShown(app.otherElements, AccessibilityID.Onboarding.steps)
        XCTAssertEqual(firstInteger(in: steps.label), 1, "onboarding opens on its first step: \"\(steps.label)\"")
        waitForNoTabBar()
        XCTAssertFalse(app.scrollViews[AccessibilityID.Today.root].exists, "Today must not exist before onboarding")
        XCTAssertFalse(app.buttons[AccessibilityID.Mode.gym].exists, "the Home | Gym switch must not exist before onboarding")
    }

    /// b. A seeded launch shows Today, and each Home tab opens and shows its root.
    func testSeededLaunchShowsTodayAndEveryHomeTabOpens() throws {
        launch()

        waitForToday()
        XCTAssertTrue(app.tabBars.buttons[AccessibilityID.Tab.today].isSelected)
        XCTAssertGreaterThan(caloriesEatenOnToday, 0, "the seeded day's calories are showing")

        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
        XCTAssertTrue(app.tabBars.buttons[AccessibilityID.Tab.nutrients].isSelected)
        XCTAssertGreaterThan(app.buttons.matching(identifier: AccessibilityID.Nutrients.foodRow).count, 0,
                             "the seeded day's food is listed")

        openTab(AccessibilityID.Tab.coach)
        waitShown(app.textFields, AccessibilityID.Coach.input)
        XCTAssertTrue(app.tabBars.buttons[AccessibilityID.Tab.coach].isSelected)
        XCTAssertGreaterThan(assistantMessages.count, 0, "the conversation is showing")

        openTab(AccessibilityID.Tab.today)
        waitForToday()

        openTab(AccessibilityID.Tab.progress)
        waitShown(app.scrollViews, AccessibilityID.Progress.root)
        XCTAssertTrue(app.tabBars.buttons[AccessibilityID.Tab.progress].isSelected)

        try auditAccessibility("Progress", knownIssues: """
            About 28 issues (14 contrast, 11 Dynamic Type, 2 label, 1 clipped text; counts are from one \
            run and move by one or two between runs). About 22 are on elements of \
            the hidden Gym surface, which stays in the accessibility tree (Victoria/App/RootView.swift:174, \
            :179), so invisible text is audited. On screen: contrast on the plan card \
            (Features/Plan/PlanCard.swift:44, :46) and the Log weigh-in bar (Features/Weight/WeightView.swift:425); \
            the trend figure is a fixed 56 pt with no readable label (WeightView.swift:153), and the \
            rate arrow image has no label (WeightView.swift:191).
            """)
    }

    /// l. Out of order: the coach is the first thing opened on a fresh seeded launch.
    func testOpeningTheCoachBeforeAnythingElse() {
        launch()

        // Straight to the coach, without waiting for Today to settle first.
        openCoach()
        XCTAssertGreaterThan(assistantMessages.count, 0, "the conversation renders")
        XCTAssertFalse(coachIsTyping, "nothing was sent, so nothing is pending")

        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
        openTab(AccessibilityID.Tab.progress)
        waitShown(app.scrollViews, AccessibilityID.Progress.root)
        openTab(AccessibilityID.Tab.today)
        waitForToday()
        XCTAssertGreaterThan(caloriesEatenOnToday, 0)
    }

    /// l. Out of order: Gym is opened before Today has ever been shown.
    func testOpeningGymBeforeEverOpeningToday() {
        addTeardownBlock { self.leaveStoredModeAtHome() }
        launch(tab: "workouts")

        waitForWorkouts()
        waitForNoTabBar()
        XCTAssertFalse(isShown(app.scrollViews, AccessibilityID.Today.root))
        XCTAssertGreaterThan(app.buttons.matching(identifier: AccessibilityID.Workouts.sessionRow).count, 0,
                             "the seeded session is listed")

        switchMode(to: AccessibilityID.Mode.home)
        waitForToday()
        waitForTabBar()
        XCTAssertGreaterThan(caloriesEatenOnToday, 0, "Today renders its figures on its first showing")
    }

    /// l. Out of order: Settings (the avatar button on Today) opens and comes back.
    func testOpeningSettingsFromTodayAndComingBack() {
        launch()
        waitForToday()
        let eaten = caloriesEatenOnToday

        tap(app.buttons, AccessibilityID.Today.settings)
        tap(app.buttons, AccessibilityID.Settings.done)

        waitHidden(app.buttons, AccessibilityID.Settings.done)
        waitForToday()
        waitForTabBar()
        XCTAssertEqual(caloriesEatenOnToday, eaten, "Today is as it was")

        // And again: a repeated round trip must be as good as the first.
        tap(app.buttons, AccessibilityID.Today.settings)
        tap(app.buttons, AccessibilityID.Settings.done)
        waitForToday()
        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
    }
}
