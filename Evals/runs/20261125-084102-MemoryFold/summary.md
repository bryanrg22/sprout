## memoryFold on `memory_fold/v1` (12 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 36 | 100% | **92%** | 81%–100% | 78%–97% | 83% 100% 92% | 2.6 | 3.1 | 955 / 0 | 228 | 0.00210 | 2.10 |
| `anthropic:claude-haiku-5-5` | 36 | 100% | **100%** | 100%–100% | 90%–100% | 100% 100% 100% | 2.3 | 2.6 | 1352 / 0 | 426 | 0.00035 | 0.35 |

**Compared with `anthropic:claude-haiku-4-5-20251001` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 12 | +8.3% | +0.0% to +22.2% |

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
| no_app_owned_number_stored | 1.000 | 1.000 |
| no_gendered_pronoun | 0.611 | 0.972 |
| notes_chars | 394.083 | 537.472 |
| notes_within_budget | 1.000 | 1.000 |
| parses | 1.000 | 1.000 |
| retracted_fact_absent | 0.917 | 1.000 |
| small_talk_not_kept | 0.556 | 0.444 |
| summary_chars | 437.250 | 578.861 |
| summary_within_budget | 1.000 | 1.000 |
| wrong_person_pronoun | 0.028 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| alex-existing-notes | 1/3 | 3/3 |
| sam-takes-back-a-saved-note | 2/3 | 3/3 |

