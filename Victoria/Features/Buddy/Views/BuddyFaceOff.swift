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
    /// A short label of MY workout today ("Chest · Arms", "Run · 30 min") so the Exercise row can
    /// say WHAT I did, not just "Moved!". Empty when I didn't log a session.
    let myWorkoutSummary: String
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
                    workoutSummary: myWorkoutSummary,
                    avatar: myAvatar)
    }

    /// The buddy's avatar is the OTHER pixel character by default (the payload doesn't
    /// carry an avatar choice): if I'm Victoria, my buddy shows as Bryan, and vice-versa.
    private var theirAvatar: CompanionAvatar { myAvatar.buddyStandIn }

    private var them: FaceOffSide {
        FaceOffSide(name: buddy.displayName.isEmpty ? "Buddy" : buddy.displayName,
                    steps: buddy.stepsToday, stepGoal: buddy.stepGoal,
                    waterOz: buddy.waterToday, waterGoal: buddy.waterGoal,
                    workedOut: buddy.workedOutToday,
                    workoutSummary: buddy.workoutSummary,
                    avatar: theirAvatar)
    }

    private var rows: [FaceOffMetric] {
        [.steps, .water, .gym].map { FaceOffMetric(kind: $0, me: me, them: them) }
    }

    /// A warm headline summarizing the whole day (counts only metrics both have a goal for).
    private var summary: (text: String, tone: FaceOffTone) {
        let bothWon = rows.filter { $0.bothReachedGoal }.count
        let scored = rows.filter { $0.isScorable }.count
        if scored == 0 { return ("Log a little movement to kick off today's face-off", .cheer) }
        if bothWon == scored { return ("You both crushed every goal today!", .win) }
        if bothWon > 0 { return ("You both showed up today — go you two!", .win) }
        return ("Day's underway — every little bit counts", .cheer)
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
            HStack(spacing: 7) {
                Image(systemName: summary.tone.symbol).font(.footnote.weight(.bold))
                Text(summary.text).font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(summary.tone.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(summary.tone.tint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
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
    /// Short label of today's workout ("Chest · Arms") — shown in the Exercise row instead of a
    /// bare "Moved!". Empty when no session was logged.
    var workoutSummary: String = ""
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
    /// The clean SF Symbol shown in the metric's tinted disc — the app speaks in symbols
    /// everywhere else, so a flat multicolor emoji (the sneaker especially) read as generic and
    /// broke the flow. These match the rest of the app's icon language (steps / water / strength).
    var symbol: String {
        switch self {
        case .steps: return "figure.walk"
        case .water: return "drop.fill"
        case .gym:   return "figure.strengthtraining.traditional"
        }
    }
    var title: String {
        switch self {
        case .steps: return "Steps"
        case .water: return "Water"
        case .gym:   return "Exercise"
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
    /// What each side did today (used by the gym row) — "Chest · Arms". Empty = no session logged.
    let myWorkoutSummary: String
    let theirWorkoutSummary: String

    var id: FaceOffMetricKind { kind }

    init(kind: FaceOffMetricKind, me: FaceOffSide, them: FaceOffSide) {
        self.kind = kind
        self.myName = me.name
        self.theirName = them.name
        self.myWorkoutSummary = me.workoutSummary
        self.theirWorkoutSummary = them.workoutSummary
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

    /// Warm, non-shaming outcome — clean text + a TONE that drives the styled result chip below (no
    /// baked emoji; the chip supplies a matching SF Symbol + tint). Celebrates a "both" day, gently
    /// cheers a leader while rooting for the other, stays encouraging when neither has hit goal yet.
    var outcome: (text: String, tone: FaceOffTone) {
        guard let m = myFraction, let t = theirFraction else {
            return ("Cheering you both on", .cheer)
        }
        // Gym is binary — phrase it as showing up, never as a score.
        if kind == .gym {
            switch (m >= 1, t >= 1) {
            case (true, true):   return ("You both moved today!", .win)
            case (true, false):  return ("You moved today — nice one", .win)
            case (false, true):  return ("\(theirName) moved today — your turn", .nudge)
            case (false, false): return ("A little movement is a win — no rush", .cheer)
            }
        }
        if m >= 1 && t >= 1 { return ("You both hit your goal!", .win) }
        // Compare progress, framed warmly. A small lead is "edged"; a clear one "ahead".
        let lead = m - t
        if abs(lead) < 0.08 { return ("Neck and neck — keep going!", .cheer) }
        if lead > 0 { return ("You're ahead on \(kind.title.lowercased()) — go you!", .win) }
        let verb = abs(lead) < 0.2 ? "edged you" : "is ahead"
        return ("\(theirName) \(verb) on \(kind.title.lowercased()) — go get it", .nudge)
    }
}

/// The emotional tone of a face-off outcome — drives the result chip's tint + SF Symbol so the copy
/// reads as a designed status, never a bare line of text + emoji.
enum FaceOffTone {
    case win    // both hit / you're ahead / you moved — a celebration
    case cheer  // neck-and-neck / no goal yet / no rush — warm encouragement
    case nudge  // buddy's ahead / your turn — a gentle "go get it"

    var tint: Color {
        switch self {
        case .win:   return Theme.positive
        case .cheer: return Theme.brand
        case .nudge: return Theme.info
        }
    }
    var symbol: String {
        switch self {
        case .win:   return "checkmark.seal.fill"
        case .cheer: return "flame.fill"
        case .nudge: return "arrow.up.forward.circle.fill"
        }
    }
}

/// A small, centered, soft-tinted result pill — an SF Symbol + the outcome text. Replaces the old
/// left-aligned "text + emoji" line so each metric's verdict reads as a designed component that sits
/// in the SAME visual language as the rings, the metric discs, and the nudge chips.
private struct OutcomeChip: View {
    let text: String
    let tone: FaceOffTone

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tone.symbol).font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(tone.tint)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(tone.tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tone.tint.opacity(0.22), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .center)   // center the hugging pill
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
                    Image(systemName: metric.kind.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
                Text(metric.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if metric.bothReachedGoal {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("both")
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
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
                            theirName: metric.theirName,
                            mySummary: metric.myWorkoutSummary,
                            theirSummary: metric.theirWorkoutSummary)
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

            OutcomeChip(text: metric.outcome.text, tone: metric.outcome.tone)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        func pct(_ f: Double?) -> String { f.map { "\(Int(($0 * 100).rounded())) percent of goal" } ?? "no goal set" }
        return "\(metric.kind.title): you \(pct(metric.myFraction)), \(metric.theirName) \(pct(metric.theirFraction)). \(metric.outcome.text)"
    }
}

/// A clean, on-brand **paired progress ring** for one metric: two rings (you + buddy) side by
/// side, each filled to **% of THAT person's own goal** (clamped 0...1 so both can top out), with
/// the % in the center and the person's name + exact value below. Uses the SAME ring language as
/// the dashboard + the buddy card, so the face-off reads as native — fair and playful, never raw
/// numbers against each other.
private struct PairedBarGraph: View {
    let myFraction: Double?
    let theirFraction: Double?
    /// Exact value shown under each ring (e.g. "8,432" steps, "44 oz" water). nil hides it.
    var myStat: String? = nil
    var theirStat: String? = nil
    let myName: String
    let theirName: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            Spacer(minLength: 0)
            ring(fraction: myFraction, tint: Theme.brand, name: myName, stat: myStat)
            ring(fraction: theirFraction, tint: Theme.info, name: theirName, stat: theirStat)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// One person's ring: a soft track + a tinted progress arc (rounded cap, same 6pt weight as
    /// the dashboard/buddy-card rings), the % in the center, then their first name + exact value.
    @ViewBuilder
    private func ring(fraction: Double?, tint: Color, name: String, stat: String?) -> some View {
        let f = min(max(fraction ?? 0, 0), 1)
        let reached = (fraction ?? 0) >= 1
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Theme.divider.opacity(0.55), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.001, f))
                    .stroke(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: f)
                Text(fraction == nil ? "—" : "\(Int((f * 100).rounded()))%")
                    .font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(reached ? tint : Theme.textPrimary)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .frame(width: 62, height: 62)
            Text(firstName(name))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let stat {
                Text(stat)
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1).fixedSize()
            }
        }
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
    var mySummary: String = ""
    var theirSummary: String = ""

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Spacer(minLength: 0)
            badge(name: firstName(myName), moved: iMoved, summary: mySummary, tint: Theme.brand)
            badge(name: firstName(theirName), moved: theyMoved, summary: theirSummary, tint: Theme.info)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func badge(name: String, moved: Bool, summary: String, tint: Color) -> some View {
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
            // Show WHAT they did when we know it ("Chest · Arms") — cooler + more telling than a bare
            // "Moved!"; falls back to "Moved!" / "Not yet". Still no numbers, reps, or intensity.
            Text(moved ? (summary.isEmpty ? "Moved! 💪" : summary) : "Not yet")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 104)
        .opacity(moved ? 1 : 0.85)
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// A 1pt horizontal line shape for the dotted goal marker.

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
            // My own character (the buddy is always a built-in stand-in): one image for
            // every mood, in the same 120×144 box the grid characters are authored at.
            case .custom:   CustomCompanionImage().frame(width: 120, height: 144)
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
                    myWorkoutSummary: "Chest · Arms",
                    myAvatar: .victoria,
                    buddy: .init(ownerUserID: "b", displayName: "Sam",
                                 dayStreak: 9, characterMood: .thriving,
                                 loggedToday: true, lastActive: .now,
                                 stepsToday: 8800, stepGoal: 10000,
                                 waterToday: 96, waterGoal: 96,
                                 workedOutToday: true, workoutSummary: "Legs · Glutes"))

                // Both crush everything.
                BuddyFaceOff(
                    mySteps: 8200, myStepGoal: 8000,
                    myWaterOz: 95, myWaterGoal: 90,
                    myWorkedOut: true,
                    myWorkoutSummary: "Push day",
                    myAvatar: .bryan,
                    buddy: .init(ownerUserID: "b", displayName: "Alex",
                                 dayStreak: 12, characterMood: .thriving,
                                 loggedToday: true, lastActive: .now,
                                 stepsToday: 11000, stepGoal: 10000,
                                 waterToday: 100, waterGoal: 96,
                                 workedOutToday: true, workoutSummary: "Run · 30 min"))
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
