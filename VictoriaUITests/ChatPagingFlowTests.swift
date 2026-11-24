import XCTest

/// v. Loading earlier messages keeps what the reader is looking at in place (EVAL_REPORT 32).
///
/// Measured the way a person meets it: a 201-message conversation, scrolled to the top of
/// what is loaded with real swipes, left to come to rest, then "Load earlier messages"
/// tapped. The message that was at the top must be where it was. Automatic loading is
/// turned off (`--chat-debug-do hold`) so each page loads from rest, the worst case: while
/// a finger is moving, a shift hides inside the motion.
final class ChatPagingFlowTests: SproutUITestCase {

    /// Allowed movement of the held message. 0 is the goal; 2 pt allows for sub-point layout
    /// rounding between two snapshots.
    static let tolerance: CGFloat = 2

    private var messages: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
            [AccessibilityID.Coach.userMessage, AccessibilityID.Coach.assistantMessage]))
    }

    private var loadEarlier: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Load earlier messages")).firstMatch
    }

    /// The message nearest the top of the screen that is fully below the navigation bar.
    /// The label is only "You said" / "Vita said"; the text (unique per message: the seeded
    /// lines carry "(#n)") is the accessibility value.
    private func topVisibleMessage() -> (text: String, minY: CGFloat)? {
        let top = app.navigationBars.firstMatch.frame.maxY
        var best: (String, CGFloat)?
        for element in messages.allElementsBoundByIndex where element.exists {
            let f = element.frame
            guard f.minY >= top, f.maxY <= app.frame.maxY - 120,
                  let text = element.value as? String, text.contains("(#") else { continue }
            if best == nil || f.minY < best!.1 { best = (text, f.minY) }
        }
        return best.map { (text: $0.0, minY: $0.1) }
    }

    private func rest() { RunLoop.current.run(until: Date().addingTimeInterval(1.5)) }

    func testLoadingEarlierMessagesKeepsTheTopMessageInPlace() throws {
        app.launchArguments = ["--ui-testing", "--ui-test-fresh-defaults", "--seed-demo", "--demo-gain",
                               "--demo-tab", "coach", "--demo-long-chat", "201", "--chat-debug-do", "hold"]
        app.launch()
        wait("the conversation") { self.messages.count > 0 }

        var shifts: [CGFloat] = []
        for page in 1...3 {
            var swipes = 0
            while !(loadEarlier.exists && loadEarlier.isHittable), swipes < 40 {
                app.swipeDown(velocity: .fast)
                swipes += 1
            }
            XCTAssertTrue(loadEarlier.isHittable, "page \(page): reached the top of what is loaded")
            rest()
            let before = try XCTUnwrap(topVisibleMessage(), "page \(page): a message on screen")
            loadEarlier.tap()
            rest()
            let after = messages.matching(NSPredicate(format: "value == %@", before.text)).firstMatch
            XCTAssertTrue(after.exists, "page \(page): the held message still exists")
            let shift = after.frame.minY - before.minY
            shifts.append(shift)
            print("CHAT-PAGING page \(page): moved \(shift) pt (\(before.text.prefix(40)))")
        }
        print("CHAT-PAGING shifts: \(shifts)")
        for (i, shift) in shifts.enumerated() {
            XCTAssertLessThanOrEqual(abs(shift), Self.tolerance, "page \(i + 1) moved \(shift) pt")
        }
    }

    // MARK: - What the flipped list must not break

    private var input: XCUIElement { app.textViews[AccessibilityID.Coach.input].firstMatch.exists
        ? app.textViews[AccessibilityID.Coach.input].firstMatch
        : app.textFields[AccessibilityID.Coach.input].firstMatch }
    private var jumpToLatest: XCUIElement { app.buttons["coach.jumpToLatest"] }

    /// The seeded messages on screen, top to bottom, with their "(#n)" numbers.
    private func onScreen() -> [(n: Int, frame: CGRect)] {
        let top = app.navigationBars.firstMatch.frame.maxY
        return messages.allElementsBoundByIndex.compactMap { element -> (Int, CGRect)? in
            guard element.exists, let text = element.value as? String,
                  let r = text.range(of: #"\(#(\d+)\)"#, options: .regularExpression) else { return nil }
            let f = element.frame
            guard f.maxY > top, f.minY < app.frame.maxY else { return nil }
            let digits = text[r].dropFirst(2).dropLast()
            return Int(digits).map { ($0, f) }
        }
        .sorted { $0.1.minY < $1.1.minY }
        .map { (n: $0.0, frame: $0.1) }
    }

    private func launchLongChat(messages count: Int = 201) {
        app.launchArguments = ["--ui-testing", "--ui-test-fresh-defaults", "--seed-demo", "--demo-gain",
                               "--demo-tab", "coach", "--demo-long-chat", "\(count)"]
        app.launch()
        wait("the conversation") { !self.onScreen().isEmpty }
        rest()
    }

    /// Opens at the newest message, just above the input bar, oldest above newest.
    func testTheChatOpensAtTheNewestMessageInReadingOrder() {
        launchLongChat()
        let rows = onScreen()
        XCTAssertGreaterThan(rows.count, 2)
        XCTAssertEqual(rows.map(\.n), rows.map(\.n).sorted(), "older above newer: \(rows.map(\.n))")
        let newest = rows.last!
        XCTAssertLessThanOrEqual(newest.frame.maxY, input.frame.minY + 1, "the newest message is above the input bar")
        XCTAssertLessThan(input.frame.minY - newest.frame.maxY, 120, "and right above it, not a screen away")
        XCTAssertFalse(jumpToLatest.exists, "nothing to jump to at the newest message")
    }

    /// Far up the conversation, "jump to latest" returns to the same newest message.
    func testJumpToLatestReturnsToTheNewestMessage() {
        launchLongChat()
        let newest = try! XCTUnwrap(onScreen().last)
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        rest()
        XCTAssertTrue(jumpToLatest.waitForExistence(timeout: 5), "offered once away from the newest message")
        XCTAssertFalse(onScreen().contains { $0.n == newest.n }, "the newest message is off screen")
        jumpToLatest.tap()
        rest()
        let back = onScreen()
        XCTAssertEqual(back.last?.n, newest.n, "back at \(newest.n), got \(back.map(\.n))")
        XCTAssertEqual(back.last!.frame.maxY, newest.frame.maxY, accuracy: 2, "at the same place as when the chat opened")
        wait("the button goes") { !self.jumpToLatest.exists }
    }

    /// Scrolling up loads page after page by itself and reaches the first message: 121
    /// messages are three pages above the first one. A fast swipe moves about five messages
    /// here, on this list and on the unflipped one alike (measured), so 60 is ample.
    func testScrollingUpReachesTheBeginningOfTheConversation() {
        launchLongChat(messages: 121)
        let start = app.staticTexts["Beginning of your conversation"]
        var swipes = 0
        while !start.exists, swipes < 60 {
            app.swipeDown(velocity: .fast)
            swipes += 1
        }
        print("CHAT-PAGING reached the beginning in \(swipes) swipes")
        XCTAssertTrue(start.exists, "reached the beginning")
        rest()
        let rows = onScreen()
        XCTAssertEqual(rows.map(\.n), rows.map(\.n).sorted(), "still in reading order: \(rows.map(\.n))")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "value BEGINSWITH %@", "Hi ")).firstMatch.exists,
                      "the welcome, the first message, is there")
    }

    /// The keyboard pushes the conversation up with it: the newest message stays visible.
    func testTheKeyboardKeepsTheNewestMessageVisible() {
        launchLongChat()
        let newest = try! XCTUnwrap(onScreen().last)
        input.tap()
        wait("the keyboard") { self.app.keyboards.firstMatch.exists }
        rest()
        let field = input.frame
        let now = try! XCTUnwrap(onScreen().last)
        XCTAssertEqual(now.n, newest.n)
        XCTAssertLessThanOrEqual(now.frame.maxY, field.minY + 1, "above the input bar, which is above the keyboard")
        XCTAssertLessThan(field.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertLessThan(field.minY - now.frame.maxY, 120)
    }

    /// A message that arrives while the reader is further up does not move what they are
    /// reading; it is counted on "jump to latest" instead.
    func testAMessageArrivingWhileReadingFurtherUpMovesNothing() throws {
        app.launchArguments = ["--ui-testing", "--ui-test-fresh-defaults", "--seed-demo", "--demo-gain",
                               "--demo-tab", "coach", "--demo-long-chat", "201", "--chat-debug-do", "arrive:12"]
        app.launch()
        wait("the conversation") { !self.onScreen().isEmpty }
        for _ in 0..<3 { app.swipeDown() }
        rest()
        let before = try XCTUnwrap(topVisibleMessage())
        let jump = app.buttons.matching(NSPredicate(format: "label == %@", "Jump to latest message, 1 new")).firstMatch
        XCTAssertTrue(jump.waitForExistence(timeout: 30), "the arrival is counted")
        rest()
        let after = messages.matching(NSPredicate(format: "value == %@", before.text)).firstMatch
        XCTAssertTrue(after.exists)
        let shift = after.frame.minY - before.minY
        print("CHAT-PAGING arrival moved the reader \(shift) pt")
        XCTAssertLessThanOrEqual(abs(shift), Self.tolerance, "moved \(shift) pt")
        jump.tap()
        rest()
        XCTAssertEqual(onScreen().last?.n, 9999, "jump to latest shows the message that arrived")
    }

    /// The order assistive technologies get the chat in, by identifier, as the tree lists it.
    private func readingOrder() -> [(id: String, n: Int?, minY: CGFloat)] {
        app.descendants(matching: .any).allElementsBoundByIndex.compactMap { e in
            let id = e.identifier
            let isMessage = id == AccessibilityID.Coach.userMessage || id == AccessibilityID.Coach.assistantMessage
            let isEarlier = e.elementType == .button && e.label.hasPrefix("Load earlier messages")
            guard isMessage || isEarlier || id == AccessibilityID.Coach.input else { return nil }
            var n: Int?
            if isMessage, let text = e.value as? String,
               let r = text.range(of: #"\(#(\d+)\)"#, options: .regularExpression) {
                n = Int(text[r].dropFirst(2).dropLast())
            }
            return (id: isEarlier ? "earlier" : id, n: n, minY: e.frame.minY)
        }
    }

    /// VoiceOver reads the chat as it is drawn: top to bottom, oldest to newest, then the
    /// input bar. The rows are declared newest first for the flip, and this order was
    /// reversed before `ChatReadingOrder` (docs/chat-standards.md, section 1).
    func testVoiceOverReadsTheChatInTheOrderItIsDrawn() {
        app.launchArguments = ["--ui-testing", "--ui-test-fresh-defaults", "--seed-demo", "--demo-gain",
                               "--demo-tab", "coach", "--demo-long-chat", "201", "--chat-debug-do", "hold"]
        app.launch()
        wait("the conversation") { !self.onScreen().isEmpty }
        rest()

        func check(_ where: String) {
            let order = readingOrder()
            print("CHAT-ORDER \(`where`): " + order.map { "\($0.id.split(separator: ".").last ?? "")#\($0.n.map(String.init) ?? "-")@\(Int($0.minY))" }.joined(separator: " "))
            let messages = order.filter { $0.n != nil }
            XCTAssertGreaterThan(messages.count, 2, "\(`where`): messages exposed")
            XCTAssertEqual(messages.map { $0.n! }, messages.map { $0.n! }.sorted(), "\(`where`): oldest to newest")
            XCTAssertEqual(messages.map(\.minY), messages.map(\.minY).sorted(), "\(`where`): top to bottom")
            let input = order.firstIndex { $0.id == AccessibilityID.Coach.input }
            let lastMessage = order.lastIndex { $0.n != nil }
            XCTAssertNotNil(input, "\(`where`): the input bar is exposed")
            if let input, let lastMessage {
                XCTAssertGreaterThan(input, lastMessage, "\(`where`): the input bar after the conversation")
            }
            if let earlier = order.firstIndex(where: { $0.id == "earlier" }),
               let firstMessage = order.firstIndex(where: { $0.n != nil }) {
                XCTAssertLessThan(earlier, firstMessage, "\(`where`): load earlier before the messages")
            }
        }

        check("at the newest")
        var swipes = 0
        while !(loadEarlier.exists && loadEarlier.isHittable), swipes < 40 {
            app.swipeDown(velocity: .fast)
            swipes += 1
        }
        XCTAssertTrue(loadEarlier.isHittable, "reached the top of what is loaded")
        rest()
        check("at the top of what is loaded")
        loadEarlier.tap()
        rest()
        check("after loading earlier")
    }
}
