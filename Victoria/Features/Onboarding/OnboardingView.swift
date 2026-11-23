import SwiftUI
import SwiftData
import Charts
import UIKit

/// Warm, conversational onboarding — Victoria's first impression of Vita.
///
/// This is deliberately NOT a clinical intake form. It reads like a caring coach
/// talking *with* her: Vita introduces herself, asks what she's *hoping for* (a
/// feeling, not a number), teaches a few genuinely-helpful, ADDITIVE habits before any
/// numbers appear, gathers the essentials gently ("only if you're comfortable"), gives
/// her room to share context in her own words, then puts together a kind plan and
/// closes with a personal note.
///
/// ED-safe by design (the app is built for people more likely to under-eat than over-eat):
/// the deficit/surplus is already baked into the computed TARGET, so the whole job is
/// to eat UP TO the target — never under. Nothing here says "eat less", implies a
/// weight-loss *speed*, or leads with a calorie number or goal weight. We LEAD with
/// eating ENOUGH. (See RESEARCH_onboarding.md.)
///
/// All of the original data collection, the `GoalPace.Direction` logic, lose/maintain/
/// gain behavior, and `finish()` persistence are preserved exactly — the coach voice,
/// the education step, the free-text note, and Vita's closing message are ADDITIVE.
/// Colors come only from `Theme.*`, so the screen inherits the active skin (onboarding
/// defaults to the warm `.cute` pastel skin; see RootView).
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var existing: UserProfile?

    // ─────────────────────────────────────────────────────────────────────────
    // ✏️  BRYAN — WRITE YOUR PERSONAL NOTE TO VICTORIA HERE.
    // This is the FIRST screen she sees when she opens the app. Replace the text
    // below with your own words (keep the triple quotes). Line breaks are fine.
    // ─────────────────────────────────────────────────────────────────────────
    private let bryanNote = """
    Hola Victoria, welcome to my app! I hope the design is cute enough for you and the application is actually helpful, because I spent a long time making sure that there are no bugs, that everything looks just perfect and works perfectly and seems perfect. And if there is anything you would like for me to add, I'm just one Claude Code prompt away!

    Also — ironically, I ended up liking the app while building it so much that I'll also be using it for myself as well. So you'll notice that I added a few little unexpected features that are interesting and hopefully will motivate both of us for both our goals this summer.

    Now, for the real plan: let's go beat that motherfucker Alejandro, so we can spend that $200 on another flight for you to come to SF instead. LOL :) Now go have fun using Sprout! Luv u lots! <3
    """

    /// DEBUG: `--onboard-step N` jumps straight to a step for screenshots; 0 in normal use.
    static var initialStep: Int {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--onboard-step"),
           i + 1 < CommandLine.arguments.count, let n = Int(CommandLine.arguments[i + 1]) { return n }
        #endif
        return 0
    }
    /// DEBUG: `--onboard-look cool` runs onboarding in the dark skin with that look picked,
    /// for screenshots; nil in normal use (onboarding runs in the default skin).
    static var debugLook: ThemeStyle? {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--onboard-look"),
           i + 1 < CommandLine.arguments.count { return ThemeStyle(rawValue: CommandLine.arguments[i + 1]) }
        #endif
        return nil
    }
    @State private var page = OnboardingView.initialStep
    @State private var startTrigger = false
    @State private var appeared = false   // drives the gentle per-screen cascade

    // Inputs (unchanged set — the data we collect and persist is identical).
    @State private var name = ""
    @State private var sex: BiologicalSex = .female
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var heightInches = 65.0
    @State private var currentWeight = 150.0
    @State private var goalWeight = 140.0
    @State private var activity: ActivityLevel = .light
    // The goal DIRECTION drives which paces we offer (lose/maintain/gain). Default
    // .lose keeps the original flow byte-identical for the primary (loss) user.
    @State private var direction: GoalPace.Direction = .lose
    @State private var pace: GoalPace = .relaxed
    // NEW: her optional free-text context. Persisted to UserProfile.onboardingNote.
    @State private var note = ""
    /// Her chosen look (cute = warm/cream, cool = dark/electric). Applied at finish so
    /// each person lands in their own theme — this is the per-user personalization, not
    /// a hardcoded skin. Defaults to cute (the primary user); Bryan picks cool.
    @State private var themeChoice: ThemeStyle = OnboardingView.debugLook ?? .cute

    // Vita's closing reflection: generated (LLM when a key exists) or templated. We
    // kick it off on the "putting your plan together" beat so it's ready by the note
    // screen; the flow never *waits* on it (there's always a warm fallback).
    @State private var coachMessage: String?
    @State private var coachMessageStarted = false

    @FocusState private var noteFocused: Bool

    // MARK: Connect step (final practical setup — all optional / skippable)
    /// What she pastes in (the key a friend texted her). Saved to the Keychain on tap.
    @State private var apiKeyDraft = ""
    /// Mirrors "is a key stored" so the card + footer react the instant she saves one.
    @State private var keySaved = AIConfig.hasActiveKey
    /// Apple Health: optimistic "connected" flag once the system sheet has been answered.
    @State private var healthConnected = false
    @State private var healthBusy = false
    /// Live location authorization (permission-only for now; nearby suggestions later).
    @State private var location = LocationService.shared
    @FocusState private var keyFocused: Bool

    // MARK: Character step (optional: a pixel character made from a photo)
    /// Consent, photo, the call to OpenAI and its fallbacks (`AvatarCreationModel`). The
    /// accepted PNG is applied in `finish()`; with none, the built-in character stands.
    @State private var avatarModel = AvatarCreationModel(theme: OnboardingView.debugLook ?? .cute)

    // Page indices — named so the flow reads clearly.
    private enum Step: Int, CaseIterable {
        case fromBryan, welcome, look, goal, education, about, weight, activity, note, plan, connect, avatar, vitaNote
    }
    private var pageCount: Int { Step.allCases.count }
    private var step: Step { Step(rawValue: page) ?? .welcome }
    private var isLastPage: Bool { page == pageCount - 1 }

    /// The gentlest pace that actually moves weight in the given direction (so a
    /// gain goal lands on Lean gain, not the always-present Maintain). Maintain
    /// resolves to `.maintain`. `paces(for:)` includes `.maintain` in every list, so
    /// we filter to the matching direction first and only then fall back.
    static func defaultPace(for direction: GoalPace.Direction) -> GoalPace {
        GoalPace.paces(for: direction).first { $0.direction == direction } ?? .maintain
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step dots — brand-tinted for the active step.
            stepDots
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)

            TabView(selection: $page) {
                fromBryanPage.tag(Step.fromBryan.rawValue)
                welcomePage.tag(Step.welcome.rawValue)
                lookPage.tag(Step.look.rawValue)
                goalPage.tag(Step.goal.rawValue)
                educationPage.tag(Step.education.rawValue)
                aboutPage.tag(Step.about.rawValue)
                weightPage.tag(Step.weight.rawValue)
                activityPage.tag(Step.activity.rawValue)
                notePage.tag(Step.note.rawValue)
                summaryPage.tag(Step.plan.rawValue)
                connectPage.tag(Step.connect.rawValue)
                avatarPage.tag(Step.avatar.rawValue)
                vitaNotePage.tag(Step.vitaNote.rawValue)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: page)

            footer
        }
        .background(backdrop)
        .tint(Theme.brand)
        .onAppear { withAnimation { appeared = true } }
        // Re-cascade content each time she lands on a new screen.
        .onChange(of: page) { _, _ in
            appeared = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9).delay(0.05)) { appeared = true }
            // Begin generating Vita's closing note when her plan is revealed, so it's
            // ready by the final screen. Guarded to run once; never blocks the flow.
            if step == .plan { startCoachMessage() }
            // The character step falls back to the built-in that goes with the picked look,
            // and re-checks for an OpenAI key (one may have been saved on the step before).
            if step == .avatar {
                avatarModel.theme = themeChoice
                avatarModel.refreshKeyState()
            }
        }
    }

    // MARK: - Backdrop

    /// Soft canvas with a faint brand glow up top for warmth (skin-aware).
    private var backdrop: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.brand.opacity(0.10), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Step indicator

    private var stepDots: some View {
        HStack(spacing: Theme.Space.sm) {
            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Theme.brand : Theme.textSecondary.opacity(0.30))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(page + 1) of \(pageCount)")
        .accessibilityIdentifier(AccessibilityID.Onboarding.steps)
    }

    // MARK: - Vita: the coach voice

    /// Vita's avatar — a small, friendly heart-in-a-circle that recurs on the
    /// conversational screens so it feels like she's talking *with* someone.
    private func vitaAvatar(size: CGFloat = 44) -> some View {
        // Vita's real identity — the Sprout mascot — in place of the old heart glyph.
        VitaAvatar(size: size, showsSparkle: false)
    }

    /// A chat-style bubble in Vita's voice — the heart of the "talking with a coach"
    /// feel. Renders markdown (so we can **bold** the warm bits).
    private func vitaBubble(_ markdown: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            vitaAvatar(size: 38)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: 6) {
                    Text("Vita")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(Theme.brand)
                }
                Text(markdown)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.brand.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1)
            )
        }
    }

    /// First-person greeting helper — folds her name in once she's typed it.
    private var friendlyName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : t
    }

    // MARK: - Page 0 · A note from Bryan (the very first, personal beat)

    /// A heartfelt opener in Bryan's own voice — the first thing she sees, before Vita.
    /// The message text lives in `bryanNote` up top (Bryan edits it).
    private var fromBryanPage: some View {
        coachScroll {
            HStack(spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(Theme.brand.opacity(0.14)).frame(width: 46, height: 46)
                    Circle().strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1).frame(width: 46, height: 46)
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.brandGradient)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("A note for you")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("from Bryan")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .appearLift(appeared, index: 0)

            Text(bryanNote)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.brand.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1)
                )
                .appearLift(appeared, index: 1)

            Text("— Bryan 🫶")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .appearLift(appeared, index: 2)
        }
    }

    // MARK: - Page 1 · Welcome (Vita introduces herself)

    private var welcomePage: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()

            // Friendly hero — Vita (the Sprout mascot), breathing gently.
            VitaAvatar(size: 168, showsSparkle: true)
                .breathing()
                .accessibilityHidden(true)
                .appearLift(appeared, index: 0)

            VStack(spacing: Theme.Space.md) {
                Text("Hi — I'm Vita 💛")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .appearLift(appeared, index: 1)

                Text("I'll help you hit your goals — and actually enjoy getting there. Let's set you up. Takes about a minute.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Space.lg)
                    .appearLift(appeared, index: 2)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    // MARK: - Page 1b · Choose your look (per-user theme: cute vs cool)

    /// A quick, visual identity pick so each person lands in their OWN skin — cute (warm)
    /// for Victoria, cool (dark/electric) for Bryan — from a real choice, not a hardcoded
    /// default. The preview cards render each palette directly (hardcoded swatches), since
    /// onboarding itself runs in the default skin until `finish()` applies the pick.
    private var lookPage: some View {
        coachScroll {
            vitaBubble("First — pick your look. You can switch it anytime in Settings.")
                .appearLift(appeared, index: 0)

            VStack(spacing: Theme.Space.md) {
                lookCard(style: .cute,
                         bg: Color(hex: 0xF8F1E7), card: .white,
                         accent: Color(hex: 0xF2976F), ink: Color(hex: 0x2B2620))
                lookCard(style: .cool,
                         bg: Color(hex: 0x0E1110), card: Color(hex: 0x1A1E1C),
                         accent: Color(hex: 0xC6FF3D), ink: .white)
            }
            .appearLift(appeared, index: 1)
        }
    }

    /// One big tappable look option: a mini palette preview + name + blurb + check.
    private func lookCard(style: ThemeStyle, bg: Color, card: Color,
                          accent: Color, ink: Color) -> some View {
        let selected = themeChoice == style
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { themeChoice = style }
        } label: {
            HStack(spacing: Theme.Space.md) {
                miniPreview(bg: bg, card: card, accent: accent, ink: ink)
                    .frame(width: 86, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(style.label)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(style.blurb)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.brand : Theme.textSecondary.opacity(0.35))
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(selected ? Theme.brand.opacity(0.10) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(selected ? Theme.brand.opacity(0.55) : Theme.divider,
                              lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(style.label) look. \(style.blurb).")
    }

    /// A tiny faux-screen in the given palette — a header dot + pill, an accent "button",
    /// and a content line — enough to convey each vibe at a glance.
    private func miniPreview(bg: Color, card: Color, accent: Color, ink: Color) -> some View {
        ZStack {
            bg
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 13, height: 13)
                    Capsule().fill(ink.opacity(0.20)).frame(width: 28, height: 6)
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(card)
                    .frame(height: 28)
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: 24, height: 9).padding(.leading, 6)
                    }
                HStack(spacing: 4) {
                    Capsule().fill(ink.opacity(0.16)).frame(width: 36, height: 5)
                    Spacer(minLength: 0)
                }
            }
            .padding(9)
        }
    }

    // MARK: - Page 2 · What are you hoping for? (direction, by FEELING)

    /// The earliest meaningful choice, framed by FEELING rather than a number. Each
    /// option still maps to a `GoalPace.Direction` (lose / maintain / gain) and drives
    /// the pace list + framing throughout. No speed slider, no shame language — warm,
    /// goal-positive, and reflected straight back to her below.
    private var goalPage: some View {
        coachScroll {
            vitaBubble("What are you here to do? Pick the one that fits.")
                .appearLift(appeared, index: 0)

            VStack(spacing: Theme.Space.sm) {
                goalCard(
                    target: .lose,
                    icon: "flame.fill",
                    title: "Lose weight",
                    detail: "Drop fat, feel leaner, and get stronger."
                )
                goalCard(
                    target: .maintain,
                    icon: "heart.circle.fill",
                    title: "Maintain my weight",
                    detail: "Stay where I am and lock in healthy habits."
                )
                goalCard(
                    target: .gain,
                    icon: "dumbbell.fill",
                    title: "Build muscle",
                    detail: "Add lean muscle and get stronger."
                )
            }
            .appearLift(appeared, index: 1)

            // Vita reflects the choice back warmly.
            vitaBubble(goalReassurance)
                .appearLift(appeared, index: 2)
                .id("goal-reflect-\(direction)")   // re-animate when the choice changes
        }
    }

    /// A large, tappable goal card with a brand check on selection. Choosing a direction
    /// also snaps `pace` to the gentlest pace for that direction so a pace from another
    /// direction can never leak through (e.g. a loss pace on a gain profile).
    private func goalCard(target: GoalPace.Direction, icon: String, title: String, detail: String) -> some View {
        let selected = direction == target
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                direction = target
                pace = Self.defaultPace(for: target)
            }
        } label: {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(selected ? Theme.brand : Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(
                        (selected ? Theme.brand.opacity(0.15) : Theme.textSecondary.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.brand : Theme.textSecondary.opacity(0.35))
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(selected ? Theme.brand.opacity(0.10) : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(selected ? Theme.brand.opacity(0.55) : Theme.divider,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Goal-positive reflection keyed off the chosen direction — in Vita's voice. Leads
    /// with eating ENOUGH / fueling; never restriction, never a speed.
    private var goalReassurance: LocalizedStringKey {
        switch direction {
        case .lose:     return "Let's do it. We'll get you there by **fueling you right** — high protein, smart choices, real results."
        case .maintain: return "Solid. We'll keep your energy high and lock in the habits that make it stick."
        case .gain:     return "Let's build. A steady, protein-forward surplus — we'll add **muscle**, not just weight."
        }
    }

    // MARK: - Page 3 · Education (value-first, BEFORE the numbers)

    /// Positive, ADDITIVE "ways to reach your goal" cards shown before any data entry.
    /// Every card is something to add or do (eat enough, protein, get stronger, sleep,
    /// move) — safe and encouraging for an under-eater. Copy adapts for a gain goal.
    private var educationPage: some View {
        coachScroll {
            vitaBubble(LocalizedStringKey(OnboardingEducation.intro(for: direction)))
                .appearLift(appeared, index: 0)

            VStack(spacing: Theme.Space.sm) {
                let cards = OnboardingEducation.cards(for: direction)
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    educationCard(card)
                        .appearLift(appeared, index: idx + 1)
                }
            }
        }
    }

    private func educationCard(_ card: OnboardingEducation.Card) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: card.icon)
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 40, height: 40)
                .background(Theme.brand.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(card.headline)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(card.why)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Page 4 · About you (gentle, "only if you're comfortable")

    private var aboutPage: some View {
        coachScroll {
            vitaBubble("Now a few basics, so the plan I build is truly *yours*. Share only what you're comfortable with — you can change any of it later.")
                .appearLift(appeared, index: 0)

            VStack(spacing: Theme.Space.md) {
                fieldCard(icon: "person.fill", label: "What can I call you?") {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }

                fieldCard(icon: "figure.stand", label: "Sex (helps estimate your energy needs)") {
                    Picker("Sex", selection: $sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                fieldCard(icon: "calendar", label: "Birthday") {
                    // Bounded 13–100 years (mirrors the coach tools' limits) — an unbounded
                    // picker allowed a FUTURE birthday, which fed a negative age into the
                    // calorie math.
                    DatePicker("", selection: $birthDate, in: birthDateRange, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                fieldCard(icon: "ruler", label: "Height") {
                    HStack {
                        Text(heightString)
                            .font(Theme.number(22))
                            .foregroundStyle(Theme.brand)
                            .contentTransition(.numericText())
                        Spacer()
                        Stepper("", value: $heightInches, in: 48...84, step: 1)
                            .labelsHidden()
                    }
                }
            }
            .appearLift(appeared, index: 1)
        }
    }

    // MARK: - Page 5 · Weight (gentle, just a starting point)

    private var weightPage: some View {
        coachScroll {
            vitaBubble("And your current weight — just the **starting point for the math**.")
                .appearLift(appeared, index: 0)

            VStack(spacing: Theme.Space.md) {
                weightStepperCard(title: "Where you are now", value: $currentWeight, tint: Theme.textPrimary)
                weightStepperCard(title: weightGoalLabel, value: $goalWeight, tint: Theme.brand)
            }
            .appearLift(appeared, index: 1)

            // Direction/goal mismatch caught HERE, warmly, instead of silently hiding the
            // projection later and confusing every downstream chart and coach read.
            if let warning = goalMismatchWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.md)
                .background(Theme.warning.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .transition(.opacity)
            }

            // Vita reflects gently — direction-aware, never about speed.
            vitaBubble(weightReassurance)
                .appearLift(appeared, index: 2)
        }
    }

    /// Warm inline check that the goal weight actually lies in the chosen direction.
    /// Nil when everything lines up (or when goal == current, which reads as "no target yet").
    private var goalMismatchWarning: String? {
        switch direction {
        case .lose where goalWeight > currentWeight:
            return "Small mix-up: you picked “lose weight,” but this goal is above where you are now. Nudge the goal below \(Int(currentWeight)) lb — or hop back a page if you meant to build instead."
        case .gain where goalWeight < currentWeight:
            return "Small mix-up: you picked “build,” but this goal is below where you are now. Nudge the goal above \(Int(currentWeight)) lb — or hop back a page if you meant to lose instead."
        default:
            return nil
        }
    }

    /// Valid birthday window: 13–100 years old (same bounds Vita's set_birth_date enforces).
    private var birthDateRange: ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date.now
        let oldest = cal.date(byAdding: .year, value: -100, to: now) ?? now
        let youngest = cal.date(byAdding: .year, value: -13, to: now) ?? now
        return oldest...youngest
    }

    /// Goal-weight label — direct, with "(optional)" so it never reads as mandatory.
    private var weightGoalLabel: String {
        switch direction {
        case .lose:     return "Goal weight (optional)"
        case .maintain: return "Weight to hold"
        case .gain:     return "Goal weight (optional)"
        }
    }

    /// Direction-aware line on the weight page — direct, results-focused, no pressure.
    private var weightReassurance: LocalizedStringKey {
        switch direction {
        case .lose:     return "Set a target if you've got one — we'll track your trend and get you there. Change it anytime."
        case .maintain: return "Set this at or near where you are now — we'll help you hold it."
        case .gain:     return "Aim a bit above where you are now — we'll fuel a steady, lean build to get there."
        }
    }

    private func weightStepperCard(title: String, value: Binding<Double>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack {
                Text("\(Int(value.wrappedValue)) lb")
                    .font(Theme.number(34))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                Spacer()
                Stepper("", value: value, in: 70...500, step: 1)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Page 6 · Activity & pace

    private var activityPage: some View {
        coachScroll {
            vitaBubble("How active is a typical week? This just helps me dial in your numbers.")
                .appearLift(appeared, index: 0)

            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionHeader(title: "How active are you?")
                    VStack(spacing: Theme.Space.sm) {
                        ForEach(ActivityLevel.allCases) { level in
                            selectRow(
                                title: level.label,
                                detail: level.detail,
                                selected: activity == level
                            ) { activity = level }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionHeader(title: paceSectionTitle)
                    VStack(spacing: Theme.Space.sm) {
                        // Paces are filtered by the goal direction chosen earlier:
                        // loss → relaxed/steady/ambitious/maintain, gain →
                        // leanGain/steadyGain/maintain, maintain → maintain.
                        ForEach(GoalPace.paces(for: direction)) { p in
                            selectRow(
                                title: p.label,
                                detail: paceDetail(p),
                                selected: pace == p
                            ) { pace = p }
                        }
                    }
                }
            }
            .appearLift(appeared, index: 1)

            vitaBubble(paceReassurance)
                .appearLift(appeared, index: 2)
                .id("pace-reflect-\(pace)")
        }
    }

    /// A tappable selectable row used for activity + pace, with a brand check on selection.
    private func selectRow(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.brand : Theme.textSecondary.opacity(0.35))
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(selected ? Theme.brand.opacity(0.10) : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(selected ? Theme.brand.opacity(0.55) : Theme.divider,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Page 7 · Free-text note (her own words, totally optional)

    private var notePage: some View {
        coachScroll {
            vitaBubble("Anything else I should know? Your routine, foods you love, what's worked before, what hasn't. The more I know, the better I can tailor this. **Optional.**")
                .appearLift(appeared, index: 0)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ZStack(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("Type anything here, or skip it.")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $note)
                        .focused($noteFocused)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                }
                .card()

                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Theme.brand)
                    Text("The more you share, the more I can tailor your plan to you.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .appearLift(appeared, index: 1)

            // Gentle real-time acknowledgement once she's written something.
            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                vitaBubble("Got it — I'll fold this right into your plan. 💛")
                    .appearLift(appeared, index: 2)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: note.isEmpty)
        // Tapping outside the editor dismisses the keyboard.
        .contentShape(Rectangle())
        .onTapGesture { noteFocused = false }
    }

    // MARK: - Page 8 · Plan summary (leads with the plan, straight to it)

    /// The kind targets summary. The deficit/surplus is already baked into the computed
    /// target, so the whole framing is "fuel to *reach*", never a limit to fear. We LEAD
    /// with the eating-enough philosophy; the calorie figure appears only as a *supporting*
    /// labeled detail (never a giant hero number), with goal weight kept out of the
    /// headline. All of the original kind copy is preserved.
    private var summaryPage: some View {
        coachScroll {
            vitaBubble(planIntro)
                .appearLift(appeared, index: 0)

            VStack(spacing: Theme.Space.md) {
                // 1) LEAD with HOW to eat toward the goal — the eat-enough message first.
                reassuranceCard(
                    icon: "heart.circle.fill",
                    text: eatingPhilosophyText
                )

                // 2) Daily fuel — the calorie figure as a SUPPORTING, framed detail (not a
                //    hero headline). Meaning text sits right beside it so the number always
                //    reads as "a target to reach", never a ceiling.
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Label("Your daily fuel", systemImage: "fork.knife.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("about \(Int(previewTarget))")
                            .font(Theme.number(30))
                            .foregroundStyle(Theme.calories)
                            .contentTransition(.numericText())
                        Text("calories a day")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(calorieMeaningText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                // 3) Macro grams + a friendly one-liner on why each matters.
                VStack(spacing: Theme.Space.sm) {
                    macroRow("Protein", previewMacros.proteinG, Theme.protein)
                    Divider().overlay(Theme.divider)
                    macroRow("Carbs", previewMacros.carbsG, Theme.carbs)
                    Divider().overlay(Theme.divider)
                    macroRow("Fat", previewMacros.fatG, Theme.fat)
                    Text(macroMeaningText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Space.xs)
                }
                .card()

                // 4) Recommended daily steps + water, with plain explanations.
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("We also suggest")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    recRow(icon: "shoeprints.fill", tint: Theme.info,
                           title: "\(recommendedSteps.formatted()) steps a day",
                           detail: "You don't need 10,000 — that was a marketing slogan. Around 7–8k gives you most of the health benefit.")
                    recRow(icon: "drop.fill", tint: Theme.water,
                           title: "\(recommendedWaterContainers) bottles of water",
                           detail: "About \(Int(recommendedWaterOz)) oz. Tea, coffee, and water-rich foods all count too.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                // 5) Gentle projection — downward for loss, upward for gain.
                if showsProjection {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text("Projected trend")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("On a \(pace.label.lowercased()) pace you'd hit \(Int(goalWeight)) lb in about \(estimatedWeeks) weeks. We'll adjust as we go.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        Chart(projection, id: \.week) { point in
                            AreaMark(
                                x: .value("Week", point.week),
                                y: .value("Weight", point.weight)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.brand.opacity(0.30), Theme.brand.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Week", point.week),
                                y: .value("Weight", point.weight)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .foregroundStyle(Theme.brandGradient)
                        }
                        .chartYScale(domain: chartYDomain)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisGridLine().foregroundStyle(Theme.divider)
                                AxisValueLabel().foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisGridLine().foregroundStyle(Theme.divider)
                                AxisValueLabel().foregroundStyle(Theme.textSecondary)
                            }
                        }
                        // Keep the gradient AREA fill inside the plot — otherwise it
                        // bleeds down past the chart and tints the whole card.
                        .chartPlotStyle { plotArea in plotArea.clipped() }
                        .frame(height: 168)
                        .clipped()
                        .padding(.top, Theme.Space.xs)
                    }
                    .card()
                } else if pace == .maintain {
                    reassuranceCard(
                        icon: "equal.circle.fill",
                        text: "You're set to maintain — we'll help you hold steady and feel strong."
                    )
                } else if direction == .gain {
                    reassuranceCard(
                        icon: "arrow.up.right.circle.fill",
                        text: "Set a goal weight above where you are now and we'll map out your climb — steady fuel, mostly muscle."
                    )
                } else {
                    reassuranceCard(
                        icon: "arrow.up.right.circle.fill",
                        text: "Your goal is at or above your current weight — we'll support you wherever you're headed."
                    )
                }

                // Footer: honest about the estimate (real progress isn't perfectly linear).
                Text("A smart estimate — real progress isn't a straight line, so I'll keep adjusting as we learn your pace.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.Space.xs)
            }
            .appearLift(appeared, index: 1)
        }
    }

    /// Vita's lead-in to the plan — warm and goal-positive (never number-first).
    private var planIntro: LocalizedStringKey {
        switch direction {
        case .lose:     return "Here's your plan — built to get you real results. **Hit your protein, hit your number, stay consistent.**"
        case .maintain: return "Here's where we'll start — built to keep you steady, strong, and well-fueled."
        case .gain:     return "Here's where we'll start — built to **fuel your build**, with protein leading the way."
        }
    }

    private func macroRow(_ label: String, _ grams: Double, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(Int(grams)) g")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
    }

    /// A recommendation row: icon + headline number + plain-language "why".
    private func recRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reassuranceCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brand)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Page 10 · Connect (final practical setup — key + Health + location)

    /// The one practical beat before the warm send-off. The ONLY thing she truly needs is
    /// the coach key so we can chat; Apple Health and location are *offered*, never required.
    /// Everything is optional and recoverable later in Settings, so the footer reads
    /// "Maybe later" until a key is in. (A friend can text her the key — the Paste button
    /// makes it a single tap.)
    private var connectPage: some View {
        coachScroll {
            vitaBubble("Last little thing — let's get you set up. The only must-have is my **key** so we can actually chat. Everything else here is optional, and you can change any of it later 💛")

            // 1) THE KEY — the real unlock for the coach. Most prominent.
            connectCard(
                icon: "sparkles",
                tint: Theme.brand,
                title: "Connect Vita’s brain",
                done: keySaved,
                doneLabel: "Key saved — we’re all set to chat ✨"
            ) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Paste the key you were sent. It lives only on your phone (in the Keychain) — never shared.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Space.sm) {
                        TextField("Paste your key", text: $apiKeyDraft)
                            .font(.callout)
                            .foregroundStyle(Theme.textPrimary)
                            .tint(Theme.brand)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($keyFocused)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Theme.cardRaised))
                            .overlay(Capsule().strokeBorder(
                                Theme.brand.opacity(keyFocused ? 0.45 : 0.12), lineWidth: 1))

                        Button {
                            if let s = UIPasteboard.general.string {
                                apiKeyDraft = s.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.brand)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(Theme.brandSoft))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Paste from clipboard")
                    }

                    Button(action: saveKey) {
                        Text("Save key")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.primary)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
            }

            // 2) APPLE HEALTH — optional weight sync.
            connectCard(
                icon: "heart.fill",
                tint: Theme.positive,
                title: "Sync Apple Health",
                subtitle: "Optional",
                done: healthConnected,
                doneLabel: "Connected to Apple Health"
            ) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("If you keep your weight in Apple Health, I’ll keep your trend in sync. Skip it if you don’t — nothing breaks.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    secondaryButton(title: healthBusy ? "Connecting…" : "Connect Apple Health",
                                    tint: Theme.positive,
                                    busy: healthBusy,
                                    action: connectHealth)
                        .disabled(healthBusy)
                }
            }

            // 3) LOCATION — optional, for nearby healthy suggestions (feature coming soon).
            connectCard(
                icon: "location.fill",
                tint: Theme.info,
                title: "Healthy options nearby",
                subtitle: "Optional",
                done: location.isAuthorized,
                doneLabel: "Location on — I’ll find nearby options"
            ) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Turn this on and I can point you to healthy bites near you when you’re out and about.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    secondaryButton(
                        title: location.isDetermined && !location.isAuthorized
                            ? "Turn on in Settings" : "Allow location",
                        tint: Theme.info,
                        busy: false,
                        action: handleLocationTap)
                }
            }
        }
    }

    /// One card in the Connect step: icon disc + title (+ optional "Optional" tag), a
    /// check + confirmation line when it's done, otherwise the supplied control content.
    @ViewBuilder
    private func connectCard<Content: View>(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        done: Bool,
        doneLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.headline).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tint)
                }
            }

            if done {
                Label(doneLabel, systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: done)
    }

    /// A tinted, outlined secondary action button (we only ship a `.primary` style).
    private func secondaryButton(title: String, tint: Color, busy: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                if busy { ProgressView().controlSize(.small).tint(tint) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(tint.opacity(0.10), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connect actions

    /// Store the pasted key on-device (Keychain), under the ACTIVE provider's slot
    /// (Anthropic on a fresh install; whatever's selected on a re-onboard).
    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AIKeyRouting.savePastedKey(trimmed)   // filed by the key's own provider, which becomes active
        keyFocused = false
        apiKeyDraft = ""
        withAnimation { keySaved = true }
        startTrigger.toggle()
    }

    /// Present the Apple Health permission sheet. HealthKit never reveals read-auth status
    /// (privacy), so we optimistically mark "connected" once she's answered the sheet.
    private func connectHealth() {
        guard HealthKitService.isAvailable else { return }
        healthBusy = true
        Task {
            try? await HealthKitService.shared.requestAuthorization()
            await MainActor.run {
                healthBusy = false
                withAnimation { healthConnected = true }
            }
        }
    }

    /// First tap → system location prompt. If she already decided and denied, route her to
    /// Settings (iOS won't re-prompt). If already authorized, nothing to do.
    private func handleLocationTap() {
        if location.isDetermined {
            if !location.isAuthorized, let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            location.requestWhenInUse()
        }
    }

    // MARK: - Page 11 · Your character (optional: a pixel character from a photo)

    /// After the key step, because it needs a key: an OpenAI one, whatever provider she
    /// chats with. Never required and never a dead end: the footer always moves on, and
    /// with no key, a refusal or a failure she simply starts with the built-in character.
    private var avatarPage: some View {
        coachScroll {
            vitaBubble("One fun extra: want a **pixel character that looks like you**? Totally optional. Skip it and you'll start with one of mine.")
                .appearLift(appeared, index: 0)
            AvatarCreationView(model: avatarModel)
                .appearLift(appeared, index: 1)
        }
    }

    // MARK: - Page 12 · A note from Vita (LLM reflection / warm fallback)

    private var vitaNotePage: some View {
        coachScroll {
            HStack(spacing: Theme.Space.sm) {
                vitaAvatar(size: 40).breathing()
                VStack(alignment: .leading, spacing: 2) {
                    Text("A note from Vita")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Just for you")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .appearLift(appeared, index: 0)

            Group {
                if let coachMessage {
                    Text(coachMessage)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .fill(Theme.brand.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1)
                        )
                        .transition(.opacity)
                } else {
                    // Gentle "writing…" placeholder. Practically always resolves before
                    // she lands here (we started it on the previous beat), but if not,
                    // we never block — and a warm fallback always arrives.
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView()
                            .tint(Theme.brand)
                        Text("Vita is writing you a note…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.md)
                    .card()
                }
            }
            .appearLift(appeared, index: 1)
            .animation(.easeInOut(duration: 0.3), value: coachMessage)

            // The warm send-off above the Start button.
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.brand)
                Text("Whenever you're ready — let's get to work 💪")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appearLift(appeared, index: 2)
        }
        // Safety net: if she reaches this screen before generation was triggered
        // (e.g. swiped fast), make sure it's running.
        .onAppear { startCoachMessage() }
    }

    // MARK: - Coach message generation

    /// Kick off Vita's closing message exactly once. Uses the LLM when an API key
    /// exists, otherwise a warm templated message — and always falls back to the
    /// template on any error (see OnboardingCoachMessage). Never blocks the flow.
    private func startCoachMessage() {
        guard !coachMessageStarted else { return }
        coachMessageStarted = true
        let inputs = OnboardingCoachMessage.Inputs(
            name: friendlyName,
            direction: direction,
            paceLabel: pace.label,
            activityLabel: activity.label,
            note: note
        )
        Task {
            let message = await OnboardingCoachMessage.make(inputs)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) { coachMessage = message }
            }
        }
    }

    // MARK: - Shared page chrome

    /// A scrollable conversational step. Unlike the old form chrome (big left-aligned
    /// title), content here is led by Vita's bubble, so this is a clean vertical stack
    /// with consistent rhythm and bottom breathing room for the footer.
    private func coachScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.xl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    /// A labeled input chip over a card — large, tasteful, native.
    private func fieldCard<Content: View>(
        icon: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Footer (Back / Next / Start)

    private var footer: some View {
        HStack(spacing: Theme.Space.md) {
            if page > 0 {
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { page -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier(AccessibilityID.Onboarding.back)
            }

            if isLastPage {
                Button("Start my journey", action: finish)
                    .buttonStyle(.primary)
                    .sensoryFeedback(.success, trigger: startTrigger)
                    .accessibilityIdentifier(AccessibilityID.Onboarding.start)
            } else {
                Button {
                    noteFocused = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { page += 1 }
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Text(nextButtonTitle)
                        Image(systemName: "chevron.right")
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.primary)
                .accessibilityLabel(nextButtonTitle)
                .accessibilityIdentifier(AccessibilityID.Onboarding.next)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.Space.md)
        .background(.ultraThinMaterial)
    }

    /// A softer, skippable-feeling label on steps that are optional to fill in.
    private var nextButtonTitle: String {
        switch step {
        case .welcome:   return "Let's start"
        case .note:      return note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip for now" : "See my plan"
        case .connect:   return keySaved ? "Continue" : "Maybe later"
        case .avatar:    return avatarModel.acceptedPNG != nil ? "Continue" : "Skip for now"
        default:         return "Next"
        }
    }

    // MARK: - Derived display

    private var heightString: String {
        let total = Int(heightInches.rounded())
        return "\(total / 12)' \(total % 12)\""
    }

    /// Pace described by FEELING, not by a lb/week rate. The pace still drives the
    /// (already-baked-in) calorie math; we just keep a *speed* number off the screen for
    /// a user who's sensitive to it — matching the research's feeling-based framing.
    private func paceDetail(_ p: GoalPace) -> String {
        switch p {
        case .relaxed:    return "The most relaxed pace — easiest to stick with (recommended)"
        case .steady:     return "A balanced middle — steady and sustainable"
        case .ambitious:  return "A faster pace — push harder, still sustainable"
        case .maintain:   return "Hold steady and stay strong"
        case .leanGain:   return "A lean, steady build — patience pays off"
        case .steadyGain: return "A solid, steady build — protein leads the way"
        }
    }

    private var paceReassurance: LocalizedStringKey {
        switch pace {
        case .maintain: return "Holding steady is a real goal — it builds habits and protects the progress you make."
        case .relaxed:  return "A gentle pace protects your energy and your muscle. This is the one that actually sticks."
        case .steady:   return "A balanced, steady pace — gentle enough to keep, real enough to feel."
        case .ambitious: return "If you choose a quicker pace, listen to your body — slowing down anytime is a win, not a setback."
        case .leanGain:  return "A small, steady surplus builds muscle while keeping fat gain low — patience pays off."
        case .steadyGain: return "A solid surplus to grow — keep protein high and most of it becomes muscle, not fat."
        }
    }

    /// "Your pace" vs "Your gain pace" — small touch so the gain flow reads naturally.
    private var paceSectionTitle: String {
        direction == .gain ? "Your gain pace" : "Your pace"
    }

    /// What the daily-calorie number MEANS, by direction. Loss/maintain = a target to
    /// REACH (never a limit to fear); gain = fuel to grow into.
    private var calorieMeaningText: String {
        switch direction {
        case .lose:
            return "This is your daily target — hit it. Eating too little stalls progress and burns muscle; enough food and enough protein is what actually moves the scale."
        case .maintain:
            return "Think of this as your steady number — enough to hold your weight and keep your energy up, day to day."
        case .gain:
            return "Think of this as fuel to grow into — eating up to this is what powers new muscle. Falling short is what stalls a build, so aim to hit it."
        }
    }

    /// The macro one-liner, nudged toward muscle for a gain goal.
    private var macroMeaningText: String {
        switch direction {
        case .gain:
            return "Protein is the raw material for new muscle; carbs fuel your lifts and recovery, and fat keeps your hormones happy — hit your protein and the gains stay lean."
        default:
            return "Protein keeps you full and strong; carbs and fat fuel your energy and mood — none of them are the enemy."
        }
    }

    /// Closing philosophy on HOW to eat toward the goal — never restrictive.
    private var eatingPhilosophyText: String {
        switch direction {
        case .lose:
            return "The edge most diets miss: you don't need tiny portions. Lean on protein and high-volume foods — big salads, fruit, veggies — and you can fill your plate, stay full, and still hit your target."
        case .maintain:
            return "Nothing's off-limits. Lean on protein and whole foods most of the time, leave room for what you love, and stay consistent — that's what works."
        case .gain:
            return "Growing is the fun part: you get to eat more. Build meals around protein, add calorie-dense favorites — nut butters, oats, rice, olive oil — and move consistently. The fuel plus the work is what turns into muscle."
        }
    }

    // MARK: - Plan preview (throwaway profile so math matches the real app)

    private var previewProfile: UserProfile {
        let p = UserProfile()
        p.sex = sex
        p.birthDate = birthDate
        p.heightCm = NutritionMath.inToCm(heightInches)
        p.startWeightLbs = currentWeight
        p.goalWeightLbs = goalWeight
        p.activityLevel = activity
        p.pace = pace
        return p
    }

    private var previewTarget: Double { previewProfile.dailyCalorieTarget(weightLbs: currentWeight) }
    private var previewMacros: NutritionMath.Macros { previewProfile.macroTargets(weightLbs: currentWeight) }

    // Recommended goals (research-backed): steps 7–8k, water ½-bodyweight clamped 64–100 oz.
    private var recommendedSteps: Int { 8000 }
    private var recommendedWaterOz: Double {
        min(100, max(64, (currentWeight * 0.5).rounded()))
    }
    private var recommendedWaterContainers: Int {
        max(1, Int((recommendedWaterOz / 16.9).rounded()))   // ~standard 500ml bottle
    }

    /// True when there's a real curve to draw: a moving pace AND a goal that lies in
    /// the chosen direction (below current for loss, above current for gain).
    private var showsProjection: Bool {
        guard estimatedWeeks > 0 else { return false }
        switch direction {
        case .lose: return currentWeight > goalWeight
        case .gain: return goalWeight > currentWeight
        case .maintain: return false
        }
    }

    /// Weeks to span the gap at the chosen pace. Uses the absolute gap so it works
    /// in either direction; 0 when the goal isn't on the right side of current.
    private var estimatedWeeks: Int {
        guard pace.weeklyRateLbs > 0 else { return 0 }
        let goalIsAhead = (direction == .gain) ? (goalWeight > currentWeight) : (currentWeight > goalWeight)
        guard goalIsAhead else { return 0 }
        return max(1, Int((abs(currentWeight - goalWeight) / pace.weeklyRateLbs).rounded(.up)))
    }

    /// The week-by-week curve. Loss steps DOWN toward the goal (clamped at the goal
    /// floor); gain steps UP toward the goal (clamped at the goal ceiling). Driven by
    /// the SIGNED weekly rate so the line moves the right way for the chosen direction.
    private var projection: [(week: Int, weight: Double)] {
        guard estimatedWeeks > 0 else { return [] }
        let signedRate = pace.signedWeeklyRateLbs   // negative = loss, positive = gain
        return (0...estimatedWeeks).map { w in
            let raw = currentWeight + signedRate * Double(w)
            let clamped = direction == .gain ? min(goalWeight, raw) : max(goalWeight, raw)
            return (week: w, weight: clamped)
        }
    }

    /// Y-axis spans current↔goal (plus padding) regardless of direction.
    private var chartYDomain: ClosedRange<Double> {
        let lo = min(currentWeight, goalWeight) - 2
        let hi = max(currentWeight, goalWeight) + 2
        return lo < hi ? lo...hi : lo...(lo + 1)
    }

    // MARK: - Finish

    private func finish() {
        startTrigger.toggle()

        let p = existing ?? UserProfile()
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "friend" : name
        p.sex = sex
        p.birthDate = birthDate
        p.heightCm = NutritionMath.inToCm(heightInches)
        p.startWeightLbs = currentWeight
        p.goalWeightLbs = goalWeight
        p.activityLevel = activity
        p.pace = pace
        // Her chosen look — so she (or Bryan) lands in their own theme AND their own pixel
        // companion from the start. Cool = Bryan's character, Cute = Victoria's. (Without
        // this, companionAvatar stayed at its .victoria default for everyone.)
        p.themeStyle = themeChoice
        p.companionAvatar = (themeChoice == .cool) ? .bryan : .victoria
        // A character she made and accepted on the character step replaces the built-in.
        // Only the finished PNG is kept; the photo it came from was never stored.
        if let png = avatarModel.acceptedPNG { p.useCustomAvatar(png: png) }
        // NEW: persist her optional free-text context (trimmed; "" when she skipped).
        p.onboardingNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Seed the recommended goals we just showed her (she can change any in Settings).
        p.dailyStepGoal = recommendedSteps
        p.waterGoalOzOverride = recommendedWaterOz
        p.onboardingComplete = true
        // A brand-new user starts caught-up, so "What's New" won't fire for the version they
        // just installed — only for genuine future updates.
        WhatsNew.markSeen()

        if existing == nil { context.insert(p) }
        context.insert(WeightEntry(weightLbs: currentWeight))
        try? context.save()

        // Safety net: if she typed a key but didn't tap "Save key", flush it now so she
        // isn't left unable to chat just because she skipped the explicit save.
        let typedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedKey.isEmpty && !AIConfig.hasActiveKey {
            AIKeyRouting.savePastedKey(typedKey)
        }
    }
}
