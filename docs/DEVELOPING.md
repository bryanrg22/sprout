# Developing Sprout

How the app is built, checked and recorded. `AGENTS.md` is the short version; this is
the long one. Read section 3 before a first change.

## 1. Setup

- macOS with Xcode 26.4, `brew install xcodegen gitleaks`.
- The repository at `~/dev/GitHub/sprout`. Not under `~/Documents`, `~/Desktop` or any
  other iCloud-synced folder (EVAL_REPORT 2).
- A simulator named `Victoria-Dev`:
  `xcrun simctl create Victoria-Dev "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-26-4`
- `xcodegen generate` after adding or moving any file. `Victoria.xcodeproj` is generated;
  edit `project.yml`.

Schemes: `Victoria` (the app and its unit tests) and `VictoriaEvals` (the evaluation
harness; offline self-tests by default, live evaluations only through `Evals/run.sh`).

## 2. The records, and what each is for

| Record | Answers | Updated when |
|---|---|---|
| `docs/EVAL_REPORT.md` | What was measured or found, and what it decided. Numbered sections, never rewritten. | Any measurement, audit or decision. |
| `VictoriaTests/LEDGER.md` | What each test file protects, and what no test covers. | A test file is added, or the behaviour it pins changes. |
| `docs/test-evidence/<label>/` | Exactly what passed for a version: commit, toolchain, counts, coverage, warnings. | Before a TestFlight upload, and when the suite changes materially. |
| `Evals/runs/<run>/` | One live evaluation: manifest, every record, the summary table. | Every live run, automatically. |
| `Evals/datasets/<task>/v<n>.jsonl` | The labelled cases. Immutable once a result cites them. | A new version, never an edit. |
| `CHANGELOG.md` | What changed for the user and for the developer, per version. | Every change. |
| `docs/audits/<date>/` | Long-form audits and research that a report section summarises. | When one is done. |

## 3. The method

1. **Research the standard first.** Before designing, find how the established work does
   it and write that down with its source. The standard can be improved on only after it
   is understood.
2. **Make no assumptions; verify empirically.** Run it and read the output. A count comes
   from the result bundle, not from an exit code through a pipe. A surprising result is
   re-run before it is written down.
3. **Measure alternatives side by side.** For a model, a prompt, a reasoning effort or a
   threshold: a labelled dataset, a baseline, every candidate on the same cases with at
   least three repeats, and accuracy, cost, tokens and latency in one table. The default
   is the cheapest candidate within noise of the best. "Within noise" means the 95%
   intervals overlap; with fewer than about 50 cases only a gap of 15 points or more is
   real.
4. **Test every path**, and the regression that the existing path is unchanged. Logic
   that depends on the date takes the date, the calendar and the time zone as arguments.
5. **Record every number** in the record that owns it (section 2).
6. **Be honest.** Three words are kept apart everywhere: *verified* (run, output in
   hand), *read* (the code path was traced, not run), *open*. A pull request says what
   was not verified.

## 4. Recipes

### Run the gates and capture the evidence

```bash
tooling/evidence/capture.sh v2.1.0-b16
```

Regenerates the project, runs the unit suite with coverage, the evaluation self-tests, a
Release build and the secret scan, and writes `docs/test-evidence/v2.1.0-b16/`. It exits
non-zero if a gate failed and writes the record either way.

### Run just the tests

```bash
xcodegen generate
xcodebuild test -project Victoria.xcodeproj -scheme Victoria \
  -destination 'platform=iOS Simulator,name=Victoria-Dev' -resultBundlePath /tmp/t.xcresult
python3 tooling/check_xcresult.py /tmp/t.xcresult --min-tests 780
```

### Verify a store

```bash
python3 tooling/verify_store.py "<...>/Containers/Shared/AppGroup/<id>/Library/Application Support/default.store"
python3 tooling/verify_store.py --self-test
```

Read-only (SQLite `mode=ro`). Prints every entity table with its row count and the per-day
food, water, steps and weigh-in totals of the last 14 days, and exits 1 on a NULL `id`, a
negative calorie, macro, weight, ounce or step value, or two rows on one day in the steps,
sleep or vitals table. Days are counted in `--tz` (default: this machine's zone).

### Test code that calls a model

Nothing in the test suite reaches a provider. Scope a runtime with a scripted transport
and call the real feature:

```swift
let transport = ScriptedTransport([.json(200, recordedProviderResponse)])
let runtime = AIRuntime(provider: .anthropic, apiKey: "test-key-not-real", transport: transport)
let estimate = try await AIRuntime.$current.withValue(runtime) {
    try await FoodPhotoAnalyzer.analyze(description: "a medium banana")
}
// assert on `estimate`, and on `transport.body()` for what was sent
```

### Add an AI feature

1. Add a case to `AITask` with its tier, and its row to `AITaskModelTests`.
2. Call the model through `AIClient.make()` / `makeFull()` with
   `model: AIConfig.model(for: .yourTask)`; gate on `AIConfig.hasActiveKey`; keep a
   template or manual fallback.
3. Keep the prompt builder and the response parser as functions a test can call, and
   test the parser against scripted responses, including a malformed one.
4. Add a dataset (`Evals/datasets/<task>/v1.jsonl`), a grader with its own tests in
   `GraderTests`, and a live evaluation in `LiveEvals`.

### Choose or change a default model

1. State the cost estimate and get the owner's approval.
2. `Evals/run.sh <Eval> "<candidates>" 3` on the whole dataset.
3. Write the EVAL_REPORT section: the table from `summary.md`, the run id, what was
   chosen and why, what was not measured.
4. Add or change the row in `AIConfig.measuredDefaults` citing that section, and update
   `AITaskModelTests` in the same change.

### Ship a TestFlight build

1. Bump `CURRENT_PROJECT_VERSION` in `project.yml` (three places), `xcodegen generate`.
2. `tooling/evidence/capture.sh v<version>-b<build>`; all gates green.
3. Add the version to `CHANGELOG.md`. Commit.
4. Archive and upload from Xcode (the owner's action). If the build adds a CloudKit
   field, deploy the schema to Production first (`TESTFLIGHT.md` section 3).
5. A TestFlight build stops opening 90 days after upload (EVAL_REPORT 7).

## 5. Definition of done

- The gates are green and the count in the result bundle went up by the tests added.
- A defect fix has a test that fails on the old code.
- The record that owns the change is updated in the same change (section 2).
- Anything not verified is written down as not verified.
