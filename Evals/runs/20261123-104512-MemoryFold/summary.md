## memoryFold on `memory_fold/v1` (12 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 36 | 100% | **97%** | 86%–100% | 92% 100% 100% | 2.7 | 3.0 | 955 / 0 | 223 | 0.00207 | 2.07 |
| `anthropic:claude-haiku-5-5` | 36 | 100% | **100%** | 90%–100% | 100% 100% 100% | 2.3 | 2.5 | 1352 / 0 | 423 | 0.00035 | 0.35 |
| `anthropic:claude-sonnet-5` | 36 | 92% | **92%** | 78%–97% | 83% 100% 92% | 4.5 | 5.2 | 1351 / 0 | 388 | 0.00658 | 6.58 |
| `anthropic:claude-sonnet-5-5` | 36 | 100% | **100%** | 90%–100% | 100% 100% 100% | 4.0 | 8.0 | 1352 / 0 | 450 | 0.00720 | 7.20 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| all_facts_kept | 1.000 | 1.000 | 1.000 | 1.000 |
| bare_json | 0.000 | 1.000 | 1.000 | 1.000 |
| both_fields_returned | 1.000 | 1.000 | 1.000 | 1.000 |
| existing_notes_kept | 1.000 | 1.000 | 1.000 | 1.000 |
| facts_kept_share | 1.000 | 1.000 | 1.000 | 1.000 |
| kept_allergy | 1.000 | 1.000 | 1.000 | 1.000 |
| kept_injury | 1.000 | 1.000 | 1.000 | 1.000 |
| kept_preference | 1.000 | 1.000 | 1.000 | 1.000 |
| kept_schedule | 1.000 | 1.000 | 1.000 | 1.000 |
| no_app_owned_number_stored | 1.000 | 0.917 | 0.970 | 1.000 |
| no_gendered_pronoun | 0.611 | 1.000 | 0.879 | 0.972 |
| notes_chars | 385.444 | 529.667 | 505.636 | 548.806 |
| notes_within_budget | 1.000 | 1.000 | 1.000 | 1.000 |
| parses | 1.000 | 1.000 | 0.917 | 1.000 |
| retracted_fact_absent | 0.972 | 1.000 | 1.000 | 1.000 |
| small_talk_not_kept | 0.583 | 0.361 | 0.394 | 0.361 |
| summary_chars | 431.417 | 583.556 | 483.242 | 649.917 |
| summary_within_budget | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.028 | 0.000 | 0.061 | 0.028 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| alex-existing-notes | 3/3 | 3/3 | 2/3 | 3/3 |
| alex-first-fold | 3/3 | 3/3 | 2/3 | 3/3 |
| sam-first-fold | 3/3 | 3/3 | 2/3 | 3/3 |
| sam-takes-back-a-saved-note | 2/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-sonnet-5`: the reply did not parse as {notes, summary}

