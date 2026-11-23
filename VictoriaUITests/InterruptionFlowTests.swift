import XCTest

/// Leaving the app in the middle of something and coming back (flow k).
final class InterruptionFlowTests: SproutUITestCase {

    /// k. Backgrounded with the manual-food sheet half filled in: on return the sheet is
    /// still there with what was typed (or cleanly gone), and saving makes one entry.
    func testBackgroundingInTheMiddleOfTheManualFoodSheet() {
        let food = "Interrupted toast"
        launch()
        waitForToday()
        let eatenBefore = caloriesEatenOnToday
        openTab(AccessibilityID.Tab.nutrients)
        waitShown(app.scrollViews, AccessibilityID.Nutrients.root)

        openManualFoodSheet()
        fillManualFoodSheet(name: food, calories: 111)
        backgroundAndReturn()

        // The sheet's Save button is in its navigation bar, so it is there whenever the
        // sheet is (the form's rows are not: a row scrolled out of view leaves the tree).
        let save = app.buttons[AccessibilityID.AddFood.save]
        if appears(save, timeout: 3) {
            XCTAssertEqual(app.textFields[AccessibilityID.AddFood.calories].value as? String, "111",
                           "what was typed is still in the sheet")
            XCTAssertEqual(foodRows(named: food).count, 0, "nothing was saved by leaving")
            save.tap()
            wait("the add-food sheet to close") { !save.exists }
            wait("the entry to be listed once, under the name that was typed") { self.foodRows(named: food).count == 1 }
            openTab(AccessibilityID.Tab.today)
            waitForToday()
            XCTAssertEqual(caloriesEatenOnToday, eatenBefore + 111, "one entry, counted once")
        } else {
            // Cleanly dismissed is also a valid state, as long as nothing half-made was saved.
            waitShown(app.scrollViews, AccessibilityID.Nutrients.root)
            XCTAssertEqual(foodRows(named: food).count, 0)
            openTab(AccessibilityID.Tab.today)
            waitForToday()
            XCTAssertEqual(caloriesEatenOnToday, eatenBefore)
        }
    }

    /// k. Backgrounded while the coach is replying (`coach-slow` takes a few seconds): on
    /// return the turn finishes once, with one copy of the message and one reply.
    func testBackgroundingInTheMiddleOfACoachTurn() {
        let message = "How am I doing today"
        launch(script: "coach-slow")
        waitForToday()
        openCoach()
        XCTAssertEqual(scriptedReplies.count, 0)

        sendToCoach(message)
        wait("the coach to be mid-turn", timeout: 3) { self.coachIsTyping }
        backgroundAndReturn()

        wait("the reply to arrive after returning") { self.scriptedReplies.count == 1 }
        wait("the typing indicator to go") { !self.coachIsTyping }
        XCTAssertEqual(userMessages(saying: message).count, 1, "the message is in the conversation once")
        XCTAssertEqual(scriptedReplies.count, 1, "and it got one reply")
        XCTAssertEqual(app.staticTexts.matching(identifier: AccessibilityID.Coach.errorBanner).count, 0)
        XCTAssertTrue(waitShown(app.textFields, AccessibilityID.Coach.input).isEnabled)

        dismissKeyboard()
        openTab(AccessibilityID.Tab.today)
        waitForToday()
    }
}
