## memoryFold on `memory_fold/v1` (12 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 60 | 100% | **98%** | 95%–100% | 91%–100% | 100% 100% 100% 92% 100% | 2.7 | 3.3 | 955 / 0 | 225 | 0.00208 | 2.08 |
| `anthropic:claude-haiku-5-5` | 60 | 100% | **97%** | 90%–100% | 89%–99% | 92% 92% 100% 100% 100% | 2.3 | 2.5 | 1352 / 0 | 423 | 0.00035 | 0.35 |

**Compared with `anthropic:claude-haiku-4-5-20251001` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 12 | -1.7% | -10.0% to +5.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| all_facts_kept | 1.000 | 1.000 |
| bare_json | 0.000 | 1.000 |
| both_fields_returned | 1.000 | 1.000 |
| existing_notes_kept | 1.000 | 1.000 |
| facts_kept_share | 1.000 | 1.000 |
| kept_allergy | 1.000 | 1.000 |
| kept_injury | 1.000 | 1.000 |
| kept_preference | 1.000 | 1.000 |
| kept_schedule | 1.000 | 1.000 |
| no_app_owned_number_stored | 1.000 | 0.800 |
| no_gendered_pronoun | 0.717 | 1.000 |
| notes_chars | 396.917 | 525.867 |
| notes_within_budget | 1.000 | 1.000 |
| parses | 1.000 | 1.000 |
| retracted_fact_absent | 0.983 | 0.967 |
| small_talk_not_kept | 0.617 | 0.433 |
| summary_chars | 424.883 | 589.783 |
| summary_within_budget | 1.000 | 1.000 |
| wrong_person_pronoun | 0.017 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| alex-takes-back-a-saved-note | 5/5 | 3/5 |
| sam-takes-back-a-saved-note | 4/5 | 5/5 |

