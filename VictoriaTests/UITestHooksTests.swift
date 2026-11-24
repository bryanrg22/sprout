import SwiftData
import XCTest
@testable import Victoria

/// The hooks the UI smoke flows launch the app with (`--ui-testing`,
/// `--ui-test-scripted-ai=<name>`): that they are inert unless a DEBUG build is asked
/// for them, the order in which the AI layer picks its runtime (task-local scope, then
/// the process-wide default, then `URLSession`), and that each built-in script answers
/// the real client the way the flows rely on.
final class UITestHooksTests: XCTestCase {

    override func tearDown() {
        AIRuntime.setProcessDefault(nil)
        super.tearDown()
    }

    private let key = "test-key-not-real"

    // MARK: - The plan: inert unless a DEBUG build is asked

    func testNoArgumentMeansInert() {
        XCTAssertEqual(UITestHooks.plan(arguments: ["Victoria"], isDebugBuild: true), .inert)
        XCTAssertEqual(UITestHooks.plan(arguments: ["Victoria", "--seed-demo", "--demo-gain"], isDebugBuild: true),
                       .inert, "the demo arguments alone must not switch the store")
        XCTAssertFalse(UITestHooks.Plan.inert.isActive)
        XCTAssertNil(UITestHooks.Plan.inert.scriptedAI)
    }

    func testAReleaseBuildIsInertWhateverItIsPassed() {
        let everything = ["Victoria", "--ui-testing", "--seed-demo", "--demo-gain",
                          "--ui-test-scripted-ai=coach-log-water"]
        XCTAssertEqual(UITestHooks.plan(arguments: everything, isDebugBuild: false), .inert)
        for script in UITestAIScript.allCases {
            let arguments = ["Victoria", "--ui-testing", "--ui-test-scripted-ai=\(script.rawValue)"]
            XCTAssertEqual(UITestHooks.plan(arguments: arguments, isDebugBuild: false), .inert)
        }
    }

    func testUITestingArgumentActivatesADebugBuild() {
        let plan = UITestHooks.plan(arguments: ["Victoria", "--ui-testing"], isDebugBuild: true)
        XCTAssertTrue(plan.isActive)
        XCTAssertNil(plan.scriptedAI)
    }

    func testScriptNameIsReadFromItsArgument() {
        let plan = UITestHooks.plan(
            arguments: ["Victoria", "--ui-testing", "--ui-test-scripted-ai=fail-500"], isDebugBuild: true)
        XCTAssertEqual(plan, UITestHooks.Plan(isActive: true, scriptedAI: "fail-500"))
    }

    // MARK: - Starting from empty app defaults

    func testFreshDefaultsIsAskedForByItsOwnArgumentAndOnlyWithUITesting() {
        XCTAssertFalse(UITestHooks.plan(arguments: ["Victoria", "--ui-testing"], isDebugBuild: true).freshDefaults)
        XCTAssertEqual(UITestHooks.plan(arguments: ["Victoria", "--ui-testing", "--ui-test-fresh-defaults"],
                                        isDebugBuild: true),
                       UITestHooks.Plan(isActive: true, scriptedAI: nil, freshDefaults: true))
        XCTAssertEqual(UITestHooks.plan(arguments: ["Victoria", "--ui-test-fresh-defaults"], isDebugBuild: true),
                       .inert, "without --ui-testing nothing may be cleared")
        XCTAssertEqual(UITestHooks.plan(arguments: ["Victoria", "--ui-testing", "--ui-test-fresh-defaults"],
                                        isDebugBuild: false), .inert, "a Release build never clears anything")
    }

    func testDefaultsAreClearedOnlyWhenThePlanAsks() throws {
        let suite = "ui-test-hooks-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func fill() {
            defaults.set("gym", forKey: "app_mode")
            defaults.set(Data([1, 2, 3]), forKey: "a.day.cache")
        }

        fill()
        XCTAssertFalse(UITestHooks.resetDefaultsIfAsked(for: .inert, defaults: defaults, domain: suite))
        XCTAssertFalse(UITestHooks.resetDefaultsIfAsked(for: .init(isActive: true), defaults: defaults, domain: suite),
                       "--ui-testing alone keeps the defaults: a relaunch inside a flow depends on that")
        XCTAssertFalse(UITestHooks.resetDefaultsIfAsked(for: .init(isActive: false, freshDefaults: true),
                                                        defaults: defaults, domain: suite))
        XCTAssertFalse(UITestHooks.resetDefaultsIfAsked(for: .init(isActive: true, freshDefaults: true),
                                                        defaults: defaults, domain: nil), "no domain, nothing to clear")
        XCTAssertEqual(defaults.string(forKey: "app_mode"), "gym")
        XCTAssertNotNil(defaults.data(forKey: "a.day.cache"))

        XCTAssertTrue(UITestHooks.resetDefaultsIfAsked(for: .init(isActive: true, freshDefaults: true),
                                                       defaults: defaults, domain: suite))
        XCTAssertNil(defaults.string(forKey: "app_mode"))
        XCTAssertNil(defaults.data(forKey: "a.day.cache"))
    }

    func testTheTestHostsOwnDefaultsAreNeverClearedByDefault() {
        // `current` is inert in the unit-test host, so the default call does nothing.
        XCTAssertFalse(UITestHooks.resetDefaultsIfAsked())
    }

    func testAScriptNameWithoutUITestingDoesNothing() {
        XCTAssertEqual(UITestHooks.plan(arguments: ["Victoria", "--ui-test-scripted-ai=coach-prose"],
                                        isDebugBuild: true), .inert)
    }

    /// The unit-test host is a normal launch: no hook is active in it and no process
    /// default is installed, so every other test in this bundle runs as before.
    func testTheTestHostItselfIsNotInUITestingMode() {
        XCTAssertFalse(CommandLine.arguments.contains(UITestHooks.uiTestingArgument))
        XCTAssertEqual(UITestHooks.current, .inert)
        XCTAssertFalse(UITestHooks.isActive)
        XCTAssertNil(AIRuntime.processDefault)
        XCTAssertNil(AIRuntime.effective)
    }

    func testAnInertPlanInstallsNothing() {
        XCTAssertNil(UITestHooks.aiRuntime(for: .inert))
        UITestHooks.installAIRuntime(for: .inert)
        XCTAssertNil(AIRuntime.processDefault)
        // What a Release build computes for any arguments is the inert plan.
        let release = UITestHooks.plan(arguments: ["Victoria", "--ui-testing", "--ui-test-scripted-ai=coach-prose"],
                                       isDebugBuild: false)
        UITestHooks.installAIRuntime(for: release)
        XCTAssertNil(AIRuntime.processDefault)
    }

    /// The setter of the process default and the scripted transport must not exist in a
    /// Release build. A unit test runs a DEBUG build, so this reads the source the bundle
    /// was compiled from (as `StoreVerificationTests` does) and checks the conditional
    /// compilation around them.
    func testProcessDefaultSetterAndScriptsAreCompiledForDebugOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runtime = try String(contentsOf: root.appendingPathComponent("Victoria/Services/AI/AIRuntime.swift"),
                                 encoding: .utf8)
        let lines = runtime.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let setter = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("static func setProcessDefault(") })
        let opening = try XCTUnwrap(lines[..<setter].lastIndex { $0.hasPrefix("#if") || $0 == "#else" || $0 == "#endif" })
        XCTAssertEqual(lines[opening], "#if DEBUG", "setProcessDefault must sit directly inside #if DEBUG")
        let closing = try XCTUnwrap(lines[setter...].firstIndex { $0.hasPrefix("#if") || $0 == "#else" || $0 == "#endif" })
        XCTAssertEqual(lines[closing], "#else")
        XCTAssertEqual(lines.filter { $0.contains("func setProcessDefault(") }.count, 1, "one setter, the DEBUG one")
        XCTAssertTrue(lines[closing...].prefix(3).contains("static var processDefault: AIRuntime? { nil }"),
                      "the Release value is the constant nil")

        let scripts = try String(contentsOf: root.appendingPathComponent("Victoria/Services/AI/UITestScriptedAI.swift"),
                                 encoding: .utf8)
        let scriptLines = scripts.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(scriptLines.first, "#if DEBUG")
        XCTAssertEqual(scriptLines.last, "#endif")
        XCTAssertEqual(scriptLines.filter { $0.hasPrefix("#if") }.count, 1, "the whole file is one DEBUG block")
    }

    // MARK: - Precedence: task-local scope, then the process default, then the shipped transport

    func testWithNothingSetTheTransportIsTheShippedOne() {
        XCTAssertNil(AIRuntime.effective)
        XCTAssertTrue(AIRuntime.transport is AIDefaultTransport, "the shipped transport: the gateway for a placeholder key, URLSession otherwise")
        XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "m-1")
    }

    func testProcessDefaultIsUsedWhenNothingIsScoped() async throws {
        let global = ScriptedTransport([.json(200, textReply("from the process default"))])
        AIRuntime.setProcessDefault(AIRuntime(provider: .anthropic, apiKey: key, model: "process-model",
                                              transport: global))
        XCTAssertNil(AIRuntime.current, "the task-local is untouched")
        XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "process-model")
        XCTAssertTrue(AIConfig.hasActiveKey, "a process default with a key counts as a key being present")
        XCTAssertEqual(AIConfig.provider, .anthropic)

        let text = try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                                  model: "m-1", maxTokens: 10)
        XCTAssertEqual(text, "from the process default")
        XCTAssertEqual(global.requests.count, 1)
        XCTAssertEqual(global.requests.first?.value(forHTTPHeaderField: "x-api-key"), key)
        XCTAssertEqual(global.body()["model"] as? String, "process-model")
    }

    func testProcessDefaultReachesADetachedTask() async throws {
        let global = ScriptedTransport([.json(200, textReply("detached"))])
        AIRuntime.setProcessDefault(AIRuntime(provider: .anthropic, apiKey: key, transport: global))
        // A task-local would not be inherited here; the process default is.
        let text = try await Task.detached {
            try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                           model: "m-1", maxTokens: 10)
        }.value
        XCTAssertEqual(text, "detached")
        XCTAssertEqual(global.requests.count, 1)
    }

    func testTaskLocalScopeWinsOverTheProcessDefault() async throws {
        let global = ScriptedTransport([.json(200, textReply("from the process default"))])
        let scoped = ScriptedTransport([.json(200, openAIChatReply("from the scope"))])
        AIRuntime.setProcessDefault(AIRuntime(provider: .anthropic, apiKey: key, model: "process-model",
                                              transport: global))
        let text = try await AIRuntime.$current.withValue(
            AIRuntime(provider: .openai, apiKey: "scoped-key-not-real", model: "gpt-4.1-mini", transport: scoped)
        ) {
            XCTAssertEqual(AIConfig.provider, .openai)
            XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "gpt-4.1-mini")
            return try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                                  model: "m-1", maxTokens: 10)
        }
        XCTAssertEqual(text, "from the scope")
        XCTAssertEqual(scoped.requests.count, 1)
        XCTAssertEqual(global.requests.count, 0, "the process default must not see a scoped call")
        // Outside the scope the process default is back in force.
        XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "process-model")
    }

    /// The scope replaces the process default as a whole: a field the scope leaves nil is
    /// not filled in from the default (a test that scopes only a model must not pick up a
    /// transport it never asked for).
    func testAScopeDoesNotInheritFieldsFromTheProcessDefault() {
        AIRuntime.setProcessDefault(AIRuntime(provider: .openai, apiKey: key, model: "process-model",
                                              transport: ScriptedTransport([])))
        AIRuntime.$current.withValue(AIRuntime(provider: .anthropic)) {
            XCTAssertEqual(AIConfig.provider, .anthropic)
            XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "m-1")
            XCTAssertTrue(AIRuntime.transport is AIDefaultTransport, "the shipped transport: the gateway for a placeholder key, URLSession otherwise")
        }
    }

    func testClearingTheProcessDefaultRestoresShippedBehaviour() {
        AIRuntime.setProcessDefault(AIRuntime(provider: .anthropic, apiKey: key, model: "process-model"))
        XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "process-model")
        AIRuntime.setProcessDefault(nil)
        XCTAssertNil(AIRuntime.effective)
        XCTAssertEqual(AIRuntime.resolve(model: "m-1"), "m-1")
        XCTAssertTrue(AIRuntime.transport is AIDefaultTransport, "the shipped transport: the gateway for a placeholder key, URLSession otherwise")
    }

    // MARK: - What an active plan installs

    func testUITestingWithoutAScriptLeavesNoKeyAndNoNetwork() async {
        let plan = UITestHooks.Plan(isActive: true, scriptedAI: nil)
        UITestHooks.installAIRuntime(for: plan)
        XCTAssertFalse(AIConfig.hasActiveKey, "no script means the no-key path, whatever the Keychain holds")
        XCTAssertThrowsError(try AIClient.makeFull()) { error in
            guard case AIConfig.AIError.missingKey = error else { return XCTFail("expected missingKey, got \(error)") }
        }
        XCTAssertFalse(AIRuntime.transport is URLSessionTransport)
        do {
            _ = try await AIRuntime.transport.data(for: URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!))
            XCTFail("the offline transport must refuse")
        } catch {}
    }

    func testEveryScriptInstallsAsAKeyedAnthropicRuntime() throws {
        for script in UITestAIScript.allCases {
            let plan = UITestHooks.plan(arguments: ["Victoria", "--ui-testing", "--ui-test-scripted-ai=\(script.rawValue)"],
                                        isDebugBuild: true)
            UITestHooks.installAIRuntime(for: plan)
            XCTAssertTrue(AIConfig.hasActiveKey, script.rawValue)
            XCTAssertEqual(AIConfig.provider, .anthropic, script.rawValue)
            XCTAssertTrue(try AIClient.makeFull() is AnthropicClient, script.rawValue)
            XCTAssertEqual((AIRuntime.transport as? UITestScriptedTransport)?.script, script)
            AIRuntime.setProcessDefault(nil)
        }
    }

    func testScriptNames() {
        XCTAssertEqual(Set(UITestAIScript.allCases.map(\.rawValue)),
                       ["coach-log-water", "coach-prose", "coach-slow", "fail-500"])
        XCTAssertNil(UITestAIScript(rawValue: "coach-log-watr"), "an unknown name resolves to nothing")
    }

    // MARK: - The scripts, through the real client

    private func scriptedRuntime(_ script: UITestAIScript) -> AIRuntime {
        AIRuntime(provider: .anthropic, apiKey: UITestAIScript.placeholderKey,
                  transport: UITestScriptedTransport(script: script))
    }

    private func coachTurn(_ messages: [AnthropicClient.Msg], profile: UserProfile) async throws -> AnthropicClient.ChatTurn {
        try await AIClient.makeFull().chatWithTools(
            system: "volatile", messages: messages, tools: CoachTools.schemas(for: profile),
            model: AIConfig.model(for: .coachTurn), maxTokens: 1500,
            cachedSystemPrefix: "stable", forbidToolUse: false)
    }

    /// The script is only useful while it matches the app's real tool contract: the
    /// call it scripts must parse, and must be one the coach applies without a confirm.
    func testCoachLogWaterScriptsAToolCallThenProse() async throws {
        let profile = UserProfile()
        try await AIRuntime.$current.withValue(scriptedRuntime(.coachLogWater)) {
            let user = AnthropicClient.Msg(role: "user", content: "I drank two bottles")
            let first = try await coachTurn([user], profile: profile)
            let tool = try XCTUnwrap(first.toolUse)
            XCTAssertEqual(tool.name, "log_water")
            XCTAssertEqual(tool.input["containers"] as? Int, UITestAIScript.waterContainers)
            guard case .ok(let request) = CoachTools.parse(name: tool.name, input: tool.input,
                                                           profile: profile, todaysFoods: []) else {
                return XCTFail("the scripted log_water call must be valid for the real parser")
            }
            XCTAssertFalse(request.requiresConfirm, "log_water is applied at once with an Undo")

            let followUp = try await coachTurn(
                [user,
                 AnthropicClient.assistantMessage(content: first.assistantContent),
                 AnthropicClient.toolResultMessage(toolUseId: tool.id, resultText: "Applied.")],
                profile: profile)
            XCTAssertNil(followUp.toolUse, "the follow-up must end the turn, not chain another tool")
            XCTAssertEqual(followUp.text, UITestAIScript.afterToolReply)

            // A new message starts over with the tool call (the flows send twice).
            let again = try await coachTurn([user, AnthropicClient.Msg(role: "assistant", content: followUp.text),
                                             AnthropicClient.Msg(role: "user", content: "and two more")],
                                            profile: profile)
            XCTAssertEqual(again.toolUse?.name, "log_water")
        }
    }

    func testCoachProseAndCoachSlowReplyInProse() async throws {
        let profile = UserProfile()
        try await AIRuntime.$current.withValue(scriptedRuntime(.coachProse)) {
            let turn = try await coachTurn([AnthropicClient.Msg(role: "user", content: "hi")], profile: profile)
            XCTAssertNil(turn.toolUse)
            XCTAssertEqual(turn.text, UITestAIScript.proseReply)
        }
        // The slow script is the same reply after a delay; the delay itself is not waited for here.
        let body: [String: Any] = ["model": "m", "tools": CoachTools.schemas(for: profile),
                                   "messages": [["role": "user", "content": "hi"]]]
        let slow = UITestAIScript.coachSlow.reply(to: body)
        var prose = UITestAIScript.coachProse.reply(to: body)
        XCTAssertEqual(slow.status, 200)
        XCTAssertEqual(slow.delaySeconds, UITestAIScript.slowReplySeconds)
        XCTAssertGreaterThan(slow.delaySeconds, 0)
        prose.delaySeconds = slow.delaySeconds
        XCTAssertEqual(slow, prose)
    }

    /// Only the coach's turn is scripted. Any other call is refused at once, so the
    /// screens that phrase things with a model show their template fallback.
    func testCallsThatAreNotACoachTurnAreRefused() async {
        for script in [UITestAIScript.coachLogWater, .coachProse, .coachSlow] {
            await AIRuntime.$current.withValue(scriptedRuntime(script)) {
                do {
                    _ = try await AIClient.make().chat(system: "s", messages: [ChatTurnMsg(role: "user", text: "hi")],
                                                       model: "m-1", maxTokens: 10)
                    XCTFail("\(script.rawValue): a plain call must not be answered")
                } catch AIConfig.AIError.badResponse {
                } catch { XCTFail("\(script.rawValue): expected badResponse, got \(error)") }
                do {
                    _ = try await AIClient.makeFull().structured(
                        system: "s", userContent: "u", toolName: "log_water", toolDescription: "d",
                        schema: ["type": "object"], model: "m-1", maxTokens: 10)
                    XCTFail("\(script.rawValue): a forced-tool call must not be answered")
                } catch AIConfig.AIError.badResponse {
                } catch { XCTFail("\(script.rawValue): expected badResponse, got \(error)") }
            }
        }
        let refused = UITestAIScript.coachProse.reply(to: ["messages": [["role": "user", "content": "hi"]]])
        XCTAssertEqual(refused.status, 400, "400 is not retried, so a refused call costs no backoff")
        XCTAssertEqual(refused.delaySeconds, 0)
    }

    func testFail500FailsEveryCallWithoutARetry() async {
        let profile = UserProfile()
        await AIRuntime.$current.withValue(scriptedRuntime(.fail500)) {
            for _ in 0..<2 {
                do {
                    _ = try await coachTurn([AnthropicClient.Msg(role: "user", content: "hi")], profile: profile)
                    XCTFail("fail-500 must throw")
                } catch AIConfig.AIError.badResponse {
                } catch { XCTFail("expected badResponse, got \(error)") }
            }
        }
        let reply = UITestAIScript.fail500.reply(to: [:])
        XCTAssertEqual(reply.status, 500)
        XCTAssertFalse([429, 503, 529].contains(reply.status), "500 is outside the client's retry list")
    }

    // MARK: - What the flows rely on outside the hooks

    func testModeIdentifiersMatchTheSwitch() {
        XCTAssertEqual(AccessibilityID.Mode.home, "mode.\(AppMode.home.rawValue)")
        XCTAssertEqual(AccessibilityID.Mode.gym, "mode.\(AppMode.gym.rawValue)")
        XCTAssertEqual(AccessibilityID.WorkoutLog.kind(WorkoutKind.run.rawValue), "workoutLog.kind.run")
    }

    /// The flows pass `--demo-tab today` so a launch opens on Home / Today whatever
    /// mode an earlier launch stored, and `--demo-tab workouts` to open on Gym.
    func testTheDemoTabArgumentsTheFlowsPass() {
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria", "--demo-tab", "today"], stored: "gym"), .home)
        XCTAssertEqual(HomeTab.initial(arguments: ["Victoria", "--demo-tab", "today"]), .today)
        XCTAssertEqual(AppMode.initial(arguments: ["Victoria", "--demo-tab", "workouts"], stored: "home"), .gym)
    }

    func testTheUITestStoreIsTheProductionSchemaInMemory() throws {
        let container = try UITestHooks.makeContainer()
        XCTAssertEqual(container.configurations.count, 1)
        let configuration = try XCTUnwrap(container.configurations.first)
        XCTAssertTrue(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.cloudKitContainerIdentifier, "CloudKit is off")
        XCTAssertEqual(container.schema.entities.count, AppSchema.models.count)
        // A second container shares nothing with the first: every launch starts empty.
        let context = ModelContext(container)
        context.insert(UserProfile())
        try context.save()
        let other = try UITestHooks.makeContainer()
        XCTAssertEqual(try ModelContext(other).fetchCount(FetchDescriptor<UserProfile>()), 0)
    }

    // MARK: - Recorded replies

    private func textReply(_ text: String) -> [String: Any] {
        ["model": "claude-haiku-4-5-20251001", "content": [["type": "text", "text": text]],
         "stop_reason": "end_turn", "usage": ["input_tokens": 1, "output_tokens": 1]]
    }

    private func openAIChatReply(_ text: String) -> [String: Any] {
        ["model": "gpt-4.1-mini",
         "choices": [["message": ["role": "assistant", "content": text], "finish_reason": "stop"]],
         "usage": ["prompt_tokens": 1, "completion_tokens": 1]]
    }
}
