## foodSuggestions on `food_suggestions/v1` (18 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 54 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 3.5 | 4.8 | 1813 / 0 | 286 | 0.00649 | 6.49 |
| `openai:gpt-6.2-sol` | 54 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 3.9 | 4.7 | 1022 / 0 | 131 | 0.00336 | 3.36 |

**Compared with `anthropic:claude-sonnet-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 18 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| at_least_two_shown | 0.963 | 1.000 |
| avoided_foods_absent | 0.917 | 1.000 |
| details_one_sentence | 1.000 | 1.000 |
| model_count_within_schema | 1.000 | 1.000 |
| names_a_logged_food | 0.889 | 0.944 |
| nearby_pick_names_the_place | 1.000 | 1.000 |
| nearby_rule_kept | 1.000 | 1.000 |
| no_banned_phrase | 1.000 | 1.000 |
| nothing_eaten_today_in_a_title | 0.981 | 1.000 |
| one_emoji_each | 0.963 | 1.000 |
| shown_within_schema | 1.000 | 1.000 |
| titles_2_to_5_words | 0.926 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| (none) | | |

