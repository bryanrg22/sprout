## checklistPlan on `checklist_plan/v1` (16 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 1.6 | 1.9 | 2170 / 0 | 357 | 0.00040 | 0.40 |
| `anthropic:claude-sonnet-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 3.4 | 4.1 | 2236 / 0 | 365 | 0.00812 | 8.12 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 16 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| chips_within_schema | 1.000 | 1.000 |
| icons_known_share | 0.947 | 0.917 |
| no_number_outside_the_data | 0.667 | 1.000 |
| none_cut_short | 0.896 | 1.000 |
| none_dropped_by_the_app | 0.854 | 0.500 |
| reflects_the_routine | 1.000 | 1.000 |
| tasks_within_schema | 1.000 | 1.000 |
| titles_at_most_four_words | 0.188 | 0.833 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| (none) | | |

