## foodSuggestions on `food_suggestions/v1` (18 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 54 | 96% | **96%** | 87%–99% | 94% 100% 94% | 3.7 | 4.4 | 1810 / 0 | 286 | 0.00648 | 6.48 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` |
|---|---|
| avoided_foods_absent | 0.833 |
| details_one_sentence | 1.000 |
| model_count_within_schema | 1.000 |
| names_a_logged_food | 0.923 |
| nearby_pick_names_the_place | 1.000 |
| nearby_rule_kept | 1.000 |
| no_banned_phrase | 1.000 |
| nothing_eaten_today_in_a_title | 1.000 |
| one_emoji_each | 0.981 |
| shown_within_schema | 1.000 |
| titles_2_to_5_words | 0.923 |
| wrong_person_pronoun | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` |
|---|---|
| alex-lunch-little-history | 2/3 |
| sam-lunch-under-protein | 2/3 |

**Errors**

- `anthropic:claude-sonnet-5-5`: decoding("the answer broke the schema (answer.suggestions: 1 items, at least 2)")

