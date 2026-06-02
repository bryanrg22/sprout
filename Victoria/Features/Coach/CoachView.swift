import SwiftUI
import SwiftData

/// The AI coach chat — "Vita", a warm, supportive conversation grounded in the
/// user's real data (targets, today's intake, weight trend, streak) via `CoachContext`.
///
/// Persistence: every message — including the user's, the assistant's reply, and the
/// one-time welcome seed — is a `ChatMessage` in SwiftData, so the conversation
/// survives relaunch and the coach has scroll-back memory. We save after each mutation.
struct CoachView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context

    // Full conversation, oldest first.
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    // Context the coach reasons over. Sort doesn't matter for aggregation.
    @Query private var foods: [FoodEntry]
    @Query private var weights: [WeightEntry]

    @State private var draft: String = ""
    @State private var isSending = false
    @State private var showMissingKeyBanner = false
    @State private var errorBanner: String?
    @State private var sendTrigger = 0
    @State private var confettiTrigger = 0
    /// An in-flight tool request the coach proposed, awaiting the user's one-tap confirm.
    /// Held in transient @State (not SwiftData) because it carries the raw assistant
    /// `content` blocks needed to continue the API turn, and only matters mid-interaction.
    @State private var pendingTool: PendingTool?
    @FocusState private var inputFocused: Bool

    /// "Ask Vita about this": set when the user long-pressed a component on another screen.
    @Environment(AskVitaCenter.self) private var askVita: AskVitaCenter?
    /// The component we're currently explaining — shows a little mini-card atop the chat so
    /// Vita's answer is anchored to a *thing she can see*, not just text.
    @State private var aboutTopic: AskVitaTopic?

    private let quickPrompts = [
        "How's my week?",
        "Review today",
        "I'm feeling discouraged",
        "Is this enough protein?",
    ]

    /// Sliding-window cap on how many recent messages we send to the model verbatim per turn,
    /// so a long-running chat can never overflow the context window or balloon cost. The FULL
    /// transcript still lives on-device (she keeps her scroll-back), and her bio + live stats
    /// are injected separately by `CoachContext`, so trimming old chatter never loses who she
    /// is. Older messages that scroll past this window are NOT forgotten: they're folded into
    /// `CoachMemory` (durable notes + a rolling summary) by `CoachMemoryService` in the
    /// background, and that memory is re-injected into every turn — so continuity survives.
    /// Because that long-term layer now backs us, the verbatim window can be tighter (16) than
    /// the old 24, keeping cost/latency down without losing the thread.
    private static let maxHistoryMessages = 16

    private var coachName: String { profile.coachName.isEmpty ? "Vita" : profile.coachName }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if showMissingKeyBanner {
                        missingKeyBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let errorBanner {
                        inlineBanner(text: errorBanner,
                                     tint: Theme.warning,
                                     systemImage: "exclamationmark.bubble.fill")
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // The little "About this" mini-card when the user asked about a component.
                    if let aboutTopic {
                        AskVitaContextCard(topic: aboutTopic) {
                            withAnimation { self.aboutTopic = nil }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    conversation

                    inputArea
                }

                // Celebrate a confirmed positive change (a kind little reward).
                ConfettiBurst(trigger: confettiTrigger)
                    .allowsHitTesting(false)
            }
            .navigationTitle(coachName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { navTitle }
            }
        }
        .tint(Theme.brand)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showMissingKeyBanner)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: errorBanner)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: aboutTopic)
        .onAppear(perform: seedWelcomeIfNeeded)
        // Pick up an "Ask Vita about this" request — on appear (if set before we showed) and
        // whenever it changes (the common case: a long-press flips us to this tab).
        .onAppear { if let t = askVita?.pendingTopic { handleAskVita(t) } }
        .onChange(of: askVita?.pendingTopic) { _, topic in
            if let topic { handleAskVita(topic) }
        }
    }

    /// Consume an "Ask Vita about this" topic: show its mini-card atop the chat, then ask the
    /// (self-contained) question on the user's behalf so Vita explains it right away.
    private func handleAskVita(_ topic: AskVitaTopic) {
        withAnimation { aboutTopic = topic }
        askVita?.pendingTopic = nil
        guard !isSending else { return }
        send(text: topic.question)
    }

    // MARK: - Nav title (avatar + name)

    private var navTitle: some View {
        HStack(spacing: Theme.Space.xs) {
            CoachAvatar(size: 26)
            Text(coachName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chat with \(coachName)")
    }

    // MARK: - Conversation list

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        MessageRow(message: message,
                                   coachName: coachName,
                                   showsTimestamp: showsTimestamp(at: index))
                            .id(message.id)
                    }
                    if isSending {
                        TypingIndicator(coachName: coachName)
                            .id(Self.typingID)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // The one-tap confirm card sits inline at the bottom of the chat,
                    // beside the coach avatar, like a proposal from Vita herself.
                    if let pending = pendingTool {
                        ToolConfirmCard(coachName: coachName,
                                        summary: pending.request.confirmSummary,
                                        onYes: confirmPendingTool,
                                        onNo: declinePendingTool)
                            .id(Self.confirmID)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: messages.count)
            .animation(.easeInOut(duration: 0.2), value: isSending)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: pendingTool != nil)
            .onChange(of: messages.count) { scrollToBottom(proxy) }
            .onChange(of: isSending) { scrollToBottom(proxy) }
            .onChange(of: pendingTool != nil) { scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    private static let typingID = "typing-indicator"
    private static let confirmID = "tool-confirm-card"

    /// Show a timestamp above the first message and whenever there's a meaningful gap
    /// (>5 min) from the previous message — classic native messaging grouping.
    private func showsTimestamp(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = messages[index].createdAt
        let previous = messages[index - 1].createdAt
        return current.timeIntervalSince(previous) > 5 * 60
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable
        if pendingTool != nil {
            target = AnyHashable(Self.confirmID)
        } else if isSending {
            target = AnyHashable(Self.typingID)
        } else {
            target = messages.last.map { AnyHashable($0.id) } ?? AnyHashable(Self.typingID)
        }
        let scroll = { proxy.scrollTo(target, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { scroll() }
        } else {
            scroll()
        }
    }

    // MARK: - Input area (quick chips + text field + send)

    private var inputArea: some View {
        VStack(spacing: Theme.Space.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(quickPrompts, id: \.self) { prompt in
                        QuickPromptChip(text: prompt) { send(text: prompt) }
                            .disabled(isSending || pendingTool != nil)
                            .opacity(isSending || pendingTool != nil ? 0.5 : 1)
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, 2)
            }

            HStack(alignment: .bottom, spacing: Theme.Space.sm) {
                TextField("Message \(coachName)…", text: $draft, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.brand)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 11)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.cardRaised)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        inputFocused ? Theme.brand.opacity(0.45)
                                                     : Color.white.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .submitLabel(.send)
                    .onSubmit { send(text: draft) }
                    .animation(.easeOut(duration: 0.2), value: inputFocused)

                Button {
                    send(text: draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(canSend ? Theme.background : Theme.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(
                            Group {
                                if canSend {
                                    Circle().fill(Theme.brandGradient)
                                } else {
                                    Circle().fill(Theme.cardRaised)
                                }
                            }
                        )
                        .shadow(color: canSend ? Theme.brand.opacity(0.35) : .clear,
                                radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .scaleEffect(canSend ? 1 : 0.92)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.bottom, Theme.Space.sm)
        }
        .padding(.top, Theme.Space.sm)
        .background(
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Divider()
                    .overlay(Theme.divider)
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .sensoryFeedback(.impact(weight: .light), trigger: sendTrigger)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Sending

    private func send(text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        // Fire haptic feedback for the primary action.
        sendTrigger += 1

        // Clear any stale error/banner and the draft. Resetting the missing-key banner
        // here is essential: a fresh send re-creates AnthropicClient(), which re-reads the
        // Keychain — so if the user has since saved a key in Settings, this attempt should
        // try again rather than stay stuck on the old "add your key" state.
        errorBanner = nil
        showMissingKeyBanner = false
        // A brand-new message supersedes any unanswered tool proposal.
        pendingTool = nil
        if text == draft.trimmingCharacters(in: .whitespacesAndNewlines) { draft = "" }
        inputFocused = false

        // Insert the user's message and persist immediately so it shows even if the
        // network call fails.
        let userMessage = ChatMessage(role: "user", content: text)
        context.insert(userMessage)
        try? context.save()

        // Build the history from everything *except* the canned welcome seed. We map to
        // the client's `Msg` (content is a plain String here).
        // Recent sliding window only (full transcript stays on-device for scroll-back).
        var recent = Array(messages.filter { !$0.isSystemSeed }.suffix(Self.maxHistoryMessages))
        // The Messages API requires the conversation to start on a user turn.
        while let first = recent.first, first.roleRaw != "user" { recent.removeFirst() }
        let history: [AnthropicClient.Msg] = recent
            .map { AnthropicClient.Msg(role: $0.roleRaw, content: $0.content) }

        // Snapshot the system prompt + tool schemas now (on the main actor, off SwiftData).
        // `coachMemory()` reads/creates the single memory row; `CoachContext.system` folds its
        // strings into the prompt synchronously here, so the @Model never crosses to the Task.
        let system = CoachContext.system(profile: profile, foods: foods, weights: weights,
                                         memory: coachMemory())
        let tools = CoachTools.schemas(for: profile)

        isSending = true
        Task {
            do {
                let client = try AnthropicClient()
                let turn = try await client.chatWithTools(system: system, messages: history, tools: tools)
                await MainActor.run { handle(turn: turn, history: history) }
            } catch AIConfig.AIError.missingKey {
                await MainActor.run {
                    showMissingKeyBanner = true
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorBanner = friendlyError(error)
                    isSending = false
                }
            }
        }
    }

    // MARK: - Tool-use handling

    /// Process an assistant turn that may include text and/or a tool request.
    @MainActor
    private func handle(turn: AnthropicClient.ChatTurn, history: [AnthropicClient.Msg]) {
        // Persist any prose the assistant included so the conversation reads naturally,
        // whether or not a tool was also requested.
        let trimmed = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            context.insert(ChatMessage(role: "assistant", content: trimmed))
            try? context.save()
        }

        guard let toolUse = turn.toolUse else {
            // Plain conversational reply. If there was somehow no text either, show a
            // gentle fallback rather than leaving the turn empty.
            if trimmed.isEmpty {
                context.insert(ChatMessage(role: "assistant", content: "I'm here 💚"))
                try? context.save()
            }
            isSending = false
            // The user's reply is already on screen. Now, off their turn, fold any messages
            // that have scrolled past the verbatim window into long-term memory. Every final
            // reply (plain, post-confirm, post-decline, and invalid-recovery) lands here, so
            // this one call site covers them all.
            consolidateMemoryIfNeeded()
            return
        }

        // Validate the request against the profile *before* offering it. An invalid
        // request (out-of-range, bad pace) is bounced straight back to the model as a
        // tool_result error so it can recover in-conversation — the user never sees a
        // confirm for something we can't safely do.
        switch CoachTools.parse(name: toolUse.name, input: toolUse.input, profile: profile) {
        case .invalid(let reason):
            continueTurn(history: history,
                         assistantContent: turn.assistantContent,
                         toolUseId: toolUse.id,
                         resultText: reason,
                         isError: true)

        case .ok(let request):
            // DO NOT apply yet. Surface a one-tap confirm; apply happens only on "Yes".
            pendingTool = PendingTool(request: request,
                                      toolUseId: toolUse.id,
                                      assistantContent: turn.assistantContent,
                                      history: history)
            isSending = false
        }
    }

    /// User tapped "Yes": apply the change, then tell the coach so it can reply warmly.
    @MainActor
    private func confirmPendingTool() {
        guard let pending = pendingTool else { return }
        pendingTool = nil
        sendTrigger += 1

        let resultText = CoachTools.apply(pending.request, to: profile, context: context)
        confettiTrigger += 1   // a small celebration for taking a positive step

        continueTurn(history: pending.history,
                     assistantContent: pending.assistantContent,
                     toolUseId: pending.toolUseId,
                     resultText: "Applied. \(resultText)",
                     isError: false)
    }

    /// User tapped "Not now": tell the coach the change was declined so it bows out kindly.
    @MainActor
    private func declinePendingTool() {
        guard let pending = pendingTool else { return }
        pendingTool = nil
        sendTrigger += 1

        continueTurn(history: pending.history,
                     assistantContent: pending.assistantContent,
                     toolUseId: pending.toolUseId,
                     resultText: "The user decided not to make this change right now. "
                               + "Nothing was changed. Respond warmly and without any pressure.",
                     isError: false)
    }

    /// Send the assistant turn + a tool_result back to continue the conversation, then
    /// persist the coach's follow-up reply. Used for confirm, decline, and invalid paths.
    @MainActor
    private func continueTurn(history: [AnthropicClient.Msg],
                              assistantContent: [[String: Any]],
                              toolUseId: String,
                              resultText: String,
                              isError: Bool) {
        // history already ends with the user's triggering message; append the assistant's
        // tool_use turn, then our tool_result, exactly as the Messages API requires.
        let continued = history
            + [AnthropicClient.assistantMessage(content: assistantContent),
               AnthropicClient.toolResultMessage(toolUseId: toolUseId,
                                                  resultText: resultText,
                                                  isError: isError)]

        let system = CoachContext.system(profile: profile, foods: foods, weights: weights,
                                         memory: coachMemory())
        let tools = CoachTools.schemas(for: profile)

        isSending = true
        Task {
            do {
                let client = try AnthropicClient()
                // Keep tools available so a follow-up tool call is still possible, but the
                // common case is a plain warm reply.
                let turn = try await client.chatWithTools(system: system, messages: continued, tools: tools)
                await MainActor.run { handle(turn: turn, history: continued) }
            } catch AIConfig.AIError.missingKey {
                await MainActor.run {
                    showMissingKeyBanner = true
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorBanner = friendlyError(error)
                    isSending = false
                }
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        // Network / API hiccups shouldn't read like a stack trace.
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "I can't reach the internet right now — mind checking your connection? 💚"
        }
        return "Something went wrong on my end. Let's try that again in a moment 💚"
    }

    // MARK: - Long-term memory

    /// The single `CoachMemory` row, fetched-or-created (seeded from her onboarding note on
    /// first creation). Cheap and idempotent — fetches an existing row, only inserting one if
    /// none exists yet — so it's safe to call on every turn.
    private func coachMemory() -> CoachMemory {
        CoachMemory.fetchOrCreate(in: context, profile: profile)
    }

    /// If any non-seed messages have scrolled past the verbatim window AND haven't been folded
    /// into memory yet, consolidate them in the BACKGROUND (one cheap LLM call), then persist
    /// the updated notes/summary and advance the high-water mark.
    ///
    /// This is strictly off the user's turn: it runs only after the visible reply has already
    /// landed and `isSending` is back to false, and the network call happens inside a detached
    /// `Task` so it never blocks or delays anything the user sees. On any failure (no key,
    /// network, bad output) `consolidate` returns nil and we leave memory — and the high-water
    /// mark — untouched, so the same batch is simply retried after the next reply.
    @MainActor
    private func consolidateMemoryIfNeeded() {
        let memory = coachMemory()

        // Pure selection: which older, not-yet-folded messages should we summarize?
        let toFold = CoachMemoryService.messagesToConsolidate(
            messages: messages,
            windowSize: Self.maxHistoryMessages,
            summarizedThrough: memory.summarizedThroughDate
        )
        guard !toFold.isEmpty else { return }

        // Snapshot everything the background call needs OFF SwiftData, on the main actor, so no
        // @Model object crosses an actor boundary.
        let snapshots = toFold.map {
            CoachMemoryService.MessageSnapshot(role: $0.roleRaw,
                                               content: $0.content,
                                               createdAt: $0.createdAt)
        }
        guard let newHighWater = toFold.map(\.createdAt).max() else { return }
        let currentNotes = memory.profileNotes
        let currentSummary = memory.conversationSummary
        let profileName = profile.name
        let memoryID = memory.id   // re-fetch by id on completion to avoid capturing the @Model

        Task { @MainActor in
            guard let result = await CoachMemoryService.consolidate(
                currentNotes: currentNotes,
                currentSummary: currentSummary,
                olderMessages: snapshots,
                profileName: profileName
            ) else { return }   // no-op on failure / no key — high-water mark stays put

            // Re-fetch the row fresh (we're back on the main actor after an await) and write.
            let target = (try? context.fetch(
                FetchDescriptor<CoachMemory>(predicate: #Predicate { $0.id == memoryID })
            ).first) ?? coachMemory()
            target.profileNotes = result.profileNotes
            target.conversationSummary = result.conversationSummary
            // Only advance the high-water mark forward, never backward (a concurrent earlier
            // pass could in principle have folded further already).
            if let existing = target.summarizedThroughDate {
                target.summarizedThroughDate = max(existing, newHighWater)
            } else {
                target.summarizedThroughDate = newHighWater
            }
            target.updatedAt = .now
            try? context.save()
        }
    }

    // MARK: - Welcome seed

    private func seedWelcomeIfNeeded() {
        guard messages.isEmpty else { return }
        let name = profile.name.isEmpty ? "there" : profile.name
        // Direction-aware so Bryan (gain) isn't greeted as a "weight-loss buddy".
        let role: String
        switch profile.pace.direction {
        case .lose:     role = "weight-loss buddy"
        case .gain:     role = "muscle-building buddy"
        case .maintain: role = "healthy-habits buddy"
        }
        let welcome = """
        Hi \(name)! I'm \(coachName), your \(role) 💚 \
        I'm here to cheer you on, talk through the hard days, and help you make sense of your progress. \
        Ask me anything, or tap a prompt below to get started.
        """
        let seed = ChatMessage(role: "assistant", content: welcome, isSystemSeed: true)
        context.insert(seed)
        try? context.save()
    }

    // MARK: - Banners

    private var missingKeyBanner: some View {
        inlineBanner(text: "I'm ready to chat once you add your AI key in More → AI 💚",
                     tint: Theme.brand,
                     systemImage: "key.fill")
    }

    private func inlineBanner(text: String, tint: Color, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Space.md)
        .padding(.top, Theme.Space.sm)
    }
}

// MARK: - Coach avatar (the Sprout mascot — Vita's real face)

private struct CoachAvatar: View {
    var size: CGFloat = 30

    var body: some View {
        // Vita's identity is the Sprout seedling (matches the app name + icon),
        // not a generic glyph. Sparkle off for the small in-chat instances.
        VitaAvatar(size: size, showsSparkle: false)
    }
}

// MARK: - Message row (avatar + bubble + grouped timestamp)

private struct MessageRow: View {
    let message: ChatMessage
    let coachName: String
    let showsTimestamp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if showsTimestamp {
                Text(timestamp)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Space.xs)
                    .padding(.bottom, 2)
            }

            HStack(alignment: .bottom, spacing: Theme.Space.xs) {
                if message.isUser {
                    Spacer(minLength: 44)
                    bubble
                } else {
                    CoachAvatar(size: 28)
                    bubble
                    Spacer(minLength: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bubble: some View {
        Text(Self.styled(message.content))
            .font(.body)
            .foregroundStyle(message.isUser ? Theme.background : Theme.textPrimary)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 11)
            .background(bubbleBackground)
            .clipShape(BubbleShape(isUser: message.isUser))
            .overlay(
                BubbleShape(isUser: message.isUser)
                    .strokeBorder(message.isUser ? Color.clear : Color.white.opacity(0.06),
                                  lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(message.isUser ? 0.2 : 0.25),
                    radius: 6, x: 0, y: 3)
            .textSelection(.enabled)
            .accessibilityLabel(message.isUser ? "You said" : "\(coachName) said")
            .accessibilityValue(message.content)
    }

    @ViewBuilder private var bubbleBackground: some View {
        if message.isUser {
            Theme.brandGradient
        } else {
            Theme.card
        }
    }

    /// Render Vita's inline markdown (**bold**, *italic*) as real styling instead of showing
    /// the literal asterisks, while preserving the message's whitespace. Plain-text fallback.
    private static func styled(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    private var timestamp: String {
        Self.formatter.localizedString(for: message.createdAt, relativeTo: .now).capitalizedFirst
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// Asymmetric rounded bubble: the tail corner (bottom-trailing for the user,
/// bottom-leading for the coach) is tightened for a classic chat silhouette.
private struct BubbleShape: InsettableShape {
    let isUser: Bool
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let big: CGFloat = Theme.Radius.lg
        let small: CGFloat = 6
        let corners = UnevenRoundedRectangle(
            topLeadingRadius: big,
            bottomLeadingRadius: isUser ? big : small,
            bottomTrailingRadius: isUser ? small : big,
            topTrailingRadius: big,
            style: .continuous
        )
        return corners.path(in: inset)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Quick prompt chip

private struct QuickPromptChip: View {
    let text: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.brand)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 8)
                .background(Theme.brandSoft, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

// MARK: - Typing indicator (animated three dots in a coach bubble)

private struct TypingIndicator: View {
    let coachName: String
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xs) {
            CoachAvatar(size: 28)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.textSecondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1 : 0.55)
                        .opacity(animating ? 1 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 14)
            .background(Theme.card)
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            .accessibilityLabel("\(coachName) is typing")

            Spacer(minLength: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
    }
}

// MARK: - Pending tool proposal (awaiting one-tap confirm)

/// A validated tool request the coach proposed, plus the exact API state needed to
/// continue the turn once the user answers. Transient (lives in @State only) — it
/// carries the raw assistant `content` blocks (non-Codable) and is only meaningful
/// during the brief confirm interaction.
private struct PendingTool {
    let request: CoachTools.ParsedRequest
    let toolUseId: String
    let assistantContent: [[String: Any]]
    /// The conversation history up to and including the user's triggering message —
    /// what we replay (plus the assistant turn + tool_result) to continue.
    let history: [AnthropicClient.Msg]
}

// MARK: - Inline tool-confirm card ("Want me to set your step goal to 12,000?")

/// A warm, on-brand confirmation that appears inline like a message from Vita. Nothing
/// changes until the user taps "Yes" — this is the single human gate in front of every
/// setting change the coach can make.
private struct ToolConfirmCard: View {
    let coachName: String
    let summary: String          // e.g. "set your daily step goal to 12,000 steps"
    let onYes: () -> Void
    let onNo: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xs) {
            CoachAvatar(size: 28)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Want me to \(summary)?")
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Space.sm) {
                    Button(action: onYes) {
                        Text("Yes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, Theme.Space.lg)
                            .padding(.vertical, 9)
                            .background(Theme.brandGradient, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.jelly)
                    .accessibilityLabel("Yes, \(summary)")

                    Button(action: onNo) {
                        Text("Not now")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, 9)
                            .background(Theme.cardRaised, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .bouncyPress()
                    .accessibilityLabel("Not now")
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 12)
            .background(Theme.card)
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .strokeBorder(Theme.brand.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popIn(appeared)
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
    }
}
