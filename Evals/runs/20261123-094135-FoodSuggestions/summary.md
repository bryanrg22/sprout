## foodSuggestions on `food_suggestions/v1` (18 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 4.4 | 6.0 | 1754 / 0 | 294 | 0.00322 | 3.22 |
| `anthropic:claude-haiku-5-5` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.0 | 2.2 | 2056 / 0 | 332 | 0.00037 | 0.37 |
| `anthropic:claude-sonnet-5` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 3.9 | 5.6 | 2122 / 0 | 285 | 0.00710 | 7.10 |
| `anthropic:claude-sonnet-5-5` | 54 | 0% | **0%** | 0%–7% | 0% 0% 0% | 0.0 | 0.0 | 0 / 0 | 0 | 0.00000 | 0.00 |
| `openai:gpt-4.1-mini` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 4.5 | 5.1 | 1010 / 0 | 125 | 0.00060 | 0.60 |
| `openai:gpt-5.6-luna` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.5 | 2.9 | 1002 / 0 | 162 | 0.00039 | 0.39 |
| `openai:gpt-5.6-terra` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 3.7 | 5.2 | 1002 / 0 | 230 | 0.00477 | 4.77 |
| `openai:gpt-6-luna` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.3 | 2.6 | 1002 / 0 | 149 | 0.00017 | 0.17 |
| `openai:gpt-6.1-terra` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 3.4 | 4.3 | 1002 / 0 | 133 | 0.00167 | 1.67 |
| `openai:gpt-6.2-sol` | 54 | 100% | **100%** | 93%–100% | 100% 100% 100% | 3.3 | 3.9 | 1023 / 0 | 131 | 0.00335 | 3.35 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| avoided_foods_absent | 0.333 | 0.583 | 0.917 |  | 0.417 | 0.583 | 1.000 | 0.500 | 1.000 | 1.000 |
| details_one_sentence | 0.870 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| model_count_within_schema | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| names_a_logged_food | 0.944 | 0.981 | 0.944 |  | 0.685 | 0.963 | 0.944 | 0.944 | 0.944 | 0.944 |
| nearby_pick_names_the_place | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| nearby_rule_kept | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_banned_phrase | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| nothing_eaten_today_in_a_title | 0.944 | 0.944 | 0.963 |  | 1.000 | 0.963 | 1.000 | 0.981 | 1.000 | 1.000 |
| one_emoji_each | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| shown_within_schema | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| titles_2_to_5_words | 0.889 | 0.759 | 0.963 |  | 0.907 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 |  | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| alex-breakfast-nothing-yet | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-dinner-big-gap-nearby | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-late-snack-nearly-there | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-lunch-little-history | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-lunch-under-protein | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-maintain-dinner | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-vegan-breakfast | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-vegan-dinner | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-breakfast-nothing-yet | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-breakfast-treats-logged-most | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-dinner-on-target-nearby | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-dinner-protein-already-hit | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-lunch-nearby-no-category | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-lunch-under-protein | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-maintain-snack-nearby | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-snack-trend-unknown | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-vegetarian-dinner | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-vegetarian-lunch | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-sonnet-5-5`: badResponse("tool_choice: type \"tool\" and \"any\" are not supported for this model.")

