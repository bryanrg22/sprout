## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 0.9 | 1.2 | 271 / 0 | 53 | 0.00053 | 0.53 |
| `anthropic:claude-haiku-5-5` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 0.8 | 1.0 | 379 / 0 | 74 | 0.00008 | 0.08 |
| `anthropic:claude-sonnet-5` | 39 | 100% | **92%** | 80%–97% | 92% 92% 92% | 1.4 | 1.8 | 378 / 0 | 63 | 0.00138 | 1.38 |
| `anthropic:claude-sonnet-5-5` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.0 | 1.7 | 379 / 0 | 71 | 0.00146 | 1.46 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 0.974 | 1.000 |
| body_at_most_two_sentences | 0.231 | 0.462 | 0.974 | 0.769 |
| changed_the_wording | 0.897 | 1.000 | 1.000 | 1.000 |
| headline_at_most_one_number | 1.000 | 0.949 | 0.974 | 1.000 |
| headline_one_sentence | 0.872 | 0.538 | 0.923 | 0.718 |
| no_number_invented | 1.000 | 1.000 | 0.923 | 1.000 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| streak-14 | 3/3 | 3/3 | 0/3 | 3/3 |

