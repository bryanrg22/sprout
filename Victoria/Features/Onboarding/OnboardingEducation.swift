import Foundation

/// The value-first "here's what actually works" content shown BEFORE any numbers in
/// onboarding. Direct, confident, results-focused coaching — real nutrition/training
/// fundamentals, no hedging and no treating the user as fragile. Copy adapts by goal
/// direction (lose / maintain / gain) but keeps the same straight-talking spirit.
struct OnboardingEducation {
    /// A single teaching card: SF Symbol + headline + one-line "why".
    /// `id` is the icon name (unique within a set) so SwiftUI identity is STABLE across
    /// re-renders — no churn if the view rebuilds.
    struct Card: Identifiable {
        var id: String { icon }
        let icon: String
        let headline: String
        let why: String
    }

    /// 5 cards tuned to the goal direction — the real fundamentals, stated plainly.
    static func cards(for direction: GoalPace.Direction) -> [Card] {
        switch direction {
        case .gain:
            return [
                Card(icon: "fork.knife.circle.fill",
                     headline: "Eat enough to grow",
                     why: "Muscle is built from fuel — under-eating stalls a gain. Eat enough and the work pays off."),
                Card(icon: "fish.fill",
                     headline: "Protein builds muscle",
                     why: "It's the raw material for new muscle and it keeps you full. Hit it and your gains stay lean."),
                Card(icon: "dumbbell.fill",
                     headline: "Get stronger, not just bigger",
                     why: "Consistent strength training tells your body to turn that fuel into muscle, not just fat."),
                Card(icon: "moon.zzz.fill",
                     headline: "Sleep makes it easier",
                     why: "Your body does most of its muscle-building while you rest. Good sleep does heavy lifting."),
                Card(icon: "figure.walk.motion",
                     headline: "Move in a way you enjoy",
                     why: "You don't need 10,000 steps — ~7,000 brings most of the benefit. What you enjoy is what lasts."),
            ]
        case .lose, .maintain:
            return [
                Card(icon: "fork.knife.circle.fill",
                     headline: "Fuel the work",
                     why: "Eating too little backfires — it stalls progress and burns muscle. Eat enough, especially protein, and you lose fat, not strength."),
                Card(icon: "fish.fill",
                     headline: "Protein is your friend",
                     why: "Keeps you full and protects your muscle while you lean out. Hit it daily and you'll feel strong, not drained."),
                Card(icon: "dumbbell.fill",
                     headline: "Get stronger, not just smaller",
                     why: "Strength training keeps your muscle while you lean out — you'll feel capable, not just lighter."),
                Card(icon: "moon.zzz.fill",
                     headline: "Sleep makes it easier",
                     why: "Good sleep steadies your appetite and energy — quietly one of the biggest levers you've got."),
                Card(icon: "figure.walk.motion",
                     headline: "Move in a way you enjoy",
                     why: "You don't need 10,000 steps — ~7,000 brings most of the benefit. What you enjoy is what sticks."),
            ]
        }
    }

    /// A one-line intro shown above the cards, keyed to direction. Direct + confident.
    static func intro(for direction: GoalPace.Direction) -> String {
        switch direction {
        case .lose:
            return "A few things that actually move the needle. Lock these in and the results come."
        case .maintain:
            return "A few habits that keep you strong and steady. Lock these in and they stick."
        case .gain:
            return "A few things that actually build muscle. Lock these in and the work pays off."
        }
    }
}
