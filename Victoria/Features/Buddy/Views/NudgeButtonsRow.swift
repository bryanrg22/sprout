import SwiftUI

/// A row of one-tap nudge buttons — one per `NudgeKind` — for cheering your buddy on,
/// plus a "Write your own 💬" chip that opens a tiny composer for a personal note.
/// Every kind is health-POSITIVE by construction (see `NudgeKind`); there is no shaming
/// option to render. Each preset tap calls `onSend(kind)` (routed by the VM to
/// `sendNudge(_:)`); the composer calls `onSendCustom(text:)`. Both squish with a jelly
/// press and pop a tiny confirmation, and both fire the hub's confetti on success.
///
/// Laid out as a horizontally-scrolling rail of round icon chips so all five presets *plus*
/// the "write your own" affordance fit comfortably and stay ≥ 44pt touch targets — nothing
/// runs off the edge.
struct NudgeButtonsRow: View {
    /// Called with the chosen kind when a preset chip is tapped.
    var onSend: (NudgeKind) -> Void
    /// Called with a hand-written note when the composer is sent.
    var onSendCustom: (String) -> Void
    /// The most-recently-sent kind, so the matching chip can flash a brief check.
    var lastSentKind: NudgeKind?

    @State private var showComposer = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Send a little love")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.md) {
                    // Composer leads the rail — a personal note is the warmest way to reach
                    // your buddy, so it sits first, ahead of the one-tap presets.
                    WriteOwnChip { showComposer = true }
                    ForEach(NudgeKind.allCases) { kind in
                        NudgeChip(kind: kind,
                                  justSent: lastSentKind == kind,
                                  action: { onSend(kind) })
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            // Clip the rail to its own bounds so chips never bleed past the card's rounded
            // edge — they scroll within the box instead of spilling off-screen.
        }
        .sheet(isPresented: $showComposer) {
            CustomNoteComposer { text in
                onSendCustom(text)
            }
        }
    }
}

/// A single circular nudge button: tinted icon disc + label, jelly press, success haptic.
private struct NudgeChip: View {
    let kind: NudgeKind
    let justSent: Bool
    let action: () -> Void

    /// Bumped on tap to drive `.sensoryFeedback`.
    @State private var tapPulse = 0

    var body: some View {
        Button {
            tapPulse &+= 1
            action()
        } label: {
            VStack(spacing: 6) {
                // Per-kind soft tinted disc (shared with the inbox + challenge cards) so the
                // five nudges read as a warm, cohesive set rather than five identical chips.
                NudgeIconDisc(systemImage: kind.systemImage,
                              tint: kind.tint,
                              size: 58,
                              showsCheck: justSent)
                    .popIn(true)
                Text(kind.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 66)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .sensoryFeedback(.success, trigger: tapPulse)
        .accessibilityLabel("Send \(kind.label) to your buddy")
    }
}

/// The "write your own" chip — same circular shape + label as a preset, but a dashed,
/// inviting outline and a chat glyph so it reads as "compose", not "send now".
private struct WriteOwnChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Theme.brandSoft.opacity(0.6))
                        .frame(width: 58, height: 58)
                        .overlay(
                            Circle().strokeBorder(
                                Theme.brand.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                            )
                        )
                    Image(systemName: "square.and.pencil")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
                Text("Write your own")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .accessibilityLabel("Write your own note to your buddy")
    }
}

/// A small sheet to type a short, personal note (≤ `BuddyViewModel.maxCustomNoteLength`
/// chars) and send it. Warm and low-pressure: a live character count, a couple of
/// quick-start suggestions, and a Send button that's enabled the moment there's a
/// non-blank message. Sending dismisses the sheet; the hub shows the confetti + kind
/// confirmation (same as a preset nudge).
private struct CustomNoteComposer: View {
    /// Called with the typed note when "Send" is tapped.
    var onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    /// Friendly, all-positive starters — never about a missed goal (see RESEARCH_social.md).
    private let suggestions = [
        "Thinking of you today 💛",
        "So proud of you!",
        "You've got this 💪",
        "Coffee + a walk later? ☕️"
    ]

    private var limit: Int { BuddyViewModel.maxCustomNoteLength }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty }
    private var remaining: Int { limit - text.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    header
                    field
                    suggestionChips
                }
                .padding(.horizontal)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Write a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send 💛") { send() }
                        .fontWeight(.semibold)
                        .tint(Theme.brand)
                        .disabled(!canSend)
                }
            }
            .onAppear { fieldFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Say something just for them 💬")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("A little note your buddy will love. Keep it warm — they'll see it in their inbox.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Type your note…", text: $text, axis: .vertical)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3...5)
                .focused($fieldFocused)
                .submitLabel(.done)
                .onChange(of: text) { _, newValue in
                    // Hard char cap so an over-long note can never reach the wire.
                    if newValue.count > limit {
                        text = String(newValue.prefix(limit))
                    }
                }
                .padding(Theme.Space.md)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                )

            Text("\(remaining)")
                .font(.caption2.weight(.medium)).monospacedDigit()
                .foregroundStyle(remaining <= 10 ? Theme.warning : Theme.textSecondary)
                .accessibilityLabel("\(remaining) characters left")
        }
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Need a starter?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            // Wrapping rows so the suggestions never run off the edge either.
            FlowChips(items: suggestions) { suggestion in
                Button {
                    text = suggestion
                    fieldFocused = true
                } label: {
                    Text(suggestion)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, Theme.Space.sm)
                        .background(Theme.brandSoft, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .bouncyPress()
            }
        }
    }

    private func send() {
        guard canSend else { return }
        onSend(trimmed)
        dismiss()
    }
}

/// A tiny wrapping layout (chips flow onto new rows instead of overflowing). Uses SwiftUI's
/// native `Layout` so it stays correct at any width / Dynamic Type size.
private struct FlowChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: Theme.Space.sm) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

/// Minimal flow layout: places subviews left-to-right, wrapping to the next line when the
/// current one is full. Keeps the suggestion chips fully reachable regardless of width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview("Nudge buttons") {
    ZStack {
        Theme.background.ignoresSafeArea()
        NudgeButtonsRow(onSend: { _ in }, onSendCustom: { _ in }, lastSentKind: .cheer)
            .padding()
    }
}
