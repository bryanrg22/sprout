import Foundation

/// "Your goals changed since this plan was built" — a per-plan flag that survives
/// relaunch WITHOUT touching the SwiftData/CloudKit schema (it's keyed by the plan's
/// id in UserDefaults). A rebuild updates the existing plan row in place and keeps its
/// id, so `PlanService.generate` clears the flag explicitly when a build succeeds.
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

    /// The plan was just rebuilt against the current goals.
    func clearGoalsChanged() {
        UserDefaults.standard.removeObject(forKey: goalsChangedKey)
    }
}
