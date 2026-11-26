## planBuild on `plan_build/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-opus-4-8` | 30 | 100% | **97%** | 90%–100% | 83%–99% | 93% 100% | 22.4 | 25.6 | 3069 / 0 | 1484 | 0.05245 | 52.45 |
| `anthropic:claude-opus-5-5` | 30 | 100% | **97%** | 90%–100% | 83%–99% | 93% 100% | 24.1 | 27.6 | 2904 / 0 | 2071 | 0.05304 | 53.04 |

**Compared with `anthropic:claude-opus-4-8` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-opus-5-5` | 15 | +0.0% | -10.0% to +10.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` |
|---|---|---|
| about_you_written | 1.000 | 0.967 |
| assessment_words | 73.233 | 81.133 |
| calorie_min_at_or_above_floor | 1.000 | 0.967 |
| changelog_note_written | 1.000 | 0.967 |
| has_range | 1.000 | 0.967 |
| hedges_on_an_early_read | 1.000 | 1.000 |
| insight_count | 5.000 | 4.833 |
| insight_tones_valid_as_written | 1.000 | 0.967 |
| insights_three_to_five | 1.000 | 0.967 |
| logged_days | 17.067 | 17.067 |
| no_number_outside_the_input | 0.000 | 0.033 |
| numbers_outside_that_are_sums_or_differences | 2.667 | 8.633 |
| numbers_outside_the_input | 4.400 | 12.033 |
| prose_present | 1.000 | 0.967 |
| protein_g_per_lb | 0.828 | 0.810 |
| protein_in_sane_band | 1.000 | 1.000 |
| protein_set | 1.000 | 0.967 |
| range_contains_app_target | 0.700 | 0.448 |
| range_direction_fits_goal | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -59.267 | -64.379 |
| range_ordered_as_written | 1.000 | 1.000 |
| range_width_kcal | 185.167 | 190.517 |
| strategy_words | 105.967 | 122.367 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.033 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` |
|---|---|---|
| build-alex-gaining-too-fast | 2/2 | 1/2 |
| build-alex-maintain-half-marathon | 1/2 | 2/2 |

