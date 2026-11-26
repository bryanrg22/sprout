## planBuild on `plan_build/v1` (1 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 9.1 | 9.1 | 3226 / 0 | 1857 | 0.00125 | 1.25 |
| `anthropic:claude-opus-4-8` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 21.9 | 21.9 | 3228 / 0 | 1430 | 0.05189 | 51.89 |
| `anthropic:claude-opus-5-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 24.4 | 24.4 | 3059 / 0 | 2070 | 0.05364 | 53.64 |
| `anthropic:claude-sonnet-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 17.3 | 17.3 | 3292 / 0 | 1512 | 0.02170 | 21.70 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| about_you_written | 1.000 | 1.000 | 1.000 | 1.000 |
| assessment_words | 157.000 | 67.000 | 75.000 | 83.000 |
| calorie_min_at_or_above_floor | 1.000 | 1.000 | 1.000 | 1.000 |
| changelog_note_written | 1.000 | 1.000 | 1.000 | 1.000 |
| has_range | 1.000 | 1.000 | 1.000 | 1.000 |
| insight_count | 5.000 | 5.000 | 5.000 | 5.000 |
| insight_tones_valid_as_written | 1.000 | 1.000 | 1.000 | 1.000 |
| insights_three_to_five | 1.000 | 1.000 | 1.000 | 1.000 |
| logged_days | 21.000 | 21.000 | 21.000 | 21.000 |
| no_number_outside_the_input | 0.000 | 0.000 | 0.000 | 0.000 |
| numbers_outside_that_are_sums_or_differences | 3.000 | 3.000 | 8.000 | 5.000 |
| numbers_outside_the_input | 4.000 | 4.000 | 10.000 | 6.000 |
| prose_present | 1.000 | 1.000 | 1.000 | 1.000 |
| protein_g_per_lb | 0.810 | 0.810 | 0.750 | 0.810 |
| protein_in_sane_band | 1.000 | 1.000 | 1.000 | 1.000 |
| protein_set | 1.000 | 1.000 | 1.000 | 1.000 |
| range_contains_app_target | 1.000 | 1.000 | 1.000 | 1.000 |
| range_direction_fits_goal | 1.000 | 1.000 | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -175.000 | -175.000 | -181.000 | -175.000 |
| range_ordered_as_written | 1.000 | 1.000 | 1.000 | 1.000 |
| range_width_kcal | 150.000 | 150.000 | 150.000 | 150.000 |
| strategy_words | 173.000 | 88.000 | 97.000 | 124.000 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| (none) | | | | |

