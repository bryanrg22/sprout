import XCTest

/// The coach against a scripted model: a turn that logs through a tool, its Undo, and a
/// provider that is down (flows i and j).
final class CoachFlowTests: SproutUITestCase {

    /// i. `coach-log-water`: a message leads to a `log_water` tool call. The app's rule
    /// for a quick, reversible log is to apply it at once and offer Undo; the reply then
    /// appears and Today's water reflects it. Undo on a second log puts the figure back.
    func testCoachLogsWaterThroughAToolAndUndoPutsItBack() throws {
        launch(script: "coach-log-water")
        waitForToday()
        let containersBefore = waterContainersOnToday
        let amountBefore = waterAmountOnToday
        let scriptedContainers = 2

        openCoach()
        sendToCoach("I drank two bottles of water")
        XCTAssertTrue(appears(app.buttons[AccessibilityID.Coach.undo]), "an applied log offers Undo")
        wait("the coach's reply after the tool call") { self.scriptedReplies.count == 1 }
        wait("the typing indicator to go") { !self.coachIsTyping }
        dismissKeyboard()

        openTab(AccessibilityID.Tab.today)
        waitForToday()
        XCTAssertEqual(waterContainersOnToday, containersBefore + scriptedContainers, "Today shows the logged water")
        let amountAfterFirst = waterAmountOnToday
        XCTAssertGreaterThan(amountAfterFirst, amountBefore)

        // A second log, undone straight away. Wait out the first log's Undo so the one
        // tapped below can only be the second's.
        openCoach()
        wait("the first Undo to time out") { !self.app.buttons[AccessibilityID.Coach.undo].exists }
        sendToCoach("And two more")
        tap(app.buttons, AccessibilityID.Coach.undo)
        wait("Undo to go once used") { !self.app.buttons[AccessibilityID.Coach.undo].exists }
        wait("the coach's second reply") { self.scriptedReplies.count == 2 }
        wait("the typing indicator to go") { !self.coachIsTyping }
        dismissKeyboard()

        openTab(AccessibilityID.Tab.today)
        waitForToday()
        XCTAssertEqual(waterContainersOnToday, containersBefore + scriptedContainers,
                       "the undone log is gone and the first one stayed")
        XCTAssertEqual(waterAmountOnToday, amountAfterFirst)

        openCoach()
        try auditAccessibility("Coach", knownIssues: """
            About 20 issues (8 contrast, 12 Dynamic Type, 1 clipped text; counts are from one run and \
            move by one or two between runs). About 17 are on elements of the \
            hidden Gym surface, which stays in the accessibility tree (Victoria/App/RootView.swift:174, \
            :179). On screen: in some runs, contrast on the quick-prompt chips (brand text on the \
            raised card, Features/Coach/CoachView.swift:1065); partial Dynamic Type on the navigation title and on a \
            message timestamp (CoachView.swift:194, :914).
            """)
    }

    /// j. `fail-500`: the provider is down. The friendly error is shown, nothing spins
    /// forever, a second attempt behaves the same, and the rest of the app still works.
    func testProviderFailureShowsTheErrorAndTheAppStaysUsable() {
        launch(script: "fail-500")
        waitForToday()
        let containersBefore = waterContainersOnToday

        openCoach()
        let repliesBefore = assistantMessages.count
        let error = app.staticTexts.matching(identifier: AccessibilityID.Coach.errorBanner)

        sendToCoach("Are you there")
        wait("the error to be shown") { error.count > 0 }
        wait("the typing indicator to go") { !self.coachIsTyping }
        XCTAssertEqual(assistantMessages.count, repliesBefore, "a failed turn adds no reply")

        // Again, with the provider still down.
        sendToCoach("Trying once more")
        wait("the typing indicator to go after the second attempt") { !self.coachIsTyping }
        wait("the error to be shown again") { error.count > 0 }
        XCTAssertEqual(assistantMessages.count, repliesBefore)
        XCTAssertEqual(userMessages(saying: "Are you there").count, 1, "each attempt is in the conversation once")
        XCTAssertEqual(userMessages(saying: "Trying once more").count, 1)
        XCTAssertTrue(waitShown(app.textFields, AccessibilityID.Coach.input).isEnabled, "the field is ready for another try")

        // The rest of the app is unaffected.
        dismissKeyboard()
        openTab(AccessibilityID.Tab.today)
        waitForToday()
        tap(app.buttons, AccessibilityID.Today.waterAdd)
        wait("water to log while the provider is down") { self.waterContainersOnToday == containersBefore + 1 }
        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
    }
}
