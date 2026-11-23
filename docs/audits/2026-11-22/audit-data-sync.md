# Sprout — data in/out audit (everything except the LLM layer)

- Repo audited: ``, HEAD `3fc5c6c` plus an uncommitted working tree
  (another change set is in flight in `Victoria/Services/AI/*`, `project.yml`, some `*Service.swift`; none of the files
  cited below as bugs are modified relative to HEAD except `project.yml`).
- Method: read-only. Nothing was built, run, or sent over the network. No simulator, no xcodebuild.
- Every finding is from reading the code path end to end. Nothing here was observed at runtime.
  - **VERIFIED BUG** = the code path was read and is wrong; exact scenario given. Still worth one runtime confirmation
    before fixing, because "verified by reading" is not "reproduced".
  - **SUSPECTED** = depends on runtime or CloudKit Dashboard state that cannot be seen from the repo; the check to run is stated.
  - **DESIGN RISK** = works as written, but fragile or surprising.
  - **OK** = checked and sound.
- Paths are relative to the repo root. Line numbers are from the working tree at audit time.

---

## 0. Ranked summary

### Verified bugs (highest impact first)

| # | Area | Bug | Where |
|---|------|-----|-------|
| V1 | Buddy / privacy | Opting out of "share full stats" still uploads weight trend, goal weight, weekly rate, calories, macros and food names to the PUBLIC CloudKit DB; only the reader's UI hides them | `Victoria/Features/Buddy/Views/BuddyAutoPublisher.swift:59,76-99`; `BuddyViewModel.swift:428-455`; `CloudKitSyncService.swift:546-558` |
| V2 | Buddy / pairing | Typing a code that does not exist (typo, or owner has not uploaded yet) returns success and shows "You're connected!" | `CloudKitSyncService.swift:380-392,411-416`; `BuddyViewModel.swift:238-241` |
| V3 | Buddy / pairing | Local link is persisted before the claim is saved; a failed save leaves a one-sided link that is later promoted to "connected" | `CloudKitSyncService.swift:406-416`; `BuddyViewModel.swift:198-203` |
| V4 | Buddy / pairing | No unlink or re-pair path once linked, identity lives only in UserDefaults; if one side reinstalls, the other is permanently stuck on a dead ID | `BuddyViewModel.swift:25-32`; `CloudKitSyncService.swift:265-273`; `BuddyHomeView.swift:361` (only entry to pairing is the not-linked state); `unlink()` has zero callers |
| V5 | HealthKit export | Weigh-ins are never written to Apple Health. `saveWeight` has zero callers, yet write permission is requested and the usage string promises it | `Victoria/Services/HealthKitService.swift:83,108`; `project.yml` (NSHealthUpdateUsageDescription); insert sites `WeightView.swift:434-438`, `CoachTools.swift:2181`, `OnboardingView.swift:1587` |
| V6 | Widgets | After midnight the widget keeps showing yesterday's calories/steps/water as today's until the app is opened. The 30-minute reload re-reads the same stored snapshot and nothing checks `updated` | `VictoriaWidgets/SnapshotProvider.swift:23-27`; `Shared/WidgetSnapshot.swift:9,124-129`; `Shared/WidgetViews.swift` (no use of `updated`) |
| V7 | HealthKit sleep | Each sleep sample is bucketed by its own end date, so for staged sources (many samples per night) everything before midnight lands on the previous day's row | `Victoria/Services/HealthKitSleepWorkouts.swift:62` |
| V8 | Cross-source merge | HealthKit and Google rewrite the same sleep/vitals rows on every refresh (HK first, Google second). If the Google fetch fails (offline), the last 7 nights regress to HealthKit's numbers; the HK vitals pass can zero a half Google delivered | `RootView.swift:122-132`; `HealthKitSleepWorkouts.swift:121-131,159,211-215`; `GoogleHealthSync.swift:50-69` |
| V9 | Buddy publish | `BuddyAutoPublisher` owns its own view model whose `isLinked` is read once at init. After pairing in-session, auto-publish stays off until the next cold launch | `BuddyAutoPublisher.swift:161,182,193,201`; `BuddyViewModel.swift:110` |
| V10 | Buddy nudges | Streak milestones re-fire every day once the streak is 3 or more (tiers use `>=`, dedupe key is per day), with the wrong number in the text | `Victoria/Features/Buddy/Services/BuddyMilestones.swift:72-75,87-89,19-22` |
| V11 | Buddy nudges | A milestone is marked celebrated before the send; if the send fails it is never retried | `BuddyMilestones.swift:109-110`; `BuddyViewModel.swift:343` |
| V12 | Notifications | For a new user who keeps the default (cute) theme, reminders are not scheduled and notification permission is not requested until the next cold launch | `RootView.swift:55,74-88`; `NotificationService.swift:172-179`; `OnboardingView.swift:1557-1596` (no call) |
| V13 | Food lookup | Search terms containing `&`, `+` or `=` are sent unescaped, so "M&M" searches for "M" | `Victoria/Services/OpenFoodFactsService.swift:39-40` |
| V14 | Push | The remote-notification handler reports `.newData` before any work has run, and fires a buddy refresh for every CloudKit push including the private-mirror ones | `Victoria/App/AppDelegate.swift:44-48` |
| V15 | Backup | "Export a backup" is export-only (no import exists) and drops most of the data model | `Victoria/Services/DataExport.swift:11-39,57-75`; no `fileImporter` anywhere |
| V16 | Diagnostics | While the pairing screen is open, a "snapshot fetch failed quietly" line is logged every 4 s, which evicts the 600-line ring in about 40 minutes — exactly when the real pairing error is needed | `PairingView.swift:54-60`; `BuddyViewModel.swift:215-225,518-520`; `Diagnostics.swift:19,46-52` |
| V17 | Buddy publish | On backgrounding with the hub open, two view models publish the same record at once; one fails with a change-tag conflict and marks sync as failed | `BuddyHomeView.swift:148-151`; `BuddyAutoPublisher.swift:192-193`; `BuddyViewModel.swift:463` (guard is per instance) |
| V18 | Buddy nudges | Sending a nudge requires a fetched snapshot, so a linked user whose buddy has not published yet is told to "pair first" | `BuddyViewModel.swift:284-288,313-316` (compare the correct fallback at `:339`) |
| V19 | Health settings | "Connect Apple Health" always shows as not connected on re-entry; copy still says "Victoria" | `Victoria/Features/Settings/HealthSettingsView.swift:25,84` |
| V20 | HealthKit auth | Users who authorised before sleep/workout/vitals types were added are never re-prompted | `HealthKitService.swift:76-100`; only callers `HealthSettingsView.swift:131`, `OnboardingView.swift:1219` |
| V21 | Project config | Widget extension Info.plist is pinned at 1.0 (1) while the app is 2.1 (15) | `VictoriaWidgets/Info.plist:19-22` vs `project.yml` |
| V22 | Push | Nudge pushes set the badge (`shouldBadge = true`) and nothing in the app ever clears it | `CloudKitSyncService.swift:305`; no `setBadgeCount` anywhere |

### Top suspected issues (need a runtime or Dashboard check)

| # | What | Check |
|---|------|-------|
| S1 | Private-DB mirror may be failing silently in Production if the `CD_*` record types/fields for recently added models were never deployed (same failure class as the frozen buddy schema) | CloudKit Dashboard, Production, private DB schema: confirm `CD_SleepEntry`, `CD_VitalsEntry`, `CD_DetectedWorkout`, `CD_WorkoutSession`, `CD_ExerciseEntry`, `CD_CoachPlan`, `CD_ChecklistItem` and every current field exist |
| S2 | Public-DB security roles: claiming a pairing record and marking a nudge read both modify a record another iCloud user created | Dashboard, Security Roles: does `_icloud` have Write on `BuddyPairing` and `Nudge`? Look for `link.save` / `markRead` CKError 10 in Diagnostics |
| S3 | Fresh install / new phone: Keychain-surviving Google tokens and HealthKit backfill insert rows before the CloudKit import arrives, giving duplicate per-day rows; re-onboarding creates a second `UserProfile` and a spurious weigh-in | Reinstall on a device with cloud data, then count rows per day in the store |
| S4 | Signing out of iCloud likely purges the mirrored local store, sending the user back to onboarding | Sign out of iCloud on a test device and relaunch |
| S5 | Background publish has no background-task assertion, so "log, close the app, buddy sees it in seconds" may not complete | Log, background immediately, read the publish timestamps in Diagnostics |

---

## 1. Apple HealthKit

Files: `Victoria/Services/HealthKitService.swift` (226), `HealthKitSteps.swift` (103), `HealthKitSleepWorkouts.swift` (337),
`Victoria/Features/Settings/HealthSettingsView.swift` (182).

### V5 — VERIFIED BUG: weight export never happens
- `HealthKitService.saveWeight(lbs:date:)` at `HealthKitService.swift:108-131` has no callers (grep of `Victoria/`, `Shared/`,
  `VictoriaWidgets/`, `VictoriaTests/` finds only the definition).
- All three weigh-in insert sites write SwiftData only: `WeightView.swift:434-438`, `CoachTools.swift:2181-2183`,
  `OnboardingView.swift:1587`.
- Yet `requestAuthorization` asks for share access to body mass (`HealthKitService.swift:83,99`), `project.yml` ships
  `NSHealthUpdateUsageDescription: "Sprout saves the weigh-ins you log to Apple Health…"`, and
  `HealthSettingsView.swift:66` tells the user about "saving weight".
- Scenario: log a weigh-in in Sprout, open Apple Health — nothing is there.
- Side risk: requesting a HealthKit write permission the app never uses is an App Review exposure.
- If it is wired up: the sync identifier is derived from the timestamp with a constant version 1
  (`HealthKitService.swift:116-120`), so an edited weigh-in would not replace the earlier sample (same identifier, same
  version). There is also no delete path. Both need designing before turning it on.

### V7 — VERIFIED BUG: sleep night bucketing
- `dailySleep` maps every `HKCategorySample` to `cal.startOfDay(for: s.endDate)` (`HealthKitSleepWorkouts.swift:62`).
- The doc comment (`:32-36`) says a night belongs to its wake morning. That holds only when a source writes one sample per
  night. Apple Watch and most bridges write many short stage samples.
- Scenario: asleep 22:30 to 06:30 with staged samples. The 22:30–23:59 samples end before midnight and are added to the
  previous calendar day; only the post-midnight part lands on the wake day. Every row then mixes the tail of one night with
  the head of the next.
- Naps are also summed into the day on this path, while the Google path excludes naps (`GoogleHealthClient.swift:172`),
  so the two pipes disagree by construction.
- Not unit-tested: `dailySleep` is not pure, and `HealthTrackerImportTests` only covers the merge.
- Fix direction: key by a noon-to-noon (or 18:00 cutoff) window, or group contiguous samples into sessions and key by the
  session end. Extract the aggregation into a pure function and test it.

### V20 — VERIFIED gap: upgraders never get the new permission sheet
- New read types (sleep, workouts, resting HR, HRV) were added to `requestAuthorization` (`HealthKitService.swift:88-96`).
- It is only called from onboarding (`OnboardingView.swift:1219`) and the manual Connect button (`HealthSettingsView.swift:131`).
- `RootView.refreshTrackerData` (`RootView.swift:122-127`) queries those types without ever asking. For a user who
  authorised on an older build, the queries return empty forever.
- Standard practice: call `getRequestStatusForAuthorization` on launch and prompt when it returns `.shouldRequest`.

### V19 — VERIFIED (minor): Health settings state and copy
- `isConnected` is `@State … = false` (`HealthSettingsView.swift:25`) and is only set by tapping Connect in that session, so
  the row reads "Connect Apple Health" every time the screen opens.
- `HealthSettingsView.swift:84`: "…that aren't already in Victoria." The app is called Sprout.

### Weight import — convention violation and gaps
- **VERIFIED (convention)**: `importRecent` (`HealthKitService.swift:159-225`) does its own filter-and-insert inline. It is
  the one ingest path that does not go through a pure, unit-tested merge function, contrary to the CLAUDE.md rule.
- **DESIGN RISK**: weight import is manual only (`HealthSettingsView.swift:141-172`). It is not part of
  `refreshTrackerData`, so a smart-scale reading never appears on its own, although the read usage string says weight
  "stays in sync".
- **DESIGN RISK**: no tombstones. An imported weigh-in the user deletes comes back on the next import because its UUID is
  no longer in `existingHealthKitUUIDs` (`HealthSettingsView.swift:29-31,147`).
- **OK**: skips samples authored by this app (`:197`), dedupes by sample UUID, HealthKit work happens off the main actor and
  inserts happen on it.

### Steps
- **OK**: `mergeDailySteps` (`HealthKitSteps.swift:86-102`) is pure, idempotent and tested (`StepsBackfillTests`).
- **Dead code with parallel insert logic**: `importTodaySteps` and `todaySteps` (`HealthKitSteps.swift:7-37`) have no
  callers and contain their own upsert. Delete them.
- **DESIGN RISK**: each reader creates a fresh `HKHealthStore()` (`HealthKitSteps.swift:10,45`,
  `HealthKitSleepWorkouts.swift:40,167,244`) instead of the long-lived `store` on the service.

### Day keys and time zones — DESIGN RISK (inferred, not run)
- Step/sleep/vitals rows store `startOfDay` as an absolute instant and match with `calendar.isDate(_:inSameDayAs:)` in the
  current zone (`HealthKitSteps.swift:93`, `HealthKitSleepWorkouts.swift:121,211`).
- After travelling west, a row stored at 00:00 Eastern on day D reads as 21:00 Pacific on D-1, so the next refresh treats
  it as the previous day. Rows inside the refresh window get rewritten shifted by one; history outside the window stays
  mislabelled by a day.
- The app already models travel (`TravelSignal`), so this is an expected situation. A civil-date key (`"yyyy-MM-dd"`)
  avoids it.

### Other HealthKit notes
- **DESIGN RISK**: nothing reconciles deletions. A workout, night or weigh-in removed at the source stays in Sprout.
- **DESIGN RISK**: two HealthKit sources reporting the same workout (Watch plus a bridge) both insert; the time-window
  dedup only applies across pipes (`GoogleHealthSync.swift:123-124`).
- **OK**: locked device or no authorisation returns empty results and the merges early-return on empty input, so an
  unavailable source never wipes data.

---

## 2. Google Health API v4 / Fitbit

Files: `Victoria/Services/GoogleHealth/GoogleHealthAuth.swift` (317), `GoogleHealthClient.swift` (322),
`GoogleHealthSync.swift` (131), `Victoria/Features/Settings/GoogleHealthSettingsView.swift` (171), `KeychainStore.swift` (100).

### OK
- PKCE S256 with a 64-byte verifier (`GoogleHealthAuth.swift:101-116`), `state` generated and checked (`:169,209`),
  no client secret, `ASWebAuthenticationSession`, continuation resumed exactly once (`:181-203`).
- Tokens only in the Keychain with `AfterFirstUnlock` (`KeychainStore.swift:73`); client ID in UserDefaults (it is public).
- Single-flight refresh (`GoogleHealthAuth.swift:240-255`); a disconnect during a refresh cannot resurrect tokens (`:267`).
- `invalid_grant` clears tokens and logs (`:273-277`).
- Sync re-reads existing rows from the context rather than a caller snapshot, each stream fails independently, and it is
  single-flighted (`GoogleHealthSync.swift:41-88`).
- Parsers are pure and tolerant of string int64s, missing summaries and malformed points; 23 tests in `GoogleHealthTests`.
- Steps are deliberately not read from Google, so there is no double count.

### DESIGN RISK
- **No 401 handling.** `fetchAllPages` takes one token and never retries with a refresh (`GoogleHealthClient.swift:80-99`).
  A grant revoked on the Google side before the access token expires yields HTTP 401 on every sync with no automatic
  disconnect.
- **Silent weekly disconnect in OAuth testing mode.** The code comment at `GoogleHealthAuth.swift:271-272` acknowledges the
  7-day refresh-token expiry. When it happens on a foreground refresh the only trace is a Diagnostics line; the Today
  tracker card just shows a status string (`TrackerCard.swift:311`). There is no "reconnect Fitbit" prompt.
- **Launch chores wait on the network.** `RootView.swift:83-88` awaits the tracker refresh before the widget refresh and
  `NotificationService.refreshOnLaunch`. The Google requests use the default 60 s timeout, sequentially for sleep, vitals
  and workouts (`GoogleHealthSync.swift:50-80`), plus a token refresh. On a captive or very slow network those launch
  chores can be delayed by minutes, and `trackerRefreshInFlight` stays set so later foregrounds skip the HealthKit pass too.
  Set a short per-request timeout and do not gate local work on it.
- **Token endpoint ignores HTTP status** and maps non-JSON to `[:]` (`GoogleHealthAuth.swift:297-298`); the user sees
  "unknown error".
- **A rotated refresh token would be dropped** (`:280-282` always keeps the old one). Google normally does not rotate here.
- **Disconnect then immediate reconnect** while an old refresh is in flight can overwrite the new refresh token with the old
  one (`:258,280-282` use the captured `current`). Very narrow window.
- **Keychain writes are delete-then-add with the status ignored** (`KeychainStore.swift:69-74`). A failed add after a
  successful delete loses the token.
- **Tokens survive uninstall** (documented in CLAUDE.md as a convenience). It also means a different person installing on
  the same phone inherits the Fitbit connection.
- **Revocation puts the refresh token in the URL query** (`GoogleHealthAuth.swift:87-92`). Works; a form body is cleaner.
- **Edits and deletions never propagate.** Workout merge is insert-only by ID (`HealthKitSleepWorkouts.swift:295-304`).
- **A night split into two sessions keeps only the longer one** (`GoogleHealthClient.swift:221-222`).
- **`mergeDetectedWorkouts` does not add to `known` inside the loop** (`HealthKitSleepWorkouts.swift:295-304`), so a
  repeated ID within one fetched batch would insert twice.

### SUSPECTED
- **Background launch before first unlock.** `GoogleHealthAuth.shared` reads the Keychain once in `init`
  (`GoogleHealthAuth.swift:68-74`). If the process is first created by a silent push while the Keychain is unreadable,
  `tokens` stays nil for that process and Fitbit shows as disconnected until the app is killed. Check: reboot, do not
  unlock, trigger a buddy push, then open the app.
- **Filter grammar and field names** (`civil_end_time`, `daily_resting_heart_rate.date`, …) could not be checked against
  the live API from here. The header says they were verified against the discovery document.

---

## 3. Merge functions and cross-source dedup

### Does every ingest path use them?

| Path | Merge used | Verdict |
|------|-----------|---------|
| HK steps (`RootView.swift:123`) | `mergeDailySteps` | OK |
| HK sleep (`:124`) | `mergeDailySleep` | OK |
| HK vitals (`:126`) | `mergeDailyVitals` | OK |
| HK workouts (`:125`) | `dedupAgainstExisting` then `mergeDetectedWorkouts` | OK |
| Google sleep / vitals / workouts (`GoogleHealthSync.swift:53,64,75`) | same three merges (+ `overlayVitals`) | OK |
| HK weight (`HealthSettingsView.swift:152`) | none — inline insert at `HealthKitService.swift:215-223` | VERIFIED convention violation |
| `importTodaySteps` (`HealthKitSteps.swift:26-37`) | own upsert | dead code, delete |
| `DemoSeed` (`DemoSeed.swift:65-104`) | direct inserts | acceptable (seed only), see §11 on DEBUG gating |

The merge functions live as static members in extensions of `HealthKitService`, so the Google path calls
`HealthKitService.mergeDailySleep`. They should be their own type.

### V8 — VERIFIED BUG: HealthKit and Google fight over the same rows
- `refreshTrackerData` runs HealthKit, then Google, relying on order for "Google wins" (`RootView.swift:113-132`).
- `mergeDailySleep` overwrites whenever any of six fields differs (`HealthKitSleepWorkouts.swift:121-131`). There is no
  source column on `SleepEntry` or `VitalsEntry`.
- Scenario A (every foreground, both pipes have the night): the HK pass writes HK's numbers and saves, the Google pass
  writes Google's back and saves. Two writes per overlapping night per foreground, each exported to CloudKit, with the UI
  briefly observing the HK values. An iPhone with a Sleep schedule writes in-bed samples on its own, and the in-bed
  fallback at `:95` turns those into "asleep" minutes, so this does not require a Watch.
- Scenario B (offline or Google error): HealthKit works offline, Google does not. The HK pass downgrades up to 7 nights
  (stages lost) and they stay that way until the next successful Google sync.
- Vitals: `dailyVitals` fills a missing half with 0 (`:159`) and `mergeDailyVitals` writes both halves (`:211-215`). The
  "0 never beats a real reading" overlay exists only on the Google side (`GoogleHealthSync.swift:95-107`). So an HK day
  with HRV but no resting HR writes `rhr = 0` over Google's value; it is restored only if the Google pass then succeeds.
- Fix direction: add a `source` field and a precedence rule inside the merge, apply the overlay symmetrically, and make
  the merge a no-op when the incoming source is lower priority.

### Dedup
- **OK**: `dedupAgainstExisting` is symmetric and tested (`GoogleHealthSync.swift:116-130`, `GoogleHealthTests:232-269`).
- **DESIGN RISK**: workouts are first-writer-wins (HealthKit, because it runs first) while sleep/vitals are Google-wins.
  That inconsistency is undocumented.
- **DESIGN RISK**: all merges use `existing.first(where:)`. With duplicate rows for a day (see S3) only one is updated.

---

## 4. Buddy sync (CloudKit public database)

Files: `Victoria/Features/Buddy/Services/CloudKitSyncService.swift` (828), `BuddySyncService.swift` (276),
`BuddySync.swift` (32), `BuddyMilestones.swift` (113), `LocalMockSyncService.swift` (363),
`Views/BuddyViewModel.swift` (543), `Views/BuddyAutoPublisher.swift` (225), `Views/BuddyHomeView.swift` (393),
`Views/PairingView.swift` (289), `Victoria/App/AppDelegate.swift` (54).

### V1 — VERIFIED BUG: privacy toggle does not stop the upload
- `BuddyStateComposer.compose` reads the flag (`BuddyAutoPublisher.swift:59`) but fills `trendWeightLbs`, `goalWeightLbs`,
  `weeklyRateLbs`, calories, protein, carbs, fat and `todayFoods` unconditionally (`:76-99`).
- `publishMine` forwards them all (`BuddyViewModel.swift:428-455`) and `publish` writes them all
  (`CloudKitSyncService.swift:546-558`).
- The doc comment at `BuddyViewModel.swift:391-393` says the fields "stay 0/"" and never leave the device with meaning".
  That is not what the code does. `README.md:176` describes the toggle as controlling what a buddy sees, which is true of
  the UI only.
- The record is in the public database, and the toggle defaults to on (`UserProfile.swift:71`).
- Scenario: turn "Share my full stats" off, log lunch. The public `snapshot-<id>` record now holds today's food names,
  calories and weight trend with `sharesFullData = 0`.
- Related: toggling the switch does not republish. `dataSignature` (`BuddyAutoPublisher.swift:167-173`) has no profile
  inputs and `SettingsView.swift:600-601` is a bare binding.
- Fix: zero the full-data fields in the composer when the flag is off, add the flag to the signature, publish on toggle.

### V2 — VERIFIED BUG: a wrong code "connects"
- `link(usingCode:)` treats `.unknownItem` as "I am first": it creates `pairing-<code>` with me as owner and returns
  normally (`CloudKitSyncService.swift:380-392,411-416`).
- `BuddyViewModel.link` then sets `isLinked = true` and shows "You're connected! 💚" (`BuddyViewModel.swift:238-241`).
- `.invalidPairingCode` is only thrown for an empty string (`CloudKitSyncService.swift:349`), so the "that code didn't
  match" copy (`BuddyViewModel.swift:505-506`) is unreachable on the real backend.
- Scenario: B mistypes A's code, or types it before A's phone has uploaded it. B lands on the linked hub with no buddy.
  B now owns a record under A's code, so when A's upload runs, `publishMyPairingCode` sees an owner that is not A and does
  nothing (`:245-249`). Neither side links until someone re-enters a code.
- Fix: the typer must never create. On `.unknownItem` throw `.invalidPairingCode`; only `publishMyPairingCode` creates.

### V3 — VERIFIED BUG: link persisted before the save
- `buddyUserID = ownerID` at `CloudKitSyncService.swift:408` fires the `didSet` that writes UserDefaults (`:138-140`)
  before `database.save(record)` at `:412`.
- If the save throws, the view model shows a failure, but the next `refresh()` finds `service.linkedBuddyID != nil` and
  flips to linked with "They got your code — you're connected!" (`BuddyViewModel.swift:198-203`).
- The owner's record has no claimant, so the owner never discovers the buddy (`resolveBuddyIfNeeded`, `:265-273`).
- This is the path that S2 would hit on every claim if the security role is missing.
- Fix: assign `buddyUserID` only after the save succeeds.

### V4 — VERIFIED BUG: no way out of a link, identity is not durable
- `myUserID` is a UUID minted into UserDefaults (`BuddyViewModel.swift:25-32`). Deleting the app mints a new one.
- `unlink()` is implemented in both services and has no caller anywhere.
- The only navigation into `PairingView` is from the not-linked empty state (`BuddyHomeView.swift:361`).
- `resolveBuddyIfNeeded` only runs when `buddyUserID == nil` (`CloudKitSyncService.swift:266`), so a linked device never
  notices that the record's claimant changed.
- Scenario: Victoria reinstalls or moves phones without a device restore. She gets a new ID and code. Bryan's app stays
  linked to her old ID: frozen snapshot, nudges addressed to an ID nobody reads. He cannot unlink or re-pair; the only
  recovery is deleting his app too.
- Fix direction: store identity somewhere that survives reinstall (Keychain, or the mirrored `BuddyLink` model that
  already exists for this and is unused), add an unlink action, and re-resolve when the pairing record changes.

### V9 — VERIFIED BUG: auto-publisher does not learn about a new link
- `BuddyAutoPublisher` holds `@State private var model = BuddyViewModel(observePushes: false)` (`:161`).
- `isLinked` is seeded from UserDefaults in `init` (`BuddyViewModel.swift:110`) and afterwards only changes in
  `refresh`/`loadSnapshot`/`link`, none of which the publisher calls.
- All three publish triggers are guarded by `model.isLinked` (`BuddyAutoPublisher.swift:182,193,201`).
- Scenario: pair on Monday from the hub. Until the process is next cold-launched, logging food on any other tab uploads
  nothing; the buddy only gets updates while the Buddy page itself is open.
- Fix: one shared buddy store injected through the environment, or re-read `service.linkedBuddyID` at each trigger.

### V10 / V11 — VERIFIED BUGS: milestone nudges
- `met` returns `.streak3` for any streak from 3 to 6, `.streak7` for 7 to 13, and so on (`BuddyMilestones.swift:72-75`).
  The celebrated flag is keyed per day (`:87-89`). So the buddy gets a streak push every day from day 3 onward, and on
  day 5 it reads "is on a 3-day logging streak". `BuddyMilestonesTests:48-60` asserts the next-day re-fire.
- `consumeNewlyReached` sets the flag (`:110`) before `celebrate` runs, and `celebrate` uses `try?`
  (`BuddyViewModel.swift:343`). An offline moment at goal time loses the cheer for the day.
- Fix: fire a streak tier only when `dayStreak == threshold` (or key streak tiers without the day), and mark celebrated
  after a successful send.
- Hygiene: the flags add up to 8 UserDefaults keys per day forever and are never pruned.

### V14 — VERIFIED BUG: remote-notification handler
- `application(_:didReceiveRemoteNotification:)` posts `.buddyRemoteChange` and immediately returns `.newData`
  (`AppDelegate.swift:44-48`). Returning ends the background window, so the refresh it triggered is not guaranteed to run.
- It never inspects `userInfo`. The SwiftData private mirror also delivers silent pushes to this app, so every private-DB
  change triggers a buddy refresh.
- The only observer is a live `BuddyViewModel` created by the hub (`BuddyViewModel.swift:136-144`); the auto-publisher
  passes `observePushes: false`. If the hub is not in memory the push does nothing, and nothing is persisted or written
  to the widget.
- Net: the "silent-push refresh" described at `README.md:176-178` is effective only while the hub is already open, where
  the 20 s poll (`BuddyHomeView.swift:127-133`) covers it anyway. The comment at `BuddyHomeView.swift:122-124` already
  calls the push unreliable.
- Fix: parse `CKNotification`, filter on the subscription ID, await the fetch before returning, and persist the result.

### V16 — VERIFIED BUG: diagnostics flood during pairing
- `PairingView` polls `model.refresh()` every 4 s while unlinked (`PairingView.swift:54-60`).
- Each pass calls `loadSnapshot`, which throws `.notLinked` and logs through `handleSilently`
  (`BuddyViewModel.swift:215-225,518-520`).
- The log is a 600-line ring that rewrites the whole file on every line (`Diagnostics.swift:19,46-52`).
- About 900 lines an hour, so the real `link.save` / `pairing.save` error is gone after roughly 40 minutes on that screen.
- Each pass also makes about five CloudKit calls (three `accountStatus`, one record fetch, one query).
- Fix: do not log `.notLinked`, coalesce repeated lines, append instead of rewriting.

### V17 — VERIFIED (low): concurrent publishes from two view models
- `isPublishing`/`queuedPayload` serialise within one `BuddyViewModel` (`BuddyViewModel.swift:463-489`), but the hub and
  the auto-publisher each have their own instance and their own `CloudKitSyncService`.
- On `.background` with the hub in the navigation stack, both fire (`BuddyHomeView.swift:148-151`,
  `BuddyAutoPublisher.swift:192-193`). Both do fetch-modify-save on `snapshot-<me>`; the loser gets a change-tag conflict
  and sets `lastPublishFailed`, which then forces a retry on the next foreground.
- No data is lost. The health indicator is wrong.

### V18 — VERIFIED (low): nudge send gated on the snapshot
- `send(_:)` and `send(text:)` bail with "Pair with a buddy first" when `buddySnapshot` is nil
  (`BuddyViewModel.swift:284-288,313-316`). The service already knows the buddy ID and overrides `toUserID` itself
  (`CloudKitSyncService.swift:443-449`); `celebrate` uses the right fallback (`BuddyViewModel.swift:339`).

### V22 — VERIFIED (low): badge never cleared
- The nudge subscription sets `shouldBadge = true` (`CloudKitSyncService.swift:305`). No code calls `setBadgeCount` or
  resets the server-side count, so the icon badge only grows.

### Other verified-by-reading behaviours
- **Inbox is wiped on any error** (`BuddyViewModel.swift:351-357`), and an offline poll re-raises the "back online" banner
  every cycle.
- **Every error is flattened to one message.** No iCloud account, restricted account, network failure and schema
  rejection all become `.cloudKitUnavailable` with "will catch up once you're back online — nothing lost"
  (`CloudKitSyncService.swift:215-228`, `BuddyViewModel.swift:507-508`). For a signed-out user that is wrong advice. The
  correct text exists only in the hidden `diagnose()` (`:681-691`).
- **`sharedState(myLoggedToday:)` writes UserDefaults** from what is documented as a derived UI value
  (`BuddyViewModel.swift:156-182`).
- **`fetchInbox` has no limit, cursor or age filter** (`CloudKitSyncService.swift:463-487`) and runs every 20 s while the
  hub is open. Nudges are never deleted.

### Error handling, retry, missing schema field, signed out — as asked
- **Production schema lacks a field**: the whole `publish` save fails with `invalidArguments`
  (`CloudKitSyncService.swift:560-568`). It is logged, flattened to `.cloudKitUnavailable`, and retried unchanged on the
  next trigger, failing the same way every time. There is no fallback that retries with the legacy field set. The hub
  shows a soft warning (`BuddyHomeView.swift:246-250`) and `diagnose()` step 4 pinpoints it. Classification: DESIGN RISK,
  mitigated by diagnostics rather than handled.
- **Retry**: publish is retried on foreground when the last attempt failed or the last success is older than 6 hours
  (`BuddyAutoPublisher.swift:200-203`). Nudges are not retried. The pairing announce is retried by the 4 s poll.
- **Signed out of iCloud**: every call throws `.cloudKitUnavailable` after `accountStatus`
  (`CloudKitSyncService.swift:215-228`). No crash, no hang. The message is misleading (above). There is no
  `CKAccountChanged` observer, and identity is not tied to the iCloud user.
- **Subscriptions**: created lazily from `fetchBuddySnapshot` (`:574-576`) and flagged in UserDefaults. The snapshot
  subscription needs `BuddySnapshot.ownerUserID` to be queryable; failure is logged and retried each fetch.

### SUSPECTED
- **S2 security roles.** `link` (`:407-412`) and `markRead` (`:496-498`) write to records created by the other user. With
  default public-DB roles only the creator can write. If Write was not granted to `_icloud`, every claim fails (and V3
  then shows a one-sided "connected"), and read receipts never stick, so the optimistic local read state
  (`BuddyViewModel.swift:363-374`) reverts on the next 20 s poll. The header runbook lists indexes but not roles;
  `diagnose()` mentions roles only in its final line. Two devices on the same Apple ID would hide this.
- **S5 background publish.** `Task { await publish() }` on `.background` with no `beginBackgroundTask` (grep finds none).
  The publish needs `accountStatus`, a fetch and a save.

### DESIGN RISK
- Public database for weight, calories and food names, addressed by a short guessable code, with last-writer-wins
  claiming and no check that a code is unclaimed (`CloudKitSyncService.swift:406-408`). Documented as a TODO at `:48-52`.
- The alert title is hard-coded "Vita 💛" (`:298`) although the coach name is user-configurable.
- Tapping a nudge notification does nothing specific; there is no `didReceive response` handler.
- `BuddyLink`, `Nudge` and `BuddySnapshot` are `@Model` types registered in the schema (`VictoriaApp.swift:32-34`) but
  never inserted or fetched. `Nudge` is used as an in-memory DTO built from `NudgeWire` every poll. They add three empty
  record types to the private mirror and should be plain structs.

### Stale documentation in this area
- `BuddySync.swift:6-14` says Release still uses the mock; the code selects by simulator vs device (`:25-30`).
- `CloudKitSyncService.swift:14-27` says `DEVELOPMENT_TEAM` is blank; `project.yml` sets it.
- `CloudKitSyncService.swift:361-367` "KNOWN WIRING GAP" describes a gap that `publishMyPairingCode` closed.
- `BuddyViewModel.swift:60-61` and `BuddySyncService.swift:80-82` say the snapshot never carries weight or calories.
- `BuddyLink.swift:13` says CloudKit-backed SwiftData is "wired up later".

---

## 5. SwiftData and the CloudKit private mirror

Config: `VictoriaApp.swift:11-51`. `ModelContainer(for: schema)` with a default configuration. With the iCloud container
entitlement present this means automatic CloudKit mirroring into `iCloud.com.bryanram.victoria`, and the store sits in
the app-group container (CLAUDE.md confirms the location). The same container also hosts the buddy public database.

### Rule check per model (all attributes optional or defaulted, no unique constraints, relationships optional)

| Model | File | Result |
|-------|------|--------|
| UserProfile | `Victoria/Models/UserProfile.swift:7-109` | OK (all defaulted, `[Int]` defaulted, no unique, no relationships) |
| WeightEntry | `Models/WeightEntry.swift:7-16` | OK |
| FoodEntry | `Models/FoodEntry.swift:6-46` | OK for the rules; see note on `additionalPhotoData` |
| WorkoutEntry | `Models/WorkoutEntry.swift:6-18` | OK (legacy, see §11) |
| WaterEntry | `Models/WaterEntry.swift:5-10` | OK |
| ChatMessage | `Models/ChatMessage.swift:6-26` | OK (`imageData` external storage, optional) |
| CoachMemory | `Models/CoachMemory.swift:26-46` | OK |
| CoachPlan | `Models/CoachPlan.swift:25-61` | OK (JSON strings, no relationships) |
| StepsEntry | `Models/StepsEntry.swift:6-11` | OK |
| SleepEntry | `Models/SleepEntry.swift:12-28` | OK |
| DetectedWorkout | `Models/DetectedWorkout.swift:11-25` | OK |
| VitalsEntry | `Models/VitalsEntry.swift:10-18` | OK |
| AchievementUnlock | `Models/AchievementUnlock.swift:7-11` | OK |
| InsightShown | `Models/InsightShown.swift:7-10` | OK |
| WorkoutSession | `Models/WorkoutSession.swift:14-33` | OK (flat `sessionID` link instead of a relationship) |
| ExerciseEntry | `Models/ExerciseEntry.swift:14-46` | OK |
| ChecklistItem | `Features/Checklist/ChecklistItem.swift:12-28` | OK |
| BuddyLink | `Features/Buddy/Models/BuddyLink.swift:17-38` | OK (unused) |
| Nudge | `Features/Buddy/Models/Nudge.swift:16-36` | OK (unused as a persisted model) |
| BuddySnapshot | `Features/Buddy/Models/BuddySnapshot.swift:16-101` | OK (unused) |

No violations found: no `@Attribute(.unique)`, no `#Unique`, no `@Relationship`, every stored property has a default or
is optional.

### Consequences of those rules that the code does not handle — DESIGN RISK
- **No uniqueness means duplicates are possible and nothing collapses them.** Singletons (`UserProfile`, `CoachMemory`,
  current `CoachPlan`) and per-day rows (`StepsEntry`, `SleepEntry`, `VitalsEntry`) are all fetch-or-create or
  first-match. `profiles.first` is read unsorted in `RootView.swift:7,23`, `BuddyAutoPublisher.swift:156,163`,
  `BuddyHomeView.swift:34,72`, `WorkoutsView.swift:21`, `WorkoutDayDetail.swift:31`. `CoachMemory.fetchOrCreate` at
  least sorts deterministically (`CoachMemory.swift:76-80`). There is no dedupe pass.
- **S3 (SUSPECTED): reinstall or new device.** The launch task backfills immediately (`RootView.swift:83`). Google tokens
  survive in the Keychain, so 14 days of sleep/vitals/workouts are inserted into the empty store; the CloudKit import then
  delivers the same days. The workout ID check only looks at rows present at insert time. Separately, onboarding is shown
  whenever no profile exists locally yet (`RootView.swift:65-70`), and finishing it inserts a new `UserProfile` plus a
  `WeightEntry` at the typed weight (`OnboardingView.swift:1586-1588`), which then sits in the trend next to the restored
  history.
- **Mirror failures are invisible.** Nothing observes `NSPersistentCloudKitContainer.eventChangedNotification`. Given the
  month-long buddy freeze, export/import errors should go to Diagnostics.
- **S1 (SUSPECTED): Production schema for the private mirror.** Development auto-creates `CD_*` types; Production does
  not. If a model or field added since the last deploy is missing there, exports fail on TestFlight builds with no trace
  in the app. This is the same mechanism that froze buddy sync.
- **In-memory fallback** (`VictoriaApp.swift:43-51`). Any store-open failure, including a future non-lightweight schema
  change, silently drops the user into onboarding with data that vanishes on relaunch. It is logged but the user is not
  told, and a local-only configuration at the same URL is not tried first. The widget and buddy publisher keep running
  against the empty store. There is no `VersionedSchema` or migration plan.
- **S4 (SUSPECTED): iCloud sign-out.** The mirrored store is expected to be purged when the account goes away.
- **`FoodEntry.additionalPhotoData: [Data]?`** (`FoodEntry.swift:40`) is stored inline. Every unfiltered
  `FetchDescriptor<FoodEntry>()` or `@Query [FoodEntry]` loads those JPEGs (`WidgetDataWriter.swift:15`,
  `DataExport.swift:57`, `BuddyAutoPublisher.swift:151`, `BuddyHomeView.swift:23`). Use a predicate for "today", or move
  the extra photos to a child record with external storage.
- **46 `try? context.save()` calls** discard failures; only `CoachTools.saveOrLog` (`CoachTools.swift:36`) reports them.
- **Store in the app-group container (inferred).** A process suspended while holding the SQLite lock is terminated with
  `0xdead10cc`. Worth a look in crash logs given the background publish and mirror activity.

---

## 6. Widgets

Files: `Shared/WidgetSnapshot.swift` (138), `Shared/WidgetViews.swift` (411), `Victoria/Services/WidgetDataWriter.swift` (63),
`VictoriaWidgets/*` (137 total).

- **How it is written**: `WidgetDataWriter.refresh` builds a `WidgetSnapshot`, JSON-encodes it into app-group
  UserDefaults under `widget_snapshot_v1`, and calls `reloadAllTimelines()` (`WidgetDataWriter.swift:11-62`).
- **When**: only from `RootView` — at the end of the launch task (`:84`), after the foreground tracker refresh (`:101`),
  and on background (`:106`). The doc comment at `WidgetDataWriter.swift:6-7` says it is also called after logging; it
  is not. In practice the background call covers it.
- **V6 — VERIFIED BUG: day rollover.** `getTimeline` produces a single entry and asks for a reload in 30 minutes
  (`SnapshotProvider.swift:23-27`), but each reload decodes the same stored snapshot. `updated` is written and never
  read by any view. After midnight the widget shows yesterday's eaten calories, macros, steps and water as today's.
  Fix: in the provider, if `updated` is not today, zero the per-day fields; or emit a second entry at the next midnight.
- **DESIGN RISK: placeholder shown as real data.** `WidgetSharedStore.load()` returns `.placeholder` when there is no
  snapshot or decoding fails (`WidgetSnapshot.swift:124-129`). The placeholder is named "Victoria" with 1,355 kcal and a
  28-day streak (`:64-76`). A fresh install, a profile-less state (`WidgetDataWriter.swift:12` returns without writing)
  or a future non-optional field all produce fake numbers under the wrong name. Show an "Open Sprout" state instead.
- **Dead code**: `CalorieBudgetWidget` (`VictoriaWidgets/CalorieBudgetWidget.swift`) is not in the bundle
  (`VictoriaWidgetBundle.swift:8-11`), and its view `CalorieBudgetView` (`Shared/WidgetViews.swift:11`) is otherwise
  unused.
- **V21 — VERIFIED**: `VictoriaWidgets/Info.plist:19-22` hard-codes version 1.0 and build 1. `project.yml` sets 2.1 / 15
  as build settings for the widget target but the plist does not reference them.
- **DESIGN RISK**: `Theme.current` is a global `static var` assigned inside view bodies (`RootView.swift:51`,
  `CompanionWidget.swift:27`, `CalorieBudgetWidget.swift:30`, `Shared/Theme.swift:86`).
- **OK**: the widget never opens the SwiftData store; back-compatible decoding for the three newest fields.

---

## 7. Local notifications and push registration

Files: `Victoria/Services/NotificationService.swift` (230), `AppDelegate.swift` (54),
`Features/Settings/RemindersSettingsView.swift`.

- **V12 — VERIFIED BUG (by reading; confirm once on device).** `refreshOnLaunch` is called only from the root `.task`,
  and only if onboarding was already complete when it ran (`RootView.swift:86-88`). `OnboardingView.finish()`
  (`:1557-1596`) does not call it. The task re-runs only when `.id(themeStyle)` changes (`RootView.swift:55`), which
  happens if the user picked the cool theme, because the pre-onboarding default is cute (`:46`). So a user who keeps cute
  finishes onboarding with weigh-in and meal reminders enabled by default (`UserProfile.swift:89-91`) but nothing
  scheduled and no permission prompt until the next cold launch. Without permission, buddy nudge alerts are not shown
  either.
- **Side effect of that `.id`**: changing theme in Settings rebuilds the whole tree and re-runs every launch chore
  (30-day HealthKit backfill, Google sync, widget write, notification reschedule).
- **OK**: `rescheduleAll` removes everything and rebuilds from the profile with stable identifiers; calendar triggers
  follow local time; denied permission cancels everything.
- **DESIGN RISK**: reminder settings mirror to other devices through CloudKit but are only rescheduled on launch or on a
  local Settings change.
- **Push registration**: `registerForRemoteNotifications()` at every launch (`AppDelegate.swift:21`); both delegate
  callbacks are empty, which is correct for CloudKit-managed push, but a registration failure is not logged (`:30-33`).
  `willPresent` shows banners in the foreground for all notifications (`:36-39`).
- **Entitlements**: `aps-environment` is hard-coded to `production` (`Victoria.entitlements`, `project.yml`). Not
  verifiable from here whether development-signed builds are affected.
- See V14 and V22 for the handler and the badge.

---

## 8. Food database and other outbound calls

Complete list of non-AI outbound network calls found:

| Call | Where | Timeout | Status checked | Offline behaviour |
|------|-------|---------|----------------|-------------------|
| Open Food Facts product | `OpenFoodFactsService.swift:31-36` | 20 s (`:113`) | no (`:114`) | throws, UI says check connection (`ScanView.swift:213-217`) |
| Open Food Facts search | `:38-47` | 20 s | no | throws, `.failed` phase (`RecentFoodsSheet.swift:303-308`) |
| Google token endpoint | `GoogleHealthAuth.swift:286-299` | default 60 s | no | throws, surfaced per stream |
| Google revoke | `:84-94` | default | no | fire-and-forget |
| Google data points | `GoogleHealthClient.swift:79-111` | default 60 s | yes (`:94-99`) | throws, logged |
| MapKit local search | `NearbyPlacesService.swift:78-89` | system | n/a | returns nil |
| CloudKit public DB | `CloudKitSyncService.swift` | system | per-call catch | `.cloudKitUnavailable` |

Findings:
- **V13 — VERIFIED BUG**: `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)`
  (`OpenFoodFactsService.swift:39`) leaves `&`, `+` and `=` unescaped inside `search_terms=…`. "mac & cheese" sends
  `search_terms=mac%20` plus a stray parameter. Build the URL with `URLComponents`/`URLQueryItem`.
- **VERIFIED (low)**: `fetch` ignores the HTTP status and turns non-JSON into `[:]` (`:114-115`). A 429 or 5xx becomes
  "We couldn't find that one" for a barcode (`ScanView.swift:208-210`) or an empty result list for search, instead of
  the error state.
- **DESIGN RISK**: force-unwrapped `URL(string:)!` with the raw barcode interpolated into the path (`:32`), and at `:40`.
  The manual-entry path feeds free text here. On the iOS 18 deployment target `URL(string:)` percent-encodes rather than
  returning nil, so this is not flagged as a crash, but it should go through `URLComponents` with a digits-only check.
- **DESIGN RISK**: the User-Agent hard-codes a personal email address and "Victoria/1.0"
  (`OpenFoodFactsService.swift:28`) in a public portfolio repo.
- **DESIGN RISK**: search uses the legacy `cgi/search.pl` endpoint; no caching of barcode lookups.
- **OK**: search is debounced 350 ms with cancellation (`RecentFoodsSheet.swift:273-283`); a barcode lookup cannot
  double-fire (`ScanView.swift:197`); parsing is pure, per-nutrient, and sanity-checked.

---

## 9. Export backup / import

File: `Victoria/Services/DataExport.swift` (106), entry point `SettingsView.swift:85-91`.

- **V15 — VERIFIED**: there is no import. No `fileImporter`, no decode of `Backup` outside the round-trip test. The header
  comment (`DataExport.swift:5-8`) calls it "a real backup so reinstalling … can never feel like losing it all".
- **VERIFIED: the export is lossy.**
  - Not exported at all: `SleepEntry`, `VitalsEntry`, `DetectedWorkout`, `ExerciseEntry` (the sets/reps/weights of every
    gym session), `CoachPlan`, `CoachMemory`, `ChecklistItem`, `AchievementUnlock`.
  - Profile: only 5 fields (`:23-29`); sex, birth date, height, activity, pace, units, reminders and overrides are dropped.
  - Food: no id, favourite flag, barcode, calorie range, confidence or created date (`:30-34`).
  - Weight: no source or HealthKit UUID (`:35`), so a future import could not dedupe against Health.
  - Workouts: `title` is filled with `focusesRaw` (`:69`).
- **DESIGN RISK**: no format version field (only `appVersion`); fetches are unsorted so output order is not stable;
  it runs synchronously on the main actor and loads every `FoodEntry` including inline photo blobs; the temp file is
  never removed; the filename date is UTC (`:85`).
- **OK**: failures are logged and return nil; dates are ISO 8601; the seed chat message is excluded.

---

## 10. Concurrency

- **Language mode**: `SWIFT_VERSION: "5.0"` (`project.yml`), so none of the isolation below is compiler-enforced.
- **OK — tracker refresh single-flight**: `trackerRefreshInFlight` (`RootView.swift:21,117-120`) covers the cold-launch
  double fire of `.task` and `.active`; `GoogleHealthSync.isRefreshing` (`GoogleHealthSync.swift:30-31,43-45`) covers
  Settings "Sync now".
- **DESIGN RISK — the two guards do not exclude each other.** The HealthKit importers capture `existing` from the
  `@Query` arrays as an argument and then await the HealthKit query before merging
  (`HealthKitSleepWorkouts.swift:104-106,196-198,280-285`, `HealthKitSteps.swift:75-77`). A Settings-initiated Google
  sync that inserts a row inside that await is invisible to the HK merge, which then inserts a duplicate for the same
  day. The window is the duration of one HK query. Re-fetch from the context after the await, as the Google path does.
- **DESIGN RISK — the guard lives in view state.** Moving the refresh into a `@MainActor` coordinator object would make
  it testable and independent of view identity.
- **OK — main-actor discipline**: `GoogleHealthAuth`, `CloudKitSyncService`, `BuddyViewModel` and `LocationService` are
  `@MainActor`; `@Model` objects are converted to `Sendable` wire types before any await (`NudgeWire`,
  `ImportableWeight`, `ImportableWorkout`); the HealthKit readers return value types.
- **OK — `Diagnostics`**: serial queue, `@unchecked Sendable` justified (`Diagnostics.swift:12-17`). Performance note:
  whole-file rewrite per line.
- **VERIFIED — parallel state**: two `BuddyViewModel` instances with independent `isLinked`, `isPublishing`,
  `lastPublishFailed` and service caches (V9, V17). `DiagnosticsView` creates a third (`Diagnostics.swift:90`), whose
  `init` also fires `announceMyCode`.
- **DESIGN RISK — unstructured tasks at lifecycle edges**: `Task { await publish() }` on background
  (`BuddyAutoPublisher.swift:193`, `BuddyHomeView.swift:151`), `Task { await self.announceMyCode() }` in an initialiser
  (`BuddyViewModel.swift:117`), the fire-and-forget revoke (`GoogleHealthAuth.swift:92`). None are cancellable or tied to
  a background-task assertion.
- **DESIGN RISK — global mutable state**: `Theme.current` (`Shared/Theme.swift:86`).
- **Foreground re-entrancy, summarised**: on `.active` three things start at once — the tracker refresh
  (`RootView.swift:95-102`), the auto-publisher retry (`BuddyAutoPublisher.swift:200-203`) and, if the hub is alive, a hub
  refresh (`BuddyHomeView.swift:139-146`). They are independent except for the publish conflict in V17. A step-count
  change from the tracker refresh then triggers one more debounced publish through `dataSignature`.
- **DESIGN RISK**: `TravelSignal.checkNow()` runs only in the launch task (`RootView.swift:79`), not on foreground, so a
  flight taken with the app suspended is not detected until the next cold launch.

---

## 11. Project hygiene and organisation

### The 20 largest Swift files

Descriptions are from reading the file where it was in scope, otherwise from its type declarations and MARK sections.

| # | Lines | File | What it mixes |
|---|-------|------|---------------|
| 1 | 2518 | `Victoria/Features/Coach/CoachTools.swift` | One `enum`: tool names, bounds, JSON schemas, request parsing, validation, SwiftData writes and undo for every tool |
| 2 | 1597 | `Victoria/Features/Onboarding/OnboardingView.swift` | One `struct`: every onboarding page, coach voice, HealthKit connect, API-key entry, projection maths and profile persistence |
| 3 | 1316 | `Victoria/Features/Coach/CoachView.swift` | Chat screen plus 11 private types (bubbles, typing indicator, tool confirm cards, undo banner) and send/tool orchestration |
| 4 | 953 | `VictoriaTests/CoachToolsWriteTests.swift` | Test file |
| 5 | 860 | `Victoria/Features/Food/FoodLogView.swift` | Nutrients tab: day navigation, water card, steps card, macros, meal sections and mutations in one view |
| 6 | 839 | `Victoria/Features/Workouts/WorkoutLogFlow.swift` | Log flow plus 8 helper types (tiles, editor, add-machine sheet, a flow layout) |
| 7 | 828 | `Victoria/Features/Buddy/Services/CloudKitSyncService.swift` | 60-line runbook, pairing, two subscriptions, nudges, snapshot publish/fetch, DEBUG schema seeder, diagnostics probe, record mapping |
| 8 | 822 | `Victoria/Features/Coach/CoachContext.swift` | One `enum` building the whole coach context string; lives in Features but is service logic |
| 9 | 742 | `Victoria/Features/Achievements/AchievementsView.swift` | Grid, hero, earning logic, badge tile, detail sheet, tint mapping |
| 10 | 739 | `Victoria/Features/Settings/SettingsView.swift` | One `struct` with 12 sections, including export and DEBUG developer tools |
| 11 | 719 | `Victoria/Features/Checklist/ChecklistCard.swift` | Card UI, AI plan loading, a UserDefaults day cache, custom task sheet, a second flow layout, shimmer |
| 12 | 669 | `Victoria/Features/Dashboard/DashboardView.swift` | One `struct` for the whole Today screen plus derived maths |
| 13 | 642 | `Victoria/Services/AI/OpenAIClient.swift` | Out of scope (AI layer) |
| 14 | 639 | `Victoria/Features/Companion/CompanionCard.swift` | Animation state, tap-to-talk, target maths, hand-drawn face shapes, speech bubble |
| 15 | 629 | `Victoria/Features/Buddy/Views/BuddyFaceOff.swift` | View plus the scoring model (`FaceOffSide`, `FaceOffMetric`, `FaceOffTone`) and 6 subviews |
| 16 | 600 | `Victoria/Features/Food/ScanView.swift` | Scanner UI, lookup logic, nutrition-label text parsing, `DataScanner` wrapper |
| 17 | 569 | `Victoria/Features/Workouts/WorkoutsView.swift` | Tab view plus `WorkoutSummary` and `WorkoutStats` logic |
| 18 | 566 | `Victoria/Features/Weight/WeightView.swift` | Progress tab, chart, range enum, log sheet, persistence |
| 19 | 560 | `Victoria/Services/PlanService.swift` | Generate, review, prompts, research phase, result mapping, output schema |
| 20 | 543 | `Victoria/Features/Buddy/Views/BuddyViewModel.swift` | Identity persistence, pairing, inbox, publish queue, sync health, panda state with UserDefaults writes, error copy |

Next in line: `PhotoFoodFlow.swift` 507 (flow, two UIKit pickers, a `UIImage` extension, `MealTime`),
`RecentFoodsSheet.swift` 499, `AddFoodSheet.swift` 487.

### Structural findings
1. **`Features/Workout` vs `Features/Workouts`.** `Workout/` holds the legacy `WorkoutLogView.swift` (471) and
   `RunningAppCard.swift` (86). `WorkoutLogView` is reachable only through the `--demo-screen workout` launch argument
   (`RootView.swift:37`); `RunningAppCard` is used only by it. The shipping tab is `Workouts/`. The legacy `WorkoutEntry`
   model is still in the schema and is written only by `DemoSeed.swift:159`. For the other auditor: `CoachView.swift:21`
   and `CoachContext.swift:41,73,268,492` still read `[WorkoutEntry]`, which production never writes.
2. **`Victoria/Services/` is a flat folder of 37 files** mixing integrations (HealthKit, Open Food Facts, location,
   notifications, widget writer), pure domain maths (`NutritionMath`, `TrendCalculator`, `StreakCalculator`),
   AI services (`PlanService`, `CoachMemoryService`, `DailyBriefService`, …), a `UserProfile` extension, a 438-line
   static catalogue (`MachineCatalog`) and debug seeding.
3. **Merge functions sit on `HealthKitService`**, so the Google pipeline depends on the HealthKit type for its own writes.
4. **Models are in three places**: `Victoria/Models/`, `Features/Buddy/Models/`, `Features/Checklist/ChecklistItem.swift`.
   The schema list in `VictoriaApp.swift:11-40` is the only index.
5. **Logic under `Views/`**: `BuddyViewModel`, `BuddyAutoPublisher` (state struct, composer, view-model extension and the
   view), and the face-off scoring model.
6. **Dead or debug-only code shipped in Release**: `importTodaySteps`/`todaySteps`; `CalorieBudgetWidget` and
   `CalorieBudgetView`; `BuddyChallengeCard.swift` (241 lines, referenced only by its own previews); `unlink()` on both
   services; `BuddyLink`/`BuddySnapshot` as models; `DemoSeed`, `WidgetGalleryView` and the `--demo-*` arguments are
   described as DEBUG-only (`DemoSeed.swift:4-5`) but are not inside `#if DEBUG`, and `RootView.swift:60-63,75` consults
   them unconditionally.
7. **Duplicated logic**: two flow layouts (`WorkoutFlowLayout`, `ChecklistFlowLayout`); "today" totals for food, water and
   steps recomputed in `WidgetDataWriter`, `BuddyStateComposer`, `BuddyHomeView` and the dashboard; the basis-weight
   fallback of 150 repeated (`WidgetDataWriter.swift:27`, `BuddyAutoPublisher.swift:57-58`); container, app-group and
   keychain identifiers as string literals in `CloudKitSyncService.swift:71`, `WidgetSnapshot.swift:119`,
   `Diagnostics.swift:29`, `KeychainStore.swift:12`; UserDefaults keys as ad hoc literals, with
   `"buddy.myPairingCode.<id>"` built independently in `BuddyViewModel.swift:34` and `CloudKitSyncService.swift:171`.
8. **Naming**: target, folders, bundle ID, notification IDs and several user-visible strings still say Victoria while the
   product is Sprout (`HealthSettingsView.swift:84`, the Open Food Facts User-Agent, `TESTFLIGHT.md` title,
   `WidgetSnapshot.placeholder`). The persistence field `healthKitUUID` also holds `ghealth:` and `demo-` IDs
   (`DetectedWorkout.swift:15`); `sourceID` would be accurate.
9. **Root-level documents**: `RESEARCH_ai_native.md` (227 lines), `RESEARCH_onboarding.md` (263), `RESEARCH_social.md`
   (59), `DESIGN_SPEC.md` (57), `FUTURE_IMPLEMENTATIONS.md` (60), `GOOGLE_HEALTH_SETUP.md` (62), `TESTFLIGHT.md` (107).
   `DESIGN_SPEC.md` describes a single forced-dark lime theme, which no longer matches the two-skin app.
   `RESEARCH_social.md` states the buddy card shows "presence + vibe, NEVER magnitude", which the full-stats share
   contradicts. `AGENTS.md` is an untracked copy of `CLAUDE.md` differing only in the title line. For a portfolio repo
   these belong under `docs/`, with stale ones marked as historical.
10. **Generated project is committed and drifting**: `Victoria.xcodeproj/project.pbxproj` is tracked and currently
    modified; one `xcuserdata` file is tracked despite `.gitignore`. Version numbers are repeated in four places in
    `project.yml` and not referenced by the widget plist.
11. **Test coverage in this scope**: good for Google parsing and merges, steps merge, Open Food Facts parsing, milestones
    and travel. None for the pairing state machine, `BuddyViewModel`, `BuddyStateComposer` (where V1 lives),
    HealthKit sleep aggregation (V7), widget snapshot staleness, `NotificationService`, or the export field set.

### Proposed target layout (nothing moved)

```
Victoria/                              (rename to Sprout/ only together with the target)
  App/                 VictoriaApp, AppDelegate, RootView, MainTabView, AppSchema (schema list + container factory)
  Core/
    Models/            every @Model + CoreEnums (ChecklistItem moves here; Buddy models become structs)
    Persistence/       container factory with local fallback, mirror event logger, DataExport (+ import)
    Diagnostics/       Diagnostics, DiagnosticsView
    Security/          KeychainStore
    Config/            AppIdentifiers (container, app group, keychain service), DefaultsKeys
  Domain/              NutritionMath, NutritionSanity, TrendCalculator, StreakCalculator, RecoverySignal,
                       UserProfile+Targets, StepsSupport, MachineCatalog, FoodSuggestionEngine,
                       DailyInsightEngine, RecommendationEngine, DailyTotals (one "today" calculator)
  Integrations/
    Ingest/            TrackerMerge (steps/sleep/vitals/workouts/weight merges, overlay, dedup, source precedence),
                       TrackerRefreshCoordinator (the single-flight now in RootView)
    HealthKit/         HealthKitService (auth, readers, weight export), SleepAggregation (pure)
    GoogleHealth/      Auth, Client, Sync
    FoodDatabase/      OpenFoodFactsService
    Location/          LocationService, NearbyPlacesService, TravelSignal
    Notifications/     NotificationService, RemotePushRouter
    Widget/            WidgetDataWriter
  AI/                  Services/AI + Coach*/Plan*/DailyBrief/WeeklyReflection services, CoachContext, CoachTools (split)
  Features/
    Today/  Nutrition/  Progress/  Workouts/  Coach/  Onboarding/  Settings/
    Achievements/  Checklist/  Companion/  Plan/  WhatsNew/
    Buddy/
      Domain/          BuddySnapshotPayload, NudgeWire, BuddyMilestones, BuddyStateComposer, FaceOff scoring
      Sync/            BuddySyncService, CloudKitSyncService (split: pairing / nudges / snapshot / subscriptions),
                       CloudKitDiagnostics, LocalMockSyncService, BuddyStore (one shared instance)
      UI/              views only
  DesignSystem/
  Debug/               DemoSeed, WidgetGalleryView, legacy WorkoutLogView — all inside #if DEBUG
Shared/                WidgetSnapshot, Theme, WidgetViews, WidgetPixelArt
VictoriaWidgets/
VictoriaTests/         mirrored by area (Domain/, Integrations/, Buddy/, AI/)
docs/
  research/            RESEARCH_*.md
  design/              DESIGN_SPEC.md (marked historical)
  roadmap/             FUTURE_IMPLEMENTATIONS.md
  setup/               GOOGLE_HEALTH_SETUP.md, TESTFLIGHT.md, cloudkit-runbook.md (lifted from the service header)
```

---

## 12. Fix order I would defend

1. V1 (zero the full-data fields when not sharing; republish on toggle) — small change, privacy.
2. V2 + V3 + V4 as one pairing rework (typer never creates, set state after save, durable identity, unlink/re-pair),
   after checking S2 in the Dashboard.
3. S1 Dashboard check, and add mirror event logging so the answer is visible from a device.
4. V6 widget rollover.
5. V8 + V7 together: add `source` to sleep/vitals rows with precedence in the merge, fix night bucketing, add pure tests.
6. V9, V10, V11, V16, V17 by collapsing to one shared buddy store.
7. V5: either wire up weight export properly or remove the write permission and the usage string.
8. V12, V13, V14, V15, then hygiene.
