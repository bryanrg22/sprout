import Foundation

/// How the active plan's targets are mirrored into the profile overrides that the rings,
/// achievements and Vita's context read through `dailyCalorieTarget` / `macroTargets`.
enum PlanTargetSync {

    struct PlanTargets: Equatable {
        var hasRange: Bool
        var calorieMin: Double
        var calorieMax: Double
        var proteinTarget: Double
        /// The goal direction each number was written for (`CoachPlan.caloriesDirection` /
        /// `proteinDirection`); nil when unknown, which is treated as "the current one".
        var caloriesDirection: GoalPace.Direction? = nil
        var proteinDirection: GoalPace.Direction? = nil
    }

    struct Overrides: Equatable {
        var calorie: Double
        var calorieMax: Double
        var protein: Double
    }

    /// With a plan, the plan's numbers win. With NO plan the calorie overrides fall back to 0
    /// (the computed defaults, since only a plan ever sets them), but the protein override is
    /// left as it is: without a plan its only writer is the user, through Vita's
    /// `set_protein_goal`, and that choice must survive a relaunch.
    ///
    /// A plan number written for a different goal direction than `direction` does not drive
    /// anything: its override is 0, so the target is the computed one, until the plan is
    /// rebuilt or the number is set again for the new direction. Nothing on the plan is
    /// changed, so switching the direction back brings the same number back.
    static func overrides(plan: PlanTargets?, currentProtein: Double,
                          direction: GoalPace.Direction? = nil) -> Overrides {
        guard let plan else {
            return Overrides(calorie: 0, calorieMax: 0, protein: max(0, currentProtein))
        }
        let caloriesApply = applies(writtenFor: plan.caloriesDirection, now: direction)
        let proteinApplies = applies(writtenFor: plan.proteinDirection, now: direction)
        return Overrides(calorie: plan.hasRange && caloriesApply ? plan.calorieMin : 0,
                         calorieMax: plan.hasRange && caloriesApply ? plan.calorieMax : 0,
                         protein: proteinApplies ? max(0, plan.proteinTarget) : 0)
    }

    /// True when the plan has numbers that the current direction keeps from driving the targets.
    static func isSuspended(plan: PlanTargets?, direction: GoalPace.Direction) -> Bool {
        guard let plan else { return false }
        let calories = plan.hasRange && !applies(writtenFor: plan.caloriesDirection, now: direction)
        let protein = plan.proteinTarget > 0 && !applies(writtenFor: plan.proteinDirection, now: direction)
        return calories || protein
    }

    private static func applies(writtenFor: GoalPace.Direction?, now: GoalPace.Direction?) -> Bool {
        guard let writtenFor, let now else { return true }
        return writtenFor == now
    }
}

extension PlanTargetSync.PlanTargets {
    init(_ plan: CoachPlan) {
        self.init(hasRange: plan.hasRange, calorieMin: plan.calorieMin, calorieMax: plan.calorieMax,
                  proteinTarget: plan.proteinTarget,
                  caloriesDirection: plan.caloriesDirection, proteinDirection: plan.proteinDirection)
    }
}

extension PlanTargetSync {
    /// Writes the overrides for `plan` (the current plan, or nil) into `profile`. Called at
    /// launch, when the plan changes, and when the goal direction changes.
    static func apply(plan: CoachPlan?, to profile: UserProfile) {
        let direction = profile.pace.direction
        plan?.adoptAnchorsIfMissing(current: direction)
        let next = overrides(plan: plan.map(PlanTargets.init),
                             currentProtein: profile.proteinTargetOverride,
                             direction: direction)
        if profile.calorieTargetOverride != next.calorie { profile.calorieTargetOverride = next.calorie }
        if profile.calorieMaxOverride != next.calorieMax { profile.calorieMaxOverride = next.calorieMax }
        if profile.proteinTargetOverride != next.protein { profile.proteinTargetOverride = next.protein }
    }

    /// Whether `plan`'s numbers are held back from the targets for `profile`'s direction.
    static func isSuspended(plan: CoachPlan?, for profile: UserProfile) -> Bool {
        isSuspended(plan: plan.map(PlanTargets.init), direction: profile.pace.direction)
    }
}
