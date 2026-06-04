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

/// A single release's notes: the headline, the highlighted features (the FIRST is rendered as
/// a hero card), and a plain list of bug-fix one-liners.
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

    /// The app's marketing version (e.g. "1.7"), from the bundle.
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
        version: "1.8",
        title: "Meet the new Vita 🌱",
        features: [
            WhatsNewFeature(
                icon: "text.bubble.fill", tint: Theme.brand,
                title: "A beautiful new way to chat",
                detail: "Vita's replies now read like a real conversation — clean lists and highlights instead of walls of text. Your suggestions stay put, the text box grows as you type, and a goal you approve stays right in your chat history."),
            WhatsNewFeature(
                icon: "sparkles", tint: Theme.info,
                title: "Vita logs it for you",
                detail: "Just ask — \"log a chicken bowl, 600 cal\" or \"delete that\" — and she logs, edits, or removes your food, water, and weight. She can see every item in your day, too. Quick logs apply instantly, with an Undo."),
            WhatsNewFeature(
                icon: "brain.head.profile", tint: Theme.protein,
                title: "Vita remembers you",
                detail: "Tell her you take creatine, train Mon/Wed/Fri, or see a nutritionist — and she'll keep it in mind in every future chat."),
            WhatsNewFeature(
                icon: "camera.fill", tint: Theme.calories,
                title: "Show Vita your plate",
                detail: "Snap or attach a photo right in the chat. Vita actually sees it — and can log the meal for you."),
            WhatsNewFeature(
                icon: "barcode.viewfinder", tint: Theme.water,
                title: "One scan for everything",
                detail: "Point your camera at a barcode or a nutrition label — one Scan button figures out which, and asks how many servings you had."),
            WhatsNewFeature(
                icon: "lightbulb.fill", tint: Theme.warning,
                title: "Smarter Smart Picks",
                detail: "Suggestions that fit the time of day and never re-pitch something you've already had today."),
            WhatsNewFeature(
                icon: "chart.line.uptrend.xyaxis", tint: Theme.protein,
                title: "A Progress page that tells a story",
                detail: "An AI recap of your goal, trend sparklines for every metric, and a consistency heatmap."),
            WhatsNewFeature(
                icon: "person.2.fill", tint: Theme.positive,
                title: "Your buddy & panda, reimagined",
                detail: "One clean buddy card with weight, calories, protein and today's food — and a panda that munches its bamboo when you fuel it well."),
        ],
        fixes: [
            "Yesterday's step count now fills in to its real total instead of freezing at a partial number.",
            "Fixed a Vita freeze when using the keyboard or sending a message.",
            "Fixed a calorie undercount when logging more than one serving (like 2 apples).",
            "Your home-screen widget now shows calories, and the rings can climb past 100%.",
        ])
}

// MARK: - View

/// The "What's New" sheet — a celebratory header, a hero feature, the rest of the highlights,
/// and a plain "Also fixed" list, over a pinned "Let's go" button. Skin-aware via `Theme`.
struct WhatsNewView: View {
    let release: WhatsNewRelease
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    header
                    if let hero = release.features.first {
                        heroCard(hero)
                    }
                    ForEach(release.features.dropFirst()) { FeatureRow(feature: $0) }
                    if !release.fixes.isEmpty { fixesSection }
                }
                .padding(Theme.Space.lg)
                .padding(.bottom, Theme.Space.xl)   // breathing room above the pinned button
            }
            footer
        }
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT'S NEW")
                .font(.caption.weight(.heavy)).tracking(2)
                .foregroundStyle(Theme.brand)
            Text(release.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Version \(release.version)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.sm)
    }

    // MARK: Hero (first feature gets a bigger, brand-tinted card)

    private func heroCard(_ f: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.brand.opacity(0.22))
                Image(systemName: f.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.brand)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(f.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(f.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.brand.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.brand.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: Fixes

    private var fixesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Also fixed")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            ForEach(release.fixes, id: \.self) { fix in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
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
        .padding(Theme.Space.md)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .padding(.top, Theme.Space.xs)
    }

    // MARK: Footer button (pinned)

    private var footer: some View {
        Button("Let's go") {
            WhatsNew.markSeen()
            dismiss()
        }
        .buttonStyle(.primary)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.md)
        .background(Theme.background)
    }
}

/// A standard (non-hero) highlight row: tinted icon chip + title + one-line benefit.
private struct FeatureRow: View {
    let feature: WhatsNewFeature
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(feature.tint.opacity(0.18))
                Image(systemName: feature.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(feature.tint)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
