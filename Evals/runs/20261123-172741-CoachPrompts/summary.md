## coachPrompts on `coach_prompts/v1` (16 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 16 | 100% | **100%** | 81%–100% | 100% | 2.0 | 2.8 | 1654 / 0 | 44 | 0.00375 | 3.75 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` |
|---|---|
| chips_at_most_six_words | 1.000 |
| count_within_bounds | 1.000 |
| model_count_within_schema | 1.000 |
| no_number_invented | 1.000 |
| nods_to_the_routine | 0.917 |
| none_cut_short | 1.000 |
| none_dropped_by_the_app | 0.938 |
| returned_the_count_asked | 0.938 |
| wrong_person_pronoun | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` |
|---|---|
| (none) | |

