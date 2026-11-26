## planBuild on `plan_build/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-opus-5-5` | 30 | 93% | **93%** | 83%–100% | 79%–98% | 93% 93% | 25.5 | 29.9 | 2904 / 0 | 2284 | 0.05731 | 57.31 |
| `openai:gpt-6.2-sol` | 30 | 100% | **100%** | 100%–100% | 89%–100% | 100% 100% | 15.9 | 18.2 | 1613 / 0 | 627 | 0.00950 | 9.50 |

**Compared with `anthropic:claude-opus-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 15 | +6.7% | +0.0% to +16.7% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-opus-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| about_you_written | 1.000 | 1.000 |
| assessment_words | 83.500 | 66.533 |
| calorie_min_at_or_above_floor | 1.000 | 1.000 |
| changelog_note_written | 1.000 | 1.000 |
| has_range | 1.000 | 1.000 |
| hedges_on_an_early_read | 1.000 | 1.000 |
| insight_count | 5.000 | 3.967 |
| insight_tones_valid_as_written | 1.000 | 1.000 |
| insights_three_to_five | 1.000 | 1.000 |
| logged_days | 17.286 | 17.067 |
| no_number_outside_the_input | 0.000 | 0.000 |
| numbers_outside_that_are_sums_or_differences | 7.929 | 4.133 |
| numbers_outside_the_input | 11.357 | 5.167 |
| prose_present | 1.000 | 1.000 |
| protein_g_per_lb | 0.815 | 0.806 |
| protein_in_sane_band | 1.000 | 1.000 |
| protein_set | 1.000 | 1.000 |
| range_contains_app_target | 0.536 | 0.567 |
| range_direction_fits_goal | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -29.071 | -13.667 |
| range_ordered_as_written | 1.000 | 1.000 |
| range_width_kcal | 196.429 | 177.733 |
| strategy_words | 122.857 | 76.200 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-opus-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| build-sam-ambitious-timeframe | 1/2 | 2/2 |
| build-sam-vegetarian | 1/2 | 2/2 |

**Errors**

- `anthropic:claude-opus-5-5`: decoding("the answer was cut off at 2200 tokens")
- `anthropic:claude-opus-5-5`: decoding("the plan came back empty")

