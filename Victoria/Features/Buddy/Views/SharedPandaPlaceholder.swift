import SwiftUI

/// The SHARED character the two buddies keep thriving together — a PANDA.
///
/// **The core idea (made visible):** the panda needs BOTH people. When `me` + `buddy` are
/// supplied, the card shows a two-sided view — each person's pixel avatar flanks the panda
/// with a clear "logged ✓ / waiting" state — so it's unmistakable that *both* of you keep it
/// alive. (Pattern drawn from shared-streak/co-op-pet apps: two slots that must both fill.)
/// The panda blinks + breathes like the home-screen companion so it reads as *alive*.
///
/// **Tone contract:** the panda THRIVES when both logged today, is gently "okay" when one
/// of you has, and "sleepy" (waiting, not dead/punished) when neither has. Never sad,
/// scolding, or punitive — and the person who hasn't logged is never the subject of a
/// negative verb (the copy is about the *panda's* needs, future-facing).
struct SharedPandaPlaceholder: View {

    /// Combined state of the pair. `thriving`/`okay`/`sleepy` reflect TODAY's logging;
    /// `hungry`/`fainted` add stakes when the pair neglects logging for DAYS (computed from
    /// "last fed"). Never punitive in copy — always the panda's need + "one log revives it".
    enum CombinedState: Equatable {
        case thriving   // both logged today — the happy peak
        case okay       // one of you logged today — a warm middle
        case sleepy     // neither yet today, but recently fed — waiting, not unhappy
        case hungry     // a day or two with no logs — drooping, needs a check-in
        case fainted    // several days neglected — keeled over (X-eyes); any log revives it

        var accessory: String {
            switch self {
            case .thriving: return "✨"
            case .okay:     return "💛"
            case .sleepy:   return "💤"
            case .hungry:   return "🥺"
            case .fainted:  return "💫"
            }
        }
        var headline: String {
            switch self {
            case .thriving: return "You two are crushing it!"
            case .okay:     return "Doing alright together 💛"
            case .sleepy:   return "Waiting on a check-in 💤"
            case .hungry:   return "Your panda's getting hungry 🎋"
            case .fainted:  return "Your panda keeled over 💫"
            }
        }
        var subline: String {
            switch self {
            case .thriving: return "Both of you logged today — bamboo for everyone!"
            case .okay:     return "One of you logged today — a little nudge keeps you both going."
            case .sleepy:   return "Log something today to wake your panda up. No rush 💛"
            case .hungry:   return "A couple quiet days — one log brings it right back."
            case .fainted:  return "A few days with no logs and it fainted. Log once to revive it!"
            }
        }
        var tint: Color {
            switch self {
            case .thriving: return Theme.brand
            case .okay:     return Theme.positive
            case .sleepy:   return Theme.info
            case .hungry:   return Theme.warning
            case .fainted:  return Theme.textSecondary
            }
        }
        var pandaMood: PandaMood {
            switch self {
            case .thriving: return .thriving
            case .okay:     return .okay
            case .sleepy:   return .sleepy
            case .hungry:   return .hungry
            case .fainted:  return .fainted
            }
        }
    }

    /// One of the two people who keep the panda alive.
    struct Contributor {
        let avatar: CompanionAvatar
        let name: String
        let logged: Bool
    }

    var state: CombinedState
    /// When BOTH are supplied, the two-sided "you + buddy" view renders. Omit (nil) for the
    /// not-yet-linked empty state, which shows just the resting panda.
    var me: Contributor? = nil
    var buddy: Contributor? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false
    private let blinkTimer = Timer.publish(every: 3.6, on: .main, in: .common).autoconnect()
    /// Drives the "eat the bamboo" cycle (thriving only): looping 1 hold-low → 2 lift → 3 bite
    /// → 4 chew, so the paws carry the stalk to the mouth and it's chewed down. 0 = still frame.
    @State private var eatPhase = 0
    private let eatTimer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            if let me, let buddy {
                pairedStage(me: me, buddy: buddy)
            } else {
                pandaCore(size: 168)
            }

            VStack(spacing: 4) {
                Text(headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.sm)
        .onReceive(blinkTimer) { _ in doBlink() }
        .onReceive(eatTimer) { _ in
            guard !reduceMotion, state == .thriving else { return }
            withAnimation(.easeInOut(duration: 0.16)) { eatPhase = eatPhase >= 4 ? 1 : eatPhase + 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Two-sided "you + buddy" stage

    /// You on the left, the panda in the middle, your buddy on the right — each person's
    /// pixel avatar with a clear "logged / waiting" state, so it reads at a glance that the
    /// panda needs *both* of you.
    private func pairedStage(me: Contributor, buddy: Contributor) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.xs) {
            contributorColumn(me)
            pandaCore(size: 132)
                .layoutPriority(1)
            contributorColumn(buddy)
        }
        .frame(maxWidth: .infinity)
    }

    /// One person's avatar + name + a logged/waiting pip. The avatar's disc glows when they
    /// logged today and dims (with a gentle "waiting" pip) when they haven't — that empty
    /// side is the thing that draws the eye, never a shaming label.
    private func contributorColumn(_ c: Contributor) -> some View {
        let tint = c.logged ? Theme.positive : Theme.textSecondary
        return VStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(tint.opacity(c.logged ? 0.18 : 0.10))
                    .frame(width: 60, height: 60)
                    .overlay(Circle().strokeBorder(tint.opacity(c.logged ? 0.40 : 0.22), lineWidth: 1.5))

                miniAvatar(c.avatar)
                    .frame(width: 60, height: 66)

                // Status pip: a green check when they've logged, a soft hourglass while waiting.
                Image(systemName: c.logged ? "checkmark.circle.fill" : "hourglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(c.logged ? Theme.positive : Theme.textSecondary)
                    .background(Circle().fill(Theme.card).padding(-1))
                    .offset(x: 4, y: 2)
            }
            Text(c.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(c.logged ? "logged ✓" : "waiting")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 78)
        .opacity(c.logged ? 1 : 0.9)
    }

    /// A person's pixel character, scaled to sit on the avatar disc (not clipped — the
    /// sprite's transparent background lets the tinted disc show through). Centered thanks to
    /// `PixelArtView`'s content-centering, so it never sits lopsided in the disc.
    @ViewBuilder
    private func miniAvatar(_ avatar: CompanionAvatar) -> some View {
        Group {
            switch avatar {
            case .victoria: PixelVictoriaView(mood: .happy)
            case .bryan:    PixelBryanView(mood: .happy)
            }
        }
        .scaleEffect(0.44)
    }

    // MARK: - Panda core (glow + concentric habitat + the live, blinking panda)

    /// The panda on a soft halo + a concentric tinted "habitat" disc. A circle (not a rect)
    /// so it always reads as a clean spotlight behind the centered panda. Breathes when
    /// thriving, blinks on the shared timer — alive like the home-screen companion.
    private func pandaCore(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [state.tint.opacity(0.22), state.tint.opacity(0.05), .clear],
                        center: .center, startRadius: 4, endRadius: size * 0.6)
                )
                .frame(width: size, height: size)

            Circle()
                .fill(state.tint.opacity(0.10))
                .overlay(Circle().strokeBorder(state.tint.opacity(0.22), lineWidth: 1))
                .frame(width: size * 0.82, height: size * 0.82)

            PixelPandaView(mood: state.pandaMood, eyesOpen: !blink, eatPhase: eatPhase)
                .frame(width: size, height: size)
                .modifier(PandaLiveness(state: state, reduceMotion: reduceMotion))
                .overlay(alignment: .topTrailing) {
                    Text(state.accessory)
                        .font(.system(size: size * 0.17))
                        .offset(x: -size * 0.07, y: size * 0.06)
                        .popIn(true)
                }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: state)
    }

    // MARK: - Copy (names who's missing, never shames)

    /// Personalized, future-facing copy when we know both people's state; otherwise the
    /// state's generic warm lines.
    private var headline: String {
        // Hungry/fainted are about the panda's CONDITION (days neglected), not today's split.
        if state == .hungry || state == .fainted { return state.headline }
        guard let me, let buddy else { return state.headline }
        switch (me.logged, buddy.logged) {
        case (true, true):   return "You're both crushing it! 🎋"
        case (true, false):  return "You did your part 💛"
        case (false, true):  return "\(buddy.name) showed up! 🐼"
        case (false, false): return "Your panda's having a sleepy day 💤"
        }
    }
    private var subline: String {
        if state == .hungry || state == .fainted { return state.subline }
        guard let me, let buddy else { return state.subline }
        switch (me.logged, buddy.logged) {
        case (true, true):   return "Both of you logged today — the panda is thriving."
        case (true, false):  return "Waiting on \(buddy.name) to log — give them a nudge?"
        case (false, true):  return "Log today to keep your panda thriving together."
        case (false, false): return "When you both log, it perks right up. No rush 💛"
        }
    }

    private var accessibilityText: String {
        guard let me, let buddy else { return "Your shared panda. \(state.headline) \(state.subline)" }
        let meS = me.logged ? "you logged today" : "you haven't logged yet"
        let buS = buddy.logged ? "\(buddy.name) logged today" : "\(buddy.name) hasn't logged yet"
        return "Your shared panda. \(meS); \(buS). \(headline) \(subline)"
    }

    // MARK: - Blink

    private func doBlink() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.08)) { blink = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeInOut(duration: 0.12)) { blink = false }
        }
    }
}

/// Liveness for the panda: breathes when thriving (alive + happy), a slow wiggle when okay,
/// and holds still when sleepy. Respects Reduce Motion via the passed flag.
private struct PandaLiveness: ViewModifier {
    let state: SharedPandaPlaceholder.CombinedState
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        switch state {
        case .thriving: AnyView(content.breathing())
        case .okay:     AnyView(content.wiggle(true))
        case .sleepy:   AnyView(content)
        case .hungry:   AnyView(content.breathing())   // slow, alive-but-tired
        case .fainted:  AnyView(content.opacity(0.9))  // out cold — still + faded
        }
    }
}

#Preview("Shared panda — paired states") {
    ZStack {
        Theme.background.ignoresSafeArea()
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                SharedPandaPlaceholder(
                    state: .thriving,
                    me: .init(avatar: .victoria, name: "You", logged: true),
                    buddy: .init(avatar: .bryan, name: "Bryan", logged: true))
                SharedPandaPlaceholder(
                    state: .okay,
                    me: .init(avatar: .victoria, name: "You", logged: true),
                    buddy: .init(avatar: .bryan, name: "Bryan", logged: false))
                SharedPandaPlaceholder(state: .sleepy)
            }
            .padding()
        }
    }
}
