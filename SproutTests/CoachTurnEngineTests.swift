import XCTest
import SwiftData
@testable import Sprout

/// The coach's turn loop (`CoachTurnEngine`), driven the way the app drives it: a real
/// in-memory store on the full schema, the real provider clients, and scripted provider
/// responses in each of the three wire formats (Anthropic Messages, OpenAI Chat Completions,
/// OpenAI Responses). Nothing here reaches a provider or reads a stored key.
///
/// Every scenario runs once per wire unless its name says otherwise, and each assertion
/// message names the wire that failed.
@MainActor
final class CoachTurnEngineTests: XCTestCase {

    // MARK: - Rig

    struct Rig {
        let wire: ChatWire
        let container: ModelContainer
        let context: ModelContext
        let profile: UserProfile
        let clock: TickingClock
        let background: RecordingBackgroundTasks
        let transport: TurnTransport
        let engine: CoachTurnEngine
        /// Opened by a test to let the Undo banner's five-second wait end.
        let undoGate: Gate

        func messages() throws -> [ChatMessage] {
            try TestStore.fetchAll(ChatMessage.self, in: container, sortBy: [SortDescriptor(\.createdAt)])
        }

        /// `role: content` for every stored row, oldest first; a decision marker reads
        /// `decision(yes|no): summary`.
        func transcript() throws -> [String] {
            try messages().map { row in
                if let summary = row.decisionSummary {
                    return "decision(\(row.decisionAccepted == true ? "yes" : "no")): \(summary)"
                }
                return "\(row.roleRaw): \(row.content)"
            }
        }

        func waterEntries() throws -> [WaterEntry] { try TestStore.fetchAll(WaterEntry.self, in: container) }
    }

    private func rig(_ wire: ChatWire, _ steps: [TurnTransport.Step],
                     key: String = "test-key-not-real") throws -> Rig {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let profile = UserProfile()
        profile.name = "Alex"
        profile.startWeightLbs = 158
        profile.goalWeightLbs = 140
        profile.pace = .relaxed
        profile.dailyStepGoal = 8000
        profile.onboardingComplete = true
        context.insert(profile)
        try context.save()

        let clock = TickingClock()
        let background = RecordingBackgroundTasks()
        let transport = TurnTransport(steps)
        let undoGate = Gate()
        var env = CoachTurnEngine.Environment()
        env.now = { clock.now() }
        env.sleep = { _ in await undoGate.wait() }
        env.background = background
        env.runtime = wire.runtime(transport, key: key)
        let engine = CoachTurnEngine(context: context, profile: profile, env: env)
        return Rig(wire: wire, container: container, context: context, profile: profile, clock: clock,
                   background: background, transport: transport, engine: engine, undoGate: undoGate)
    }

    /// Stored rows created directly, as an existing conversation.
    @discardableResult
    private func seed(_ rig: Rig, _ rows: [(role: String, content: String)]) throws -> [ChatMessage] {
        let made = rows.map { ChatMessage(role: $0.role, content: $0.content, createdAt: rig.clock.now()) }
        made.forEach(rig.context.insert)
        try rig.context.save()
        return made
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 5,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(what)", file: file, line: line) }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private let water20 = ScriptedToolCall("call_water_1", "log_water", ["oz": 20])
    private let steps12k = ScriptedToolCall("call_steps_1", "set_step_goal", ["steps": 12000])

    // MARK: - Sending and the first call

    func testPlainReplyIsSavedAndTheUsersMessageIsStoredBeforeTheCall() async throws {
        for wire in ChatWire.allCases {
            let gate = Gate()
            let r = try rig(wire, [.held(gate, .ok(wire.turn("You're doing well this week.")))])
            let task = try XCTUnwrap(r.engine.send(text: "  How am I doing?  "), "\(wire)")

            XCTAssertTrue(r.engine.isSending, "\(wire)")
            await waitUntil("the request to be in flight") { r.transport.requestCount == 1 }
            // The request is in flight and unanswered; the user's message is already in the store.
            XCTAssertEqual(try r.transcript(), ["user: How am I doing?"], "\(wire)")

            gate.open()
            await task.value

            XCTAssertFalse(r.engine.isSending, "\(wire)")
            XCTAssertNil(r.engine.failure, "\(wire)")
            XCTAssertNil(r.engine.pendingTool, "\(wire)")
            XCTAssertEqual(try r.transcript(),
                           ["user: How am I doing?", "assistant: You're doing well this week."], "\(wire)")
            XCTAssertEqual(r.engine.streamingMessageID, try r.messages().last?.id,
                           "\(wire): the fresh reply is the one that types itself out")
            XCTAssertEqual(r.transport.requests.first?.url?.path, wire.path, "\(wire)")
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire)")
            XCTAssertTrue(r.transport.bodyText(0).contains("How am I doing?"), "\(wire)")
            XCTAssertFalse(wire.forbidsTools(r.transport.body(0)), "\(wire)")
            XCTAssertFalse((r.transport.body(0)["tools"] as? [Any] ?? []).isEmpty,
                           "\(wire): the tool schemas travel with the first call")
            XCTAssertEqual(r.engine.hapticTick, 1, "\(wire)")
        }
    }

    func testEmptyOrWhitespaceTextSendsNothing() async throws {
        let r = try rig(.anthropic, [])
        XCTAssertNil(r.engine.send(text: "   \n "))
        XCTAssertEqual(try r.transcript(), [])
        XCTAssertEqual(r.transport.requestCount, 0)
        XCTAssertFalse(r.engine.isSending)
    }

    func testAPhotoAloneIsAMessageAndTravelsAsAnImageBlock() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn("That looks like oatmeal."))])
            let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
            await r.engine.send(text: "", imageData: jpeg)?.value

            let rows = try r.messages()
            XCTAssertEqual(rows.first?.imageData, jpeg, "\(wire)")
            XCTAssertEqual(rows.first?.content, "", "\(wire)")
            XCTAssertTrue(r.transport.bodyText(0).contains(jpeg.base64EncodedString()),
                          "\(wire): the photo is in the request")
            XCTAssertEqual(rows.last?.content, "That looks like oatmeal.", "\(wire)")
        }
    }

    func testAnEmptyReplyBecomesTheGentleFallback() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn(nil))])
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(try r.transcript(), ["user: hello", "assistant: I'm here 💚"], "\(wire)")
            XCTAssertNil(r.engine.failure, "\(wire)")
            XCTAssertNil(r.engine.streamingMessageID, "\(wire): the fallback does not type itself out")
        }
    }

    // MARK: - History sent to the model

    func testHistoryIsTheLastSixteenRealMessagesStartingOnAUserTurn() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn("ok"))])
            r.context.insert(ChatMessage(role: "assistant", content: "WELCOME-SEED",
                                         createdAt: r.clock.now(), isSystemSeed: true))
            // 20 alternating messages m01…m20, with a decision marker in the middle.
            for index in 1...20 {
                r.context.insert(ChatMessage(role: index % 2 == 1 ? "user" : "assistant",
                                             content: String(format: "m%02d", index), createdAt: r.clock.now()))
                if index == 12 {
                    r.context.insert(ChatMessage(role: "assistant", content: "", createdAt: r.clock.now(),
                                                 decisionSummary: "DECISION-MARKER", decisionAccepted: true))
                }
            }
            try r.context.save()

            await r.engine.send(text: "newest")?.value

            // 21 real messages; the last 16 are m06…m20 + newest. m06 is the assistant's, and a
            // conversation has to open on the user, so the window starts at m07.
            let text = r.transport.bodyText(0)
            XCTAssertFalse(text.contains("m05"), "\(wire)")
            XCTAssertFalse(text.contains("m06"), "\(wire): a leading assistant message is dropped")
            XCTAssertTrue(text.contains("m07"), "\(wire)")
            XCTAssertTrue(text.contains("m20"), "\(wire)")
            XCTAssertTrue(text.contains("newest"), "\(wire)")
            XCTAssertFalse(text.contains("WELCOME-SEED"), "\(wire): the canned welcome is never sent")
            XCTAssertFalse(text.contains("DECISION-MARKER"), "\(wire): a decision marker is never sent")
        }
    }

    func testHistoryWindowRule() {
        let clock = TickingClock()
        func row(_ role: String, _ content: String, seed: Bool = false, decision: String? = nil,
                 image: Data? = nil) -> ChatMessage {
            ChatMessage(role: role, content: content, imageData: image, createdAt: clock.now(),
                        isSystemSeed: seed, decisionSummary: decision, decisionAccepted: decision.map { _ in true })
        }
        XCTAssertEqual(CoachTurnEngine.historyWindow([]).count, 0)
        XCTAssertEqual(CoachTurnEngine.historyWindow([row("assistant", "seed", seed: true)]).count, 0)
        XCTAssertEqual(CoachTurnEngine.historyWindow([row("assistant", "a"), row("assistant", "b")]).count, 0,
                       "with no user turn there is nothing to send")
        // An empty message (no text, no photo) is not a turn; a photo with no text is.
        let window = CoachTurnEngine.historyWindow([
            row("user", "one"), row("assistant", ""), row("user", "", image: Data([1])),
            row("assistant", "", decision: "x"), row("assistant", "two"),
        ])
        XCTAssertEqual(window.map(\.content), ["one", "", "two"])
        XCTAssertNotNil(window[1].imageData)

        let long = (1...40).map { row($0 % 2 == 1 ? "user" : "assistant", "m\($0)") }
        let last = CoachTurnEngine.historyWindow(long)
        XCTAssertEqual(last.count, 16)
        XCTAssertEqual(last.first?.content, "m25")
        XCTAssertEqual(last.last?.content, "m40")

        let api = CoachTurnEngine.apiMessages(window)
        XCTAssertEqual(api[0].content as? String, "one")
        XCTAssertEqual((api[1].content as? [[String: Any]])?.first?["type"] as? String, "image")
        XCTAssertEqual((api[1].content as? [[String: Any]])?.count, 1, "no empty text block beside a photo")
    }

    func testRecentHistoryFetchMatchesTheWindowRuleOverTheWholeConversation() throws {
        let r = try rig(.anthropic, [])
        r.context.insert(ChatMessage(role: "assistant", content: "seed", createdAt: r.clock.now(), isSystemSeed: true))
        for index in 1...60 {
            r.context.insert(ChatMessage(role: index % 2 == 1 ? "user" : "assistant", content: "m\(index)",
                                         createdAt: r.clock.now()))
            if index % 7 == 0 {
                r.context.insert(ChatMessage(role: "assistant", content: "", createdAt: r.clock.now(),
                                             decisionSummary: "d\(index)", decisionAccepted: false))
            }
        }
        try r.context.save()
        let everything = try r.context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(r.engine.recentHistory().map(\.id), CoachTurnEngine.historyWindow(everything).map(\.id),
                       "the limited fetch selects exactly what filtering the whole table selected")
    }

    // MARK: - A tool that applies at once (with Undo)

    func testAQuickLogIsAppliedAtOnceEchoedBackAndCanBeUndone() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn("Logging that.", tools: [water20])),
                                   .ok(wire.turn("Done, 20 oz logged."))])
            await r.engine.send(text: "log 20 oz of water")?.value

            XCTAssertEqual(try r.waterEntries().map(\.amountOz), [20], "\(wire): the log was written")
            XCTAssertEqual(try r.transcript(), ["user: log 20 oz of water", "assistant: Logging that.",
                                                "assistant: Done, 20 oz logged."], "\(wire)")
            XCTAssertNil(r.engine.pendingTool, "\(wire): a quick log needs no confirmation")
            XCTAssertEqual(r.engine.undoToast?.summary, "log 20 oz of water", "\(wire)")

            // The follow-up call carries the model's own tool call and exactly one result for it.
            XCTAssertEqual(r.transport.requestCount, 2, "\(wire)")
            let followUp = r.transport.body(1)
            XCTAssertEqual(wire.echoedToolCallIDs(followUp), ["call_water_1"], "\(wire)")
            let results = wire.toolResults(followUp)
            XCTAssertEqual(results.map(\.id), ["call_water_1"], "\(wire)")
            XCTAssertEqual(results.first?.text, "Applied. Logged 20 oz of water.", "\(wire)")
            if wire == .anthropic { XCTAssertEqual(results.first?.isError, false) }
            XCTAssertFalse(wire.forbidsTools(followUp), "\(wire)")

            r.engine.performUndo()
            XCTAssertEqual(try r.waterEntries().count, 0, "\(wire): Undo removed the entry")
            XCTAssertNil(r.engine.undoToast, "\(wire)")
            XCTAssertEqual(r.engine.hapticTick, 2, "\(wire): send, then undo")
        }
    }

    func testTheUndoBannerDismissesItselfAndUndoAfterThatDoesNothing() async throws {
        let r = try rig(.anthropic, [.ok(ChatWire.anthropic.turn(nil, tools: [water20])),
                                     .ok(ChatWire.anthropic.turn("Logged."))])
        await r.engine.send(text: "log water")?.value
        XCTAssertNotNil(r.engine.undoToast)

        r.undoGate.open()   // the injected five-second wait ends
        await waitUntil("the banner to dismiss") { r.engine.undoToast == nil }
        r.engine.performUndo()
        XCTAssertEqual(try r.waterEntries().count, 1, "with no banner there is nothing to undo")
    }

    // MARK: - A tool that waits for the user

    func testAGoalChangeWaitsForYesAndIsAppliedOnlyThen() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn("Sure.", tools: [steps12k])),
                                   .ok(wire.turn("Your goal is 12,000 now."))])
            await r.engine.send(text: "set my step goal to 12000")?.value

            XCTAssertEqual(r.engine.pendingTool?.request.confirmSummary,
                           "set your daily step goal to 12,000 steps", "\(wire)")
            XCTAssertFalse(r.engine.isSending, "\(wire): the turn rests while the card is up")
            XCTAssertEqual(r.profile.dailyStepGoal, 8000, "\(wire): nothing is applied before Yes")
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire)")
            XCTAssertNil(r.engine.undoToast, "\(wire)")

            await r.engine.confirmPendingTool()?.value

            XCTAssertNil(r.engine.pendingTool, "\(wire)")
            XCTAssertEqual(r.profile.dailyStepGoal, 12000, "\(wire)")
            XCTAssertEqual(try TestStore.fetchAll(UserProfile.self, in: r.container).first?.dailyStepGoal, 12000,
                           "\(wire): saved, not just set")
            XCTAssertEqual(r.engine.confettiTick, 1, "\(wire)")
            XCTAssertEqual(try r.transcript(), [
                "user: set my step goal to 12000", "assistant: Sure.",
                "decision(yes): set your daily step goal to 12,000 steps",
                "assistant: Your goal is 12,000 now.",
            ], "\(wire)")
            let results = wire.toolResults(r.transport.body(1))
            XCTAssertEqual(results.map(\.id), ["call_steps_1"], "\(wire)")
            XCTAssertEqual(results.first?.text, "Applied. Daily step goal is now 12,000 steps.", "\(wire)")
            XCTAssertFalse(r.transport.bodyText(1).contains("decision"), "\(wire): the marker is not sent")
        }
    }

    func testNotNowChangesNothingAndTellsTheModelSo() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn(nil, tools: [steps12k])),
                                   .ok(wire.turn("No problem at all."))])
            await r.engine.send(text: "set my step goal to 12000")?.value
            await r.engine.declinePendingTool()?.value

            XCTAssertEqual(r.profile.dailyStepGoal, 8000, "\(wire)")
            XCTAssertEqual(r.engine.confettiTick, 0, "\(wire)")
            XCTAssertEqual(try r.transcript(), [
                "user: set my step goal to 12000",
                "decision(no): set your daily step goal to 12,000 steps",
                "assistant: No problem at all.",
            ], "\(wire)")
            XCTAssertEqual(wire.toolResults(r.transport.body(1)).first?.text,
                           CoachTurnEngine.declinedToolResult, "\(wire)")
        }
    }

    func testANewMessageSupersedesAnUnansweredProposal() async throws {
        let wire = ChatWire.anthropic
        let r = try rig(wire, [.ok(wire.turn(nil, tools: [steps12k])), .ok(wire.turn("Sure, another time."))])
        await r.engine.send(text: "set my step goal to 12000")?.value
        XCTAssertNotNil(r.engine.pendingTool)

        await r.engine.send(text: "actually never mind")?.value
        XCTAssertNil(r.engine.pendingTool)
        XCTAssertEqual(r.profile.dailyStepGoal, 8000)
        XCTAssertNil(r.engine.confirmPendingTool(), "there is nothing left to confirm")
        XCTAssertTrue(wire.toolResults(r.transport.body(1)).isEmpty,
                      "the dropped proposal is not echoed into the next call")
        XCTAssertEqual(try r.transcript().filter { $0.hasPrefix("decision") }, [])
    }

    func testConfirmIsIgnoredWhileATurnIsInFlight() async throws {
        let wire = ChatWire.anthropic
        let gate = Gate()
        let r = try rig(wire, [.ok(wire.turn(nil, tools: [steps12k])),
                               .held(gate, .ok(wire.turn("Done.")))])
        await r.engine.send(text: "set my step goal to 12000")?.value
        let confirming = try XCTUnwrap(r.engine.confirmPendingTool())
        XCTAssertNil(r.engine.confirmPendingTool(), "a second Yes cannot apply the change twice")
        XCTAssertNil(r.engine.declinePendingTool())
        gate.open()
        await confirming.value
        XCTAssertEqual(try r.transcript().filter { $0.hasPrefix("decision") }.count, 1)
        XCTAssertEqual(r.engine.confettiTick, 1)
    }

    // MARK: - A tool the app rejects

    func testARejectedToolCallGoesBackAsAnErrorAndTheModelRecovers() async throws {
        let tooMany = ScriptedToolCall("call_bad_1", "set_step_goal", ["steps": 9_000_000])
        let unknown = ScriptedToolCall("call_bad_2", "launch_rocket", ["now": true])
        for wire in ChatWire.allCases {
            for bad in [tooMany, unknown] {
                let r = try rig(wire, [.ok(wire.turn(nil, tools: [bad])),
                                       .ok(wire.turn("I can't do that one, but I can set a smaller goal."))])
                await r.engine.send(text: "do it")?.value

                XCTAssertEqual(r.profile.dailyStepGoal, 8000, "\(wire) \(bad.name): nothing was applied")
                XCTAssertNil(r.engine.pendingTool, "\(wire) \(bad.name): no confirm card for an invalid request")
                XCTAssertNil(r.engine.failure, "\(wire) \(bad.name)")
                let results = wire.toolResults(r.transport.body(1))
                XCTAssertEqual(results.map(\.id), [bad.id], "\(wire) \(bad.name)")
                XCTAssertTrue(results.first?.text.contains("No change was made")
                              ?? false || results.first?.text.contains("nothing was changed") ?? false,
                              "\(wire) \(bad.name): the reason is what the model reads, got \(results)")
                if wire == .anthropic { XCTAssertEqual(results.first?.isError, true, "\(bad.name)") }
                XCTAssertEqual(try r.transcript().last,
                               "assistant: I can't do that one, but I can set a smaller goal.", "\(wire)")
            }
        }
    }

    // MARK: - Two tool calls in one turn

    func testTwoToolCallsInOneTurnAreHandledOneAtATime() async throws {
        let second = ScriptedToolCall("call_water_2", "log_water", ["oz": 8])
        for wire in ChatWire.allCases {
            // The model asks for two logs at once. The client exposes the first; the follow-up
            // tells the model only that one ran, and the model asks for the other again.
            let r = try rig(wire, [.ok(wire.turn(nil, tools: [water20, second])),
                                   .ok(wire.turn(nil, tools: [second])),
                                   .ok(wire.turn("Both are logged."))])
            await r.engine.send(text: "log 20 oz and then 8 oz")?.value

            XCTAssertEqual(try r.waterEntries().map(\.amountOz).sorted(), [8, 20], "\(wire)")
            XCTAssertEqual(r.transport.requestCount, 3, "\(wire)")
            // Every tool call echoed back has exactly one result (a missing result is a 400).
            for index in 1...2 {
                let body = r.transport.body(index)
                XCTAssertEqual(wire.echoedToolCallIDs(body).sorted(), wire.toolResults(body).map(\.id).sorted(),
                               "\(wire) request \(index)")
            }
            XCTAssertEqual(wire.echoedToolCallIDs(r.transport.body(1)), ["call_water_1"],
                           "\(wire): the unanswered second call is not echoed")
            XCTAssertEqual(wire.echoedToolCallIDs(r.transport.body(2)), ["call_water_1", "call_water_2"], "\(wire)")
            XCTAssertEqual(try r.transcript().last, "assistant: Both are logged.", "\(wire)")
        }
    }

    // MARK: - The depth cap

    func testTheChainStopsAtTheDepthCapEvenIfTheModelKeepsAskingForTools() async throws {
        for wire in ChatWire.allCases {
            let calls = (1...8).map { ScriptedToolCall("call_w\($0)", "log_water", ["oz": 8]) }
            let r = try rig(wire, calls.map { .ok(wire.turn(nil, tools: [$0])) })
            await r.engine.send(text: "log water forever")?.value

            XCTAssertEqual(r.transport.requestCount, CoachTurnEngine.maxToolDepth + 1,
                           "\(wire): the first call and one per allowed tool")
            XCTAssertEqual(try r.waterEntries().count, CoachTurnEngine.maxToolDepth,
                           "\(wire): a tool asked for after the cap is not applied")
            for index in 0..<CoachTurnEngine.maxToolDepth {
                XCTAssertFalse(wire.forbidsTools(r.transport.body(index)), "\(wire) request \(index)")
            }
            let last = r.transport.body(CoachTurnEngine.maxToolDepth)
            XCTAssertTrue(wire.forbidsTools(last), "\(wire): the last call forbids tools")
            XCTAssertFalse((last["tools"] as? [Any] ?? []).isEmpty,
                           "\(wire): the schemas stay, because the history holds tool blocks")
            XCTAssertFalse(r.engine.isSending, "\(wire)")
            XCTAssertNil(r.engine.failure, "\(wire)")
            XCTAssertEqual(try r.transcript().last, "assistant: I'm here 💚", "\(wire): the turn still ends in a reply")
            XCTAssertEqual(r.transport.remaining, 2, "\(wire): the rest of the script was never asked for")
        }
    }

    // MARK: - Cut off by the output cap

    func testAReplyCutOffMidToolCallAppliesNothingAndRetryReplacesThePartialText() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn("Let me log th", tools: [water20], stop: .cutOff)),
                                   .ok(wire.turn(nil, tools: [water20])),
                                   .ok(wire.turn("Logged 20 oz."))])
            await r.engine.send(text: "log 20 oz of water")?.value

            XCTAssertEqual(try r.waterEntries().count, 0, "\(wire): a half-written tool call is never applied")
            XCTAssertEqual(r.engine.failure?.error, .cutOff, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire)")
            XCTAssertEqual(try r.transcript(), ["user: log 20 oz of water", "assistant: Let me log th"],
                           "\(wire): what did arrive is shown")
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire): nothing was echoed back")

            await r.engine.retry()?.value

            XCTAssertNil(r.engine.failure, "\(wire)")
            XCTAssertEqual(try r.waterEntries().count, 1, "\(wire)")
            XCTAssertEqual(try r.transcript(), ["user: log 20 oz of water", "assistant: Logged 20 oz."],
                           "\(wire): the partial reply is gone and the user's message is there once")
            XCTAssertFalse(r.transport.bodyText(1).contains("Let me log th"),
                           "\(wire): the partial text is not sent back as if it were a finished turn")
        }
    }

    func testACutOffWithNoTextShowsTheFailureNotTheFallback() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn(nil, tools: [water20], stop: .cutOff))])
            await r.engine.send(text: "log water")?.value
            XCTAssertEqual(try r.transcript(), ["user: log water"], "\(wire): no \"I'm here\" for a cut-off turn")
            XCTAssertEqual(r.engine.failure?.error, .cutOff, "\(wire)")
        }
    }

    // MARK: - Refusals and a conversation that no longer fits

    func testARefusalWithTextIsTheReplyAndOneWithoutIsAFailureThatCannotBeRetried() async throws {
        // OpenAI puts the refusal in its own field / content part: it is what the model said.
        for wire in [ChatWire.openAIChat, .openAIResponses] {
            let r = try rig(wire, [.ok(wire.turn(nil, stop: .refusal, refusal: "I can't help with that."))])
            await r.engine.send(text: "something")?.value
            XCTAssertEqual(try r.transcript(), ["user: something", "assistant: I can't help with that."], "\(wire)")
            XCTAssertNil(r.engine.failure, "\(wire)")
        }
        // Anthropic's `refusal` stop reason and OpenAI's `content_filter` carry no text.
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn(nil, stop: .refusal))])
            await r.engine.send(text: "something")?.value
            XCTAssertEqual(try r.transcript(), ["user: something"], "\(wire)")
            XCTAssertEqual(r.engine.failure?.error, .refusal, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .rephrase, "\(wire)")
            XCTAssertNil(r.engine.retry(), "\(wire): sending the same thing again would be refused again")
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire)")
        }
    }

    func testAConversationTooLargeForTheModelIsNamedAsThat() async throws {
        let cases: [(ChatWire, TurnTransport.Step)] = [
            (.anthropic, .reply(400, ChatWire.anthropic.errorBody(
                type: "invalid_request_error", message: "prompt is too long: 250000 tokens > 200000 maximum"))),
            (.anthropic, .ok(ChatWire.anthropic.turn(nil, stop: .contextOverflow))),
            (.anthropic, .reply(413, ChatWire.anthropic.errorBody(type: "request_too_large", message: "too large"))),
            (.openAIChat, .reply(400, ChatWire.openAIChat.errorBody(
                type: "invalid_request_error", message: "This model's maximum context length is 128000 tokens.",
                code: "context_length_exceeded"))),
            (.openAIResponses, .reply(400, ChatWire.openAIResponses.errorBody(
                type: "invalid_request_error", message: "Input exceeds the context window.",
                code: "context_length_exceeded"))),
        ]
        for (wire, step) in cases {
            let r = try rig(wire, [step])
            await r.engine.send(text: "a very long message")?.value
            XCTAssertEqual(r.engine.failure?.error, .tooLong, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .rephrase, "\(wire)")
            XCTAssertEqual(try r.transcript(), ["user: a very long message"], "\(wire): the message is kept")
        }
    }

    // MARK: - HTTP failures

    func testARejectedKeyPointsAtAISettingsAndRetryDoesNotDuplicateTheMessage() async throws {
        for wire in ChatWire.allCases {
            let rejected = wire == .anthropic
                ? wire.errorBody(type: "authentication_error", message: "invalid x-api-key")
                : wire.errorBody(type: "invalid_request_error", message: "Incorrect API key provided.",
                                 code: "invalid_api_key")
            let r = try rig(wire, [.reply(401, rejected), .ok(wire.turn("Hi Alex!"))])
            await r.engine.send(text: "hello")?.value

            XCTAssertEqual(r.engine.failure?.error, .auth, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire): the owner's key, fixed on the gateway")
            XCTAssertTrue(r.engine.failure?.message.contains(wire.provider.label) ?? false, "\(wire)")
            XCTAssertFalse(r.engine.isSending, "\(wire)")
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire): a 401 is not retried by the client")
            XCTAssertEqual(try r.transcript(), ["user: hello"], "\(wire): the message survives the failure")

            await r.engine.retry()?.value   // the user fixed the key and tapped Retry

            XCTAssertNil(r.engine.failure, "\(wire)")
            XCTAssertEqual(try r.transcript(), ["user: hello", "assistant: Hi Alex!"],
                           "\(wire): one copy of the message, then the reply")
            XCTAssertEqual(wire.items(r.transport.body(1)).filter { $0["role"] as? String == "user" }.count, 1,
                           "\(wire): the retried request holds the message once")
        }
    }

    func testARateLimitIsRetriedOnceThenReportedWithTheProvidersWait() async throws {
        for wire in ChatWire.allCases {
            let limited = wire.errorBody(type: wire == .anthropic ? "rate_limit_error" : "rate_limit_exceeded",
                                         message: "Rate limit reached.")
            let r = try rig(wire, [.reply(429, limited, headers: ["retry-after": "0"]),
                                   .reply(429, limited, headers: ["retry-after": "20"])])
            let before = r.clock.current
            await r.engine.send(text: "hello")?.value

            XCTAssertEqual(r.transport.requestCount, 2, "\(wire): one automatic retry after a short wait")
            XCTAssertEqual(r.engine.failure?.error, .rateLimited(retryAfter: 20), "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .retryAfter(20), "\(wire)")
            let notBefore = try XCTUnwrap(r.engine.failure?.retryNotBefore, "\(wire)")
            XCTAssertEqual(notBefore.timeIntervalSince(r.clock.current), 20, accuracy: 0.001,
                           "\(wire): the wait is counted from the injected clock")
            XCTAssertGreaterThan(notBefore, before, "\(wire)")
            XCTAssertTrue(r.engine.failure?.message.contains("20 seconds") ?? false, "\(wire)")
            XCTAssertEqual(try r.transcript(), ["user: hello"], "\(wire)")
        }
    }

    func testALongRetryAfterIsNotSatOutByTheClient() async throws {
        for wire in ChatWire.allCases {
            let limited = wire.errorBody(type: "rate_limit_error", message: "Rate limit reached.")
            let r = try rig(wire, [.reply(429, limited, headers: ["retry-after": "45"]),
                                   .ok(wire.turn("never asked for"))])
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire): a second request inside the wait only extends it")
            XCTAssertEqual(r.engine.failure?.error, .rateLimited(retryAfter: 45), "\(wire)")
        }
    }

    func testAnAccountOutOfCreditIsNotRetriedAndIsNotCalledARateLimit() async throws {
        let cases: [(ChatWire, Int, [String: Any])] = [
            (.openAIChat, 429, ChatWire.openAIChat.errorBody(
                type: "insufficient_quota", message: "You exceeded your current quota.", code: "insufficient_quota")),
            (.openAIResponses, 429, ChatWire.openAIResponses.errorBody(
                type: "insufficient_quota", message: "Quota exhausted.", code: "credit_balance_exhausted")),
            (.anthropic, 400, ChatWire.anthropic.errorBody(
                type: "invalid_request_error",
                message: "Your credit balance is too low to access the Anthropic API.")),
            (.anthropic, 402, ChatWire.anthropic.errorBody(type: "billing_error", message: "Billing issue.")),
        ]
        for (wire, status, body) in cases {
            let r = try rig(wire, [.reply(status, body), .ok(wire.turn("never asked for"))])
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire) \(status): waiting cannot fix an empty account")
            XCTAssertEqual(r.engine.failure?.error, .billing, "\(wire) \(status)")
            XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire) \(status)")
        }
    }

    func testOverloadAndServerErrors() async throws {
        // 529 is Anthropic's overload; the client retries it once. 503 is retried by both.
        let anthropic = ChatWire.anthropic
        var r = try rig(anthropic, [
            .reply(529, anthropic.errorBody(type: "overloaded_error", message: "Overloaded"), headers: ["retry-after": "0"]),
            .reply(529, anthropic.errorBody(type: "overloaded_error", message: "Overloaded")),
        ])
        await r.engine.send(text: "hello")?.value
        XCTAssertEqual(r.transport.requestCount, 2)
        XCTAssertEqual(r.engine.failure?.error, .overloaded)
        XCTAssertEqual(r.engine.failure?.action, .retry)

        for wire in ChatWire.allCases {
            r = try rig(wire, [
                .reply(503, wire.errorBody(type: "server_error", message: "The server is overloaded."),
                       headers: ["retry-after-ms": "10"]),
                .ok(wire.turn("Here now.")),
            ])
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(r.transport.requestCount, 2, "\(wire)")
            XCTAssertNil(r.engine.failure, "\(wire): the one automatic retry recovered it")
            XCTAssertEqual(try r.transcript().last, "assistant: Here now.", "\(wire)")

            // A 500 is not retried by the client; the user is offered Retry.
            r = try rig(wire, [.reply(500, wire.errorBody(type: "api_error", message: "Internal error")),
                               .ok(wire.turn("Back."))])
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire)")
            XCTAssertEqual(r.engine.failure?.error, .server, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire)")
            await r.engine.retry()?.value
            XCTAssertEqual(try r.transcript(), ["user: hello", "assistant: Back."], "\(wire)")
        }
    }

    func testAnErrorBodyThatIsNotJSONStillClassifiesByStatus() async throws {
        let r = try rig(.anthropic, [.reply(502, [:])])
        await r.engine.send(text: "hello")?.value
        XCTAssertEqual(r.engine.failure?.error, .server)
    }

    func testAnUnknownModelIsTheOwnersToFixAndCanBeRetried() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.reply(404, wire.errorBody(type: "not_found_error", message: "model: nope"))])
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(r.engine.failure?.error, .modelUnavailable, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire)")
        }
    }

    // MARK: - Transport failures

    func testOfflineTimeoutAndADroppedConnection() async throws {
        let cases: [(URLError.Code, CoachTurnError)] = [
            (.notConnectedToInternet, .offline), (.dataNotAllowed, .offline),
            (.timedOut, .timeout), (.networkConnectionLost, .connectionLost),
            (.cannotFindHost, .connectionLost), (.badServerResponse, .unknown),
        ]
        for wire in ChatWire.allCases {
            for (code, expected) in cases {
                let r = try rig(wire, [.fail(code), .ok(wire.turn("Back online."))])
                await r.engine.send(text: "hello")?.value
                XCTAssertEqual(r.engine.failure?.error, expected, "\(wire) \(code.rawValue)")
                XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire) \(code.rawValue)")
                XCTAssertEqual(r.transport.requestCount, 1, "\(wire): a transport failure is not retried silently")
                XCTAssertEqual(try r.transcript(), ["user: hello"], "\(wire) \(code.rawValue)")
                XCTAssertFalse(r.engine.isSending, "\(wire)")

                await r.engine.retry()?.value
                XCTAssertEqual(try r.transcript(), ["user: hello", "assistant: Back online."], "\(wire) \(code.rawValue)")
            }
        }
    }

    func testNoAIOnThisPhoneMakesNoRequestAndSaysSo() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [], key: "")
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(r.engine.failure?.error, .missingKey, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .unavailable, "\(wire)")
            XCTAssertEqual(r.engine.failure?.message,
                           "I can't chat on this phone, sorry. Everything you log still works 💚", "\(wire)")
            XCTAssertEqual(r.transport.requestCount, 0, "\(wire)")
            XCTAssertEqual(try r.transcript(), ["user: hello"], "\(wire)")
        }
    }

    func testAnUnreadableSuccessBodyIsAFailureWithRetry() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(["unexpected": true])])
            await r.engine.send(text: "hello")?.value
            XCTAssertEqual(r.engine.failure?.error, .malformed, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire)")
        }
    }

    // MARK: - Retry after a tool was already applied

    func testRetryAfterAFailedFollowUpDoesNotApplyTheToolAgain() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn(nil, tools: [water20])),
                                   .reply(500, wire.errorBody(type: "api_error", message: "Internal error")),
                                   .ok(wire.turn("Logged 20 oz."))])
            await r.engine.send(text: "log 20 oz of water")?.value

            XCTAssertEqual(try r.waterEntries().count, 1, "\(wire): the log was written before the failure")
            XCTAssertEqual(r.engine.failure?.error, .server, "\(wire)")
            XCTAssertNotNil(r.engine.undoToast, "\(wire): the change can still be undone")

            await r.engine.retry()?.value

            XCTAssertEqual(try r.waterEntries().count, 1, "\(wire): Retry re-asks for the reply, not the tool")
            XCTAssertEqual(r.transport.requestCount, 3, "\(wire)")
            XCTAssertEqual(wire.toolResults(r.transport.body(2)).map(\.id), ["call_water_1"],
                           "\(wire): the retried call carries the same tool result")
            XCTAssertTrue(NSDictionary(dictionary: r.transport.body(1)).isEqual(to: r.transport.body(2)),
                          "\(wire): the retried call is the failed call, field for field")
            XCTAssertEqual(try r.transcript(), ["user: log 20 oz of water", "assistant: Logged 20 oz."], "\(wire)")
        }
    }

    func testANewMessageAfterAFailureClearsItAndSendsBothMessages() async throws {
        let wire = ChatWire.anthropic
        let r = try rig(wire, [.fail(.timedOut), .ok(wire.turn("Got both."))])
        await r.engine.send(text: "first")?.value
        XCTAssertNotNil(r.engine.failure)
        await r.engine.send(text: "second")?.value
        XCTAssertNil(r.engine.failure)
        XCTAssertEqual(try r.transcript(), ["user: first", "user: second", "assistant: Got both."])
        XCTAssertTrue(r.transport.bodyText(1).contains("first"))
        XCTAssertNil(r.engine.retry(), "with no failure there is nothing to retry")
    }

    // MARK: - Double send, stop, leaving the screen, the background

    func testASecondSendWhileATurnIsInFlightDoesNothing() async throws {
        for wire in ChatWire.allCases {
            let gate = Gate()
            let r = try rig(wire, [.held(gate, .ok(wire.turn("One reply."))), .ok(wire.turn("never asked for"))])
            let first = try XCTUnwrap(r.engine.send(text: "hello"), "\(wire)")
            XCTAssertNil(r.engine.send(text: "hello"), "\(wire): the second tap is ignored")
            XCTAssertNil(r.engine.send(text: "something else"), "\(wire)")
            XCTAssertNil(r.engine.retry(), "\(wire)")
            gate.open()
            await first.value

            XCTAssertEqual(try r.transcript(), ["user: hello", "assistant: One reply."], "\(wire)")
            XCTAssertEqual(r.transport.requestCount, 1, "\(wire): one turn, one request")
        }
    }

    func testStopEndsTheTurnKeepsTheMessageAndDropsALateReply() async throws {
        for wire in ChatWire.allCases {
            let gate = Gate()
            let r = try rig(wire, [.held(gate, .ok(wire.turn("Too late."))), .ok(wire.turn("Second try."))])
            let task = try XCTUnwrap(r.engine.send(text: "hello"), "\(wire)")
            await waitUntil("the request to be in flight") { r.transport.requestCount == 1 }

            r.engine.stop()
            gate.open()   // the provider answers after the user stopped
            await task.value

            XCTAssertFalse(r.engine.isSending, "\(wire)")
            XCTAssertEqual(r.engine.failure?.error, .cancelled, "\(wire)")
            XCTAssertEqual(try r.transcript(), ["user: hello"], "\(wire): the late reply is not shown")

            await r.engine.retry()?.value
            XCTAssertEqual(try r.transcript(), ["user: hello", "assistant: Second try."], "\(wire)")
        }
    }

    func testAStopInTheInstantAfterSendIsIgnored() async throws {
        // The send button turns into the stop button where it stands, so the second tap of a
        // double tap lands on Stop. It must not cancel the turn the first tap started.
        let wire = ChatWire.anthropic
        let gate = Gate()
        let r = try rig(wire, [.held(gate, .ok(wire.turn("Still here.")))])
        var frozen = Date(timeIntervalSince1970: 1_900_000_000)
        r.engine.env.now = { frozen }
        let task = try XCTUnwrap(r.engine.send(text: "hello"))

        r.engine.stop()   // 0 s after the send
        frozen = frozen.addingTimeInterval(0.59)
        r.engine.stop()
        gate.open()
        await task.value
        XCTAssertNil(r.engine.failure, "the turn was not cancelled")
        XCTAssertEqual(try r.messages().map(\.content).sorted(), ["Still here.", "hello"])

        // After the guard interval Stop works.
        let second = Gate()
        let r2 = try rig(wire, [.held(second, .ok(wire.turn("Too late.")))])
        var clock = Date(timeIntervalSince1970: 1_900_000_000)
        r2.engine.env.now = { clock }
        let task2 = try XCTUnwrap(r2.engine.send(text: "hello"))
        clock = clock.addingTimeInterval(0.6)
        r2.engine.stop()
        second.open()
        await task2.value
        XCTAssertEqual(r2.engine.failure?.error, .cancelled)
    }

    func testAReplyThatArrivesAfterTheScreenIsGoneIsStillSaved() async throws {
        for wire in ChatWire.allCases {
            let gate = Gate()
            var r: Rig? = try rig(wire, [.held(gate, .ok(wire.turn("Saved anyway.")))])
            let container = try XCTUnwrap(r?.container)
            let transport = try XCTUnwrap(r?.transport)
            let task = try XCTUnwrap(r?.engine.send(text: "hello"), "\(wire)")
            weak var engine = r?.engine
            r = nil   // the view, and every reference it held to the engine, is gone
            await waitUntil("the request to be in flight") { transport.requestCount == 1 }
            XCTAssertNotNil(engine, "\(wire): the running turn keeps the engine alive")

            gate.open()
            await task.value

            let rows = try TestStore.fetchAll(ChatMessage.self, in: container, sortBy: [SortDescriptor(\.createdAt)])
            XCTAssertEqual(rows.map(\.content), ["hello", "Saved anyway."], "\(wire)")
        }
    }

    func testEveryTurnHoldsABackgroundTaskUntilItSettles() async throws {
        let wire = ChatWire.anthropic
        let gate = Gate()
        var r = try rig(wire, [.held(gate, .ok(wire.turn(nil, tools: [water20]))), .ok(wire.turn("Done."))])
        let task = try XCTUnwrap(r.engine.send(text: "log water"))
        XCTAssertEqual(r.background.begun.count, 1, "begun before the request leaves")
        XCTAssertEqual(r.background.ended.count, 0)
        gate.open()
        await task.value
        XCTAssertTrue(r.background.isBalanced, "one task covers the whole chain, and it is ended")
        XCTAssertEqual(r.background.begun.count, 1)

        r = try rig(wire, [.fail(.networkConnectionLost)])
        await r.engine.send(text: "hello")?.value
        XCTAssertTrue(r.background.isBalanced, "ended after a failure too")
    }

    // MARK: - A message with no reply after a relaunch

    func testAnUnansweredMessageFromAnEarlierRunOffersRetryWithoutDuplicatingIt() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn("Sorry for the wait."))])
            try seed(r, [("user", "are you there?")])

            r.engine.noteUnansweredMessageIfAny()
            XCTAssertEqual(r.engine.failure?.error, .interrupted, "\(wire)")
            XCTAssertEqual(r.engine.failure?.action, .retry, "\(wire)")
            r.engine.noteUnansweredMessageIfAny()   // appearing again changes nothing
            XCTAssertEqual(r.engine.failure?.error, .interrupted, "\(wire)")

            await r.engine.retry()?.value
            XCTAssertEqual(try r.transcript(), ["user: are you there?", "assistant: Sorry for the wait."], "\(wire)")
        }
    }

    func testAnAnsweredConversationIsNotFlagged() throws {
        let r = try rig(.anthropic, [])
        r.engine.noteUnansweredMessageIfAny()
        XCTAssertNil(r.engine.failure, "an empty conversation")
        try seed(r, [("user", "hi"), ("assistant", "hello")])
        r.engine.noteUnansweredMessageIfAny()
        XCTAssertNil(r.engine.failure)
        // A decision marker after the user's message does not count as an answer.
        try seed(r, [("user", "set it")])
        r.context.insert(ChatMessage(role: "assistant", content: "", createdAt: r.clock.now(),
                                     decisionSummary: "set a goal", decisionAccepted: true))
        try r.context.save()
        r.engine.noteUnansweredMessageIfAny()
        XCTAssertEqual(r.engine.failure?.error, .interrupted)
    }

    // MARK: - Welcome seed and delete

    func testTheWelcomeIsSeededOnceIntoAnEmptyConversationAndNeverSent() async throws {
        let wire = ChatWire.anthropic
        let r = try rig(wire, [.ok(wire.turn("Hello!"))])
        r.engine.seedWelcomeIfNeeded()
        r.engine.seedWelcomeIfNeeded()
        let rows = try r.messages()
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isSystemSeed)
        XCTAssertTrue(rows[0].content.hasPrefix("Hi Alex! I'm Vita, your "), rows[0].content)
        r.engine.noteUnansweredMessageIfAny()
        XCTAssertNil(r.engine.failure, "the welcome is the coach's, so nothing is unanswered")

        await r.engine.send(text: "hi")?.value
        XCTAssertFalse(r.transport.bodyText(0).contains("Hi Alex! I'm Vita"))
        XCTAssertEqual(try r.messages().count, 3)
    }

    func testDeleteRemovesTheRowAndClearsAFailureThatWasAboutIt() async throws {
        let r = try rig(.anthropic, [.fail(.timedOut)])
        try seed(r, [("user", "old question"), ("assistant", "old answer")])
        await r.engine.send(text: "new question")?.value
        XCTAssertNotNil(r.engine.failure)
        var changes: [CoachTurnEngine.TranscriptChange] = []
        r.engine.onTranscriptChange = { changes.append($0) }

        let failed = try XCTUnwrap(try r.messages().last)
        let failedID = failed.id
        r.engine.delete(messageID: failedID)
        XCTAssertEqual(try r.transcript(), ["user: old question", "assistant: old answer"])
        XCTAssertNil(r.engine.failure, "the unanswered message is gone, so there is nothing to retry")
        XCTAssertEqual(changes, [.removed([failedID])])

        r.engine.delete(messageID: UUID())   // an id that is not there
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(try r.messages().count, 2)
    }

    func testTheTranscriptIsToldAboutEveryRowTheEngineAdds() async throws {
        let wire = ChatWire.anthropic
        let r = try rig(wire, [.ok(wire.turn("Sure.", tools: [steps12k])), .ok(wire.turn("Done."))])
        var changes = 0
        r.engine.onTranscriptChange = { _ in changes += 1 }
        await r.engine.send(text: "set my step goal to 12000")?.value
        XCTAssertEqual(changes, 2, "the user's message and the prose")
        await r.engine.confirmPendingTool()?.value
        XCTAssertEqual(changes, 4, "the decision marker and the reply")
        XCTAssertEqual(try r.messages().count, 4)
    }

    // MARK: - Memory consolidation

    /// `count` stored messages `m001…`, alternating from the user, as an existing conversation.
    private func seedConversation(_ r: Rig, count: Int) throws -> [ChatMessage] {
        try seed(r, (1...count).map { (role: $0 % 2 == 1 ? "user" : "assistant", content: String(format: "m%03d", $0)) })
    }

    private let foldJSON = #"{"notes": "Likes mornings.", "summary": "Talked about breakfast."}"#

    func testNoFoldWhileEverythingStillFitsTheWindow() async throws {
        let wire = ChatWire.anthropic
        let r = try rig(wire, [.ok(wire.turn("ok"))])
        _ = try seedConversation(r, count: 14)   // 14 + the new question + the reply = 16
        await r.engine.send(text: "question")?.value
        await r.engine.memoryTask?.value
        XCTAssertEqual(r.transport.requestCount, 1, "nothing has left the window, so there is nothing to fold")
        XCTAssertNil(r.engine.memoryTask)
    }

    func testMessagesThatLeftTheWindowAreFoldedAfterTheReply() async throws {
        for wire in ChatWire.allCases {
            let r = try rig(wire, [.ok(wire.turn("Here you go.")), .ok(wire.turn(foldJSON))])
            let old = try seedConversation(r, count: 30)
            await r.engine.send(text: "question")?.value
            XCTAssertFalse(r.engine.isSending, "\(wire): the fold never holds the user's turn open")
            await r.engine.memoryTask?.value

            // 32 real messages; the window is m017…m030 + question + reply; m001…m016 fold.
            XCTAssertEqual(r.transport.requestCount, 2, "\(wire)")
            let fold = r.transport.bodyText(1)
            XCTAssertTrue(fold.contains("m001"), "\(wire)")
            XCTAssertTrue(fold.contains("m016"), "\(wire)")
            XCTAssertFalse(fold.contains("m017"), "\(wire): a message still sent verbatim is not folded")
            XCTAssertTrue(fold.contains("Alex: m001"), "\(wire): the user's turns carry the user's name")

            let memory = try XCTUnwrap(try TestStore.fetchAll(CoachMemory.self, in: r.container).first, "\(wire)")
            XCTAssertEqual(memory.profileNotes, "Likes mornings.", "\(wire)")
            XCTAssertEqual(memory.conversationSummary, "Talked about breakfast.", "\(wire)")
            XCTAssertEqual(memory.summarizedThroughDate, old[15].createdAt, "\(wire): the mark is the newest folded message")
            XCTAssertEqual(memory.updatedAt, r.clock.current, "\(wire): stamped from the injected clock")
        }
    }

    func testALongBacklogIsFoldedInBatchesOldestFirst() async throws {
        let wire = ChatWire.anthropic
        let r = try rig(wire, [.ok(wire.turn("one")), .ok(wire.turn(foldJSON)),
                               .ok(wire.turn("two")), .ok(wire.turn(foldJSON))])
        let old = try seedConversation(r, count: 100)
        await r.engine.send(text: "question")?.value
        await r.engine.memoryTask?.value

        // 86 messages are outside the window; one fold takes the oldest 40 of them.
        let first = r.transport.bodyText(1)
        XCTAssertTrue(first.contains("m001") && first.contains("m040"))
        XCTAssertFalse(first.contains("m041"), "a backlog is never sent to the model in one piece")
        var memory = try XCTUnwrap(try TestStore.fetchAll(CoachMemory.self, in: r.container).first)
        XCTAssertEqual(memory.summarizedThroughDate, old[39].createdAt)

        // The next reply folds the next 40, starting after the mark.
        await r.engine.send(text: "another")?.value
        await r.engine.memoryTask?.value
        let second = r.transport.bodyText(3)
        XCTAssertFalse(second.contains("m040"), "nothing is folded twice")
        XCTAssertTrue(second.contains("m041") && second.contains("m080"))
        XCTAssertFalse(second.contains("m081"))
        memory = try XCTUnwrap(try TestStore.fetchAll(CoachMemory.self, in: r.container).first)
        XCTAssertEqual(memory.summarizedThroughDate, old[79].createdAt)
    }

    func testTheStoreFetchSelectsWhatThePureRuleSelects() throws {
        let r = try rig(.anthropic, [])
        r.context.insert(ChatMessage(role: "assistant", content: "seed", createdAt: r.clock.now(), isSystemSeed: true))
        let rows = try seedConversation(r, count: 45)
        r.context.insert(ChatMessage(role: "assistant", content: "", createdAt: r.clock.now(),
                                     decisionSummary: "d", decisionAccepted: true))
        try r.context.save()
        let everything = try r.context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)]))

        for mark in [nil, rows[4].createdAt, rows[28].createdAt, rows[44].createdAt] as [Date?] {
            let pure = CoachMemoryService.messagesToConsolidate(
                messages: everything.filter { !$0.isDecision },
                windowSize: CoachTurnEngine.maxHistoryMessages, summarizedThrough: mark)
            XCTAssertLessThanOrEqual(pure.count, CoachTurnEngine.memoryFoldBatch)
            XCTAssertEqual(r.engine.messagesToFold(summarizedThrough: mark).map(\.content), pure.map(\.content),
                           "mark \(String(describing: mark))")
        }
    }

    func testAFailedFoldLeavesMemoryAndTheMarkAlone() async throws {
        let wire = ChatWire.anthropic
        let r = try rig(wire, [.ok(wire.turn("ok")),
                               .reply(500, wire.errorBody(type: "api_error", message: "Internal error"))])
        _ = try seedConversation(r, count: 30)
        await r.engine.send(text: "question")?.value
        await r.engine.memoryTask?.value
        let memory = try XCTUnwrap(try TestStore.fetchAll(CoachMemory.self, in: r.container).first)
        XCTAssertEqual(memory.conversationSummary, "")
        XCTAssertNil(memory.summarizedThroughDate, "the same batch is offered again after the next reply")
        XCTAssertNil(r.engine.failure, "a background fold never shows an error")
    }

    func testNotesWrittenWhileAFoldWasRunningAreKept() async throws {
        let wire = ChatWire.anthropic
        let gate = Gate()
        let r = try rig(wire, [.ok(wire.turn("ok")), .held(gate, .ok(wire.turn(foldJSON)))])
        _ = try seedConversation(r, count: 30)
        await r.engine.send(text: "question")?.value
        await waitUntil("the fold to be in flight") { r.transport.requestCount == 2 }

        let memory = CoachMemory.fetchOrCreate(in: r.context, profile: r.profile)
        memory.profileNotes = "Allergic to peanuts."   // a tool or a Settings edit, mid-fold
        try r.context.save()
        gate.open()
        await r.engine.memoryTask?.value

        XCTAssertEqual(memory.profileNotes, "Allergic to peanuts.", "the newer notes win")
        XCTAssertEqual(memory.conversationSummary, "Talked about breakfast.", "the summary still folds")
        XCTAssertNotNil(memory.summarizedThroughDate)
    }

    func testNoFoldAfterAFailedTurnOrWhileAProposalWaits() async throws {
        let wire = ChatWire.anthropic
        var r = try rig(wire, [.fail(.timedOut)])
        _ = try seedConversation(r, count: 30)
        await r.engine.send(text: "question")?.value
        XCTAssertNil(r.engine.memoryTask)

        r = try rig(wire, [.ok(wire.turn(nil, tools: [steps12k]))])
        _ = try seedConversation(r, count: 30)
        await r.engine.send(text: "set my step goal to 12000")?.value
        XCTAssertNil(r.engine.memoryTask, "a turn that is waiting for the user has not ended")
    }

    // MARK: - An engine with no store

    func testAnEngineThatWasNeverAttachedDoesNothing() {
        let engine = CoachTurnEngine()
        XCTAssertFalse(engine.isAttached)
        XCTAssertNil(engine.send(text: "hello"))
        XCTAssertNil(engine.retry())
        XCTAssertNil(engine.confirmPendingTool())
        engine.seedWelcomeIfNeeded()
        engine.noteUnansweredMessageIfAny()
        engine.performUndo()
        engine.stop()
        XCTAssertFalse(engine.isSending)
        XCTAssertNil(engine.failure)
    }
}
