## memoryFold on `memory_fold/v1` (12 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 36 | 97% | **97%** | 92%–100% | 86%–100% | 100% 92% 100% | 4.4 | 5.3 | 1351 / 0 | 394 | 0.00664 | 6.64 |
| `openai:gpt-6.2-sol` | 36 | 100% | **28%** | 6%–53% | 16%–44% | 25% 25% 33% | 4.1 | 5.3 | 826 / 0 | 148 | 0.00313 | 3.13 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 12 | -69.4% | -94.4% to -38.9% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| all_facts_kept | 1.000 | 0.278 |
| bare_json | 1.000 | 1.000 |
| both_fields_returned | 1.000 | 1.000 |
| existing_notes_kept | 1.000 | 0.944 |
| facts_kept_share | 1.000 | 0.819 |
| kept_allergy | 1.000 | 1.000 |
| kept_injury | 1.000 | 0.278 |
| kept_preference | 1.000 | 1.000 |
| kept_schedule | 1.000 | 1.000 |
| no_app_owned_number_stored | 1.000 | 1.000 |
| no_gendered_pronoun | 0.857 | 1.000 |
| notes_chars | 508.514 | 301.056 |
| notes_within_budget | 1.000 | 1.000 |
| parses | 0.972 | 1.000 |
| retracted_fact_absent | 1.000 | 1.000 |
| small_talk_not_kept | 0.457 | 0.833 |
| summary_chars | 507.457 | 336.278 |
| summary_within_budget | 1.000 | 1.000 |
| wrong_person_pronoun | 0.029 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| alex-existing-notes | 3/3 | 0/3 |
| alex-first-fold | 3/3 | 1/3 |
| alex-notes-and-a-short-lived-plan | 3/3 | 0/3 |
| alex-takes-back-a-saved-note | 3/3 | 0/3 |
| alex-with-a-summary | 2/3 | 3/3 |
| sam-existing-notes | 3/3 | 0/3 |
| sam-first-fold | 3/3 | 0/3 |
| sam-notes-and-a-cancelled-booking | 3/3 | 0/3 |
| sam-takes-back-a-saved-note | 3/3 | 0/3 |
| sam-with-a-summary | 3/3 | 0/3 |

**Errors**

- `anthropic:claude-sonnet-5`: the reply did not parse as {notes, summary}

