import Foundation
import SwiftData

/// The coach's SAFE, health-positive tool surface.
///
/// Vita ("the coach") may *propose* changing a small set of encouragement-oriented
/// settings — daily step goal, water goal, and goal pace. Everything here is designed
/// around two hard rules:
///
/// 1. **Nothing applies without a one-tap confirm.** These tools are advertised to the
///    model and *parsed/validated* here, but the actual write to `UserProfile` only
///    happens in `apply(...)`, which `CoachView` calls after the user taps "Yes".
/// 2. **Never anything that means under-eating.** There is deliberately NO tool to set a
///    weight target, a calorie/macro target, or anything that would lower a loss-user's
///    intake. Calorie/macro targets are *computed* from the profile (see
///    `UserProfile+Targets`) and stay clamped to a safe floor — the coach can't push
///    them down. Pace changes are validated against the user's existing goal *direction*
///    (a loss user can pick Relaxed/Steady/Ambitious/Maintain — never a route to eating
///    less than their body needs; and "Maintain" is always available as a gentle off-ramp).
///
/// The persona text in `CoachContext` separately instructs the model to gently refuse
/// requests that amount to crash-dieting; these tools simply make sure that even if it
/// tried, there's no lever here to do harm.
enum CoachTools {

    // MARK: - Tool names (single source of truth; used in schema + dispatch)

    enum Name: String, CaseIterable {
        case setStepGoal           = "set_step_goal"
        case setWaterGoalContainers = "set_water_goal_containers"
        case setPace               = "set_pace"
    }

    // MARK: - Safe bounds
    //
    // These mirror the existing Settings UI so the coach can't set a value the user
    // couldn't set themselves with the steppers (SettingsView: steps 4000…20000;
    // water goal up to 16 containers).
    static let stepGoalRange = 2_000...30_000
    static let waterContainersRange = 1...16

    // MARK: - Schemas (Anthropic tool-use JSON schema)

    /// The full `tools` array passed to `AnthropicClient.chatWithTools`. Pace is
    /// constrained to the labels valid for the user's current goal direction, so the
    /// model can only ever offer a safe, in-direction pace.
    static func schemas(for profile: UserProfile) -> [[String: Any]] {
        [stepGoalSchema, waterGoalSchema, paceSchema(for: profile)]
    }

    private static let stepGoalSchema: [String: Any] = [
        "name": Name.setStepGoal.rawValue,
        "description": """
        Set the user's DAILY STEP GOAL (a movement/activity target). Use when the user \
        asks to change how many steps they aim for per day, e.g. "bump my step goal to \
        12k" or "make my step goal 8000". This is a gentle activity target, never a \
        punishment. Steps must be between \(stepGoalRange.lowerBound) and \
        \(stepGoalRange.upperBound).
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "steps": [
                    "type": "integer",
                    "description": "The new daily step goal, e.g. 12000.",
                    "minimum": stepGoalRange.lowerBound,
                    "maximum": stepGoalRange.upperBound,
                ],
            ],
            "required": ["steps"],
        ],
    ]

    private static let waterGoalSchema: [String: Any] = [
        "name": Name.setWaterGoalContainers.rawValue,
        "description": """
        Set the user's DAILY WATER GOAL, expressed as a number of their usual drink \
        containers (bottles/glasses/cups — whichever they've chosen). Use when the user \
        wants to drink more or less water, e.g. "I want to drink more water" or "set my \
        water goal to 8 bottles". Encouraging hydration is always healthy. Count must be \
        between \(waterContainersRange.lowerBound) and \(waterContainersRange.upperBound) \
        containers.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "count": [
                    "type": "integer",
                    "description": "How many containers (bottles/glasses) per day, e.g. 8.",
                    "minimum": waterContainersRange.lowerBound,
                    "maximum": waterContainersRange.upperBound,
                ],
            ],
            "required": ["count"],
        ],
    ]

    /// Pace schema — the `pace` enum is the set of raw values valid for THIS user's
    /// goal direction (loss / maintain / gain), so the model can never propose an
    /// out-of-direction pace. We never offer a tool that lowers intake below the safe
    /// computed floor; pace only nudges the *rate*, and "maintain" is always offered.
    private static func paceSchema(for profile: UserProfile) -> [String: Any] {
        let allowed = allowedPaces(for: profile)
        let optionList = allowed
            .map { "\"\($0.rawValue)\" (\($0.label) — \($0.subtitle.lowercased()))" }
            .joined(separator: ", ")
        return [
            "name": Name.setPace.rawValue,
            "description": """
            Set the user's GOAL PACE — how fast they're aiming to change weight. Use when \
            the user asks to go gentler, steadier, or to hold steady, e.g. "put me on a \
            steadier pace" or "I want to take it slower". Only these paces are valid for \
            this user's goal: \(optionList). Always encourage a sustainable, non-crash \
            pace; favour gentler options and never frame a slower pace as failure.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "pace": [
                        "type": "string",
                        "description": "One of the allowed pace identifiers for this user.",
                        "enum": allowed.map { $0.rawValue },
                    ],
                ],
                "required": ["pace"],
            ],
        ]
    }

    /// Paces this user may switch to: those matching their current goal direction, plus
    /// Maintain (always a safe, non-restrictive off-ramp). Mirrors `GoalPace.paces(for:)`.
    static func allowedPaces(for profile: UserProfile) -> [GoalPace] {
        GoalPace.paces(for: profile.pace.direction)
    }

    // MARK: - Parsed, validated request

    /// A tool request that has passed name + input validation and is ready either to
    /// confirm (show in the UI) or to apply. Carries everything the confirm card and the
    /// apply step need — including a friendly human summary for the prompt.
    struct ParsedRequest {
        let name: Name
        /// What changes, in the user's own terms — used in the confirm prompt and the
        /// post-apply "Done — …" tone. e.g. "set your step goal to 12,000".
        let confirmSummary: String
        /// The concrete change to perform on confirm.
        let action: Action

        enum Action {
            case stepGoal(Int)
            case waterContainers(Int)
            case pace(GoalPace)
        }
    }

    /// Outcome of validating a raw `tool_use` from the model.
    enum ParseResult {
        case ok(ParsedRequest)
        /// Validation failed (unknown tool, out-of-range, bad pace). The associated text
        /// is sent straight back to the model as a `tool_result` error so it can recover
        /// gracefully ("Hmm, I can't set it that high — want to try a smaller number?").
        case invalid(String)
    }

    /// Validate a tool request against the user's current profile. Pure — never mutates.
    static func parse(name rawName: String,
                      input: [String: Any],
                      profile: UserProfile) -> ParseResult {
        guard let name = Name(rawValue: rawName) else {
            return .invalid("Unknown tool \"\(rawName)\". No change was made.")
        }

        switch name {
        case .setStepGoal:
            guard let steps = intValue(input["steps"]) else {
                return .invalid("Missing or non-numeric step count. No change was made.")
            }
            guard stepGoalRange.contains(steps) else {
                return .invalid("Step goal must be between \(stepGoalRange.lowerBound) and "
                              + "\(stepGoalRange.upperBound). \(steps) is out of range, so nothing was changed.")
            }
            return .ok(ParsedRequest(
                name: name,
                confirmSummary: "set your daily step goal to \(grouped(steps)) steps",
                action: .stepGoal(steps)))

        case .setWaterGoalContainers:
            guard let count = intValue(input["count"]) else {
                return .invalid("Missing or non-numeric container count. No change was made.")
            }
            guard waterContainersRange.contains(count) else {
                return .invalid("Water goal must be between \(waterContainersRange.lowerBound) and "
                              + "\(waterContainersRange.upperBound) containers. \(count) is out of range, "
                              + "so nothing was changed.")
            }
            let label = containerLabel(profile, count: count)
            return .ok(ParsedRequest(
                name: name,
                confirmSummary: "set your daily water goal to \(count) \(label)",
                action: .waterContainers(count)))

        case .setPace:
            guard let raw = input["pace"] as? String else {
                return .invalid("Missing pace value. No change was made.")
            }
            guard let pace = GoalPace(rawValue: raw) else {
                return .invalid("\"\(raw)\" isn't a pace I recognize. No change was made.")
            }
            // Must be valid for THIS user's goal direction — never let a loss user be
            // routed to a gain pace (or vice-versa) by a stray tool call.
            guard allowedPaces(for: profile).contains(pace) else {
                let names = allowedPaces(for: profile).map { $0.label }.joined(separator: ", ")
                return .invalid("\"\(pace.label)\" isn't an option for this goal. "
                              + "Valid paces are: \(names). Nothing was changed.")
            }
            return .ok(ParsedRequest(
                name: name,
                confirmSummary: "switch you to a \(pace.label.lowercased()) pace (\(pace.subtitle.lowercased()))",
                action: .pace(pace)))
        }
    }

    // MARK: - Apply (called ONLY after the user taps "Yes")

    /// Apply a confirmed change to the profile and persist it. Returns a short,
    /// factual confirmation string that is sent back to the model as the `tool_result`
    /// so it can reply warmly. Runs on the main actor (mutates a SwiftData @Model).
    @MainActor
    static func apply(_ request: ParsedRequest,
                      to profile: UserProfile,
                      context: ModelContext) -> String {
        switch request.action {
        case .stepGoal(let steps):
            profile.dailyStepGoal = steps
            try? context.save()
            return "Daily step goal is now \(grouped(steps)) steps."

        case .waterContainers(let count):
            // The by-the-bottle UI stores the goal in oz as `count × container size`,
            // exactly how the Settings stepper does it. `waterGoalContainers` reads it
            // back as round(targetOz / containerSize), so this round-trips to `count`.
            let size = profile.waterContainerOz > 0 ? profile.waterContainerOz : 16.9
            profile.waterGoalOzOverride = Double(count) * size
            try? context.save()
            let label = containerLabel(profile, count: count)
            return "Daily water goal is now \(count) \(label)."

        case .pace(let pace):
            profile.pace = pace   // enum setter writes paceRaw
            try? context.save()
            return "Goal pace is now \(pace.label) (\(pace.subtitle.lowercased()))."
        }
    }

    // MARK: - Helpers

    /// Accepts Int or numeric-String JSON (JSONSerialization may hand back NSNumber).
    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d.rounded()) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    /// Pluralized container word for the user's chosen container, e.g. "8 bottles".
    private static func containerLabel(_ profile: UserProfile, count: Int) -> String {
        let base = profile.waterContainerLabel.isEmpty ? "bottle" : profile.waterContainerLabel
        return count == 1 ? base : base + "s"
    }

    private static func grouped(_ n: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: n)) ?? String(n)
    }
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()
}
