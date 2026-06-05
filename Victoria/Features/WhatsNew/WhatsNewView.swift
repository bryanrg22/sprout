import SwiftUI

// MARK: - Model

/// One highlighted item on the "What's New" screen — an icon, a tint, and a short benefit
/// line. Deliberately copy-driven (no screenshots required) so shipping a release note is
/// just editing `WhatsNew.current` below.
struct WhatsNewFeature: Identifiable {
    let id = UUID()
    let icon: String        // SF Symbol (verified to exist on iOS 18)
    let tint: Color
    let title: String
    let detail: String
}

/// A single release's notes: the headline, the highlighted features (each is rendered as its
/// OWN swipeable page in the carousel), and a plain list of bug-fix one-liners (the finale page).
struct WhatsNewRelease {
    let version: String
    let title: String
    let features: [WhatsNewFeature]
    let fixes: [String]
}

// MARK: - Gate (version-tracking) + content

/// Decides when the "What's New" sheet appears and stores what the user has seen. It shows
/// ONCE per marketing version: a brand-new user is marked caught-up at the end of onboarding
/// (so they never see notes for the version they installed), and an existing user who updates
/// sees the new version's notes a single time.
enum WhatsNew {

    private static let key = "whatsnew.lastSeenVersion"

    /// The app's marketing version (e.g. "2.0"), from the bundle.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// DEBUG: `--whats-new` forces the sheet open regardless of version, for screenshots.
    static var isForced: Bool { CommandLine.arguments.contains("--whats-new") }

    /// Show when forced, or when the last-seen version differs from the current one. A fresh
    /// user is marked caught-up at onboarding, so `lastSeen == appVersion` and they skip it.
    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        if isForced { return true }
        guard !appVersion.isEmpty else { return false }
        return defaults.string(forKey: key) != appVersion
    }

    /// Record the current version as seen (called at onboarding completion, demo seeding, and
    /// when the user dismisses the sheet) so it doesn't reappear until the next update.
    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(appVersion, forKey: key)
    }

    /// The notes for the current release. Editing this (and bumping MARKETING_VERSION) is all
    /// it takes to ship a new "What's New".
    static let current = WhatsNewRelease(
        version: "2.0",
        title: "A whole new Sprout 🌱",
        features: [
            WhatsNewFeature(
                icon: "figure.strengthtraining.traditional", tint: Theme.brand,
                title: "Workouts, done right",
                detail: "Your training finally has a home. Log a gym day machine by machine — or a quick run, walk, or ride — see your whole week at a glance, and tap any day for the full breakdown."),
            WhatsNewFeature(
                icon: "sparkles", tint: Theme.protein,
                title: "Just ask Vita",
                detail: "Tell her in plain words and she handles it. \"Log chest day — chest press 90 for 3 sets,\" \"I forgot my oatmeal yesterday,\" \"switch me to pounds.\" Vita logs it, back-dates it, even updates your settings — no menus."),
            WhatsNewFeature(
                icon: "square.grid.2x2.fill", tint: Theme.water,
                title: "Your machines, in your order",
                detail: "The machines you actually use rise to the top. Sprout learns your go-to lifts for each muscle — and the most popular ones — so your next set is always a tap away."),
            WhatsNewFeature(
                icon: "chart.bar.fill", tint: Theme.positive,
                title: "Your whole day, in rings",
                detail: "Macros, steps, and water — for today or any day last week — each with a ring that fills as you hit your goal. Plus a plain-English progress recap with your starting weight right on the chart."),
        ],
        fixes: [
            "Your streak now counts only the days you actually log — auto-imported steps and scale syncs don't pad it anymore.",
            "Vita's calorie math now matches your Nutrients card to the calorie.",
            "A protein goal you set with Vita now sticks, even when you're following a plan.",
        ])
}

// MARK: - View

/// The "What's New" sheet — a swipeable, paged carousel. Each release feature is its own
/// full-screen page (a big tinted medallion + title + detail), with an "Also fixed" checklist
/// as the finale. A fixed header carries the version, and pinned Back / Next controls drive the
/// page (the TabView's dots show progress). Skin-aware via `Theme`.
struct WhatsNewView: View {
    let release: WhatsNewRelease
    @Environment(\.dismiss) private var dismiss

    /// The current carousel page (also the TabView selection). 0-based.
    @State private var page = 0

    // MARK: Page bookkeeping

    /// Whether the release has a trailing "Also fixed" page (omitted gracefully when empty).
    private var hasFixesPage: Bool { !release.fixes.isEmpty }

    /// Total pages: one per feature, plus the fixes finale when there are fixes.
    private var pageCount: Int { release.features.count + (hasFixesPage ? 1 : 0) }

    /// Index of the last page (where "Next" becomes "Let's go").
    private var lastIndex: Int { max(0, pageCount - 1) }

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $page) {
                ForEach(Array(release.features.enumerated()), id: \.element.id) { index, feature in
                    featurePage(feature).tag(index)
                }
                if hasFixesPage {
                    fixesPage.tag(release.features.count)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: page)

            footer
        }
        .background(Theme.background.ignoresSafeArea())
        // The page dots are a UIPageControl under the hood and default to white-ish — invisible
        // on the cream (cute) canvas. Tint them to the brand (active) + a faint primary (inactive)
        // so progress reads clearly in BOTH skins.
        .onAppear {
            UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Theme.brand)
            UIPageControl.appearance().pageIndicatorTintColor = UIColor(Theme.textPrimary.opacity(0.18))
        }
    }

    // MARK: Header (fixed — same across pages)

    private var header: some View {
        VStack(spacing: 4) {
            Text("WHAT'S NEW")
                .font(.caption.weight(.heavy)).tracking(2)
                .foregroundStyle(Theme.brand)
            Text("Version \(release.version)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
    }

    // MARK: Feature page (one per feature — big, centered, celebratory)

    private func featurePage(_ f: WhatsNewFeature) -> some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer(minLength: Theme.Space.lg)

            // Tinted medallion — large circular chip with the symbol over a soft tint fill.
            ZStack {
                Circle()
                    .fill(f.tint.opacity(0.16))
                Circle()
                    .strokeBorder(f.tint.opacity(0.28), lineWidth: 1)
                Image(systemName: f.icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(f.tint)
            }
            .frame(width: 92, height: 92)

            VStack(spacing: Theme.Space.md) {
                Text(f.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(f.detail)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Space.xl)
    }

    // MARK: Fixes page (the finale — a clean green checklist)

    private var fixesPage: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer(minLength: Theme.Space.lg)

            VStack(spacing: Theme.Space.md) {
                ZStack {
                    Circle()
                        .fill(Theme.positive.opacity(0.16))
                    Circle()
                        .strokeBorder(Theme.positive.opacity(0.28), lineWidth: 1)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Theme.positive)
                }
                .frame(width: 92, height: 92)

                Text("Also fixed 🛠️")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // The fixes as a checklist — same green checkmark + text treatment as before.
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ForEach(release.fixes, id: \.self) { fix in
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.positive)
                            .padding(.top, 2)
                        Text(fix)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.lg)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))

            Spacer(minLength: Theme.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Space.xl)
    }

    // MARK: Footer (pinned navigation — Back + Next / Let's go)

    private var footer: some View {
        VStack(spacing: Theme.Space.sm) {
            Button(page == lastIndex ? "Let's go" : "Next") {
                if page == lastIndex {
                    WhatsNew.markSeen()
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 }
                }
            }
            .buttonStyle(.primary)

            // "Back" — subtle, secondary, and only once there's a page to go back to.
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page -= 1 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
                    Text("Back")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
            .opacity(page > 0 ? 1 : 0)
            .disabled(page == 0)          // keep layout height stable; just hide when on page 0
            .accessibilityHidden(page == 0)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.md)
        .background(Theme.background)
    }
}
