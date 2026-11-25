## foodSuggestions on `food_suggestions/v1` (18 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 54 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 3.5 | 4.0 | 2122 / 0 | 288 | 0.00712 | 7.12 |
| `anthropic:claude-sonnet-5-5` | 54 | 89% | **89%** | 81%–96% | 78%–95% | 89% 89% 89% | 3.6 | 4.4 | 1810 / 0 | 269 | 0.00631 | 6.31 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 18 | -11.1% | -18.5% to -3.7% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| avoided_foods_absent | 0.750 | 0.727 |
| details_one_sentence | 1.000 | 1.000 |
| model_count_within_schema | 1.000 | 1.000 |
| names_a_logged_food | 0.944 | 0.938 |
| nearby_pick_names_the_place | 1.000 | 1.000 |
| nearby_rule_kept | 1.000 | 1.000 |
| no_banned_phrase | 1.000 | 1.000 |
| nothing_eaten_today_in_a_title | 0.907 | 1.000 |
| one_emoji_each | 1.000 | 1.000 |
| shown_within_schema | 1.000 | 1.000 |
| titles_2_to_5_words | 0.907 | 0.917 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| alex-breakfast-nothing-yet | 3/3 | 2/3 |
| alex-dinner-big-gap-nearby | 3/3 | 2/3 |
| alex-lunch-under-protein | 3/3 | 2/3 |
| sam-breakfast-treats-logged-most | 3/3 | 2/3 |
| sam-dinner-on-target-nearby | 3/3 | 2/3 |
| sam-vegetarian-dinner | 3/3 | 2/3 |

**Errors**

- `anthropic:claude-sonnet-5-5`: decoding("the answer broke the schema (answer.suggestions: 1 items, at least 2)")

