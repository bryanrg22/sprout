import SwiftUI

/// A gentle, ONE-TIME "add a widget" nudge on the Today screen. Shown only AFTER she's
/// engaged (a couple days in, so there's real data worth glancing at) — never at first
/// launch, where an empty widget means nothing. iOS can't place a widget for her, so this is
/// a warm how-to she can dismiss for good. (Bryan's "hey, we have widgets!" idea, done the
/// earned way — see [[ai-coach-research]] widget-promotion-timing.)
struct WidgetPromoCard: View {
    let profile: UserProfile
    /// Engagement gate from the dashboard (a 2+ day streak) — only surface once she's in.
    let eligible: Bool

    @AppStorage("widgetPromo.dismissed") private var dismissed = false

    private var appName: String { "Sprout" }

    var body: some View {
        if eligible && !dismissed {
            card
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(Theme.brandSoft).frame(width: 38, height: 38)
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Put me on your home screen ✨")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your companion, calories, steps + streak — at a glance, no app needed.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(7)
                        .background(Theme.cardRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            // The how-to (iOS can't add a widget for you — it's always a long-press).
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.brand)
                Text("Touch & hold your home screen → tap ＋ → search “\(appName)”")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brandSoft.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            Text("✨ Want a different look? You can change the app icon too — Settings → App Icon.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add a \(appName) widget to your home screen. Touch and hold the home screen, tap plus, and search \(appName).")
    }
}
