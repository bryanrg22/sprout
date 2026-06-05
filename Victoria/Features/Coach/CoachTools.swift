import Foundation
import SwiftData

/// The coach's SAFE, agentic tool surface.
///
/// Vita ("the coach") can do two kinds of things here: *log/edit the user's data* on her
/// behalf (food, water, weight) and *propose changing* a small set of encouragement
/// settings (step goal, water goal, goal pace, goal weight). Everything is designed around
/// these hard rules:
///
/// 1. **Confirmation is risk-scaled, not all-or-nothing.** Quick, reversible logs
///    (`log_food`, `edit_food`, `log_water`, `log_weight`) apply immediately — the UI shows
///    an Undo. Destructive or goal-changing actions (`delete_food`, `set_pace`,
///    `set_step_goal`, `set_water_goal_containers`, `set_weight_goal`) require a one-tap
///    confirm before anything is written. `ParsedRequest.requiresConfirm` encodes which is
///    which; `CoachView` reads it to choose auto-apply-with-Undo vs. confirm. Either way the
///    actual write only happens in `apply(...)`.
/// 2. **Never anything that means under-eating.** There is deliberately NO tool to set a
///    calorie or macro target, or anything that lowers a loss-user's intake. Calorie/macro
///    targets are *computed* from the profile (see `UserProfile+Targets`) and stay clamped
///    to a safe floor — the coach can't push them down. Pace changes are validated against
///    the user's existing goal *direction* (a loss user can pick
///    Relaxed/Steady/Ambitious/Maintain — never a route to eating less than their body
///    needs; "Maintain" is always available as a gentle off-ramp). `set_weight_goal` moves
///    only the *target*, never intake, and is validated to lie in the user's goal direction
///    within sane bounds.
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
        // Data-logging + edit tools (the agentic surface). These WRITE the same SwiftData
        // models the manual UI does — they don't recompute targets or touch intake levers.
        case logFood               = "log_food"
        case editFood              = "edit_food"
        case deleteFood            = "delete_food"
        case logWater              = "log_water"
        case logWeight             = "log_weight"
        case setWeightGoal         = "set_weight_goal"
        // Durable memory: save a lasting fact about the user (creatine, nutritionist, allergy…)
        // to her long-term notes so it persists across every future conversation.
        case rememberFact          = "remember_about_user"
        // Adaptive Plan: record a change to her evolving Plan (the AI-authored "understanding
        // of you" on Progress) so every adaptation is visible in its changelog.
        case updatePlan            = "update_plan"
        // Log a workout / training session — she could READ workouts but not WRITE one until now.
        case logWorkout            = "log_workout"
        // Edit the user's adaptive PLAN's content directly (targets / prose / focus) + log the change.
        case editPlan              = "edit_plan"
        // Correct/forget a fact from her durable profile notes — the counterpart to remember.
        case forgetFact            = "forget_about_user"
        // Settings / preferences tools — let Vita change every setting the user can in Settings.
        // Each writes a single profile field, validated to the same options/ranges the UI allows.
        case setUnits              = "set_units"
        case setTheme              = "set_theme"
        case setHomeGym            = "set_home_gym"
        case setGoalDirection      = "set_goal_direction"
        case setHeight             = "set_height"
        case setBirthDate          = "set_birth_date"
        case setSex                = "set_sex"
        case setActivityLevel      = "set_activity_level"
        case setCompanion          = "set_companion"
        case setCoachName          = "set_coach_name"
        case setWaterContainer     = "set_water_container"
        case setProteinGoal        = "set_protein_goal"
        case toggleStepsInBudget   = "toggle_steps_in_budget"
    }

    // MARK: - Safe bounds
    //
    // These mirror the existing Settings UI so the coach can't set a value the user
    // couldn't set themselves with the steppers (SettingsView: steps 4000…20000;
    // water goal up to 16 containers).
    static let stepGoalRange = 2_000...30_000
    static let waterContainersRange = 1...16

    // Bounds for the data-logging tools. These mirror what the manual UI accepts so the
    // coach can never write a value the user couldn't enter themselves.
    /// Weigh-in / goal-weight bounds in lb — matches the weigh-in slider (50…500 lb).
    /// (Weights are stored as the entered number in the user's unit, like every other
    /// write path; true kg conversion is an app-wide gap handled elsewhere, not here.)
    static let weightRangeLbs = 50.0...500.0
    /// One logged water amount, in oz — generous so any real glass/bottle/jug fits.
    static let waterOzRange = 1.0...300.0
    /// How many containers may be logged at once (e.g. "I drank 3 bottles").
    static let waterContainersLogRange = 1...20
    /// A logged workout's length, in minutes — generous (a 5-min walk through a long session).
    static let workoutMinutesRange = 1...600

    // Bounds for the settings/preferences tools. These mirror what the Settings UI accepts so
    // the coach can never write a value the user couldn't set themselves.
    /// Height in cm — comfortably spans the onboarding stepper (48–84 in ≈ 122–213 cm).
    static let heightCmRange = 120.0...230.0
    /// A plausible adult age in whole years (used when she gives an age instead of a birth date).
    static let ageYearsRange = 13...100
    /// A directly-set daily protein target, in grams — generous but sane (0 clears any override).
    static let proteinGoalRange = 0.0...400.0
    /// The size of "one drink" she logs, in oz — spans the Settings presets (glass 8 … big bottle 32)
    /// with a little headroom for a custom container.
    static let waterContainerOzRange = 4.0...64.0

    // MARK: - Schemas (Anthropic tool-use JSON schema)

    /// The full `tools` array passed to `AnthropicClient.chatWithTools`. Pace is
    /// constrained to the labels valid for the user's current goal direction, so the
    /// model can only ever offer a safe, in-direction pace.
    static func schemas(for profile: UserProfile) -> [[String: Any]] {
        [stepGoalSchema, waterGoalSchema, paceSchema(for: profile),
         logFoodSchema, editFoodSchema, deleteFoodSchema,
         logWaterSchema(for: profile), logWeightSchema(for: profile),
         weightGoalSchema(for: profile), rememberSchema, updatePlanSchema, logWorkoutSchema,
         editPlanSchema, forgetSchema,
         // Settings / preferences tools — every setting the user can change in Settings.
         setUnitsSchema, setThemeSchema, setHomeGymSchema, setGoalDirectionSchema(for: profile),
         setHeightSchema(for: profile), setBirthDateSchema, setSexSchema, setActivityLevelSchema,
         setCompanionSchema, setCoachNameSchema, setWaterContainerSchema, setProteinGoalSchema,
         toggleStepsInBudgetSchema]
    }

    /// Save a durable fact about the user to long-term memory. This is the tool that lets Vita
    /// actually "update the profile" when the user shares something lasting — and it means she
    /// must never CLAIM to have saved something without calling it.
    private static let rememberSchema: [String: Any] = [
        "name": Name.rememberFact.rawValue,
        "description": """
        Save a DURABLE fact about the user to your long-term memory so it persists across ALL \
        future conversations (not just this chat). Use this whenever she shares something \
        lasting about her life, health, habits, routine, or preferences — e.g. "I take \
        creatine daily", "I see a nutritionist", "I'm vegetarian", "I work night shifts", \
        "I'm allergic to peanuts", "my gym days are Mon/Wed/Fri". Once you call it you genuinely \
        remember it. NEVER tell her you've saved or updated something about her without calling \
        this tool — if you didn't call it, you didn't do it.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "note": [
                    "type": "string",
                    "description": "The durable fact to remember, as a short phrase, e.g. \"takes creatine daily\".",
                ],
            ],
            "required": ["note"],
        ],
    ]

    /// Record a change to the user's adaptive **Plan** (the evolving "understanding of you" on
    /// Progress). This appends a line to the plan's visible changelog so every adaptation is
    /// surfaced, never silent — like `remember_about_user`, calling it is what makes a claimed
    /// plan change real.
    private static let updatePlanSchema: [String: Any] = [
        "name": Name.updatePlan.rawValue,
        "description": """
        Record a change to the user's adaptive PLAN — the evolving "understanding of you" that \
        lives on the Progress tab. Use when you and she agree to adjust her approach, e.g. \
        "let's add a protein focus", "shifting your timeframe to October", or "easing off on \
        cardio for now". This appends a visible line to her plan's changelog so the adaptation \
        is never silent. NEVER tell her you've updated her plan without calling this tool — if \
        you didn't call it, you didn't do it.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "note": [
                    "type": "string",
                    "description": "What changed about their plan + why, one or two sentences.",
                ],
            ],
            "required": ["note"],
        ],
    ]

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

    // MARK: - Schemas: data-logging tools

    /// Meal identifiers accepted by the food tools (the `MealType` raw values).
    private static let mealEnum = MealType.allCases.map { $0.rawValue }

    private static let logFoodSchema: [String: Any] = [
        "name": Name.logFood.rawValue,
        "description": """
        Log a FOOD ITEM or meal to the user's diary — TODAY by default (the normal case), or a \
        PAST day she forgot via the optional `date`. Use when she tells you what \
        she ate and wants it recorded, e.g. "log a chicken bowl, about 600 calories, 45g \
        protein" or "add my oatmeal breakfast". Provide your best calorie + macro estimate \
        from what she described; portion size is the biggest unknown, so estimate sensibly. \
        This logs immediately (she can undo), so only call it when she clearly wants the \
        item recorded — if she's just chatting about food, don't.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "What she ate, e.g. \"Chicken burrito bowl\"."],
                "meal": [
                    "type": "string",
                    "description": "Which meal it belongs to.",
                    "enum": mealEnum,
                ],
                "calories": ["type": "number", "description": "Calories in ONE serving — per-serving, NOT pre-multiplied by quantity. e.g. 600 for one bowl."],
                "protein_g": ["type": "number", "description": "Protein grams in ONE serving.", "minimum": 0],
                "carbs_g": ["type": "number", "description": "Carbohydrate grams in ONE serving.", "minimum": 0],
                "fat_g": ["type": "number", "description": "Fat grams in ONE serving.", "minimum": 0],
                "quantity": [
                    "type": "number",
                    "description": "How many servings she ate. The per-serving calories/macros above are multiplied by this — so DON'T pre-multiply them. Use 1 for a single item; only set higher for genuine multiples (e.g. 2 for two identical bowls). Defaults to 1.",
                    "minimum": 0,
                ],
                "date": [
                    "type": "string",
                    "description": "ONLY when she means a PAST day she forgot to log (e.g. \"add the burger I had yesterday\"): \"yesterday\" or an ISO date like \"2026-06-04\". Omit entirely for today — the normal case.",
                ],
            ],
            "required": ["name", "meal", "calories", "protein_g", "carbs_g", "fat_g"],
        ],
    ]

    private static let editFoodSchema: [String: Any] = [
        "name": Name.editFood.rawValue,
        "description": """
        Edit a food item the user ALREADY logged TODAY. Identify it by its name (match what \
        she logged, e.g. "my latte"). Only include the fields she wants to change — omit the \
        rest and they stay as they are. Use for corrections like "actually my latte was 250 \
        calories" or "change the burrito to lunch". If you can't tell which item she means, \
        ask her to clarify rather than guessing.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "The CURRENT name of the logged item to find."],
                "new_name": ["type": "string", "description": "A new name, if she's renaming it."],
                "meal": [
                    "type": "string",
                    "description": "Move it to this meal, if changing.",
                    "enum": mealEnum,
                ],
                "calories": ["type": "number", "description": "New PER-SERVING calorie value, if changing (not multiplied by quantity)."],
                "protein_g": ["type": "number", "description": "New per-serving protein grams, if changing.", "minimum": 0],
                "carbs_g": ["type": "number", "description": "New per-serving carb grams, if changing.", "minimum": 0],
                "fat_g": ["type": "number", "description": "New per-serving fat grams, if changing.", "minimum": 0],
                "quantity": ["type": "number", "description": "New number of servings, if changing.", "minimum": 0],
            ],
            "required": ["name"],
        ],
    ]

    private static let deleteFoodSchema: [String: Any] = [
        "name": Name.deleteFood.rawValue,
        "description": """
        Delete a food item the user logged TODAY, found by its name. Use only when she \
        clearly asks to remove something, e.g. "delete the fries I logged" or "remove my \
        snack". This is destructive, so the app asks her to confirm before it's removed. If \
        the name is ambiguous, ask her which one she means instead of guessing.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "The name of the logged item to remove."],
            ],
            "required": ["name"],
        ],
    ]

    /// Water-logging schema — phrased in HER container so she never thinks in oz, but `oz`
    /// is also accepted for "I drank a big glass / 20 oz". One of the two must be present.
    private static func logWaterSchema(for profile: UserProfile) -> [String: Any] {
        let label = profile.waterContainerLabel.isEmpty ? "bottle" : profile.waterContainerLabel
        return [
            "name": Name.logWater.rawValue,
            "description": """
            Log water the user drank, ADDING to today's total. Prefer `containers` — her usual \
            drink is a \(label) (\(Int(containerSize(profile).rounded())) oz) — e.g. "I had 2 \
            \(label)s of water" → containers: 2. Use `oz` only when she gives an explicit ounce \
            amount. Encouraging hydration is always healthy, so log it whenever she mentions \
            drinking water.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "containers": [
                        "type": "integer",
                        "description": "Number of her usual \(label)s, e.g. 2.",
                        "minimum": waterContainersLogRange.lowerBound,
                        "maximum": waterContainersLogRange.upperBound,
                    ],
                    "oz": [
                        "type": "number",
                        "description": "Explicit fluid ounces, if she gave one.",
                        "minimum": waterOzRange.lowerBound,
                        "maximum": waterOzRange.upperBound,
                    ],
                ],
            ],
        ]
    }

    /// Workout-logging schema. Deliberately light — the goal is to reward showing up, so only the
    /// activity `type` is required; `minutes` / `focus` / `notes` are optional.
    private static let logWorkoutSchema: [String: Any] = [
        "name": Name.logWorkout.rawValue,
        "description": """
        Log a workout / training session the user did (gym, run, walk, cycle, yoga, HIIT, sports). \
        Use whenever she mentions exercising — "I hit the gym", "ran 3 miles", "did legs today". \
        Only `type` is required; add `minutes`, `focus` (strength split: push/pull/legs/…), and a \
        short `notes` if she gave them. Showing up always counts — log it whenever it comes up.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "type": [
                    "type": "string",
                    "description": "The kind of workout.",
                    "enum": WorkoutType.allCases.map { $0.rawValue },
                ],
                "minutes": [
                    "type": "integer",
                    "description": "Duration in minutes, if she gave one.",
                    "minimum": workoutMinutesRange.lowerBound,
                    "maximum": workoutMinutesRange.upperBound,
                ],
                "focus": [
                    "type": "string",
                    "description": "Optional training split for strength days.",
                    "enum": WorkoutFocus.allCases.map { $0.rawValue },
                ],
                "notes": ["type": "string", "description": "A short optional note, e.g. 'felt strong'."],
            ],
            "required": ["type"],
        ],
    ]

    /// Edit the user's adaptive PLAN's content directly — set only the fields she asked to change,
    /// like edit_food. Vita's coaching judgment (educate, don't enable extremes) is the guardrail;
    /// there's no hard gate. `change_note` becomes the changelog line so the edit is visible.
    private static let editPlanSchema: [String: Any] = [
        "name": Name.editPlan.rawValue,
        "description": """
        Edit the user's adaptive PLAN in place when she asks to change it ("bump my protein to 150", \
        "make the focus about dinners", "shift my range up"). Set ONLY the fields she wants changed — \
        you can see her plan in your context, so keep the rest. Before any extreme change (e.g. a very \
        low calorie range), educate her first — never just enable it. Always include a short change_note.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "headline": ["type": "string", "description": "New one-line headline, if changing it."],
                "assessment": ["type": "string", "description": "New 'how it's going' read (markdown), if changing it."],
                "strategy": ["type": "string", "description": "New approach / focus (markdown), if changing it."],
                "calorie_min": ["type": "number", "description": "New lower bound of the daily calorie range."],
                "calorie_max": ["type": "number", "description": "New upper bound of the daily calorie range."],
                "protein_target": ["type": "number", "description": "New daily protein target (g)."],
                "change_note": ["type": "string", "description": "One line: what you changed + why (becomes the plan's changelog entry)."],
            ],
            "required": ["change_note"],
        ],
    ]

    /// Forget / correct a fact in her durable profile notes — removes any remembered lines matching
    /// `fact`. The counterpart to remember_about_user; together they let her profile be edited.
    private static let forgetSchema: [String: Any] = [
        "name": Name.forgetFact.rawValue,
        "description": """
        Remove something from your durable memory about her when she says it's wrong or no longer true \
        ("I don't take creatine anymore", "forget that I work nights"). Pass the `fact` to forget; any \
        remembered note matching it is dropped. To CORRECT a fact, forget the old one then remember the new.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "fact": ["type": "string", "description": "The SHORTEST distinctive keyword(s) to remove — match how it was likely stored, NOT a full sentence. Use 'desk job' not 'I work a 9-5 desk job'; 'creatine' not 'I take creatine every morning'. Pick the 1–3 key words; matching is whole-word (plurals OK)."],
            ],
            "required": ["fact"],
        ],
    ]

    /// Weight-logging schema — the value is in HER unit (lb or kg), stored as the entered
    /// number, exactly how the weigh-in sheet records it (no kg conversion here).
    private static func logWeightSchema(for profile: UserProfile) -> [String: Any] {
        let unit = profile.unitSystem.weightUnit
        return [
            "name": Name.logWeight.rawValue,
            "description": """
            Log today's weigh-in for the user, in \(unit) (her unit). Use when she tells you \
            the scale number, e.g. "I'm \(unit == "lb" ? "152" : "69") today" or "log my \
            weigh-in at \(unit == "lb" ? "150.4" : "68.2")". Remind her gently that one number \
            is just one day — the trend is what matters — but go ahead and log it. Value must \
            be between \(Int(weightRangeLbs.lowerBound)) and \(Int(weightRangeLbs.upperBound)) \(unit).
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "weight": [
                        "type": "number",
                        "description": "Her weight today in \(unit).",
                        "minimum": weightRangeLbs.lowerBound,
                        "maximum": weightRangeLbs.upperBound,
                    ],
                ],
                "required": ["weight"],
            ],
        ]
    }

    /// Goal-weight schema — moves only her TARGET, never her intake. The model is told the
    /// direction it must respect so it can't propose an out-of-direction goal; `parse`
    /// enforces it regardless.
    private static func weightGoalSchema(for profile: UserProfile) -> [String: Any] {
        let unit = profile.unitSystem.weightUnit
        let dir: String
        switch profile.pace.direction {
        case .lose:     dir = "Her goal is weight LOSS, so a new goal must be BELOW her current weight."
        case .gain:     dir = "Her goal is a lean GAIN, so a new goal must be ABOVE her current weight."
        case .maintain: dir = "She is MAINTAINING, so a new goal should be close to her current weight."
        }
        return [
            "name": Name.setWeightGoal.rawValue,
            "description": """
            Set the user's GOAL WEIGHT (the target she's working toward), in \(unit). Use when \
            she asks to change her target, e.g. "set my goal to \(unit == "lb" ? "140" : "63")". \
            \(dir) This changes only the target line on her progress chart — it does NOT change \
            how much she eats (her calorie target stays computed and safely floored). Must be \
            between \(Int(weightRangeLbs.lowerBound)) and \(Int(weightRangeLbs.upperBound)) \(unit). \
            The app shows a one-tap confirm before it's saved.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "weight": [
                        "type": "number",
                        "description": "The new goal weight in \(unit).",
                        "minimum": weightRangeLbs.lowerBound,
                        "maximum": weightRangeLbs.upperBound,
                    ],
                ],
                "required": ["weight"],
            ],
        ]
    }

    // MARK: - Schemas: settings / preferences tools
    //
    // One per Settings control, so Vita can change anything the user can in the Settings sheet.
    // Each is constrained to the same options/ranges the UI offers (see SettingsView), so a tool
    // call can never write a value the user couldn't pick themselves.

    private static let setUnitsSchema: [String: Any] = [
        "name": Name.setUnits.rawValue,
        "description": """
        Set the user's UNIT SYSTEM — imperial (lb) or metric (kg). Use when she asks to switch \
        units, e.g. "show my weight in kg" or "switch me to pounds". This changes only how \
        weights are displayed/entered; it doesn't alter any logged values. The app shows a \
        one-tap confirm before it's saved.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "system": [
                    "type": "string",
                    "description": "Which unit system to use.",
                    "enum": UnitSystem.allCases.map { $0.rawValue },
                ],
            ],
            "required": ["system"],
        ],
    ]

    private static let setThemeSchema: [String: Any] = [
        "name": Name.setTheme.rawValue,
        "description": """
        Set the app's APPEARANCE / theme. Two looks: "\(ThemeStyle.cute.rawValue)" \
        (\(ThemeStyle.cute.label) — \(ThemeStyle.cute.blurb.lowercased())) and \
        "\(ThemeStyle.cool.rawValue)" (\(ThemeStyle.cool.label) — \(ThemeStyle.cool.blurb.lowercased())). \
        Use when she asks to change how the app looks, e.g. "make it dark" → cool, or "give me \
        the soft pastel look" → cute. Same layout either way; only the palette changes.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "theme": [
                    "type": "string",
                    "description": "Which look to wear.",
                    "enum": ThemeStyle.allCases.map { $0.rawValue },
                ],
            ],
            "required": ["theme"],
        ],
    ]

    private static let setHomeGymSchema: [String: Any] = [
        "name": Name.setHomeGym.rawValue,
        "description": """
        Set the user's PRIMARY (home) GYM — used to show the right machine photos and personalize \
        workout advice. Options: \(HomeGym.allCases.map { "\"\($0.rawValue)\" (\($0.label))" }.joined(separator: ", ")). \
        Use when she tells you where she trains, e.g. "I work out at 24 Hour Fitness". This doesn't \
        change which machines are listed — the catalog stays the same.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "gym": [
                    "type": "string",
                    "description": "Her home gym.",
                    "enum": HomeGym.allCases.map { $0.rawValue },
                ],
            ],
            "required": ["gym"],
        ],
    ]

    /// Goal-direction schema — flips whether she's losing, maintaining, or gaining. The model is
    /// told her current direction and current weight so it understands the consequence; `parse`
    /// snaps her pace to a sensible in-direction pace (mirroring Settings' goalDirectionBinding).
    private static func setGoalDirectionSchema(for profile: UserProfile) -> [String: Any] {
        let cur: String
        switch profile.pace.direction {
        case .lose:     cur = "losing weight"
        case .gain:     cur = "on a lean gain"
        case .maintain: cur = "maintaining"
        }
        return [
            "name": Name.setGoalDirection.rawValue,
            "description": """
            Set the user's GOAL DIRECTION — whether she's working to lose weight, hold steady \
            (maintain), or gain (a lean build). She is currently \(cur). Use when she wants to \
            change what she's aiming for, e.g. "I want to switch to maintaining" or "let's start a \
            lean bulk". This picks a gentle, sustainable pace in the new direction; it never routes \
            her to under-eating. The app shows a one-tap confirm before it's saved.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "direction": [
                        "type": "string",
                        "description": "Which way she's aiming: lose, maintain, or gain.",
                        "enum": ["lose", "maintain", "gain"],
                    ],
                ],
                "required": ["direction"],
            ],
        ]
    }

    /// Height schema — always in cm internally. The example is phrased in her unit so it reads
    /// naturally, but the model is told to send cm.
    private static func setHeightSchema(for profile: UserProfile) -> [String: Any] {
        let imperial = profile.unitSystem == .imperial
        let hint = imperial ? "e.g. she says 5'6\" → send 168" : "e.g. she says 168 cm → send 168"
        return [
            "name": Name.setHeight.rawValue,
            "description": """
            Set the user's HEIGHT, in CENTIMETRES (this feeds her calorie/BMR math). Always send \
            `cm` — convert from feet/inches yourself if she gives those (\(hint)). Use when she \
            tells you or corrects her height. Must be between \(Int(heightCmRange.lowerBound)) and \
            \(Int(heightCmRange.upperBound)) cm. The app shows a one-tap confirm before it's saved.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "cm": [
                        "type": "number",
                        "description": "Her height in centimetres, e.g. 168.",
                        "minimum": heightCmRange.lowerBound,
                        "maximum": heightCmRange.upperBound,
                    ],
                ],
                "required": ["cm"],
            ],
        ]
    }

    private static let setBirthDateSchema: [String: Any] = [
        "name": Name.setBirthDate.rawValue,
        "description": """
        Set the user's AGE / BIRTH DATE (this feeds her calorie/BMR math). Pass EITHER `age` in \
        whole years (the usual case — "I'm 29") OR an exact `date` as ISO "yyyy-MM-dd" if she gives \
        her birthday. Use when she tells you or corrects her age. Age must be between \
        \(ageYearsRange.lowerBound) and \(ageYearsRange.upperBound). The app shows a one-tap \
        confirm before it's saved.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "age": [
                    "type": "integer",
                    "description": "Her age in whole years, e.g. 29.",
                    "minimum": ageYearsRange.lowerBound,
                    "maximum": ageYearsRange.upperBound,
                ],
                "date": [
                    "type": "string",
                    "description": "Her birth date as ISO \"yyyy-MM-dd\", if she gave an exact birthday.",
                ],
            ],
        ],
    ]

    private static let setSexSchema: [String: Any] = [
        "name": Name.setSex.rawValue,
        "description": """
        Set the user's BIOLOGICAL SEX — used only for the BMR/calorie equation. Options: \
        \(BiologicalSex.allCases.map { "\"\($0.rawValue)\" (\($0.label))" }.joined(separator: ", ")). \
        Use when she tells you or corrects it. The app shows a one-tap confirm before it's saved.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "sex": [
                    "type": "string",
                    "description": "Her biological sex (for the BMR equation).",
                    "enum": BiologicalSex.allCases.map { $0.rawValue },
                ],
            ],
            "required": ["sex"],
        ],
    ]

    private static let setActivityLevelSchema: [String: Any] = [
        "name": Name.setActivityLevel.rawValue,
        "description": """
        Set the user's ACTIVITY LEVEL — her everyday baseline movement, which feeds her calorie \
        target (TDEE). Options: \
        \(ActivityLevel.allCases.map { "\"\($0.rawValue)\" (\($0.label) — \($0.detail.lowercased()))" }.joined(separator: "; ")). \
        Use when she describes how active her days are, e.g. "I'm on my feet all day at work" → \
        a higher level. The app shows a one-tap confirm before it's saved.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "level": [
                    "type": "string",
                    "description": "Her everyday activity baseline.",
                    "enum": ActivityLevel.allCases.map { $0.rawValue },
                ],
            ],
            "required": ["level"],
        ],
    ]

    private static let setCompanionSchema: [String: Any] = [
        "name": Name.setCompanion.rawValue,
        "description": """
        Set the user's little COMPANION — its name and/or its pixel avatar. Provide whichever she \
        wants to change (at least one). The avatar choices are \
        \(CompanionAvatar.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " or ")). Use when \
        she says e.g. "rename my buddy to Sprout" (name) or "make my companion Bryan" (avatar). \
        This is a fun cosmetic change and applies right away (she can undo).
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "A new name for the companion, if renaming it."],
                "avatar": [
                    "type": "string",
                    "description": "Which pixel avatar the companion uses, if changing it.",
                    "enum": CompanionAvatar.allCases.map { $0.rawValue },
                ],
            ],
        ],
    ]

    private static let setCoachNameSchema: [String: Any] = [
        "name": Name.setCoachName.rawValue,
        "description": """
        Rename YOU, the coach. Use when she wants to call you something else, e.g. "I'll call you \
        Coach" or "your name is now Mia". This just changes your display name throughout the app — \
        it applies right away (she can undo).
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "The new coach name, e.g. \"Mia\"."],
            ],
            "required": ["name"],
        ],
    ]

    private static let setWaterContainerSchema: [String: Any] = [
        "name": Name.setWaterContainer.rawValue,
        "description": """
        Set what "one drink" means for water logging — its size in ounces, and optionally a friendly \
        label ("glass", "bottle", "big bottle"). Common sizes: a glass ≈ 8 oz, a bottle ≈ 17 oz, a \
        big bottle ≈ 32 oz. Use when she tells you what she usually drinks from, e.g. "I drink from a \
        32 oz bottle" → oz: 32, label: "big bottle". Size must be between \
        \(Int(waterContainerOzRange.lowerBound)) and \(Int(waterContainerOzRange.upperBound)) oz. The \
        app shows a one-tap confirm before it's saved (it affects how her water goal is counted).
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "oz": [
                    "type": "number",
                    "description": "The size of one drink/container in fluid ounces, e.g. 32.",
                    "minimum": waterContainerOzRange.lowerBound,
                    "maximum": waterContainerOzRange.upperBound,
                ],
                "label": ["type": "string", "description": "A friendly name for it, e.g. \"big bottle\". Optional."],
            ],
            "required": ["oz"],
        ],
    ]

    private static let setProteinGoalSchema: [String: Any] = [
        "name": Name.setProteinGoal.rawValue,
        "description": """
        Set the user's DAILY PROTEIN TARGET directly, in grams. Use when she asks to aim for a \
        specific protein number, e.g. "I want to hit 140g of protein a day". Higher protein is \
        healthy and supportive of her goals — encourage it. Must be between \
        \(Int(proteinGoalRange.lowerBound)) and \(Int(proteinGoalRange.upperBound)) g (send 0 only \
        if she wants to clear a custom target and go back to the calculated one). The app shows a \
        one-tap confirm before it's saved.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "grams": [
                    "type": "number",
                    "description": "The daily protein target in grams, e.g. 140.",
                    "minimum": proteinGoalRange.lowerBound,
                    "maximum": proteinGoalRange.upperBound,
                ],
            ],
            "required": ["grams"],
        ],
    ]

    private static let toggleStepsInBudgetSchema: [String: Any] = [
        "name": Name.toggleStepsInBudget.rawValue,
        "description": """
        Turn ON or OFF "let steps add to my budget" — when on, steps she walks above her baseline \
        add a little to her daily calorie budget. Use when she asks for this, e.g. "let my steps \
        earn me extra calories" → on, or "stop adding steps to my budget" → off. The app shows a \
        one-tap confirm before it's saved.
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "enabled": [
                    "type": "boolean",
                    "description": "true to let steps add to her budget, false to turn it off.",
                ],
            ],
            "required": ["enabled"],
        ],
    ]

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
            // Data-logging actions. Edit/delete carry the id of the entry `parse` resolved
            // among today's items, so `apply` re-fetches it by id (never captures a @Model).
            case logFood(FoodDraft)
            case editFood(id: UUID, changes: FoodEdit)
            case deleteFood(id: UUID)
            case logWaterOz(Double)
            case logWeight(lbs: Double)
            case weightGoal(lbs: Double)
            case rememberFact(String)
            case updatePlan(note: String)
            case logWorkout(type: WorkoutType, minutes: Int, focus: WorkoutFocus?, notes: String?)
            case editPlan(PlanEdit)
            case forgetFact(String)
            // Settings / preferences actions — each writes a single profile field.
            case setUnits(UnitSystem)
            case setTheme(ThemeStyle)
            case setHomeGym(HomeGym)
            case setGoalDirection(GoalPace.Direction)
            case setHeight(cm: Double)
            case setBirthDate(Date)
            case setSex(BiologicalSex)
            case setActivityLevel(ActivityLevel)
            case setCompanion(name: String?, avatar: CompanionAvatar?)
            case setCoachName(String)
            case setWaterContainer(oz: Double, label: String?)
            case setProteinGoal(grams: Double)
            case toggleStepsInBudget(Bool)
        }

        /// Whether the UI must get an explicit one-tap confirm before applying.
        ///
        /// Quick, reversible logs auto-apply (the UI offers Undo). Anything destructive or
        /// goal-changing is gated behind a confirm. This is the single source of truth the
        /// view reads to pick its flow — keeping the risk policy here, next to the tools.
        var requiresConfirm: Bool {
            switch name {
            case .logFood, .editFood, .logWater, .logWeight, .rememberFact, .updatePlan, .logWorkout,
                 .forgetFact,
                 // Cosmetic / personalization preferences with no effect on targets, units, or her
                 // goal — like a rename, these are safely reversible, so auto-apply with Undo.
                 .setTheme, .setHomeGym, .setCompanion, .setCoachName:
                return false   // quick + reversible → auto-apply with Undo
            case .editPlan:
                // A prose tweak (headline / assessment / strategy) auto-applies with Undo, but
                // changing the TARGETS (calorie range or protein) is goal-changing — confirm it with
                // the same Yes/Not-now card as set_water_goal / set_weight_goal.
                if case .editPlan(let edit) = action {
                    return edit.calorieMin != nil || edit.calorieMax != nil || edit.proteinTarget != nil
                }
                return false
            case .deleteFood,                                   // destructive
                 .setPace, .setStepGoal, .setWaterGoalContainers, .setWeightGoal,
                 // Biometric / unit / goal-direction / target-changing settings — anything that
                 // moves her numbers (BMR inputs, units, goal, computed budget) → confirm first.
                 .setUnits, .setGoalDirection, .setHeight, .setBirthDate, .setSex, .setActivityLevel,
                 .setProteinGoal, .setWaterContainer, .toggleStepsInBudget:
                return true    // goal-changing / not a casual log → confirm first
            }
        }
    }

    /// A plain-value set of field edits for `edit_food`: each is nil when unchanged, so
    /// `apply` only touches the fields the user actually asked to change.
    struct FoodEdit {
        var name: String?
        var meal: MealType?
        var calories: Double?
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?
        var quantity: Double?

        /// True when at least one field is set — guards against a no-op edit.
        var hasAnyChange: Bool {
            name != nil || meal != nil || calories != nil || proteinG != nil
                || carbsG != nil || fatG != nil || quantity != nil
        }
    }

    /// A plain-value set of edits for `edit_plan`: each nil when unchanged, so `apply` only touches
    /// the fields she actually asked to change. `changeNote` becomes the plan's changelog line.
    struct PlanEdit {
        var headline: String?
        var assessment: String?
        var strategy: String?
        var calorieMin: Double?
        var calorieMax: Double?
        var proteinTarget: Double?
        var changeNote: String = ""

        /// True when at least one substantive field is set (a bare note belongs in update_plan).
        var hasAnyChange: Bool {
            headline != nil || assessment != nil || strategy != nil
                || calorieMin != nil || calorieMax != nil || proteinTarget != nil
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
    ///
    /// `todaysFoods` is the set of `FoodEntry`s logged today, needed only by `edit_food` /
    /// `delete_food` to resolve "the latte" to a specific row (and to report not-found /
    /// ambiguous as a friendly `.invalid`). It defaults to `[]` so the settings-only call
    /// sites and existing tests keep their exact signatures.
    static func parse(name rawName: String,
                      input: [String: Any],
                      profile: UserProfile,
                      todaysFoods: [FoodEntry] = []) -> ParseResult {
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

        case .logFood:
            return parseLogFood(input: input)

        case .editFood:
            return parseEditFood(input: input, todaysFoods: todaysFoods)

        case .deleteFood:
            return parseDeleteFood(input: input, todaysFoods: todaysFoods)

        case .logWater:
            return parseLogWater(input: input, profile: profile)

        case .logWeight:
            return parseLogWeight(input: input, profile: profile)

        case .setWeightGoal:
            return parseWeightGoal(input: input, profile: profile)

        case .rememberFact:
            return parseRemember(input: input)

        case .updatePlan:
            return parseUpdatePlan(input: input)

        case .logWorkout:
            return parseLogWorkout(input: input)

        case .editPlan:
            return parseEditPlan(input: input)

        case .forgetFact:
            return parseForget(input: input)

        case .setUnits:
            return parseSetUnits(input: input)

        case .setTheme:
            return parseSetTheme(input: input)

        case .setHomeGym:
            return parseSetHomeGym(input: input)

        case .setGoalDirection:
            return parseSetGoalDirection(input: input, profile: profile)

        case .setHeight:
            return parseSetHeight(input: input)

        case .setBirthDate:
            return parseSetBirthDate(input: input)

        case .setSex:
            return parseSetSex(input: input)

        case .setActivityLevel:
            return parseSetActivityLevel(input: input)

        case .setCompanion:
            return parseSetCompanion(input: input)

        case .setCoachName:
            return parseSetCoachName(input: input)

        case .setWaterContainer:
            return parseSetWaterContainer(input: input)

        case .setProteinGoal:
            return parseSetProteinGoal(input: input)

        case .toggleStepsInBudget:
            return parseToggleStepsInBudget(input: input)
        }
    }

    private static func parseLogWorkout(input: [String: Any]) -> ParseResult {
        guard let typeRaw = input["type"] as? String, let type = WorkoutType(rawValue: typeRaw) else {
            return .invalid("I need to know what kind of workout it was. Nothing was logged.")
        }
        var minutes = 0
        if let mv = doubleValue(input["minutes"]), mv > 0 {
            let m = Int(mv.rounded())
            guard workoutMinutesRange.contains(m) else {
                return .invalid("That length looks off — give me minutes between "
                              + "\(workoutMinutesRange.lowerBound) and \(workoutMinutesRange.upperBound). Nothing was logged.")
            }
            minutes = m
        }
        let focus = (input["focus"] as? String).flatMap(WorkoutFocus.init(rawValue:))
        let rawNote = (input["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (rawNote?.isEmpty == false) ? rawNote : nil
        let summary = "log a \(type.label.lowercased()) workout" + (minutes > 0 ? " (\(minutes) min)" : "")
        return .ok(ParsedRequest(
            name: .logWorkout,
            confirmSummary: summary,
            action: .logWorkout(type: type, minutes: minutes, focus: focus, notes: note)))
    }

    private static func parseEditPlan(input: [String: Any]) -> ParseResult {
        var edit = PlanEdit()
        if let h = (input["headline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty { edit.headline = h }
        if let a = (input["assessment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { edit.assessment = a }
        if let s = (input["strategy"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { edit.strategy = s }
        if let lo = doubleValue(input["calorie_min"]) {
            guard lo > 0 else { return .invalid("A calorie floor has to be above zero. Nothing was changed.") }
            edit.calorieMin = lo
        }
        if let hi = doubleValue(input["calorie_max"]) {
            guard hi > 0 else { return .invalid("A calorie ceiling has to be above zero. Nothing was changed.") }
            edit.calorieMax = hi
        }
        if let p = doubleValue(input["protein_target"]) {
            guard p >= 0 else { return .invalid("Protein can't be negative. Nothing was changed.") }
            edit.proteinTarget = p
        }
        if let lo = edit.calorieMin, let hi = edit.calorieMax, lo > hi {
            return .invalid("The calorie floor can't be above the ceiling. Nothing was changed.")
        }
        guard edit.hasAnyChange else {
            return .invalid("Tell me what to change on the plan — the targets, the focus, or the read. "
                          + "(If you just want to note something, use update_plan.) Nothing was changed.")
        }
        var note = (input["change_note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if note.isEmpty { note = "Adjusted the plan." }
        edit.changeNote = note
        // When targets change, phrase the confirm card like the other goal tools ("Want me to {…}?").
        // Prose-only edits auto-apply, so their summary is just the Undo-banner text.
        var targetParts: [String] = []
        if let p = edit.proteinTarget { targetParts.append("set your protein target to \(Int(p))g") }
        if let lo = edit.calorieMin, let hi = edit.calorieMax {
            targetParts.append("set your daily fuel to \(Int(lo))–\(Int(hi)) kcal")
        } else if let lo = edit.calorieMin {
            targetParts.append("raise your calorie floor to \(Int(lo)) kcal")
        } else if let hi = edit.calorieMax {
            targetParts.append("set your calorie ceiling to \(Int(hi)) kcal")
        }
        let summary = targetParts.isEmpty ? "update your plan — \(note)" : targetParts.joined(separator: " and ")
        return .ok(ParsedRequest(name: .editPlan,
                                 confirmSummary: summary,
                                 action: .editPlan(edit)))
    }

    private static func parseForget(input: [String: Any]) -> ParseResult {
        guard let fact = (input["fact"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fact.isEmpty else {
            return .invalid("Tell me what to forget. Nothing was changed.")
        }
        // Guard against a too-vague target ("i", "a") that, as a substring, would match — and wipe —
        // nearly every note. `removingFact` matches whole words, but require a real token up front too.
        guard fact.count >= 3 else {
            return .invalid("That's too broad to forget safely — name the specific thing "
                          + "(e.g. \"that I'm vegetarian\"). Nothing was changed.")
        }
        return .ok(ParsedRequest(name: .forgetFact,
                                 confirmSummary: "forget that \(fact)",
                                 action: .forgetFact(fact)))
    }

    private static func parseRemember(input: [String: Any]) -> ParseResult {
        guard let note = (input["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else {
            return .invalid("I need the detail to remember. Nothing was saved.")
        }
        guard note.count <= 280 else {
            return .invalid("That's a bit long to note — give me the short version. Nothing was saved.")
        }
        return .ok(ParsedRequest(
            name: .rememberFact,
            confirmSummary: "remember that \(note)",
            action: .rememberFact(note)))
    }

    private static func parseUpdatePlan(input: [String: Any]) -> ParseResult {
        guard let note = (input["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else {
            return .invalid("I need the detail of what's changing on your plan. Nothing was changed.")
        }
        guard note.count <= 280 else {
            return .invalid("That's a bit long for a plan note — give me the short version. Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .updatePlan,
            confirmSummary: "note on your plan that \(note)",
            action: .updatePlan(note: note)))
    }

    // MARK: - Parse helpers: settings / preferences tools
    //
    // One per Settings control. Each is pure, returns the same `ParseResult`, and validates against
    // the exact options/ranges the Settings UI offers so a tool call can never set an out-of-bounds
    // value. The confirmSummary phrasing matches the goal tools ("set your … to …").

    private static func parseSetUnits(input: [String: Any]) -> ParseResult {
        guard let raw = input["system"] as? String else {
            return .invalid("Tell me imperial or metric. Nothing was changed.")
        }
        guard let system = UnitSystem(rawValue: raw) else {
            return .invalid("\"\(raw)\" isn't a unit system I know (imperial or metric). Nothing was changed.")
        }
        let name = system == .imperial ? "imperial (lb)" : "metric (kg)"
        return .ok(ParsedRequest(
            name: .setUnits,
            confirmSummary: "switch your units to \(name)",
            action: .setUnits(system)))
    }

    private static func parseSetTheme(input: [String: Any]) -> ParseResult {
        guard let raw = input["theme"] as? String else {
            return .invalid("Tell me which look — cute or cool. Nothing was changed.")
        }
        guard let theme = ThemeStyle(rawValue: raw) else {
            return .invalid("\"\(raw)\" isn't a theme I know (cute or cool). Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .setTheme,
            confirmSummary: "switch your appearance to \(theme.label) (\(theme.blurb.lowercased()))",
            action: .setTheme(theme)))
    }

    private static func parseSetHomeGym(input: [String: Any]) -> ParseResult {
        guard let raw = input["gym"] as? String else {
            return .invalid("Tell me which gym. Nothing was changed.")
        }
        guard let gym = HomeGym(rawValue: raw) else {
            let names = HomeGym.allCases.map { $0.label }.joined(separator: ", ")
            return .invalid("I don't recognize that gym. I can set: \(names). Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .setHomeGym,
            confirmSummary: "set your home gym to \(gym.label)",
            action: .setHomeGym(gym)))
    }

    /// Goal-direction parse — maps lose/maintain/gain to the gentlest in-direction pace (mirroring
    /// Settings' `goalDirectionBinding`), so pace + direction stay consistent. Guards against an
    /// already-current direction so we never show a no-op confirm.
    private static func parseSetGoalDirection(input: [String: Any], profile: UserProfile) -> ParseResult {
        guard let raw = (input["direction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return .invalid("Tell me the direction — lose, maintain, or gain. Nothing was changed.")
        }
        let direction: GoalPace.Direction
        switch raw {
        case "lose", "lose weight", "loss", "cut":     direction = .lose
        case "maintain", "hold", "maintenance":        direction = .maintain
        case "gain", "gain weight", "bulk", "build":   direction = .gain
        default:
            return .invalid("\"\(raw)\" isn't a direction I know (lose, maintain, or gain). Nothing was changed.")
        }
        guard direction != profile.pace.direction else {
            let word = direction == .lose ? "losing" : (direction == .gain ? "gaining" : "maintaining")
            return .invalid("You're already set to \(word), so there's nothing to change.")
        }
        // Pick the gentlest pace that actually moves weight in the new direction (gain → Lean gain,
        // not the always-listed Maintain) — exactly like the Settings goal picker.
        let newPace = GoalPace.paces(for: direction).first { $0.direction == direction } ?? .maintain
        let label: String
        switch direction {
        case .lose:     label = "losing weight"
        case .gain:     label = "a lean gain"
        case .maintain: label = "maintaining"
        }
        let paceNote = direction == .maintain ? "" : " (on a \(newPace.label.lowercased()) pace)"
        return .ok(ParsedRequest(
            name: .setGoalDirection,
            confirmSummary: "switch your goal to \(label)\(paceNote)",
            action: .setGoalDirection(direction)))
    }

    private static func parseSetHeight(input: [String: Any]) -> ParseResult {
        guard let cm = doubleValue(input["cm"]) else {
            return .invalid("I need your height in centimetres. Nothing was changed.")
        }
        guard heightCmRange.contains(cm) else {
            return .invalid("A height of \(Int(cm.rounded())) cm is outside the range I can set "
                          + "(\(Int(heightCmRange.lowerBound))–\(Int(heightCmRange.upperBound)) cm). Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .setHeight,
            confirmSummary: "set your height to \(Int(cm.rounded())) cm",
            action: .setHeight(cm: cm)))
    }

    /// Birth-date parse — accepts EITHER an `age` in years (converted to a birth date) OR an ISO
    /// `date`. Either way the resulting age must land in `ageYearsRange`, and never the future.
    private static func parseSetBirthDate(input: [String: Any]) -> ParseResult {
        let cal = Calendar.current
        // Prefer an explicit ISO date when given; otherwise build one from the age.
        if let raw = (input["date"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let fmt = DateFormatter()
            fmt.calendar = cal
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd"
            guard let date = fmt.date(from: raw) else {
                return .invalid("I couldn't read that birth date — use YYYY-MM-DD. Nothing was changed.")
            }
            let age = cal.dateComponents([.year], from: date, to: .now).year ?? -1
            guard ageYearsRange.contains(age) else {
                return .invalid("That birth date works out to an age outside what I can set "
                              + "(\(ageYearsRange.lowerBound)–\(ageYearsRange.upperBound)). Nothing was changed.")
            }
            return .ok(ParsedRequest(
                name: .setBirthDate,
                confirmSummary: "set your age to \(age) (born \(raw))",
                action: .setBirthDate(date)))
        }
        if let age = intValue(input["age"]) {
            guard ageYearsRange.contains(age) else {
                return .invalid("An age of \(age) is outside what I can set "
                              + "(\(ageYearsRange.lowerBound)–\(ageYearsRange.upperBound)). Nothing was changed.")
            }
            // Mirror the model's own default: subtract `age` years from now. We don't try to recover
            // an exact birthday from an age — the BMR math only uses whole years anyway.
            guard let date = cal.date(byAdding: .year, value: -age, to: .now) else {
                return .invalid("I couldn't set that age. Nothing was changed.")
            }
            return .ok(ParsedRequest(
                name: .setBirthDate,
                confirmSummary: "set your age to \(age)",
                action: .setBirthDate(date)))
        }
        return .invalid("Tell me your age in years, or your birth date as YYYY-MM-DD. Nothing was changed.")
    }

    private static func parseSetSex(input: [String: Any]) -> ParseResult {
        guard let raw = input["sex"] as? String else {
            return .invalid("Tell me female or male (for the calorie math). Nothing was changed.")
        }
        guard let sex = BiologicalSex(rawValue: raw.lowercased()) else {
            return .invalid("\"\(raw)\" isn't a value I know (female or male). Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .setSex,
            confirmSummary: "set your biological sex to \(sex.label.lowercased()) (for the calorie math)",
            action: .setSex(sex)))
    }

    private static func parseSetActivityLevel(input: [String: Any]) -> ParseResult {
        guard let raw = input["level"] as? String else {
            return .invalid("Tell me your activity level. Nothing was changed.")
        }
        guard let level = ActivityLevel(rawValue: raw) else {
            let names = ActivityLevel.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            return .invalid("\"\(raw)\" isn't an activity level I know. Valid: \(names). Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .setActivityLevel,
            confirmSummary: "set your activity level to \(level.label.lowercased())",
            action: .setActivityLevel(level)))
    }

    private static func parseSetCompanion(input: [String: Any]) -> ParseResult {
        var newName: String?
        if let n = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            guard n.count <= 40 else {
                return .invalid("That name's a bit long — keep it short and sweet. Nothing was changed.")
            }
            newName = n
        }
        var avatar: CompanionAvatar?
        if let a = (input["avatar"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            guard let parsed = CompanionAvatar(rawValue: a.lowercased()) else {
                let names = CompanionAvatar.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " or ")
                return .invalid("\"\(a)\" isn't an avatar I have — pick \(names). Nothing was changed.")
            }
            avatar = parsed
        }
        guard newName != nil || avatar != nil else {
            return .invalid("Tell me a new name or which avatar for your companion. Nothing was changed.")
        }
        var parts: [String] = []
        if let n = newName { parts.append("name your companion \"\(n)\"") }
        if let a = avatar { parts.append("set its avatar to \(a.rawValue.capitalized)") }
        return .ok(ParsedRequest(
            name: .setCompanion,
            confirmSummary: parts.joined(separator: " and "),
            action: .setCompanion(name: newName, avatar: avatar)))
    }

    private static func parseSetCoachName(input: [String: Any]) -> ParseResult {
        guard let name = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return .invalid("Tell me what to call me. Nothing was changed.")
        }
        guard name.count <= 40 else {
            return .invalid("That name's a bit long — keep it short. Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .setCoachName,
            confirmSummary: "rename your coach to \(name)",
            action: .setCoachName(name)))
    }

    private static func parseSetWaterContainer(input: [String: Any]) -> ParseResult {
        guard let oz = doubleValue(input["oz"]) else {
            return .invalid("Tell me the size of your drink in ounces. Nothing was changed.")
        }
        guard waterContainerOzRange.contains(oz) else {
            return .invalid("\(Int(oz.rounded())) oz is outside the size I can set for one drink "
                          + "(\(Int(waterContainerOzRange.lowerBound))–\(Int(waterContainerOzRange.upperBound)) oz). Nothing was changed.")
        }
        var label: String?
        if let l = (input["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty {
            guard l.count <= 30 else {
                return .invalid("That container name's a bit long — keep it short (e.g. \"big bottle\"). Nothing was changed.")
            }
            label = l
        }
        let labelNote = label.map { " (\($0))" } ?? ""
        return .ok(ParsedRequest(
            name: .setWaterContainer,
            confirmSummary: "set one drink to \(Int(oz.rounded())) oz\(labelNote)",
            action: .setWaterContainer(oz: oz, label: label)))
    }

    private static func parseSetProteinGoal(input: [String: Any]) -> ParseResult {
        guard let grams = doubleValue(input["grams"]) else {
            return .invalid("I need a protein number in grams. Nothing was changed.")
        }
        guard proteinGoalRange.contains(grams) else {
            return .invalid("A protein target of \(Int(grams.rounded()))g is outside the range I can set "
                          + "(\(Int(proteinGoalRange.lowerBound))–\(Int(proteinGoalRange.upperBound))g). Nothing was changed.")
        }
        // 0 is the documented "clear the custom target, go back to the calculated one" value.
        if grams == 0 {
            return .ok(ParsedRequest(
                name: .setProteinGoal,
                confirmSummary: "clear your custom protein target (back to the calculated one)",
                action: .setProteinGoal(grams: 0)))
        }
        return .ok(ParsedRequest(
            name: .setProteinGoal,
            confirmSummary: "set your daily protein target to \(Int(grams.rounded()))g",
            action: .setProteinGoal(grams: grams)))
    }

    private static func parseToggleStepsInBudget(input: [String: Any]) -> ParseResult {
        guard let enabled = boolValue(input["enabled"]) else {
            return .invalid("Tell me whether to turn it on or off. Nothing was changed.")
        }
        return .ok(ParsedRequest(
            name: .toggleStepsInBudget,
            confirmSummary: enabled
                ? "let your steps add to your daily budget"
                : "stop your steps from adding to your daily budget",
            action: .toggleStepsInBudget(enabled)))
    }

    // MARK: - Parse helpers: data-logging tools
    //
    // Split out (one per tool) so the main `parse` switch stays readable; each is pure and
    // returns the same `ParseResult`. Names are matched case-insensitively against today's
    // entries for edit/delete.

    private static func parseLogFood(input: [String: Any]) -> ParseResult {
        guard let rawName = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return .invalid("I need the food's name to log it. Nothing was logged.")
        }
        guard let mealRaw = input["meal"] as? String, let meal = MealType(rawValue: mealRaw) else {
            return .invalid("I need to know which meal (breakfast, lunch, dinner, or snack). Nothing was logged.")
        }
        guard let calories = doubleValue(input["calories"]), calories >= 0,
              let protein = doubleValue(input["protein_g"]), protein >= 0,
              let carbs = doubleValue(input["carbs_g"]), carbs >= 0,
              let fat = doubleValue(input["fat_g"]), fat >= 0 else {
            return .invalid("I need non-negative calories and protein/carbs/fat in grams. Nothing was logged.")
        }
        // Quantity is optional; default 1, and never zero/negative.
        let quantity = doubleValue(input["quantity"]).map { $0 > 0 ? $0 : 1 } ?? 1

        var draft = FoodDraft()
        draft.name = rawName
        draft.meal = meal
        draft.quantity = quantity
        draft.calories = calories
        draft.proteinG = protein
        draft.carbsG = carbs
        draft.fatG = fat
        draft.source = .manual   // logged via the coach, same as a manual add
        draft.loggedDate = resolveLogDate(input["date"])   // nil = today; set only when back-dating

        // Show the TOTAL (per-serving × quantity), which is what actually lands in the diary.
        let totalKcal = Int((calories * quantity).rounded())
        let qtyNote = quantity != 1 ? " ×\(trimmed(quantity))" : ""
        let dayNote = draft.loggedDate != nil ? ((input["date"] as? String).map { " for \($0)" } ?? "") : ""
        return .ok(ParsedRequest(
            name: .logFood,
            confirmSummary: "log \(rawName)\(qtyNote) (\(totalKcal) kcal) to \(meal.label.lowercased())\(dayNote)",
            action: .logFood(draft)))
    }

    /// Resolve a tool-supplied log-date string to a concrete day (set to NOON, to dodge midnight
    /// edge cases), or `nil` for today / omitted / unparseable / future — so the apply just uses
    /// `.now`. Accepts "today", "yesterday", or an ISO "yyyy-MM-dd". Never returns a future day.
    static func resolveLogDate(_ raw: Any?) -> Date? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty, s != "today" else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func noon(_ day: Date) -> Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day }
        if s == "yesterday" {
            return cal.date(byAdding: .day, value: -1, to: today).map(noon)
        }
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        if let parsed = fmt.date(from: s) {
            let day = cal.startOfDay(for: parsed)
            return day <= today ? noon(day) : nil   // never the future
        }
        return nil
    }

    private static func parseEditFood(input: [String: Any], todaysFoods: [FoodEntry]) -> ParseResult {
        guard let query = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return .invalid("Tell me which item to edit (by name). Nothing was changed.")
        }
        let match: FoodEntry
        switch resolveEntry(named: query, in: todaysFoods) {
        case .found(let e):       match = e
        case .invalid(let msg):   return .invalid(msg)
        }

        // Build the partial edit from whatever fields were supplied. An edit with no actual
        // changes is bounced so we never show a confirm/Undo for a no-op.
        var edit = FoodEdit()
        if let n = (input["new_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            edit.name = n
        }
        if let m = input["meal"] as? String, let meal = MealType(rawValue: m) { edit.meal = meal }
        if let c = doubleValue(input["calories"]) {
            guard c >= 0 else { return .invalid("Calories can't be negative. Nothing was changed.") }
            edit.calories = c
        }
        if let p = doubleValue(input["protein_g"]) {
            guard p >= 0 else { return .invalid("Protein can't be negative. Nothing was changed.") }
            edit.proteinG = p
        }
        if let c = doubleValue(input["carbs_g"]) {
            guard c >= 0 else { return .invalid("Carbs can't be negative. Nothing was changed.") }
            edit.carbsG = c
        }
        if let f = doubleValue(input["fat_g"]) {
            guard f >= 0 else { return .invalid("Fat can't be negative. Nothing was changed.") }
            edit.fatG = f
        }
        if let q = doubleValue(input["quantity"]) {
            guard q > 0 else { return .invalid("Quantity has to be more than zero. Nothing was changed.") }
            edit.quantity = q
        }
        guard edit.hasAnyChange else {
            return .invalid("I couldn't tell what to change on \"\(match.name)\". "
                          + "Let me know which value to update. Nothing was changed.")
        }

        return .ok(ParsedRequest(
            name: .editFood,
            confirmSummary: "update \"\(match.name)\"",
            action: .editFood(id: match.id, changes: edit)))
    }

    private static func parseDeleteFood(input: [String: Any], todaysFoods: [FoodEntry]) -> ParseResult {
        guard let query = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return .invalid("Tell me which item to remove (by name). Nothing was deleted.")
        }
        switch resolveEntry(named: query, in: todaysFoods) {
        case .found(let e):
            return .ok(ParsedRequest(
                name: .deleteFood,
                confirmSummary: "delete \"\(e.name)\" from today's log",
                action: .deleteFood(id: e.id)))
        case .invalid(let msg):
            return .invalid(msg)
        }
    }

    private static func parseLogWater(input: [String: Any], profile: UserProfile) -> ParseResult {
        // Accept EITHER containers (preferred) or an explicit oz amount — exactly one.
        if let count = intValue(input["containers"]) {
            guard waterContainersLogRange.contains(count) else {
                return .invalid("I can log between \(waterContainersLogRange.lowerBound) and "
                              + "\(waterContainersLogRange.upperBound) \(containerLabel(profile, count: 2)) at once. "
                              + "Nothing was logged.")
            }
            let oz = Double(count) * containerSize(profile)
            let label = containerLabel(profile, count: count)
            return .ok(ParsedRequest(
                name: .logWater,
                confirmSummary: "log \(count) \(label) of water",
                action: .logWaterOz(oz)))
        }
        if let oz = doubleValue(input["oz"]) {
            guard waterOzRange.contains(oz) else {
                return .invalid("\(Int(oz.rounded())) oz is outside what I can log at once "
                              + "(\(Int(waterOzRange.lowerBound))–\(Int(waterOzRange.upperBound)) oz). Nothing was logged.")
            }
            return .ok(ParsedRequest(
                name: .logWater,
                confirmSummary: "log \(Int(oz.rounded())) oz of water",
                action: .logWaterOz(oz)))
        }
        return .invalid("Tell me how much water — a number of \(containerLabel(profile, count: 2)) or ounces. Nothing was logged.")
    }

    private static func parseLogWeight(input: [String: Any], profile: UserProfile) -> ParseResult {
        let unit = profile.unitSystem.weightUnit
        guard let weight = doubleValue(input["weight"]) else {
            return .invalid("I need a number for your weigh-in. Nothing was logged.")
        }
        guard weightRangeLbs.contains(weight) else {
            return .invalid("A weigh-in of \(trimmed(weight)) \(unit) is outside the range I can log "
                          + "(\(Int(weightRangeLbs.lowerBound))–\(Int(weightRangeLbs.upperBound)) \(unit)). Nothing was logged.")
        }
        return .ok(ParsedRequest(
            name: .logWeight,
            confirmSummary: "log today's weigh-in at \(trimmed(weight)) \(unit)",
            action: .logWeight(lbs: weight)))
    }

    private static func parseWeightGoal(input: [String: Any], profile: UserProfile) -> ParseResult {
        let unit = profile.unitSystem.weightUnit
        guard let goal = doubleValue(input["weight"]) else {
            return .invalid("I need a number for your goal weight. Nothing was changed.")
        }
        guard weightRangeLbs.contains(goal) else {
            return .invalid("A goal of \(trimmed(goal)) \(unit) is outside the sensible range "
                          + "(\(Int(weightRangeLbs.lowerBound))–\(Int(weightRangeLbs.upperBound)) \(unit)). Nothing was changed.")
        }
        // The goal must lie in her goal DIRECTION relative to where she is now (her start
        // weight; see `currentWeightLbs`). This is a target only; her calorie intake stays
        // computed + floored regardless, so there's no eat-less lever here — just a guard
        // against an obviously contradictory target.
        let current = currentWeightLbs(profile)
        switch profile.pace.direction {
        case .lose:
            guard goal < current else {
                return .invalid("You're set to lose weight, so your goal should be below your current "
                              + "\(trimmed(current)) \(unit). Want to pick a lower number? Nothing was changed.")
            }
        case .gain:
            guard goal > current else {
                return .invalid("You're set to gain, so your goal should be above your current "
                              + "\(trimmed(current)) \(unit). Want to pick a higher number? Nothing was changed.")
            }
        case .maintain:
            break   // maintaining — any sane target is fine (it just reframes the chart line)
        }
        return .ok(ParsedRequest(
            name: .setWeightGoal,
            confirmSummary: "set your goal weight to \(trimmed(goal)) \(unit)",
            action: .weightGoal(lbs: goal)))
    }

    /// Result of resolving a name to a single logged entry.
    private enum EntryResolution { case found(FoodEntry), invalid(String) }

    /// Find the one food entry today whose name matches `query`. Prefers an exact
    /// (case-insensitive) match; falls back to a unique substring match. Returns a friendly
    /// `.invalid` when there's nothing logged, no match, or more than one plausible match —
    /// so the coach asks the user to clarify instead of editing the wrong row.
    private static func resolveEntry(named query: String, in foods: [FoodEntry]) -> EntryResolution {
        guard !foods.isEmpty else {
            return .invalid("You haven't logged anything today yet, so there's nothing to change.")
        }
        let needle = query.lowercased()

        let exact = foods.filter { $0.name.lowercased() == needle }
        if exact.count == 1 { return .found(exact[0]) }
        if exact.count > 1 {
            return .invalid("You have \(exact.count) items called \"\(query)\" today — which one did you mean?")
        }

        let contains = foods.filter { $0.name.lowercased().contains(needle) }
        if contains.count == 1 { return .found(contains[0]) }
        if contains.count > 1 {
            let names = contains.map { "\"\($0.name)\"" }.joined(separator: ", ")
            return .invalid("A few of today's items match \"\(query)\" (\(names)) — which one did you mean?")
        }

        return .invalid("I couldn't find \"\(query)\" in today's log. Could you tell me its exact name?")
    }

    // MARK: - Apply (called after confirm, or immediately for auto-apply tools)

    /// The outcome of applying a tool: the model-facing confirmation string, plus an optional
    /// `undo` that EXACTLY reverses the write (present for the reversible auto-apply logs).
    /// The undo runs on the main actor moments later; for edits it re-fetches by id.
    struct Applied {
        let message: String
        let undo: (@MainActor () -> Void)?
    }

    /// The authoritative "today so far" calorie line for a tool result, computed EXACTLY like the
    /// food log (`FoodLogView`): same `basisWeight` (current trend, else start weight, else 150) and
    /// `dailyCalorieTarget`. Handing this to Vita stops her recomputing "kcal left" in chat and
    /// getting it wrong. `nil` when there's no usable target. Returns e.g. "Today so far: 1555 of
    /// 1740 kcal (185 left)."
    @MainActor
    static func calorieStatusLine(profile: UserProfile, context: ModelContext) -> String? {
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        let cal = Calendar.current
        let consumed = foods.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.totalCalories }
        let basis = TrendCalculator.currentTrend(weights)
            ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
        let target = profile.dailyCalorieTarget(weightLbs: basis)
        guard target > 0 else { return nil }
        let consumedI = Int(consumed.rounded()), targetI = Int(target.rounded())
        let remaining = targetI - consumedI
        if remaining >= 0 {
            return "Today so far: \(consumedI) of \(targetI) kcal (\(remaining) left)."
        }
        return "Today so far: \(consumedI) of \(targetI) kcal (\(-remaining) over — and that's okay, one day doesn't define the week)."
    }

    /// Apply a confirmed change and return just the message. Thin wrapper over
    /// `applyReturningUndo` so the confirm path + existing tests keep their `String` contract.
    @MainActor
    static func apply(_ request: ParsedRequest,
                      to profile: UserProfile,
                      context: ModelContext) -> String {
        applyReturningUndo(request, to: profile, context: context).message
    }

    /// Apply a change and persist it, returning the message AND (for reversible logs) an
    /// `undo` closure. The auto-apply path uses the undo to offer a one-tap revert.
    @MainActor
    static func applyReturningUndo(_ request: ParsedRequest,
                                   to profile: UserProfile,
                                   context: ModelContext) -> Applied {
        switch request.action {
        case .stepGoal(let steps):
            let old = profile.dailyStepGoal
            profile.dailyStepGoal = steps
            try? context.save()
            return Applied(message: "Daily step goal is now \(grouped(steps)) steps.",
                           undo: { profile.dailyStepGoal = old; try? context.save() })

        case .waterContainers(let count):
            // The by-the-bottle UI stores the goal in oz as `count × container size`,
            // exactly how the Settings stepper does it. `waterGoalContainers` reads it
            // back as round(targetOz / containerSize), so this round-trips to `count`.
            let oldOverride = profile.waterGoalOzOverride
            let size = profile.waterContainerOz > 0 ? profile.waterContainerOz : 16.9
            profile.waterGoalOzOverride = Double(count) * size
            try? context.save()
            let label = containerLabel(profile, count: count)
            return Applied(message: "Daily water goal is now \(count) \(label).",
                           undo: { profile.waterGoalOzOverride = oldOverride; try? context.save() })

        case .pace(let pace):
            let old = profile.pace
            profile.pace = pace   // enum setter writes paceRaw
            try? context.save()
            return Applied(message: "Goal pace is now \(pace.label) (\(pace.subtitle.lowercased())).",
                           undo: { profile.pace = old; try? context.save() })

        case .logFood(let draft):
            // Run a plausibility check; we still log either way (it's her data), but a
            // flagged item carries a friendly note both on the entry and back to the model.
            let sanity = NutritionSanity.check(calories: draft.calories,
                                               protein: draft.proteinG,
                                               carbs: draft.carbsG,
                                               fat: draft.fatG)
            let note = sanity.isSuspicious ? sanity.reason : nil
            // Build the entry exactly like the manual-add path (AddFoodSheet.save). `loggedDate`
            // is set only when the coach back-dates a forgotten meal; otherwise it's today.
            let entry = FoodEntry(
                date: draft.loggedDate ?? .now,
                mealType: draft.meal,
                name: draft.name,
                servingDescription: draft.servingDescription,
                quantity: draft.quantity == 0 ? 1 : draft.quantity,
                calories: draft.calories,
                proteinG: draft.proteinG,
                carbsG: draft.carbsG,
                fatG: draft.fatG,
                source: draft.source,
                notes: note)
            context.insert(entry)
            try? context.save()
            var msg = "Logged \(entry.name) to \(entry.mealType.label.lowercased()): "
                + "\(Int(entry.totalCalories.rounded())) kcal, \(Int(entry.totalProteinG.rounded()))g protein."
            if let note { msg += " Note: \(note)." }
            // Hand Vita the AUTHORITATIVE post-log day total so she states the real "kcal left"
            // instead of doing her own (error-prone) chat arithmetic — she was getting it wrong
            // (e.g. saying 80 left when 185 was actually left, double-counting the item she'd just
            // logged). Computed exactly like the food log (same basisWeight + target) so the number
            // matches what the user sees on the Nutrients card.
            if let status = calorieStatusLine(profile: profile, context: context) { msg += " " + status }
            return Applied(message: msg,
                           undo: { context.delete(entry); try? context.save() })

        case .logWorkout(let type, let minutes, let focus, let notes):
            let workout = WorkoutEntry(type: type, durationMinutes: minutes, focus: focus, notes: notes)
            context.insert(workout)
            try? context.save()
            var wmsg = "Logged a \(workout.type.label.lowercased()) workout"
            if minutes > 0 { wmsg += " — \(minutes) min" }
            wmsg += ". Showing up counts 💪"
            return Applied(message: wmsg,
                           undo: { context.delete(workout); try? context.save() })

        case .editPlan(let edit):
            guard let plan = CoachPlan.current(in: context) else {
                return Applied(message: "She doesn't have a plan yet — she can build one on the Progress tab.",
                               undo: nil)
            }
            // Snapshot everything edit_plan can touch so undo restores exactly it.
            let b = (plan.headline, plan.assessment, plan.strategy,
                     plan.calorieMin, plan.calorieMax, plan.proteinTarget, plan.changelog, plan.updatedAt)
            if let h = edit.headline { plan.headline = h }
            if let a = edit.assessment { plan.assessment = a }
            if let s = edit.strategy { plan.strategy = s }
            if let lo = edit.calorieMin { plan.calorieMin = lo }
            if let hi = edit.calorieMax { plan.calorieMax = hi }
            if let p = edit.proteinTarget { plan.proteinTarget = p }
            plan.changelog = plan.changelog + [PlanChange(date: .now, summary: edit.changeNote)]
            plan.updatedAt = .now
            try? context.save()
            return Applied(message: "Updated your plan — \(edit.changeNote)", undo: {
                plan.headline = b.0; plan.assessment = b.1; plan.strategy = b.2
                plan.calorieMin = b.3; plan.calorieMax = b.4; plan.proteinTarget = b.5
                plan.changelog = b.6; plan.updatedAt = b.7
                try? context.save()
            })

        case .forgetFact(let fact):
            let memory = CoachMemory.fetchOrCreate(in: context, profile: profile)
            let before = memory.profileNotes
            guard let kept = removingFact(fact, from: before) else {
                return Applied(message: "I didn't find anything about \"\(fact)\" in what I remember, so nothing changed.",
                               undo: nil)
            }
            memory.profileNotes = kept
            memory.updatedAt = .now
            try? context.save()
            return Applied(message: "Done — I've forgotten that.", undo: {
                memory.profileNotes = before; memory.updatedAt = .now; try? context.save()
            })

        case .editFood(let id, let changes):
            guard let entry = fetchFood(id: id, context: context) else {
                return Applied(message: "I couldn't find that item anymore — it may have already been changed or removed.",
                               undo: nil)
            }
            // Snapshot the fields we're about to touch so undo restores exactly them.
            let before = FoodEdit(name: entry.name, meal: entry.mealType,
                                  calories: entry.calories, proteinG: entry.proteinG,
                                  carbsG: entry.carbsG, fatG: entry.fatG, quantity: entry.quantity)
            // Apply only the supplied fields (in place, preserving identity/source), exactly
            // like editing through AddFoodSheet.
            if let n = changes.name { entry.name = n }
            if let m = changes.meal { entry.mealType = m }
            if let c = changes.calories { entry.calories = c }
            if let p = changes.proteinG { entry.proteinG = p }
            if let c = changes.carbsG { entry.carbsG = c }
            if let f = changes.fatG { entry.fatG = f }
            if let q = changes.quantity { entry.quantity = q }
            try? context.save()
            let msg = "Updated \(entry.name): \(Int(entry.totalCalories.rounded())) kcal, "
                + "\(Int(entry.totalProteinG.rounded()))g protein, in \(entry.mealType.label.lowercased())."
            return Applied(message: msg, undo: {
                guard let e = fetchFood(id: id, context: context) else { return }
                e.name = before.name ?? e.name
                if let m = before.meal { e.mealType = m }
                e.calories = before.calories ?? e.calories
                e.proteinG = before.proteinG ?? e.proteinG
                e.carbsG = before.carbsG ?? e.carbsG
                e.fatG = before.fatG ?? e.fatG
                e.quantity = before.quantity ?? e.quantity
                try? context.save()
            })

        case .deleteFood(let id):
            guard let entry = fetchFood(id: id, context: context) else {
                return Applied(message: "That item was already gone — nothing to delete.", undo: nil)
            }
            let name = entry.name
            context.delete(entry)
            try? context.save()
            return Applied(message: "Removed \"\(name)\" from today's log.", undo: nil)

        case .logWaterOz(let oz):
            // ADD to today's total exactly like the dashboard + button: one new WaterEntry.
            let water = WaterEntry(amountOz: oz)
            context.insert(water)
            try? context.save()
            return Applied(message: "Logged \(Int(oz.rounded())) oz of water.",
                           undo: { context.delete(water); try? context.save() })

        case .logWeight(let lbs):
            // Stored as the entered number, like the weigh-in sheet (no kg conversion here).
            let weight = WeightEntry(weightLbs: lbs)
            context.insert(weight)
            try? context.save()
            let unit = profile.unitSystem.weightUnit
            return Applied(message: "Logged today's weigh-in: \(trimmed(lbs)) \(unit). Remember, the trend is what matters.",
                           undo: { context.delete(weight); try? context.save() })

        case .weightGoal(let lbs):
            let old = profile.goalWeightLbs
            profile.goalWeightLbs = lbs
            try? context.save()
            let unit = profile.unitSystem.weightUnit
            return Applied(message: "Goal weight is now \(trimmed(lbs)) \(unit).",
                           undo: { profile.goalWeightLbs = old; try? context.save() })

        case .rememberFact(let note):
            // Append the fact to her durable long-term notes (which `CoachContext` re-injects
            // into every future turn), so Vita actually remembers it — this is the tool that
            // makes "update my profile" real.
            let memory = CoachMemory.fetchOrCreate(in: context, profile: profile)
            let old = memory.profileNotes
            let line = "- \(note)"
            memory.profileNotes = old.isEmpty ? line : old + "\n" + line
            // Bounded (most-recent kept) so a long history can't bloat the prompt.
            if memory.profileNotes.count > 2000 {
                memory.profileNotes = String(memory.profileNotes.suffix(2000))
            }
            memory.updatedAt = .now
            try? context.save()
            return Applied(message: "Noted — I'll remember that.", undo: {
                let m = CoachMemory.fetchOrCreate(in: context, profile: profile)
                m.profileNotes = old
                try? context.save()
            })

        case .updatePlan(let note):
            // Append a visible line to her adaptive Plan's changelog so the adaptation is never
            // silent. No plan yet → nothing to amend (she builds one on Progress first).
            guard let plan = CoachPlan.current(in: context) else {
                return Applied(message: "She doesn't have a plan yet — she can build one on the Progress tab.",
                               undo: nil)
            }
            let old = plan.changelog
            plan.changelog.append(PlanChange(date: .now, summary: note))
            plan.updatedAt = .now
            try? context.save()
            return Applied(message: "Noted on your plan.", undo: {
                plan.changelog = old
                try? context.save()
            })

        // MARK: Settings / preferences applies (each captures the old value for Undo)

        case .setUnits(let system):
            let old = profile.unitSystem
            profile.unitSystem = system   // enum setter writes unitSystemRaw
            try? context.save()
            let name = system == .imperial ? "imperial (lb)" : "metric (kg)"
            return Applied(message: "Units are now \(name).",
                           undo: { profile.unitSystem = old; try? context.save() })

        case .setTheme(let theme):
            let old = profile.themeStyle
            profile.themeStyle = theme   // enum setter writes themeStyleRaw
            try? context.save()
            return Applied(message: "Appearance is now \(theme.label) — \(theme.blurb.lowercased()).",
                           undo: { profile.themeStyle = old; try? context.save() })

        case .setHomeGym(let gym):
            let old = profile.homeGym
            profile.homeGym = gym   // optional setter writes homeGymRaw
            try? context.save()
            return Applied(message: "Home gym is now \(gym.label).",
                           undo: { profile.homeGym = old; try? context.save() })

        case .setGoalDirection(let direction):
            // Mirror Settings' goalDirectionBinding: changing direction snaps the pace to the
            // gentlest one that moves weight that way (gain → Lean gain, not Maintain). The pace
            // stays the single stored source of truth, so undo just restores the old pace.
            let oldPace = profile.pace
            let newPace = GoalPace.paces(for: direction).first { $0.direction == direction } ?? .maintain
            profile.pace = newPace
            try? context.save()
            let label: String
            switch direction {
            case .lose:     label = "losing weight"
            case .gain:     label = "a lean gain"
            case .maintain: label = "maintaining"
            }
            let paceNote = direction == .maintain ? "" : " (\(newPace.label) pace)"
            return Applied(message: "Your goal is now \(label)\(paceNote).",
                           undo: { profile.pace = oldPace; try? context.save() })

        case .setHeight(let cm):
            let old = profile.heightCm
            profile.heightCm = cm
            try? context.save()
            return Applied(message: "Height is now \(Int(cm.rounded())) cm.",
                           undo: { profile.heightCm = old; try? context.save() })

        case .setBirthDate(let date):
            let old = profile.birthDate
            profile.birthDate = date
            try? context.save()
            return Applied(message: "Got it — your age is now set to \(profile.ageYears).",
                           undo: { profile.birthDate = old; try? context.save() })

        case .setSex(let sex):
            let old = profile.sex
            profile.sex = sex   // enum setter writes sexRaw
            try? context.save()
            return Applied(message: "Biological sex is now \(sex.label.lowercased()) (used only for the calorie math).",
                           undo: { profile.sex = old; try? context.save() })

        case .setActivityLevel(let level):
            let old = profile.activityLevel
            profile.activityLevel = level   // enum setter writes activityLevelRaw
            try? context.save()
            return Applied(message: "Activity level is now \(level.label.lowercased()).",
                           undo: { profile.activityLevel = old; try? context.save() })

        case .setCompanion(let name, let avatar):
            // Capture both fields; restore exactly what changed on undo.
            let oldName = profile.companionName
            let oldAvatar = profile.companionAvatar
            if let name { profile.companionName = name }
            if let avatar { profile.companionAvatar = avatar }
            try? context.save()
            var msg = "Your companion is now"
            if let name { msg += " \"\(name)\"" }
            if let avatar { msg += (name != nil ? " (\(avatar.rawValue.capitalized) avatar)" : " the \(avatar.rawValue.capitalized) avatar") }
            msg += "."
            return Applied(message: msg, undo: {
                profile.companionName = oldName
                profile.companionAvatar = oldAvatar
                try? context.save()
            })

        case .setCoachName(let name):
            let old = profile.coachName
            profile.coachName = name
            try? context.save()
            return Applied(message: "You can call me \(name) from now on.",
                           undo: { profile.coachName = old; try? context.save() })

        case .setWaterContainer(let oz, let label):
            // Capture both size + label so undo restores the pair. Only overwrite the label when she
            // gave one (otherwise keep her existing label for the new size).
            let oldOz = profile.waterContainerOz
            let oldLabel = profile.waterContainerLabel
            profile.waterContainerOz = oz
            if let label { profile.waterContainerLabel = label }
            try? context.save()
            let shownLabel = profile.waterContainerLabel.isEmpty ? "drink" : profile.waterContainerLabel
            return Applied(message: "One \(shownLabel) is now \(Int(oz.rounded())) oz.",
                           undo: {
                               profile.waterContainerOz = oldOz
                               profile.waterContainerLabel = oldLabel
                               try? context.save()
                           })

        case .setProteinGoal(let grams):
            // Write the override DIRECTLY so it works even with no plan (macroTargets honors it).
            // 0 clears it → back to the calculated target.
            let old = profile.proteinTargetOverride
            profile.proteinTargetOverride = grams
            try? context.save()
            let msg = grams == 0
                ? "Cleared your custom protein target — back to the calculated one."
                : "Daily protein target is now \(Int(grams.rounded()))g."
            return Applied(message: msg,
                           undo: { profile.proteinTargetOverride = old; try? context.save() })

        case .toggleStepsInBudget(let enabled):
            let old = profile.stepsAdjustCalories
            profile.stepsAdjustCalories = enabled
            try? context.save()
            let msg = enabled
                ? "Your steps above baseline will now add a little to your daily budget."
                : "Steps will no longer add to your daily budget."
            return Applied(message: msg,
                           undo: { profile.stepsAdjustCalories = old; try? context.save() })
        }
    }

    /// Re-fetch a `FoodEntry` by id from the context (we never carry a live @Model across
    /// the confirm/await gap — `parse` resolves the id, `apply` looks it up fresh).
    @MainActor
    private static func fetchFood(id: UUID, context: ModelContext) -> FoodEntry? {
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Remove `fact` from durable profile notes WITHOUT collateral damage. Matches the fact as a
    /// whole word/phrase (so "art" can't delete "startup", and a stray "i" can't delete every line),
    /// and on a multi-fact line — the comma/“·”-joined onboarding seed is a single line — strips only
    /// the matching clause(s) instead of nuking the whole line. Returns the new notes, or nil when
    /// nothing matched (caller reports "didn't find anything"). Pure + testable.
    static func removingFact(_ fact: String, from notes: String) -> String? {
        let needle = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 3, !notes.isEmpty else { return nil }
        // Whole-word, but tolerant of a common inflection on the last word — so "desk job" still
        // matches a stored "desk jobs" (autocorrect/plural), while the leading \b still prevents the
        // dangerous mid-word over-match ("art" must not hit "startup").
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "(ing|es|ed|'s|s)?\\b"
        func matches(_ s: String) -> Bool {
            s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        var changed = false
        var outLines: [String] = []
        for raw in notes.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard matches(raw) else { outLines.append(raw); continue }
            if raw.contains(",") || raw.contains("·") {
                // Multi-clause line → drop only the offending clause(s), keep the rest.
                let kept = raw.components(separatedBy: CharacterSet(charactersIn: ",·"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !matches($0) }
                changed = true
                if !kept.isEmpty { outLines.append(kept.joined(separator: ", ")) }
            } else {
                changed = true   // single-fact line → drop it entirely
            }
        }
        guard changed else { return nil }
        return outLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
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

    /// Accepts Double / Int / numeric-String JSON (the model often sends whole numbers as Int).
    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// Accepts a JSON boolean (Bool/NSNumber) or a common truthy/falsy string ("true"/"on"/"yes",
    /// "false"/"off"/"no") — the model occasionally sends the toggle value as a word.
    private static func boolValue(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        if let s = (any as? String)?.trimmingCharacters(in: .whitespaces).lowercased() {
            switch s {
            case "true", "on", "yes", "1":  return true
            case "false", "off", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    /// The size of one logged container in oz (her bottle/glass), same fallback as the UI.
    private static func containerSize(_ profile: UserProfile) -> Double {
        profile.waterContainerOz > 0 ? profile.waterContainerOz : 16.9
    }

    /// Her current weight for the goal-direction check. `parse` is pure (no weigh-in
    /// history), so we use her start weight — the "where you are now" she set at onboarding —
    /// falling back to the same 150 lb default the rest of the app uses. This guards only
    /// against an obviously contradictory target (e.g. a loss user aiming higher); it is not
    /// an intake lever.
    private static func currentWeightLbs(_ profile: UserProfile) -> Double {
        profile.startWeightLbs > 0 ? profile.startWeightLbs : 150
    }

    /// A weight number without a trailing ".0" (e.g. "152" not "152.0", but "150.4" kept).
    private static func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
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
