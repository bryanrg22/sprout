## memoryFold on `memory_fold/v1` (12 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 36 | 100% | **100%** | 100%–100% | 90%–100% | 100% 100% 100% | 2.3 | 3.0 | 1352 / 0 | 423 | 0.00035 | 0.35 |
| `anthropic:claude-sonnet-5` | 36 | 100% | **100%** | 100%–100% | 90%–100% | 100% 100% 100% | 4.3 | 5.2 | 1351 / 0 | 389 | 0.00659 | 6.59 |

**Compared with `anthropic:claude-haiku-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5` | 12 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| all_facts_kept | 1.000 | 1.000 |
| bare_json | 1.000 | 1.000 |
| both_fields_returned | 1.000 | 1.000 |
| existing_notes_kept | 1.000 | 1.000 |
| facts_kept_share | 1.000 | 1.000 |
| kept_allergy | 1.000 | 1.000 |
| kept_injury | 1.000 | 1.000 |
| kept_preference | 1.000 | 1.000 |
| kept_schedule | 1.000 | 1.000 |
| no_app_owned_number_stored | 1.000 | 1.000 |
| no_gendered_pronoun | 1.000 | 0.944 |
| notes_chars | 531.389 | 502.639 |
| notes_within_budget | 1.000 | 1.000 |
| parses | 1.000 | 1.000 |
| retracted_fact_absent | 1.000 | 1.000 |
| small_talk_not_kept | 0.444 | 0.389 |
| summary_chars | 586.944 | 502.139 |
| summary_within_budget | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.056 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| (none) | | |

