import XCTest

/// Base class of the UI smoke flows: how a flow launches the app, finds things, waits,
/// and audits a screen.
///
/// Every launch passes `--ui-testing` (in-memory store, no permission prompt, no network
/// for the model; see `UITestHooks` in the app), so a flow starts from a known state and
/// leaves nothing behind in the simulator's real store.
class SproutUITestCase: XCTestCase {

    let app = XCUIApplication()

    /// Long enough for a cold launch on a loaded CI runner; a wait returns as soon as
    /// its condition holds, so a passing run does not spend it.
    static let timeout: TimeInterval = 20

    /// The scripted model's replies start with this (`UITestAIScript` in the app).
    static let scriptedReplyPrefix = "Scripted reply"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // `--ui-testing` must have kept every system permission alert away.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertFalse(alert.exists, "A system alert is showing over the app: \(alert.exists ? alert.label : "")")
        app.terminate()
    }

    // MARK: - Launching

    /// Launch (or relaunch) the app under `--ui-testing`.
    /// - Parameters:
    ///   - seeded: seed the dark demo profile (`--seed-demo --demo-gain`); false is a fresh install.
    ///   - tab: the `--demo-tab` value. `"today"` (the default) opens Home on Today whatever
    ///     mode an earlier launch stored; `"workouts"` opens Gym; nil passes no `--demo-tab`,
    ///     so the stored mode decides, as on a normal launch.
    ///   - script: a `--ui-test-scripted-ai` name; nil leaves the app with no key.
    func launch(seeded: Bool = true, tab: String? = "today", script: String? = nil) {
        var arguments = ["--ui-testing"]
        if seeded { arguments += ["--seed-demo", "--demo-gain"] }
        if let tab { arguments += ["--demo-tab", tab] }
        if let script { arguments.append("--ui-test-scripted-ai=\(script)") }
        app.launchArguments = arguments
        app.launch()
    }

    /// Send the app to the background and bring it back, as a user leaving and returning.
    func backgroundAndReturn(file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.press(.home)
        wait("the app to leave the foreground", file: file, line: line) { self.app.state != .runningForeground }
        app.activate()
        wait("the app to return to the foreground", file: file, line: line) { self.app.state == .runningForeground }
    }

    // MARK: - Waiting

    /// Poll a condition until it holds or the timeout passes; fails the test on a timeout.
    @discardableResult
    func wait(_ what: String, timeout: TimeInterval = SproutUITestCase.timeout,
              file: StaticString = #filePath, line: UInt = #line,
              until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        if condition() { return true }
        XCTFail("Timed out after \(Int(timeout))s waiting for \(what)", file: file, line: line)
        return false
    }

    /// True once the element exists. `waitForExistence` alone costs a second even when
    /// the element is already there, so look first.
    func appears(_ element: XCUIElement, timeout: TimeInterval = SproutUITestCase.timeout) -> Bool {
        element.exists || element.waitForExistence(timeout: timeout)
    }

    // MARK: - Known defects

    /// Assert something that is known to be wrong in the app today, as an expected
    /// failure with the reason. The flow carries on afterwards: with
    /// `continueAfterFailure` false an expected failure would otherwise END the test
    /// there and report it as passed, silently skipping the rest of the flow.
    func expectKnownDefect(_ reason: String, _ assertions: () -> Void) {
        let stopsOnFailure = continueAfterFailure
        continueAfterFailure = true
        XCTExpectFailure(reason) { assertions() }
        continueAfterFailure = stopsOnFailure
    }

    // MARK: - Finding

    /// The first match that is on screen and can be touched, or nil.
    ///
    /// Home and Gym both stay alive under the switch and BOTH stay in the accessibility
    /// tree, so "exists" does not mean "shown"; a hidden surface's elements exist and are
    /// not hittable. A flow asserts what the user can see and touch.
    func shown(_ query: XCUIElementQuery, _ identifier: String) -> XCUIElement? {
        let matches = query.matching(identifier: identifier)
        for index in 0..<matches.count {
            let element = matches.element(boundBy: index)
            if element.isHittable { return element }
        }
        return nil
    }

    func isShown(_ query: XCUIElementQuery, _ identifier: String) -> Bool {
        shown(query, identifier) != nil
    }

    /// Wait until an element with this identifier is on screen, and return it.
    @discardableResult
    func waitShown(_ query: XCUIElementQuery, _ identifier: String,
                   timeout: TimeInterval = SproutUITestCase.timeout,
                   file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        var found: XCUIElement?
        wait("\(identifier) to be on screen", timeout: timeout, file: file, line: line) {
            found = self.shown(query, identifier)
            return found != nil
        }
        return found ?? query.matching(identifier: identifier).firstMatch
    }

    func waitHidden(_ query: XCUIElementQuery, _ identifier: String,
                    timeout: TimeInterval = SproutUITestCase.timeout,
                    file: StaticString = #filePath, line: UInt = #line) {
        wait("\(identifier) to leave the screen", timeout: timeout, file: file, line: line) {
            !self.isShown(query, identifier)
        }
    }

    /// Wait for the element with this identifier and tap it. XCUITest scrolls it into
    /// view first when it is below the fold or under the keyboard. For an identifier
    /// that is on both surfaces (the mode switch), use `switchMode(to:)`.
    func tap(_ query: XCUIElementQuery, _ identifier: String,
             file: StaticString = #filePath, line: UInt = #line) {
        let element = query.matching(identifier: identifier).firstMatch
        guard appears(element) else {
            return XCTFail("\(identifier) does not exist", file: file, line: line)
        }
        element.tap()
    }

    /// Wait for the field with this identifier, give it focus and type into it.
    func type(_ text: String, into identifier: String,
              file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields.matching(identifier: identifier).firstMatch
        guard appears(field) else {
            return XCTFail("\(identifier) does not exist", file: file, line: line)
        }
        field.tap()
        field.typeText(text)
    }

    /// The first whole number in a piece of text ("Eaten, 1,355" is 1355; "2 / 5" is 2).
    /// Flows read figures this way so rewording the words around a number breaks nothing.
    func firstInteger(in text: String) -> Int? {
        var digits = ""
        for character in text {
            if character.isWholeNumber {
                digits.append(character)
            } else if character == ",", !digits.isEmpty {
                continue   // a grouping separator inside a number
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits)
    }

    /// The first whole number in the label of the (possibly off-screen) element with this identifier.
    func figure(_ query: XCUIElementQuery, _ identifier: String,
                file: StaticString = #filePath, line: UInt = #line) -> Int {
        let element = query.matching(identifier: identifier).firstMatch
        guard appears(element) else {
            XCTFail("\(identifier) does not exist", file: file, line: line)
            return -1
        }
        guard let value = firstInteger(in: element.label) else {
            XCTFail("\(identifier) shows no number: \"\(element.label)\"", file: file, line: line)
            return -1
        }
        return value
    }

    // MARK: - Home tabs and the mode switch

    func openTab(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(app.tabBars.buttons, identifier, file: file, line: line)
    }

    var tabBarIsShown: Bool { isShown(app.tabBars.buttons, AccessibilityID.Tab.today) }

    func waitForTabBar(file: StaticString = #filePath, line: UInt = #line) {
        wait("the tab bar to be on screen", file: file, line: line) { self.tabBarIsShown }
    }

    func waitForNoTabBar(file: StaticString = #filePath, line: UInt = #line) {
        wait("the tab bar to be off screen", file: file, line: line) { !self.tabBarIsShown }
    }

    /// Tap a segment of the Home | Gym switch. Each surface has its own copy of the
    /// switch, so this taps the one that is on screen.
    func switchMode(to identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        waitShown(app.buttons, identifier, file: file, line: line).tap()
    }

    func waitForToday(file: StaticString = #filePath, line: UInt = #line) {
        waitShown(app.scrollViews, AccessibilityID.Today.root, file: file, line: line)
    }

    func waitForWorkouts(file: StaticString = #filePath, line: UInt = #line) {
        waitShown(app.scrollViews, AccessibilityID.Workouts.root, file: file, line: line)
    }

    /// The software keyboard covers the tab bar; drag the content down into it, the way
    /// the screens dismiss it (`scrollDismissesKeyboard`).
    func dismissKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        guard app.keyboards.firstMatch.exists else { return }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        from.press(forDuration: 0.05, thenDragTo: to)
        wait("the keyboard to go away", file: file, line: line) { !self.app.keyboards.firstMatch.exists }
    }

    // MARK: - Figures on Today

    var caloriesEatenOnToday: Int { figure(app.staticTexts, AccessibilityID.Today.caloriesEaten) }
    var waterContainersOnToday: Int { figure(app.staticTexts, AccessibilityID.Today.waterCount) }
    var waterAmountOnToday: Int { figure(app.staticTexts, AccessibilityID.Today.waterAmount) }

    // MARK: - Nutrients: the manual food sheet

    func foodRows(named name: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                         AccessibilityID.Nutrients.foodRow, name))
    }

    func openManualFoodSheet(file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons, AccessibilityID.Nutrients.add, file: file, line: line)
        tap(app.buttons, AccessibilityID.Nutrients.addManual, file: file, line: line)
    }

    func fillManualFoodSheet(name: String, calories: Int, file: StaticString = #filePath, line: UInt = #line) {
        type(name, into: AccessibilityID.AddFood.name, file: file, line: line)
        type(String(calories), into: AccessibilityID.AddFood.calories, file: file, line: line)
    }

    /// Log one food through Nutrients → add → manual entry, and wait for the sheet to close.
    func logFoodManually(name: String, calories: Int, file: StaticString = #filePath, line: UInt = #line) {
        openManualFoodSheet(file: file, line: line)
        fillManualFoodSheet(name: name, calories: calories, file: file, line: line)
        tap(app.buttons, AccessibilityID.AddFood.save, file: file, line: line)
        wait("the add-food sheet to close", file: file, line: line) {
            !self.app.buttons[AccessibilityID.AddFood.save].exists
        }
    }

    // MARK: - Coach

    var assistantMessages: XCUIElementQuery {
        app.staticTexts.matching(identifier: AccessibilityID.Coach.assistantMessage)
    }

    func userMessages(saying text: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND value == %@",
                                             AccessibilityID.Coach.userMessage, text))
    }

    var scriptedReplies: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND value BEGINSWITH %@",
                                             AccessibilityID.Coach.assistantMessage, Self.scriptedReplyPrefix))
    }

    var coachIsTyping: Bool { app.otherElements[AccessibilityID.Coach.typing].exists }

    func openCoach(file: StaticString = #filePath, line: UInt = #line) {
        openTab(AccessibilityID.Tab.coach, file: file, line: line)
        waitShown(app.textFields, AccessibilityID.Coach.input, file: file, line: line)
    }

    /// Type a message into the coach's field and send it with the send button.
    func sendToCoach(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        type(text, into: AccessibilityID.Coach.input, file: file, line: line)
        tap(app.buttons, AccessibilityID.Coach.send, file: file, line: line)
        wait("the sent message to appear in the conversation", file: file, line: line) {
            self.userMessages(saying: text).count >= 1
        }
    }

    // MARK: - Accessibility audit

    /// Run Apple's accessibility audit on the screen that is showing.
    ///
    /// Every issue is logged (`A11Y-AUDIT` lines in the test log, and an attachment),
    /// with whether its element is on screen: the audit also walks the surface that is
    /// hidden under the Home | Gym switch, because that surface stays in the tree.
    /// Pass `knownIssues` when the audit of this screen is known to report issues: the
    /// call is then an expected failure with that summary, so the issues stay visible in
    /// every result and the flow's own assertions still guard behaviour. The expected
    /// failure is strict: when the screen is clean the test says so and the summary goes.
    func auditAccessibility(_ screen: String, knownIssues: String? = nil) throws {
        var found: [String] = []
        let run = {
            try self.app.performAccessibilityAudit { issue in
                let element = issue.element.map { element -> String in
                    let identifier = element.identifier.isEmpty ? "" : " #\(element.identifier)"
                    // Both surfaces are in the tree, so say which an issue is on.
                    let place = element.isHittable ? "on screen" : "not on screen"
                    return "\(place) | type \(element.elementType.rawValue)\(identifier) \"\(element.label.prefix(60))\""
                } ?? "(no element)"
                found.append("\(Self.name(of: issue.auditType)) | \(element) | \(issue.compactDescription)")
                return false
            }
        }
        // The audit records one failure per issue. Let it record them all (the first
        // must not stop the test) so the log and the attachment hold the whole list.
        let stopsOnFailure = continueAfterFailure
        continueAfterFailure = true
        var thrown: Error?
        do {
            if let knownIssues {
                try XCTExpectFailure("Accessibility audit of \(screen): \(knownIssues)") { try run() }
            } else {
                try run()
            }
        } catch {
            thrown = error
        }
        continueAfterFailure = stopsOnFailure

        for issue in found { print("A11Y-AUDIT | \(screen) | \(issue)") }
        print("A11Y-AUDIT-SUMMARY | \(screen) | \(found.count) issues")
        let attachment = XCTAttachment(string: found.isEmpty ? "no issues" : found.joined(separator: "\n"))
        attachment.name = "Accessibility audit: \(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let thrown { throw thrown }
    }

    private static func name(of type: XCUIAccessibilityAuditType) -> String {
        var names: [String] = []
        if type.contains(.contrast) { names.append("contrast") }
        if type.contains(.elementDetection) { names.append("elementDetection") }
        if type.contains(.hitRegion) { names.append("hitRegion") }
        if type.contains(.sufficientElementDescription) { names.append("sufficientElementDescription") }
        if type.contains(.dynamicType) { names.append("dynamicType") }
        if type.contains(.textClipped) { names.append("textClipped") }
        if type.contains(.trait) { names.append("trait") }
        return names.isEmpty ? "other(\(type.rawValue))" : names.joined(separator: "+")
    }
}
