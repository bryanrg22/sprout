## planReview on `plan_review/v1` (14 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-opus-5-5` | 28 | 100% | **96%** | 89%–100% | 82%–99% | 93% 100% | 19.8 | 24.0 | 2490 / 0 | 1706 | 0.04409 | 44.09 |
| `openai:gpt-6.2-sol` | 28 | 100% | **100%** | 100%–100% | 88%–100% | 100% 100% | 11.4 | 13.4 | 1345 / 0 | 478 | 0.00747 | 7.47 |

**Compared with `anthropic:claude-opus-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 14 | +3.6% | +0.0% to +10.7% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-opus-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| about_you_written | 1.000 | 1.000 |
| assessment_words | 64.643 | 53.500 |
| calorie_max_change_kcal | 35.714 | 0.000 |
| calorie_min_at_or_above_floor | 1.000 | 1.000 |
| calorie_min_change_kcal | 32.143 | 7.143 |
| changelog_note_written | 0.964 | 1.000 |
| has_range | 1.000 | 1.000 |
| hedges_on_an_early_read | 0.500 | 0.500 |
| insight_count | 4.643 | 3.821 |
| insight_tones_valid_as_written | 1.000 | 1.000 |
| insights_three_to_five | 0.964 | 1.000 |
| logged_days | 22.286 | 22.286 |
| no_change_note_matches_the_numbers | 1.000 | 1.000 |
| no_number_outside_the_input | 0.000 | 0.000 |
| numbers_outside_that_are_sums_or_differences | 5.000 | 2.714 |
| numbers_outside_the_input | 6.071 | 2.929 |
| prose_present | 0.964 | 1.000 |
| protein_change_g | 0.000 | 0.000 |
| protein_g_per_lb | 0.781 | 0.781 |
| protein_in_sane_band | 1.000 | 1.000 |
| protein_set | 1.000 | 1.000 |
| range_contains_app_target | 0.179 | 0.071 |
| range_direction_fits_goal | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -7.286 | -37.643 |
| range_moved_as_expected | 0.808 | 1.000 |
| range_ordered_as_written | 1.000 | 1.000 |
| range_width_kcal | 178.571 | 167.857 |
| says_no_change | 0.214 | 0.143 |
| strategy_words | 80.500 | 43.179 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-opus-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| review-sam-stalled | 1/2 | 2/2 |

