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
| `regrade-text.sh` | Grades the text tasks' past answers again with the graders as they are now, and rebuilds what the app shows (`shown`) for the memory fold and the checklist. Calls no model. |
| `judge.py`, `judge_rubrics.json`, `judge_agreement.py`, `labeling/` | The quality judge, its rubrics, and the check of the judge against the owner's labels (below). `judge.py` **spends money**. |
| `regrade-avatars.sh` | Grades a past `Avatar` run's saved characters again with the graders as they are now, and writes `regrade-avatar.json` in that run. Calls no model and spends nothing. Only on the machine that made the run: the characters are never committed. |
| `summarize.py` | Records → `summary.md` / `summary.json`: pass rate with a 95% Wilson interval, per-repeat spread, every score, latency, tokens, cost. |
| `prices.json` | List prices read from the vendors' pricing pages, with the date. A model not listed gets no cost, never an estimate. |
| `runs/<utc>-<eval>/` | One directory per run: `manifest.json` (commit, dataset hashes, models, repeats), `records-<task>.jsonl`, `summary.md`. |
| `../SproutEvals/` | The harness (`EvalHarness.swift`), the graders (`Graders.swift`), the live evaluations (`LiveEvals.swift`) and their offline self-tests (`GraderTests.swift`). |

## The evaluations

| Eval | Task | What runs | Pass rule |
|---|---|---|---|
| `MealDescribe` | `mealDescribe` | `FoodPhotoAnalyzer.analyze(description:)` on `meal_describe/v3` (14: v1's cases with the label nutrients) | total calories within 20% of the USDA total (the US labelling tolerance) |
| `MealDescribeHousehold` | `mealDescribe` | the same call on `meal_describe/v4` (22): foods in household measures with no weight ("a medium banana", "half a salmon fillet"); the truth is USDA's own gram weight for that measure (`build_v4.py`) | total calories within 20% |
| `MealPhoto` | `mealPhoto` | `FoodPhotoAnalyzer.analyze(imageData:)` on `meal_photo/v1` (30 Nutrition5k plates, CC BY 4.0, see its `ATTRIBUTION.md`), each photo prepared as `PhotoFoodFlow` prepares it | total calories within 20% of the weighed plate |
| `CoachConversation` | `coachTurn` | `CoachTurnEngine.send` on `coach_conversations/v1` (30): the fixture user's data and the earlier turns in an in-memory store, then the newest message, exactly as the chat sends it (tools applied or proposed as in the app) | a usable reply; quality is for `judge.py` (the record's `given` holds the data, notes and conversation) |
| `PlanBuild` | `planBuild` | the plan's write call on `plan_build/v1` (15): the app's own system prompt, user turn, schema and structured call, **without** the live research phase, so the authoring model is isolated (`PlanEvals.swift` states every difference) | it decodes, has a headline, assessment, strategy and range, the range starts at or above the safe calorie floor, protein is set, 3 to 5 insights, no wrong-person pronoun |
| `PlanReview` | `planReview` | `PlanService.review` on `plan_review/v1` (14): an existing plan and the data since, in an in-memory store | the same as the build |
| `PlanResearch` | `planResearch` | the research call with its web-search tool on the build cases' words; `ResearchCache` is never read or written. **Each call reads about 85,000 tokens of search results** (about $0.45 on `claude-opus-4-8`, plus $0.05 for five searches) | a brief came back and the model searched |
| `CoachToolChoice` | `coachTurn` | `CoachContext.systemParts` + `CoachTools.schemas` + `chatWithTools`, then `CoachTools.parse` | the right decision (act or answer), the right action, the right value, as the app itself resolves the call |
| `DailyBrief` | `dailyBrief` | `DailyBriefService.pick` + `rephrase` | every number kept, none invented, and no wrong-person pronoun |
| `InsightLine` | `insightLine` | `DailyInsightEngine.bestInsight` + `InsightPhraser.rephrase` on `insight_line/v1` (19 cases) | the line is used (the sanitiser kept it), every number of the template is kept, none is added beyond the template and the observation, and no wrong-person pronoun |
| `WeeklyReflection` | `weeklyReflection` | `WeeklyReflection.written` on `weekly_reflection/v1` (16) | the note is used, it states no number it was not given (the day counts, and the person's own note), and no wrong-person pronoun |
| `OnboardingNote` | `onboardingNote` | `OnboardingCoachMessage.written` on `onboarding_note/v1` (15) | the note is used, it states no number that is not in the person's own note, no wrong-person pronoun, and no phrase that names a goal other than the one it was told |
| `MemoryFold` | `memoryFold` | `CoachMemoryService.consolidate` on `memory_fold/v1` (12), the reply graded as `CoachMemoryService.parse` stores it | the reply parses, all four planted facts are in the notes, the fact the user took back is not still stated, the notes passed in are kept, and both blocks are within the service's budgets |
| `ProgressSummary` | `progressSummary` | `ProgressSummaryService.summary(snapshot:)` on `progress_summary/v1` (15) | the recap decodes, it has 2 to 4 highlights and none blank, no number that is not in the snapshot, no wrong-person pronoun, and none of the prompt's banned phrases |
| `FoodSuggestions` | `foodSuggestions` | `FoodSuggestionService.suggestions(for:)` on `food_suggestions/v1` (18) | the reply decodes, 2 to 3 suggestions are shown and no emoji is blank, a "nearby" pick only when a place was offered and at most one, no wrong-person pronoun, and none of the prompt's banned phrases |
| `CoachPrompts` | `coachPrompts` | `CoachPromptService.generate` on `coach_prompts/v1` (16) | the reply decodes, 2 to 3 chips are left after the app's own cleaning, no number that is not in what the model was given, and no wrong-person pronoun |
| `ChecklistPlan` | `checklistPlan` | `ChecklistPlanService.make` on `checklist_plan/v1` (16) | the reply decodes, 3 to 5 tasks and 4 to 8 chips are left after the app's own cleaning, and no wrong-person pronoun |

Each also records scores that do not decide the pass (macro error in grams, whether
the model's own calorie range contained the truth, whether a tool call was valid,
sentence counts, and so on); `summary.md` lists them all.

### The eight wording and structure evaluations

The last eight rows were added on 2026-11-23 and were first run on 2026-11-24 and 2026-11-25
(EVAL_REPORT 35, 36). Their graders and datasets pass their offline tests (`GraderTests`).

Every rule comes from the feature's own prompt, schema or sanitiser, and each grader states
its rule beside it in `Graders.swift`. Three things hold for all eight:

- **A discarded reply is not usable, and is kept.** The three notes fall back to a template
  when their sanitiser rejects a reply (a banned phrase, a digit, too long), and the structured
  features throw when a reply does not decode. The evaluation calls the app's own function
  under a recording transport (`EvalRunner.recording`), so the record holds what the model
  wrote together with the reason it was not used.
- **What the app would show is what is graded.** `CoachPromptService` and `ChecklistPlanService`
  drop banned titles, cut long ones and cap the count before anything is shown; the pass rule
  reads what is left, and scores (`none_dropped_by_the_app`, `none_cut_short`,
  `model_count_within_schema`, `icons_known_share`) say what the cleaning had to do.
- **`claude-sonnet-5-5` scores 0% usable on the four structured tasks**, because each forces a
  tool call and that model rejects a forced tool choice (EVAL_REPORT 10, defect 2).

The cases use the two fixture users (Alex, a man who is gaining; Sam, a woman who is losing).
A few give one of them a goal of holding steady, because the features word that goal
differently. `memory_fold/v1` plants, in each transcript, an allergy, an injury, a food
preference and a schedule constraint, one plan the user states and later takes back, some
chit-chat, and one number the app owns; in two cases the fact taken back was already in the
notes. `coach_prompts/v1` and `checklist_plan/v1` hold the same sixteen situations, because
both features read the same inputs.

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

v3 was built on 2026-11-25 (EVAL_REPORT 36) with one request and then a build with no
network; CI rebuilds it and diffs, as it does v1:

```bash
python3 Evals/datasets/meal_describe/fetch_usda.py --details-only
python3 Evals/datasets/meal_describe/build_v3.py
```

## Judging quality (`judge.py`)

The graders above check rules. Whether an answer is any good is judged by a model:
`judge.py <run> --baseline <provider:model> --candidate <provider:model>` asks
`claude-opus-5-5` (Batches API, half price; **spends money**, about $0.25 to $0.55 a task)
which of two recorded answers to the same input is better, and writes `<run>/judge-<candidate>.json`.

- Blind, and in both orders: a verdict that changes with the order counts as a tie.
- `tie` and `both_bad` are allowed; the answers are passed as data; the verdict comes back
  through a JSON schema, reasoning first.
- The rubric per task is in `judge_rubrics.json`, written from the feature's own prompt.
- Controls: a real answer against an empty one, "I don't know." and the answer to the most
  different case. A task whose controls fail is not to be trusted.
- It judges what the app **shows**: each record's `shown` field (a structured reply decoded
  and cleaned, the memory as `parse` stores it), rebuilt for older runs by
  `regrade-text.sh`. For the memory fold and the checklist the raw reply is not what the
  person sees, and the judge refuses those without it.
- `net` = (candidate wins − baseline wins) / pairs, with a 95% case-bootstrap interval.

The judge is trusted only as far as it agrees with a person. `judge_agreement.py sample`
draws pairs for the owner to label blind (`labeling/`: the page, the pairs, and the key that
is never shown), and `judge_agreement.py score <labels.json>` reports the agreement. The target
is the 80% two people reach in MT-Bench. A model switch that rests on the judge alone waits
for that check.

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
- `meal_photo/v1` is 30 cafeteria plates photographed from above on one tray, in one
  cafeteria: no restaurant plates, no bowls of soup, no packaged food, no side views. Its
  published comparison (Thames et al. 2021) is 18.8% calorie error from overhead RGB-D and
  26.1% from 2D video frames for models trained on the dataset, and 41–53% for people.
- `coach_tool_choice/v1` covers the first turn of a conversation only.
  `coach_conversations/v1` covers a next reply after three to five turns, but not a reply to
  a photo, a confirm or decline of a proposed change, or a conversation long enough to fold.
- The labels were written by reading the tool descriptions. They are the intended
  behaviour as understood on 2026-11-22 and should be reviewed by the owner.
- The eight wording and structure evaluations are code-graded checks of format and
  faithfulness. Whether the advice is good or the tone right is judged by `judge.py`
  (above), which a person has not yet checked: until the owner's labels are scored, its
  verdicts are evidence, not a decision.
- Their number rule is strict in ways a reader must know before trusting a failure. A figure
  the model worked out itself ("down 3.6 lb", from two weights in the snapshot) or rounded
  counts as not given. A number word used for something else ("the two of us") fails a weekly
  or an onboarding note. "One" is never read as a number, so a count of one cannot be checked.
- The pronoun rule is word-based. A third person from the user's own note, spoken of with the
  pronoun the reader does not use ("my brother ... he", in a note of Sam's), is read as a
  wrong-person pronoun. Such a failure has to be read before it is counted.
- `memory_fold/v1` finds a fact by keyword. A fact kept in other words is counted as lost, and
  a note is read as recording a retraction when the clause holds a word such as "not",
  "cancelled" or "pulled out" (`Graders.stillStates`), which a clause can hold for another
  reason. Neither the summary's accuracy nor anything the notes add is checked.
- `FoodSuggestionEngine.Context` has no field for a diet or an allergy, so the feature is never
  told one and no pass rule can hold it to one. Four cases log only vegetarian or only vegan
  foods and record `avoided_foods_absent` as a score. The amounts a suggestion states are not
  checked (the prompt asks for them), nor is whether a pick suits the meal.
- `progress_summary/v1` writes its snapshots through a copy of the wording of
  `ProgressSummaryCard.buildSnapshot`, which is a private method of the view. A test holds
  every label to the view's source; the numbers in the cases are written by hand, not computed
  by `TrendCalculator`.
- `coach_prompts/v1` and `checklist_plan/v1` build the fixture user's logs relative to the day
  of the run, so the data summary (weekday names, "Today", "Yesterday") differs from one day
  to the next. A session is given as "days ago", never as a date.
- 12 to 19 cases each resolve only large differences, and every case is a single first call.
