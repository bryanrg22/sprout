# Evals

How a model is chosen for a task: the app's real code path is run against a labelled
dataset on every candidate model, and the numbers decide. Results are written up in
[`docs/EVAL_REPORT.md`](../docs/EVAL_REPORT.md); a default in
`AIConfig.measuredDefaults` cites the section that measured it.

## What is here

| Path | What it is |
|---|---|
| `datasets/<task>/v<n>.jsonl` | Labelled cases, one JSON object per line. A released version is never edited: a change is a new `v<n+1>` file, so old results stay comparable. |
| `datasets/meal_describe/fetch_usda.py`, `build_v1.py` | How the meal dataset's ground truth is produced from USDA FoodData Central (cached in `usda_cache.json`; CI rebuilds `v1.jsonl` and diffs it). |
| `run.sh` | Runs one live evaluation and leaves a record directory. **Spends money.** |
| `summarize.py` | Records → `summary.md` / `summary.json`: pass rate with a 95% Wilson interval, per-repeat spread, every score, latency, tokens, cost. |
| `prices.json` | List prices read from the vendors' pricing pages, with the date. A model not listed gets no cost, never an estimate. |
| `runs/<utc>-<eval>/` | One directory per run: `manifest.json` (commit, dataset hashes, models, repeats), `records-<task>.jsonl`, `summary.md`. |
| `../VictoriaEvals/` | The harness (`EvalHarness.swift`), the graders (`Graders.swift`), the live evaluations (`LiveEvals.swift`) and their offline self-tests (`GraderTests.swift`). |

## The evaluations

| Eval | Task | What runs | Pass rule |
|---|---|---|---|
| `MealDescribe` | `mealDescribe` | `FoodPhotoAnalyzer.analyze(description:)` | total calories within 20% of the USDA total (the US labelling tolerance) |
| `CoachToolChoice` | `coachTurn` | `CoachContext.systemParts` + `CoachTools.schemas` + `chatWithTools`, then `CoachTools.parse` | the right decision (act or answer), the right action, the right value, as the app itself resolves the call |
| `DailyBrief` | `dailyBrief` | `DailyBriefService.pick` + `rephrase` | every number kept, none invented, and no wrong-person pronoun |

Each also records scores that do not decide the pass (macro error in grams, whether
the model's own calorie range contained the truth, whether a tool call was valid,
sentence counts, and so on); `summary.md` lists them all.

## Running one

```bash
# a cheap pilot: 3 cases, one repeat
Evals/run.sh MealDescribe "anthropic:claude-haiku-5-5,openai:gpt-6-luna" 1 3

# the real comparison: whole dataset, three repeats
Evals/run.sh CoachToolChoice "anthropic:claude-haiku-5-5,anthropic:claude-sonnet-5-5,openai:gpt-6-luna,openai:gpt-6.1-terra" 3
```

A candidate is `provider:model`, with an optional `@effort` for OpenAI reasoning
effort (`openai:gpt-6.1-terra@none`). Keys are read from `ANTHROPIC_API_KEY` and
`OPENAI_API_KEY` in the environment and are never written to a record.

## Reading a result

- **usable** is the share of attempts that returned something the app could parse.
  A model that fails here is not a candidate, whatever its accuracy on the rest.
- **pass** has a 95% interval beside it. With 14 to 34 cases the interval is wide:
  only a large gap between two models is real. When intervals overlap, the models are
  within noise on quality and the decision goes to cost and latency.
- **per-repeat pass** shows the same cases run again; a spread there is the model's
  own run-to-run variance.
- The default is the cheapest candidate within noise of the best.

## What these datasets do not measure yet

- `meal_describe/v1` states every portion in grams, so it measures food knowledge and
  arithmetic, not portion estimation, which is the hard part of the real task.
- There is no meal-photo dataset yet. Nutrition5k (CC BY 4.0) is the public ground
  truth; published per-dish calorie error for general vision models is 30–45%.
- `coach_tool_choice/v1` covers the first turn of a conversation only: no
  multi-turn tool chains, no confirm/decline follow-ups, no photos.
- The labels were written by reading the tool descriptions. They are the intended
  behaviour as understood on 2026-11-22 and should be reviewed by the owner.
