# VictoriaUITests: UI smoke flows

A small set of XCUITest flows that drive the real app through its main paths, and through
the same paths done out of order, repeated and interrupted (GOALS G6 and G9). They sit on
top of the unit suite: the unit tests prove the logic, these prove the screens are wired to
it.

Nothing here reaches a provider, needs a key, or touches the simulator's real data. Every
launch runs on an in-memory store, and every model call is answered by a script that is
built into the DEBUG app.

## Run

```bash
xcodegen generate
xcodebuild test -project Victoria.xcodeproj -scheme VictoriaUITests \
  -destination 'platform=iOS Simulator,name=Victoria-Dev' \
  -resultBundlePath /tmp/ui.xcresult
python3 tooling/check_xcresult.py /tmp/ui.xcresult --min-tests 25
```

The scheme is separate, so `-scheme Victoria` (the unit suite) neither builds nor runs
these. Read the count from the result bundle, as for the unit suite. One flow:
`-only-testing:VictoriaUITests/CoachFlowTests/testProviderFailureShowsTheErrorAndTheAppStaysUsable`.

There are 25 tests and a run takes about six and a half minutes on one simulator. Today the result
is 10 passed and 5 expected failures. An expected failure is not a pass: it is a flow whose
behaviour assertions all held and which also carries a known defect or a known
accessibility-audit result (see below), kept visible in every result.

The flows read the simulator's clock and locale as they are: run them with an English
(US) locale, and not across midnight (the seeded day is "today").

## Launch arguments

All of these are read in DEBUG builds only. `UITestHooks.plan(arguments:isDebugBuild:)` is
the one place that decides, and it returns the inert plan for a Release build whatever is
passed (`UITestHooksTests`).

| Argument | Effect |
|---|---|
| `--ui-testing` | The store is in memory on the production schema (`AppSchema`), CloudKit off, so every launch starts empty and the simulator's real store is never opened. No system permission alert (notifications, Health, location). No import from Apple Health or a connected tracker. No write to the widget's shared snapshot, and the reminder schedule is left alone. With no script named, the AI layer has no key, so every AI feature takes its no-key path and nothing can reach a provider. |
| `--seed-demo --demo-gain` | Existing arguments. With `--ui-testing` they seed the dark demo profile into the in-memory store. The flows only ever use this profile. Without them the launch is a fresh install and shows onboarding. |
| `--demo-tab <name>` | Existing argument. The flows pass `--demo-tab today` so a launch opens Home on Today whatever mode an earlier launch stored, and `--demo-tab workouts` to open on Gym. Passing no `--demo-tab` lets the stored mode decide, as on a normal launch. |
| `--ui-test-scripted-ai=<name>` | Needs `--ui-testing`. Every model call in the app is answered by the named script instead of the network, and the app behaves as if a key were present. An unknown name stops the launch with the list of known names. |
| `--ui-test-fresh-defaults` | Needs `--ui-testing`. The app's own defaults are cleared before anything reads them: the stored mode, the provider choice and every once-a-day cache of that install on that simulator. `launch` passes it on a flow's first launch and not on a relaunch, so a flow never sees what an earlier flow (or a person using the simulator) left, and a relaunch still sees what the flow itself stored. The app group's defaults are not touched. |
| `--ui-test-store-failure` | Needs `--ui-testing`. The launch behaves as if the on-disk store had failed to open, so a flow can check that it shows "Sprout couldn't open your data" and never onboarding. |

The Home or Gym choice lives in UserDefaults, which outlives the in-memory store. A flow
that can leave Gym stored registers `leaveStoredModeAtHome()` as a teardown block.

## Scripted-AI names

Defined in `Victoria/Services/AI/UITestScriptedAI.swift` (`UITestAIScript`), answered in
Anthropic's wire format so the real client parses them.

| Name | The coach's turn |
|---|---|
| `coach-log-water` | The first reply to a message is a `log_water` tool call for 2 containers. The follow-up, after the tool result, is the prose reply "Scripted reply: logged it." |
| `coach-prose` | The prose reply "Scripted reply: you are doing fine today." |
| `coach-slow` | The same prose reply after 4 seconds, so a flow can leave the app in the middle of a turn. |
| `fail-500` | The provider is down: every call gets HTTP 500, which the client does not retry. |

Only the coach's turn is scripted. Every other model call a screen makes on its own (the
daily brief, the checklist, the quick prompts, the progress recap) gets HTTP 400 at once
under the three `coach-*` scripts, so those features show their template fallback and a
flow sees the same screen on every run. To script one of them, add a case to
`UITestAIScript.reply(to:)` and a test of it to `UITestHooksTests`.

## The flows

| File | Flows |
|---|---|
| `LaunchFlowTests` | a. a fresh install shows the first onboarding screen. b. a seeded launch shows Today and every Home tab opens. l. the coach opened first; Gym opened before Today; Settings and back. q. a store that did not open shows that and never onboarding. |
| `ModeSwitchFlowTests` | c. Home and Gym, the tab bar gone in Gym, and the app reopening in Gym. d. Home's state (a scrolled tab, a half-typed message) survives a trip to Gym. |
| `LoggingFlowTests` | e. a food logged by hand changes Today by its calories. f. logged twice, one deleted, totals right both times. g. water from Today. h. a workout through the log flow. |
| `CoachFlowTests` | i. a tool call that logs water, the reply, Today's figure, and Undo. j. the provider down, twice, and the app still usable. |
| `InterruptionFlowTests` | k. the app backgrounded in the middle of the manual-food sheet, and in the middle of a coach turn. |
| `OnboardingFlowTests` | m. every step in order with nothing filled in ends on a working Today. n. back and forward keeps the place. o. every step passed by swiping: finishing goes back to the one required choice (sex), then finishes. p. leaving in the middle keeps the step; quitting in the middle starts onboarding again. r. Next on the about step asks for a sex before going on. Flows choose a sex as they pass that step. |
| `WorkoutWeekFlowTests` | s. the week card on Workouts counts active days; tapping a day opens it (a logged workout, a tracked one); the arrows move between weeks and stop at this one. |
| `CompetitionFlowTests` | t. the weekly competition in the Buddy hub against the mock buddy: both scores, last week's result, a day's targets on a tap. |
| `UnitsFlowTests` | u. kilograms chosen in Settings reach Progress (trend and weekly rate) and the weigh-in sheet; back to pounds; the two rates agree by the conversion. |

Flows b, c, e, h and i end with `performAccessibilityAudit()` on the screen they finish on
(Progress, Workouts, Today, Workouts again, the coach).

## Accessibility audits

Every audit reports issues today, so each is an expected failure whose reason is the
summary of what it found, with the source lines (`knownIssues:` at the call). The full
list of one run is in the test log as `A11Y-AUDIT | <screen> | <kind> | on screen or not |
<element> | <description>` lines, and attached to the test in the result bundle as
"Accessibility audit: <screen>".

Most of the issues are not on the screen being audited. Home and Gym both stay alive
under the switch and both stay in the accessibility tree (`RootView.swift`, the two
`.accessibilityHidden` lines), so the audit also walks the invisible one. Flow c pins that
defect on its own with an expected failure. When it is fixed, the audits shrink to the
"on screen" issues and the summaries need rewriting; the strict expected failure in flow c
will say so first.

## How a flow is written

- Subclass `SproutUITestCase` and start with `launch(...)`. Each flow launches fresh.
- Find controls by accessibility identifier, never by visible copy: the copy is reworded,
  identifiers are not. The identifiers are constants in `Victoria/App/AccessibilityID.swift`,
  which is compiled into the app and into this bundle. To reach a new control, add a
  constant there and one `.accessibilityIdentifier(...)` line on the control.
- Read a figure with `figure(_:_:)`, which takes the first whole number out of a label, so
  the words around the number can change.
- Assert what the user can see. Home and Gym both stay in the accessibility tree whichever
  is showing, so "exists" is not "shown": use `waitShown` / `isShown` (on screen and
  hittable) for anything that is on a surface.
- No fixed sleeps. Wait with `wait("what") { condition }`, `waitShown`, or
  `waitForExistence`; each returns as soon as its condition holds.
- If a flow finds a real defect, leave the app and the flow as they are: wrap that one
  assertion in `XCTExpectFailure("<what is wrong, file:line>")`. If an audit reports
  issues, pass `knownIssues:` to `auditAccessibility` with the summary. Both are strict:
  the day the defect is fixed, the test says the expected failure did not happen and the
  wrapper is removed.

## Adding a flow

1. Add the identifiers the flow needs (`AccessibilityID.swift` and the views).
2. Write the test in the file of its area, or a new `<Area>FlowTests.swift`, then
   `xcodegen generate` (sources are globbed).
3. Run it three times in a row before relying on it; a flow that passes once is not yet
   known to be stable.
4. If it needs a model reply that no script gives, add the script (see above) rather than
   stubbing anything in the test.
