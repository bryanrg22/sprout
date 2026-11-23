import XCTest

/// u. Kilograms (EVAL_REPORT 31): switching in Settings changes what Progress and the
/// weigh-in sheet show, and back again.
final class UnitsFlowTests: SproutUITestCase {

    private func chooseUnit(_ label: String) {
        tap(app.buttons, AccessibilityID.Today.settings)
        let picker = app.buttons[AccessibilityID.Settings.weightUnit]
        wait("the weight unit picker") { picker.exists }
        settle(picker)
        picker.tap()
        let option = app.buttons[label]
        wait("the \(label) option") { option.exists }
        settle(option)
        option.tap()
        tap(app.buttons, AccessibilityID.Settings.done)
        waitForToday()
    }

    private func texts(containing s: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s))
    }

    /// The number in the first text that holds `suffix` ("0.4 kg/wk" → 0.4).
    private func rate(_ suffix: String) -> Double? {
        let label = texts(containing: suffix).firstMatch.label
        return Double(label.components(separatedBy: " ").first { Double($0) != nil } ?? "")
    }

    func testKilogramsReachProgressAndTheWeighInSheetAndBack() throws {
        addTeardownBlock { self.app.terminate() }
        launch()
        waitForToday()

        chooseUnit("Kilograms (kg)")
        openTab(AccessibilityID.Tab.progress)
        waitShown(app.scrollViews, AccessibilityID.Progress.root)
        // (The chart's goal and start labels are not exposed to accessibility; the trend's unit
        // and the weekly rate are.) The seeded weights have random noise, so no exact number.
        wait("the trend in kilograms") { self.app.staticTexts["kg"].exists }
        wait("the rate in kilograms") { self.texts(containing: "kg/wk").firstMatch.exists }
        let kgRate = try XCTUnwrap(rate("kg/wk"))
        XCTAssertFalse(texts(containing: " lb").firstMatch.exists, "no pound label is left on Progress")

        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "weigh-in")).firstMatch.tap()
        let cancel = app.buttons["Cancel"]
        wait("the weigh-in sheet") { cancel.exists }
        XCTAssertTrue(app.staticTexts["kg"].exists, "the sheet's number is in kilograms")
        settle(cancel)
        cancel.tap()
        wait("the sheet to close") { !cancel.exists }

        openTab(AccessibilityID.Tab.today)
        waitForToday()
        chooseUnit("Pounds (lb)")
        openTab(AccessibilityID.Tab.progress)
        wait("the trend back in pounds") { self.app.staticTexts["lb"].exists }
        wait("the rate back in pounds") { self.texts(containing: "lb/wk").firstMatch.exists }
        let lbRate = try XCTUnwrap(rate("lb/wk"))
        XCTAssertFalse(texts(containing: "kg").firstMatch.exists)
        // Same stored rate, two units: each shown to one decimal, so within 0.1 of exact.
        XCTAssertEqual(kgRate, lbRate * 0.45359237, accuracy: 0.1, "\(kgRate) kg/wk vs \(lbRate) lb/wk")
    }
}
