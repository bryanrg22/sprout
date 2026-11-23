# Evals

How a model is chosen for a task: the app's real code path is run against a labelled
dataset on every candidate model, and the numbers decide. Results are written up in
[`docs/EVAL_REPORT.md`](../docs/EVAL_REPORT.md); a default in
`AIConfig.measuredDefaults` cites the section that measured it.

## What is here

| Path | What it is |
|---|---|
| `datasets/<task>/v<n>.jsonl` | Labelled cases, one JSON object per line. A released version is never edited: a change is a new `v<n+1>` file, so old results stay comparable. |
| `datasets/meal_describe/fetch_usda.py`, `build_v1.py`, `build_v3.py` | How the meal dataset's ground truth is produced from USDA FoodData Central (cached in `usda_cache.json`; CI rebuilds `v1.jsonl` and diffs it). `build_v3.py` adds the label nutrients of the same records; `GraderTests` recomputes every v3 column from the cache. |
| `run.sh` | Runs one live evaluation and leaves a record directory. **Spends money.** |
| `summarize.py` | Records → `summary.md` / `summary.json`: pass rate with a 95% Wilson interval, per-repeat spread, every score, latency, tokens, cost. |
| `prices.json` | List prices read from the vendors' pricing pages, with the date. A model not listed gets no cost, never an estimate. |
| `runs/<utc>-<eval>/` | One directory per run: `manifest.json` (commit, dataset hashes, models, repeats), `records-<task>.jsonl`, `summary.md`. |
| `../VictoriaEvals/` | The harness (`EvalHarness.swift`), the graders (`Graders.swift`), the live evaluations (`LiveEvals.swift`) and their offline self-tests (`GraderTests.swift`). |

## The evaluations

| Eval | Task | What runs | Pass rule |
|---|---|---|---|
| `MealDescribe` | `mealDescribe` | `FoodPhotoAnalyzer.analyze(description:)` on `meal_describe/v3` | total calories within 20% of the USDA total (the US labelling tolerance) |
| `CoachToolChoice` | `coachTurn` | `CoachContext.systemParts` + `CoachTools.schemas` + `chatWithTools`, then `CoachTools.parse` | the right decision (act or answer), the right action, the right value, as the app itself resolves the call |
| `DailyBrief` | `dailyBrief` | `DailyBriefService.pick` + `rephrase` | every number kept, none invented, and no wrong-person pronoun |

Each also records scores that do not decide the pass (macro error in grams, whether
the model's own calorie range contained the truth, whether a tool call was valid,
sentence counts, and so on); `summary.md` lists them all.

### The label nutrients in `MealDescribe`

The estimator is asked for four nutrients beyond the macros: fiber, total sugars, saturated
fat and sodium, each of which it may answer as null ("not known"). `meal_describe/v3` is
v1's fourteen cases with the label nutrients of the same USDA records added, and the grader
reports, per nutrient, without changing the pass rule:

| Score | Meaning | Recorded when |
|---|---|---|
| `fiber_g_abs_error`, `sugars_g_abs_error`, `saturated_fat_g_abs_error`, `sodium_mg_abs_error` | absolute error in the unit in the name (grams; milligrams for sodium) | the truth is known and the model gave a number |
| `<name>_answered` | 1 if the model gave a number, 0 if it said not known | the truth is known |
| `<name>_unknown_when_no_basis` | 1 if the model said not known, 0 if it gave a number anyway | the case lists the nutrient in `no_basis` |

Read `_abs_error` together with `_answered`: an error is averaged only over the attempts
that answered, so a model that abstains on the hard cases looks more accurate than one that
answers them all. A column that is null in the dataset (USDA does not list that nutrient
for an ingredient, or the record does not match the description; see `build_v3.py`) is not
graded. No v3 case has a `no_basis` label, because every v3 portion is a named food in
grams; the score exists for a later version with vague descriptions.

**v3 has to be built before the first run**, and was not when this was written: the USDA
demo key was rate-limited. One request, then a build with no network:

```bash
python3 Evals/datasets/meal_describe/fetch_usda.py --details-only
python3 Evals/datasets/meal_describe/build_v3.py
```

## Running one

```bash
# a cheap pilot: 3 cases, one repeat (needs meal_describe/v3.jsonl; see above)
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

- `meal_describe/v1` and `v3` state every portion in grams, so they measure food knowledge
  and arithmetic, not portion estimation, which is the hard part of the real task. For the
  same reason v3 cannot show whether a model says "not known" when it should: every case
  gives it a basis. Its sodium truths are for unseasoned reference foods, so a model that
  assumes salt was added will show a sodium error that is partly the dataset's.
- Added sugars, trans fat, cholesterol, vitamin D, calcium, iron and potassium are columns
  in v3 (where USDA lists them) that nothing grades: the estimator is not asked for them
  (`docs/nutrition-detail.md` section 5).
- There is no meal-photo dataset yet. Nutrition5k (CC BY 4.0) is the public ground
  truth; published per-dish calorie error for general vision models is 30–45%.
- `coach_tool_choice/v1` covers the first turn of a conversation only: no
  multi-turn tool chains, no confirm/decline follow-ups, no photos.
- The labels were written by reading the tool descriptions. They are the intended
  behaviour as understood on 2026-11-22 and should be reviewed by the owner.
