import SwiftUI

/// A tasteful, dismissible nudge shown while logging a RUN / cardio session: since the
/// app doesn't track pace, distance or routes, point her at a dedicated running app
/// (Strava) so that effort actually shows up somewhere.
///
/// Recommendation only — no data integration, no API. Just a one-line "why" and a
/// button that opens Strava (its `strava://` scheme if installed, otherwise the App
/// Store). Dismissed once → gone for good via `@AppStorage`. Match the app's card
/// aesthetics (see `WidgetPromoCard`).
struct RunningAppCard: View {
    @Environment(\.openURL) private var openURL

    /// Sticky dismissal — once she taps the "x", the recommendation never returns.
    @AppStorage("runningAppRec.dismissed") private var dismissed = false

    /// Strava deep link (opens the app if installed) and the App Store fallback.
    private let stravaApp = URL(string: "strava://")
    private let stravaStore = URL(string: "https://apps.apple.com/app/strava/id426826309")!

    var body: some View {
        if !dismissed {
            card
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(Theme.brandSoft).frame(width: 38, height: 38)
                    Image(systemName: "figure.run")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make that run count")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("We don't track runs. Strava logs your pace, distance and routes — so the effort actually shows up.")
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

            Button(action: openStrava) {
                Label("Get Strava", systemImage: "arrow.up.forward.app.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.brandGradient,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            }
            .buttonStyle(.jelly)
            .accessibilityLabel("Get Strava")
            .accessibilityHint("Opens Strava, or the App Store if it isn't installed")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .contain)
    }

    /// Prefer the installed Strava app (`strava://`); fall back to its App Store page.
    /// `openURL`'s completion reports whether the deep link actually opened.
    private func openStrava() {
        guard let app = stravaApp else { openURL(stravaStore); return }
        openURL(app) { accepted in
            if !accepted { openURL(stravaStore) }
        }
    }
}
