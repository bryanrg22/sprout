import SwiftUI

// The pieces of the chat screen that sit around the message bubbles: the failed-turn row,
// the "load earlier" row, the jump-to-latest button, the quoted reference in the composer
// and in a bubble, and the action row under a reply. Views only; what they show and when is
// decided by `CoachTurnEngine`, `ChatTranscript` and `ChatQuote`.

// MARK: - A turn that failed

/// Why the last message has no reply and what to do about it, shown in the conversation
/// right under that message (where the reader is looking), not as a banner at the top.
struct TurnFailureRow: View {
    let failure: CoachTurnEngine.Failure
    var onRetry: () -> Void
    var onOpenSettings: () -> Void

    private var tint: Color { failure.error == .missingKey ? Theme.brand : Theme.warning }
    private var icon: String {
        switch failure.error {
        case .missingKey, .auth: return "key.fill"
        case .offline, .connectionLost: return "wifi.slash"
        case .cancelled: return "stop.circle.fill"
        default: return "exclamationmark.bubble.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    // The message itself carries the id the UI flows look for (a static text).
                    .accessibilityIdentifier(AccessibilityID.Coach.errorBanner)
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .padding(.top, Theme.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.turnFailure")
    }

    @ViewBuilder private var actions: some View {
        switch failure.action {
        case .retry:
            pill("Try again", systemImage: "arrow.clockwise", prominent: true, action: onRetry)
        case .retryAfter:
            // Counts down to the moment the provider said the limit clears, then offers Retry.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = (failure.retryNotBefore ?? timeline.date).timeIntervalSince(timeline.date)
                if remaining > 0.5 {
                    pill("Try again in \(Self.countdown(remaining))", systemImage: "clock",
                         prominent: false, action: {})
                        .disabled(true)
                        .accessibilityLabel("Try again in \(CoachTurnError.waitText(remaining))")
                } else {
                    pill("Try again", systemImage: "arrow.clockwise", prominent: true, action: onRetry)
                }
            }
        case .openAISettings:
            // Side by side when they fit, stacked when they do not (large text sizes).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.sm) { settingsPill; retryPill }
                VStack(alignment: .leading, spacing: Theme.Space.xs) { settingsPill; retryPill }
            }
        case .rephrase, .waitForTomorrow:
            EmptyView()
        }
    }

    private var settingsPill: some View {
        pill("AI settings", systemImage: "gearshape.fill", prominent: true, action: onOpenSettings)
            .accessibilityLabel("Open AI settings")
    }

    private var retryPill: some View {
        pill("Try again", systemImage: "arrow.clockwise", prominent: false, action: onRetry)
    }

    /// "12s", "1:05": a short countdown.
    static func countdown(_ seconds: TimeInterval) -> String {
        let whole = max(1, Int(seconds.rounded(.up)))
        return whole < 60 ? "\(whole)s" : "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    private func pill(_ title: String, systemImage: String, prominent: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background {
                    if prominent {
                        Capsule(style: .continuous).fill(Theme.brandGradient)
                    } else {
                        Capsule(style: .continuous).fill(Theme.cardRaised)
                            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .bouncyPress()
    }
}

// MARK: - Earlier messages

/// The top of the loaded conversation when older messages exist. It loads the previous page
/// when it scrolls into view; it is also a button, so the same thing can be done without
/// scrolling (VoiceOver, Switch Control, a pointer).
struct LoadEarlierRow: View {
    let isLoading: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(Theme.textSecondary)
                } else {
                    Image(systemName: "arrow.up").font(.caption.weight(.bold))
                }
                Text(isLoading ? "Loading earlier messages…" : "Load earlier messages")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(Theme.cardRaised, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, Theme.Space.xs)
        .accessibilityLabel(isLoading ? "Loading earlier messages" : "Load earlier messages")
        .accessibilityIdentifier("coach.loadEarlier")
    }
}

/// Shown at the very top once the whole conversation is loaded and it spans more than one
/// page, so reaching the beginning reads as an end and not as a stall.
struct ConversationStartRow: View {
    var body: some View {
        Text("Beginning of your conversation")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.textSecondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, Theme.Space.xs)
    }
}

// MARK: - Jump to latest

/// Offered while the reader is away from the newest message. The count is how many messages
/// arrived in the meantime.
struct JumpToLatestButton: View {
    let unseenCount: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.brand)
                .frame(width: 40, height: 40)
                .background(Theme.cardRaised, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
                .overlay(alignment: .topTrailing) {
                    if unseenCount > 0 {
                        Text(unseenCount > 9 ? "9+" : "\(unseenCount)")
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.brand, in: Capsule(style: .continuous))
                            .offset(x: 5, y: -5)
                    }
                }
                .frame(width: 44, height: 44)   // the hit target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .accessibilityLabel(unseenCount > 0
                            ? "Jump to latest message, \(unseenCount) new"
                            : "Jump to latest message")
        .accessibilityIdentifier("coach.jumpToLatest")
    }
}

// MARK: - A quoted passage

/// The passage being asked about, above the message field: a visible reference the next
/// message will carry. Dismissible.
struct ComposerQuoteCard: View {
    let quote: String
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.brand)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asking about")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(quote)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(7)
                    .background(Theme.cardRaised, in: Circle())
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove quote")
        }
        .padding(.leading, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Space.md)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Asking about: \(quote)")
        .accessibilityIdentifier("coach.composerQuote")
    }
}

/// The quoted passage inside the user's own bubble (on the brand gradient).
struct BubbleQuote: View {
    let quote: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.background.opacity(0.55))
                .frame(width: 3)
            Text(quote)
                .font(.footnote)
                .foregroundStyle(Theme.background.opacity(0.8))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Theme.background.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quoted: \(quote)")
    }
}

// MARK: - Actions under a reply

/// Copy, ask about, share and (in the overflow) delete for one reply. Always under the
/// newest reply; under an older one after a tap on it.
struct MessageActionRow: View {
    let text: String
    var onCopy: () -> Void
    var onAsk: () -> Void
    var onDelete: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 2) {
            iconButton(copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied" : "Copy message") {
                onCopy()
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            }
            iconButton("sparkles", label: "Ask about this", action: onAsk)
            ShareLink(item: text) { icon("square.and.arrow.up") }
                .buttonStyle(.plain)
                .accessibilityLabel("Share message")
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete message", systemImage: "trash")
                }
            } label: {
                icon("ellipsis")
            }
            .accessibilityLabel("More")
        }
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
        .accessibilityIdentifier("coach.messageActions")
    }

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(systemName) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 40, height: 34)
            .contentShape(Rectangle())
    }
}
