import SwiftUI
import SwiftData
import UIKit

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
    // So Vita's context can see her training + hydration too, not just food + weight.
    @Query private var workouts: [WorkoutEntry]
    @Query private var water: [WaterEntry]

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
    /// A transient "X done · Undo" banner shown after an auto-applied quick log.
    @State private var undoToast: UndoToast?
    @State private var undoTask: Task<Void, Never>?
    /// A photo the user has attached to the next message (downscaled). Shows as a preview
    /// over the input until sent; Vita receives it as an image block so she can SEE it.
    @State private var attachedImage: UIImage?
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @FocusState private var inputFocused: Bool
    /// The id of the assistant message currently "typing out" (typewriter reveal). Only the
    /// freshest reply animates; everything in history renders instantly. Cleared when it finishes.
    @State private var streamingMessageID: UUID?

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
    /// Max chained tool round-trips per user message (auto-apply + invalid retries). Past this
    /// we stop advertising tools so the model must finalize — bounds cost/latency/runaway.
    private static let maxToolDepth = 5

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
                }
                // Pin the input bar as a bottom safe-area INSET rather than a VStack child.
                // This is the fix for the watchdog freeze (0x8BADF00D) on send: in a plain
                // VStack the keyboard SHRINKS the whole stack, which resizes the message
                // ScrollView's frame, which fights the auto-scroll into a non-converging
                // layout loop that pins the main thread until iOS kills the app. As a
                // safe-area inset, the keyboard adjusts the scroll view's CONTENT INSET
                // smoothly instead of resizing its frame — no loop. (Diagnosed from a field
                // log: `coach send` → 17s → process relaunch, no reply, no error = a hang.)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if let toast = undoToast {
                            UndoBanner(summary: toast.summary, onUndo: performUndo)
                                .padding(.horizontal, Theme.Space.md)
                                .padding(.bottom, Theme.Space.xs)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        inputArea
                    }
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
                                   showsTimestamp: showsTimestamp(at: index),
                                   isStreaming: message.id == streamingMessageID,
                                   onStreamComplete: {
                                       if streamingMessageID == message.id { streamingMessageID = nil }
                                       scrollToBottom(proxy)
                                   })
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
            // NOTE: broad `.animation(_:value:)` on the ScrollView was removed — it animated
            // EVERY change in the scroll view (including the keyboard-avoidance inset) and,
            // combined with the auto-scroll on send, drove a non-converging view-graph update
            // (the watchdog freeze). Insert/transition animations are handled locally instead.
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
        // Defer to the next runloop tick so the scroll never runs *inside* the in-progress
        // SwiftUI transaction (the message insert + keyboard dismiss that fire together on
        // send). Scrolling mid-transaction recurses the view-graph update and pins the main
        // thread at 100% CPU → the watchdog kill (0x8BADF00D) the user hit on send.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .bottom) }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
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

            if let img = attachedImage {
                attachmentPreview(img)
            }

            HStack(alignment: .bottom, spacing: Theme.Space.sm) {
                Button { showPhotoOptions = true } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.cardRaised))
                }
                .buttonStyle(.plain)
                .disabled(isSending || pendingTool != nil)
                .opacity(isSending || pendingTool != nil ? 0.5 : 1)
                .accessibilityLabel("Attach a photo")

                TextField("Message \(coachName)…", text: $draft, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.brand)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 11)
                    // A rounded RECTANGLE, not a Capsule: a capsule's big semicircular end-caps
                    // crowd and clip text once the field wraps to a second line (the "letters
                    // flow out of the box" bug). A continuous 20pt corner still reads as a pill
                    // at one line but grows into a clean rounded box as the text wraps.
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.cardRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
        .confirmationDialog("Add a photo", isPresented: $showPhotoOptions, titleVisibility: .visible) {
            if ImagePicker.cameraAvailable {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose from Library") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { attach($0) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            PhotoLibraryPicker(selectionLimit: 1) { imgs in imgs.first.map(attach) }
                .ignoresSafeArea()
        }
    }

    /// A thumbnail of the pending photo, with an ✕ to remove it, shown above the input.
    private func attachmentPreview(_ image: UIImage) -> some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { attachedImage = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 7, y: -7)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.md)
        .transition(.opacity)
    }

    private var canSend: Bool {
        !isSending
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil)
    }

    /// Store a picked photo (downscaled) as the pending attachment shown over the input.
    private func attach(_ image: UIImage) {
        attachedImage = image.downscaled(maxEdge: 768)
    }

    // MARK: - Sending

    private func send(text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        // JPEG of any attached (already-downscaled) photo. A message may be image-only.
        let imageData = attachedImage?.jpegData(compressionQuality: 0.6)
        guard (!text.isEmpty || imageData != nil), !isSending else { return }

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
        streamingMessageID = nil   // snap any in-progress reveal to full before the next turn
        if text == draft.trimmingCharacters(in: .whitespacesAndNewlines) { draft = "" }
        // Keep the keyboard up after send (chat-standard, like Messages). Dismissing it here —
        // while the message inserts AND the list auto-scrolls — was the freeze trigger: the
        // keyboard-avoidance safe-area animation fought the scroll/relayout into a runaway
        // view-graph update (watchdog 0x8BADF00D). The quick-prompt + Ask-Vita paths never
        // raise the keyboard, which is exactly why ONLY typing-then-send froze.

        // Insert the user's message and persist immediately so it shows even if the
        // network call fails.
        let userMessage = ChatMessage(role: "user", content: text, imageData: imageData)
        context.insert(userMessage)
        try? context.save()
        attachedImage = nil   // consumed into the message

        // Build the history from everything *except* the canned welcome seed. We map to
        // the client's `Msg` (content is a plain String here).
        // Recent sliding window only (full transcript stays on-device for scroll-back).
        var recent = Array(messages.filter { !$0.isSystemSeed && !$0.isDecision }.suffix(Self.maxHistoryMessages))
        // The Messages API requires the conversation to start on a user turn.
        while let first = recent.first, first.roleRaw != "user" { recent.removeFirst() }
        // A message with a photo becomes a multimodal content array (image + optional text)
        // so Vita can actually SEE it; text-only messages stay plain strings.
        let history: [AnthropicClient.Msg] = recent.map { m in
            if let data = m.imageData {
                var blocks: [[String: Any]] = [AnthropicClient.imageBlock(data)]
                if !m.content.isEmpty { blocks.append(AnthropicClient.textBlock(m.content)) }
                return AnthropicClient.Msg(role: m.roleRaw, content: blocks)
            }
            return AnthropicClient.Msg(role: m.roleRaw, content: m.content)
        }

        // Snapshot the system prompt + tool schemas now (on the main actor, off SwiftData).
        // `coachMemory()` reads/creates the single memory row; `CoachContext.system` folds its
        // strings into the prompt synchronously here, so the @Model never crosses to the Task.
        let system = CoachContext.system(profile: profile, foods: foods, weights: weights,
                                         workouts: workouts, water: water,
                                         memory: coachMemory(), plan: CoachPlan.current(in: context))
        let tools = CoachTools.schemas(for: profile)

        Diagnostics.shared.log("coach send: \(text.count) chars, \(history.count) history msgs", .coach)
        isSending = true
        Task {
            do {
                let client = try AnthropicClient()
                let turn = try await client.chatWithTools(system: system, messages: history, tools: tools)
                Diagnostics.shared.log("coach reply ok: \(turn.text.count) chars, tool=\(turn.toolUse?.name ?? "none")", .coach)
                await MainActor.run { handle(turn: turn, history: history) }
            } catch AIConfig.AIError.missingKey {
                await MainActor.run {
                    Diagnostics.shared.log("coach: missing API key", .coach)
                    showMissingKeyBanner = true
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    Diagnostics.shared.log("coach error: \(error)", .error)
                    errorBanner = friendlyError(error)
                    isSending = false
                }
            }
        }
    }

    // MARK: - Tool-use handling

    /// Process an assistant turn that may include text and/or a tool request.
    @MainActor
    private func handle(turn: AnthropicClient.ChatTurn, history: [AnthropicClient.Msg], depth: Int = 0) {
        Diagnostics.shared.log("coach: rendering reply (\(turn.text.count) chars, tool=\(turn.toolUse != nil))", .coach)
        // Persist any prose the assistant included so the conversation reads naturally,
        // whether or not a tool was also requested.
        let trimmed = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let reply = ChatMessage(role: "assistant", content: trimmed)
            context.insert(reply)
            try? context.save()
            streamingMessageID = reply.id   // type this freshest reply out, word by word
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
        // `todaysFoods` lets the edit/delete tools resolve "the latte" to a specific row;
        // it's harmless for the settings tools (which ignore it).
        switch CoachTools.parse(name: toolUse.name, input: toolUse.input, profile: profile,
                                todaysFoods: CoachContext.todaysFoods(foods)) {
        case .invalid(let reason):
            continueTurn(history: history,
                         assistantContent: turn.assistantContent,
                         toolUseId: toolUse.id,
                         resultText: reason,
                         isError: true,
                         depth: depth + 1)

        case .ok(let request) where request.requiresConfirm:
            // Destructive or goal-changing → DO NOT apply yet. Surface a one-tap confirm.
            pendingTool = PendingTool(request: request,
                                      toolUseId: toolUse.id,
                                      assistantContent: turn.assistantContent,
                                      history: history)
            isSending = false

        case .ok(let request):
            // A quick, reversible log → apply immediately and offer an Undo, then tell the
            // model so it replies warmly. The depth cap bounds a chain ("log my breakfast").
            let applied = CoachTools.applyReturningUndo(request, to: profile, context: context)
            if let undo = applied.undo {
                showUndoToast(summary: request.confirmSummary, undo: undo)
            }
            continueTurn(history: history,
                         assistantContent: turn.assistantContent,
                         toolUseId: toolUse.id,
                         resultText: "Applied. \(applied.message)",
                         isError: false,
                         depth: depth + 1)
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

        // Leave the decision in the transcript (grayed card, "Yes" highlighted) before the reply.
        recordDecision(summary: pending.request.confirmSummary, accepted: true)

        continueTurn(history: pending.history,
                     assistantContent: pending.assistantContent,
                     toolUseId: pending.toolUseId,
                     resultText: "Applied. \(resultText)",
                     isError: false,
                     depth: 0)
    }

    /// User tapped "Not now": tell the coach the change was declined so it bows out kindly.
    @MainActor
    private func declinePendingTool() {
        guard let pending = pendingTool else { return }
        pendingTool = nil
        sendTrigger += 1

        // Leave the decision in the transcript (grayed card, "Not now" highlighted).
        recordDecision(summary: pending.request.confirmSummary, accepted: false)

        continueTurn(history: pending.history,
                     assistantContent: pending.assistantContent,
                     toolUseId: pending.toolUseId,
                     resultText: "The user decided not to make this change right now. "
                               + "Nothing was changed. Respond warmly and without any pressure.",
                     isError: false,
                     depth: 0)
    }

    /// Persist a settled tool-confirm decision as a transcript row, so the confirm card stays in
    /// history (grayed, with the chosen option highlighted) instead of vanishing on tap. It's a
    /// UI-only marker: excluded from the API history we send and from long-term memory folding.
    @MainActor
    private func recordDecision(summary: String, accepted: Bool) {
        let marker = ChatMessage(role: "assistant", content: "",
                                 decisionSummary: summary, decisionAccepted: accepted)
        context.insert(marker)
        try? context.save()
    }

    /// Show the "done · Undo" banner for a just-applied quick log, auto-dismissing after a few
    /// seconds. A new toast replaces any prior one (we keep only the most recent action).
    @MainActor
    private func showUndoToast(summary: String, undo: @escaping @MainActor () -> Void) {
        undoTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            undoToast = UndoToast(summary: summary, undo: undo)
        }
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { undoToast = nil }
        }
    }

    /// Reverse the last auto-applied change and dismiss the banner.
    @MainActor
    private func performUndo() {
        undoTask?.cancel()
        undoToast?.undo()
        sendTrigger += 1   // a little haptic for the revert
        withAnimation(.easeOut(duration: 0.2)) { undoToast = nil }
    }

    /// Send the assistant turn + a tool_result back to continue the conversation, then
    /// persist the coach's follow-up reply. Used for confirm, decline, and invalid paths.
    @MainActor
    private func continueTurn(history: [AnthropicClient.Msg],
                              assistantContent: [[String: Any]],
                              toolUseId: String,
                              resultText: String,
                              isError: Bool,
                              depth: Int) {
        // history already ends with the user's triggering message; append the assistant's
        // tool_use turn, then our tool_result, exactly as the Messages API requires.
        let continued = history
            + [AnthropicClient.assistantMessage(content: assistantContent),
               AnthropicClient.toolResultMessage(toolUseId: toolUseId,
                                                  resultText: resultText,
                                                  isError: isError)]

        let system = CoachContext.system(profile: profile, foods: foods, weights: weights,
                                         workouts: workouts, water: water,
                                         memory: coachMemory(), plan: CoachPlan.current(in: context))
        // Once we've chained enough tools, stop offering them so the model must finalize.
        let tools = depth >= Self.maxToolDepth ? [] : CoachTools.schemas(for: profile)

        isSending = true
        Task {
            do {
                let client = try AnthropicClient()
                // Keep tools available so a follow-up tool call is still possible, but the
                // common case is a plain warm reply.
                let turn = try await client.chatWithTools(system: system, messages: continued, tools: tools)
                await MainActor.run { handle(turn: turn, history: continued, depth: depth) }
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
            messages: messages.filter { !$0.isDecision },   // UI-only decision rows never fold
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
        inlineBanner(text: missingKeyMessage,
                     tint: Theme.brand,
                     systemImage: "key.fill")
    }

    /// Vita runs on Claude (chatWithTools is Anthropic-only). If the user is on OpenAI or only
    /// has an OpenAI key saved, they HAVE added a key — so say specifically that Vita needs an
    /// Anthropic one, instead of the confusing generic "add your AI key".
    private var missingKeyMessage: String {
        if !KeychainStore.hasAPIKey(for: .anthropic)
            && (AIConfig.provider == .openai || KeychainStore.hasAPIKey(for: .openai)) {
            return "\(coachName) runs on Claude — add an Anthropic key in More → AI 💚"
        }
        return "I'm ready to chat once you add your AI key in More → AI 💚"
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
    /// True only for the freshest assistant reply, which types itself out; history renders instantly.
    var isStreaming: Bool = false
    var onStreamComplete: () -> Void = {}

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

            if message.isDecision {
                // A settled confirm decision, kept in the transcript as a grayed card with the
                // chosen option highlighted — history of what she decided, not a live prompt.
                DecidedConfirmCard(coachName: coachName,
                                   summary: message.decisionSummary ?? "",
                                   accepted: message.decisionAccepted ?? false)
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = message.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 280)
            }
            if !message.content.isEmpty {
                Group {
                    if message.isUser {
                        // Her own text — plain, on the brand gradient. Inline markup only.
                        Text(Self.styled(message.content))
                            .font(.body)
                            .foregroundStyle(Theme.background)
                    } else if isStreaming {
                        // The freshest reply types itself out word by word, then settles into the
                        // same markdown rendering as the rest.
                        TypewriterMarkdown(fullText: message.content,
                                           color: Theme.textPrimary,
                                           onComplete: onStreamComplete)
                    } else {
                        // Vita's replies render real markdown blocks (lists, headings, rules)
                        // instead of leaking literal `- ` / `##` / `---`.
                        MarkdownMessage(message.content, color: Theme.textPrimary)
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 11)
            }
        }
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
        .accessibilityValue(message.imageData != nil ? "\(message.content) (photo attached)" : message.content)
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

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.brand)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 8)
                .background(Theme.brandSoft, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1)
                )
        }
        // `.jelly` drives the press-squish from the ButtonStyle's own `isPressed`. The old
        // `.simultaneousGesture(DragGesture(minimumDistance: 0))` was the "can't scroll the
        // chips" bug: at distance 0 it claimed the touch instantly and starved the horizontal
        // ScrollView's pan. A ButtonStyle yields to the scroll, so the row scrolls again.
        .buttonStyle(.jelly)
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

/// A just-applied, reversible action: the human summary to show + the closure that undoes it.
private struct UndoToast {
    let summary: String
    let undo: @MainActor () -> Void
}

/// The transient "✓ {summary} · Undo" banner shown above the input after an auto-applied log.
private struct UndoBanner: View {
    let summary: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.positive)
            Text(capitalizedSummary)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Space.sm)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 11)
        .background(Theme.cardRaised, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.06)))
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
    }

    /// The action summary reads like "log Chicken bowl …"; show it sentence-cased.
    private var capitalizedSummary: String {
        guard let first = summary.first else { return summary }
        return first.uppercased() + summary.dropFirst()
    }
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

// MARK: - Decided confirm card (a settled proposal, kept in the transcript)

/// The history form of `ToolConfirmCard`. Once she taps Yes / Not now, the live card is replaced
/// by this — same silhouette, but grayed and non-interactive, with the option she chose lit up in
/// light green. The conversation keeps a visible record of what was decided instead of the card
/// just vanishing. Backed by a `ChatMessage` decision row, so it survives relaunch.
private struct DecidedConfirmCard: View {
    let coachName: String
    let summary: String
    let accepted: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xs) {
            CoachAvatar(size: 28)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Want me to \(summary)?")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Space.sm) {
                    decidedPill(title: "Yes", chosen: accepted)
                    decidedPill(title: "Not now", chosen: !accepted)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 12)
            .background(Theme.card.opacity(0.55))
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
            .opacity(0.9)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accepted ? "Accepted" : "Declined"): \(summary)")
    }

    /// One settled pill: the chosen option glows light green with a check; the other is dimmed.
    @ViewBuilder
    private func decidedPill(title: String, chosen: Bool) -> some View {
        HStack(spacing: 5) {
            if chosen {
                Image(systemName: "checkmark").font(.caption2.weight(.bold))
            }
            Text(title).font(.subheadline.weight(chosen ? .semibold : .medium))
        }
        .foregroundStyle(chosen ? Theme.positive : Theme.textSecondary.opacity(0.6))
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(chosen ? Theme.positive.opacity(0.16) : Theme.cardRaised.opacity(0.5))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chosen ? Theme.positive.opacity(0.5) : Color.white.opacity(0.05),
                              lineWidth: 1)
        )
    }
}
