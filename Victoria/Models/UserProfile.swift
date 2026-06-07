import Foundation
import SwiftData

/// The single user profile (Victoria). There is exactly one of these in the store.
/// Stores onboarding inputs + preferences; calorie/macro targets are *computed* from
/// these via `NutritionMath` (see UserProfile+Targets) so they always stay consistent.
@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""

    // Biometrics
    var sexRaw: String = BiologicalSex.female.rawValue
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var heightCm: Double = 165

    // Goal
    var activityLevelRaw: String = ActivityLevel.light.rawValue
    var paceRaw: String = GoalPace.relaxed.rawValue
    var startWeightLbs: Double = 0
    var goalWeightLbs: Double = 0

    // Preferences
    var unitSystemRaw: String = UnitSystem.imperial.rawValue
    var coachName: String = "Vita"
    var dailyStepGoal: Int = 8000
    var stepsAdjustCalories: Bool = false
    var onboardingComplete: Bool = false
    var createdAt: Date = Date.now

    /// Free-text context she optionally shares during onboarding ("your routine, what
    /// you enjoy, what's worked or felt hard before"). Plain, unparsed text — used to
    /// personalize her plan and Vita's tone, never to compute targets. Default "".
    var onboardingNote: String = ""

    // Water preferences
    /// User's chosen daily water goal in oz. 0 = use the computed default (½ bodyweight).
    var waterGoalOzOverride: Double = 0
    /// Size of "one drink" she logs with the + button, in oz. Default ≈ a standard 500 ml bottle.
    var waterContainerOz: Double = 16.9
    /// Friendly label for that container ("bottle", "glass", "cup").
    var waterContainerLabel: String = "bottle"

    // Plan-driven targets (single source of truth)
    /// When the adaptive Plan is active, ITS targets become the app's targets: these mirror the
    /// plan's calorie floor + protein target so every ring / achievement / Vita read (all of which
    /// go through `dailyCalorieTarget` / `macroTargets`) reflects the plan — with NO call site needing
    /// to know about the plan. `0` = no plan, use the computed default. Kept in sync reactively from
    /// `CoachPlan` (see RootView.syncPlanTargets). The calorie value is still clamped to the safe floor
    /// at read time, so a plan can never route the app below a safe intake. Defaulted for CloudKit/
    /// SwiftData migration (older rows read as 0 → computed).
    var calorieTargetOverride: Double = 0
    var proteinTargetOverride: Double = 0
    /// The plan's soft calorie CEILING (kcal) — the top of her daily range — mirrored from
    /// `CoachPlan.calorieMax`. `0` = no plan ceiling (a band is synthesized around the target).
    /// Defaulted so the @Model stays SwiftData-migration- and CloudKit-ready.
    var calorieMaxOverride: Double = 0

    // Buddy
    /// Opt-IN to sharing the FULL daily picture (weight trend, calories, protein, today's
    /// foods) with a paired buddy — not just the safe activity face-off. Default `true`:
    /// this is for partners who've explicitly chosen to share everything (see the Buddy
    /// settings toggle). The publish path only fills the full-data snapshot fields when
    /// this is on, so flipping it off instantly reverts to the activity-only contract.
    /// Defaulted so the @Model stays SwiftData-migration- and CloudKit-ready (older rows
    /// read as the opt-in default).
    var shareFullStatsWithBuddy: Bool = true

    // Companion
    /// The little buddy's name (she can rename it). Thrives when she eats enough + balanced + hydrated.
    var companionName: String = "Sprout"
    /// Which pixel avatar the solo companion uses (Victoria vs Bryan).
    var companionAvatarRaw: String = CompanionAvatar.victoria.rawValue

    /// Last day the Alejandro "rival" goal-hit gag played — caps it to once per day. The rival
    /// is a motivational figure only (no data sync). See `AlejandroGagOverlay`.
    var lastAlejandroGagDate: Date = Date.distantPast

    // Appearance
    /// Visual theme/skin: `.cute` (Victoria — warm pastel, light) or `.cool`
    /// (Bryan — bold dark, electric lime). Same layout/flow either way.
    var themeStyleRaw: String = ThemeStyle.cute.rawValue

    // Reminders
    var weighInReminderEnabled: Bool = true
    var weighInHour: Int = 8           // 8 AM
    var mealRemindersEnabled: Bool = true
    var breakfastHour: Int = 9
    var lunchHour: Int = 13
    var dinnerHour: Int = 19
    var gymReminderEnabled: Bool = false
    var gymHour: Int = 17
    /// Weekday numbers (1=Sun ... 7=Sat) the user wants a gym nudge.
    var gymWeekdays: [Int] = [2, 4, 6]

    // AI
    /// Preferred Anthropic model id. The key itself lives in the Keychain, never here.
    var aiModelFood: String = "claude-sonnet-4-6"
    var aiModelChat: String = "claude-sonnet-4-6"

    // Workouts
    /// The user's primary gym (raw `HomeGym` value; "" = unset). Used to show machine photos +
    /// personalize context — it does NOT filter the (universal) machine catalog. Defaulted so the
    /// @Model stays SwiftData-migration- and CloudKit-ready (older rows read as unset).
    var homeGymRaw: String = ""

    init() {
        self.id = UUID()
        self.createdAt = .now
    }

    // MARK: Enum accessors
    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .female }
        set { sexRaw = newValue.rawValue }
    }
    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .light }
        set { activityLevelRaw = newValue.rawValue }
    }
    var pace: GoalPace {
        get { GoalPace(rawValue: paceRaw) ?? .relaxed }
        set { paceRaw = newValue.rawValue }
    }
    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .imperial }
        set { unitSystemRaw = newValue.rawValue }
    }
    var themeStyle: ThemeStyle {
        get { ThemeStyle(rawValue: themeStyleRaw) ?? .cute }
        set { themeStyleRaw = newValue.rawValue }
    }
    var companionAvatar: CompanionAvatar {
        get { CompanionAvatar(rawValue: companionAvatarRaw) ?? .victoria }
        set { companionAvatarRaw = newValue.rawValue }
    }
    /// The user's primary gym, or `nil` when unset. Backed by `homeGymRaw`.
    var homeGym: HomeGym? {
        get { HomeGym(rawValue: homeGymRaw) }
        set { homeGymRaw = newValue?.rawValue ?? "" }
    }

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 25
    }
}
