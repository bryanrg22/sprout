## planReview on `plan_review/v1` (1 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 5.6 | 5.6 | 2699 / 0 | 1114 | 0.00083 | 0.83 |
| `anthropic:claude-opus-4-8` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 17.8 | 17.8 | 2701 / 0 | 1156 | 0.04240 | 42.41 |
| `anthropic:claude-opus-5-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 15.9 | 15.9 | 2527 / 0 | 1302 | 0.03615 | 36.15 |
| `anthropic:claude-sonnet-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 12.7 | 12.7 | 2765 / 0 | 1121 | 0.01674 | 16.74 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| about_you_written | 1.000 | 1.000 | 1.000 | 1.000 |
| assessment_words | 88.000 | 77.000 | 40.000 | 46.000 |
| calorie_max_change_kcal | 0.000 | 0.000 | 0.000 | 0.000 |
| calorie_min_at_or_above_floor | 1.000 | 1.000 | 1.000 | 1.000 |
| calorie_min_change_kcal | 0.000 | 0.000 | 0.000 | 0.000 |
| changelog_note_written | 1.000 | 1.000 | 1.000 | 1.000 |
| has_range | 1.000 | 1.000 | 1.000 | 1.000 |
| insight_count | 4.000 | 4.000 | 4.000 | 5.000 |
| insight_tones_valid_as_written | 1.000 | 1.000 | 1.000 | 1.000 |
| insights_three_to_five | 1.000 | 1.000 | 1.000 | 1.000 |
| logged_days | 28.000 | 28.000 | 28.000 | 28.000 |
| no_change_note_matches_the_numbers | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_outside_the_input | 0.000 | 0.000 | 0.000 | 0.000 |
| numbers_outside_that_are_sums_or_differences | 4.000 | 2.000 | 1.000 | 1.000 |
| numbers_outside_the_input | 4.000 | 2.000 | 1.000 | 1.000 |
| prose_present | 1.000 | 1.000 | 1.000 | 1.000 |
| protein_change_g | 0.000 | 0.000 | 0.000 | 0.000 |
| protein_g_per_lb | 0.660 | 0.660 | 0.660 | 0.660 |
| protein_in_sane_band | 1.000 | 1.000 | 1.000 | 1.000 |
| protein_set | 1.000 | 1.000 | 1.000 | 1.000 |
| range_contains_app_target | 0.000 | 0.000 | 0.000 | 0.000 |
| range_direction_fits_goal | 1.000 | 1.000 | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -375.000 | -375.000 | -375.000 | -375.000 |
| range_moved_as_expected | 1.000 | 1.000 | 1.000 | 1.000 |
| range_ordered_as_written | 1.000 | 1.000 | 1.000 | 1.000 |
| range_width_kcal | 150.000 | 150.000 | 150.000 | 150.000 |
| says_no_change | 1.000 | 1.000 | 1.000 | 1.000 |
| strategy_words | 84.000 | 95.000 | 78.000 | 66.000 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| (none) | | | | |

