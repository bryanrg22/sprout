# Changelog

What changed, per version, for the people using the app and for the people building it.
Sections cited as "EVAL_REPORT n" are in `docs/EVAL_REPORT.md`.

## Unreleased (will ship as 2.1, build 16)

### Fixed

- **The widget no longer shows someone else's numbers.** When it could not read your
  data (after a phone restart, before the first unlock) it drew a built-in sample profile
  as if it were yours. It now shows "Open Sprout to refresh" and retries in five minutes
  (EVAL_REPORT 11).
- The widget's calories, steps and water reset at midnight instead of showing yesterday's
  totals until the app is opened.
- **On OpenAI's newer models, "log 20 oz of water" logged one bottle instead.** Found by
  the model comparison, fixed, and re-measured on five models (EVAL_REPORT 10).
- The "good to see you" note after a few days away is no longer thrown away after being
  rewritten (its own wording tripped the app's guardrail).
- **Privacy:** turning off "Share my full stats with your buddy" now actually stops
  your weight, calories, macros and food names from being uploaded. Before, they were
  uploaded and only hidden on your buddy's screen (EVAL_REPORT 3, D-V1).
- The Nutrients tab no longer saves a meal to yesterday when the app was left open
  overnight (L-B1).
- The "your goals changed since this plan was built" notice clears after a rebuild (L-B3).
- A protein target set through Vita without a plan is kept after a relaunch (L-B4).
- OpenAI models from the 6.x families can be used: the client chose the endpoint and
  token parameter by name prefix and would have sent them a request they reject
  (EVAL_REPORT 4).

### Added

- **Home and Gym.** A switch at the top of Today and of Workouts moves between everyday
  tracking (Today, Nutrients, Progress, the coach) and the workout screens. The app
  reopens on whichever you left it on (EVAL_REPORT 12).

### Changed

- The daily brief is written by `claude-haiku-5-5` (Anthropic) or `gpt-6-luna` (OpenAI),
  chosen by measurement: equal or better on every case at a seventh and a quarter of the
  cost of the models they replace (EVAL_REPORT 10).

### For developers

- The AI clients can run under a scoped runtime (key, provider, model, transport,
  usage sink), so they are testable without a network or a stored key.
- Every model call names its task (`AITask`); per-task defaults are chosen by
  measurement (`AIConfig.measuredDefaults`, empty until the first evaluation is run).
- An evaluation harness (`Evals/`, `VictoriaEvals/`) with three datasets and their graders.
- CI (`.github/workflows/ci.yml`): tests with a minimum count, a Release build, a secret
  scan, tooling checks.
- Records: `docs/EVAL_REPORT.md`, `VictoriaTests/LEDGER.md`, `docs/test-evidence/`,
  `docs/DEVELOPING.md`, `AGENTS.md` as the single instruction file.
- Tests: 443 → 516 unit tests, plus 18 offline evaluation self-tests.
- First live model comparison: ten models, three tasks, 3,636 graded attempts, $6.23
  (EVAL_REPORT 10). `docs/GOALS.md` lists the objectives and the `/goal` condition that
  works through them.

### Known and open

Listed with severity in EVAL_REPORT 3. The ones a user is most likely to meet: with a
plan, changing your goal does not change your targets until the plan is rebuilt (L-B2);
asking Vita to switch to kilograms corrupts weights (L-B7); widgets show yesterday's
numbers until the app is opened (L-B5); a mistyped buddy code says "You're connected!"
(D-V2).

## 2.1 (build 15), uploaded 2026-07-13

Travel-aware insights, the editable "What Vita has learned" notes, a full plan rebuild
when goals change, and a cache for plan research. This TestFlight build stopped opening
on 2026-10-11, 90 days after upload (EVAL_REPORT 7).

## 2.0 (build 14) and earlier

See `git log`.
