import SwiftUI

/// Renders a buddy's low-stakes daily snapshot kindly: name, day-streak, character mood,
/// a "logged today ✓" presence cue, and a soft "active 2h ago" hint.
///
/// **Hard rule:** this NEVER shows weight or calorie numbers — only warm, encouraging
/// presence signals (mirrors the `BuddySnapshot` "no numbers that invite comparison"
/// contract). The only number shown is the motivating day-streak.
struct BuddyStatusCard: View {
    let snapshot: BuddySnapshotPayload
    /// The buddy's pixel character (the OTHER avatar from mine), shown in the header instead
    /// of a bland monogram — so your buddy feels present and personal.
    var avatar: CompanionAvatar = .bryan

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            HStack(spacing: Theme.Space.sm) {
                if snapshot.dayStreak > 0 { streakChip }
                loggedChip
                Spacer(minLength: 0)
            }
            lastActiveRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Header — avatar + name + mood

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            // Mood-tinted monogram avatar (Theme tokens only).
            ZStack {
                Circle()
                    .fill(moodTint.opacity(0.18))
                    .frame(width: 46, height: 46)
                    .overlay(Circle().strokeBorder(moodTint.opacity(0.35), lineWidth: 1))
                pixelAvatar
                    .frame(width: 46, height: 50)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: snapshot.characterMood.systemImage)
                        .font(.caption)
                    Text(moodLine)
                        .font(.subheadline)
                }
                .foregroundStyle(moodTint)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Chips

    private var streakChip: some View {
        chip(
            text: "\(streakEmoji) \(snapshot.dayStreak)-day streak",
            tint: Theme.warning
        )
    }

    private var loggedChip: some View {
        chip(
            text: snapshot.loggedToday ? "logged today ✓" : "no log yet today",
            tint: snapshot.loggedToday ? Theme.positive : Theme.textSecondary
        )
    }

    private func chip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
            .foregroundStyle(tint)
            .lineLimit(1)
    }

    private var lastActiveRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
            Text("active \(relativeLastActive)")
                .font(.caption)
        }
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Derived

    /// The buddy's pixel character, scaled to sit on the mood-tinted disc (centered by
    /// `PixelArtView`'s content-centering, so it never sits lopsided).
    @ViewBuilder private var pixelAvatar: some View {
        Group {
            switch avatar {
            case .victoria: PixelVictoriaView(mood: .happy)
            case .bryan:    PixelBryanView(mood: .happy)
            }
        }
        .scaleEffect(0.34)
    }

    private var moodTint: Color {
        switch snapshot.characterMood {
        case .thriving: return Theme.brand
        case .happy:    return Theme.positive
        case .sleepy:   return Theme.info
        }
    }

    /// Warm phrasing for the mood (kinder than the raw enum label for `.sleepy`).
    private var moodLine: String {
        switch snapshot.characterMood {
        case .thriving: return "thriving"
        case .happy:    return "doing great"
        case .sleepy:   return "taking it easy"
        }
    }

    private var streakEmoji: String { snapshot.dayStreak >= 7 ? "🔥" : "🌱" }

    /// "2h ago", "just now", etc. — a soft, friendly relative time.
    private var relativeLastActive: String {
        let interval = Date.now.timeIntervalSince(snapshot.lastActive)
        if interval < 90 { return "just now" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: snapshot.lastActive, relativeTo: .now)
    }

    private var accessibilitySummary: String {
        var parts = ["\(snapshot.displayName), \(moodLine)"]
        if snapshot.dayStreak > 0 { parts.append("\(snapshot.dayStreak) day streak") }
        parts.append(snapshot.loggedToday ? "logged today" : "hasn't logged yet today")
        parts.append("active \(relativeLastActive)")
        return parts.joined(separator: ", ")
    }
}

#Preview("Buddy status — moods") {
    ZStack {
        Theme.background.ignoresSafeArea()
        VStack(spacing: Theme.Space.md) {
            BuddyStatusCard(snapshot: .init(ownerUserID: "b", displayName: "Bryan",
                                            dayStreak: 12, characterMood: .thriving,
                                            loggedToday: true,
                                            lastActive: Date.now.addingTimeInterval(-5400)))
            BuddyStatusCard(snapshot: .init(ownerUserID: "b", displayName: "Sam",
                                            dayStreak: 3, characterMood: .happy,
                                            loggedToday: true,
                                            lastActive: Date.now.addingTimeInterval(-60)))
            BuddyStatusCard(snapshot: .init(ownerUserID: "b", displayName: "Alex",
                                            dayStreak: 0, characterMood: .sleepy,
                                            loggedToday: false,
                                            lastActive: Date.now.addingTimeInterval(-86400)))
        }
        .padding()
    }
}
