import Foundation

/// The "cheap gate" of the proactive-AI architecture (see RESEARCH_ai_native.md).
///
/// This is PURE, free, on-device logic — no LLM. It reads the day's already-computed
/// numbers, scores a set of HEALTH-POSITIVE candidate insights, and returns the single
/// best+freshest one (or nil — silence is a feature). An LLM is NOT needed to *detect*
/// an insight; later it will only *rephrase* the chosen one in a warmer voice.
///
/// Anti-restriction contract (the end user under-eats): every insight celebrates
/// sufficiency, protein, hydration, consistency, or showing up. NOTHING here rewards
/// eating less, a deficit, "cutting", or labels food good/bad. The gentlest nudge is
/// "let's get you fed," never "you ate too much."
enum DailyInsightEngine {

    // MARK: Inputs

    /// A flat, testable snapshot of what the engine reasons over. The caller (dashboard
    /// or a background job) assembles this from SwiftData; the engine stays pure.
    struct Input {
        var caloriesEaten: Double
        var calorieTarget: Double
        var protein: Double
        var proteinTarget: Double
        var waterOz: Double
        var waterGoalOz: Double
        var steps: Int
        var stepGoal: Int
        var loggedAnythingToday: Bool
        var loggingStreakDays: Int        // consecutive days with any log, incl. today
        var proteinHitStreakDays: Int     // consecutive days protein target met
        var hydrationHitStreakDays: Int   // consecutive days water goal met
        var workoutToday: Bool
        var hourOfDay: Int                 // 0...23, so we don't say "fuel up" at 9am
    }

    // MARK: Output

    /// A scored candidate. `id` is stable so we can avoid repeating it day-to-day.
    /// `template` is the free, shippable copy; the optional AI layer will rephrase it.
    struct Insight: Identifiable, Equatable {
        let id: String
        let template: String
        /// A tiny factual summary handed to the optional AI rephraser (NOT advice; just
        /// the observation, e.g. "28-day logging streak"). Defaults to the template.
        var factualHint: String = ""
        /// SF Symbol + tint for the card.
        let systemImage: String
        let tintToken: Tint
        /// Higher = more worth saying today.
        let score: Int

        enum Tint { case brand, protein, water, info, warning, positive }
    }

    // MARK: Evaluate

    /// Returns the single best insight to show today, or nil if nothing crosses a
    /// threshold worth a fresh sentence. `recentlyShown` are ids shown in the last
    /// few days (so we stay fresh); a freshly-eligible insight beats a stale repeat.
    static func bestInsight(_ i: Input, recentlyShown: Set<String> = []) -> Insight? {
        let candidates = allCandidates(i)
        // Prefer fresh (not recently shown); among those, highest score. Fall back to
        // the best candidate even if shown, so the card is rarely empty when warranted.
        let fresh = candidates.filter { !recentlyShown.contains($0.id) }
        return (fresh.isEmpty ? candidates : fresh).max(by: { $0.score < $1.score })
    }

    /// All currently-true candidates, each pre-scored. Order doesn't matter; the caller picks.
    static func allCandidates(_ i: Input) -> [Insight] {
        var out: [Insight] = []
        let calFrac = i.calorieTarget > 0 ? i.caloriesEaten / i.calorieTarget : 0
        let proFrac = i.proteinTarget > 0 ? i.protein / i.proteinTarget : 0

        // --- The gentle, MOST IMPORTANT nudge: under-fueled late in the day ---
        // Only after ~6pm, only if she's logged something (so it's not just an empty
        // morning), and only when genuinely low. Never shaming — an invitation to eat.
        if i.loggedAnythingToday, i.hourOfDay >= 18, calFrac < 0.5, i.calorieTarget > 0 {
            out.append(.init(
                id: "fuel_up",
                template: "You're a bit under your fuel for today — a real dinner or a solid snack would help you feel your best. 🥣",
                factualHint: "She's eaten well under her daily fuel and it's evening — a gentle, caring nudge to eat a proper dinner/snack (never about eating less).",
                systemImage: "fork.knife", tintToken: .warning, score: 100))
        }

        // --- Celebrate hitting protein (single day) ---
        if proFrac >= 1.0 {
            out.append(.init(
                id: "protein_hit",
                template: "You hit your protein today — that's what keeps you full, strong, and recovering well. 💪",
                systemImage: "p.circle.fill", tintToken: .protein, score: 60))
        }
        // --- Protein STREAK (more special) ---
        if i.proteinHitStreakDays >= 3 {
            out.append(.init(
                id: "protein_streak",
                template: "\(i.proteinHitStreakDays) days of hitting your protein in a row — your body is getting exactly what it needs. 🌟",
                factualHint: "She hit her protein goal \(i.proteinHitStreakDays) days in a row — celebrate this streak.",
                systemImage: "flame.fill", tintToken: .protein, score: 85))
        }

        // --- Ate enough (sufficiency win) ---
        if calFrac >= 0.85, calFrac <= 1.25 {
            out.append(.init(
                id: "well_fueled",
                template: "You fueled yourself well today — eating enough is exactly how the weight comes off and stays off. 💚",
                systemImage: "checkmark.seal.fill", tintToken: .positive, score: 70))
        }

        // --- Hydration ---
        if i.waterGoalOz > 0, i.waterOz >= i.waterGoalOz {
            out.append(.init(
                id: "hydrated",
                template: "Hydration goal met 💧 small thing, big difference for energy and how full you feel.",
                systemImage: "drop.fill", tintToken: .water, score: 45))
        }
        if i.hydrationHitStreakDays >= 3 {
            out.append(.init(
                id: "hydration_streak",
                template: "\(i.hydrationHitStreakDays) days hydrated in a row — you're building a real habit.",
                systemImage: "drop.fill", tintToken: .water, score: 55))
        }

        // --- Showing up / consistency (the biggest predictor of success) ---
        if i.loggingStreakDays >= 7 {
            out.append(.init(
                id: "streak_week",
                template: "\(i.loggingStreakDays) days logged in a row. Showing up beats being perfect — proud of you.",
                systemImage: "calendar", tintToken: .brand, score: 80))
        } else if i.loggingStreakDays == 3 {
            out.append(.init(
                id: "streak_3",
                template: "Three days in a row — that's how a habit starts. Keep it gentle and steady.",
                systemImage: "calendar", tintToken: .brand, score: 50))
        }

        // --- Movement ---
        if i.workoutToday {
            out.append(.init(
                id: "moved",
                template: "You moved your body today — even a little counts, and it adds up. 🏃‍♀️",
                systemImage: "figure.run", tintToken: .info, score: 48))
        } else if i.stepGoal > 0, i.steps >= i.stepGoal {
            out.append(.init(
                id: "steps_goal",
                template: "Step goal reached today — nice work getting those in. 👟",
                systemImage: "shoeprints.fill", tintToken: .info, score: 44))
        }

        // --- Quiet, unconditional kindness (low score, only wins if nothing else) ---
        if i.loggedAnythingToday {
            out.append(.init(
                id: "gentle_default",
                template: "Every time you check in, you're learning your body a little better. That's the whole game. 💛",
                systemImage: "sparkles", tintToken: .brand, score: 10))
        }

        return out
    }
}
