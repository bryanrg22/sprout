import Foundation

/// "Your goals changed since this plan was built" — a per-plan flag that survives
/// relaunch WITHOUT touching the SwiftData/CloudKit schema (it's keyed by the plan's
/// id in UserDefaults, so a rebuild — which mints a new plan id — clears it naturally).
///
/// Set from BOTH goal-editing surfaces (Settings → Your goals, and Vita's
/// set_goal_direction tool); read by PlanCard to offer the FULL rebuild with fresh
/// web research instead of the light review — a direction flip or a new goal weight
/// invalidates the plan's premises, not just its numbers.
extension CoachPlan {
    private var goalsChangedKey: String { "plan.goalsChanged.\(id.uuidString)" }

    var goalsChangedSinceBuild: Bool {
        UserDefaults.standard.bool(forKey: goalsChangedKey)
    }

    func markGoalsChanged() {
        UserDefaults.standard.set(true, forKey: goalsChangedKey)
    }
}
