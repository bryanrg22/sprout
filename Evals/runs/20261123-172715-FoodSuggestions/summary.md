## foodSuggestions on `food_suggestions/v1` (18 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 18 | 100% | **94%** | 74%–99% | 94% | 3.9 | 5.1 | 1810 / 0 | 280 | 0.00642 | 6.42 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` |
|---|---|
| avoided_foods_absent | 0.750 |
| details_one_sentence | 1.000 |
| model_count_within_schema | 0.944 |
| names_a_logged_food | 0.889 |
| nearby_pick_names_the_place | 1.000 |
| nearby_rule_kept | 1.000 |
| no_banned_phrase | 1.000 |
| nothing_eaten_today_in_a_title | 1.000 |
| one_emoji_each | 0.889 |
| shown_within_schema | 0.944 |
| titles_2_to_5_words | 0.833 |
| wrong_person_pronoun | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` |
|---|---|
| alex-lunch-little-history | 0/1 |

