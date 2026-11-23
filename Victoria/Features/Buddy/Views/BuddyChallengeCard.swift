import SwiftUI

/// Playful, **kind**, activity-based prompts for the linked Buddy hub — the "friendly
/// rivalry" layer. They turn the buddy's SAFE activity (movement / steps) + my own into a
/// little spark: *"Bryan hit the gym today — your turn? 💪"*, *"you're winning the step
/// race today 👟"*.
///
/// ## Hard tone rules (see `RESEARCH_social.md`)
/// - **Encouragement + light rivalry, NEVER guilt.** A prompt celebrates someone showing up
///   or invites moving together; it never says "you're behind", "you skipped", or surfaces a
///   raw "X vs Y". Movement is a "showed up" flag; steps are compared only as **% of each
///   person's OWN goal** so it's fair across bodies/fitness.
/// - **Activity only** — steps 👟 / water 💧 / gym 💪. Never weight or calories.
/// - **Tapping a prompt sends a warm nudge from me to my buddy** (human-framed, opt-in), or
///   simply cheers — it never auto-fires and never scolds either of us.
///
/// These are derived purely from the values the hub already has, so they cost nothing extra
/// to compute and stay perfectly in sync with the face-off.
struct BuddyChallengeCard: View {
    let prompt: BuddyChallengePrompt
    /// Sends the prompt's pre-filled encouraging note to the buddy (routed via the VM).
    var onSend: (String, NudgeKind) -> Void

    @State private var sent = false
    @State private var tapPulse = 0

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            // Same soft tinted disc as the nudge rail + inbox, holding the prompt's emoji, so
            // the friendly-nudge card reads as part of the one cohesive Buddy set.
            NudgeIconDisc(emoji: prompt.emoji, tint: prompt.tint, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(prompt.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.sm)

            Button {
                tapPulse &+= 1
                onSend(prompt.message, prompt.nudgeKind)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { sent = true }
            } label: {
                Label(sent ? "Sent!" : prompt.actionLabel,
                      systemImage: sent ? "checkmark" : prompt.actionIcon)
                    .font(.caption.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.horizontal, Theme.Space.sm + 2)
                    .padding(.vertical, 8)
                    .background(prompt.tint.opacity(sent ? 0.18 : 0.22), in: Capsule())
                    .overlay(Capsule().strokeBorder(prompt.tint.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(prompt.tint)
            }
            .buttonStyle(.plain)
            .bouncyPress()
            .sensoryFeedback(.success, trigger: tapPulse)
            .disabled(sent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(prompt.tint.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(prompt.tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prompt.title). \(prompt.subtitle)")
        .accessibilityHint(sent ? "Sent" : "Double tap to \(prompt.actionLabel.lowercased())")
    }
}

// MARK: - The prompt model

/// One playful, kind prompt. Carries its copy + the warm note it pre-fills when tapped.
struct BuddyChallengePrompt: Identifiable, Equatable {
    enum Flavor: String { case nudgeThem, theirMove, myStepLead, bothMoved, cheerOn }

    let flavor: Flavor
    let emoji: String
    let title: String
    let subtitle: String
    /// The pre-filled, encouraging note sent to the buddy when the action is tapped.
    let message: String
    /// Health-POSITIVE intent for the sent nudge (icon/label in the buddy's inbox).
    let nudgeKind: NudgeKind
    let actionLabel: String
    let actionIcon: String

    var id: Flavor { flavor }

    var tint: Color {
        switch flavor {
        case .nudgeThem:  return Theme.warning     // a friendly "they haven't checked in" poke
        case .theirMove:  return Theme.positive   // movement
        case .myStepLead: return Theme.brand       // steps / "winning"
        case .bothMoved:  return Theme.brand
        case .cheerOn:    return Theme.info
        }
    }
}

// MARK: - Derivation (pure, testable, fair, kind)

/// Builds the (at most a couple of) prompts that apply RIGHT NOW from the SAFE activity the
/// hub already holds — mine + the buddy snapshot. All comparisons are framed kindly and use
/// **% of each person's OWN goal** for steps (never raw counts); gym is a "showed up" flag.
///
/// Order = priority; the hub shows the top one or two so it never becomes a wall of cards.
enum BuddyChallenges {

    /// - Parameters:
    ///   - myStepFraction:    my steps as a fraction of MY OWN goal (clamped 0...1), or `nil`
    ///                        if I have no step goal set (then no step-race prompt).
    ///   - theirStepFraction: buddy's steps as a fraction of THEIR OWN goal, or `nil`.
    ///   - myWorkedOut/theirWorkedOut: simple "moved today" flags.
    ///   - buddyName:         the buddy's display name for warm, personal copy.
    static func prompts(myStepFraction: Double?,
                        theirStepFraction: Double?,
                        myWorkedOut: Bool,
                        theirWorkedOut: Bool,
                        myLoggedToday: Bool,
                        theirLoggedToday: Bool,
                        buddyName: String) -> [BuddyChallengePrompt] {
        let name = buddyName.isEmpty ? "Your buddy" : buddyName
        var out: [BuddyChallengePrompt] = []

        // (0) Buddy hasn't checked in today → a friendly NUDGE. This is the heart of being an
        //     accountability buddy: a warm poke to THEM (never shaming her). Top priority.
        if !theirLoggedToday {
            out.append(BuddyChallengePrompt(
                flavor: .nudgeThem,
                emoji: "👋",
                title: "\(name) hasn't checked in yet 👋",
                subtitle: myLoggedToday
                    ? "You're already in — give them a friendly nudge to keep your panda thriving."
                    : "A little nudge keeps you both going — send one their way?",
                message: "Hey! 👋 Don't forget to log today — let's keep our panda (and our streak) going 🐼",
                nudgeKind: .checkIn,
                actionLabel: "Nudge \(name)",
                actionIcon: "hand.wave.fill"))
        }

        // (1) Buddy moved today and I haven't → a gentle "your turn?" INVITATION (never guilt).
        if theirWorkedOut && !myWorkedOut {
            out.append(BuddyChallengePrompt(
                flavor: .theirMove,
                emoji: "💪",
                title: "\(name) hit the gym today — your turn? 💪",
                subtitle: "No pressure at all. Cheer them on, then move a little when you're ready 💛",
                message: "Saw you got your workout in — amazing! 💪 You've inspired me, I'm gonna move too.",
                nudgeKind: .letsMove,
                actionLabel: "Cheer + join",
                actionIcon: "figure.walk.motion"))
        }

        // (2) We BOTH moved today → celebrate the duo (pure positive reinforcement).
        if theirWorkedOut && myWorkedOut {
            out.append(BuddyChallengePrompt(
                flavor: .bothMoved,
                emoji: "🎉",
                title: "You both moved today! 🎉",
                subtitle: "Two for two — send \(name) a little high-five 🙌",
                message: "We both got moving today — go us! 🙌",
                nudgeKind: .flex,
                actionLabel: "High-five",
                actionIcon: "hands.clap.fill"))
        }

        // (3) I'm clearly ahead on steps (vs each of our OWN goals) → playful "step race" win.
        //     Requires a real lead (≥ 10 pts of own-goal progress) so it's never a hair-split
        //     and never reads as shaming a close or trailing buddy.
        if let mine = myStepFraction, let theirs = theirStepFraction, mine - theirs >= 0.10 {
            out.append(BuddyChallengePrompt(
                flavor: .myStepLead,
                emoji: "👟",
                title: "You're winning the step race today 👟",
                subtitle: "You're ahead on your goal — send \(name) some friendly motivation 😄",
                message: "I'm ahead on steps today 😄 catch me if you can — you've got this! 👟",
                nudgeKind: .cheer,
                actionLabel: "Send a cheer",
                actionIcon: "hands.clap.fill"))
        }

        // (4) Fallback so the rivalry corner is never empty *and* never shaming: a plain warm
        //     cheer. Shown only when nothing above fired (e.g. buddy hasn't moved yet — we do
        //     NOT call that out; we just offer a kind cheer instead).
        if out.isEmpty {
            out.append(BuddyChallengePrompt(
                flavor: .cheerOn,
                emoji: "💛",
                title: "Spark a little friendly rivalry 💛",
                subtitle: "Send \(name) a cheer to get you both moving today",
                message: "Let's both get a little movement in today — I'm in if you are! 🚶💛",
                nudgeKind: .letsMove,
                actionLabel: "Cheer",
                actionIcon: "hands.clap.fill"))
        }

        // Keep it light: at most two prompts at a time, in priority order.
        return Array(out.prefix(2))
    }
}

#if DEBUG
#Preview("Buddy challenge cards") {
    ZStack {
        Theme.background.ignoresSafeArea()
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                ForEach(BuddyChallenges.prompts(
                    myStepFraction: 0.9, theirStepFraction: 0.5,
                    myWorkedOut: false, theirWorkedOut: true,
                    myLoggedToday: true, theirLoggedToday: false,
                    buddyName: "Sam")) { p in
                        BuddyChallengeCard(prompt: p) { _, _ in }
                }
                ForEach(BuddyChallenges.prompts(
                    myStepFraction: 0.4, theirStepFraction: 0.4,
                    myWorkedOut: true, theirWorkedOut: true,
                    myLoggedToday: true, theirLoggedToday: true,
                    buddyName: "Alex")) { p in
                        BuddyChallengeCard(prompt: p) { _, _ in }
                }
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
