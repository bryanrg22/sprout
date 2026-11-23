## insightLine on `insight_line/v1` (19 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 0.7 | 0.8 | 296 / 0 | 26 | 0.00043 | 0.43 |
| `anthropic:claude-haiku-5-5` | 57 | 100% | **95%** | 86%–98% | 95% 95% 95% | 0.7 | 0.9 | 408 / 0 | 34 | 0.00006 | 0.06 |
| `anthropic:claude-sonnet-5` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 1.3 | 1.4 | 407 / 0 | 32 | 0.00114 | 1.14 |
| `anthropic:claude-sonnet-5-5` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 0.8 | 1.6 | 408 / 0 | 35 | 0.00116 | 1.16 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 1.000 | 1.000 |
| at_most_22_words | 0.982 | 0.930 | 0.982 | 0.912 |
| at_most_one_emoji | 1.000 | 1.000 | 1.000 | 1.000 |
| changed_the_wording | 0.860 | 1.000 | 1.000 | 1.000 |
| no_hashtag | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 1.000 | 0.947 | 1.000 | 1.000 |
| one_sentence | 0.982 | 0.877 | 1.000 | 0.825 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| welcome-back-14 | 3/3 | 0/3 | 3/3 | 3/3 |

