## dailyBrief on `daily_brief/v1` (4 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 12 | 100% | **100%** | 76%–100% | 100% 100% 100% | 0.8 | 0.9 | 384 / 0 | 74 | 0.00008 | 0.08 |
| `openai:gpt-4.1-mini` | 12 | 100% | **100%** | 76%–100% | 100% 100% 100% | 1.2 | 1.4 | 251 / 0 | 45 | 0.00017 | 0.17 |
| `openai:gpt-6-luna` | 12 | 100% | **100%** | 76%–100% | 100% 100% 100% | 1.5 | 1.6 | 250 / 0 | 42 | 0.00005 | 0.05 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-6-luna` |
|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.417 | 0.167 | 0.833 |
| changed_the_wording | 1.000 | 1.000 | 1.000 |
| headline_at_most_one_number | 1.000 | 1.000 | 1.000 |
| headline_one_sentence | 1.000 | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-6-luna` |
|---|---|---|---|
| (none) | | | |

