## planReview on `plan_review/v1` (14 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-opus-4-8` | 28 | 100% | **96%** | 89%–100% | 82%–99% | 100% 93% | 16.9 | 19.5 | 2664 / 0 | 1171 | 0.04260 | 42.60 |
| `anthropic:claude-opus-5-5` | 28 | 100% | **100%** | 100%–100% | 88%–100% | 100% 100% | 19.8 | 23.3 | 2491 / 0 | 1694 | 0.04384 | 43.84 |

**Compared with `anthropic:claude-opus-4-8` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-opus-5-5` | 14 | +3.6% | +0.0% to +10.7% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` |
|---|---|---|
| about_you_written | 1.000 | 1.000 |
| assessment_words | 55.964 | 68.286 |
| calorie_max_change_kcal | 21.429 | 42.857 |
| calorie_min_at_or_above_floor | 1.000 | 1.000 |
| calorie_min_change_kcal | 23.214 | 37.500 |
| changelog_note_written | 1.000 | 1.000 |
| has_range | 1.000 | 1.000 |
| hedges_on_an_early_read | 1.000 | 1.000 |
| insight_count | 4.929 | 4.893 |
| insight_tones_valid_as_written | 1.000 | 1.000 |
| insights_three_to_five | 1.000 | 1.000 |
| logged_days | 22.286 | 22.286 |
| no_change_note_matches_the_numbers | 1.000 | 1.000 |
| no_number_outside_the_input | 0.071 | 0.000 |
| numbers_outside_that_are_sums_or_differences | 2.179 | 5.214 |
| numbers_outside_the_input | 2.500 | 6.000 |
| prose_present | 1.000 | 1.000 |
| protein_change_g | 0.179 | -0.714 |
| protein_g_per_lb | 0.782 | 0.776 |
| protein_in_sane_band | 1.000 | 0.929 |
| protein_set | 1.000 | 1.000 |
| range_contains_app_target | 0.107 | 0.214 |
| range_direction_fits_goal | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -18.893 | -1.036 |
| range_moved_as_expected | 0.885 | 0.769 |
| range_ordered_as_written | 1.000 | 1.000 |
| range_width_kcal | 173.214 | 180.357 |
| says_no_change | 0.214 | 0.214 |
| strategy_words | 82.500 | 81.214 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.036 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` |
|---|---|---|
| review-sam-maintain-drifting-up | 1/2 | 2/2 |

