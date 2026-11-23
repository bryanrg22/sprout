# Sprout lifecycle audit (read-only)

**Repo audited:** ``, HEAD `3fc5c6c` ("Bump to Sprout 2.1 (build 15)") **plus the uncommitted working tree** (17 modified tracked files, and untracked `Victoria/Services/AI/AITask.swift`, `AIRuntime.swift`, `Evals/`, `VictoriaEvals/`). Paths below are relative to that repo; a path starting with `App/`, `Features/`, `Models/` or `Services/` is under `Victoria/`.

**Method:** code reading only. Nothing was built, run, edited, or sent over the network. So:

- **VERIFIED BUG** = I read the full code path and it is wrong; a user-step reproduction is given. None of these were reproduced at runtime.
- **SUSPECTED** = depends on timing, OS behaviour, or server state I could not observe; the runtime check is stated.
- **OK** = read and holds.

---

## 0. The three things that matter most for the "re-onboard everyone on a fresh build" plan

1. **A fresh build does not re-onboard anyone.** Onboarding is shown only when no `UserProfile` with `onboardingComplete == true` exists (`Victoria/App/RootView.swift:58-72`). Installing a new TestFlight build over the old one keeps the SwiftData store, UserDefaults and Keychain, so users land straight in the main UI. Deleting the app and reinstalling wipes the local store, but the default `ModelContainer` mirrors to the private CloudKit database, so the old completed profile is expected to re-import and skip onboarding again. There is **no reset / start-over / delete-my-data control anywhere in Settings** (`Victoria/Features/Settings/SettingsView.swift`, searched for delete/reset/erase: only "Reset to default model" and "Reset to recommended water"). A true from-scratch re-onboard needs either an in-app reset (not present) or wiping each user's CloudKit private zone.
2. **Delete + reinstall is the most damaging path, not the cleanest.** Keychain survives (API keys, Google tokens) while UserDefaults does not (AI provider choice, Google client ID, buddy identity and link, all caches). Three verified breakages follow from that split (B9, B10, B11 below), plus a suspected duplicate-profile race (S1).
3. **Once an adaptive plan exists, the profile inputs stop driving the targets.** Goal direction, pace, activity level and weight changes do not move calories or protein until the plan is rebuilt, the Settings footer says the opposite, and the "goals changed" banner that is supposed to prompt the rebuild never clears (B2, B3).

---

## 1. App launch

| Step | Code | Finding |
|---|---|---|
| Schema | `Victoria/App/VictoriaApp.swift:11-40` | One flat `Schema` of 20 `@Model` types. **No `VersionedSchema`, no `SchemaMigrationPlan`** anywhere (grep over Victoria/Shared/VictoriaWidgets/VictoriaTests). Migration is entirely implicit lightweight migration. Every stored property has a default and there are no `.unique` attributes or relationships, so additive changes migrate and stay CloudKit-legal. A rename is a silent drop + add; a type change fails the open. |
| Container | `VictoriaApp.swift:42` | `ModelContainer(for: schema)` with the default configuration. With the entitlements in `Victoria/Victoria.entitlements` (app group `group.com.bryanram.victoria`, iCloud container `iCloud.com.bryanram.victoria`, CloudKit service) the default configuration puts the store in the app-group container and turns on private-database CloudKit mirroring. Nothing in the app observes CloudKit import/export events or de-duplicates after an import. |
| Open failure | `VictoriaApp.swift:43-51` | Logs "CRITICAL…" to Diagnostics, then falls back to an **in-memory** container via `try!`. No crash, the on-disk store is not deleted. The user sees onboarding, and everything entered disappears at the next launch. No visible warning. See S3. |
| DEBUG key injection | `VictoriaApp.swift:53-62` | `SPROUT_ANTHROPIC_KEY` env var, `#if DEBUG` only. OK. |
| Root decision | `RootView.swift:7,23,58-72` | `@Query private var profiles` is **unsorted**; `profile = profiles.first`. Widget gallery → demo deep link → `MainTabView` when `profile.onboardingComplete` → else `OnboardingView(existing: profile)`. |
| Launch task | `RootView.swift:74-89` | Runs once per cold launch: `DemoSeed.seedIfNeeded` (only with `--seed-demo` and no profile), `TravelSignal.checkNow()`, tracker refresh (30 days steps, 14 days sleep/workouts/vitals; HealthKit first, then Google), widget snapshot, and notification permission + scheduling **only if a completed profile already exists at that moment**. |
| Foreground / background | `RootView.swift:90-110` | `.active`: tracker refresh (7 days) + widget snapshot. `.background`: widget snapshot. `TravelSignal.checkNow()` and notification scheduling are **not** called here. |
| Plan → targets mirror | `RootView.swift:184-205` | `MainTabView.task` and `onChange(of: coachPlans.first?.updatedAt)` call `syncPlanTargets()`, which writes the newest plan's `calorieMin` / `calorieMax` / `proteinTarget` into `profile.calorieTargetOverride` / `calorieMaxOverride` / `proteinTargetOverride`, or **0 when there is no plan**. |
| Launch arguments | `DemoSeed.swift:7-31`, `RootView.swift:28-32`, `OnboardingView.swift:45-51`, `WhatsNewView.swift:45` | `--seed-demo`, `--demo-gain`, `--demo-fueled`, `--demo-tab`, `--demo-screen`, `--onboard-step` (DEBUG), `--whats-new`. Not reachable by a TestFlight user. OK. |

---

## 2. Onboarding

`Victoria/Features/Onboarding/OnboardingView.swift`. Twelve pages in a **swipeable** page-style `TabView` (`:96-98`, `:118-132`); the footer's Next button has no validation (`:1371-1407`).

| # | Page | Collected | Rules |
|---|---|---|---|
| 0 | fromBryan (`:230`) | nothing | Hardcoded personal note addressed to Victoria (`:36-42`), shown to every user. |
| 1 | welcome | nothing | |
| 2 | look (`:316`) | `themeChoice` cute/cool | default cute |
| 3 | goal (`:406`) | `direction` lose/maintain/gain | sets `pace` to the gentlest pace of that direction (`:445-449`). Direction itself is not stored, only `pace`. |
| 4 | education | nothing | |
| 5 | about (`:545`) | name, sex, birthday, height | birthday bounded 13–100 years (`:642-648`); height 48–84 in, whole inches (`:582`); name optional |
| 6 | weight (`:593`) | current weight, goal weight | both 70–500 lb steppers (`:679`), **defaults 150 → 140** (`:61-62`); a direction/goal mismatch only shows a warning (`:630-639`) |
| 7 | activity (`:689`) | activity level, pace | pace list filtered by direction |
| 8 | note (`:768`) | free text | optional |
| 9 | plan (`:823`) | nothing (preview) | preview built from a throwaway `UserProfile` (`:1493-1506`), so the numbers match the real math. Starts the closing-note generation (`:146`). |
| 10 | connect (`:1032`) | API key, Apple Health, location | all optional; key saved under `AIConfig.provider` (`:1203-1211`), no provider choice, no key verification |
| 11 | vitaNote (`:1241`) | nothing | "Start my journey" → `finish()` |

**`finish()` (`:1559-1596`) writes:**

- `UserProfile` (new unless `existing` is non-nil): name ("friend" if blank), sex, birthDate, heightCm, `startWeightLbs = currentWeight`, `goalWeightLbs`, activityLevel, pace, themeStyle, companionAvatar (cool → bryan, cute → victoria), onboardingNote, `dailyStepGoal = 8000`, `waterGoalOzOverride = clamp(½ bodyweight, 64…100)`, `onboardingComplete = true`.
- One `WeightEntry(weightLbs: currentWeight)` dated now.
- UserDefaults `whatsnew.lastSeenVersion`.
- Keychain: any typed-but-unsaved key, under the active provider.

**What can be skipped and what it leaves behind:**

| Skip | Later state |
|---|---|
| Everything (swipe to the end, tap Start) | Profile "friend", female, 25, 5′5″, 150 lb → 140 lb, lightly active, relaxed loss. A real 150-lb weigh-in is recorded and **cannot be deleted or edited later** (see B21). OK by design, but the default weigh-in is the one piece that cannot be corrected. |
| Name | "friend" everywhere (greetings, buddy display name, widget). Editable in Settings. OK. |
| Goal weight mismatch | Persisted as-is. Settings footer and Vita flag it later (`SettingsView.swift:247-252`). OK. |
| API key | All AI features use template fallbacks; Today shows `FinishSetupCard`. OK apart from B15. |
| Apple Health | No steps/sleep/vitals. OK. |
| Plan intake | Not part of onboarding at all. It is the "Build my plan" card on Progress (`Features/Plan/PlanCard.swift:40-61`). Without it targets are the computed ones. OK. |

**Not collected in onboarding:** unit system (imperial only), reminder times (defaults: weigh-in 8, meals 9/13/19, all on), AI provider, home gym.

Onboarding findings are B12, B13, B14, B9 and S1 in the lists below.

---

## 3. Derived targets

**Pure math** (`Victoria/Services/NutritionMath.swift`, tested in `VictoriaTests/NutritionMathTests.swift`): Mifflin-St Jeor BMR (`:17-23`), TDEE = BMR × activity multiplier (`:26-28`), calorie goal = TDEE + signed pace adjustment (±500 kcal per lb/week), floored at 1200 (female) / 1500 (male) for loss and capped at +500 for gain (`:39-63`), macros = 1.8 g/kg protein, 0.8 g/kg fat, carbs fill the rest (`:68-77`), water = 0.5 oz per lb (`:97-99`).

**Profile composition** (`Victoria/Services/UserProfile+Targets.swift`, tested in `VictoriaTests/ProfileTargetsTests.swift`):

- `dailyCalorieTarget(weightLbs:)` (`:45-53`): if `calorieTargetOverride` is set (0 < x < 20,000) return `max(override, safe floor)`; otherwise the computed goal.
- `macroTargets` (`:55-64`): computed, unless `proteinTargetOverride > 0`, which pins protein and refills carbs.
- `calorieGoalRange` (`:80-93`): gain → `(target, ∞)`; lose/maintain → `(target, calorieMaxOverride if sane else target + 150)`.
- `waterTargetOz` (`:121-124`): override if > 0, else 0.5 × **start** weight.
- Step goal: stored `dailyStepGoal`, never derived. Step bonus (`Services/StepsSupport.swift:21-40`) only when `stepsAdjustCalories` is on.

Every consumer recomputes on read with the weight basis "smoothed trend, else start weight, else 150": Dashboard (`DashboardView.swift:39-61`), Nutrients (`FoodLogView.swift:92`), Settings (`SettingsView.swift:29-45`), widget writer (`WidgetDataWriter.swift:26-33`), buddy snapshot (`BuddyAutoPublisher.swift:56-68`), coach context (`CoachContext.swift:282-316`), achievements (`AchievementCatalog.swift:172-177`), weekly reflection, smart suggestions, progress recap. Exception: the companion card uses start weight only (`CompanionCard.swift:70-74`).

**Propagation matrix** (does a change in the input reach the dependent?):

| Input changed | No plan | Plan active |
|---|---|---|
| New weigh-in (trend) | Calories/macros move everywhere on next render. Water does not (start weight; and onboarding always sets an explicit water override). Companion card does not (start weight). | **No effect** on calories or protein. Carbs/fat still track weight. |
| Goal direction | Calories move; range shape flips. | **Calories and protein unchanged** (old plan's floor). Only the range shape flips: a loss plan's floor becomes a single "eat at least" number for gain. `goalsChanged` flag set. |
| Pace within a direction | Calories move. | **No effect, and no flag.** |
| Activity level | Calories move. | **No effect, and no flag.** |
| Sex | BMR and floor move. | Only the safe floor clamp moves. |
| Goal weight | Chart line, ETA, buddy snapshot, widget. Never calories. | Same, plus flag from Settings (`SettingsView.swift:197-199`) but **not** from Vita's `set_weight_goal` (`CoachTools.swift:2188-2194`). |
| Start weight | Chart "Start" line, fallback basis, water default, **companion card targets**, Vita's direction check. | Same minus the companion targets. |

Dependents that are cached and do not see a same-day change: today's checklist (`ChecklistCard.swift:427-453`, key = profile id + day), daily brief (`DailyBriefService.swift:139-169`, key = day), progress recap (`ProgressSummaryCard.swift:247-253`, key = UTC day + override values only), smart food picks (`SmartSuggestionsView.swift:356-358`), coach prompt chips (`CoachPromptService.swift:325-334`, 3-day bucket). The widget and buddy snapshot are rewritten on foreground/background and on logging, so they do follow.

---

## 4. Situation changes

| Situation | Code path | Updates | Does not update |
|---|---|---|---|
| **Goal direction change** | Settings picker `SettingsView.swift:155-166`, `:186-199`; Vita `set_goal_direction` `CoachTools.swift:2264-2295` | `profile.pace` (snapped to the gentlest pace of the new direction); `plan.goalsChanged.<planId>` flag; Vita is told the plan and goal weight may be stale | Plan numbers and therefore all targets (B2); goal weight; today's cached checklist / brief / recap (B19); the flag is never cleared (B3) |
| **Weight goal reached** | none | nothing | Everything: pace keeps its deficit/surplus, no prompt to switch to maintain, no achievement. Widget "to go" just disappears (`Shared/WidgetSnapshot.swift:60`). (B23) |
| **Start-weight edit** | Settings stepper `SettingsView.swift:225-233`; Vita `set_start_weight` `CoachTools.swift:2196-2202` | `startWeightLbs` | The onboarding `WeightEntry` that carried the wrong value stays in the trend and cannot be removed (B21). Vita's tool text says targets do not change, but companion-card targets do when no plan is active (B22). |
| **Gap / comeback** | `StreakCalculator.daysSinceLastLog` (`StreakCalculator.swift:46-57`); Vita note at ≥ 4 days (`CoachContext.swift:443-451`); daily brief "gapReturn" at 4–6 days (`DailyBriefService.swift:70-74`); `WelcomeBackCard` at ≥ 7 days (`WelcomeBackCard.swift:30`) | Framing only; streak restarts at 0/1 | OK overall. After a gap with one new weigh-in, `ratePerWeek` falls back to the whole history (`TrendCalculator.swift:41-43`), so "this week" trend copy can describe months (S11). |
| **Travel / timezone** | `TravelSignal.checkNow()` `TravelSignal.swift:58-73`, called only at `RootView.swift:79` | Records shift ≥ 2 h (zone id change), 2–5 day window; feeds Vita (`CoachContext.swift:396-398`) and the brief (`DailyBriefCard.swift:89-92`). DST is ignored correctly (`:42-44`, tested). | Not checked on foreground (B16). All day bucketing uses the current calendar, so history re-buckets (B8, S8). |
| **Plan rebuild** | `PlanIntakeView.swift:219-248` → `PlanService.generate` `PlanService.swift:18-87` | Rebuilds the same `CoachPlan` row in place (`:65-82`), overwrites `profile.onboardingNote` with the model's `about_you` (`:57-58`), research brief cached 30 days by direction + 10-lb goal band (`ResearchCache.swift:23-51`); targets re-mirror via `updatedAt` | `goalsChanged` flag (B3). Light review (`PlanService.review`, `:99-157`) is web-free by design. |
| **Add a tracker** | Apple Health: `HealthSettingsView.swift:122-137`; Google Health: `GoogleHealthSettingsView.swift`, `GoogleHealthAuth.swift` | Steps/sleep/workouts/vitals import on launch and foreground through shared merge functions | Weight: import is a manual button only and writes never happen (B13) |
| **Remove a tracker** | `GoogleHealthAuth.disconnect()` `:84-97` | Tokens cleared, best-effort revoke | Already-imported rows stay (reasonable). Refresh-token death is handled as a silent disconnect (S7). |
| **Switch AI provider** | `AIProviderSettingsView.swift:46-49` → `AIConfig.provider` | Persisted immediately; every feature goes through `AIClient.make()/makeFull()`; chat history is plain text so it carries over | If the new provider has no key, features fall back and the coach banner explains (`CoachView.swift:856-863`). OK. |
| **Lose the API key** | `AIProviderSettingsView.removeKey` `:239-244`; gates on `AIConfig.hasActiveKey` | Fallback templates everywhere; plan review/build show an error | `FinishSetupCard` does not reappear until relaunch (B15). An invalid or revoked key (as opposed to a missing one) still counts as "has key": features fail per call and fall back silently, only chat and plan surface an error. |
| **Reinstall with iCloud restore** | no dedicated code | Local store is recreated empty; CloudKit import refills it at some later point | See S1 (duplicate profile), B9, B10, B11, and notifications not rescheduled until the next cold launch (B12). |
| **TestFlight expiry, new build installed over data** | no app logic | Store, UserDefaults, Keychain, permissions all persist; implicit lightweight migration; "What's New" shows only when `CFBundleShortVersionString` changes (`WhatsNewView.swift:49-53`) | No onboarding. If the store fails to open: S3. |
| **CoachMemory / profileNotes** | `CoachMemory.fetchOrCreate` `Models/CoachMemory.swift:74-97`; Settings binding `SettingsView.swift:396-406`; plan intake fold `PlanIntakeView.swift:187-198` | Seeded once from `onboardingNote`; later plan builds rewrite `onboardingNote` but not the seeded copy | With two rows the accessor alternates between them (S2). |

---

## 5. Date and time

"Today" is always `Calendar.current` evaluated at render or call time (`isDateInToday`, `startOfDay(for: .now)`). There is **no day-change observer anywhere** (no `NSCalendarDayChanged`, no `significantTimeChangeNotification`, no `TimelineView`; grep over all three source roots).

| Spot | Code | Class |
|---|---|---|
| Nutrients tab keeps yesterday selected after an overnight resume | `FoodLogView.swift:43`, `:155-158` | VERIFIED (B1) |
| Nutrients-tab entries are stamped at local midnight of the selected day, not the time of logging | `FoodLogView.swift:155-158`, `AddFoodSheet.swift:394`, `RecentFoodsSheet.swift:451` | VERIFIED (B8) |
| Widget never compares the snapshot's date to today | `Shared/WidgetSnapshot.swift:9` (`updated` is written, never read), `VictoriaWidgets/SnapshotProvider.swift:23-27` | VERIFIED (B5) |
| Progress recap day key is formatted with `.iso8601`, whose default time zone is GMT | `ProgressSummaryCard.swift:252` | VERIFIED from the API default, not run (B19) |
| Travel check only at cold launch | `RootView.swift:79` | VERIFIED (B16) |
| Dashboard "today" after an overnight resume when no query changes | `DashboardView.swift:33-63` | SUSPECTED (S5) |
| Start-of-day keyed rows after a timezone change (`StepsEntry.date`, `SleepEntry.date`, `VitalsEntry.date`, `ChecklistItem.day`) | `HealthKitSteps.swift:93-96`, `ChecklistItem.swift:38`, `ChecklistCard.swift:60` | SUSPECTED (S8) |
| Streak walk-back | `StreakCalculator.swift:61-76` uses `date(byAdding: .day)` from start of day | OK across DST |
| Trend math uses `/ 86_400` on real timestamps | `TrendCalculator.swift:23,41,44` | OK (elapsed time, not calendar days) |
| Recommendation snooze `snoozeDays * 86_400` | `RecommendationCard.swift:42-43` | OK (duration) |
| Weekly reflection gate keyed by start of week in current calendar | `WeeklyReflection.swift:264-274` | OK; may re-fire once after crossing zones |
| Coach prompt bucket | `CoachPromptService.swift:317-320` | OK (UTC days by design) |
| Daily brief cache | `DailyBriefService.swift:141-150`, `DailyBriefCard.swift:60` | OK for rollover; one global key, not per profile (B24) |
| Age | `UserProfile.swift:147-149` | OK |

Streak definitions in use: `StreakCalculator` (food, water, manual weigh-ins) for Dashboard, widget, buddy, brief, recap; Vita's wrapper drops water (B17); Achievements use a different definition that includes imported steps and all weights (B6).

---

## 6. Persistence inventory

### SwiftData models (all flat, no relationships, all properties defaulted, all CloudKit-mirrored)

| Model | Fields |
|---|---|
| `UserProfile` (`Models/UserProfile.swift`) | id, name, sexRaw, birthDate, heightCm, activityLevelRaw, paceRaw, startWeightLbs, goalWeightLbs, unitSystemRaw, coachName, dailyStepGoal, stepsAdjustCalories, onboardingComplete, createdAt, onboardingNote, waterGoalOzOverride, waterContainerOz, waterContainerLabel, waterUnitRaw, calorieTargetOverride, proteinTargetOverride, calorieMaxOverride, shareFullStatsWithBuddy, companionName, companionAvatarRaw, lastAlejandroGagDate, themeStyleRaw, weighInReminderEnabled, weighInHour, mealRemindersEnabled, breakfastHour, lunchHour, dinnerHour, gymReminderEnabled, gymHour, gymWeekdays, aiModelFood, aiModelChat (both unused), homeGymRaw |
| `WeightEntry` | id, date, weightLbs, note, source, healthKitUUID, createdAt |
| `FoodEntry` | id, date, mealTypeRaw, name, servingDescription, quantity, calories, proteinG, carbsG, fatG, caloriesLow, caloriesHigh, sourceRaw, confidenceRaw, notes, barcode, photoData (external storage), additionalPhotoData, isFavorite, createdAt |
| `WaterEntry` | id, date, amountOz, createdAt |
| `StepsEntry` | id, date (start of day), count, createdAt |
| `SleepEntry` | id, date (wake morning start of day), asleepMinutes, inBedMinutes, deepMinutes, remMinutes, coreMinutes, awakeMinutes, createdAt |
| `DetectedWorkout` | id, healthKitUUID (dedup key), date, activity, durationMinutes, caloriesBurned, sourceName, createdAt |
| `VitalsEntry` | id, date (start of day), restingHeartRate, hrvMs, createdAt |
| `WorkoutEntry` (legacy) | id, date, typeRaw, title, durationMinutes, caloriesBurned, focusRaw, notes, createdAt |
| `WorkoutSession` | id, date, typeRaw, focusesRaw, durationMinutes, notes |
| `ExerciseEntry` | id, sessionID (flat link to session), date, machineKey, displayName, iconName, weightLbs, reps, sets |
| `ChatMessage` | id, roleRaw, content, imageData (external storage), createdAt, isSystemSeed, decisionSummary, decisionAccepted |
| `CoachMemory` (singleton by convention) | id, profileNotes, conversationSummary, summarizedThroughDate, updatedAt |
| `CoachPlan` (singleton by convention) | id, headline, assessment, strategy, calorieMin, calorieMax, proteinTarget, goalSummary, timeframe, researchNotes, dataPointsAtBuild, insightsJSON, changelogJSON, createdAt, updatedAt |
| `AchievementUnlock` | achievementID, unlockedAt |
| `InsightShown` | insightID, shownAt |
| `ChecklistItem` | title, systemIcon, day (start of day), done, sortOrder |
| `BuddyLink` | myUserID, buddyUserID, buddyDisplayName, pairingCode, statusRaw, createdAt |
| `Nudge` | id, fromUserID, toUserID, kindRaw, text, createdAt, isRead |
| `BuddySnapshot` | ownerUserID, displayName, dayStreak, characterMoodRaw, loggedToday, lastActive, stepsToday, stepGoal, waterToday, waterGoal, workedOutToday, workoutSummary, sharesFullData, trendWeightLbs, goalWeightLbs, weeklyRateLbs, caloriesEaten, calorieTarget, proteinEaten, proteinTarget, carbsEaten, carbTarget, fatEaten, fatTarget, todayFoods |

### UserDefaults (standard suite unless noted)

| Key | Owner |
|---|---|
| `ai_provider`, `ai_base_url`, `ai_model_<provider>_<coach\|insight\|plan>` | `Services/AI/AIConfig.swift:85,94,114-116` |
| `googleHealth.clientID`, `googleHealth.lastSyncAt` | `GoogleHealthAuth.swift:18`, `GoogleHealthSync.swift:20` |
| `travel.zoneID`, `travel.offsetSec`, `travel.shiftHours`, `travel.shiftAt` | `TravelSignal.swift:24-27` |
| `dailyBrief.v1` | `DailyBriefService.swift:139` |
| `researchCache.<dir>.band<n>` | `ResearchCache.swift:20-31` |
| `plan.goalsChanged.<planId>` | `Features/Plan/PlanGoalsFlag.swift:12` |
| `whatsnew.lastSeenVersion` | `WhatsNewView.swift:37` |
| `weeklyReflection.lastShownWeek` | `WeeklyReflection.swift:248` |
| `welcomeBack.dismissedForLastLogDay` | `WelcomeBackCard.swift:27` |
| `widgetPromo.dismissed`, `runningAppRec.dismissed` (`@AppStorage`) | `WidgetPromoCard.swift:13`, `RunningAppCard.swift:15` |
| `victoria.checkIn.enabled`, `victoria.checkIn.hour` | `NotificationService.swift:40-41` |
| `vita.rec.snoozed.<id>` | `RecommendationCard.swift:37` |
| `vita.checklist.<profileId>.<yyyy-MM-dd>` (one per day, never pruned) | `ChecklistCard.swift:427-430` |
| `vita.foodpicks.<user>.<yyyy-MM-dd>.<slot>` (never pruned) | `SmartSuggestionsView.swift:356-358` |
| `vita.prompts.<userId>.<bucket>` (never pruned, by its own comment) | `CoachPromptService.swift:332-334` |
| `insightPhrased.<id>.<day>` (never pruned) | `InsightCard.swift:67-70` |
| `progress.summary.<UTC day>.<target signature>` (never pruned) | `ProgressSummaryCard.swift:251-253` |
| `buddyMyUserID`, `buddy.myPairingCode.<id>`, `buddy.lastPublishOK.<id>`, `buddy.panda.lastFed.<id>` | `BuddyViewModel.swift:22,34,97,162` |
| `buddy.ck.linkedTo.<id>`, `buddy.ck.subscribed.v2.<id>`, `buddy.ck.snapshotSub.<id>.from.<buddy>` | `CloudKitSyncService.swift:177,285,323` |
| `buddy.lastActiveDay`, `buddy.milestone.<id>.<milestone>.<day>` | `BuddyMilestones.swift:44,87-89` |
| `buddy.mock.*` (simulator mock only) | `LocalMockSyncService.swift:45-50` |
| App-group suite `group.com.bryanram.victoria`: `widget_snapshot_v1` | `Shared/WidgetSnapshot.swift:119-122` |

Also on disk: `diagnostics.log` in the app-group container or Caches (`Services/Diagnostics.swift:28-31`).

### Keychain (service `com.bryanram.victoria`, generic password, `kSecAttrAccessibleAfterFirstUnlock`)

| Account | Content |
|---|---|
| `anthropic_api_key` | Anthropic key (`KeychainStore.swift:15-19`) |
| `openai_api_key` | OpenAI key |
| `google_health_tokens` | JSON of access token, refresh token, expiry (`GoogleHealthAuth.swift:19,76-82`) |

### What survives what

| Event | SwiftData store | UserDefaults | Keychain | Permissions |
|---|---|---|---|---|
| New build installed over the old one (including after TestFlight expiry) | kept, lightweight-migrated | kept | kept | kept |
| Local store files deleted (app kept) | gone locally; on a device signed in to iCloud the mirror is expected to re-import (S14) | kept | kept | kept |
| App deleted and reinstalled | local gone; CloudKit re-import expected | **gone** (both suites) | **kept** | Health and notifications reset |
| Store fails to open | untouched on disk, app runs in memory | kept | kept | kept |

---

## 7. Expiry and time-bomb logic

No date-based expiry, build-date check, receipt check or TestFlight detection exists in the app (grep for expire / receipt / TestFlight / hardcoded 20xx dates / kill switch / minimum version: only comments and tool-description examples). The time limits that do apply are external:

- **TestFlight 90-day build expiry** (`TESTFLIGHT.md:77-78`). Enforced by the OS; the app has no say and no data is touched.
- **Google OAuth refresh tokens in Testing mode** can expire after 7 days (`GOOGLE_HEALTH_SETUP.md:21,54`; handled as a silent disconnect at `GoogleHealthAuth.swift:271-276`). S7.
- **Hardcoded model IDs** (`AIConfig.swift:45-76`: `claude-sonnet-5`, `claude-opus-4-8`, `claude-haiku-4-5-20251001`, `gpt-5.6-terra`, `gpt-5.6-sol`, `gpt-4.1-mini`, plus `OpenAIClient.researchModel`). No remote config. S6.
- `ResearchCache` 30-day TTL (`ResearchCache.swift:19,38-42`) and the recommendation snooze are ordinary caches. OK.

---

## 8. Verified bugs, ranked by what a real user hits

Each was established by reading the code path end to end. None was reproduced on a device or simulator.

### B1. Nutrients tab logs food to yesterday after the app sits in memory overnight
- **Code:** `Features/Food/FoodLogView.swift:43` (`@State private var selectedDay = startOfDay(for: .now)`, set once), `:155-158` (every add flow receives `date: selectedDay`). The file has no scenePhase or day-change handling.
- **Repro:** Monday: open the Nutrients tab once. Leave the app in the background. Tuesday morning: reopen (not a cold launch), go to Nutrients, add a meal. The header reads "Yesterday", the meal is saved to Monday, and Today's ring does not move.

### B2. With an adaptive plan, changing your goal does not change your targets, and Settings says it does
- **Code:** `Services/UserProfile+Targets.swift:49-51` (override wins), `App/RootView.swift:197-205` (override = plan numbers), `Features/Settings/SettingsView.swift:253` ("Changing any of these updates your daily targets right away."), `:204-210` and `:286-292` (pace and activity pickers set no flag).
- **Repro:** Build a plan on a loss goal (say 1,500–1,700 kcal). Settings → Your goals → switch to Gain. Daily targets still show 1,500 kcal and the plan's protein; Today now shows 1,500 as a single "at least" number for a gain goal (`UserProfile+Targets.swift:83-84`). Changing pace or activity level changes nothing and shows no notice at all.

### B3. "Your goals changed since this plan was built" never goes away
- **Code:** `Features/Plan/PlanGoalsFlag.swift:12-20` (flag is only ever set to true; the comment at `:5` assumes a rebuild mints a new plan id), `Services/PlanService.swift:65-82` (rebuild mutates the existing row, same `id`).
- **Repro:** With a plan, change goal weight in Settings. Progress shows the warning. Tap "Rebuild with fresh research" and finish. The warning is still there, permanently.

### B4. A protein goal set through Vita without a plan is erased at the next launch
- **Code:** `Features/Coach/CoachTools.swift:2390-2396` (no plan → writes only `proteinTargetOverride`), `App/RootView.swift:186` and `:201,204` (`syncPlanTargets` resets the override to the plan's value, which is 0 with no plan).
- **Repro:** No adaptive plan. Ask Vita to set protein to 150 g and confirm. Force-quit and relaunch (or switch theme, which rebuilds the tab view). Protein target is back to the computed value.

### B5. Home-screen widgets show yesterday as today, and the weight widget is loss-only
- **Code:** `Shared/WidgetSnapshot.swift:9` (`updated` stored, never read in `Shared/WidgetViews.swift` or `VictoriaWidgets/`), `VictoriaWidgets/SnapshotProvider.swift:23-27` (re-reads the same snapshot every 30 minutes); `Shared/WidgetViews.swift:165-167` and `WidgetSnapshot.swift:60-61` (rate coloured positive only when losing; "to go" only when trend is above goal); `WidgetSnapshot.swift:64-76,124-128` (placeholder "Victoria", 153.8 lb, 28-day streak when no snapshot exists).
- **Repro:** Log food Monday evening, do not open the app Tuesday: the widget shows Monday's calories, water, steps and streak all day Tuesday. On a gain profile gaining on plan: the trend widget shows the rate in the warning colour and never shows distance to goal. On a fresh install, add the widget before finishing onboarding: it shows the Victoria sample data.

### B6. Streak achievements unlock from auto-imported Apple Health steps
- **Code:** `Features/Achievements/AchievementCatalog.swift:204-210` (logged days = food ∪ all weights ∪ steps), `:259,261` (`consistency_7`, `self_kindness` at 14), `App/RootView.swift:83` (30-day step backfill on launch). `Services/StreakCalculator.swift:8-12` documents this exact mistake as a fixed bug for the main streak.
- **Repro:** New user grants Apple Health with a normal step history, opens Achievements on day one: the 7-day and 14-day consistency badges unlock, permanently.

### B7. "Switch to kg" relabels every weight without converting, then corrupts the math
- **Code:** `CoachTools.swift:2242-2248` (`set_units`), `:507-533`, `:1833-1846`, `:2179-2186` (weigh-in stored as the typed number), `Features/Weight/WeightView.swift:44-47` (the code itself notes kg conversion is a known gap), `UserProfile+Targets.swift:24-29` (math always treats the stored number as pounds). There is no units picker in Settings; Vita's tool is the only way in.
- **Repro:** Ask Vita to switch to metric. The app now shows "158 kg". Log "72" as a weigh-in: it is stored as 72 lb, the trend drops sharply, and with no plan the calorie target drops with it, down to the safe floor as more kg values are logged. Weights under 50 kg are rejected (`CoachTools.swift:100`).

### B8. Flying west moves food history a day earlier
- **Code:** `FoodLogView.swift:155-158`, `AddFoodSheet.swift:394`, `RecentFoodsSheet.swift:451` (entries from the Nutrients tab are stamped at local midnight of the selected day), and every reader buckets with the current calendar.
- **Repro:** Log lunch in New York from the Nutrients tab, then let the phone change to Chicago or Los Angeles time. Midnight Eastern is the previous evening further west, so that lunch and every earlier Nutrients-tab entry appear under the previous day. Today's ring empties and per-day totals shift. Eastward travel is unaffected. Entries logged through Vita use the real time and do not move.

### B9. Reinstall for an OpenAI user: the pasted key goes into the Anthropic slot
- **Code:** `Services/AI/AIConfig.swift:98-104` (provider lives in UserDefaults, default Anthropic), `OnboardingView.swift:87,1203-1206,1592-1594` and `Features/Dashboard/FinishSetupCard.swift:91-96` (save under the active provider, no provider choice, no verification).
- **Repro:** Use OpenAI as provider. Delete and reinstall. The OpenAI key is still in the Keychain but the provider is Anthropic again, so onboarding and Today both say no key. Paste the OpenAI key there: it is stored as the Anthropic key and every AI call fails authentication. (The coach tab banner does explain the mismatch, `CoachView.swift:856-863`; the two paste fields do not.)

### B10. Reinstall with Google Health connected: shows connected, cannot refresh
- **Code:** `Services/GoogleHealth/GoogleHealthAuth.swift:31-41` (client ID in UserDefaults), `:61-73` (tokens in Keychain), `:66` (`isConnected = tokens != nil`), `:258` (refresh needs the client ID, else throws `notConnected` without clearing tokens).
- **Repro:** Connect Fitbit via Google Health, delete and reinstall. Settings shows connected; once the hour-long access token lapses every sync fails. The fix is Disconnect, re-enter the client ID, sign in again.

### B11. Reinstall gives the user a new buddy identity and strands the partner
- **Code:** `Features/Buddy/Views/BuddyViewModel.swift:22-32` (`buddyMyUserID` minted into UserDefaults), `Features/Buddy/Services/CloudKitSyncService.swift:165,177` (link stored in UserDefaults).
- **Repro:** Paired users; one deletes and reinstalls. That phone has a new id and no link. The partner's phone stays linked to the old id, which never publishes again, so it shows a frozen snapshot with no explanation. Both must unlink and pair again.

### B12. No reminders (and no permission prompt) until the second launch
- **Code:** `App/RootView.swift:74-89` (`NotificationService.refreshOnLaunch` runs only in the root `.task`, only if a completed profile already exists); other call site is the Reminders settings screen (`RemindersSettingsView.swift:156-157`).
- **Repro:** Fresh install, finish onboarding, keep using the app. Weigh-in and meal reminders are on by default in the profile but nothing is scheduled and the permission prompt does not appear until the app is cold-launched again. Same after a reinstall when the profile arrives from iCloud after launch.

### B13. Apple Health weight sync is promised but not wired
- **Code:** `Services/HealthKitService.swift:108` (`saveWeight` has no callers), `:159` (`importRecent` is called only from the manual button at `Features/Settings/HealthSettingsView.swift:152`), `project.yml:71-72` (usage strings say Sprout reads weight and saves weigh-ins), `OnboardingView.swift:1100` ("I'll keep your trend in sync").
- **Repro:** Connect Apple Health in onboarding, log weigh-ins in Sprout: nothing appears in Health. Weigh on a smart scale: nothing appears in Sprout until Settings → Apple Health → import is tapped by hand. The app also requests write access it never uses.

### B14. Vita's onboarding closing note is always the template on a first install
- **Code:** `OnboardingView.swift:146` (generation starts on the plan page), `:1314-1316` (runs once), `OnboardingCoachMessage.swift:33` (no key → template). The key is entered one page later.
- **Repro:** Fresh install, paste a valid key on the connect page: the final note is still the canned text.

### B15. "Almost there — connect Vita" card does not track the key state
- **Code:** `FinishSetupCard.swift:13` (`@State hasKey` read once).
- **Repro:** Skip the key in onboarding, then add it in Settings → AI Provider: the card stays on Today until relaunch. Conversely, remove the key in Settings: the card does not come back until relaunch.

### B16. Travel detection only runs on a cold launch
- **Code:** `App/RootView.swift:79` is the only call; `Services/TravelSignal.swift:55` says "once per launch/foreground".
- **Repro:** Background the app, fly across several time zones, reopen it from memory: no travel framing. When the app is eventually cold-launched, the shift is stamped with that later time, so the adjustment window starts late.

### B17. Vita reports a different streak than the Today header
- **Code:** `Features/Coach/CoachContext.swift:429,460-469` (water not passed, although `summary` receives it at `:269`).
- **Repro:** On a day where the only log is water, Today counts the day; Vita is told "nothing logged today yet".

### B18. Settings shows the wrong height for values not entered in whole inches
- **Code:** `SettingsView.swift:258-263` (feet from the truncated inches, inches from the rounded inches).
- **Repro:** Tell Vita your height is 182 cm: Settings shows 5′0″ (182 cm). 152 cm shows 4′0″. Heights from the onboarding stepper are unaffected.

### B19. The Progress recap cache rolls over at UTC midnight and ignores goal changes
- **Code:** `Features/Weight/ProgressSummaryCard.swift:247-253` (`.iso8601` day, whose documented default time zone is GMT, not checked at runtime; signature contains only the override numbers, step goal and water goal).
- **Repro:** In Pacific time the recap regenerates in the late afternoon rather than at midnight. Change goal direction or pace with no plan: the recap keeps its old framing until the key changes.

### B20. Water "Reset to recommended (N)" shows one number and applies another
- **Code:** `SettingsView.swift:480` (label from trend weight) versus `UserProfile+Targets.swift:121-124` (result from start weight, unclamped; onboarding clamps to 64–100 at `OnboardingView.swift:1510-1512`).
- **Repro:** Start at 200 lb, trend now 180 lb: the button says 90 oz, tapping it sets 100 oz.

### B21. Weigh-ins cannot be edited or deleted
- **Code:** `Features/Weight/WeightView.swift:434-438` is the only weigh-in write in the UI; the only delete is Vita's immediate Undo (`CoachTools.swift:2186`). Onboarding always inserts one (`OnboardingView.swift:1587`).
- **Repro:** Accept the default 150 lb in onboarding (or mistype a weigh-in). Correcting "Starting weight" in Settings moves the chart line but the 150-lb point stays in the trend, the rate, and (with no plan) the calorie math.

### B22. Start weight is used as "current weight" in two places
- **Code:** `Features/Companion/CompanionCard.swift:70-74` (companion targets), `CoachTools.swift:1861,2497-2499` (goal-direction check). Also `CoachTools.swift:2188-2194` does not mark the plan stale although `PlanGoalsFlag.swift:7-8` says both surfaces do.
- **Repro:** Lose user, start 180, now 150, no plan: the companion's "enough food" threshold is computed at 180 lb and the ring's at 150 lb, roughly 190 kcal apart at light activity unless the safe floor clamps both. Ask Vita to set a goal of 160: accepted, although it is above the current weight.

### B23. Reaching the goal weight changes nothing
- **Code:** no handler exists (search for goal-reached logic found none); `GoalPace` stays as set.
- **Effect:** The deficit or surplus continues indefinitely with no prompt to move to maintenance.

### B24. Smaller items
- Stale "More → AI" directions; that tab no longer exists (`CoachView.swift:860,862`, `AIConfig.swift:175`, `PlanIntakeView.swift:239`).
- Daily check-in notification copy is fixed at scheduling time, so it does not rotate by weekday as the comment says (`NotificationService.swift:187-200`).
- Per-day UserDefaults keys are never pruned (list in section 6).
- The first onboarding page is a hardcoded personal note to Victoria shown to every user (`OnboardingView.swift:36-42`).
- Prompts say "she/her" for every user (`OnboardingCoachMessage.swift:79-81`, `PlanService.swift:270-271,471-486`, `DailyBriefService.swift:189`), against the project's variant-aware rule.
- The daily brief cache is one global key, not per profile (`DailyBriefService.swift:139`).
- `UserProfile.aiModelFood` / `aiModelChat` are dead fields (`UserProfile.swift:102-103`).

---

## 9. Suspected, with the runtime check for each

| # | Suspicion | Why | Check |
|---|---|---|---|
| S1 | **Duplicate `UserProfile` after reinstall** | `finish()` inserts a new profile when none is local (`OnboardingView.swift:1562,1586`); nothing de-duplicates after a CloudKit import; five views read an unsorted `profiles.first` (`RootView.swift:7,23`, `WorkoutsView.swift:18`, `WorkoutDayDetail.swift:13`, `BuddyHomeView.swift:34`, `BuddyAutoPublisher.swift:156`). It also adds a new onboarding weigh-in to the restored history, and a newer `createdAt` would hide earlier days in the Nutrients navigator (`FoodLogView.swift:59`). If the import lands first, onboarding is simply skipped. | Reinstall on a device with iCloud data, finish onboarding in airplane mode, go online, count profiles (`sqlite3` on the store) and watch which one the UI uses across relaunches. |
| S2 | `CoachMemory` alternates between two rows | `fetchOrCreate` takes the row with the **oldest** `updatedAt` (`CoachMemory.swift:76-81`); each write makes the other row the oldest. Needs two rows, which S1's conditions (or opening Settings / chat before the import) can create. | Create two rows, save a note twice, see which row each write lands in. |
| S3 | Store-open failure is silent, and the fallback may crash | In-memory fallback has no UI signal (`VictoriaApp.swift:43-51`). The fallback config keeps the default CloudKit setting, so if the failure was a CloudKit schema validation error the `try!` at `:50` would fail the same way. | Force a failing open (incompatible model change on an existing store) in a debug build and observe. |
| S4 | CloudKit Production schema may not cover all 20 record types | Release/TestFlight builds use Production; newer models (sleep, vitals, detected workouts, workout sessions, exercises, plan, memory, checklist) must be deployed there or their rows never mirror or restore. The repo's own comments describe this failure for the buddy records (`CloudKitSyncService.swift:40-44`). | CloudKit Console → Production → confirm a `CD_` record type and all fields for each model. |
| S5 | Today screen may show yesterday after an overnight resume | "Today" is computed at render time and nothing forces a render at midnight. A changed step or tracker row on foreground usually triggers one. | With Apple Health and Google Health off, background at night, foreground next morning, check the ring before touching anything. |
| S6 | Model retirement would take features down | Model IDs are compiled in; only the coach tier has a Settings override (`AIProviderSettingsView.swift:126-137`), not plan or insight. I could not check that the listed IDs are currently valid. | "Verify key works" for coach; run a plan build and a daily brief on each provider. |
| S7 | Google Health disconnects every 7 days without telling the user | Testing-mode refresh tokens; expiry is logged to Diagnostics only (`GoogleHealthAuth.swift:271-276`). | Wait out the window, see whether anything on Today or Settings prompts a reconnect. |
| S8 | Timezone change shifts start-of-day keyed rows by a day | Steps, sleep, vitals and checklist rows store midnight of the old zone; westward travel maps them to the previous day. | Change the simulator time zone west and compare step and sleep charts. |
| S9 | Step-bonus inconsistency when "Let steps add to my budget" is on | "To go" includes the bonus (`DashboardView.swift:46-47`), "Fueled" and the gauge do not (`:49-60`); the widget adds it to both. | Turn the toggle on, walk past the baseline, compare. |
| S10 | Plan card can show a range below the safe floor while rings show the clamped one | Plan numbers are stored unclamped (`PlanService.swift:387-395`), read-time clamp at `UserProfile+Targets.swift:50,89-90`. | Edit the plan floor to 1,000 via Vita on a female profile. |
| S11 | Rate after a long gap spans all history | `TrendCalculator.swift:41-43` falls back to every point when fewer than two are in the 14-day window; the brief then says "this week" (`DailyBriefCard.swift:120-122`). | Seed old weigh-ins plus one today. |
| S12 | Working tree does not match HEAD | 17 tracked files are modified and several depend on untracked `AITask.swift` / `AIRuntime.swift`. A build from a clean checkout is a different app from the one on disk; committing only the tracked changes would not compile. | `git status` before archiving. |
| S13 | Key save failures are invisible | `SecItemAdd` status ignored (`KeychainStore.swift:36`); onboarding sets "Key saved" unconditionally (`OnboardingView.swift:1209`). | Low value; note only. |
| S14 | Deleting the local store on a real device brings the old profile back | CloudKit mirroring re-imports. The runbook's "wipe the store to reseed" works on the simulator because it has no iCloud account. | Wipe the store on a device signed in to iCloud and relaunch. |

Platform behaviours used above (Keychain items surviving app deletion, UserDefaults and the app-group container being removed with the app, Health and notification permissions resetting on reinstall, CloudKit mirroring being enabled by the default configuration when the entitlement is present) are from platform knowledge, not observed in this audit.

---

## 10. Read and found sound

- Target math and its floor/ceiling clamps, including garbage-override guards (`UserProfile+Targets.swift:45-93`), with unit tests.
- Single-flight guards on tracker refresh (`RootView.swift:117-133`, `GoogleHealthSync.swift:41-45`) and the shared idempotent merge functions.
- Main streak definition and comeback gap handling (`StreakCalculator.swift`), with tests; DST handled in the streak walk and in `TravelSignal`.
- Plan build/review updating the row in place and keeping the changelog (`PlanService.swift:59-82,139-155`).
- Provider switching through `AIClient.make()/makeFull()`; every optional AI surface gates on `AIConfig.hasActiveKey` and has a fallback.
- DEBUG-only key injection and launch-argument demo paths are not reachable in Release.
- Google token refresh is single-flighted and guards against resurrecting a disconnected session (`GoogleHealthAuth.swift:243-284`).
