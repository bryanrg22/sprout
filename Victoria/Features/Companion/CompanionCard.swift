import SwiftUI
import Combine

/// The little companion, rendered as a card for the dashboard (and reusable on a
/// dedicated tab). The caller passes *today's running totals*; this view computes
/// the matching targets from the profile and asks `CompanionEngine` how the buddy
/// feels, then renders an adorable, on-theme creature that reflects it.
///
/// Health-positive by design (see `CompanionEngine`): the buddy thrives when she's
/// eaten enough + balanced + hydrated, and only ever gets sleepy/hungry — never
/// scolding, never reacting to eating "too much".
///
/// The creature is built entirely from SF Symbols + shapes (no image assets) so it
/// drops in with zero asset wiring. The face (eyes, cheeks, mouth, sparkle) is
/// hand-assembled from shapes so Sprout can *blink* and beam; the engine's mood
/// glyphs still drive the floating aura + a little held accent, so the engine stays
/// the single source of mood truth.
// TODO: swap in pixel-art of Victoria's companion (replace `creature` below).
struct CompanionCard: View {
    let profile: UserProfile
    let caloriesEaten: Double
    let protein: Double
    let waterOz: Double
    /// The weight the dashboard computes its targets from (trend, else start weight, else 150).
    /// Nil only in previews, which have no weigh-ins.
    let basisWeightLbs: Double?

    /// - Parameters:
    ///   - profile: the user profile (supplies name + targets).
    ///   - caloriesEaten: kcal logged so far today.
    ///   - protein: grams of protein logged today.
    ///   - waterOz: fluid ounces of water logged today.
    ///   - basisWeightLbs: the dashboard's basis weight, so the companion and the ring agree.
    init(profile: UserProfile, caloriesEaten: Double, protein: Double, waterOz: Double,
         basisWeightLbs: Double? = nil) {
        self.profile = profile
        self.caloriesEaten = caloriesEaten
        self.protein = protein
        self.waterOz = waterOz
        self.basisWeightLbs = basisWeightLbs
    }

    // MARK: Life / animation state

    /// Springs the whole buddy in the first time the card appears.
    @State private var appeared = false
    /// Drives the eye-blink: flips briefly closed on a gentle timer.
    @State private var blink = false
    /// Bumped once when she (re)enters the `thriving` state, to fire one confetti burst.
    @State private var celebrateTrigger = 0
    /// Tracks the last mood we saw so we only celebrate on the *transition* into thriving.
    @State private var lastMood: CompanionMood?

    // MARK: Tap-to-talk
    /// The catchphrase currently shown in the companion's speech bubble. Tap the
    /// companion and she blurts one of her lines (her own vocabulary — see
    /// `CompanionPhrases`); it lingers ~5s then fades.
    @State private var speech: String?
    /// Supersedes the previous auto-hide timer whenever she's tapped again, so a
    /// fresh tap restarts the 5s window instead of an old timer cutting it short.
    @State private var speechToken = 0
    /// A light haptic on each tap.
    @State private var talkTrigger = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slow, friendly blink loop. ~ once every few seconds, with an occasional
    /// double-blink feel from the short close interval.
    private let blinkTimer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()

    // MARK: Targets (the dashboard's, not a second computation)
    //
    // The companion's "enough food" and the calorie ring are the same judgement, so they use
    // the same basis weight. This card used the START weight, which drifts from the trend as
    // soon as she makes progress (`CompanionTargets`).
    private var targets: CompanionTargets {
        CompanionTargets(profile: profile, basisWeightLbs: basisWeightLbs)
    }
    private var calorieTarget: Double { targets.calories }
    private var proteinTarget: Double { targets.proteinG }
    private var waterTarget: Double { profile.waterTargetOz }

    /// "Has she logged anything today?" — any fuel or water counts.
    private var loggedToday: Bool {
        caloriesEaten > 0 || protein > 0 || waterOz > 0
    }

    private var state: CompanionState {
        CompanionEngine.evaluate(caloriesEaten: caloriesEaten,
                                 calorieTarget: calorieTarget,
                                 protein: protein,
                                 proteinTarget: proteinTarget,
                                 waterOz: waterOz,
                                 waterTargetOz: waterTarget,
                                 loggedToday: loggedToday)
    }

    /// She wiggles with delight whenever she's in one of her best moods.
    private var isJoyful: Bool { state.mood == .thriving || state.mood == .happy }

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            header
            creature
                // Tap her to hear one of her lines (her own voice). A separate gesture
                // from the card's long-press "Ask Vita", so both coexist.
                .contentShape(Rectangle())
                .onTapGesture { talk() }
                .overlay(alignment: .top) { speechBubble }
                .sensoryFeedback(.impact(weight: .light), trigger: talkTrigger)
            message
            needsRow
        }
        .frame(maxWidth: .infinity)
        .cardElevated(padding: Theme.Space.lg)
        // One spring drives every mood-dependent change (face, color, halo) so the
        // whole buddy reacts together when her totals tick over a threshold.
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.mood)
        // The whole card squishes when tapped — Sprout loves the attention.
        .bouncyPress()
        // Springy entrance the first time she shows up.
        .popIn(appeared)
        .onAppear {
            appeared = true
            // If she's already thriving when the card first appears, give one
            // welcome burst (handled by syncCelebration via lastMood == nil).
            syncCelebration()
        }
        .onChange(of: state.mood) { _, _ in syncCelebration() }
        .onReceive(blinkTimer) { _ in doBlink() }
        .fontDesign(.rounded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.companionName) is \(state.mood.label.lowercased()). \(state.message)")
    }

    /// Fire a single, tasteful confetti burst when she first reaches `thriving`.
    /// We compare against the last mood so it only pops on the *transition* in,
    /// never repeatedly while she stays thriving.
    private func syncCelebration() {
        let previous = lastMood
        lastMood = state.mood
        guard state.mood == .thriving else { return }
        // Celebrate on the way in (or on a fresh appear into thriving), not on
        // every recompute while already glowing.
        if previous != .thriving { celebrateTrigger += 1 }
    }

    /// Briefly close the eyes, then open them again.
    private func doBlink() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.09)) { blink = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            withAnimation(.easeInOut(duration: 0.12)) { blink = false }
        }
    }

    /// Tap-to-talk: blurt a random line in her voice, hold it ~5s, then fade. A new
    /// tap supersedes the prior timer (via `speechToken`) so re-tapping restarts the
    /// window and swaps the line. Random each time, never the same line twice in a row.
    private func talk() {
        let phrase = CompanionPhrases.random(for: profile.companionAvatar, excluding: speech)
        talkTrigger += 1
        speechToken += 1
        let token = speechToken
        withAnimation(.spring(response: 0.34, dampingFraction: 0.6)) { speech = phrase }
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                guard speechToken == token else { return }   // a newer tap owns the bubble
                withAnimation(.easeOut(duration: 0.3)) { speech = nil }
            }
        }
    }

    /// The floating speech bubble above her head (only while a line is showing).
    @ViewBuilder private var speechBubble: some View {
        if let speech {
            SpeechBubble(text: speech)
                .id(speech)   // re-pop when the line changes on a quick re-tap
                .offset(y: -2)
                .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: Header — name + mood label pill
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(profile.companionName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            moodPill
        }
    }

    private var moodPill: some View {
        HStack(spacing: 5) {
            Image(systemName: state.mood.auraSymbol)
                .symbolRenderingMode(.hierarchical)
                // The aura glyph gives a tiny bounce-in whenever the mood flips.
                .id(state.mood)
                .transition(.scale.combined(with: .opacity))
            Text(state.mood.label)
                .fontWeight(.bold)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(state.mood.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(state.mood.accent.opacity(0.16))
        )
        .overlay(
            Capsule().strokeBorder(state.mood.accent.opacity(0.34), lineWidth: 1)
        )
        // A soft glow so the pill feels like a happy little badge.
        .shadow(color: state.mood.accent.opacity(0.28), radius: 6, y: 1)
    }

    // MARK: Creature — SF Symbols + shapes only
    //
    // Sprout is the star, so she's BIG and soft: a glowing vitality halo, a round
    // squishy body in a soft tint of the mood color, two bouncy ears, little side
    // arms, rosy cheeks, expressive eyes that blink, and a mouth that matches the
    // mood. The engine's aura glyph floats beside her as a sparkle/heart accent.
    private var creature: some View {
        ZStack {
            // Soft dreamy glow behind the buddy, tinted by mood — bigger + warmer.
            Circle()
                .fill(state.mood.accent.opacity(0.22))
                .frame(width: 168, height: 168)
                .blur(radius: 26)

            // Vitality halo — how fuelled she is overall (average of the needs).
            // A faint inner companion ring adds a little extra "energy" depth.
            ZStack {
                Circle()
                    .stroke(state.mood.accent.opacity(0.10), lineWidth: 2)
                    .frame(width: 162, height: 162)
                ProgressRing(progress: state.vitality,
                             lineWidth: 9,
                             color: state.mood.accent,
                             track: Color.white.opacity(0.07))
                    .frame(width: 150, height: 150)
            }

            // Idle "alive" breathing on every state, with the shared-kit delight
            // wiggle layered on ONLY when she's joyful (the kit's wiggle rests at a
            // slight tilt when inactive, so calmer moods skip it and stay upright).
            Group {
                if isJoyful {
                    companionBody.wiggle(true)
                } else {
                    companionBody
                }
            }
            .breathing()

            // Floating aura glyph (sparkle / heart / leaf / zzz / drop) from the
            // engine — keeps the engine as the source of mood truth and adds a
            // cute, mood-amplifying accent that gently breathes on its own.
            Image(systemName: state.mood.auraSymbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(state.mood.accent)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: state.mood.accent.opacity(0.5), radius: 6)
                .offset(x: 64, y: -60)
                .breathing()
                .transition(.scale.combined(with: .opacity))
                .id("aura-\(state.mood.rawValue)")

            // One tasteful celebration burst on reaching the reward state.
            ConfettiBurst(trigger: celebrateTrigger)
                .frame(width: 200, height: 200)
                .allowsHitTesting(false)
        }
        .frame(height: 184)
    }

    /// The companion character: **pixel-art Victoria** (her long dark hair, thin
    /// glasses, warm smile), with her expression reflecting the mood while the
    /// surrounding vitality ring / halo / aura carry the mood *color* — so she
    /// always looks like herself, never recolored. Blinks on the shared timer.
    ///
    /// (Sprout — the shape-built creature in `sproutBody` below — is kept for a
    /// future per-user companion toggle, e.g. Bryan's own character.)
    private var companionBody: some View {
        let open = !blink && state.mood != .sleepy
        return Group {
            switch profile.companionAvatar {
            case .bryan:    PixelBryanView(mood: state.mood, eyesOpen: open)
            case .victoria: PixelVictoriaView(mood: state.mood, eyesOpen: open)
            // One image whatever the mood or blink (version 1); the ring, halo and aura
            // around it still carry the mood. Same 120×144 box as the grid characters.
            case .custom:   CustomCompanionImage(png: profile.customAvatarPNG)
                                .frame(width: 120, height: 144)
            }
        }
    }

    /// Sprout's body: a round, squishy squircle with ears, arms, face, and cheeks.
    private var sproutBody: some View {
        RoundedRectangle(cornerRadius: 46, style: .continuous)
            .fill(
                LinearGradient(colors: [state.mood.accent.opacity(0.34),
                                        state.mood.accent.opacity(0.16)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 116, height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .strokeBorder(state.mood.accent.opacity(0.5), lineWidth: 2)
            )
            // A soft top highlight makes the body read as round/glossy.
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 54, height: 22)
                    .blur(radius: 6)
                    .offset(y: 14)
            }
            // Ears / antennae peeking above.
            .overlay(alignment: .top) { ears }
            // Little arms on each side.
            .overlay { arms }
            // The expressive face (eyes + cheeks + mouth).
            .overlay { face }
            .shadow(color: state.mood.accent.opacity(0.4), radius: 16, y: 4)
    }

    /// Two rounded "ears" peeking above the body, tipped with a soft highlight.
    private var ears: some View {
        HStack(spacing: 44) {
            ear
            ear
        }
        .offset(y: -16)
    }

    private var ear: some View {
        Capsule()
            .fill(
                LinearGradient(colors: [state.mood.accent.opacity(0.6),
                                        state.mood.accent.opacity(0.4)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 15, height: 26)
            .overlay(
                Capsule().strokeBorder(state.mood.accent.opacity(0.5), lineWidth: 1.5)
            )
    }

    /// Two tiny side arms — when she's joyful they tilt up in a little cheer.
    private var arms: some View {
        HStack {
            Capsule()
                .fill(state.mood.accent.opacity(0.5))
                .frame(width: 22, height: 11)
                .rotationEffect(.degrees(isJoyful ? -28 : -8))
                .offset(x: -8)
            Spacer()
            Capsule()
                .fill(state.mood.accent.opacity(0.5))
                .frame(width: 22, height: 11)
                .rotationEffect(.degrees(isJoyful ? 28 : 8))
                .offset(x: 8)
        }
        .frame(width: 132)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isJoyful)
    }

    // MARK: Face — hand-built so she can blink + beam
    //
    // Eyes are big rounded "pills"; blinking squashes them to a thin line. A small
    // sparkle sits over one eye when she's thriving. Rosy cheeks + a mood-matched
    // mouth finish the expression.
    private var face: some View {
        VStack(spacing: 7) {
            // Eyes (with cheeks flanking them).
            HStack(spacing: 12) {
                cheek
                eye
                eye
                cheek
            }
            mouth
        }
        .offset(y: 6)
    }

    /// One eye. A tall rounded capsule that squashes flat on a blink. Sleepy/hungry
    /// moods get softly half-lidded, lower-energy eyes; her best moods get a shine.
    private var eye: some View {
        let isLowEnergy = state.mood == .sleepy || state.mood == .hungry
        let openHeight: CGFloat = isLowEnergy ? 11 : 16
        return Capsule(style: .continuous)
            .fill(Theme.background.opacity(0.92))
            .frame(width: 12, height: blink ? 2.5 : openHeight)
            .overlay(alignment: .topTrailing) {
                // A little catch-light so the eyes look glossy + alive.
                Circle()
                    .fill(Color.white.opacity(blink ? 0 : 0.9))
                    .frame(width: 4, height: 4)
                    .offset(x: -1.5, y: 2.5)
            }
            .overlay(alignment: .topLeading) {
                // Extra sparkle on one eye while thriving (overlaid on each eye;
                // tiny + soft so it reads as a happy glint, not clutter).
                if state.mood == .thriving {
                    Image(systemName: "sparkle")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(blink ? 0 : 0.95)
                        .offset(x: -3, y: -4)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: blink)
    }

    /// A soft rosy cheek dot — pure cuteness. A gentle pink that still sits on theme.
    private var cheek: some View {
        Circle()
            .fill(
                RadialGradient(colors: [cheekColor.opacity(0.85), cheekColor.opacity(0.0)],
                               center: .center, startRadius: 0, endRadius: 8)
            )
            .frame(width: 14, height: 14)
            .offset(y: 4)
    }

    /// Warm cheek tint: a friendly pink, leaning into her mood accent a touch.
    private var cheekColor: Color {
        // Theme.fat is a soft violet/pink (0xC78BFF) — derived from the palette,
        // gives Sprout rosy cheeks without inventing a new token.
        state.mood == .hungry ? Theme.warning : Theme.fat
    }

    /// A mood-matched mouth built from shapes:
    /// • thriving/happy → a big open beaming smile
    /// • content → a gentle closed smile
    /// • sleepy → a tiny calm "o"
    /// • hungry → a small soft wobble (kind, never a frown)
    private var mouth: some View {
        Group {
            switch state.mood {
            case .thriving, .happy:
                // Big open beaming grin: a flat-topped half-disc (a "smile bowl"),
                // with a little tongue clipped neatly inside it.
                OpenSmile()
                    .fill(Theme.background.opacity(0.9))
                    .frame(width: 24, height: 13)
                    .overlay {
                        // Little pink tongue, clipped to the mouth so it never spills.
                        Capsule()
                            .fill(Theme.fat.opacity(0.75))
                            .frame(width: 12, height: 7)
                            .offset(y: 5)
                            .clipShape(OpenSmile())
                    }
            case .content:
                // Gentle closed smile.
                SmileArc()
                    .stroke(Theme.background.opacity(0.85),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 22, height: 11)
            case .sleepy:
                // Calm tiny mouth.
                Circle()
                    .fill(Theme.background.opacity(0.8))
                    .frame(width: 7, height: 7)
            case .hungry:
                // Soft small wobble — a kind "feed me", never a frown.
                SmileArc()
                    .stroke(Theme.background.opacity(0.8),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 16, height: 7)
            }
        }
        .frame(height: 14)
    }

    // MARK: Message — the buddy's one-liner
    private var message: some View {
        Text(state.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            // Cross-fade + a little rise when the line changes with the mood.
            .id(state.message)
            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity))
    }

    // MARK: Needs row — three little pips (food / protein / water)
    private var needsRow: some View {
        HStack(spacing: Theme.Space.md) {
            ForEach(state.needs) { need in
                NeedPip(need: need)
            }
        }
    }
}

/// A gentle upward smile arc (a shallow bowl) used for closed-mouth expressions.
private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.maxY * 1.4))
        return p
    }
}

/// A big open grin: a flat top edge with a rounded bottom (a "smile bowl"). Filled,
/// this reads as a happy open mouth; it also doubles as a clip shape for the tongue.
private struct OpenSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Sweep the bottom as a curve down and back for a rounded grin.
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.maxY * 2.0))
        p.closeSubpath()
        return p
    }
}

/// A small, tappable-looking "need" indicator: a tinted ring filling toward met,
/// with its icon at center and a percentage underneath. Filled/bright when the
/// need is met, dimmer (but never red/alarming) when it still wants attention.
/// Pops a tiny "met!" star and springs up a touch the moment a need fills.
private struct NeedPip: View {
    let need: CompanionNeed

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressRing(progress: need.fraction,
                             lineWidth: 5,
                             color: need.tint,
                             track: Color.white.opacity(0.07))
                    .frame(width: 44, height: 44)
                Image(systemName: need.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(need.isMet ? need.tint : need.tint.opacity(0.55))
                    .symbolRenderingMode(.hierarchical)
                // A tiny celebratory star pops in at the corner once the need is met.
                if need.isMet {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(need.tint)
                        .offset(x: 17, y: -17)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // A gentle lift + glow when this need is satisfied.
            .scaleEffect(need.isMet ? 1.06 : 1.0)
            .shadow(color: need.tint.opacity(need.isMet ? 0.35 : 0), radius: 6)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: need.isMet)

            Text("\(Int((need.rawFraction * 100).rounded()))%")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(need.isMet ? need.tint : Theme.textSecondary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(need.label) \(Int((need.rawFraction * 100).rounded())) percent")
    }
}

/// A cute speech bubble that floats above the companion when she's tapped — a rounded
/// pill with a little downward tail, so a tapped line reads as *her* talking.
private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.bold))
            .fontDesign(.rounded)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous).fill(Theme.cardRaised)
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(Theme.brand.opacity(0.28), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                // Little tail pointing down toward her head.
                BubbleTail()
                    .fill(Theme.cardRaised)
                    .frame(width: 14, height: 8)
                    .offset(y: 6)
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            .fixedSize()
    }
}

/// A small downward-pointing triangle — the speech bubble's tail.
private struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))   // apex at bottom center
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

#if DEBUG
#Preview("Companion moods") {
    // Lightweight in-memory profile for the canvas; targets compute from it.
    let profile: UserProfile = {
        let p = UserProfile()
        p.companionName = "Sprout"
        p.startWeightLbs = 150
        return p
    }()

    return ScrollView {
        VStack(spacing: Theme.Space.md) {
            // Thriving (well-fed + protein + hydrated)
            CompanionCard(profile: profile, caloriesEaten: 1700, protein: 110, waterOz: 70)
            // Content / sleepy (light day)
            CompanionCard(profile: profile, caloriesEaten: 800, protein: 30, waterOz: 16)
            // Hungry (under-eating — the gentle nudge)
            CompanionCard(profile: profile, caloriesEaten: 350, protein: 10, waterOz: 8)
            // Nothing logged yet
            CompanionCard(profile: profile, caloriesEaten: 0, protein: 0, waterOz: 0)
        }
        .padding()
    }
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
#endif

/// The calorie and protein targets the companion reacts to: the profile's targets at the
/// dashboard's basis weight. Without a basis weight (a preview) the start weight stands in.
struct CompanionTargets: Equatable {
    let calories: Double
    let proteinG: Double

    init(profile: UserProfile, basisWeightLbs: Double?) {
        let basis = basisWeightLbs ?? profile.currentWeightLbs(latestLogged: nil)
        calories = profile.dailyCalorieTarget(weightLbs: basis)
        proteinG = profile.macroTargets(weightLbs: basis).proteinG
    }
}
