import Foundation

/// The proactive *recommendation* counterpart to `DailyInsightEngine`.
///
/// Where `DailyInsightEngine` celebrates a single day, this engine looks at a few
/// weeks of history and asks one question: **has she so consistently CLEARED a
/// goal that the goal itself is now too easy?** If so, it PROPOSES nudging that
/// goal up a notch — but it never changes anything itself. The card layer turns a
/// `Recommendation` into a one-tap card she must approve.
///
/// This is PURE, free, on-device logic — no LLM, no network. The caller assembles a
/// flat `Input` from SwiftData; the engine stays a testable function of that input.
///
/// ## Anti-restriction contract (load-bearing — the primary user UNDER-eats and is
/// image-sensitive)
/// Every rule here is HEALTH-POSITIVE and one-directional:
/// - It ONLY ever proposes *raising* a goal (more steps, more water).
/// - It NEVER proposes lowering anything, and NEVER touches calories, macros, weight,
///   or pace. Those are off-limits by design, not by threshold.
/// - Each `Recommendation.apply` re-checks and refuses to lower its field, so even a
///   buggy caller can't turn a "nudge up" into a cut.
/// - Silence is the default. With nothing genuinely earned, it returns `[]`.
enum RecommendationEngine {

    // MARK: Inputs

    /// A flat, testable snapshot of recent behavior. The caller (the card or a
    /// background job) builds this from SwiftData; the engine never reads the store.
    ///
    /// History arrays are **most-recent-first, one entry per day**, already
    /// aggregated to a daily total. `metGoalStreakDays`-style fields are derived by
    /// the caller (it owns the calendar) so the engine stays pure arithmetic.
    struct Input {
        // Steps
        /// Current daily step goal (`UserProfile.dailyStepGoal`).
        var stepGoal: Int
        /// Consecutive days (incl. today) she comfortably met/exceeded the step goal.
        var stepGoalMetStreakDays: Int
        /// Her typical daily steps over that recent run — used to size a sensible bump.
        var typicalDailySteps: Int

        // Hydration
        /// Current effective daily water goal in oz (`UserProfile.waterTargetOz`).
        var waterGoalOz: Double
        /// Consecutive days (incl. today) she met/exceeded the water goal.
        var waterGoalMetStreakDays: Int
        /// Her typical daily water over that recent run, in oz.
        var typicalDailyWaterOz: Double

        /// Total days of history available. We stay quiet until there's enough signal
        /// to trust a streak (a 12-day streak means little if we only have 12 days and
        /// no sense of whether it's stable).
        var daysOfHistory: Int

        public init(
            stepGoal: Int,
            stepGoalMetStreakDays: Int,
            typicalDailySteps: Int,
            waterGoalOz: Double,
            waterGoalMetStreakDays: Int,
            typicalDailyWaterOz: Double,
            daysOfHistory: Int
        ) {
            self.stepGoal = stepGoal
            self.stepGoalMetStreakDays = stepGoalMetStreakDays
            self.typicalDailySteps = typicalDailySteps
            self.waterGoalOz = waterGoalOz
            self.waterGoalMetStreakDays = waterGoalMetStreakDays
            self.typicalDailyWaterOz = typicalDailyWaterOz
            self.daysOfHistory = daysOfHistory
        }
    }

    // MARK: Output

    /// A proposed (never applied) change to a single setting. `id` is stable so the
    /// card can snooze a specific proposal without re-nagging.
    struct Recommendation: Identifiable, Equatable {
        /// Stable identity, e.g. `"raise_step_goal"`. Used for snooze keys + dedup.
        let id: String
        /// Short headline shown on the card, e.g. "Ready for more steps?".
        let title: String
        /// One or two warm sentences explaining *why* — celebratory, never corrective.
        let rationale: String
        /// What the [Apply] button will show, e.g. "8,000 → 9,000 steps".
        let applyButtonLabel: String
        /// A tiny success line shown after applying, e.g. "New goal: 9,000 steps 🎉".
        let appliedConfirmation: String
        /// SF Symbol + tint for the card's leading badge.
        let systemImage: String
        let tintToken: Tint
        /// Higher = more worth proposing right now. The card shows the single best.
        let score: Int
        /// Whether [Not now] is offered. Always `true` here — a proposal must be
        /// declineable; we never corner her. Kept explicit per the spec.
        let declineable: Bool

        /// Applies the change to the live profile. Guaranteed one-directional: each
        /// closure re-checks and will only ever RAISE its field, never lower it.
        /// Captured as a closure (not a keypath) so each rule owns its safe math.
        let apply: (UserProfile) -> Void

        enum Tint: Equatable { case brand, info, water, positive }

        // Equatable: compare identity + the visible payload. Closures aren't
        // comparable, so we deliberately exclude `apply` (two recs with the same id
        // and copy are "equal" for test/dedup purposes).
        static func == (lhs: Recommendation, rhs: Recommendation) -> Bool {
            lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.applyButtonLabel == rhs.applyButtonLabel &&
            lhs.score == rhs.score
        }
    }

    // MARK: Tunables (named so the thresholds are defensible, not magic numbers)

    private enum Rule {
        /// Don't trust a streak until we have a few weeks of context.
        static let minHistoryDays = 12
        /// Steps: ~10–14 straight days of clearing the goal before we propose a bump.
        static let stepStreakDays = 10
        /// Hydration habits form faster and matter less if slightly off; 10 days too.
        static let waterStreakDays = 10
        /// Only propose if she's clearing the goal with real headroom, not squeaking
        /// past it — otherwise a bump would immediately feel like a setback.
        static let stepHeadroom = 1.10      // typical ≥ 110% of goal
        static let waterHeadroom = 1.10
        /// Step bump granularity (nice round numbers she'd recognize).
        static let stepBumpIncrement = 1000
        /// Cap the step goal we'll ever propose — past this it stops being "a notch".
        static let stepGoalCap = 15_000
        /// Water bump in oz (~one extra glass), and the most we'll ever propose.
        static let waterBumpOz = 8.0
        static let waterGoalCapOz = 120.0
    }

    // MARK: Evaluate

    /// The single best recommendation to propose right now, or `nil` for silence.
    /// `snoozed` are ids the user tapped "Not now" on recently; they're filtered out
    /// so the card never re-nags about something she already declined.
    static func bestRecommendation(_ i: Input, snoozed: Set<String> = []) -> Recommendation? {
        recommendations(i)
            .filter { !snoozed.contains($0.id) }
            .max(by: { $0.score < $1.score })
    }

    /// All currently-earned recommendations, each pre-scored. Returns `[]` when
    /// nothing is genuinely warranted (the common, healthy case).
    static func recommendations(_ i: Input) -> [Recommendation] {
        // Gate 1: not enough history to trust any streak yet → stay quiet.
        guard i.daysOfHistory >= Rule.minHistoryDays else { return [] }

        var out: [Recommendation] = []

        // ── Steps: consistently clearing the goal with headroom → propose +1k ──
        if i.stepGoal > 0,
           i.stepGoalMetStreakDays >= Rule.stepStreakDays,
           Double(i.typicalDailySteps) >= Double(i.stepGoal) * Rule.stepHeadroom,
           i.stepGoal < Rule.stepGoalCap {

            // Size the bump from how far past the goal she actually is, snapped to a
            // round 1k, clamped to a single comfortable notch and the overall cap.
            let proposed = proposedStepGoal(current: i.stepGoal, typical: i.typicalDailySteps)
            if proposed > i.stepGoal {     // never propose a no-op or a decrease
                out.append(.init(
                    id: "raise_step_goal",
                    title: "Ready for a few more steps?",
                    rationale: "You've topped your \(fmt(i.stepGoal))-step goal \(i.stepGoalMetStreakDays) days running — your body's clearly up for it. Want to set the bar a little higher?",
                    applyButtonLabel: "\(fmt(i.stepGoal)) → \(fmt(proposed)) steps",
                    appliedConfirmation: "New step goal: \(fmt(proposed)) 🎉",
                    systemImage: "figure.walk.motion",
                    tintToken: .info,
                    score: 70,
                    declineable: true,
                    apply: { profile in
                        // One-directional guard: only ever raise, and respect the cap.
                        let next = min(proposed, Rule.stepGoalCap)
                        if next > profile.dailyStepGoal { profile.dailyStepGoal = next }
                    }))
            }
        }

        // ── Hydration: consistently meeting the goal with headroom → propose +1 glass ──
        if i.waterGoalOz > 0,
           i.waterGoalMetStreakDays >= Rule.waterStreakDays,
           i.typicalDailyWaterOz >= i.waterGoalOz * Rule.waterHeadroom,
           i.waterGoalOz < Rule.waterGoalCapOz {

            let proposed = proposedWaterGoalOz(current: i.waterGoalOz)
            if proposed > i.waterGoalOz {
                out.append(.init(
                    id: "raise_water_goal",
                    title: "Add a glass to your water goal?",
                    rationale: "You've hit your hydration goal \(i.waterGoalMetStreakDays) days in a row 💧 Nudging it up a touch keeps that great habit growing with you.",
                    applyButtonLabel: "\(oz(i.waterGoalOz)) → \(oz(proposed))",
                    appliedConfirmation: "New water goal: \(oz(proposed)) 💧",
                    systemImage: "drop.fill",
                    tintToken: .water,
                    score: 55,
                    declineable: true,
                    apply: { profile in
                        // Bump the explicit override (the only writable water knob).
                        // Only ever raise vs. her CURRENT effective goal, and cap it.
                        let next = min(proposed, Rule.waterGoalCapOz)
                        if next > profile.waterTargetOz {
                            profile.waterGoalOzOverride = next
                        }
                    }))
            }
        }

        return out
    }

    // MARK: Bump sizing (pure helpers — also unit-testable)

    /// Next step goal: round her typical down to the nearest 1k as an "easy" target,
    /// but move at most one full increment past the current goal so it stays gentle.
    static func proposedStepGoal(current: Int, typical: Int) -> Int {
        let roundedTypical = (typical / Rule.stepBumpIncrement) * Rule.stepBumpIncrement
        let oneNotch = current + Rule.stepBumpIncrement
        let target = min(roundedTypical, oneNotch)          // never overshoot a notch
        return min(max(target, current + Rule.stepBumpIncrement), Rule.stepGoalCap)
    }

    /// Next water goal: one extra glass (~8 oz) above the current goal, capped.
    static func proposedWaterGoalOz(current: Double) -> Double {
        min((current + Rule.waterBumpOz).rounded(), Rule.waterGoalCapOz)
    }

    // MARK: Formatting

    private static func fmt(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic))
    }
    private static func oz(_ v: Double) -> String { "\(Int(v.rounded())) oz" }
}
