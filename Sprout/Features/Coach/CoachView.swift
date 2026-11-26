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
    @Environment(\.scenePhase) private var scenePhase

    /// The turn logic: sending, the model calls, tools, confirm, undo, failures, memory.
    /// This view reads its state and forwards taps (see `CoachTurnEngine`).
    @State private var engine = CoachTurnEngine()
    /// The loaded part of the conversation: the newest page, plus earlier pages as the
    /// reader scrolls up (see `ChatTranscript`). There is no `@Query` over every message.
    @State private var transcript = ChatTranscript()

    @State private var draft: String = ""
    /// A photo the user has attached to the next message (downscaled). Shows as a preview
    /// over the input until sent; Vita receives it as an image block so she can SEE it.
    @State private var attachedImage: UIImage?
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @FocusState private var inputFocused: Bool
    /// A passage picked with "Ask about this", shown above the field and sent with the next message.
    @State private var quote: String?
    /// The reply whose action row was revealed by a tap (the newest reply always shows its row).
    @State private var actionsRevealedFor: UUID?
    /// The message a Delete was asked for, until the user confirms.
    @State private var pendingDelete: UUID?
    @State private var showDeleteDialog = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// Scroll offsets, kept out of view state so reading them never re-renders the chat.
    @State private var scrollBox = ChatScrollBox()

    /// "Ask Vita about this": set when the user long-pressed a component on another screen.
    @Environment(AskVitaCenter.self) private var askVita: AskVitaCenter?
    /// The component we're currently explaining — shows a little mini-card atop the chat so
    /// Vita's answer is anchored to a *thing she can see*, not just text.
    @State private var aboutTopic: AskVitaTopic?

    /// The quick-prompt chips shown above the input. Starts as the synchronous, no-network
    /// fixed list (constants + generic extras) so the row is NEVER empty and there's no flash;
    /// a `.task` then swaps in a personalized set (the constants always lead) that refreshes
    /// every few days. See `CoachPromptService`. The hide-while-typing gating below is unchanged.
    @State private var quickPrompts: [String] = CoachPromptService.fixedPrompts()

    /// Drives the personalized-prompt `.task`: changes per user and every few days (the cache
    /// bucket rolling over), so the chips reload — served from cache or regenerated — with no timer.
    private var promptPeriodKey: String { CoachPromptService.periodKey(userId: profile.id) }

    private var coachName: String { profile.coachName.isEmpty ? "Vita" : profile.coachName }

    init(profile: UserProfile) {
        self.profile = profile
        #if DEBUG
        ChatLoadProbe.markViewInit()
        #endif
    }

    var body: some View {
        #if DEBUG
        let _ = ChatLoadProbe.markFirstBody()
        #endif
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
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
                        if let toast = engine.undoToast {
                            UndoBanner(summary: toast.summary, onUndo: engine.performUndo)
                                .padding(.horizontal, Theme.Space.md)
                                .padding(.bottom, Theme.Space.xs)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        inputArea
                    }
                }

                // Celebrate a confirmed positive change (a kind little reward).
                ConfettiBurst(trigger: engine.confettiTick)
                    .allowsHitTesting(false)
            }
            .navigationTitle(coachName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { navTitle }
            }
            // The conversation is a flipped scroll view, so the bar cannot tell from its
            // offset when content is under it (iOS 18), and iOS 26's edge blur is hidden for
            // it (`chatEdgeEffectsHidden`): the bar always has its own background.
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .surfaceContent()   // Home | Gym: hidden from VoiceOver when not showing (U-1)
        }
        .tint(Theme.brand)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: aboutTopic)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: engine.undoToast?.id)
        // Pick up an "Ask Vita about this" request — on appear (if set before we showed) and
        // whenever it changes (the common case: a long-press flips us to this tab).
        .onAppear {
            start()
            if let t = askVita?.pendingTopic { handleAskVita(t) }
            takePendingQuote()
        }
        .onChange(of: askVita?.pendingTopic) { _, topic in
            if let topic { handleAskVita(topic) }
        }
        // A topic that arrived while a reply was on its way is asked once that turn settles.
        .onChange(of: engine.isSending) { _, sending in
            if !sending, let topic = askVita?.pendingTopic { handleAskVita(topic) }
        }
        // "Ask about this" on a passage or a whole message: the quote goes above the field.
        .onChange(of: askVita?.pendingQuote) { _, _ in takePendingQuote() }
        // Another device may have added messages while the app was away.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, engine.isAttached, !engine.isSending { transcript.reload() }
        }
        // Swap the fixed starter chips for a personalized set, refreshed every few days. Keyed on
        // user + the cache bucket so it re-runs when the bucket rolls over (served from cache, or
        // one cheap call to regenerate). Never empties the row: on no-key / any failure the service
        // returns the same fixed list `quickPrompts` already holds, so this only ever improves it.
        .task(id: promptPeriodKey) { await loadQuickPrompts() }
        // The id travels with the dialog (`presenting:`), so the button still has it after
        // the dialog has dismissed itself.
        .confirmationDialog("Delete this message?", isPresented: $showDeleteDialog,
                            titleVisibility: .visible, presenting: pendingDelete) { id in
            Button("Delete", role: .destructive) { engine.delete(messageID: id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is removed from this conversation for good.")
        }
    }

    /// Wire the engine and the transcript to the store (the model context comes from the
    /// environment, so this cannot happen in `init`), seed the welcome into an empty
    /// conversation, and say so if the newest message never got its reply.
    private func start() {
        guard !engine.isAttached else { return }
        engine.attach(context: context, profile: profile)
        #if DEBUG
        ChatDebug.configure(engine)
        #endif
        transcript.attach(context: context)
        engine.onTranscriptChange = { [transcript] change in
            switch change {
            case .added: transcript.appendNewer()
            case .removed(let ids): transcript.remove(ids: ids)
            }
        }
        engine.seedWelcomeIfNeeded()
        engine.noteUnansweredMessageIfAny()
        #if DEBUG
        ChatDebug.runScript(engine: engine, transcript: transcript, center: askVita,
                            scrollToTop: { scrollPosition.scrollTo(edge: .bottom) },
                            isAtBottom: { [transcript] in transcript.window.isAtBottom },
                            arrive: { [context, transcript] text in
                                context.insert(ChatMessage(role: "assistant", content: text, createdAt: .now,
                                                           isSystemSeed: false))
                                try? context.save()
                                transcript.appendNewer()
                            })
        #endif
    }

    /// Load the personalized quick-prompt chips (constants + a personalized set, refreshed every
    /// few days) and swap them in. The service handles the cache, the no-key fallback, and all
    /// failures internally — it always returns a non-empty list — so this just assigns the result.
    @MainActor
    private func loadQuickPrompts() async {
        let data = CoachDataSnapshot.fetch(from: context)
        let prompts = await CoachPromptService.prompts(
            profile: profile, foods: data.foods, weights: data.weights,
            sessions: data.sessions, water: data.water,
            memory: CoachMemory.fetchOrCreate(in: context, profile: profile)
        )
        // Only animate/replace if something actually changed (the common cache-hit re-run returns
        // the same list), so the row doesn't flicker on every appear.
        if prompts != quickPrompts {
            withAnimation(.easeInOut(duration: 0.25)) { quickPrompts = prompts }
        }
    }

    /// Consume an "Ask Vita about this" topic: show its mini-card atop the chat, then ask the
    /// (self-contained) question on the user's behalf so Vita explains it right away. While a
    /// reply is on its way the topic waits (it is asked when that turn settles) instead of
    /// being dropped with its card left on screen.
    private func handleAskVita(_ topic: AskVitaTopic) {
        guard engine.isAttached, !engine.isSending else { return }
        withAnimation { aboutTopic = topic }
        askVita?.pendingTopic = nil
        send(text: topic.question)
    }

    /// Move a quoted passage from the bus into the composer and bring the keyboard up.
    private func takePendingQuote() {
        guard let passage = askVita?.pendingQuote else { return }
        askVita?.pendingQuote = nil
        setQuote(passage)
    }

    /// "Ask about this" on a selection or a whole message. It goes through the same bus a
    /// long-press on a card elsewhere in the app uses, so there is one way into the composer.
    private func ask(about passage: String) {
        if let askVita { askVita.quote(passage) } else { setQuote(passage) }
    }

    private func setQuote(_ passage: String) {
        let normalized = ChatQuote.normalized(passage)
        guard !normalized.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) { quote = normalized }
        inputFocused = true
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

    /// Whether VoiceOver is running, or a UI flow asked for its layout.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    private var readsInDrawnOrder: Bool { voiceOverEnabled || UITestHooks.current.voiceOverLayout }

    /// The stack that holds the rows. SwiftUI ignores `accessibilitySortPriority` among a lazy
    /// stack's rows (measured: the same priorities left the order newest first in a
    /// `LazyVStack` and put it right in a `VStack`; EVAL_REPORT 43), and the flip declares rows
    /// newest first, so with VoiceOver on the rows go in a plain stack and are read in the order
    /// they are drawn. Without VoiceOver the lazy stack stays: a plain one measured slower to
    /// open and heavier (docs/chat-standards.md). The flip keeps pages from jumping either way.
    @ViewBuilder
    private func chatStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if readsInDrawnOrder {
            VStack(alignment: .leading, spacing: Theme.Space.xs, content: content)
        } else {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xs, content: content)
        }
    }

    private var conversation: some View {
        // A FLIPPED list, the layout chat products use (Stream's SwiftUI message list,
        // UIKit chats on a flipped table): the scroll view is turned upside down and every row
        // turned back, so the newest message is the START of the content and older pages are
        // added at its END. Adding at the end never moves what is on screen, so loading
        // earlier messages cannot jump, whatever the lazy stack estimates for rows it has not
        // laid out (the unflipped list held its top row from that estimate and moved it by up
        // to 178 pt: docs/chat-standards.md, section 1; EVAL_REPORT 32).
        ScrollView {
            chatStack {
                // Why the last message has no reply, and what to do about it, right under it.
                if let failure = engine.failure, !engine.isSending {
                    TurnFailureRow(failure: failure,
                                   onRetry: { engine.retry() })
                        .chatFlipped()
                        .chatReadingOrder(ChatReadingOrder.failure)
                        .id(Self.failureID)
                        .transition(.opacity)
                }

                // The one-tap confirm card sits inline at the bottom of the chat,
                // beside the coach avatar, like a proposal from Vita herself.
                if let pending = engine.pendingTool {
                    ToolConfirmCard(coachName: coachName,
                                    summary: pending.request.confirmSummary,
                                    onYes: { engine.confirmPendingTool() },
                                    onNo: { engine.declinePendingTool() })
                        .chatFlipped()
                        .chatReadingOrder(ChatReadingOrder.confirm)
                        .id(Self.confirmID)
                        // The content is flipped, so its top edge is the screen's bottom.
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if engine.isSending {
                    TypingIndicator(coachName: coachName)
                        .chatFlipped()
                        .chatReadingOrder(ChatReadingOrder.typing)
                        .id(Self.typingID)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(Array(transcript.rows.enumerated().reversed()), id: \.element.id) { index, message in
                    MessageRow(message: message,
                               coachName: coachName,
                               showsTimestamp: transcript.window.showsTimestamp(at: index),
                               isStreaming: message.id == engine.streamingMessageID,
                               showsActions: showsActions(for: message),
                               onStreamComplete: {
                                   if engine.streamingMessageID == message.id { engine.streamingMessageID = nil }
                                   if transcript.window.isAtBottom { scrollToBottom() }
                               },
                               onTap: { toggleActions(for: message) },
                               onCopy: { UIPasteboard.general.string = message.content },
                               onAsk: { passage in ask(about: passage ?? message.content) },
                               onDelete: {
                                   pendingDelete = message.id
                                   showDeleteDialog = true
                               })
                        .chatFlipped()
                        .chatReadingOrder(ChatReadingOrder.message(at: index, of: transcript.rows.count))
                        .id(message.id)
                        #if DEBUG
                        .chatProbeFrame(message.id)
                        .onAppear {
                            if message.id == transcript.rows.last?.id {
                                ChatLoadProbe.markNewestRowAppeared(rowsInStore: transcript.storedCount(),
                                                                    rowsLoaded: transcript.rows.count)
                            }
                        }
                        #endif
                }

                if transcript.window.hasEarlier {
                    LoadEarlierRow(isLoading: transcript.window.isLoadingEarlier, action: loadEarlier)
                        .chatFlipped()
                        .chatReadingOrder(ChatReadingOrder.top(messages: transcript.rows.count))
                        .id(Self.earlierID)
                } else if transcript.rows.count > transcript.window.pageSize {
                    ConversationStartRow()
                        .chatFlipped()
                        .chatReadingOrder(ChatReadingOrder.top(messages: transcript.rows.count))
                }
            }
            .padding(.horizontal, Theme.Space.md)
            // Flipped: the content's top is the screen's bottom.
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.md)
        }
        .chatFlipped()
        // The rows' reading-order priorities are compared within this container.
        .accessibilityElement(children: .contain)
        .chatEdgeEffectsHidden()
        // The content starts at the newest message, so the chat opens there with no scroll.
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        // NOTE: broad `.animation(_:value:)` on the ScrollView was removed — it animated
        // EVERY change in the scroll view (including the keyboard-avoidance inset) and,
        // combined with the auto-scroll on send, drove a non-converging view-graph update
        // (the watchdog freeze). Insert/transition animations are handled locally instead.
        .onScrollGeometryChange(for: CGFloat.self, of: ChatScrollBox.distanceFromNewest) { _, distance in
            // Written to a box, not to state: this runs on every frame of a scroll.
            scrollBox.distanceFromNewest = distance
        }
        .onScrollPhaseChange { _, phase in
            // A new drag while the reader is still at the oldest loaded message (the last
            // page left them there, so "reached it" will not fire again): load the next.
            if phase == .interacting, scrollBox.isNearOldest, !ChatScrollBox.autoLoadDisabled { loadEarlier() }
        }
        .onScrollGeometryChange(for: Bool.self, of: ChatScrollBox.isNearNewest) { _, atNewest in
            transcript.setAtBottom(atNewest)
        }
        .onScrollGeometryChange(for: Bool.self, of: ChatScrollBox.isNearOldest) { _, nearOldest in
            // Reaching the oldest loaded message loads the page before it.
            scrollBox.isNearOldest = nearOldest
            if nearOldest, !ChatScrollBox.autoLoadDisabled { loadEarlier() }
        }
        .onChange(of: transcript.scrollToLatestTick) { scrollToBottom() }
        .onChange(of: engine.isSending) { if transcript.window.isAtBottom { scrollToBottom() } }
        .onChange(of: engine.pendingTool != nil) { if transcript.window.isAtBottom { scrollToBottom() } }
        .onChange(of: engine.failure?.id) { if transcript.window.isAtBottom { scrollToBottom() } }
        .onChange(of: engine.streamingMessageID) { _, id in announceReply(id) }
        .overlay(alignment: .bottomTrailing) {
            if transcript.window.showsJumpToLatest {
                JumpToLatestButton(unseenCount: transcript.window.unseenCount) { transcript.jumpToLatest() }
                    .padding(.trailing, Theme.Space.md)
                    .padding(.bottom, Theme.Space.sm)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: transcript.window.showsJumpToLatest)
    }

    private static let typingID = "typing-indicator"
    private static let confirmID = "tool-confirm-card"
    private static let failureID = "turn-failure"
    private static let earlierID = "load-earlier"

    /// The newest reply always shows its actions; an older one, or one of her own messages,
    /// after a tap on it.
    private func showsActions(for message: ChatRow) -> Bool {
        guard !message.isDecision, !message.content.isEmpty,
              message.id != engine.streamingMessageID else { return false }
        if message.id == actionsRevealedFor { return true }
        guard !message.isUser else { return false }
        return message.id == transcript.rows.last(where: { !$0.isUser && !$0.isDecision })?.id
    }

    private func toggleActions(for message: ChatRow) {
        withAnimation(.easeOut(duration: 0.18)) {
            actionsRevealedFor = actionsRevealedFor == message.id ? nil : message.id
        }
    }

    /// Add the previous page. In the flipped list it goes at the end of the content, past
    /// the top of the screen, so nothing the reader is looking at moves.
    private func loadEarlier() {
        guard transcript.window.hasEarlier, !transcript.window.isLoadingEarlier else { return }
        #if DEBUG
        let anchor = transcript.rows.first?.id
        ChatDebug.notePrepend(anchor: anchor, phase: "before")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            ChatDebug.notePrepend(anchor: anchor, phase: "after", loaded: transcript.rows.count)
        }
        #endif
        transcript.loadEarlier()
    }

    /// Scroll to the newest message: the START of the flipped content.
    private func scrollToBottom(animated: Bool = true) {
        // Defer to the next runloop tick so the scroll never runs *inside* the in-progress
        // SwiftUI transaction (the message insert + keyboard dismiss that fire together on
        // send). Scrolling mid-transaction recurses the view-graph update and pins the main
        // thread at 100% CPU → the watchdog kill (0x8BADF00D) the user hit on send.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) { scrollPosition.scrollTo(edge: .top) }
            } else {
                scrollPosition.scrollTo(edge: .top)
            }
        }
    }

    /// VoiceOver does not notice a row that is inserted while its focus is elsewhere, so a
    /// new reply is announced.
    private func announceReply(_ id: UUID?) {
        guard let id, UIAccessibility.isVoiceOverRunning,
              let reply = transcript.rows.last(where: { $0.id == id }) else { return }
        AccessibilityNotification.Announcement("\(coachName) replied: \(reply.content)").post()
    }

    // MARK: - Input area (quick chips + text field + send)

    private var inputArea: some View {
        VStack(spacing: Theme.Space.sm) {
            // Quick-prompt chips — only while the field is empty. The moment she starts typing they
            // get out of the way (they're starters, not a toolbar competing with her own words).
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.xs) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            QuickPromptChip(text: prompt) { send(text: prompt) }
                                .disabled(engine.isSending || engine.pendingTool != nil)
                                .opacity(engine.isSending || engine.pendingTool != nil ? 0.5 : 1)
                        }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let img = attachedImage {
                attachmentPreview(img)
            }

            // The passage being asked about ("Ask about this"), until it is sent or removed.
            if let quote {
                ComposerQuoteCard(quote: quote) {
                    withAnimation(.easeOut(duration: 0.15)) { self.quote = nil }
                }
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
                .disabled(engine.isSending || engine.pendingTool != nil)
                .opacity(engine.isSending || engine.pendingTool != nil ? 0.5 : 1)
                .accessibilityLabel("Attach a photo")

                TextField("Message \(coachName)…", text: $draft, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.brand)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .accessibilityIdentifier(AccessibilityID.Coach.input)
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
                    .onSubmit { sendDraft() }
                    .animation(.easeOut(duration: 0.2), value: inputFocused)

                if engine.isSending {
                    // While a reply is on its way the send button is a stop button.
                    Button {
                        engine.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.cardRaised))
                            .overlay(Circle().strokeBorder(Theme.brand.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop")
                    .accessibilityHint("Stops \(coachName)'s reply")
                } else {
                    Button {
                        sendDraft()
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
                    .accessibilityIdentifier(AccessibilityID.Coach.send)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.bottom, Theme.Space.sm)
        }
        .padding(.top, Theme.Space.sm)
        .animation(.easeInOut(duration: 0.2), value: draft.isEmpty)   // fade the chips in/out smoothly
        .animation(.easeOut(duration: 0.2), value: quote)
        .background(
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Divider()
                    .overlay(Theme.divider)
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .sensoryFeedback(.impact(weight: .light), trigger: engine.hapticTick)
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
        !engine.isSending
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || attachedImage != nil || quote != nil)
    }

    /// Store a picked photo (downscaled) as the pending attachment shown over the input.
    private func attach(_ image: UIImage) {
        attachedImage = image.downscaled(maxEdge: 768)
    }

    // MARK: - Sending

    /// Send what is in the field, with the quoted passage (if any) in front of it.
    private func sendDraft() {
        guard canSend else { return }
        send(text: ChatQuote.compose(quote: quote, question: draft))
    }

    /// Hand a message to the engine. It saves the message, starts the turn, and ignores the
    /// call while a turn is in flight; this only clears what the message consumed.
    private func send(text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        // JPEG of any attached (already-downscaled) photo. A message may be image-only.
        let imageData = attachedImage?.jpegData(compressionQuality: 0.6)
        guard engine.send(text: text, imageData: imageData) != nil else { return }

        // Keep the keyboard up after send (chat-standard, like Messages). Dismissing it here —
        // while the message inserts AND the list auto-scrolls — was the freeze trigger: the
        // keyboard-avoidance safe-area animation fought the scroll/relayout into a runaway
        // view-graph update (watchdog 0x8BADF00D). The quick-prompt + Ask-Vita paths never
        // raise the keyboard, which is exactly why ONLY typing-then-send froze.
        let typed = ChatQuote.compose(quote: quote, question: draft)
        if text == typed || text == draft.trimmingCharacters(in: .whitespacesAndNewlines) {
            draft = ""
            quote = nil
        }
        attachedImage = nil   // consumed into the message
        actionsRevealedFor = nil
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
    let message: ChatRow
    let coachName: String
    let showsTimestamp: Bool
    /// True only for the freshest assistant reply, which types itself out; history renders instantly.
    var isStreaming: Bool = false
    /// Whether the copy / ask / share row sits under this message.
    var showsActions: Bool = false
    var onStreamComplete: () -> Void = {}
    /// A tap on a reply (not on a link, not one that dismisses a selection), or a tap or long
    /// press on her own message.
    var onTap: () -> Void = {}
    var onCopy: () -> Void = {}
    /// "Ask about this": a selected passage, or nil for the whole message.
    var onAsk: (String?) -> Void = { _ in }
    var onDelete: () -> Void = {}

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
                if showsActions {
                    MessageActionRow(text: message.content, onCopy: onCopy,
                                     onAsk: { onAsk(nil) }, onDelete: onDelete)
                        // Under the bubble: past the avatar for a reply, at the right for hers.
                        .padding(.leading, message.isUser ? 0 : 28 + Theme.Space.xs)
                        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bubble as drawn, without its menu or accessibility.
    private var bubbleBody: some View {
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
                        // Her own text — plain, on the brand gradient. Inline markup only. A
                        // message that opens with a quoted passage shows it as a reference.
                        let parts = ChatQuote.split(message.content)
                        VStack(alignment: .leading, spacing: 8) {
                            if let quote = parts.quote { BubbleQuote(quote: quote) }
                            Text(Self.styled(parts.body))
                                .font(.body)
                                .foregroundStyle(Theme.background)
                        }
                    } else if isStreaming {
                        // The freshest reply types itself out word by word, then settles into the
                        // same markdown rendering as the rest.
                        TypewriterMarkdown(fullText: message.content,
                                           color: Theme.textPrimary,
                                           onComplete: onStreamComplete)
                    } else {
                        // Vita's replies render real markdown blocks (lists, headings, rules)
                        // instead of leaking literal `- ` / `##` / `---`, in a text view so a
                        // passage can be selected by range (SwiftUI `Text` selects all or nothing).
                        SelectableMarkdownText(markdown: message.content, color: Theme.textPrimary,
                                               onAsk: { onAsk($0) }, onTap: onTap)
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
    }

    private var bubble: some View {
        bubbleBody
            .modifier(OwnMessageActions(enabled: message.isUser && !message.content.isEmpty,
                                        showsActions: showsActions, onTap: onTap))
        .accessibilityElement(children: .ignore)
        // A message is read-only text. Saying so keeps it a static-text element now that a
        // reply is drawn by a text view (for selection) rather than by `Text`; VoiceOver and
        // the UI flows both find messages as static text.
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(message.isUser ? "You said" : "\(coachName) said")
        .accessibilityValue(message.imageData != nil ? "\(message.content) (photo attached)" : message.content)
        .accessibilityIdentifier(message.isUser ? AccessibilityID.Coach.userMessage
                                                : AccessibilityID.Coach.assistantMessage)
        .accessibilityAction(named: "Copy message") { onCopy() }
        .accessibilityAction(named: "Ask about this") { onAsk(nil) }
        .accessibilityAction(named: "Delete message") { onDelete() }
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

    /// The EXACT time a message was sent ("3:05 PM"), not a relative "12 minutes ago" — so it
    /// reads like a real messages thread and you can see precisely when you talked to Vita. Older
    /// messages carry a "Yesterday" / dated prefix so the time is never ambiguous.
    private var timestamp: String {
        let cal = Calendar.current
        let date = message.createdAt
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return time }
        if cal.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
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
            .accessibilityIdentifier(AccessibilityID.Coach.typing)

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
            .accessibilityIdentifier(AccessibilityID.Coach.undo)
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

/// Her own messages: a tap toggles the same action row a reply has (copy, ask about, share,
/// delete), and a long press opens it. Not the system context menu: the chat is a flipped
/// scroll view, and the lifted preview UIKit cuts from a bubble inside it came out as a thin
/// line, or narrower than the bubble and cut off when given explicitly (seen on iOS 26.4).
/// Chat SDKs built on a flipped list draw their own message actions for the same reason.
/// A reply has neither: a long press on its text starts a selection, and a tap on it is
/// handled by its text view.
private struct OwnMessageActions: ViewModifier {
    let enabled: Bool
    let showsActions: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .onLongPressGesture(minimumDuration: 0.35) { if !showsActions { onTap() } }
                .sensoryFeedback(.impact(weight: .light), trigger: showsActions) { old, new in !old && new }
        } else {
            content
        }
    }
}

