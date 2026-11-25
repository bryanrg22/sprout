## coachPrompts on `coach_prompts/v1` (16 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 0.8 | 0.9 | 1976 / 0 | 75 | 0.00023 | 0.23 |
| `anthropic:claude-sonnet-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 1.3 | 1.9 | 2042 / 0 | 78 | 0.00486 | 4.86 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 16 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| chips_at_most_six_words | 0.396 | 0.896 |
| count_within_bounds | 1.000 | 1.000 |
| model_count_within_schema | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| nods_to_the_routine | 0.889 | 0.861 |
| none_cut_short | 1.000 | 1.000 |
| none_dropped_by_the_app | 0.958 | 1.000 |
| returned_the_count_asked | 0.958 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| (none) | | |

