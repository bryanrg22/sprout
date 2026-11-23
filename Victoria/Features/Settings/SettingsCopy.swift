import Foundation

/// The sentences in Settings that say what a change does. They are functions of state, not
/// literals in the view, because what a change does depends on whether an adaptive plan is
/// setting the targets, and a sentence that promises the wrong thing is a defect
/// (EVAL_REPORT 3, L-B2: "updates your daily targets right away" was shown with a plan
/// whose numbers did not move).
enum SettingsCopy {

    /// What sets the calorie and protein targets right now.
    enum TargetSource: Equatable {
        /// No plan, or a plan with no numbers: the targets are computed from the profile.
        case calculated
        /// The adaptive plan's numbers are the targets.
        case plan
        /// A plan exists, but it was written for another goal direction, so the targets are
        /// the computed ones until it is rebuilt.
        case planSetAside
    }

    static func targetSource(hasPlanNumbers: Bool, suspended: Bool) -> TargetSource {
        guard hasPlanNumbers else { return .calculated }
        return suspended ? .planSetAside : .plan
    }

    /// The footer under "Your goals": the journey in one sentence, then either a heads-up
    /// when the direction and the goal weight disagree, or what changing these does.
    static func goalsFooter(startWeightLbs: Double, goalWeightLbs: Double, currentWeightLbs: Double,
                            pace: GoalPace, source: TargetSource, units: UnitSystem = .imperial) -> String {
        var text = "Started at \(units.format(startWeightLbs, decimals: 0)) → aiming for \(units.format(goalWeightLbs, decimals: 0)) at a \(pace.label.lowercased()) pace."
        switch pace.direction {
        case .lose where goalWeightLbs >= currentWeightLbs:
            text += " Heads-up: your goal weight is at or above where you are now — for a lose goal, set it below your current weight."
        case .gain where goalWeightLbs <= currentWeightLbs:
            text += " Heads-up: your goal weight is at or below where you are now — for a gain goal, set it above your current weight."
        default:
            break
        }
        return text + " " + whatChangingDoes(source)
    }

    static func whatChangingDoes(_ source: TargetSource) -> String {
        switch source {
        case .calculated:
            return "Goal and pace change your daily calories right away. Goal weight and starting weight move your chart, not your calories."
        case .plan:
            return "Your adaptive plan sets your daily targets. Switching between lose, maintain and gain sets the plan's numbers aside and uses calculated targets until you rebuild it. Changing pace, activity, goal weight or starting weight keeps the plan's numbers and marks the plan for a rebuild on Progress."
        case .planSetAside:
            return "Your adaptive plan was built for a different goal, so your daily targets are calculated ones for now. Rebuild the plan on Progress, or switch the goal back to use its numbers again."
        }
    }

    /// The footer under "Your daily targets".
    static func targetsFooter(source: TargetSource, planFloor: Double, planProtein: Double,
                              clampedToFloor: Bool, coachName: String) -> String {
        switch source {
        case .plan:
            let protein = planProtein > 0 ? ", protein \(Int(planProtein)) g" : ""
            let floor = planFloor > 0 ? "floor \(Int(planFloor)) kcal" : "calories calculated from your weight"
            return "Set by your adaptive plan — \(floor)\(protein). Ask \(coachName) to adjust the plan to change these. (Calories are kept at or above a safe minimum.)"
        case .planSetAside:
            return "Calculated from your weight and goal. Your adaptive plan was built for a different goal, so its numbers are set aside until you rebuild it on Progress."
        case .calculated:
            return clampedToFloor
                ? "Adjusted up to a safe minimum — we never recommend going lower. Targets update with your weight and goal."
                : "Calculated from your weight and goal. Updates automatically as you log."
        }
    }

    /// Height as feet and inches. The total is rounded to whole inches FIRST and then split,
    /// so 182 cm (71.65 in) is 6′0″; splitting before rounding gave 5′0″.
    static func feetAndInches(cm: Double) -> (feet: Int, inches: Int) {
        let total = Int((cm / 2.54).rounded())
        return (total / 12, total % 12)
    }

    static func heightText(cm: Double) -> String {
        let h = feetAndInches(cm: cm)
        return "\(h.feet)′\(h.inches)″ (\(Int(cm.rounded())) cm)"
    }
}
