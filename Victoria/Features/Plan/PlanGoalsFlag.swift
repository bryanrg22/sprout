import Foundation
import SwiftData

/// "Your goals changed since this plan was built" — a per-plan flag that survives
/// relaunch WITHOUT touching the SwiftData/CloudKit schema (it's keyed by the plan's
/// id in UserDefaults). A rebuild updates the existing plan row in place and keeps its
/// id, so `PlanService.generate` clears the flag explicitly when a build succeeds.
///
/// Set whenever one of the goal inputs in `PlanGoalInputs` changes, from either surface:
/// Settings observes the inputs, and `CoachTools.applyReturningUndo` compares them before
/// and after every tool. Read by PlanCard to offer the FULL rebuild with fresh web research
/// instead of the light review.
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

/// The profile inputs a plan is built around: the goal (direction and pace, goal weight,
/// starting weight) and what her energy needs are computed from (activity level, sex,
/// height, birth date). A change to any of them makes the plan's premises stale, so the
/// plan is flagged and PlanCard offers a rebuild. Weigh-ins are not here: following the
/// weight trend is what the plan's review pass is for.
struct PlanGoalInputs: Equatable {
    var paceRaw: String
    var activityLevelRaw: String
    var goalWeightLbs: Double
    var startWeightLbs: Double
    var sexRaw: String
    var heightCm: Double
    var birthDate: Date

    init(_ profile: UserProfile) {
        paceRaw = profile.paceRaw
        activityLevelRaw = profile.activityLevelRaw
        goalWeightLbs = profile.goalWeightLbs
        startWeightLbs = profile.startWeightLbs
        sexRaw = profile.sexRaw
        heightCm = profile.heightCm
        birthDate = profile.birthDate
    }

    var direction: GoalPace.Direction { (GoalPace(rawValue: paceRaw) ?? .relaxed).direction }

    /// Brings the plan and the targets up to date after the profile changed from `before`.
    /// The one call every surface that edits the profile makes (Settings, and
    /// `CoachTools.applyReturningUndo` for every tool):
    ///
    /// 1. a plan with no direction record was written for the direction in force BEFORE the change;
    /// 2. a changed goal input flags the plan, so PlanCard offers the rebuild;
    /// 3. the plan's numbers are mirrored into, or taken out of, the targets (`PlanTargetSync`).
    static func profileChanged(from before: PlanGoalInputs, profile: UserProfile, context: ModelContext) {
        let plan = CoachPlan.current(in: context)
        plan?.adoptAnchorsIfMissing(current: before.direction)
        if PlanGoalInputs(profile) != before { plan?.markGoalsChanged() }
        PlanTargetSync.apply(plan: plan, to: profile)
    }
}

/// Which goal direction each of the plan's numbers was written for.
///
/// A loss plan's calorie range is wrong for a gain goal, and the reverse, so the plan's
/// numbers only drive the app's targets while the profile's direction is the one they were
/// written for (`PlanTargetSync`). The plan row itself is never changed by a direction
/// switch, which is what makes the switch reversible: go back to the old direction and the
/// same numbers drive again.
///
/// Stored in UserDefaults keyed by the plan's id, like the goals-changed flag, and for the
/// same reason: `CoachPlan` is mirrored to CloudKit, and a new attribute would have to be
/// deployed to the Production schema before a build could ship. The cost is that the
/// record is per device; a device that has no record for a plan treats the plan as written
/// for the direction it sees first (`adoptAnchorsIfMissing`).
///
/// Calories and protein are recorded separately because they can be written at different
/// times: a build writes both, `edit_plan` and `set_protein_goal` may write one.
extension CoachPlan {
    private var caloriesDirectionKey: String { "plan.caloriesDirection.\(id.uuidString)" }
    private var proteinDirectionKey: String { "plan.proteinDirection.\(id.uuidString)" }

    /// The direction the calorie range was written for; nil when this device has no record.
    var caloriesDirection: GoalPace.Direction? {
        get { UserDefaults.standard.string(forKey: caloriesDirectionKey).flatMap(GoalPace.Direction.init(storedName:)) }
        set { Self.store(newValue, forKey: caloriesDirectionKey) }
    }

    /// The direction the protein target was written for; nil when this device has no record.
    var proteinDirection: GoalPace.Direction? {
        get { UserDefaults.standard.string(forKey: proteinDirectionKey).flatMap(GoalPace.Direction.init(storedName:)) }
        set { Self.store(newValue, forKey: proteinDirectionKey) }
    }

    /// A build or rebuild wrote every number for `direction`.
    func anchorTargets(to direction: GoalPace.Direction) {
        caloriesDirection = direction
        proteinDirection = direction
    }

    /// A plan from before this record existed (or from another device) is taken to be
    /// written for the direction in force now, unless the goals-changed flag says the
    /// goals moved since it was built, in which case the direction it was written for is
    /// unknown and its numbers are left driving, as they did before.
    func adoptAnchorsIfMissing(current direction: GoalPace.Direction) {
        guard !goalsChangedSinceBuild else { return }
        if caloriesDirection == nil { caloriesDirection = direction }
        if proteinDirection == nil { proteinDirection = direction }
    }

    private static func store(_ direction: GoalPace.Direction?, forKey key: String) {
        if let direction { UserDefaults.standard.set(direction.storedName, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

extension GoalPace.Direction {
    /// A stable spelling for UserDefaults (the enum has no raw value).
    var storedName: String {
        switch self {
        case .lose:     return "lose"
        case .maintain: return "maintain"
        case .gain:     return "gain"
        }
    }

    init?(storedName: String) {
        switch storedName {
        case "lose":     self = .lose
        case "maintain": self = .maintain
        case "gain":     self = .gain
        default:         return nil
        }
    }
}

/// What the plan card and the coach are told when the plan no longer matches the goals.
enum PlanGoalsCopy {
    /// Appended to the coach's context after the plan block, which always lists the plan's
    /// own numbers. Empty when the plan matches the goals.
    static func coachNote(plan: CoachPlan?, profile: UserProfile) -> String {
        guard let plan else { return "" }
        if PlanTargetSync.isSuspended(plan: plan, for: profile) {
            return "\n\nNOTE on the Plan: it was written for a different goal direction than the one in "
                + "force now, so the app has set its calorie range and protein target aside. The targets "
                + "in the data above are the calculated ones and are the ones that count. Do not quote "
                + "the Plan's numbers as current targets; the Plan card on Progress offers a rebuild."
        }
        if plan.goalsChangedSinceBuild {
            return "\n\nNOTE on the Plan: something it was built around (pace, activity level, goal or "
                + "starting weight, sex, height or age) changed since it was built. Its numbers still set "
                + "the targets; the Plan card on Progress offers a rebuild around what is set now."
        }
        return ""
    }

    /// The title of the notice on the plan card.
    static let bannerTitle = "Your goals or details changed since this plan was built"

    /// The sentence under it.
    static func bannerBody(suspended: Bool) -> String {
        suspended
            ? "This plan was built for a different goal, so its numbers are set aside: your daily targets are calculated ones until you rebuild. A fresh build re-does the research around the goal you have now."
            : "These targets were researched for what you had set before, and they still set your daily targets. A fresh build re-does the research around what you have now."
    }
}
