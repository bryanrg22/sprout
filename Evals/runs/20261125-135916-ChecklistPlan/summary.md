## checklistPlan on `checklist_plan/v1` (16 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 3.0 | 3.5 | 1934 / 0 | 324 | 0.00711 | 7.11 |
| `openai:gpt-6.2-sol` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 3.2 | 3.7 | 1099 / 0 | 126 | 0.00346 | 3.46 |

**Compared with `anthropic:claude-sonnet-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 16 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| chips_within_schema | 1.000 | 1.000 |
| icons_known_share | 0.950 | 0.971 |
| no_number_outside_the_data | 0.979 | 0.979 |
| none_cut_short | 0.979 | 0.917 |
| none_dropped_by_the_app | 1.000 | 1.000 |
| reflects_the_routine | 1.000 | 1.000 |
| tasks_within_schema | 1.000 | 1.000 |
| titles_at_most_four_words | 0.375 | 0.979 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| (none) | | |

