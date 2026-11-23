# Goals

The objectives the owner has set, each with the check that decides whether it is met.
Claude Code's built-in `/goal` works down this file with the condition in "Running it"
below: take the first objective that is not met, do the work by the method in
`AGENTS.md`, run the check, record the result, and repeat until every objective is `met`
or is waiting on the owner.

**Status values:** `met` (the check passed, and the line says where the evidence is),
`in progress`, `open`, `blocked: <what is needed from the owner>`, `todo (spec needed)`.
A status changes only when its check was actually run. "Done" without the check is `in progress`.

**Order matters.** Objectives are listed in the order they should be worked; an objective
that names a prerequisite is skipped until the prerequisite is `met`.

Last updated: 2026-11-22.

| | Objective | Status |
|---|---|---|
| G1 | Every model default is chosen by measurement | in progress |
| G2 | CI is green and stays the gate | met: 4 of 4 jobs on the pull request and on `main` after the merge |
| G3 | A widget never shows anyone else's data, or yesterday's as today's | blocked: the owner restarts his phone on a build and looks at the widget before unlocking |
| G4 | The store returns what was put in | in progress: schema, round trips, merges, queries and the SQL script are done; entry points, on-disk and UI comparison remain |
| G5 | Changing a setting changes everything that depends on it | in progress: three defects fixed and 95 matrix tests (EVAL_REPORT 16); the dependency table and kilograms remain |
| G6 | No step breaks when done out of order, repeated, or skipped | in progress: 15 UI flows pass (EVAL_REPORT 17); the onboarding flow and its skip combinations remain |
| G7 | Prompts and copy fit whoever is using the app | in progress: prompts reworded and tested (EVAL_REPORT 14); tool descriptions, onboarding copy and the demo seed remain |
| G8 | A new person gets their own pixel character from a photo | blocked: built and seen in the simulator (EVAL_REPORT 15); the owner supplies photos and approves the image runs, and deploys the CloudKit schema |
| G9 | Home and Gym as two modes, switched at the top | in progress: built, tapped by a UI test both ways with state kept (EVAL_REPORT 12, 17); open: VoiceOver reaches the hidden surface (U-1), the light theme, and the owner's look at the screenshots |
| G10 | Nutrition is as specific as it can honestly be | in progress: built and tested from every source (EVAL_REPORT 18); the estimator's accuracy on the new fields is unmeasured, and the owner deploys the CloudKit schema |
| G11 | The open defects are closed | in progress: the high-severity lifecycle defects and nine buddy groups are fixed (EVAL_REPORT 16, 19); open: kilograms, widgets' gain framing, travel day keys, HealthKit sync, U-1 to U-3, S-1, S-2 and the accessibility findings |
| G12 | Competitions | todo (spec needed) |
| G13 | The app is back on the phones and does not expire again | blocked: the owner deploys the CloudKit schema to Production (EVAL_REPORT 21) and uploads the build; an expired build must be updated in place, never deleted, because iCloud holds almost none of the data |
| G14 | The chat holds up: long histories, selection and copy, "ask about this", real error handling | in progress: built, tested and seen running (EVAL_REPORT 20); open: the view still jumps on some "load earlier" loads, nothing was run against a real provider or on a phone, and regenerate, edit-and-resend and streaming are not built |

## Running it

`/goal` is built into Claude Code: it keeps starting turns until a separate model judges
the condition met from what is shown in the conversation. It does not read files or run
commands itself, so the condition asks for the evidence to be printed. Open the session
in `~/dev/GitHub/sprout`, switch to auto mode so the turns run unattended, and paste:

```text
/goal Every objective in docs/GOALS.md has status "met", "blocked: <what the owner must do>" or "todo (spec needed)", with the proof shown in this conversation. Work the objectives in file order by the method in AGENTS.md, skipping one whose prerequisite is not met. An objective is met only when its Check was run in this session and the output is printed here: for code, tooling/evidence/capture.sh printing every gate exit code 0 and the unit-test count, plus CI green on the pull request; for a model default, the summary table from Evals/run.sh, the new EVAL_REPORT section and the measuredDefaults row. Update the status table in docs/GOALS.md, docs/EVAL_REPORT.md, VictoriaTests/LEDGER.md and CHANGELOG.md in the same change, commit on a branch and push it. At the end of every turn print the GOALS.md status table and, for what changed, what was verified by running and what was only read. Constraints: never weaken, skip or delete a test to make it pass; a defect fix needs a test that fails on the old code; no paid evaluation run estimated above 10 dollars without my approval, and if one needs more, mark that objective blocked and go on to the next; never upload to TestFlight, deploy a CloudKit schema, merge into main or rewrite pushed history; G12 stays todo; anything that needs my eyes or my phone (screenshots to approve, a restart test, label review, sample photos) is marked blocked with exactly what I must do, and work continues on the next objective. Stop after 40 turns.
```

`/goal` alone shows the status; `/goal clear` stops it.

---

## G1. Every model default is chosen by measurement

*"We created our testing case and everything, and we tried every single model."*

- **Check:** for each of the 15 tasks in `AITask`, an EVAL_REPORT section with a comparison
  table (pass rate with interval, cost, latency, at least three repeats, every current
  candidate from both providers), and a row in `AIConfig.measuredDefaults` citing it. No
  default is a deprecated model.
- **Status:** in progress. 1 of 15 decided: `dailyBrief` (EVAL_REPORT 10). `coachTurn` and
  `mealDescribe` are measured but not decided: each needs a harder dataset (advice quality
  and multi-turn for the coach; unstated portions for meals). `claude-sonnet-5-5` cannot
  run the seven structured tasks until those calls stop forcing a tool. Four tasks still
  default to the deprecated `gpt-4.1-mini` (shutdown 2027-01-14). Twelve tasks have no dataset yet:
  `mealPhoto`, `foodSuggestions`, `progressSummary`, `checklistPlan`, `coachPrompts`,
  `planBuild`, `planReview`, `planResearch`, `insightLine`, `weeklyReflection`,
  `onboardingNote`, `memoryFold`.
- **Needs the owner:** approval and a cost estimate before each paid run; review of the
  coach labels in `Evals/datasets/coach_tool_choice/v1.jsonl`; a decision on downloading a
  Nutrition5k subset for `mealPhoto`.

## G2. CI is green and stays the gate

- **Check:** every job of `.github/workflows/ci.yml` passes on the pull request and on
  `main`; the minimum test count in the workflow equals the ledger's total.
- **Status:** met on pull request 1: all four jobs passed on the first run (2026-11-22).
  Re-check after the merge to `main`.

## G3. A widget never shows anyone else's data, or yesterday's as today's

*"I sometimes see Victoria instead of mine."*

- **Cause (read, not reproduced):** when the widget could not read its snapshot (after a
  phone restart, before the first unlock, the app group's files are still encrypted) it
  fell back to a hardcoded sample profile and drew it as real.
- **Check:** `WidgetSnapshotTests` pass (an unreadable snapshot yields a neutral
  "Open Sprout to refresh" state with no name and no numbers; day totals reset at
  midnight). **And on the owner's phone:** restart it, look at the widget before unlocking
  and after: it never shows the sample.
- **Status:** fixed and tested (EVAL_REPORT 11, 13 tests). Blocked on the owner for the
  phone check, which needs a build on his device.

## G4. The store returns what was put in ("SQL verification")

*"Making sure everything works as expected, that we're able to retrieve everything."*

- **Check:** integration tests on the production schema in an in-memory container:
  (a) all 20 models open together; (b) every model round-trips every field (write, save,
  fetch in a new context, compare); (c) every ingest path (HealthKit sleep, vitals,
  workouts, steps, weight; Google Health; food from each entry point) run twice leaves the
  same rows as once; (d) each query a screen depends on (today's food, the trend window,
  the streak inputs, the buddy snapshot inputs) returns the expected rows from a fixed
  fixture; (e) `tooling/verify_store.py` runs the same counts as SQL against a seeded
  simulator store and agrees with what the app shows.
- **Status:** in progress (EVAL_REPORT 13). Done: (a), (b), (c) for the tracker merges, (d),
  and the script of (e) with its self-test in CI. Remaining: food from each entry point and
  the HealthKit weight import under (c); comparing the SQL totals with what the screens
  show under (e). Two defects it found are open (S-1, S-2).

## G5. Changing a setting changes everything that depends on it

*"If you change your environment, your settings, that is the most important part."*

- **Check:** a matrix test. For each input a user can change (goal direction, pace,
  activity level, current weight, start weight, goal weight, height, sex, birth date, units,
  step goal, water container, protein goal, theme, AI provider, tracker connected or
  removed, plan built or rebuilt) and each thing derived from it (calorie and macro targets,
  the plan's "goals changed" flag, the widget snapshot, the coach's context, the buddy
  snapshot, the cached daily brief, the checklist), the test asserts the derived thing
  moved, or that it is documented as deliberately unaffected. The known failures are fixed
  first: EVAL_REPORT 3 L-B2 (plan overrides ignore goal changes), L-B7 (unit switch
  corrupts weights), L-B9 (provider reset on reinstall stores the key in the wrong slot).
- **Status:** open.

## G6. No step breaks when done out of order, repeated, or skipped

*"What happens if you do one step in front of the other? What happens if you manage to skip a step?"*

- **Check:** (a) state tests for onboarding: every page can be reached, every optional page
  can be skipped, and every combination of skips ends in a profile whose targets are
  finite and inside the safe bounds; finishing twice creates one profile; (b) UI smoke
  flows (an XCUITest target, seeded by launch argument, with a scripted model): first run
  through onboarding to Today; log food by each entry point; a coach turn that proposes a
  tool, confirm, undo; pair and unpair a buddy on the local mock; each ends with an
  accessibility audit; (c) interrupted flows: background the app mid-onboarding and
  mid-coach-turn, relaunch, and land in a valid state.
- **Status:** open.

## G7. Prompts and copy fit whoever is using the app

Prerequisite for G8 and for inviting a third person.

- **Check:** no prompt, template or seed contains a hardcoded name, pronoun or goal
  direction (EVAL_REPORT 3, A-1 lists them); a test scans the prompt sources for
  "her", "she", "weight-loss" used about the user; the `dailyBrief` evaluation's
  `wrong_person_pronoun` score is 0 for the chosen model.
- **Status:** open.

## G8. A new person gets their own pixel character from a photo

*"When they first join, upload a pic of them, and then a call to OpenAI to make them a pixelated character like we have done for the two."*

- **Facts that shape it:** Anthropic's models do not generate images, so this needs an
  OpenAI key whatever provider the user chose for chat. The two existing characters have
  several frames each (mood, eyes), drawn by hand from generated art. The per-image price
  of OpenAI's current image models is not published as a table and has to be measured.
- **Check:** (a) an evaluation over the image candidates (`gpt-image-2.6-flare` and
  `-sunburst`, at each quality level) on a fixed set of consented sample photos, scored
  for: transparent background present, square 1024 output, dominant palette size (is it
  pixel art), and the owner's own rating of likeness and of fit with the two existing
  characters; cost per image read from the response's usage; (b) a consent step that says
  the photo goes to OpenAI, before it is sent; (c) the photo is not stored after the
  character is made; (d) with no OpenAI key, a refusal, or a failure, onboarding continues
  with a preset character; (e) the character appears everywhere the two existing ones do
  (Today, the buddy screens, the widgets); (f) request building and response handling are
  tested through `AIRuntime` with a scripted transport.
- **Status:** open. **Needs the owner:** a decision on one image or a set of mood frames
  (cost multiplies), and sample photos for the evaluation.

## G9. Home and Gym as two modes, switched at the top

*"How OpenAI has the chat and the work… sections home, and then a gym section."*

- **Check:** a two-segment switch at the top of the app (Home, Gym) in the style of the
  reference screenshot; Home holds today, food, progress and the coach; Gym holds the
  workout screens; the choice survives relaunch; every screen reachable before is still
  reachable; screenshots of both modes in both themes reviewed by the owner; the UI smoke
  flows of G6 pass through the new navigation.
- **Status:** built (EVAL_REPORT 12); rules tested; rendering seen in the simulator in the
  dark theme. Blocked on the owner: look at `docs/screenshots/review/mode-home.png` and
  `mode-gym.png`, and tap the switch on a build. Still to do after that: the light theme,
  and the UI smoke flows (G6).

## G10. Nutrition is as specific as it can honestly be

*"As specific as possible when it comes to the metrics of what you eat, like the macros."*

- **Check:** a food entry carries fiber, sugars, saturated fat and sodium beside calories,
  protein, carbohydrate and fat, from every source (barcode, label scan, photo, description,
  manual), shown per entry and per day; the estimator's schema asks for them; the
  `meal_describe` dataset gains those columns from the same USDA records and the
  evaluation reports the error on each; a value that is not known is shown as unknown,
  never as zero.
- **Needs the owner before it ships:** the new fields are new CloudKit fields, so the
  Production schema has to be deployed first (`TESTFLIGHT.md` section 3).
- **Status:** open.

## G11. The open defects are closed

- **Check:** every row of the "Open" tables in EVAL_REPORT 3 is either fixed with a test
  that fails on the old code, or marked "won't fix" with the owner's reason. High ones
  first: L-B2, L-B7, L-B9, D-V2.
- **Status:** open (eight fixed on 2026-11-22; about forty open, plus S-1 and S-2 from EVAL_REPORT 13).

## G12. Competitions

*"A new tab, competition, where people can have competitions with each other… I want to specify more about what that means."*

- **Status:** todo (spec needed). Not to be built until the owner writes down what a
  competition is. Notes from the request so far: one against one, or against two; each
  side can have a different target (one person reaching a protein goal or gaining, another
  staying under a range or a baseline).

## G13. The app is back on the phones and does not expire again

*"We can worry about getting the app last."*

- **Check:** build uploaded to TestFlight and opening on both phones with their data
  intact (the "data survives an update over an expired build" claim is unconfirmed until
  seen); a scheduled re-upload or an unlisted App Store release in place (EVAL_REPORT 7).
- **Status:** open, deliberately last. A signed archive of 2.1 (16) exists.

## G14. The chat holds up

*"If the chat is too long, it just won't load… if I scroll up maybe it lets me… the text isn't selectable, or there are no standard features like copy, or ask the AI about this specific text."*

- **Check:** `docs/chat-standards.md` compares each feature and failure with how
  established chat apps handle it; the chat opens in measured, recorded time at 200, 1,000
  and 5,000 messages and loads earlier messages on scrolling up without the view jumping;
  text in a reply can be selected and copied, a message can be copied and shared, and a
  passage or a message can be quoted to the coach; every failure (offline, timeout, bad
  key, rate limit, overload, a cut-off reply, a refusal) has its own message and action,
  the user's message is never lost and a failed turn can be retried without a duplicate;
  the turn logic lives outside the view with a test for every branch on both providers'
  wire formats; screenshots reviewed by the owner.
- **Status:** in progress (EVAL_REPORT 20). Remaining: a stable scroll position on every
  load of earlier messages; a real provider and a phone; regenerate, edit and resend,
  streaming; the owner's review of `docs/screenshots/review/chat-*.png`.
