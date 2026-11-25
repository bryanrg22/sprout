## insightLine on `insight_line/v1` (19 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 57 | 100% | **100%** | 100%–100% | 94%–100% | 100% 100% 100% | 0.7 | 0.8 | 296 / 0 | 25 | 0.00042 | 0.42 |
| `anthropic:claude-haiku-5-5` | 57 | 100% | **100%** | 100%–100% | 94%–100% | 100% 100% 100% | 0.6 | 1.0 | 408 / 0 | 35 | 0.00006 | 0.06 |

**Compared with `anthropic:claude-haiku-4-5-20251001` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 19 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| all_numbers_kept | 1.000 | 1.000 |
| at_most_22_words | 1.000 | 0.895 |
| at_most_one_emoji | 1.000 | 1.000 |
| changed_the_wording | 0.860 | 1.000 |
| no_hashtag | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| one_sentence | 1.000 | 0.860 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| (none) | | |

