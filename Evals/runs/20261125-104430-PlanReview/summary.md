## planReview on `plan_review/v1` (14 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 28 | 100% | **82%** | 64%–96% | 64%–92% | 93% 71% | 6.3 | 7.8 | 2662 / 0 | 1340 | 0.00094 | 0.94 |
| `anthropic:claude-opus-4-8` | 28 | 89% | **89%** | 71%–100% | 73%–96% | 86% 93% | 16.4 | 19.4 | 2378 / 0 | 1021 | 0.03742 | 37.42 |
| `anthropic:claude-opus-5-5` | 28 | 100% | **93%** | 82%–100% | 77%–98% | 93% 93% | 19.9 | 23.8 | 2490 / 0 | 1602 | 0.04201 | 42.01 |
| `anthropic:claude-sonnet-5` | 28 | 100% | **93%** | 79%–100% | 77%–98% | 93% 93% | 12.8 | 14.3 | 2728 / 0 | 1151 | 0.01697 | 16.97 |

**Compared with `anthropic:claude-opus-4-8` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 14 | -7.1% | -32.1% to +17.9% |
| `anthropic:claude-opus-5-5` | 14 | +3.6% | -14.3% to +25.0% |
| `anthropic:claude-sonnet-5` | 14 | +3.6% | -17.9% to +25.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| about_you_written | 1.000 | 1.000 | 0.929 | 1.000 |
| assessment_words | 106.321 | 55.680 | 55.893 | 46.571 |
| calorie_max_change_kcal | 3.571 | 14.000 | -14.286 | 1.786 |
| calorie_min_at_or_above_floor | 0.929 | 1.000 | 0.964 | 1.000 |
| calorie_min_change_kcal | -108.929 | 12.000 | -14.286 | 7.143 |
| changelog_note_written | 1.000 | 1.000 | 0.964 | 1.000 |
| has_range | 0.929 | 1.000 | 0.964 | 1.000 |
| hedges_on_an_early_read | 0.500 | 1.000 | 0.500 | 1.000 |
| insight_count | 4.500 | 4.880 | 4.607 | 4.607 |
| insight_tones_valid_as_written | 1.000 | 1.000 | 0.964 | 0.929 |
| insights_three_to_five | 1.000 | 1.000 | 0.929 | 0.929 |
| logged_days | 22.286 | 23.360 | 22.286 | 22.286 |
| no_change_note_matches_the_numbers | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_outside_the_input | 0.036 | 0.080 | 0.071 | 0.143 |
| numbers_outside_that_are_sums_or_differences | 2.679 | 1.920 | 4.786 | 2.214 |
| numbers_outside_the_input | 3.143 | 2.280 | 5.750 | 2.464 |
| prose_present | 0.857 | 1.000 | 0.929 | 1.000 |
| protein_change_g | 0.000 | 0.200 | -3.750 | 0.357 |
| protein_g_per_lb | 0.781 | 0.787 | 0.785 | 0.783 |
| protein_in_sane_band | 1.000 | 1.000 | 1.000 | 1.000 |
| protein_set | 1.000 | 1.000 | 0.964 | 1.000 |
| range_contains_app_target | 0.038 | 0.080 | 0.222 | 0.107 |
| range_direction_fits_goal | 1.000 | 1.000 | 1.000 | 1.000 |
| range_mid_minus_maintenance_kcal | -21.192 | 15.960 | 16.481 | -36.750 |
| range_moved_as_expected | 0.962 | 0.870 | 0.769 | 1.000 |
| range_ordered_as_written | 0.929 | 1.000 | 1.000 | 1.000 |
| range_width_kcal | 167.308 | 178.000 | 181.481 | 169.643 |
| says_no_change | 0.321 | 0.200 | 0.214 | 0.286 |
| strategy_words | 106.179 | 78.240 | 75.143 | 56.964 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| review-alex-comeback-after-gap | 2/2 | 1/2 | 2/2 | 2/2 |
| review-alex-wrong-direction | 1/2 | 2/2 | 2/2 | 2/2 |
| review-sam-losing-too-fast | 2/2 | 2/2 | 1/2 | 2/2 |
| review-sam-maintain-drifting-up | 1/2 | 2/2 | 2/2 | 2/2 |
| review-sam-new-constraint | 2/2 | 2/2 | 2/2 | 0/2 |
| review-sam-on-track | 0/2 | 2/2 | 2/2 | 2/2 |
| review-sam-plan-below-floor | 2/2 | 0/2 | 2/2 | 2/2 |
| review-sam-sparse-logging | 2/2 | 2/2 | 1/2 | 2/2 |
| review-sam-stalled | 1/2 | 2/2 | 2/2 | 2/2 |

**Errors**

- `anthropic:claude-opus-4-8`: Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost." UserInfo={_kCFStreamErrorCodeKey=54, NSUnderlyingError=0x10aa20a80 {Error Domain=kCFErrorDomainCFNetwork Code=-1005 "(null)" UserInfo={_kCFStreamErrorCodeKey=54, _kCFStreamErrorDomainKey=1}}, _NSURLErrorFailingURLSessionTask
- `anthropic:claude-opus-4-8`: Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost." UserInfo={_kCFStreamErrorCodeKey=54, NSUnderlyingError=0x10aa22010 {Error Domain=kCFErrorDomainCFNetwork Code=-1005 "(null)" UserInfo={_kCFStreamErrorCodeKey=54, _kCFStreamErrorDomainKey=1}}, _NSURLErrorFailingURLSessionTask
- `anthropic:claude-opus-4-8`: Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost." UserInfo={_kCFStreamErrorCodeKey=54, NSUnderlyingError=0x10aa22130 {Error Domain=kCFErrorDomainCFNetwork Code=-1005 "(null)" UserInfo={_kCFStreamErrorCodeKey=54, _kCFStreamErrorDomainKey=1}}, _NSURLErrorFailingURLSessionTask

