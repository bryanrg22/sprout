import SwiftUI

/// A playful, **FAIR**, health-SAFE daily "face-off" between you and your buddy, shown in
/// the linked Buddy hub beneath the shared panda.
///
/// ## What it compares (and what it never does)
/// ONLY movement + hydration: **steps 👟 / water 💧 / gym 💪**. It deliberately shows
/// **no weight and no calories** — and never "who ate less." (See `RESEARCH_social.md`:
/// calorie/weight numerics + over/under framing drive disordered eating; Victoria is
/// image-sensitive and tends to under-eat.)
///
/// ## Why it's fair
/// Each metric is scored as a **percentage of that person's OWN goal**, not as raw numbers
/// against each other. So a 12k-step runner and a 6k-step walker can *both* "win the day"
/// by reaching their own targets — body and fitness level don't decide the winner, *showing
/// up for your own goal* does. Scores are **clamped at 100%**, so going over your goal reads
/// as "done!" and never as "beat them by X" (mirrors the companion engine's clamp-at-1.0).
///
/// ## Tone
/// Warm and celebratory. When you both reach a goal it cheers you both ("you both showed
/// up! 🎉"); when one edges the other it celebrates the leader *and* warmly roots for the
/// other ("she edged you on water 💧 — go get it"), **never shaming the lower number**.
struct BuddyFaceOff: View {

    /// My side (read from the dashboard's live data in `BuddyHomeView`).
    let mySteps: Int
    let myStepGoal: Int
    let myWaterOz: Double
    let myWaterGoal: Double
    let myWorkedOut: Bool
    /// Which pixel avatar represents me (from `profile.companionAvatar`).
    let myAvatar: CompanionAvatar

    /// My buddy's latest snapshot (carries their activity + their OWN goals).
    let buddy: BuddySnapshotPayload

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Derived sides

    private var me: FaceOffSide {
        FaceOffSide(name: "You",
                    steps: mySteps, stepGoal: myStepGoal,
                    waterOz: myWaterOz, waterGoal: myWaterGoal,
                    workedOut: myWorkedOut,
                    avatar: myAvatar)
    }

    /// The buddy's avatar is the OTHER pixel character by default (the payload doesn't
    /// carry an avatar choice): if I'm Victoria, my buddy shows as Bryan, and vice-versa.
    private var theirAvatar: CompanionAvatar { myAvatar == .victoria ? .bryan : .victoria }

    private var them: FaceOffSide {
        FaceOffSide(name: buddy.displayName.isEmpty ? "Buddy" : buddy.displayName,
                    steps: buddy.stepsToday, stepGoal: buddy.stepGoal,
                    waterOz: buddy.waterToday, waterGoal: buddy.waterGoal,
                    workedOut: buddy.workedOutToday,
                    avatar: theirAvatar)
    }

    private var rows: [FaceOffMetric] {
        [.steps, .water, .gym].map { FaceOffMetric(kind: $0, me: me, them: them) }
    }

    /// A warm headline summarizing the whole day (counts only metrics both have a goal for).
    private var summary: String {
        let bothWon = rows.filter { $0.bothReachedGoal }.count
        let scored = rows.filter { $0.isScorable }.count
        if scored == 0 { return "Log a little movement to kick off today's face-off 💛" }
        if bothWon == scored { return "You both crushed every goal today! 🎉🎉" }
        if bothWon > 0 { return "You both showed up today — go you two! 💛" }
        return "Day's underway — every little bit counts 💪"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            avatars
            VStack(spacing: Theme.Space.sm) {
                ForEach(rows) { metric in
                    FaceOffMetricRow(metric: metric)
                }
            }
            Text(summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Today's face-off")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Text("vs")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.brand)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.brandSoft, in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's friendly activity face-off, you versus \(them.name)")
    }

    // MARK: Avatars (both pixel characters, side by side)

    private var avatars: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            avatarColumn(side: me)
            Spacer(minLength: 0)
            avatarColumn(side: them)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func avatarColumn(side: FaceOffSide) -> some View {
        VStack(spacing: 6) {
            PixelAvatarBadge(avatar: side.avatar, mood: side.avatarMood)
                .modifier(LivelyAvatar(thriving: side.avatarMood == .thriving,
                                       reduceMotion: reduceMotion))
            Text(side.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side.name)'s character")
    }
}

// MARK: - One side of the face-off

/// A single participant's safe daily activity + their OWN goals. All scoring is relative
/// to that person's own targets so the comparison stays FAIR across bodies / fitness.
struct FaceOffSide {
    let name: String
    let steps: Int
    let stepGoal: Int
    let waterOz: Double
    let waterGoal: Double
    let workedOut: Bool
    let avatar: CompanionAvatar

    /// Fraction (0...1, clamped) of MY OWN step goal reached. `nil` when no goal is set.
    var stepFraction: Double? { Self.fraction(Double(steps), goal: Double(stepGoal)) }
    /// Fraction (0...1, clamped) of MY OWN water goal reached. `nil` when no goal is set.
    var waterFraction: Double? { Self.fraction(waterOz, goal: waterGoal) }

    /// Clamp at 1.0 so over-goal = "done", never "beat them by X". `nil` = no goal to score.
    private static func fraction(_ value: Double, goal: Double) -> Double? {
        guard goal > 0 else { return nil }
        return min(max(value / goal, 0), 1)
    }

    /// How many of this person's own goals they've reached today (steps + water + gym).
    private var goalsReached: Int {
        var n = 0
        if let s = stepFraction, s >= 1 { n += 1 }
        if let w = waterFraction, w >= 1 { n += 1 }
        if workedOut { n += 1 }
        return n
    }

    /// A warm avatar mood for the pixel character — `.thriving` once they've reached any of
    /// their own goals today, otherwise a happy default. Never sad/hungry: this is a
    /// celebratory surface, and the mood reflects *their own* day, not the comparison.
    var avatarMood: CompanionMood { goalsReached >= 1 ? .thriving : .happy }
}

// MARK: - One metric, compared across both sides

/// The three SAFE metrics. Each carries its emoji + friendly label.
enum FaceOffMetricKind: CaseIterable, Identifiable {
    case steps, water, gym
    var id: Self { self }

    var emoji: String {
        switch self {
        case .steps: return "👟"
        case .water: return "💧"
        case .gym:   return "💪"
        }
    }
    var title: String {
        switch self {
        case .steps: return "Steps"
        case .water: return "Water"
        case .gym:   return "Movement"
        }
    }
}

/// A metric scored for both sides as **% of each person's own goal**, plus the warm copy
/// describing the (gentle) outcome.
struct FaceOffMetric: Identifiable {
    let kind: FaceOffMetricKind
    /// My fraction of my own goal (0...1, clamped). `nil` when I have no goal set.
    let myFraction: Double?
    /// Buddy's fraction of their own goal (0...1, clamped). `nil` when they have no goal.
    let theirFraction: Double?
    /// The exact value, shown alongside the % so the bar isn't the only signal (e.g.
    /// "8,432" steps, "44 oz" water). `nil` for gym (a yes/no, not a count).
    let myStat: String?
    let theirStat: String?
    let myName: String
    let theirName: String

    var id: FaceOffMetricKind { kind }

    init(kind: FaceOffMetricKind, me: FaceOffSide, them: FaceOffSide) {
        self.kind = kind
        self.myName = me.name
        self.theirName = them.name
        switch kind {
        case .steps:
            myFraction = me.stepFraction
            theirFraction = them.stepFraction
            myStat = me.steps.formatted(.number.grouping(.automatic))
            theirStat = them.steps.formatted(.number.grouping(.automatic))
        case .water:
            myFraction = me.waterFraction
            theirFraction = them.waterFraction
            myStat = "\(Int(me.waterOz.rounded())) oz"
            theirStat = "\(Int(them.waterOz.rounded())) oz"
        case .gym:
            // Movement is a simple "showed up" — yes/no, so it carries no count or bar.
            myFraction = me.workedOut ? 1 : 0
            theirFraction = them.workedOut ? 1 : 0
            myStat = nil
            theirStat = nil
        }
    }

    /// Both sides have something to score (a goal set, or — for gym — always scorable).
    var isScorable: Bool { myFraction != nil && theirFraction != nil }

    /// Both reached 100% of their OWN goal — the "you both win the day" case.
    var bothReachedGoal: Bool {
        guard let m = myFraction, let t = theirFraction else { return false }
        return m >= 1 && t >= 1
    }

    /// Warm, non-shaming outcome copy. Celebrates a "both" day, gently cheers a leader while
    /// rooting for the other, and stays encouraging when neither has hit goal yet.
    var copy: String {
        guard let m = myFraction, let t = theirFraction else {
            // A goal isn't set on one side — keep it light, never a "you're losing".
            return "\(kind.emoji) cheering you both on"
        }

        // Gym is binary — phrase it as showing up, never as a score.
        if kind == .gym {
            switch (m >= 1, t >= 1) {
            case (true, true):   return "💪 you both moved today! 🎉"
            case (true, false):  return "💪 you moved today — nice one!"
            case (false, true):  return "💪 \(theirName) moved today — your turn 💛"
            case (false, false): return "💪 a little movement is a win — no rush 💛"
            }
        }

        if m >= 1 && t >= 1 {
            return "\(kind.emoji) you both hit your goal! 🎉"
        }

        // Compare progress, but frame it warmly. A small lead is "edged"; a clear one "ahead".
        let lead = m - t
        let near = abs(lead) < 0.08   // within 8 pts → call it neck-and-neck
        if near {
            return "\(kind.emoji) neck and neck — keep going!"
        }
        if lead > 0 {
            // I'm ahead — celebrate me, stay kind about the gap.
            return "\(kind.emoji) you're ahead on \(kind.title.lowercased()) — go you!"
        } else {
            // Buddy is ahead — celebrate them, warmly root for me (never shame).
            let verb = abs(lead) < 0.2 ? "edged you" : "is ahead"
            return "\(kind.emoji) \(theirName) \(verb) on \(kind.title.lowercased()) — go get it"
        }
    }
}

// MARK: - Metric row UI

/// Renders one metric as a **little two-bar bar graph** — one vertical bar per person,
/// each rising to **% of THAT person's own goal** (clamped, so both can be full). A dotted
/// "goal" line sits at the top, a tiny "both 🎉" flag pops when you both reached your goals,
/// and a warm outcome line sits underneath. Fair by construction (own-goal %, never raw
/// counts), playful, and never shaming.
struct FaceOffMetricRow: View {
    let metric: FaceOffMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: 8) {
                // Soft, skin-aware tinted disc holding the metric's emoji — cuter + warmer
                // than a bare glyph, and consistent with the nudge chips' disc treatment.
                ZStack {
                    Circle()
                        .fill(Theme.brandSoft)
                        .overlay(Circle().strokeBorder(Theme.brand.opacity(0.22), lineWidth: 1))
                        .frame(width: 30, height: 30)
                    Text(metric.kind.emoji)
                        .font(.footnote)
                }
                Text(metric.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if metric.bothReachedGoal {
                    Text("both 🎉")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.positive.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.positive.opacity(0.35), lineWidth: 1))
                        .foregroundStyle(Theme.positive)
                        .popIn(true)
                }
            }

            // Movement is a yes/no, so it shows a status badge (no bar). Steps & water show a
            // tidy paired bar graph — % of each person's OWN goal — PLUS the exact value
            // underneath, so the bar isn't the only signal.
            if metric.kind == .gym {
                MovementRow(iMoved: (metric.myFraction ?? 0) >= 1,
                            theyMoved: (metric.theirFraction ?? 0) >= 1,
                            myName: metric.myName,
                            theirName: metric.theirName)
            } else {
                PairedBarGraph(
                    myFraction: metric.myFraction,
                    theirFraction: metric.theirFraction,
                    myStat: metric.myStat,
                    theirStat: metric.theirStat,
                    myName: metric.myName,
                    theirName: metric.theirName
                )
            }

            Text(metric.copy)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        func pct(_ f: Double?) -> String { f.map { "\(Int(($0 * 100).rounded())) percent of goal" } ?? "no goal set" }
        return "\(metric.kind.title): you \(pct(metric.myFraction)), \(metric.theirName) \(pct(metric.theirFraction)). \(metric.copy)"
    }
}

/// A polished **paired column chart** for one metric: two rounded columns (you + buddy)
/// share ONE little plot — a tidy continuous baseline at the bottom and a dotted "100%
/// goal" line at the top. Each column rises to **% of THAT person's own goal** (clamped
/// 0...1, so both can top out), is capped by a % pill, and labelled with the person's first
/// name underneath. Fixed-width columns (centered, not full-bleed) keep it from ever running
/// wide / off-screen. Fair and playful; for gym, the column is full ("moved!") or an empty
/// resting column ("not yet").
private struct PairedBarGraph: View {
    let myFraction: Double?
    let theirFraction: Double?
    /// Exact value shown under each column (e.g. "8,432" steps, "44 oz" water). nil hides it.
    var myStat: String? = nil
    var theirStat: String? = nil
    let myName: String
    let theirName: String

    /// Plot height for the column track, and a fixed (cute, chunky-but-tidy) column width so
    /// the pair always sits comfortably regardless of card width — never full-bleed.
    private let plotHeight: CGFloat = 58
    private let columnWidth: CGFloat = 30
    /// Each column's "slot" — a touch wider than the bar so the % pill / name can breathe and
    /// all three rows (caps · columns · names) line up perfectly above/below each column.
    private var slotWidth: CGFloat { columnWidth + 16 }

    var body: some View {
        // Three aligned rows sharing the same two centered slots, so caps sit over columns
        // and names sit under them. The middle row is the actual plot (baseline + dotted
        // 100% line bracketing the column band).
        VStack(spacing: 6) {
            twoSlots { tint, frac, _, _ in capPill(for: frac, tint: tint) }

            // Plot band: a continuous shared baseline at the bottom, a dotted "100% goal"
            // line at the top, and the two columns rising from the baseline between them.
            ZStack(alignment: .bottom) {
                Line()
                    .stroke(Theme.textSecondary.opacity(0.30),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                Line()
                    .stroke(Theme.divider, lineWidth: 1.5)
                    .frame(height: 1.5)
                twoSlots { tint, frac, _, _ in columnBar(fraction: frac, tint: tint) }
            }
            .frame(height: plotHeight)

            twoSlots { _, _, name, _ in
                Text(firstName(name))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // The exact value beneath each column — the precise stat Bryan wanted alongside
            // the % (e.g. "8,432" steps, "44 oz" water).
            twoSlots { tint, _, _, stat in
                if let stat {
                    Text(stat)
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// Lays "my" slot and "their" slot centered with a gap, each a fixed `slotWidth`, so every
    /// row stacks in perfect vertical alignment. `content` gets (tint, fraction, name).
    @ViewBuilder
    private func twoSlots<Content: View>(
        @ViewBuilder _ content: @escaping (Color, Double?, String, String?) -> Content
    ) -> some View {
        HStack(spacing: Theme.Space.md) {
            Spacer(minLength: 0)
            content(Theme.brand, myFraction, myName, myStat).frame(width: slotWidth)
            content(Theme.info, theirFraction, theirName, theirStat).frame(width: slotWidth)
            Spacer(minLength: 0)
        }
    }

    /// The % cap (or gym wording) in a soft pill that fills in once the goal's reached.
    @ViewBuilder
    private func capPill(for fraction: Double?, tint: Color) -> some View {
        let reached = (fraction ?? 0) >= 1
        Text(capLabel(for: fraction))
            .font(.caption2.weight(.bold)).monospacedDigit()
            .lineLimit(1)
            .fixedSize()                                   // never wrap "100%" onto two lines
            .foregroundStyle(reached ? tint : Theme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(reached ? tint.opacity(0.16) : Color.clear, in: Capsule())
    }

    /// The rounded column rising from the shared baseline. A soft track sits behind it so even
    /// an empty/`nil` value reads as a tidy resting column, never a harsh 0% gap.
    @ViewBuilder
    private func columnBar(fraction: Double?, tint: Color) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: columnWidth / 2, style: .continuous)
                .fill(Theme.divider.opacity(0.6))
                .frame(width: columnWidth, height: plotHeight)
            if let f = fraction, f > 0 {
                RoundedRectangle(cornerRadius: columnWidth / 2, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: columnWidth,
                           height: max(columnWidth, plotHeight * CGFloat(min(1, f))))
                    .overlay(alignment: .top) {
                        // A tiny glossy cap so the column reads soft + cute, not a slab.
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: columnWidth - 12, height: 4)
                            .padding(.top, 5)
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: f)
            }
        }
    }

    private func capLabel(for fraction: Double?) -> String {
        guard let f = fraction else { return "—" }
        return "\(Int((f * 100).rounded()))%"
    }

    /// "You" stays "You"; otherwise show the first word so the label stays tidy under a bar.
    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// Movement is a yes/no, not a count — so instead of bars it shows each person's status:
/// a warm "Moved! 💪" badge when they got activity in, or a gentle "Not yet" while they
/// haven't. No numbers, no bars — just whether the day's movement happened, fairly, for both.
private struct MovementRow: View {
    let iMoved: Bool
    let theyMoved: Bool
    let myName: String
    let theirName: String

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Spacer(minLength: 0)
            badge(name: firstName(myName), moved: iMoved, tint: Theme.brand)
            badge(name: firstName(theirName), moved: theyMoved, tint: Theme.info)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func badge(name: String, moved: Bool, tint: Color) -> some View {
        let color = moved ? tint : Theme.textSecondary
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(moved ? 0.16 : 0.08))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(color.opacity(moved ? 0.4 : 0.2), lineWidth: 1.5))
                Image(systemName: moved ? "figure.run" : "hourglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text(moved ? "Moved! 💪" : "Not yet")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(width: 104)
        .opacity(moved ? 1 : 0.85)
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// A 1pt horizontal line shape for the dotted goal marker.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Pixel avatar badge (reuses the existing companion pixel views)

/// Shows the correct pixel character for a `CompanionAvatar`, reusing the shared
/// `PixelVictoriaView` / `PixelBryanView` (read-only — not modified here), sized to sit
/// neatly in the face-off row.
struct PixelAvatarBadge: View {
    let avatar: CompanionAvatar
    let mood: CompanionMood

    var body: some View {
        Group {
            switch avatar {
            case .victoria: PixelVictoriaView(mood: mood)
            case .bryan:    PixelBryanView(mood: mood)
            }
        }
        // The sprite is authored at 120×144; scale it down to a tidy badge for this row.
        .scaleEffect(0.62)
        .frame(width: 76, height: 92)
    }
}

/// A gentle "alive" wiggle/breathe for a thriving avatar; still otherwise. Respects Reduce
/// Motion via the passed flag (the DelightKit modifiers themselves also honor the system
/// setting, so this is belt-and-suspenders).
private struct LivelyAvatar: ViewModifier {
    let thriving: Bool
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        if thriving && !reduceMotion {
            AnyView(content.breathing())
        } else {
            AnyView(content)
        }
    }
}

#if DEBUG
#Preview("Buddy face-off") {
    ZStack {
        Theme.background.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 16) {
                // Mixed day: you lead steps, buddy edges water, both moved.
                BuddyFaceOff(
                    mySteps: 9200, myStepGoal: 8000,
                    myWaterOz: 60, myWaterGoal: 90,
                    myWorkedOut: true,
                    myAvatar: .victoria,
                    buddy: .init(ownerUserID: "b", displayName: "Bryan",
                                 dayStreak: 9, characterMood: .thriving,
                                 loggedToday: true, lastActive: .now,
                                 stepsToday: 8800, stepGoal: 10000,
                                 waterToday: 96, waterGoal: 96,
                                 workedOutToday: true))

                // Both crush everything.
                BuddyFaceOff(
                    mySteps: 8200, myStepGoal: 8000,
                    myWaterOz: 95, myWaterGoal: 90,
                    myWorkedOut: true,
                    myAvatar: .bryan,
                    buddy: .init(ownerUserID: "b", displayName: "Victoria",
                                 dayStreak: 12, characterMood: .thriving,
                                 loggedToday: true, lastActive: .now,
                                 stepsToday: 11000, stepGoal: 10000,
                                 waterToday: 100, waterGoal: 96,
                                 workedOutToday: true))
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
