# Evaluation report

The ledger of what was measured and what was found, one numbered section per piece of
work, newest last. A default in the code cites the section that chose it; a section is
never rewritten after the fact, and a later result gets a new section that says what
it supersedes.

Every section says what was **verified** (run, with the output in hand), what was only
**read** (the code path was traced but not run), and what is still **open**.

| # | Section | Date |
|---|---|---|
| 1 | Baseline: what the app is and what passed before any change | 2026-11-22 |
| 2 | Why builds froze: the repository lived in an iCloud-synced folder | 2026-11-22 |
| 3 | Verification pass: defects found, what was fixed, what is open | 2026-11-22 |
| 4 | The AI layer becomes testable: a runtime seam, a model per task, one model profile | 2026-11-22 |
| 5 | The evaluation harness and its first three datasets | 2026-11-22 |
| 6 | The model line-up on 2026-11-22, and what it does to the current defaults | 2026-11-22 |
| 7 | Distribution: why the app stopped opening, and the ways to stop that recurring | 2026-11-22 |
| 8 | Continuous integration | 2026-11-22 |
| 9 | Test evidence for build 16, and what the tests do not cover | 2026-11-22 |
| 10 | First live comparison: ten models on three tasks, and four defects it found | 2026-11-22 |
| 11 | The widget that showed someone else's data | 2026-11-22 |
| 12 | Home and Gym: two surfaces and the switch between them | 2026-11-22 |
| 13 | The store returns what was put in: verification through the real store, and by SQL | 2026-11-22 |
| 14 | Prompts for whoever is using the app, re-measured; a discarded rewrite explained | 2026-11-22 |
| 15 | A character from a photo | 2026-11-22 |
| 16 | Settings that change what depends on them: the plan, kilograms, and where a key goes | 2026-11-22 |
| 17 | UI smoke flows: the app driven end to end, and what the accessibility audit found | 2026-11-23 |
| 18 | The rest of the label: eleven more nutrients, and "unknown" is never zero | 2026-11-23 |
| 19 | Buddy pairing and sync: nine defect groups closed | 2026-11-23 |
| 20 | The chat: a testable turn engine, paged history, selection, and named failures | 2026-11-23 |
| 21 | iCloud was backing up two of twenty models: the CloudKit schema, measured and fixed in Development | 2026-11-23 |
| 22 | Eight more tasks measured: four defaults changed, and two ways a reply was being lost | 2026-11-23 |

---

## 1. Baseline: what the app is and what passed before any change (2026-11-22)

Commit `3fc5c6c` ("Bump to Sprout 2.1 (build 15)"), the code of the last TestFlight
upload. Xcode 26.4 (17E192), iPhone 17 Pro simulator on iOS 26.4 (23E244).

**Verified by running:**

- `xcodebuild test -scheme Victoria`: **443 passed, 0 failed, 0 skipped**, 81 s wall clock.
- 179 tracked Swift files, 45,058 lines. 30 test files.
- A brand-new install opens its persistent store. The launch log shows
  `addPersistentStore… NSCocoaErrorDomain 512` and "Failed to stat path …/Application
  Support" on first launch; Core Data then creates the directory and retries. Afterwards
  `default.store` exists in the app-group container and the app's own
  "CRITICAL: … running IN-MEMORY" line was not logged. So the noise is benign.
- 19 compiler warnings in app code, among them Swift 6 concurrency warnings in
  `Features/Buddy/Services/LocalMockSyncService.swift` that become errors in Swift 6 mode.

**What did not exist:** any CI workflow, any UI test, any test that calls a model
client, any record of why a model was chosen other than argument
(`docs/MODEL_CHOICES.md`), any versioned schema or migration plan for the store.

**Read, not run:** `VictoriaApp.init` falls back to an in-memory store if the real one
fails to open. The user would be shown onboarding again and lose everything typed on the
next launch, with only a diagnostics line as trace. With no `VersionedSchema`, any future
model change that lightweight migration cannot handle takes that path. Open (section 3, L-S3).

## 2. Why builds froze: the repository lived in an iCloud-synced folder (2026-11-22)

The first test run of the day produced 562 bytes of log in eleven minutes, `git grep`
did not return in two, and five background agents stalled together.

**Verified:** `sample` of the stuck `xcodebuild` showed it blocked in
`-[NSFileCoordinator coordinateReadingItemAtURL:options:error:byAccessor:]` under
`Xcode3Project initWithFilePath:`. `~/Documents` carries the
`com.apple.file-provider-domain-id` attribute (iCloud Desktop & Documents), and
`fileproviderd`, `cloudd` and `mds` were the top three processes by CPU. The same
checkout cloned to `~/dev/GitHub/sprout` ran the full suite in 81 seconds.

This is also the most likely source of two older problems recorded in the project
notes, both of which are things iCloud does to a folder it manages: the
"resource fork, Finder information, or similar detritus" code-signing failures (hence
the `xattr -cr` build phase in `project.yml`), and the stray `Victoria 2.xcodeproj`
(an iCloud conflict copy; `.gitignore` already had a rule for it). That link is
inferred, not tested.

**Done:** all work from this section on is in `~/dev/GitHub/sprout`. The old folder is
untouched. `git fetch` from it brought over one commit that had never been pushed
(`3fc5c6c`, the 2.1 bump).

## 3. Verification pass: defects found, what was fixed, what is open (2026-11-22)

Three independent read-throughs of the code (onboarding and lifecycle; data in and out;
the AI layer). The two long reports are kept whole in `docs/audits/2026-11-22/`. Every
item below was found by **reading**; none was reproduced on a device. The four marked
fixed were re-read by a second pass before the fix and have a regression test.

### Fixed in this change

| ID | Defect | Fix | Test |
|---|---|---|---|
| D-V1 | **Privacy.** With "Share my full stats with your buddy" off, weight trend, goal weight, calories, macros and today's food names were still written to the CloudKit **public** database; only the buddy's screen hid them. Three layers each had a comment saying the caller blanks them, and none did (`BuddyAutoPublisher.swift:60-99`, `BuddySyncService.swift` init, `CloudKitSyncService.swift:543-559`). | `BuddySnapshotPayload.init` blanks every opt-in field when `sharesFullData` is false, and `CloudKitSyncService.publish` strips again at the upload. | `VerificationFixesTests` (4 tests) |
| L-B1 | The Nutrients tab kept the day it was opened on. Left in the background overnight, it read "Yesterday" and saved a new meal to the previous day (`FoodLogView.swift:43`). | `FoodLogDay.rolledForward`: on becoming active and on `NSCalendarDayChanged`, a view that was showing today moves to the new today; a day the user browsed to is left alone. | 6 tests, including a clock moved back and the 25-hour DST day |
| L-B3 | "Your goals changed since this plan was built" never cleared: the flag is keyed by plan id, and a rebuild updates the row in place with the same id. | `CoachPlan.clearGoalsChanged()`, called by `PlanService.generate` on success. | 1 test |
| L-B4 | A protein target set through Vita with no plan was reset to the computed value at the next launch (`RootView.syncPlanTargets` wrote the plan's value, 0 without a plan). | `PlanTargetSync.overrides`: with no plan the protein override is left as the user set it. | 4 tests |

The buddy fix is verified at the level of the payload that is uploaded. It has **not**
been observed against CloudKit, and records already in the public database keep whatever
they held until that user's next publish overwrites them.

### Open, ranked. Lifecycle (`audit-lifecycle.md`)

| ID | Defect | Severity |
|---|---|---|
| L-B2 | With an adaptive plan, changing goal direction, pace, activity level or weight does not move calories or protein until the plan is rebuilt, and the Settings footer says the opposite. Pace and activity changes raise no notice. | high |
| L-B7 | Vita's `set_units` relabels every weight as kg without converting, then stores a typed "72" as 72 lb. The trend collapses and, with no plan, the calorie target follows it down. There is no kg support elsewhere. | high (data) |
| L-B9 | Delete and reinstall as an OpenAI user: the provider choice (UserDefaults) resets to Anthropic while the key (Keychain) survives. The onboarding and Today paste fields then store an OpenAI key in the Anthropic slot. | high for reinstall |
| L-B10 | Reinstall with Google Health connected: shows connected (tokens in Keychain) but cannot refresh (client ID was in UserDefaults). | medium |
| L-B11 | Reinstall mints a new buddy identity and strands the partner on a frozen snapshot. | medium |
| L-B5 | Widgets show yesterday's totals as today's until the app is opened; the trend widget colours and "to go" are loss-only; a widget added before onboarding shows sample data under the name "Victoria". | medium |
| L-B6 | The 7- and 14-day consistency achievements count auto-imported Apple Health steps as logged days, so they unlock on day one. | medium |
| L-B8 | Entries added from the Nutrients tab are stamped at local midnight, so flying west moves food history a day earlier. | medium |
| L-B12 | After onboarding, reminders are not scheduled and the permission prompt does not appear until the next cold launch. | medium |
| L-B13 | Apple Health: `saveWeight` has no caller and import is a manual button, while the usage strings and onboarding copy promise two-way sync. The app requests a write permission it never uses. | medium (also an App Review risk) |
| L-B14…B24 | Onboarding note is always the template on first install; stale setup card; travel check only on cold launch; Vita's streak differs from the header; height display for cm values; recap cache rolls at UTC midnight; water reset shows one number and applies another; weigh-ins cannot be edited or deleted; start weight used as current weight in two places; reaching the goal weight changes nothing. | low to medium |
| L-S1 | *Suspected:* a second `UserProfile` and an extra weigh-in if onboarding finishes before the iCloud import lands. Nothing de-duplicates. | check on a device |
| L-S3 | *Suspected:* the in-memory fallback uses `try!` and would crash if the failure came from CloudKit configuration. No versioned schema. | check; design |

### Open, ranked. Data in and out (`audit-data-sync.md`)

| ID | Defect | Severity |
|---|---|---|
| D-V2 | Pairing: a mistyped or not-yet-uploaded code returns "You're connected!". | high |
| D-V3 | The link is persisted before the claim is saved. | medium |
| D-V4 | `unlink()` has no caller; identity lives only in UserDefaults (same root as L-B11). | medium |
| D-V7 | HealthKit sleep is bucketed by each sample's end date, splitting a night at midnight. | medium |
| D-V8 | HealthKit and Google Health rewrite the same rows on every refresh; offline, nights regress to HealthKit values and the HealthKit pass can zero half of a vitals row. | medium |
| D-V9 | The auto-publisher reads `isLinked` once at init, so it stays off after pairing until relaunch. | medium |
| D-V10/11 | Streak nudges re-fire daily; a milestone is consumed before a failed send. | low |
| D-V14 | The silent-push handler returns before its work runs. | low |
| D-misc | Food search does not escape `&`; backup is export-only and lossy; HealthKit weight import inserts inline instead of through the shared merge functions. | low |
| D-S | *Suspected, needs the CloudKit Dashboard:* the Production schema may not include the `CD_*` record types of the newer models; public-database security roles (claiming a code and marking a nudge read both write to another user's record). | check |

### Found while building the evaluations (verified by reading the prompts)

| ID | Defect |
|---|---|
| A-1 | Prompts are written for one specific person. `InsightPhraser` ("a warm, upbeat weight-loss buddy texting … her day … Never push restriction"), `DailyBriefService` ("writing your friend her short morning note", "Her name:"), `FoodSuggestionService` ("Here is her current data"), `CoachPromptService` ("in her voice"), `ChecklistPlanService` ("she actually does"). For a man on a gain goal the framing and the pronoun are wrong, and the project's own rule says no hardcoded names or goal-direction copy. The `dailyBrief` evaluation scores wrong-person pronouns in the output, so the effect will be measured, not assumed. |
| A-2 | The coach exposes one tool call per turn (`ChatTurn.toolUse` is the first block; the rest are dropped). "Log a banana and two waters" does one of them. By design per the comment, but untested and not told to the user. |
| A-3 | `UserProfile.aiModelFood` / `aiModelChat` default to `claude-sonnet-4-6` and are read by nothing. |
| A-4 | `DemoSeed` uses `Int.random`, so the demo profile is different every time; fine for a demo, unusable as a test fixture (the evaluations use fixed fixtures in `EvalFixtures.swift`). |
| A-5 | Hosted unit tests launch the real app against the real on-disk store with CloudKit mirroring attempts in the log. They pass, but they are not isolated from the store. |

### Not a defect, checked

- No expiry or time-bomb logic exists in the app (searched for hardcoded dates, expiry
  and receipt checks). The app stopped opening because of TestFlight, section 7.
- All 20 `@Model` types meet CloudKit's rules (defaulted attributes, no unique
  constraints, no required relationships).
- A fresh install opens its store (section 1).
- The secret scan over all 85 commits finds no secret. Its one hit is the line in
  `DailyBriefService` that names the UserDefaults entry for the cached brief, recorded
  in `.gitleaksignore` with that reason.

## 4. The AI layer becomes testable: a runtime seam, a model per task, one model profile (2026-11-22)

**Before:** both clients read their key from the Keychain in `init`, called
`URLSession.shared` directly, and logged token usage as a string. No test could run a
client, and no harness could run one against a chosen model without changing global
state. The model was chosen per *tier* (cheap, strong, heavy), so there was nowhere to
record that task X runs on model Y because a measurement said so. The OpenAI client
decided endpoint, token parameter and reasoning effort by string prefix (`gpt-5`,
`gpt-5.6`).

**Changed:**

- `AIRuntime` (task-local): a scoped provider, key, model, reasoning effort, transport
  and usage sink. Nil in the shipped app, where behaviour is unchanged.
- `AIUsage`: token accounting normalized across providers (Anthropic's input count
  excludes cached tokens, OpenAI's includes them), with latency and attempts.
- `AITask`: fifteen tasks, one per distinct prompt and output contract. Every call site
  names its task and asks `AIConfig.model(for:)`. The model-less client overloads were
  deleted, so a call that does not name a model does not compile.
- `AIConfig.measuredDefaults`: the per-task table, empty today. A row goes in only with
  the section that measured it; a test refuses a row without that citation.
- `OpenAIModelProfile.resolve`: endpoint, reasoning and effort rules decided from the
  model's family and version in one place. From gpt-5.6 on, every call (plain chat
  included) goes to `/v1/responses`. A `gpt-6.x` model previously resolved to Chat
  Completions with `max_tokens`, which those models reject.

**Verified:** every task resolves to the same model as before the change
(`AITaskModelTests` pins all 30 task-provider pairs to the literal strings in the
previous code). 32 new tests, most of which run the real clients against scripted provider responses:
headers, model override, usage arithmetic for all three wire formats, the single retry
on 429/529, no retry on 401, empty and truncated replies, and a whole meal estimate end
to end. Suite after this section's change: **475 passed, 0 failed, 0 skipped**; with the
section 3 fixes and their 15 tests, **490**.

**Not verified:** no request built by the new Responses plain-chat path has been sent
to OpenAI. It is tested against the documented response shape only. The first live
evaluation is its first real call.

## 5. The evaluation harness and its first three datasets (2026-11-22)

The method, from the practice surveyed in `docs/audits/2026-11-22/research-standards.md`
section D: a labelled dataset per task, graded by code wherever a rule can decide,
every candidate on the identical cases with repeats, accuracy with an interval beside
cost, tokens and latency, and the cheapest candidate within noise of the best as the
default. The evaluations run the app's own code (`FoodPhotoAnalyzer.analyze`,
`CoachContext.systemParts` + `CoachTools.schemas` + `CoachTools.parse`,
`DailyBriefService.pick` + `rephrase`) under a scoped runtime, so the prompt, the wire
translation and the parser under test are the ones that ship.

| Dataset | Cases | Ground truth | Pass rule |
|---|---|---|---|
| `meal_describe/v1` | 14 | USDA FoodData Central SR Legacy per-100 g values, fetched 2026-11-22, times the grams stated in the description. Each row cites its FDC ids. | total calories within 20% |
| `coach_tool_choice/v1` | 34 (25 should act, 9 should answer in prose) | The action the app resolves the call to, with its value. Written by reading the tool descriptions. | right decision, right action, right value |
| `daily_brief/v1` | 13, covering all six rungs of the template ladder | The template's own numbers. | every number kept, none invented, no wrong-person pronoun |

**Verified offline (19 tests, 16 run and pass, 3 are the live evaluations and skip without a key):**

- The graders, against hand-written outputs, including the tolerance edges
  (126 kcal passes against 105, 127 does not).
- Every dataset row decodes. The meal truths satisfy a 4/4/9 check within 12%. The
  ladder picks the topic each brief case claims.
- For 24 of the 25 "should act" coach cases, a hand-written correct tool call is
  accepted by the app's own parser **and** passes the case's label (the one without
  such a check is `food-eggs`). This caught a wrong assumption of the author's
  (`log_workout` takes `kind: "run"`, not `"cardio"`) before any money was spent on it.

**Limits, stated so the numbers are not over-read:**

- 14 to 34 cases resolve only large differences. At an 80% pass rate, n = 30 gives a
  95% interval of about ±14 points.
- `meal_describe/v1` states every portion in grams. It measures food knowledge and
  arithmetic, not portion estimation. The USDA demo key rate-limited the fetch at 9 of
  24 planned ingredients; `fetch_usda.py` resumes from its cache.
- No meal-photo dataset yet. Nutrition5k (CC BY 4.0, 5,006 plates) is the public ground
  truth, and published per-dish calorie error for general vision models on it is 30 to
  45% (Mu, Sun and He, ACM BCB 2025). Downloading a subset is a decision for the owner.
- The coach labels are one person's reading of intended behaviour and need the owner's
  review. First turn only.
- Twelve of the fifteen tasks have no evaluation yet.

**No live run has been made.** No model has been compared and no default has changed.
Section 6 gives the candidates and the cost of the first run.

## 6. The model line-up on 2026-11-22, and what it does to the current defaults (2026-11-22)

Read from the vendors' own model, pricing and deprecation pages on 2026-11-22
(`research-standards.md` section E has every source). Prices are USD per million
tokens, input / output.

| Tier | Current default | Its status today | Newer candidates |
|---|---|---|---|
| Cheap, OpenAI | `gpt-4.1-mini` 0.40 / 1.60 | **Deprecated. Shuts down 2027-01-14.** OpenAI's listed replacement is `gpt-6-luna`. | `gpt-6-luna` 0.10 / 0.50; `gpt-5.6-luna` 0.20 / 1.20 |
| Cheap, Anthropic | `claude-haiku-4-5` 1 / 5 | Active; its "not retired before" date (2026-10-15) has passed, so a 60-day notice can come at any time. | `claude-haiku-5-5` 0.10 / 0.50 |
| Strong, OpenAI | `gpt-5.6-terra` 2 / 12 | Active. | `gpt-6.1-terra` 1 / 5; `gpt-6.2-sol` 2 / 10 |
| Strong, Anthropic | `claude-sonnet-5` 2 / 10 | Active until at least 2027-06-30. | `claude-sonnet-5-5` 2 / 10 with a cheaper cache read; `claude-haiku-5-5` |
| Heavy, OpenAI | `gpt-5.6-sol` 4 / 20 | Active; **promotional price ends 2026-11-30**, later price not published. | `gpt-6.2-sol` 2 / 10; `gpt-6.2-astra` 8 / 40 |
| Heavy, Anthropic | `claude-opus-4-8` 5 / 25 | Active until at least 2027-05-28. | `claude-opus-5-5` 4 / 20 |

What follows from that, before any measurement:

- One default has a shutdown date seven weeks out. That replacement has to be chosen
  and shipped whether or not anything else changes.
- On both providers the newest cheap model costs a tenth of the current cheap default.
  Whether it is good enough for the strong-tier tasks is exactly the question the
  evaluations exist to answer; nothing here assumes it.
- Every OpenAI candidate is a reasoning model. Reasoning tokens are billed as output
  and count against the output cap, and the rewording tasks have caps of 80 to 420
  tokens. "Usable" is therefore the first column to read for those tasks.
- Things known only from documentation and not yet from a live call: whether forced
  tool choice is accepted by the always-thinking Anthropic models; whether
  `prompt_cache_options` is accepted by the 6.x family; the per-image price of
  OpenAI's current image models (the vendor publishes a calculator, not a table).
- `docs/MODEL_CHOICES.md` (2026-07-12) argued each default from price and release
  notes. It stays as the record of that reasoning; it is no longer how a default is
  chosen.

**The first run, when approved:** the three evaluations on eight candidates (the four
current defaults that are still candidates plus `claude-haiku-5-5`, `claude-sonnet-5-5`,
`gpt-6-luna`, `gpt-6.1-terra`), three repeats. The coach evaluation dominates the cost:
34 cases × 3 repeats × about 7,000 input tokens is roughly 0.7 M input tokens per model,
about $1.50 on a $2 model before caching and under 10 cents on the two $0.10 models.
The other two are a few cents per model. **Estimated total: under $10.** That figure is
an estimate from token counts, not a measurement; the run's own `summary.md` will carry
the measured cost.

## 7. Distribution: why the app stopped opening, and the ways to stop that recurring (2026-11-22)

**Verified:** the last Sprout archive on this Mac is dated 2026-07-13 (2.1, build 15).
Apple: "Each build is available to test for up to 90 days, starting from the day the
developer uploads their build", after which "you'll no longer be able to open the beta
build." Ninety days from 2026-07-13 is 2026-10-11. Nothing in the app expires
(section 3). `main` is still that commit, and an Apple Distribution certificate is now
in the keychain, which was the blocker in July.

**To get it open again:** upload a new build. Installing over the expired one is an
in-place update of the same bundle id, which is expected to keep the app's data, and
the store is also mirrored to each user's private iCloud database. Apple's pages do not
state that data survives, so that is **unconfirmed** until seen on one phone. What does
destroy local data is deleting the app first; nobody should do that.

**Ways to not expire** (Apple sources in `research-standards.md` section A):

| Option | Review | Expires | Fit |
|---|---|---|---|
| TestFlight with a scheduled re-upload | none for internal testers | 90 days per build, renewed by the schedule | Works today. Xcode Cloud can archive and upload on a schedule with Apple-managed signing (25 free hours a month). A GitHub Actions schedule needs an App Store Connect API key as a repository secret, and scheduled workflows in a public repository are disabled after 60 days without repository activity. |
| App Store, unlisted | full App Review once per version, plus a request form | never | The only route with no expiry and no discoverability: installable by anyone with the link, absent from search. Apple's examples are organizational; whether a personal app is approved is unknown. |
| App Store, public | full App Review | never | Makes the app public. |
| Ad hoc | none | about a year (profile), 100 registered devices | Manual yearly reinstall, no auto-update. |

**What App Review would raise** (guideline numbers in the research file): 5.1.3(ii)
says apps "may not store personal health information in iCloud", and this app mirrors
weight and food logs to CloudKit; 5.1.2(i) requires explicit consent before personal
data goes to a third-party AI; 2.1 means the reviewer needs a working key or a demo
mode; and L-B13 above (a HealthKit write permission that is requested and never used).
None of these apply to internal TestFlight.

**Adding a third person** is a TestFlight invitation today. The photo-to-pixel-avatar
idea needs an OpenAI key regardless of the user's chat provider (Anthropic's models do
not generate images), and A-1 above (prompts written for one person) has to be fixed
first or the new user is addressed as someone else.

## 8. Continuous integration (2026-11-22)

`.github/workflows/ci.yml`, four jobs on every pull request and every push to `main`:

| Job | Runs on | What it proves |
|---|---|---|
| `test` | `macos-26`, Xcode 26.4 | The project regenerates from `project.yml`; the unit suite passes; the count is read from the result bundle and must be at least 490 (so "no tests found" cannot read as green); coverage by target in the job summary; the evaluation harness's offline self-tests pass with exactly the three live evaluations skipped. |
| `release-build` | `macos-26` | The Release configuration compiles. |
| `secrets-scan` | `ubuntu-latest` | gitleaks over the full history. |
| `tooling` | `ubuntu-latest` | The Python and shell tooling parses, and `meal_describe/v1.jsonl` is byte-for-byte what its build script produces. |

No job uses a secret, a key or a signing identity; the paid evaluations never run in
CI. Actions are pinned to commit SHAs with Dependabot proposing updates. Standard
macOS runners are free for a public repository.

**Verified locally:** `tooling/check_xcresult.py` returns 0 on the passing bundle and 1
when the minimum is not met; gitleaks is clean over 85 commits; the scripts parse.

**Not verified:** the workflow has never run on GitHub. The simulator-creation step,
the runner's Xcode 26.4.1 against a project developed on 26.4, and the unsigned Release
build are each untested until the branch is pushed. Expect the first run to need a fix.

## 9. Test evidence for build 16, and what the tests do not cover (2026-11-22)

`docs/test-evidence/v2.1.0-b16/`, captured by `tooling/evidence/capture.sh` from the tree
that was then committed with it (the files were uncommitted at capture time and the
manifest lists them). **Verified by running:**

| Gate | Result |
|---|---|
| Unit suite | **491 passed, 0 failed, 0 skipped** (443 at the start of the day) |
| Evaluation harness self-tests | 16 passed, 3 skipped (the live evaluations) |
| Release build | succeeded |
| Secret scan, full history | no leaks |
| Signed device archive of 2.1 (16) | `ARCHIVE SUCCEEDED` (built separately; not exported or uploaded) |

**The number that matters more than 491: the tests execute 19.1% of the app's lines**
(9,143 of 47,820; the widget extension 4.1%). The suite is deep where the logic is pure
(nutrition maths, trend, streaks, merges, parsers, the tool parser) and absent where the
app is a screen or a network conversation.

`VictoriaTests/LEDGER.md` lists every test file with the invariant it protects, and the
logic no test reaches. The ten highest-risk untested areas, from that ledger:

1. The coach's turn loop in `CoachView` (confirm gate, depth cap, undo, memory
   write-back). It lives inside a view and cannot be called from a test as written.
2. `CloudKitSyncService`: the pairing handshake, the public-database publish, record mapping.
3. `VictoriaApp`: the full 20-model schema is never opened in a test; the silent
   in-memory fallback; no migration plan.
4. `BuddyViewModel`'s publish queue and state.
5. `BuddyStateComposer.compose` (what a buddy is shown).
6. Anthropic `chatWithTools` response handling (several tool calls in one turn, a turn cut
   off mid-tool-call).
7. Google Health token exchange and refresh.
8. Seven coach tools with no test anywhere, and four more tested for parsing only.
9. `PlanService.generate` and `review`.
10. `ScanView.parseNutritionLabel`, the label OCR parser.

Tests the ledger judged able to fail for reasons other than a defect (**read, not
observed failing**): `TravelSignalTests.testCheckNowRecordsShiftAndCurrentExpires` in the
weeks when US and EU daylight saving are out of step; tests in `BuddyMilestones`,
`CoachContextItems`, `HealthTrackerImport` and `CoachToolsWrite` that read the wall clock
and can straddle midnight; `DailyBriefTests.testBigDaySteadyHeartIsCrossSignal`, which
depends on the locale's number formatting; `OpenAIProviderTests.testPlanModelFollowsProvider`,
which fails if a plan-model override is set on the simulator. None failed today.

**Layers that do not exist:** UI tests (no XCUITest target), snapshot tests, migration
tests, any test against CloudKit, any performance test, a test plan file. The
recommended order for adding them is in `research-standards.md` section B.11; the next
two by value are SwiftData integration tests that run every ingest path twice on the
production schema in memory, and three to five UI smoke flows seeded by launch argument
with a scripted model.

**What "verified" covers for this build.** The four fixes of section 3 are verified at
the level of their unit tests. Nothing in this change was exercised in the running app's
UI, no request was sent to a model provider, nothing was sent to CloudKit, and the CI
workflow has not run. The first live evaluation doubles as the first real request
through the changed clients on both providers and should come before an upload.

## 10. First live comparison: ten models on three tasks, and four defects it found (2026-11-22)

Approved by the owner in the session. Ten candidates (the four current defaults and six
newer models), three repeats of every case, through the app's own code paths.
**3,636 graded attempts; measured spend $6.23** from the token counts in the records
and the list prices in `Evals/prices.json` (the estimate in section 6 was "under $10").

| Run (`Evals/runs/`) | Evaluation | Notes |
|---|---|---|
| `20261123-052445-MealDescribe` | pilot, 3 models, 2 cases | first live request through the changed clients on all three wire paths |
| `20261123-052539-MealDescribe` | `meal_describe/v1` | |
| `20261123-052935-DailyBrief` | `daily_brief/v1` | superseded: grader counted "fourteen" as a dropped number |
| `20261123-053133-CoachToolChoice` | `coach_tool_choice/v1` | superseded: found the water defect below; one label graded calories without quantity |
| `20261123-054215-DailyBrief` | `daily_brief/v1` | grader fixed; found the template conflict below |
| `20261123-054403-CoachToolChoice` | `coach_tool_choice/v2` | after the `strict: false` fix |
| `20261123-054917-DailyBrief` | `daily_brief/v1` | after the template fix; the run the brief decision rests on |

Two of the first runs are superseded because the *grader* or a *label* was wrong, found by
reading the failures one by one rather than trusting the pass rate. Both graders now have
tests for the case that fooled them. The superseded runs are kept.

### Results the decisions rest on

Pass rate with its 95% interval, and measured cost per 1,000 calls. **Bold** is a current default.

| Model | list $ in / out | Meal description (14×3) | $/1k | Coach tool choice (34×3) | $/1k | Daily brief (13×3) | $/1k |
|---|---|---|---|---|---|---|---|
| `claude-haiku-5-5` | 0.10 / 0.50 | 100% (92–100) | 0.32 | 100% (96–100) | 0.33 | 100% (91–100) | 0.07 |
| **`claude-haiku-4-5`** (cheap tier) | 1 / 5 | 81% (67–90), 83% usable | 2.75 | 90% (83–95) | 2.68 | 100% (91–100) | 0.51 |
| **`claude-sonnet-5`** (strong tier) | 2 / 10 | 98% (88–100) | 6.17 | 100% (96–100) | 6.14 | 97% (87–100) | 1.34 |
| `claude-sonnet-5-5` | 2 / 10 | **0% usable** | n/a | 100% (96–100) | 5.09 | 97% (87–100) | 1.48 |
| `gpt-6-luna` | 0.10 / 0.50 | 100% (92–100) | 0.11 | 100% (96–100) | 0.20 | 100% (91–100) | 0.04 |
| `gpt-5.6-luna` | 0.20 / 1.20 | 98% (88–100) | 0.27 | 99% (95–100) | 0.39 | 100% (91–100) | 0.10 |
| `gpt-6.1-terra` | 1 / 5 | 100% (92–100) | 1.09 | 97% (92–99) | 1.57 | 100% (91–100) | 0.43 |
| **`gpt-5.6-terra`** (strong tier) | 2 / 12 | 100% (92–100) | 3.09 | 99% (95–100) | 3.82 | 100% (91–100) | 0.96 |
| `gpt-6.2-sol` | 2 / 10 | 100% (92–100) | 2.11 | 100% (96–100) | 3.27 | 100% (91–100) | 0.89 |
| **`gpt-4.1-mini`** (cheap tier, deprecated) | 0.40 / 1.60 | 100% (92–100) | 0.34 | 87% (79–92) | 0.85 | 90% (76–96); 77% and 92% in the two earlier runs | 0.16 |

Latency (p50) was 0.8 to 1.8 s for every model on the coach and brief tasks and 1.6 to
3.3 s on the meal task; it does not separate the candidates.

### Four defects the comparison found

None of these was known, and none would have been found by reading release notes.

1. **Shipped bug, fixed and re-measured: "log 20 oz of water" logged one bottle on the
   current OpenAI default.** On the Responses API an omitted `strict` flag makes every tool
   property required ([OpenAI function calling guide, "Strict mode"](https://developers.openai.com/api/docs/guides/function-calling)),
   so the model filled the optional `containers` with 1 beside `oz: 20`, and the app's
   parser prefers the container count: 16.9 oz logged instead of 20. All five Responses
   models failed the case 3 of 3; `gpt-4.1-mini` (Chat Completions) and every Claude model
   passed. Fix: the coach's tools are sent with `strict: false`. After the fix all five
   pass 3 of 3, and `gpt-5.6-terra` went from 94% to 99% overall. The same cause produced
   an edit that zeroed a food's macros once on `gpt-5.6-luna`; not seen after the fix.
2. **`claude-sonnet-5-5` cannot run any structured feature.** The API answers
   `tool_choice: type "tool" and "any" are not supported for this model`. Seven tasks
   (meal photo and description, food suggestions, progress summary, checklist, coach
   prompts, plan build and review) force a tool call to get structured output. The newest
   Sonnet is therefore not a drop-in upgrade for the strong tier, whatever its price.
   Open: move those calls to the provider's structured-output parameter and measure again.
3. **The current Anthropic default returns a meal estimate the app cannot read about 1
   time in 40.** `claude-sonnet-5` once returned `items` as a string; `claude-haiku-4-5`
   omitted `total_calories` in 7 of 42. The user sees an error and retypes.
   `claude-haiku-5-5` and every OpenAI model returned a valid estimate 42 of 42.
4. **App copy defeated its own guardrail, fixed and re-measured.** The "back after a few
   days" template said "nothing to make up", and the rewording guardrail throws away any
   rewrite containing "make up for". Models echo the phrase, so that paid rewrite was
   discarded 3 of 3 times on `claude-haiku-5-5` and `gpt-6.2-sol`. The template no longer
   uses the phrase, a test now runs every template through the guardrail, and both models
   went from 92% to 100%.

Also seen, not acted on: `gpt-4.1-mini` set a step goal of 10,000 when the user only
wondered aloud whether 8,000 was too easy (2 of 3), and did not save a stated injury (3
of 3); `claude-haiku-4-5` asked a clarifying question instead of acting on "switch from
losing to gaining" (3 of 3) and on a 45-minute weights session (3 of 3).

### Decisions

| Task | Anthropic | OpenAI | Why |
|---|---|---|---|
| `dailyBrief` | `claude-haiku-4-5` → **`claude-haiku-5-5`** | `gpt-4.1-mini` → **`gpt-6-luna`** | Both pass 39 of 39 in the deciding run; the Anthropic choice costs a seventh of the old default, the OpenAI one a quarter, and the old OpenAI default is deprecated, passed 77 to 92% across three runs and invented a number in 9% of one of them. In `AIConfig.measuredDefaults`. |
| `coachTurn` | unchanged (`claude-sonnet-5`) | unchanged (`gpt-5.6-terra`) | **Not decided.** On choosing the right tool the two cheapest models tie the best at about 1/18 of the cost. But this dataset measures only the first turn's tool decision; it says nothing about the quality of the advice, multi-turn tool chains, or reading a photo, which are most of what the coach is. A default for the coach waits on an evaluation of those. |
| `mealDescribe` | unchanged | unchanged | **Not decided.** Same pattern (the cheapest models are as accurate at 1/19 and 1/28 of the cost, and more reliable than the Anthropic default), but every case states its portions in grams. The decision waits on cases with household and unstated portions, where a larger model may estimate better. |

What the intervals allow: with 13 to 34 cases, 100% still means "at least about 91 to 96%".
Differences of a few points between the models at the top are not established.

**Not verified:** the two new brief defaults were measured through the harness, not seen in
the app's UI. No Anthropic model above Sonnet and no `gpt-6.2-astra` was run (the heavy
tier's tasks have no dataset yet). Twelve tasks remain unmeasured, including four more
on the deprecated `gpt-4.1-mini`, which stops working on 2027-01-14.

## 11. The widget that showed someone else's data (2026-11-22)

Reported by the owner: after restarting the phone, his widget sometimes shows "Victoria"
and corrects itself shortly after.

**Cause, found by reading `Shared/WidgetSnapshot.swift`:** `WidgetSharedStore.load()`
returned a hardcoded sample profile (that name, the light theme, 153.8 lb, a 28-day
streak) whenever the snapshot could not be decoded, and the timeline provider drew it as
real data. After a restart and before the first unlock the app group's files are still
encrypted, so a timeline requested in that window reads nothing. The widget then kept the
sample until the next reload. Not reproduced: the simulator has no data protection.

**Changed:**

- A failed read is `nil`. The widget then draws a neutral "Open Sprout to refresh" state
  with no name and no numbers, and asks again in 5 minutes instead of 30.
- The sample is used only by the widget gallery and is named "Sample".
- Only the theme and companion choice (not personal data) are also written without file
  protection, so the neutral state is drawn in the user's own look.
- Day totals belong to their day (L-B5): a snapshot written yesterday shows zero eaten,
  steps and water today, and the timeline carries an entry at midnight so the reset
  happens then, not when the app is next opened. Targets, trend and streak carry over.

**Verified:** 13 tests in `WidgetSnapshotTests` (unreadable and corrupt data, the neutral
state carries nothing, retry interval, the midnight entry, a stale snapshot read in the
morning, a clock moved back). **Not verified:** on a phone. The check is to install the
build, restart the phone, and look at the widget before and after unlocking.

## 12. Home and Gym: two surfaces and the switch between them (2026-11-22)

Asked for by the owner, with a reference: the two-segment "Chat | Work" capsule at the top
of the ChatGPT app.

**What was built.** A `Home | Gym` capsule (`ModeSwitch`). Home is the tab bar with Today,
Nutrients, Progress and the coach; Gym is the Workouts experience on its own, with no tab
bar. The switch sits at the top of each surface's main screen: above the greeting on Today,
and in the navigation bar on Workouts. It is not on the other Home tabs or on pushed
screens, which matches the reference (the capsule is on the main screen only). The choice
is stored and the app reopens where it was left.

**Choices and why:**

- Both surfaces stay alive under the switch (one is hidden, not destroyed), so each keeps
  its scroll position, navigation path and half-typed text. Cost: both are in memory.
- An unknown stored value resolves to Home, so no stored state can open the app onto nothing.
- "Ask Vita about this" from Gym switches to Home and the coach tab, since the coach lives there.
- The tab bar went from five items to four, which frees a slot (five is the most iOS shows
  before a "More" list). Nothing was put in it.

**Verified:** 8 tests in `AppModeTests` for the resolution and launch rules; suite 516
passed. In the simulator on the dark demo profile, launched once into each surface, the
capsule renders in the same place on both, Home shows four tabs and Gym shows none
(`docs/screenshots/review/mode-home.png`, `mode-gym.png`; a first-launch notification
prompt is over part of both).

**Not verified:** nobody has tapped the switch (the launch argument selected the surface);
the light theme; Dynamic Type sizes; that hidden-surface state really survives a switch;
VoiceOver. There is still no UI test target, so none of this is guarded against
regression. **Needs the owner's eyes** before it counts as done.

## 13. The store returns what was put in: verification through the real store, and by SQL (2026-11-22)

Objective G4. Until now every data test ran on plain arrays or on a container holding a
handful of models; nothing opened the schema the app ships.

**Added:**

- `AppSchema`: the list of models in one place, used by the app and the tests. The store's
  version hash and table layout are identical before and after the change.
- 44 tests on an in-memory container with the full production schema and CloudKit off:
  the schema opens with all 20 models, and a model class in the source tree that is not
  registered fails a test; every model round-trips every field through a second context;
  each ingest merge (steps, sleep, vitals, detected workouts, the Google overlay) run
  twice leaves the same rows as once, and a changed value updates in place; the queries
  the screens depend on return hand-computed values from a fixed fixture; deletes are
  isolated to their model.
- `tooling/verify_store.py`: opens a SwiftData store read-only with SQL and reports every
  entity table and its row count and the per-day food, water, steps and weight totals, and
  fails on a null id, a negative quantity, or two rows for one day in a one-row-per-day
  table. It has a self-test that plants each violation, run in CI.

**Verified by running:** suite **560 tests: 558 passed, 2 expected failures, 0 failed,
0 skipped**. `verify_store.py` on a `--seed-demo --demo-gain` simulator store: 20 entity
tables, per-day totals printed, no violations.

**Two defects found, pinned as expected failures, app not changed:**

| ID | Defect | Where |
|---|---|---|
| S-1 | A detected workout that is delivered again with corrected minutes or calories is never updated: the merge only inserts. Its comment says this is by design; the owner decides. | `HealthKitSleepWorkouts.swift:297` |
| S-2 | Steps (and sleep, and workouts by the same match) are stored at local midnight and matched by calendar day, so a trip Los Angeles → New York → Los Angeles leaves two step rows for one day. | `HealthKitSteps.swift:93`; same match at `HealthKitSleepWorkouts.swift:121`, `:211` |

**Two behaviours pinned as known risks** (the tests assert what the app does today, and are
named so): the merges trust the caller's snapshot of existing rows, so a stale snapshot
duplicates a day; and with two profiles in the store the gate takes whichever the store
returns first, whatever its state (the case that can follow an iCloud restore, L-S1).

**Not covered:** the on-disk store and CloudKit; food logged from each entry point;
HealthKit weight and today's-steps import, which need HealthKit; the screens' own filters,
which are re-stated in the tests rather than called; whether the SQL totals match what
the screens show (the script prints them; nobody compared them to the UI).

## 14. Prompts for whoever is using the app, re-measured; a discarded rewrite explained (2026-11-22)

Objective G7, finding A-1 of section 3. Every prompt, template and fallback that
addressed one specific person ("her", "never push restriction", "weight-loss buddy") now
addresses the user in the second person or by the name passed in, and takes the goal
direction from the profile through one `GoalFraming` rule: for a user who is losing,
never push eating less; for a user who is gaining, never frame eating as excess. The
no-guilt, no-moralising rules are kept. `PromptNeutralityTests` (21 tests) call the real
prompt builders for both fixture users and fail on a gendered pronoun about the user, on
loss-only framing, and on either name the app was first built around.

**Still person-specific, found and not yet changed** (files other work was editing): the
coach's tool descriptions and result strings in `CoachTools.swift`; three lines of
onboarding copy in `OnboardingView.swift` that greet one person by name and sign off as
another; a few Settings, Buddy-preview and widget strings; `DemoSeed` still seeds both
names. G7 is therefore not met.

**Re-measured, because two measured prompts changed** (`Evals/runs/20261123-071932-DailyBrief`,
`20261123-072221-CoachToolChoice`; ten models, three repeats):

- Coach tool choice: no model lost ground. Six score 100% (96–100): `claude-haiku-5-5`,
  `claude-sonnet-5`, `claude-sonnet-5-5`, `gpt-6-luna`, `gpt-5.6-luna`, `gpt-5.6-terra`.
- Daily brief: `gpt-6-luna` 39 of 39 again; the default stands. `claude-haiku-5-5` passed
  36 of 39, failing one case ("your trend eased down") three times in three.

**Why that case failed, and the fix.** The harness could not say: a rewrite the app's
guardrail discards came back as nothing. `DailyBriefService.rejection(of:)` now names the
reason, the device log records it, and the evaluation keeps the raw reply. The reason was
not wording: the model wrote the headline and the body on one line, and the parser
required a line break and threw the whole reply away. The same slip explained most of
`gpt-4.1-mini`'s failures. `parse` now splits a one-line reply of two or more sentences
at its first sentence (a single sentence is still not a brief; banned phrases are still
rejected). Re-run on the four cases that had failed
(`20261123-072939-DailyBrief`): 12 of 12 on each of `claude-haiku-5-5`, `gpt-6-luna` and
`gpt-4.1-mini`. Twelve attempts per model is a confirmation of the mechanism, not a new
pass rate; the full 13-case run has not been repeated since the parser change.

The harness can now be limited to named cases (`SPROUT_EVAL_CASES`), which is how the one
failure was chased for a few cents. **Measured spend to date: $8.96** over 5,199 attempts.

## 15. A character from a photo (2026-11-22)

Objective G8. A new person can have a pixel character drawn from a photo.

**Researched** (`docs/avatar-generation.md`, sources there): OpenAI's image edit endpoint
and its current models. Confirmed from the documentation: the endpoint, the `background`,
`output_format`, `size` and `quality` values, where the image and the `usage` block are in
the response, the `moderation_blocked` error code, and the token rates. **Not confirmed
by the documentation:** a transparent background on the 2.6 models (it is stated for 2.5),
the multipart field layout together with those options, the HTTP status of a refusal, and
any per-image price. Each unconfirmed field is a named constant.

**Built:** `AvatarGenerator` (the request goes through the same test seam as the text
clients; the input photo is downscaled; the result must decode, be square and have real
transparency), one character per person stored on the profile, a custom case of the
avatar choice handled everywhere a companion is drawn, a small copy in the app group for
the widget that is drawn only if its digest matches the snapshot, an onboarding step
after the key step, and the same flow in Settings. Decisions: one image, not a set of mood
frames; the photo is sent only after an explicit consent and is never stored; without an
OpenAI key, on a refusal or on any failure the flow continues with a built-in character
and the step can always be skipped; a buddy is shown a built-in character, never
someone's custom one; the coach's tool can choose built-ins only.

**Verified:** 78 tests for request building, every failure mapping, the downscale, that
only the result is written, the widget file, and the stored values. In the simulator, in
the dark and the light theme, the step was seen in four states: choose and consent, no
OpenAI key, a preview, and a failure with its fallback
(`docs/screenshots/review/avatar-*.png`). Two things were fixed from looking: the preview
spilled past its ring, and the copy named a Settings screen that does not exist.

**Not verified:** no image has been generated. The preview in the screenshot is a
stand-in drawn in code. The request has never been sent to OpenAI, so the unconfirmed
fields above are untested; the camera path, the real widget process, and CloudKit sync of
the image have not been exercised. The default model `gpt-image-2.6-flare` was not chosen
by measurement; `Evals/run.sh Avatar` exists to do that and needs photos (synthetic or
consented) and approval for the spend. **The owner must deploy the CloudKit Production
schema** for the new `customAvatarPNG` field before a build with this reaches TestFlight.

## 16. Settings that change what depends on them: the plan, kilograms, and where a key goes (2026-11-22)

Objective G5, defects L-B2, L-B7 and L-B9 of section 3.

- **L-B2, fixed.** Each plan number now records the goal direction it was written for
  (beside the existing per-plan flag; no schema change). The plan's calories and protein
  drive the targets only while the direction still matches, so switching from losing to
  gaining falls back to the computed targets at once and raises the rebuild notice, and
  switching back restores them. A change of pace, activity level, goal or start weight,
  sex, height or birth date raises the notice and keeps the plan's numbers, from Settings
  and from every coach tool. The Settings footers now say what happens.
- **L-B7, made safe, not solved.** Full metric support touches about forty places.
  Until it is done properly, asking the coach to switch to kilograms is declined in plain
  words and writes nothing, so weights can no longer be corrupted. Kilograms are still
  not supported.
- **L-B9, fixed.** A pasted key is routed by the key itself (`sk-ant-` is Anthropic, any
  other `sk-` is OpenAI) and the active provider follows it; at launch, if the active
  provider has no key and the other has one, the active provider switches.
- Also fixed: the height shown for values not in whole inches, the water "reset to
  recommended" that showed one number and applied another, and two places that used the
  start weight as the current weight.

**Verified:** 95 new tests (a matrix of inputs against derived values, the plan rules, the
three fixes); suite 756 tests, 753 passed, 3 known defects pinned. One existing
expectation changed with a stated reason: after an undo the profile's protein target now
matches the plan (the state the running app is in) where the test had recorded a
unit-test artifact.

**Not done:** the written dependency table (`docs/settings-dependencies.md`) and the count
of matrix cells by status; simulator screenshots of the reworded Settings copy; checks
that each new test fails on the old code. **Found and open:** the step bonus is applied
on the Today ring and the widget but not on Nutrients, the coach, the buddy snapshot or
achievements; Settings' recommended water is not clamped the way onboarding's is.

## 17. UI smoke flows: the app driven end to end, and what the accessibility audit found (2026-11-23)

Objective G6. Until now nothing drove the app's UI; section 9 measured 19.1% of the
app's lines executed by tests.

**Added:** a `VictoriaUITests` target with its own scheme, and test hooks compiled into
Debug builds only (the Release binary was checked to contain none of them):
`--ui-testing` runs on an in-memory store with CloudKit off and suppresses permission
prompts, and `--ui-test-scripted-ai=<name>` answers every model call from a built-in
script. Fifteen flows, each a fresh launch, located by accessibility identifiers rather
than by copy: a fresh install shows onboarding; a seeded launch shows Today and every
Home tab opens; the Home and Gym switch is tapped both ways, the tab bar goes and comes
back, and the choice survives a relaunch; Home's state survives a round trip through
Gym; a food is logged by hand, appears, and moves Today's calories; logging twice and
deleting one leaves the right totals; water is logged; a workout is logged; a coach turn
on a scripted model proposes a tool, applies it, shows the reply, moves Today's water,
and undoes; a failing provider shows the error and the app stays usable; the app is
backgrounded in the middle of the food sheet and of a coach turn and comes back valid;
the coach, Gym and Settings are each opened first on a fresh launch.

**Verified by running:** three consecutive runs by the author of the flows, each 15 tests
with 10 passed and 5 expected failures, about 5 minutes; and once more on the integrated
branch (with the character step and the settings changes merged): the same result. Unit
suite on that branch: **780 tests, 777 passed, 3 known defects pinned.** The flows are a
CI job; it has not run on GitHub yet.

**This closes two "not verified" items of section 12:** the switch has now been tapped,
and state surviving a switch is asserted.

**Defects found:**

| ID | Defect | Where |
|---|---|---|
| U-1 | The surface hidden by the Home and Gym switch stays in the accessibility tree, so VoiceOver can reach controls that are not on screen. `.accessibilityHidden` on the hidden surface does not take effect on the tab view. Pinned as an expected failure. | `RootView.swift`, the two surfaces under the switch |
| U-2 | The demo seed's profile is created "now", so both day steppers are disabled and its seeded past days cannot be reached. | `DemoSeed.swift:29` |
| U-3 | A string in the Nutrients tab still names one person. | `FoodLogView.swift:427` |

**Accessibility audit** (`performAccessibilityAudit`, pinned as expected failures in five
flows, 19 to 32 issues per screen, about 70% of them from U-1). On screen: 9 pt day
letters on Workouts with no Dynamic Type and low contrast; contrast on the setup card,
the widget promo card, the plan card and a weight row; a clipped title on Workouts and,
in some runs, a clipped greeting on Today; a fixed-height mode switch; an unlabelled
image and a fixed 56 pt control on Progress; partial Dynamic Type in the coach. None is
fixed.

**Not covered:** onboarding beyond its first screen (the character step was being added);
the light theme; locales other than en-US; a run that crosses midnight; a simulator
signed in to iCloud.

## 18. The rest of the label: eleven more nutrients, and "unknown" is never zero (2026-11-23)

Objective G10. A food entry carried calories, protein, carbohydrate and fat.

**Researched** (`docs/nutrition-detail.md`, sources there): what the US Nutrition Facts
label requires, what Open Food Facts and USDA FoodData Central provide, and what can
honestly be estimated from a photo or a description. Two of its claims about what other
trackers show come from search excerpts, not from the products.

**Decided:** eleven optional fields, in label order: saturated fat, trans fat,
cholesterol, sodium, fiber, total sugars, added sugars, vitamin D, calcium, iron,
potassium. The photo and description estimator is asked for four of them (fiber, total
sugars, saturated fat, sodium) and not for the other seven, which are shown only when
they come from a label, a barcode or the user.

**The rule the feature rests on:** a value that is not known is stored as absent, shown
as unknown, and never counted as zero. A day's total for a nutrient says how many of the
day's foods it covers ("from 3 of 4 foods"). How "unknown" arrives from each source is
defined and tested: an absent or implausible key from Open Food Facts; an absent or
unreadable row, or a bare percent daily value, from a label scan; `null`, a missing key,
a negative or impossible amount, or four exact zeros on a food of 50 kcal or more from
the estimator (the filler a strict schema produces, section 10); an absent argument from
the coach's tools; an empty field in manual entry.

**Verified:** 111 new tests; suite **891 tests, 888 passed, 3 known defects pinned**;
evaluation self-tests 37 passed, 4 live evaluations skipped. A store written before the
change opens with the new build: its 10 rows are kept and the 11 new columns are empty.
The day card and the entry detail were seen in the simulator
(`docs/screenshots/review/nutrition-*.png`).

**Not verified:** no model has been sent the new schema, so how often each candidate
fills the four estimated fields, and how accurately, is unmeasured. The label parser ran
on typed text, not on a camera scan. `meal_describe/v3` (the existing cases with these
nutrients from the same USDA records) is **not built**: USDA's demo key refused every
request for about sixteen hours, the fetch code for nutrient details has never run
against the service, and the nutrient ids in it were written from memory, so they must
be checked on the first successful fetch. The live meal evaluation stays on v1 until then.
**The owner must deploy the CloudKit Production schema** for the eleven new `FoodEntry`
fields before a build with this reaches TestFlight.

## 19. Buddy pairing and sync: nine defect groups closed (2026-11-23)

Objective G11, the data-and-sync table of section 3. Every claim was checked against the
current code before it was fixed; none of the audit's claims turned out to be wrong.

| ID | Was | Now |
|---|---|---|
| D-V2 | A mistyped or not-yet-uploaded code said "You're connected!" | Pairing succeeds only when the code resolves to another user's record. A code that is not a code, your own code, a code nobody has shared, and a code already claimed each say so, and nothing is stored on failure. |
| D-V3 | The link was stored before the claim was saved. | Stored after the remote write succeeds; a failed claim leaves the user unpaired and able to retry. |
| D-V4, L-B11 | No way out of a pairing; a reinstall stranded the partner on a frozen snapshot. | An Unpair action with a confirmation, which tells the other side through the pairing record and deletes the published snapshot. A buddy who has published nothing for three days is shown as "hasn't shared an update since" that date, with Unpair, and their old day is not shown as current. |
| D-V9 | The publisher read the link once at launch. | It notices a new link without a relaunch. |
| D-V10/11 | Streak nudges re-fired daily; a milestone was used up before a failed send. | Each milestone is sent once and marked sent only when the send succeeded. |
| D-V14 | The silent-push handler returned before its work ran. | It waits for the refresh, bounded at 20 seconds. |
| L-B6 | The 7- and 14-day achievements counted imported steps as logged days. | They use the streak's definition of an active day. An achievement already unlocked stays unlocked. |
| L-B12 | No reminders and no permission prompt until the second launch. | Scheduled when an onboarded profile first appears. |
| V16–V18, V22 | A diagnostics flood during pairing, concurrent publishes, a nudge gated on the snapshot, a badge never cleared. | Fixed in the app; see below for what remains. |

Also changed: the pairing screen promised "never your weight or calories" while sharing
full stats is on by default, so it now says what is shared. Linking no longer publishes
an invented "logged today" snapshot.

**Verified:** 93 new tests; 47 of them were run against the old behaviour first and
failed there, and five written later were checked by breaking the code on purpose. Suite
**984 tests, 981 passed, 3 known defects pinned**. Ten states were seen in the simulator
(`docs/screenshots/review/buddy-*.png`), reached by debug launch arguments rather than
by tapping; on a fresh install the reminder prompt appeared on the first launch.

**Not verified:** nothing was sent to CloudKit. The pairing store, the snapshot delete,
the account-status mapping and the handling of a real push payload are tested against a
double of the sync service only. **Still open:** the diagnostics log rewrites its whole
file for each line; CloudKit's server-side badge count keeps growing until the
subscription is re-created on a device; the "first steps" achievement still unlocks from
imported steps; a durable identity that survives a reinstall is a design
(`docs/buddy-identity.md`), not built. **The owner must check in the CloudKit Dashboard**
(`docs/buddy-sync.md` section 10): that Production has every `BuddyPairing`, `Nudge` and
`BuddySnapshot` field and the three indexes, and that signed-in users can write
`BuddyPairing` and `Nudge` records, since claiming a code, unpairing and marking a nudge
read each write to a record another user created.

## 20. The chat: a testable turn engine, paged history, selection, and named failures (2026-11-23)

Objective G14, asked for by the owner: long chats that will not load, text that cannot
be selected, no copy, no "ask about this", and the failures every AI chat runs into.

**Researched** (`docs/chat-standards.md`, sources there): how established chat apps and
Apple's guidance handle long transcripts, selection, message actions, sending and each
kind of failure, ending in a 37-row table of the standard against what Sprout did.

**Measured before changing anything** (simulator, time from the tab being created to
usable, median of three; a debug argument seeds the conversation):

| Messages | Before | After | Memory before → after |
|---|---|---|---|
| 200 | 337 ms | 332 ms | 45.6 → 42.4 MB |
| 1,000 | 358 ms | 352 ms | 55.9 → 42.3 MB |
| 5,000 | 677 ms | 337 ms | 113.0 → 42.7 MB |

The view used to load every message in the store; it now fetches the latest 40 and pages
earlier ones in. A three-message chat opens slightly slower than before (276 → 331 ms).
**"It just won't load" was not reproduced** on the simulator at 5,000 messages: load time
doubled and memory tripled, but it loaded. A phone with a real, photo-heavy history may
behave worse than this seeded text; that has not been measured.

**Changed:**

- The turn logic is out of the view, in an engine a test can drive with a scripted model
  and an in-memory store: sending, a tool proposal, confirm or auto-apply, the follow-up
  call, the depth cap, undo, the memory fold, and every failure branch.
- Failures are typed and each has its own words and action: offline, timeout, a rejected
  or missing key (opens AI settings), a rate limit with the provider's wait shown as a
  countdown, an overloaded provider, a reply cut off by its cap, a refusal. The user's
  message is saved before the call, a failed turn has a Retry that re-sends that message
  without a duplicate, a second send while a turn is in flight is ignored, and a message
  left unanswered by a relaunch is shown as such with a retry.
- Earlier messages load on scrolling up, with a visible state, and "jump to latest"
  appears when scrolled up; a new reply no longer pulls a reader who has scrolled up back
  to the bottom.
- A range of text inside a settled reply can be selected, across paragraphs and lists,
  with Ask about this and Copy in the menu. A message can be copied, shared, deleted or
  quoted to the coach; the quote goes into the composer and to the model as context.

**Defects found in the old code and fixed with tests:** a tool call cut off by the output
cap showed a placeholder reply instead of an error; a tool could be applied past the
depth cap; there was no retry after a tool had been applied; the memory fold was
unbounded; an "ask Vita" topic set while a turn was sending was dropped; an empty message
was sent as an empty text block; a provider's refusal text was dropped by the OpenAI
client; both clients retried without honouring `retry-after` and retried on an account
with no credit.

**Verified:** 114 new tests, including the engine on Anthropic Messages, OpenAI Chat
Completions and OpenAI Responses shapes (two tool calls in one turn, a turn cut off mid
call, a rejected tool and the recovery, 401, 429, 500, 529, a timeout, offline, an empty
reply, the depth cap). Suite **1,098 tests, 1,095 passed, 3 known defects pinned**. The
fifteen UI flows pass after the merge; they caught two things the merge had broken (a
message was no longer exposed as static text once replies were drawn by a text view, and
the failure row's identifier), both fixed. Twelve states were seen in the simulator
(`docs/screenshots/review/chat-*.png`), driven by real swipes, long presses and typing
through a throwaway UI test.

**Not verified, and open:**

- When a page of earlier messages is added, the row at the top stays on screen but moved
  by 0 to 31 pt in six loads and by 156 to 173 pt in three. Five corrections were tried
  and each was worse. **The view still jumps on some loads.**
- No real provider was called: every reply and failure came from a scripted transport.
  Not seen: a phone, VoiceOver on, Dynamic Type, the light theme, real backgrounding.
- Selection does not work in the user's own messages (copy is in the menu instead),
  during a reply's 1.1 s reveal, or across messages.
- Not built: regenerate, edit and resend, read aloud, feedback, token-by-token streaming.
  The history sent to the model is not trimmed by size and photos are re-sent each turn.
  The reveal animation can freeze if its row scrolls away (read, not fixed).

## 21. iCloud was backing up two of twenty models: the CloudKit schema, measured and fixed in Development (2026-11-23)

The owner asked for the CloudKit Production schema to be deployed for twelve new fields.
Exporting the two live schemas first (read-only, `xcrun cktool export-schema`) showed the
gap was not twelve fields.

**Measured.** Production and Development were identical. They held six record types:
the three public buddy types, `Users`, and two of the app's mirrored models,
`CD_UserProfile` and `CD_WeightEntry`. The models send 20 record types and 208
attributes (`docs/cloudkit/model-manifest.json`, generated from the Core Data model the
app builds). So **18 record types did not exist** in either environment: food, water,
chat, the coach's memory and plan, steps, sleep, vitals, workouts, the checklist,
achievements and the rest. On the two that did exist, 9 fields were missing, 6 of them on
the profile from long before this work, and none of the companion asset fields that
carry values too large for a field (a long note, a photo) existed.

**What that means.** Production rejects a record type or field it does not have, and the
app is not told. In every TestFlight build so far, the iCloud mirror has carried at most
the profile and weigh-ins, and since the profile gained fields Production lacks, probably
not the profile either. The data lives on the phone only. This confirms the suspicion
marked D-S in section 3, and it withdraws a claim made in section 7: iCloud is **not** a
second copy of the data. **An expired build must be updated in place, never deleted;**
deleting the app deletes the food log, the chat, the plan and the workouts for good.
The older note in `TESTFLIGHT.md` that data mirrors to iCloud is wrong for the same reason.

**Mapping, verified three ways.** Apple documents it ("Reading CloudKit Records for Core
Data"): record type `CD_<Entity>`, field `CD_<attribute>`, a `CD_<attribute>_ckAsset`
companion for every string, binary and transformable attribute, and `CD_entityName`. The
41 fields Core Data had itself created in the existing schema all have exactly the type
this mapping gives (0 mismatches). And Apple's `cktool validate-schema` accepted the
result.

**Done.** `tooling/build_cloudkit_schema.py` took the exported Development schema and
added what was missing, changing nothing that was there (477 lines added, 0 changed or
removed): 18 record types and 29 fields on the two existing ones. It was validated and
imported into **Development**, and a fresh export passes
`tooling/check_cloudkit_schema.py` with nothing missing. **Production was not touched**;
a re-export is byte-identical to before. Development can be reset; Production cannot be
undone, which is why it was left for the owner.

**Guards added:** `CloudKitSchemaManifestTests` fails when the models and the manifest
disagree, so a model change cannot land silently; CI checks that the checker passes the
committed Development schema and fails the committed Production one; the release recipe
(`docs/cloudkit/README.md`) starts with the check against Production.

**Not verified.** Apple's own initializer could not be run to compare, because it needs a
device signed in to iCloud. No record has been saved through the new schema. The proof
that it matches what Core Data sends is a Debug build on a signed-in phone syncing
without a CloudKit error, and that has not been done. **The owner must:** run a Debug
build once on a signed-in phone and confirm it syncs; then deploy Development to
Production in the CloudKit Console; then run the checker against Production.

## 22. Eight more tasks measured: four defaults changed, and two ways a reply was being lost (2026-11-23)

Approved by the owner in the session. The eight tasks that had no evaluation, ten models,
three repeats, run from a worktree fixed at one commit so nothing else could change the
code under measurement (`Evals/runs/20261123-0925…` to `…0948…`, 3,810 attempts, $6.38
measured). **Spend to date across every run: $16.67 over 9,243 attempts.**

These graders check that a reply is used, keeps the given facts and numbers, invents
none, respects the limits its own prompt states, and addresses the right person. **None
of them measures whether the advice is good or the tone is right.** Twelve to nineteen
cases each: only large gaps are real.

Pass rate (95% interval) and measured cost per 1,000 calls. **Bold** is the default
before this section.

| Task | Anthropic | OpenAI |
|---|---|---|
| `insightLine` (19) | **haiku-4-5 100% (94–100), $0.42**; haiku-5-5 95%, $0.06 | **4.1-mini 96% (88–99), $0.14**; 6-luna 100% (94–100), $0.04; 5.6-luna 100%, $0.08 |
| `weeklyReflection` (16) | **haiku-4-5 92% (80–97), $1.49**; haiku-5-5 85%, $0.23 | **4.1-mini 96% (86–99), $0.47**; 6-luna 98% (89–100), $0.13; 5.6-luna 94%, $0.27 |
| `onboardingNote` (15) | **haiku-4-5 96% (85–99), $0.90**; haiku-5-5 89%, $0.13 | **4.1-mini 100% (92–100), $0.29**; 6-luna 100% (92–100), $0.07; 5.6-luna 98%, $0.16 |
| `memoryFold` (12) | **haiku-4-5 100% (90–100), $2.06**; haiku-5-5 92%, $0.52 | **4.1-mini 86% (71–94), $0.71**; 5.6-luna 100% (90–100), $0.43; 6-luna 78%, $0.17; 6.2-sol 28% |
| `progressSummary` (15) | **sonnet-5 64% (50–77), $6.12**; haiku-5-5 73%, $0.31; haiku-4-5 33% | **5.6-terra 89% (77–95), $3.80**; 5.6-luna 96%, $0.34; 6-luna 93%, $0.14 |
| `foodSuggestions` (18) | **sonnet-5 100% (93–100), $7.10**; haiku-5-5 100%, $0.37 | **5.6-terra 100% (93–100), $4.77**; 6-luna 100%, $0.17 |
| `coachPrompts` (16) | **sonnet-5 100% (93–100), $4.85**; haiku-5-5 100%, $0.23 | **5.6-terra 100% (93–100), $3.45**; 6-luna 100%, $0.12 |
| `checklistPlan` (16) | **sonnet-5 71% (57–82), $8.14**; haiku-5-5 100%, $0.40 | **5.6-terra 100% (93–100), $4.56**; 6-luna 100%, $0.18 |

`claude-sonnet-5-5` scored 0% on the last four: it rejects a forced tool call (section
10, defect 2), which is still open.

### Read before trusting: what the failures actually were

The pass rates above mix three different things, found by reading the failing records:

1. **A reply cut off by its output cap, on the newest Claude models.** Every unexplained
   failure of `claude-haiku-5-5` and `claude-sonnet-5-5` on the three short-writing tasks
   has exactly the task's cap as its output token count (80, 320 or 420). Those models
   think before they write, the thinking comes out of the same cap, and what is left is
   too short or empty. The app then shows its template and says nothing. This is a
   budget problem, not a quality one, and it is why `claude-haiku-5-5` trails
   `claude-haiku-4-5` here. **Open:** give thinking models a cap that allows for it, or
   lower the effort, and measure again.
2. **The current Claude default returned a checklist the app could not read in 14 of 48
   calls**, so 29% of checklist generations were silently replaced by the fallback. Each
   field held a string containing an object that wrapped that same field
   (`"chips": "{\"chips\": [...]}"`). **Fixed and re-measured:**
   `StructuredOutputRepair`, driven by the schema, unwraps that shape for every
   structured call on both providers. `claude-sonnet-5` on the checklist went from 71% to
   **100% (93–100), 48 of 48** (`Evals/runs/…-ChecklistPlan`, the last one).
   A first version of the repair was written from one truncated sample, handled a shape
   that does not occur, and changed nothing when measured; it was rewritten from the full
   records. A second failure shape is not repaired and stays a model failure: on the
   progress summary `claude-haiku-4-5` leaked tool-call markup into a field in about 1 call
   in 10.
3. **A disagreement with a label, not a defect.** On `memoryFold` the 6.x OpenAI models
   put a temporary injury ("strained lower back, deadlifts on hold while it recovers")
   in the rolling summary instead of the durable notes. The dataset counts an injury as
   durable; a reasonable reader could side with the model. The 28% for `gpt-6.2-sol` is
   that one choice, repeated. **The owner should decide** which is wanted before this
   dataset is used to rank those models again.

Also: the `progressSummary` pass rule includes "no number that is not in the snapshot",
and most failures there are derived figures (a difference, a projected date). Whether a
correct derived number is a fault is a product question; the low rates for `sonnet-5` and
`haiku-4-5` should be read with that in mind.

### Decisions

| Task | Change | Why |
|---|---|---|
| `insightLine`, `weeklyReflection`, `onboardingNote` (OpenAI) | `gpt-4.1-mini` → **`gpt-6-luna`** | As good or better on every one (100%, 98%, 100%), a quarter of the cost, and the old default is deprecated. |
| `memoryFold` (OpenAI) | `gpt-4.1-mini` → **`gpt-5.6-luna`** | 36 of 36 against 86% for the old default; `gpt-6-luna` is cheaper but, by this dataset's rule, kept every durable fact in only 78%. |
| The same four (Anthropic) | unchanged, `claude-haiku-4-5` | `claude-haiku-5-5` costs a seventh but loses replies to its output cap (finding 1). Revisit once that is solved. |
| The four structured tasks (both providers) | unchanged | The cheapest models match the defaults on these checks at about 1/20 to 1/28 of the cost, but the checks say nothing about how good the suggestions, chips, tasks or recap are. As with the coach and meal description (section 10), a change waits on a measure of that. The one reliability problem (the checklist) is fixed in the app instead. |

With these, **no task defaults to a deprecated model**, and a test now fails if one does.
Seven of fifteen tasks have a default chosen by measurement on at least one provider.

**Not verified:** none of the new defaults has been seen in the app's UI. The full
ten-model runs were not repeated after the repair, only the affected model on the
affected task. The image comparison for the character feature had not been run when this
was written; it is section 23.

## 23. The character call, made for real: eighteen images, and a grader that could not see them (2026-11-23)

Objective G8. Approved by the owner in the session, on generated faces only. Section 15
ended with "no image has been generated". This is the first time the request was sent.

**The photos.** Three portraits of people who do not exist, generated for this purpose
(a man in his thirties with curly hair and a beard, a woman in her twenties with a
ponytail and earrings, a man in his fifties with grey hair and glasses). They are in
`Evals/datasets/avatar/photos/` on the machine that ran this and, like every photo and
every character, are not committed.

**The runs.** `Evals/run.sh Avatar` with three candidates, twice
(`Evals/runs/20261123-100309-Avatar`, `…-101043-Avatar`): 18 calls of
`AvatarGenerator.generate`, the call the app makes. Cost is the response's own token
counts at the published rates, not a figure from an invoice.

| Candidate | Usable | Passed | Colours counted | Seconds (p50, per run) | Output tokens | Cost per character |
|---|---|---|---|---|---|---|
| `gpt-image-2.6-flare`, low | 6 of 6 | 6 of 6 | 29 to 45 | 7.4, 7.6 | 824 | $0.035 |
| `gpt-image-2.6-flare`, medium (the default) | 6 of 6 | 6 of 6 | 34 to 44 | 8.8, 10.0 | 1,449 | $0.054 |
| `gpt-image-2.6-sunburst`, medium | 6 of 6 | 6 of 6 | 26 to 32 | 20.1, 19.6 | 1,449 | $0.054 |

Every request carried 1,454 input tokens (430 of text, 1,024 for the photo). Six images
per candidate is far too few to rank them on a pass rate: all this table can say is that
none of the three failed.

### Confirmed by the live call (these were open in section 15)

- **A transparent background works on the 2.6 models.** All 18 images are 1024 × 1024 PNGs
  with an alpha channel, and between 34% and 46% of each is fully clear.
- **The multipart request is accepted as built.** 18 of 18 answered, none retried.
- **The `usage` block is where the code reads it**, with text and image input counted
  separately, so the cost above needs no guess.
- **The app's own acceptance check passes real images.** `validateCharacterPNG` accepted
  all 18.

### A grader that scored every character as having no colours

The first run reported 0 of 9 passed. The images were plainly pixel characters, so the
score was wrong, and the records showed why: `distinct_colours` was 0 for every one.

Measured on the files with a second tool: **the image models never return a fully solid
pixel.** The body of each character is at alpha 253 or 254, none at 255, and the cleared
background carries a scatter of alpha 1 and 2. Neither can be seen. The grader counted
colours only among pixels at exactly 255, and called a corner clear only at exactly 0 (one
`sunburst` image failed its top-corner check on a single pixel at alpha 1). It had been
tested only on images drawn in code, which are exact.

**Fixed:** a pixel at or under alpha 8 is graded clear and one at or over 250 solid. Tests
now use an image built the way the models return one, and check the two limits at their
exact edges. **Re-measured without paying again:** `Evals/regrade-avatars.sh <run>` grades
a past run's saved characters with the graders as they now are and writes
`regrade-avatar.json` beside the untouched records. The first run regrades to 9 of 9, and
its nine colour counts equal, image for image, the nine obtained independently from the
files.

**The "is it pixel art" limit, calibrated for the first time.** It was 48, a guess that
section 15 flagged. On thirteen images: ten pixel characters (the nine of the first run
and one built-in character) counted 24 to 45, and the three photographs they came from
counted 72 to 81. The limit is now 58, the middle of that gap. The second run was made
after the limit was set, so its nine images are the only ones the limit was not fitted
to: they counted 27 to 43 and all passed. **This is a weak calibration:** thirteen images,
photographs with plain backgrounds, and no example of the thing most likely to fool it (a
smooth cartoon that is not pixel art). A count between 46 and 71 has never been seen.

**The app is not changed by this.** It keeps the image as returned; a body at 99% opacity
looks solid on any background the app draws it on.

### What the code cannot grade, and one opinion about it

Likeness and fit with the existing characters are the owner's rating (G8, check a). The
18 images were looked at beside their photos during this work. This paragraph is that
reader's opinion, not a measurement, and not the owner's:

- All 18 are recognisably the person in the photo, and keep what the prompt has to keep:
  hair shape and colour, the beard, the glasses, the earrings, the colour and collar of
  the clothing. None drew a background, a second person or text.
- `flare` at low and at medium could not be told apart at the size the app shows a
  character.
- `sunburst` draws larger pixels and fewer colours (26 to 32 against 29 to 45, the one
  difference here that is measured). That is nearer to the built-in characters, which are
  coarse and flat. It costs the same as `flare` at medium and takes about twice as long.

### Decisions

- **The default stays `gpt-image-2.6-flare` at medium until the owner has looked.** On
  everything the code checks the three are equal, and by this project's rule the cheapest
  of equals (`flare`, low: a third cheaper and no slower) would be the default. But the
  thing that matters here is how the character looks, which no check measures, and a
  character is made once per person, so the difference is two cents. The owner picks from
  the saved images; changing it is one line in `AIConfig.avatarImage`.
- The grader limits and the regrade script are kept.

### Not verified

- **No real photograph has been used.** Generated portraits are easier than a real
  selfie: one face, centred, evenly lit, a plain wall. A busy background, a hat, a face at
  the edge, two people in frame, a child, a poor camera: all untested.
- **A refusal has not been seen**, so the HTTP status of one and the path that handles it
  have still only run against scripted replies.
- **The flow in the app has not made a live image.** The evaluation calls the same
  function, but the consent screen, the preview and the save were last seen with a
  stand-in (section 15). Doing it for real needs a key typed into the app, which is the
  owner's to do.
- The camera path, the widget process drawing a real character, and iCloud sync of the
  image (blocked on the Production schema, section 21) are unchanged from section 15.

**Spend:** $0.86 for the two runs and about $0.08 to generate the three portraits.
**Spend to date across every run: $17.61 over 9,261 attempts.**

## 24. The coach's tools called every user "she" (2026-11-23)

Objective G7. Section 14 reworded the prompts and said the tool descriptions were not
covered. They are what the coach model reads on every chat turn: 28 tools, and their
descriptions referred to the user as "she" or "her" 181 times ("Use when she tells you
what she ate"), whoever was using the app. The owner is one of the people this was wrong
for.

**Changed:** every description, property description and tool reply in `CoachTools` now
says "they" and "their", with the verbs made to agree. The example that named a built-in
character now follows the list of characters instead of spelling one.

**Tested:** a new test reads the tools as the model receives them, for both fixture users
on each goal direction, and fails on a gendered pronoun, the hard-coded label, or a verb
left in the singular. It was run against the old text first and failed there (five
descriptions reported before the output was cut), then passed on the new. `CoachTools.swift`
was added to the scanned source files, which covers the replies the tools hand back to
the model. Three tests that pinned the old wording ("Her weight today in lb.", "driving
her targets", "her current weight") were changed to the new wording; nothing else in them
changed. 1,113 unit tests pass.

**Measured, because a description is a prompt:** the tool-choice evaluation, same 34
cases and three repeats as section 10's last run, on the two defaults and three others
(`Evals/runs/20261123-101903-CoachToolChoice`, 510 attempts, $1.43).

| Model | Before (`…-072221`) | After |
|---|---|---|
| `claude-sonnet-5` (default) | 102 of 102 | 102 of 102 |
| `gpt-5.6-terra` (default) | 102 of 102 | 102 of 102 |
| `gpt-6-luna` | 102 of 102 | 102 of 102 |
| `claude-haiku-5-5` | 102 of 102 | 101 of 102 |
| `claude-haiku-4-5` | 95 of 102 | 93 of 102 |

Read, not just counted: `claude-haiku-4-5` fails the same three cases as before, in the
same way (it asks a question where the case expects a call, twice, and logs two eggs'
calories with a quantity of two). The one new miss on `claude-haiku-5-5` is that same
doubling, which three other models also did before the change. No failure of a new kind
appeared, and the differences are inside the intervals. The rewording did not change
which tool a model picks.

**Still open in G7:** the two built-in characters are stored, and offered to the model,
under the first names of the two people they were drawn for (`victoria`, `bryan`). The
test allows exactly that and says so. Renaming them changes a stored value and what the
app shows, and needs the owner to say what they are called. Onboarding copy, Settings,
the buddy feature, the widgets and the demo seed have not been scanned.

**Spend to date across every run: $19.04 over 9,771 attempts.**
