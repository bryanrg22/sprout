## memoryFold on `memory_fold/v1` (12 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 60 | 100% | **100%** | 94%–100% | 100% 100% 100% 100% 100% | 2.2 | 2.6 | 1352 / 0 | 420 | 0.00035 | 0.35 |
| `anthropic:claude-haiku-5-5@default` | 60 | 98% | **95%** | 86%–98% | 100% 92% 92% 100% 92% | 3.7 | 4.4 | 1353 / 0 | 741 | 0.00051 | 0.51 |
| `anthropic:claude-sonnet-5` | 60 | 100% | **100%** | 94%–100% | 100% 100% 100% 100% 100% | 4.5 | 5.9 | 1351 / 0 | 395 | 0.00665 | 6.65 |
| `anthropic:claude-sonnet-5@default` | 60 | 97% | **97%** | 89%–99% | 100% 100% 83% 100% 100% | 6.1 | 7.4 | 1351 / 0 | 540 | 0.00810 | 8.10 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-haiku-5-5@default` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5@default` |
|---|---|---|---|---|
| all_facts_kept | 1.000 | 0.983 | 1.000 | 1.000 |
| bare_json | 1.000 | 1.000 | 1.000 | 1.000 |
| both_fields_returned | 1.000 | 1.000 | 1.000 | 1.000 |
| existing_notes_kept | 1.000 | 1.000 | 1.000 | 1.000 |
| facts_kept_share | 1.000 | 0.996 | 1.000 | 1.000 |
| kept_allergy | 1.000 | 1.000 | 1.000 | 1.000 |
| kept_injury | 1.000 | 0.983 | 1.000 | 1.000 |
| kept_preference | 1.000 | 1.000 | 1.000 | 1.000 |
| kept_schedule | 1.000 | 1.000 | 1.000 | 1.000 |
| no_app_owned_number_stored | 0.883 | 1.000 | 0.967 | 1.000 |
| no_gendered_pronoun | 1.000 | 0.983 | 0.850 | 0.931 |
| notes_chars | 526.567 | 509.119 | 514.667 | 504.690 |
| notes_within_budget | 1.000 | 1.000 | 1.000 | 1.000 |
| parses | 1.000 | 0.983 | 1.000 | 0.967 |
| retracted_fact_absent | 1.000 | 0.983 | 1.000 | 1.000 |
| small_talk_not_kept | 0.500 | 0.729 | 0.417 | 0.517 |
| summary_chars | 581.450 | 634.915 | 510.033 | 531.052 |
| summary_within_budget | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.033 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-haiku-5-5@default` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5@default` |
|---|---|---|---|---|
| alex-notes-and-a-short-lived-plan | 5/5 | 4/5 | 5/5 | 5/5 |
| alex-plan-that-fell-through | 5/5 | 5/5 | 5/5 | 4/5 |
| alex-takes-back-a-saved-note | 5/5 | 4/5 | 5/5 | 5/5 |
| sam-notes-and-a-cancelled-booking | 5/5 | 4/5 | 5/5 | 4/5 |

**Errors**

- `anthropic:claude-haiku-5-5@default`: the reply did not parse as {notes, summary}
- `anthropic:claude-sonnet-5@default`: the reply did not parse as {notes, summary}

