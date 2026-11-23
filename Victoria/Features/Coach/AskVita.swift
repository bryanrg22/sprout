import SwiftUI

/// "Ask Vita about this" — long-press almost any card and ask the coach to explain it in
/// plain language (cause + effect, never a refusal). The long-press sets a `pendingTopic`
/// here; `MainTabView` watches it and switches to the Vita tab, and `CoachView` shows a
/// little visual "mini" of the component + asks Vita the question on the user's behalf.
///
/// This is the "the app *understands* your data, it's not just a database" idea Bryan wants:
/// every component can explain itself, personally, in Vita's warm voice.
@Observable
final class AskVitaCenter {
    /// Set by a long-press; consumed by the Coach. `nil` when nothing is pending.
    var pendingTopic: AskVitaTopic?

    func ask(_ topic: AskVitaTopic) { pendingTopic = topic }

    /// A passage the user wants to ask about ("Ask about this" on selected text or on a whole
    /// message). Unlike a topic it is not sent for them: the Coach puts it above the message
    /// field as a quoted reference, and it travels with whatever they type next.
    var pendingQuote: String?

    func quote(_ passage: String) {
        let trimmed = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingQuote = trimmed
    }
}

/// A snapshot of the component the user tapped — enough for Vita to explain it AND to render
/// a little visual "mini" of it in the chat (icon + name + the live value), instead of bare
/// text. Built lazily at press time so it captures the CURRENT reading.
struct AskVitaTopic: Identifiable, Equatable {
    let id = UUID()
    var name: String        // "Calories", "Steps", "Weight trend", "Your shared panda"…
    var icon: String        // an SF Symbol for the mini-card
    var value: String       // the live reading, e.g. "389 kcal to go", "9,243 steps"
    var question: String    // the question we ask Vita on the user's behalf (self-contained)

    static func == (a: AskVitaTopic, b: AskVitaTopic) -> Bool { a.id == b.id }
}

extension View {
    /// Long-press this view to offer "Ask Vita about this". The closure builds the topic
    /// lazily so it captures the value at press time.
    func askVita(_ make: @escaping () -> AskVitaTopic) -> some View {
        modifier(AskVitaModifier(make: make))
    }
}

private struct AskVitaModifier: ViewModifier {
    let make: () -> AskVitaTopic
    /// Optional so the modifier is harmless in previews / contexts without the center.
    @Environment(AskVitaCenter.self) private var center: AskVitaCenter?

    func body(content: Content) -> some View {
        content.contextMenu {
            if center != nil {
                Button {
                    center?.ask(make())
                } label: {
                    Label("Ask Vita about this", systemImage: "sparkles")
                }
            }
        }
    }
}

/// The little "About this" mini-card shown at the top of the chat when the user asked about a
/// component — a visual stand-in for the component (icon + name + its live value), so Vita's
/// answer is anchored to a *thing she can see*, not just text. Dismissible.
struct AskVitaContextCard: View {
    let topic: AskVitaTopic
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1))
                Image(systemName: topic.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("About this")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(topic.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(topic.value)
                    .font(.caption.weight(.medium)).monospacedDigit()
                    .foregroundStyle(Theme.brand)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(7)
                    .background(Theme.cardRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(Theme.Space.sm)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Space.md)
        .padding(.top, Theme.Space.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Asking Vita about \(topic.name), \(topic.value)")
    }
}
