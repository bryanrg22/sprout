import SwiftUI
import UIKit

/// A gentle "finish setting up" card on Today, shown ONLY when there's no AI key yet —
/// i.e. she tapped "Maybe later" in onboarding. It lets her paste the key right here, so
/// the one thing standing between her and chatting with the coach is a single tap away.
/// The card removes itself the instant a key is saved. This is the recoverable
/// counterpart to the onboarding Connect step (so "Maybe later" is never a dead end).
struct FinishSetupCard: View {
    let coachName: String

    /// Re-checked locally so the card disappears the moment a key is saved.
    @State private var hasKey = AIConfig.hasActiveKey
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if !hasKey {
            card
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(Theme.brandSoft).frame(width: 38, height: 38)
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Almost there — connect \(coachName)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Paste the key you were sent and we can start chatting. It stays on your phone.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Theme.Space.sm) {
                TextField("Paste your key", text: $draft)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.brand)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.cardRaised))
                    .overlay(Capsule().strokeBorder(
                        Theme.brand.opacity(focused ? 0.45 : 0.12), lineWidth: 1))

                Button {
                    if let s = UIPasteboard.general.string {
                        draft = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.brand)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Theme.brandSoft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste from clipboard")
            }

            Button(action: save) {
                Text("Save key")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.primary)
            .disabled(trimmed.isEmpty)
            .opacity(trimmed.isEmpty ? 0.5 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finish setup. Paste the key you were sent to start chatting with \(coachName).")
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty else { return }
        KeychainStore.setAPIKey(trimmed, for: AIConfig.provider)
        focused = false
        draft = ""
        withAnimation { hasKey = true }
    }
}
