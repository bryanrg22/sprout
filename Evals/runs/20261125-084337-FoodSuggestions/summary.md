## foodSuggestions on `food_suggestions/v1` (18 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 54 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 1.9 | 2.3 | 2056 / 0 | 336 | 0.00037 | 0.37 |
| `anthropic:claude-sonnet-5` | 54 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 3.4 | 3.9 | 2122 / 0 | 288 | 0.00713 | 7.13 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 18 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| avoided_foods_absent | 0.417 | 0.833 |
| details_one_sentence | 1.000 | 1.000 |
| model_count_within_schema | 1.000 | 1.000 |
| names_a_logged_food | 0.944 | 0.944 |
| nearby_pick_names_the_place | 1.000 | 1.000 |
| nearby_rule_kept | 1.000 | 1.000 |
| no_banned_phrase | 1.000 | 1.000 |
| nothing_eaten_today_in_a_title | 0.963 | 0.907 |
| one_emoji_each | 1.000 | 1.000 |
| shown_within_schema | 1.000 | 1.000 |
| titles_2_to_5_words | 0.741 | 0.963 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| (none) | | |

