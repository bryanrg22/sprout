## insightLine on `insight_line/v1` (19 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 57 | 100% | **100%** | 100%–100% | 94%–100% | 100% 100% 100% | 1.1 | 1.3 | 407 / 0 | 32 | 0.00114 | 1.14 |
| `anthropic:claude-sonnet-5-5` | 57 | 100% | **100%** | 100%–100% | 94%–100% | 100% 100% 100% | 0.8 | 1.6 | 408 / 0 | 35 | 0.00116 | 1.16 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 19 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| all_numbers_kept | 1.000 | 1.000 |
| at_most_22_words | 0.982 | 0.930 |
| at_most_one_emoji | 1.000 | 1.000 |
| changed_the_wording | 1.000 | 1.000 |
| no_hashtag | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| one_sentence | 0.982 | 0.825 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| (none) | | |

