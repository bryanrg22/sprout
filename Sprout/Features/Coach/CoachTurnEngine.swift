import Foundation
import Observation
import SwiftData
import UIKit

// MARK: - What the engine needs from outside

/// Keeps a turn running for the short time iOS allows after the app leaves the foreground,
/// so a reply that is seconds away still arrives and is saved.
protocol CoachBackgroundTasking {
    @MainActor func begin(_ name: String) -> Int
    @MainActor func end(_ token: Int)
}

/// `UIApplication.beginBackgroundTask`. The system gives a finite amount of time (about 30 s
/// in practice, not guaranteed); when it runs out the task is ended and the request fails
/// like any other dropped connection, which the engine reports with a Retry.
@MainActor
final class UIKitBackgroundTasks: CoachBackgroundTasking {
    private var active: Set<Int> = []

    nonisolated init() {}

    func begin(_ name: String) -> Int {
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in self?.end(identifier.rawValue) }
        }
        if identifier != .invalid { active.insert(identifier.rawValue) }
        return identifier.rawValue
    }

    func end(_ token: Int) {
        guard active.remove(token) != nil else { return }
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: token))
    }
}

/// Every row the coach's system prompt is built from, read from the store when a model
/// call is made.
struct CoachDataSnapshot {
    var foods: [FoodEntry] = []
    var weights: [WeightEntry] = []
    var workouts: [WorkoutEntry] = []
    var water: [WaterEntry] = []
    var steps: [StepsEntry] = []
    var sessions: [WorkoutSession] = []
    var exercises: [ExerciseEntry] = []
    var sleep: [SleepEntry] = []
    var detected: [DetectedWorkout] = []
    var vitals: [VitalsEntry] = []

    @MainActor
    static func fetch(from context: ModelContext) -> CoachDataSnapshot {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }
        return CoachDataSnapshot(foods: all(FoodEntry.self), weights: all(WeightEntry.self),
                                 workouts: all(WorkoutEntry.self), water: all(WaterEntry.self),
                                 steps: all(StepsEntry.self), sessions: all(WorkoutSession.self),
                                 exercises: all(ExerciseEntry.self), sleep: all(SleepEntry.self),
                                 detected: all(DetectedWorkout.self), vitals: all(VitalsEntry.self))
    }
}

// MARK: - The engine

/// The coach's turn logic: everything between the user pressing send and the reply (or the
/// reason there is none) being on screen.
///
/// One user message starts one turn. A turn is a chain of model calls: the first call, then
/// one more for every tool the model asks for (the tool's result goes back so the model can
/// answer in prose), until the model replies without a tool, asks for something that needs
/// the user's confirmation, or a call fails.
///
/// - The user's message is saved before the first call, so it is never lost.
/// - A tool request is validated (`CoachTools.parse`). An invalid one is answered with an
///   error result so the model can recover. A valid one that changes a goal or deletes
///   something waits for the user's Yes (`pendingTool`); a quick reversible log is applied
///   at once with an Undo.
/// - After `maxToolDepth` chained tools the next call forbids tools, and a tool the model
///   asks for anyway is ignored, so a turn always ends.
/// - A failed call ends the turn with a typed `Failure`. `retry()` issues that same call
///   again: a tool that was already applied is not applied twice, and no second copy of the
///   user's message is made.
/// - While a turn is in flight `send` does nothing, so a second tap cannot start a second turn.
/// - The task that runs a turn holds the engine, so a reply that arrives after the screen
///   went away is still saved.
///
/// The view owns nothing of this: it reads the observable state and forwards taps.
@MainActor
@Observable
final class CoachTurnEngine {

    /// How many recent messages travel verbatim with each turn. Older ones are not lost:
    /// they are folded into `CoachMemory`, which is part of every system prompt.
    static let maxHistoryMessages = 16
    /// Chained tool round-trips allowed per user message before tools are forbidden.
    static let maxToolDepth = 5
    /// The most messages one memory fold sends to the model. A longer backlog is folded
    /// over several replies, oldest first.
    static let memoryFoldBatch = 40
    /// Shown when the model ends its turn with no text and no tool.
    static let emptyReplyFallback = "I'm here 💚"
    static let declinedToolResult = "The user decided not to make this change right now. "
        + "Nothing was changed. Respond warmly and without any pressure."

    /// What the engine takes from outside, so a test can replace each piece.
    struct Environment {
        /// The clock: every message's `createdAt`, the memory row's `updatedAt`, and the
        /// moment a rate-limit wait ends.
        var now: @MainActor () -> Date = { Date() }
        /// How the Undo banner waits before it dismisses itself.
        var sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        var background: any CoachBackgroundTasking = UIKitBackgroundTasks()
        /// Scopes every model call of this engine (provider, key, transport). Nil in the app.
        var runtime: AIRuntime?
        /// How long after a turn starts a Stop is ignored. The send button becomes the stop
        /// button in place, so without this a double tap on send would cancel what it sent.
        var stopGuard: TimeInterval = 0.6
    }

    /// A validated tool request waiting for the user's Yes or Not now, with what is needed
    /// to continue the turn once they answer.
    struct PendingTool {
        let request: CoachTools.ParsedRequest
        let toolUseId: String
        let assistantContent: [[String: Any]]
        /// The messages of the call that produced the request.
        let history: [AnthropicClient.Msg]
    }

    /// A change that was just applied and can be reversed with one tap.
    struct UndoToast: Identifiable {
        let id = UUID()
        let summary: String
        let undo: @MainActor () -> Void
    }

    /// Why the last turn has no reply, what the user reads, and what they can do.
    struct Failure: Identifiable, Equatable {
        let id: UUID
        let error: CoachTurnError
        let message: String
        let action: CoachTurnError.Action
        /// For a rate limit with a stated wait: the moment Retry makes sense again.
        let retryNotBefore: Date?
    }

    // MARK: Observable state

    private(set) var isSending = false
    private(set) var pendingTool: PendingTool?
    private(set) var failure: Failure?
    private(set) var undoToast: UndoToast?
    /// The reply that is being revealed word by word. The view clears it when the reveal ends.
    var streamingMessageID: UUID?
    /// Bumped for each action that deserves a light haptic (send, confirm, decline, undo, retry).
    private(set) var hapticTick = 0
    /// Bumped when a confirmed change is applied.
    private(set) var confettiTick = 0

    // MARK: Wiring

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var profile: UserProfile?
    @ObservationIgnored var env = Environment()
    /// What the engine did to the stored conversation.
    enum TranscriptChange: Equatable {
        /// One or more messages were added at the end.
        case added
        /// These messages were deleted.
        case removed(Set<UUID>)
    }

    /// Called after the engine inserts or deletes a `ChatMessage`, so the transcript can follow.
    @ObservationIgnored var onTranscriptChange: (@MainActor (TranscriptChange) -> Void)?
    /// The running turn; await its `value` to wait for the turn to settle.
    @ObservationIgnored private(set) var turnTask: Task<Void, Never>?
    /// The running memory fold, if one was started after the last reply.
    @ObservationIgnored private(set) var memoryTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var failedCall: Call?
    @ObservationIgnored private var turnStartedAt = Date.distantPast

    /// An engine with no store yet. The view creates it before it has a model context and
    /// calls `attach` when it appears.
    nonisolated init() {}

    convenience init(context: ModelContext, profile: UserProfile, env: Environment = Environment()) {
        self.init()
        self.env = env
        attach(context: context, profile: profile)
    }

    /// Gives the engine its store and profile. The view calls this when it appears, because
    /// the model context comes from the environment; calling it again is harmless.
    func attach(context: ModelContext, profile: UserProfile) {
        self.context = context
        self.profile = profile
    }

    var isAttached: Bool { context != nil && profile != nil }

    // MARK: - One model call

    /// Everything needed to issue (or re-issue) one model call of a turn.
    private struct Call {
        var messages: [AnthropicClient.Msg]
        /// Tool round-trips made so far in this turn.
        var depth: Int
        /// The first call of a turn is rebuilt from the store on retry; a later call is
        /// re-issued as it was, so the tool results it carries are not produced twice.
        var isFirst: Bool
        /// Replies this call saved before it was found to be cut off. Retry removes them.
        var partialReplyIDs: [UUID] = []
    }

    private enum Next {
        case done
        case call(Call)
    }

    // MARK: - Sending

    /// Saves the user's message and starts a turn. Does nothing (and returns nil) when the
    /// message is empty or a turn is already in flight.
    @discardableResult
    func send(text rawText: String, imageData: Data? = nil) -> Task<Void, Never>? {
        guard let context else { return nil }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || imageData != nil, !isSending else { return nil }

        hapticTick += 1
        // A new send clears the last failure: the client is rebuilt and re-reads the key,
        // so a key added in Settings since then is picked up.
        clearFailure()
        // A brand-new message supersedes any unanswered tool proposal.
        pendingTool = nil
        streamingMessageID = nil   // snap any reveal in progress to its full text

        // Saved before the call, so the message shows (and survives) even if the call fails.
        context.insert(ChatMessage(role: "user", content: text, imageData: imageData, createdAt: env.now()))
        save("user message")
        onTranscriptChange?(.added)

        let history = Self.apiMessages(recentHistory())
        Diagnostics.shared.log("coach send: \(text.count) chars, \(history.count) history msgs", .coach)
        return start(Call(messages: history, depth: 0, isFirst: true))
    }

    /// Issues the failed call again. The user's message is already stored once and is not
    /// stored again; a tool that was applied before the failure is not applied again.
    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard !isSending, let failure, failure.error.canRetry else { return nil }
        let call = failedCall
        hapticTick += 1
        clearFailure()
        if let partial = call?.partialReplyIDs, !partial.isEmpty { deleteRows(partial) }

        if let call, !call.isFirst {
            return start(Call(messages: call.messages, depth: call.depth, isFirst: false))
        }
        let history = Self.apiMessages(recentHistory())
        guard !history.isEmpty else { return nil }
        Diagnostics.shared.log("coach retry: \(history.count) history msgs", .coach)
        return start(Call(messages: history, depth: 0, isFirst: true))
    }

    /// Stops the turn in flight. The user's message stays; anything a tool already wrote
    /// stays too (its Undo is still offered).
    func stop() {
        guard isSending, env.now().timeIntervalSince(turnStartedAt) >= env.stopGuard else { return }
        turnTask?.cancel()
    }

    func dismissFailure() { clearFailure() }

    private func clearFailure() {
        failure = nil
        failedCall = nil
    }

    private func start(_ call: Call) -> Task<Void, Never> {
        isSending = true
        turnStartedAt = env.now()
        let token = env.background.begin("coach-turn")
        // The task holds `self` on purpose: a reply that lands after the view (and its
        // reference to the engine) is gone still has somewhere to be saved from.
        let task = Task { @MainActor in
            await self.run(call)
            self.env.background.end(token)
        }
        turnTask = task
        return task
    }

    private func run(_ first: Call) async {
        var call = first
        while true {
            let next: Next
            if let runtime = env.runtime {
                next = await AIRuntime.$current.withValue(runtime) { await self.attempt(call) }
            } else {
                next = await attempt(call)
            }
            switch next {
            case .done:
                isSending = false
                return
            case .call(let following):
                call = following
            }
        }
    }

    private func attempt(_ call: Call) async -> Next {
        guard let context, let profile else { return .done }
        let provider = AIConfig.provider(for: .coachTurn)
        // Snapshot the prompt and the schemas here, on the main actor, so no model object
        // crosses to the network call.
        let data = CoachDataSnapshot.fetch(from: context)
        let system = CoachContext.systemParts(profile: profile, foods: data.foods, weights: data.weights,
                                              workouts: data.workouts, water: data.water, steps: data.steps,
                                              sessions: data.sessions, exercises: data.exercises,
                                              sleep: data.sleep, detected: data.detected, vitals: data.vitals,
                                              memory: CoachMemory.fetchOrCreate(in: context, profile: profile),
                                              plan: CoachPlan.current(in: context))
        // Once enough tools are chained the model must finish in prose. The schemas stay in
        // the request (the history holds tool blocks, which need them); the choice is "none".
        let tools = CoachTools.schemas(for: profile)
        let forbidToolUse = call.depth >= Self.maxToolDepth
        let messages = call.messages
        let recorder = AIFailureRecorder()

        do {
            let turn = try await AIFailureRecorder.$current.withValue(recorder) {
                let client = try AIClient.makeFull(for: .coachTurn)
                return try await client.chatWithTools(system: system.volatile,
                                                      messages: messages, tools: tools,
                                                      model: AIConfig.model(for: .coachTurn),
                                                      maxTokens: 1500,
                                                      cachedSystemPrefix: system.stable,
                                                      forbidToolUse: forbidToolUse)
            }
            // A reply that arrives after Stop is not shown.
            try Task.checkCancellation()
            Diagnostics.shared.log("coach reply ok: \(turn.text.count) chars, tool=\(turn.toolUse?.name ?? "none")", .coach)
            return handle(turn, call: call, provider: provider, data: data)
        } catch {
            let kind = CoachTurnError.classify(error, http: recorder.last)
            Diagnostics.shared.log("coach error (\(kind.logName)): \(error)",
                                   kind == .missingKey || kind == .cancelled ? .coach : .error)
            fail(kind, provider: provider, call: call)
            return .done
        }
    }

    // MARK: - Handling a model turn

    private func handle(_ turn: AnthropicClient.ChatTurn, call: Call,
                        provider: AIProvider, data: CoachDataSnapshot) -> Next {
        guard let context, let profile else { return .done }
        // Any prose is saved whether or not a tool was also requested, so the conversation
        // reads naturally.
        let trimmed = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var savedReply: UUID?
        if !trimmed.isEmpty {
            let reply = ChatMessage(role: "assistant", content: trimmed, createdAt: env.now())
            context.insert(reply)
            save("assistant reply")
            savedReply = reply.id
            streamingMessageID = reply.id   // the freshest reply types itself out
            onTranscriptChange?(.added)
        }

        var toolUse = turn.toolUse
        if toolUse != nil, call.depth >= Self.maxToolDepth {
            // Tools were forbidden for this call. A model that asks for one anyway is not
            // obeyed: the chain has to end somewhere.
            Diagnostics.shared.log("coach: ignored a tool call past the depth cap", .coach)
            toolUse = nil
        }

        guard let toolUse else {
            switch turn.finish {
            case .cutOff:
                // The partial text (if any) stays on screen; Retry replaces it.
                var failed = call
                failed.partialReplyIDs = savedReply.map { [$0] } ?? []
                fail(.cutOff, provider: provider, call: failed)
                return .done
            case .contextOverflow:
                fail(.tooLong, provider: provider, call: call)
                return .done
            case .refusal where trimmed.isEmpty:
                fail(.refusal, provider: provider, call: call)
                return .done
            case .refusal, .complete:
                break
            }
            // A plain reply. With no text either, a gentle fallback rather than an empty turn.
            if trimmed.isEmpty {
                context.insert(ChatMessage(role: "assistant", content: Self.emptyReplyFallback, createdAt: env.now()))
                save("fallback reply")
                onTranscriptChange?(.added)
            }
            // The reply is on screen. Off the user's turn, fold what has left the verbatim
            // window into long-term memory. Every final reply ends here.
            consolidateMemoryIfNeeded()
            return .done
        }

        // Validate against the profile before offering or applying anything.
        switch CoachTools.parse(name: toolUse.name, input: toolUse.input, profile: profile,
                                todaysFoods: CoachContext.todaysFoods(data.foods),
                                currentWeightLbs: TrendCalculator.currentTrend(data.weights)) {
        case .invalid(let reason):
            // Straight back to the model as an error result, so it recovers in conversation.
            return .call(continuation(of: call, turn: turn, toolUseId: toolUse.id,
                                      resultText: reason, isError: true))

        case .ok(let request) where request.requiresConfirm:
            // Destructive or goal-changing: nothing is applied until the user says Yes.
            pendingTool = PendingTool(request: request, toolUseId: toolUse.id,
                                      assistantContent: turn.assistantContent, history: call.messages)
            return .done

        case .ok(let request):
            // A quick, reversible log: apply now, offer Undo, and tell the model.
            let applied = CoachTools.applyReturningUndo(request, to: profile, context: context)
            if let undo = applied.undo { showUndoToast(summary: request.confirmSummary, undo: undo) }
            return .call(continuation(of: call, turn: turn, toolUseId: toolUse.id,
                                      resultText: applied.resultText,
                                      isError: !applied.changed))   // a declined tool is not a success
        }
    }

    /// The call that follows a tool: the same messages, then the assistant's tool request,
    /// then the tool's result, exactly as both providers require.
    private func continuation(of call: Call, turn: AnthropicClient.ChatTurn, toolUseId: String,
                              resultText: String, isError: Bool) -> Call {
        Call(messages: Self.continued(call.messages, assistantContent: turn.assistantContent,
                                      toolUseId: toolUseId, resultText: resultText, isError: isError),
             depth: call.depth + 1, isFirst: false)
    }

    static func continued(_ history: [AnthropicClient.Msg], assistantContent: [[String: Any]],
                          toolUseId: String, resultText: String, isError: Bool) -> [AnthropicClient.Msg] {
        history + [AnthropicClient.assistantMessage(content: assistantContent),
                   AnthropicClient.toolResultMessage(toolUseId: toolUseId, resultText: resultText,
                                                      isError: isError)]
    }

    private func fail(_ error: CoachTurnError, provider: AIProvider, call: Call?) {
        let retryNotBefore: Date?
        if case .retryAfter(let wait) = error.action { retryNotBefore = env.now().addingTimeInterval(wait) }
        else { retryNotBefore = nil }
        failedCall = call
        failure = Failure(id: UUID(), error: error,
                          message: error.message(provider: provider),
                          action: error.action, retryNotBefore: retryNotBefore)
    }

    // MARK: - Confirm / decline

    /// The user tapped Yes: apply the change, record the decision, and let the model reply.
    @discardableResult
    func confirmPendingTool() -> Task<Void, Never>? {
        guard let context, let profile, let pending = pendingTool, !isSending else { return nil }
        pendingTool = nil
        hapticTick += 1

        let resultText = CoachTools.apply(pending.request, to: profile, context: context)
        confettiTick += 1
        recordDecision(summary: pending.request.confirmSummary, accepted: true)

        return start(Call(messages: Self.continued(pending.history,
                                                   assistantContent: pending.assistantContent,
                                                   toolUseId: pending.toolUseId,
                                                   resultText: "Applied. \(resultText)", isError: false),
                          depth: 0, isFirst: false))
    }

    /// The user tapped Not now: nothing changes, and the model is told so.
    @discardableResult
    func declinePendingTool() -> Task<Void, Never>? {
        guard context != nil, let pending = pendingTool, !isSending else { return nil }
        pendingTool = nil
        hapticTick += 1
        recordDecision(summary: pending.request.confirmSummary, accepted: false)

        return start(Call(messages: Self.continued(pending.history,
                                                   assistantContent: pending.assistantContent,
                                                   toolUseId: pending.toolUseId,
                                                   resultText: Self.declinedToolResult, isError: false),
                          depth: 0, isFirst: false))
    }

    /// A settled decision stays in the transcript as a grayed card. It is a marker only:
    /// never sent to the model, never folded into memory.
    private func recordDecision(summary: String, accepted: Bool) {
        context?.insert(ChatMessage(role: "assistant", content: "", createdAt: env.now(),
                                    decisionSummary: summary, decisionAccepted: accepted))
        save("decision")
        onTranscriptChange?(.added)
    }

    // MARK: - Undo

    private func showUndoToast(summary: String, undo: @escaping @MainActor () -> Void) {
        undoTask?.cancel()
        let toast = UndoToast(summary: summary, undo: undo)
        undoToast = toast
        let sleep = env.sleep
        let window = Self.undoWindow
        undoTask = Task { @MainActor [weak self] in
            await sleep(window)
            guard !Task.isCancelled, let self, self.undoToast?.id == toast.id else { return }
            self.undoToast = nil
        }
    }

    /// How long the Undo banner stays: 5 seconds in the app. The UI flows get 15, because on a
    /// slow CI runner finding the button, letting it settle and tapping it took longer than 5
    /// and the tap found nothing (main, 2026-11-25).
    static var undoWindow: Duration { UITestHooks.isActive ? .seconds(15) : .seconds(5) }

    /// Reverses the last auto-applied change and dismisses the banner.
    func performUndo() {
        guard let toast = undoToast else { return }
        undoTask?.cancel()
        toast.undo()
        hapticTick += 1
        undoToast = nil
    }

    // MARK: - History sent to the model

    /// The newest `maxHistoryMessages` real messages (no welcome seed, no decision marker),
    /// oldest first, fetched with a limit rather than by loading the conversation.
    func recentHistory() -> [ChatMessage] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.isSystemSeed == false && $0.decisionSummary == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = Self.maxHistoryMessages
        let newestFirst = (try? context.fetch(descriptor)) ?? []
        return Self.historyWindow(newestFirst.reversed())
    }

    /// The window rule on messages that are already oldest first: drop the seed and decision
    /// markers and anything with nothing in it, keep the last `maxHistoryMessages`, and start
    /// on a user turn (both providers require the conversation to open with the user).
    static func historyWindow(_ messages: [ChatMessage]) -> [ChatMessage] {
        var recent = Array(messages
            .filter { !$0.isSystemSeed && !$0.isDecision }
            .suffix(maxHistoryMessages))
        // An empty message is not a turn, and a provider rejects an empty text block.
        recent.removeAll { $0.content.isEmpty && $0.imageData == nil }
        while let first = recent.first, first.roleRaw != "user" { recent.removeFirst() }
        return recent
    }

    /// Stored messages → the client's messages. One with a photo becomes an image block
    /// (plus its text, when it has any); the rest stay plain strings.
    static func apiMessages(_ window: [ChatMessage]) -> [AnthropicClient.Msg] {
        window.map { message in
            if let data = message.imageData {
                var blocks: [[String: Any]] = [AnthropicClient.imageBlock(data)]
                if !message.content.isEmpty { blocks.append(AnthropicClient.textBlock(message.content)) }
                return AnthropicClient.Msg(role: message.roleRaw, content: blocks)
            }
            return AnthropicClient.Msg(role: message.roleRaw, content: message.content)
        }
    }

    // MARK: - Welcome seed, unanswered message, delete

    /// The canned welcome, once, in an empty conversation. Never sent to the model.
    func seedWelcomeIfNeeded() {
        guard let context, let profile else { return }
        guard ((try? context.fetchCount(FetchDescriptor<ChatMessage>())) ?? 0) == 0 else { return }
        let name = profile.name.isEmpty ? "there" : profile.name
        let coachName = profile.coachName.isEmpty ? "Vita" : profile.coachName
        // Direction-aware: the same wording the persona uses, from the profile's goal.
        let role = CoachContext.buddyRole(profile.pace.direction)
        let welcome = """
        Hi \(name)! I'm \(coachName), your \(role) 💚 \
        I'm here to cheer you on, talk through the hard days, and help you make sense of your progress. \
        Ask me anything, or tap a prompt below to get started.
        """
        context.insert(ChatMessage(role: "assistant", content: welcome, createdAt: env.now(), isSystemSeed: true))
        save("welcome seed")
        onTranscriptChange?(.added)
    }

    /// If the newest message is the user's and nothing is in flight or waiting, the reply
    /// never arrived (the app was closed or suspended mid-request). Says so, with a Retry.
    func noteUnansweredMessageIfAny() {
        guard let context, !isSending, pendingTool == nil, failure == nil else { return }
        guard let newest = newestConversationRow(in: context), newest.isUser else { return }
        fail(.interrupted, provider: env.runtime?.provider ?? AIConfig.provider(for: .coachTurn), call: nil)
    }

    private func newestConversationRow(in context: ModelContext) -> ChatMessage? {
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.decisionSummary == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Removes one message from the conversation for good.
    func delete(messageID: UUID) {
        deleteRows([messageID])
        if streamingMessageID == messageID { streamingMessageID = nil }
        // A failure that was about a message which is no longer the newest has nothing to retry.
        if failure != nil, !isSending, let context,
           newestConversationRow(in: context)?.isUser != true {
            clearFailure()
        }
    }

    private func deleteRows(_ ids: [UUID]) {
        guard let context, !ids.isEmpty else { return }
        let rows = (try? context.fetch(FetchDescriptor<ChatMessage>(
            predicate: #Predicate { ids.contains($0.id) }))) ?? []
        guard !rows.isEmpty else { return }
        let removed = Set(rows.map(\.id))
        rows.forEach(context.delete)
        save("delete message")
        onTranscriptChange?(.removed(removed))
    }

    private func save(_ what: String) {
        guard let context else { return }
        CoachTools.saveOrLog(context, what)
    }

    // MARK: - Long-term memory

    /// The messages the next fold should summarize: real messages older than the verbatim
    /// window and newer than what memory already holds, oldest first, at most
    /// `memoryFoldBatch`. Three small fetches, never the whole conversation.
    func messagesToFold(summarizedThrough: Date?) -> [ChatMessage] {
        guard let context else { return [] }
        let window = Self.maxHistoryMessages
        var newest = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.isSystemSeed == false && $0.decisionSummary == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        newest.fetchLimit = window + 1
        guard let rows = try? context.fetch(newest), rows.count > window else { return [] }
        let windowStart = rows[window - 1].createdAt   // the oldest message still sent verbatim
        let after = summarizedThrough ?? .distantPast

        var older = FetchDescriptor<ChatMessage>(
            predicate: #Predicate {
                $0.isSystemSeed == false && $0.decisionSummary == nil
                    && $0.createdAt < windowStart && $0.createdAt > after
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        older.fetchLimit = Self.memoryFoldBatch
        return (try? context.fetch(older)) ?? []
    }

    /// After a final reply: if messages have left the verbatim window and are not in memory
    /// yet, fold them in with one cheap model call in the background, then store the new
    /// notes and summary and advance the high-water mark. On any failure memory and the mark
    /// stay as they were, so the same batch is retried after the next reply.
    private func consolidateMemoryIfNeeded() {
        guard let context, let profile else { return }
        let memory = CoachMemory.fetchOrCreate(in: context, profile: profile)
        let toFold = messagesToFold(summarizedThrough: memory.summarizedThroughDate)
        guard !toFold.isEmpty, let newHighWater = toFold.map(\.createdAt).max() else { return }

        // Plain values only: no model object crosses to the background call.
        let snapshots = toFold.map {
            CoachMemoryService.MessageSnapshot(role: $0.roleRaw, content: $0.content, createdAt: $0.createdAt)
        }
        let currentNotes = memory.profileNotes
        let currentSummary = memory.conversationSummary
        let profileName = profile.name
        let memoryID = memory.id
        let runtime = env.runtime

        memoryTask = Task { @MainActor in
            let fold = {
                await CoachMemoryService.consolidate(currentNotes: currentNotes,
                                                     currentSummary: currentSummary,
                                                     olderMessages: snapshots,
                                                     profileName: profileName)
            }
            let result: CoachMemoryService.Result?
            if let runtime {
                result = await AIRuntime.$current.withValue(runtime) { await fold() }
            } else {
                result = await fold()
            }
            guard let result else { return }   // failed or no key: the mark stays put

            let target = (try? context.fetch(
                FetchDescriptor<CoachMemory>(predicate: #Predicate { $0.id == memoryID })
            ).first) ?? CoachMemory.fetchOrCreate(in: context, profile: profile)
            // Lost-update guard: the fold reasoned over a snapshot of the notes. If a tool or
            // a Settings edit wrote notes meanwhile, keep those and fold only the summary.
            if target.profileNotes == currentNotes {
                target.profileNotes = result.profileNotes
            } else {
                Diagnostics.shared.log("memory consolidation: notes changed mid-flight — keeping newer notes", .coach)
            }
            target.conversationSummary = result.conversationSummary
            // The mark only moves forward.
            target.summarizedThroughDate = max(target.summarizedThroughDate ?? newHighWater, newHighWater)
            target.updatedAt = self.env.now()
            self.save("memory fold")
        }
    }
}
