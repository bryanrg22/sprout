## planBuild on `plan_build/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 30 | 100% | **87%** | 73%–97% | 70%–95% | 87% 87% | 8.2 | 10.0 | 3067 / 0 | 1702 | 0.00116 | 1.16 |
| `anthropic:claude-opus-4-8` | 30 | 100% | **100%** | 100%–100% | 89%–100% | 100% 100% | 21.7 | 25.7 | 3069 / 0 | 1461 | 0.05187 | 51.87 |
| `anthropic:claude-opus-5-5` | 30 | 43% | **40%** | 20%–60% | 25%–58% | 20% 60% | 22.9 | 24.5 | 2903 / 0 | 2069 | 0.05299 | 52.99 |
| `anthropic:claude-sonnet-5` | 30 | 100% | **53%** | 30%–73% | 36%–70% | 60% 47% | 18.4 | 22.2 | 3133 / 0 | 1607 | 0.02234 | 22.34 |

**Compared with `anthropic:claude-opus-4-8` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 15 | -13.3% | -26.7% to -3.3% |
| `anthropic:claude-opus-5-5` | 15 | -60.0% | -76.7% to -40.0% |
| `anthropic:claude-sonnet-5` | 15 | -46.7% | -66.7% to -23.3% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| about_you_written | 1.000 | 1.000 | 0.923 | 0.933 |
| assessment_words | 134.600 | 75.567 | 81.308 | 76.533 |
| calorie_min_at_or_above_floor | 0.933 | 1.000 | 0.923 | 1.000 |
| changelog_note_written | 1.000 | 1.000 | 1.000 | 0.867 |
| has_range | 0.933 | 1.000 | 0.923 | 1.000 |
| hedges_on_an_early_read | 1.000 | 1.000 | 1.000 | 1.000 |
| insight_count | 4.700 | 5.000 | 4.385 | 2.967 |
| insight_tones_valid_as_written | 1.000 | 1.000 | 0.923 | 0.600 |
| insights_three_to_five | 1.000 | 1.000 | 0.923 | 0.600 |
| logged_days | 17.067 | 17.067 | 15.923 | 17.067 |
| no_number_outside_the_input | 0.000 | 0.000 | 0.000 | 0.000 |
| numbers_outside_that_are_sums_or_differences | 5.600 | 3.100 | 6.769 | 4.200 |
| numbers_outside_the_input | 8.200 | 4.467 | 10.692 | 6.333 |
| prose_present | 0.933 | 1.000 | 1.000 | 0.833 |
| protein_g_per_lb | 0.835 | 0.830 | 0.820 | 0.830 |
| protein_in_sane_band | 1.000 | 1.000 | 1.000 | 1.000 |
| protein_set | 1.000 | 1.000 | 0.923 | 1.000 |
| range_contains_app_target | 0.786 | 0.667 | 0.667 | 0.867 |
| range_direction_fits_goal | 1.000 | 1.000 | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -72.429 | -61.967 | 17.583 | -83.567 |
| range_ordered_as_written | 0.933 | 1.000 | 1.000 | 1.000 |
| range_width_kcal | 184.107 | 187.367 | 195.833 | 190.333 |
| strategy_words | 166.333 | 105.833 | 119.538 | 136.733 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| build-alex-gaining-too-fast | 2/2 | 2/2 | 1/2 | 0/2 |
| build-alex-lifting-baseline | 2/2 | 2/2 | 1/2 | 2/2 |
| build-alex-little-time | 2/2 | 2/2 | 0/2 | 2/2 |
| build-alex-maintain-half-marathon | 1/2 | 2/2 | 1/2 | 2/2 |
| build-alex-poor-appetite | 1/2 | 2/2 | 1/2 | 1/2 |
| build-sam-ambitious-timeframe | 2/2 | 2/2 | 1/2 | 0/2 |
| build-sam-desk-job-baseline | 2/2 | 2/2 | 0/2 | 2/2 |
| build-sam-empty-intake | 1/2 | 2/2 | 2/2 | 2/2 |
| build-sam-knee-injury | 2/2 | 2/2 | 0/2 | 0/2 |
| build-sam-maintain-after-goal | 2/2 | 2/2 | 2/2 | 1/2 |
| build-sam-night-shifts | 2/2 | 2/2 | 0/2 | 0/2 |
| build-sam-vegetarian | 2/2 | 2/2 | 0/2 | 0/2 |
| build-sam-very-low-intake | 2/2 | 2/2 | 0/2 | 1/2 |
| build-sam-weekend-pattern | 1/2 | 2/2 | 1/2 | 1/2 |

**Errors**

- `anthropic:claude-opus-5-5`: decoding("the answer was cut off at 2200 tokens")

