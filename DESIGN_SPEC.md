# Victoria — Native iOS Design Spec (dark "fitness" aesthetic)

This is the contract for the visual-polish pass. The goal: **Apple Fitness / Activity-app caliber** native iOS quality, in a committed **dark, bold, electric-lime** theme. Match this exactly. Do NOT invent tokens, colors, fonts, or model APIs — use ONLY what's listed here (all of it already exists and compiles).

## Aesthetic
- **Committed dark.** Whole app forces `.dark`. Canvas is near-black (`Theme.background`).
- **One high-voltage accent:** electric lime (`Theme.brand`). Use it sparingly for emphasis — hero ring, key numbers, selected states, primary buttons. Don't flood the screen with it.
- **Bold + big numbers.** Hero metrics are large, heavy, rounded, monospaced digits, with `.contentTransition(.numericText())`.
- **Depth via hairlines + soft shadow,** not heavy borders. Cards = `Theme.card` with a 1px `white.opacity(0.06)` stroke (already in `.card()` / `.cardElevated()`).
- Vivid metric colors pop on black: calories=lime, protein=blue, carbs=amber, fat=violet, water=cyan.

## Native iOS quality bar (do all of these)
1. **Typography:** system SF (rounded design is applied globally). Use Dynamic Type ramps (`.largeTitle/.title/.headline/.subheadline/.caption`) + weights; never hardcode tiny px fonts except for true hero numerals. Numbers use `.monospacedDigit()`.
2. **Navigation:** use `NavigationStack` + `.navigationTitle(...)`. For list/detail screens use `.navigationBarTitleDisplayMode(.large)`; for the dashboard a custom large header is fine but keep the safe-area rhythm.
3. **Spacing rhythm:** use `Theme.Space.*` consistently (screen padding = `.padding(.horizontal)` ≈ 16, inter-card = `Theme.Space.md`). Generous vertical breathing room.
4. **Materials:** overlays/sheets/floating bars use `.ultraThinMaterial`. Sheets use `.presentationDetents` + `.presentationDragIndicator(.visible)`.
5. **Haptics:** on primary actions (save, log, add) fire `.sensoryFeedback(.success, trigger:)` or `.impact`. Use `UIImpactFeedbackGenerator` if needed.
6. **Motion:** one tasteful entrance/asymmetric reveal is fine; animate value changes with `.animation(.spring(response:0.5,dampingFraction:0.85), value:)`. Don't over-animate.
7. **Touch targets ≥ 44pt.** Buttons get `.buttonStyle(.primary)` (lime) or a clear secondary style.
8. **Empty/edge states** are designed, encouraging, never blank.
9. **Accessibility:** label icons; respect `.dynamicTypeSize` (don't truncate hero text harshly — allow it to scale).

## Theme tokens — USE ONLY THESE
Colors: `Theme.brand` `.brandDeep` `.brandSoft` `.positive` `.warning` `.info` `.calories` `.protein` `.carbs` `.fat` `.water` `.background` `.card` `.cardRaised` `.accent` `.accentSoft` `.primary` `.primarySoft` `.textPrimary` `.textSecondary` `.text` `.divider`
Gradients: `Theme.brandGradient` `.positiveGradient` ; `AngularGradient.brandSweep`
Spacing: `Theme.Space.xs/.sm/.md/.lg/.xl` (also flat aliases `Theme.spacingXS/S/M/L/XL`)
Radius: `Theme.Radius.sm/.md/.lg/.pill` (also `Theme.radiusS/M/L`, `Theme.cornerRadius`)
Fonts helpers: `Theme.title()` `Theme.largeTitle()` `Theme.number(_ size:)` (rounded, monospaced)
View modifiers: `.card(padding:)`, `.cardElevated(padding:radius:)`, `.softShadow()`
Components (already built): `ProgressRing(progress:lineWidth:color:track:)`, `GradientRing(progress:lineWidth:gradient:track:)`, `MacroBar(label:value:target:color:unit:)`, `StatTile(title:value:systemImage:tint:){trailing}`, `ConfidenceBadge(confidence:)`, `SectionHeader(title:)`, `.buttonStyle(.primary)`
If you need a new color/shade, DERIVE it from a token (e.g. `Theme.brand.opacity(0.15)`). Do NOT add tokens to Theme.

## Model + service contracts — USE THESE EXACT SIGNATURES
`@Bindable var profile: UserProfile` (passed into every tab view).
UserProfile fields: `name`, `currentDisplayName`, `sex`, `birthDate`, `ageYears`, `heightCm`, `activityLevel`, `pace`, `startWeightLbs`, `goalWeightLbs`, `unitSystem`, `coachName`, `dailyStepGoal: Int`, `stepsAdjustCalories: Bool`, `onboardingComplete`, reminder fields (`weighInReminderEnabled`, `weighInHour`, `mealRemindersEnabled`, `breakfastHour/lunchHour/dinnerHour`, `gymReminderEnabled`, `gymHour`, `gymWeekdays:[Int]`).
UserProfile methods (from UserProfile+Targets / StepsSupport):
- `dailyCalorieTarget(weightLbs:) -> Double`
- `calorieGoal(weightLbs:) -> NutritionMath.CalorieGoal` (`.dailyCalories`, `.wasClampedToFloor`)
- `macroTargets(weightLbs:) -> NutritionMath.Macros` (`.proteinG/.carbsG/.fatG`)
- `tdee(weightLbs:)`, `bmr(weightLbs:)`, `currentWeightLbs(latestLogged:)`, `waterTargetOz`
- `stepBonusCalories(weightLbs:steps:)`, `dailyTargetWithSteps(weightLbs:steps:)`
Models + initializers:
- `WeightEntry(date:weightLbs:note:source:healthKitUUID:)` — fields `date, weightLbs`
- `FoodEntry(date:mealType:name:servingDescription:quantity:calories:proteinG:carbsG:fatG:caloriesLow:caloriesHigh:source:confidence:notes:barcode:photoData:)` — accessor `.mealType`
- `WorkoutEntry(date:type:title:durationMinutes:caloriesBurned:notes:)`
- `WaterEntry(date:amountOz:)`
- `StepsEntry(date:count:)` — a day's step total
- `ChatMessage(role:content:createdAt:isSystemSeed:)` — `.isUser`, `.roleRaw`, `.content`, `.createdAt`
Enums: `BiologicalSex(.label)`, `ActivityLevel(.label,.detail,.multiplier,.baselineSteps)`, `GoalPace(.label,.subtitle,.weeklyRateLbs,.dailyDeficit)`, `UnitSystem(.weightUnit)`, `MealType(.label,.systemImage,.sortOrder,.title)`, `FoodSource`, `EstimateConfidence(.label)`, `WorkoutType(.label,.systemImage)`.
`TrendCalculator`: `.trend(_)->[TrendPoint{date,value}]`, `.currentTrend(_)->Double?`, `.ratePerWeek(_,windowDays:)->Double`, `.projectedGoalDate(_,goalLbs:)->Date?`, `.assess(ratePerWeek:currentWeightLbs:)->RateAssessment{.gainingOrFlat,.slow,.ideal,.fast}`.
SwiftData: `@Environment(\.modelContext)`, `@Query(sort:\Model.field)`. After mutations call `try? context.save()`.

## Hard rules
- Edit ONLY your assigned view file. Do NOT touch Theme*, Components, Polish, models, services, project.yml, the .xcodeproj, or other tabs' files.
- Do NOT run xcodebuild/xcodegen/the simulator. The integrator builds.
- iOS 18 SwiftUI only. Every symbol you use MUST be in this spec (verify against the real file you're given).
- Keep the existing view's `struct Name { @Bindable var profile: UserProfile }` signature unchanged so it still slots into the tab bar.
