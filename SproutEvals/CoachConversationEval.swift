import Foundation
import SwiftData
import XCTest
@testable import Sprout

/// coachTurn, mid-conversation: Vita has already exchanged a few turns with the user, and the
/// record is her NEXT reply (`Evals/datasets/coach_conversations/v1.jsonl`, 30 cases).
///
/// Unlike `CoachToolChoice`, which issues one `chatWithTools` call for a first message, this
/// drives the app's own `CoachTurnEngine` end to end, so the prompt, the tools and the history
/// handling are the app's and nothing is copied:
/// - an in-memory store on the full schema (`TestStore.makeContainer`) holds the fixture user's
///   profile, food, weigh-ins and water, the coach's notes when the case gives some, and the
///   earlier turns as `ChatMessage` rows;
/// - `engine.send(text:)` with the newest message then does what the chat's send button does:
///   saves it, builds the history (`recentHistory` → `historyWindow` → `apiMessages`), builds
///   `CoachContext.systemParts` from the store (`CoachDataSnapshot.fetch`, memory, plan), sends
///   `CoachTools.schemas`, validates any tool call with `CoachTools.parse`, applies a quick log at
///   once (with the follow-up call that lets the model answer in prose), and leaves a change that
///   needs the user's Yes as `pendingTool`, unapplied, exactly as the app does.
///
/// Where it differs from the app: the store is in memory and holds only the fixture's rows; the
/// background-task hook records instead of calling UIKit; the Undo banner's wait returns at once
/// (it is never read); and the earlier assistant turns are plain text rows, as the app stores
/// them (a tool call made in an earlier turn is not in the history, in the app either).
///
/// Graded with cheap rules only (the pass is "a usable reply"); quality is for `judge.py`.
extension LiveEvals {

    struct ConversationCase: Decodable, Sendable {
        struct Turn: Decodable, Sendable {
            /// `user` or `assistant`.
            let role: String
            let content: String
        }

        let id: String
        /// `alex` (the fixture user who is gaining) or `sam` (the one who is losing).
        let user: String
        /// A `GoalPace` raw value for the cases that give the fixture user another goal
        /// (`maintain`); absent otherwise.
        let pace: String?
        /// The coach's durable notes (`CoachMemory.profileNotes`) at the start of the case; absent for none.
        let memoryNotes: String?
        /// The tool the next reply should call, `none` when it should call none, or absent
        /// when either is fine. Only the `tool_as_expected` score reads it; it never decides the pass.
        let expectTool: String?
        /// The conversation so far, oldest first, ending with the user's new message.
        let turns: [Turn]
        /// What a good next reply does, for a person reading the results (and the judge's rubric
        /// author). Not graded in code.
        let goodReply: String

        /// The key `EvalFixtures` takes: `gain` is Alex, anything else is Sam.
        var fixtureKey: String? {
            switch user {
            case "alex": return "gain"
            case "sam": return "loss"
            default: return nil
            }
        }
    }

    func testCoachConversation() async throws {
        try EvalEnv.requireLive()
        let cases = try EvalDataset.load("coach_conversations/v1.jsonl", as: ConversationCase.self)
        try await EvalRunner.run(task: .coachTurn, dataset: "coach_conversations/v1", cases: cases,
                                 caseID: { $0.id }) { item in
            await Self.conversationAttempt(item)
        }
    }

    /// Why a case cannot be run as the app would run it, or nil.
    @MainActor
    static func conversationProblem(_ item: ConversationCase) -> String? {
        if item.fixtureKey == nil { return "user \(item.user) is neither alex nor sam" }
        if let pace = item.pace, GoalPace(rawValue: pace) == nil { return "pace \(pace) is not a GoalPace" }
        if let tool = item.expectTool, tool != "none", CoachTools.Name(rawValue: tool) == nil {
            return "expectTool \(tool) is not one of the app's tools"
        }
        guard item.turns.first?.role == "user", item.turns.last?.role == "user" else {
            return "the turns must open and end on the user (the app drops a leading assistant turn)"
        }
        if item.turns.contains(where: { !["user", "assistant"].contains($0.role)
            || $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "every turn needs a user or assistant role and some text"
        }
        // Past the verbatim window the app would also start a memory fold (another model call)
        // and the oldest turns would not be sent: not what this dataset measures.
        if item.turns.count > CoachTurnEngine.maxHistoryMessages {
            return "\(item.turns.count) turns, more than the \(CoachTurnEngine.maxHistoryMessages) the app sends"
        }
        return nil
    }

    @MainActor
    static func conversationAttempt(_ item: ConversationCase) async -> EvalOutcome {
        if let problem = conversationProblem(item) {
            return EvalOutcome(ok: false, error: "dataset: \(item.id): \(problem)", scores: [:], pass: false, output: "")
        }
        guard let key = item.fixtureKey, let newMessage = item.turns.last?.content else {
            return EvalOutcome(ok: false, error: "dataset: \(item.id) has no user", scores: [:], pass: false, output: "")
        }

        // The store, as the app would have it at this point of the conversation.
        let fixture = EvalFixtures.user(key)
        let profile = fixture.profile
        if let pace = item.pace, let chosen = GoalPace(rawValue: pace) { profile.pace = chosen }
        let container: ModelContainer
        do { container = try TestStore.makeContainer() } catch { return .failed(error) }
        let context = container.mainContext
        context.insert(profile)
        fixture.foods.forEach(context.insert)
        fixture.weights.forEach(context.insert)
        fixture.water.forEach(context.insert)
        if let notes = item.memoryNotes, !notes.isEmpty { context.insert(CoachMemory(profileNotes: notes)) }
        // Distinct, increasing `createdAt`s (the history is read newest first by date), ending
        // just before now. Nothing in the prompt reads a message's date.
        let clock = TickingClock(start: Date().addingTimeInterval(-600))
        var earlier = Set<UUID>()
        for turn in item.turns.dropLast() {
            let row = ChatMessage(role: turn.role, content: turn.content, createdAt: clock.now())
            context.insert(row)
            earlier.insert(row.id)
        }
        do { try context.save() } catch { return .failed(error) }

        // The runtime in force (provider, key, model, usage, and the harness's own recorder,
        // which `given` comes from), with every response of the turn also kept here, so the
        // record can say which tools the model asked for.
        let log = ConversationResponseLog(around: AIRuntime.transport)
        var runtime = AIRuntime.current ?? AIRuntime()
        runtime.transport = log
        var env = CoachTurnEngine.Environment()
        env.now = { clock.now() }
        env.sleep = { _ in }
        env.background = RecordingBackgroundTasks()
        env.runtime = runtime
        let engine = CoachTurnEngine(context: context, profile: profile, env: env)

        guard let task = engine.send(text: newMessage) else {
            return EvalOutcome(ok: false, error: "the engine did not start a turn", scores: [:], pass: false, output: "")
        }
        await task.value

        // What the chat shows: the turn's assistant rows (the empty-reply fallback included,
        // since the user sees it), then the Undo banner of each quick log that was applied, then
        // the confirm card of a change waiting for the user's Yes.
        let rows = (try? context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let replies = rows.filter { !earlier.contains($0.id) && !$0.isUser && !$0.isDecision }
        let written = replies.filter { $0.content != CoachTurnEngine.emptyReplyFallback }
        let replyText = written.map(\.content).joined(separator: "\n\n")

        let tools = conversationToolCalls(log.responses, fixture: fixture, profile: profile)
        let proposal = engine.pendingTool.map {
            "[proposes: \($0.request.name.rawValue): \($0.request.confirmSummary)]"
        }
        let shown = (replies.map(\.content) + tools.appliedLines + [proposal].compactMap { $0 })
            .joined(separator: "\n\n")

        let reader = EvalFixtures.reader(key)
        let usable = engine.failure == nil && (!replyText.isEmpty || proposal != nil)
        var scores: [String: Double] = [
            "used": usable ? 1 : 0,
            "reply_non_empty": replyText.isEmpty ? 0 : 1,
            "fallback_shown": replies.count != written.count ? 1 : 0,
            "wrong_person_pronoun": Graders.wrongPersonPronoun(replyText, reader: reader) ? 1 : 0,
            "tool_called": tools.calledAny ? 1 : 0,
            "tool_call_count": Double(tools.handled.count),
            "tool_applied_count": Double(tools.appliedLines.count),
            "tool_proposed": proposal == nil ? 0 : 1,
            "tool_invalid_count": Double(tools.invalid),
            "tool_calls_dropped_by_app": Double(tools.dropped),
            "assistant_messages": Double(written.count),
            "reply_words": Double(Graders.wordCount(replyText)),
            "reply_sentences": Double(Graders.sentenceCount(replyText)),
            "reply_chars": Double(replyText.count),
        ]
        if let expected = item.expectTool {
            let names = Set(tools.handled)
            scores["tool_as_expected"] = (expected == "none" ? names.isEmpty : names.contains(expected)) ? 1 : 0
        }

        // The reply text; for a turn that is only a confirm card, the card, so the judge
        // (which skips an empty `output`) still compares it.
        let output = String((replyText.isEmpty ? (proposal ?? "") : replyText).prefix(EvalRunner.outputLimit))
        if let failure = engine.failure {
            // A cut-off reply leaves its partial text on screen with a Retry; the record keeps it.
            return EvalOutcome(ok: false, error: "the turn failed: \(failure.error.logName)", scores: scores,
                               pass: false, output: output, shown: String(shown.prefix(EvalRunner.outputLimit)),
                               given: conversationGiven(item))
        }
        return EvalOutcome(ok: usable, error: usable ? nil : "no reply and no proposal", scores: scores,
                           pass: usable, output: output, shown: String(shown.prefix(EvalRunner.outputLimit)),
                           given: conversationGiven(item))
    }

    /// The tool calls the engine acted on in one turn, read from the provider responses in order.
    struct ConversationTools {
        /// The name of each call the engine handled (one per response, before the depth cap).
        var handled: [String] = []
        /// `[applied: name: summary]` for each quick log the engine applied (the Undo banner's text).
        var appliedLines: [String] = []
        /// Calls `CoachTools.parse` rejected (sent back to the model as an error result; nothing shown).
        var invalid = 0
        /// Extra calls in a response beyond the first, and calls past the depth cap: the engine ignores both.
        var dropped = 0
        var calledAny: Bool { !handled.isEmpty || dropped > 0 }
    }

    /// Mirrors what the engine does with each response: the clients expose only the FIRST tool
    /// call of a response, and from the `maxToolDepth`-th call on a tool request is ignored. Each
    /// handled call is validated again with `CoachTools.parse` against the fixture's state (the
    /// engine's own result is not exposed), to tell an applied quick log from a rejected call;
    /// a call that needs confirmation is reported from the engine's `pendingTool` instead.
    @MainActor
    static func conversationToolCalls(_ responses: [Data], fixture: EvalFixtures.User,
                                      profile: UserProfile) -> ConversationTools {
        var out = ConversationTools()
        let turns = responses.compactMap(toolCalls(inResponse:))   // completed model turns only
        let todays = CoachContext.todaysFoods(fixture.foods)
        let current = TrendCalculator.currentTrend(fixture.weights)
        for (depth, calls) in turns.enumerated() {
            guard let first = calls.first else { continue }
            guard depth < CoachTurnEngine.maxToolDepth else { out.dropped += calls.count; continue }
            out.dropped += calls.count - 1
            out.handled.append(first.name)
            switch CoachTools.parse(name: first.name, input: first.input, profile: profile,
                                    todaysFoods: todays, currentWeightLbs: current) {
            case .invalid: out.invalid += 1
            case .ok(let request) where !request.requiresConfirm:
                out.appliedLines.append("[applied: \(first.name): \(request.confirmSummary)]")
            case .ok: break
            }
        }
        return out
    }

    /// The tool calls of one provider response, in order, whichever wire format it is in
    /// (Anthropic Messages, OpenAI Chat Completions, OpenAI Responses). Nil for a body that is
    /// not a completed model turn (an error the client retried, or not JSON), so a response's
    /// position among the non-nil ones is its depth in the turn.
    static func toolCalls(inResponse data: Data) -> [(name: String, input: [String: Any])]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["error"] == nil || json["error"] is NSNull else { return nil }
        func object(_ arguments: Any?) -> [String: Any] {
            EvalRunner.jsonObject(arguments as? String) ?? [:]
        }
        var calls: [(name: String, input: [String: Any])] = []
        var isTurn = false
        if let content = json["content"] as? [[String: Any]] {                        // Anthropic
            isTurn = true
            for block in content where (block["type"] as? String) == "tool_use" {
                if let name = block["name"] as? String { calls.append((name, block["input"] as? [String: Any] ?? [:])) }
            }
        }
        if let output = json["output"] as? [[String: Any]] {                          // OpenAI Responses
            isTurn = true
            for item in output where (item["type"] as? String) == "function_call" {
                if let name = item["name"] as? String { calls.append((name, object(item["arguments"]))) }
            }
        }
        if let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] {  // Chat Completions
            isTurn = true
            for call in (message["tool_calls"] as? [[String: Any]]) ?? [] {
                if let function = call["function"] as? [String: Any], let name = function["name"] as? String {
                    calls.append((name, object(function["arguments"])))
                }
            }
        }
        return isTurn ? calls : nil
    }

    /// What a judge needs to read beside the reply: the data the coach was given (the same
    /// `CoachContext.summary` its system prompt carries), its notes, and the conversation. The
    /// request's last user message is only the newest message, so this is passed as the
    /// outcome's `given`, which the harness records in its place.
    @MainActor
    static func conversationGiven(_ item: ConversationCase) -> String {
        guard let key = item.fixtureKey else { return "" }
        let fixture = EvalFixtures.user(key)
        if let pace = item.pace, let chosen = GoalPace(rawValue: pace) { fixture.profile.pace = chosen }
        var out = "The user's data, as the coach sees it:\n"
            + CoachContext.summary(profile: fixture.profile, foods: fixture.foods,
                                   weights: fixture.weights, water: fixture.water)
        if let notes = item.memoryNotes, !notes.isEmpty {
            out += "\n\nWhat the coach remembers about the user:\n\(notes)"
        }
        out += "\n\nThe conversation so far:\n" + item.turns.dropLast()
            .map { "\($0.role == "user" ? "User" : "Vita"): \($0.content)" }
            .joined(separator: "\n\n")
        out += "\n\nThe user's new message:\n\(item.turns.last?.content ?? "")"
        return out
    }
}

/// Hands every request to the transport in force and keeps every response body, in order.
/// (`ResponseRecorder` keeps only the last, and a turn can make several calls.)
final class ConversationResponseLog: AITransport, @unchecked Sendable {
    private let inner: any AITransport
    private let lock = NSLock()
    private var bodies: [Data] = []

    init(around inner: any AITransport) { self.inner = inner }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await inner.data(for: request)
        lock.withLock { bodies.append(data) }
        return (data, response)
    }

    var responses: [Data] { lock.withLock { bodies } }
}
