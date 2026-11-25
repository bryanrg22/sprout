## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 39 | 100% | **100%** | 100%–100% | 91%–100% | 100% 100% 100% | 1.4 | 1.8 | 378 / 0 | 63 | 0.00138 | 1.38 |
| `anthropic:claude-sonnet-5-5` | 39 | 100% | **100%** | 100%–100% | 91%–100% | 100% 100% 100% | 1.0 | 1.8 | 379 / 0 | 71 | 0.00146 | 1.46 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 13 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| all_numbers_kept | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.974 | 0.744 |
| changed_the_wording | 1.000 | 1.000 |
| headline_at_most_one_number | 1.000 | 1.000 |
| headline_one_sentence | 0.872 | 0.744 |
| no_number_invented | 1.000 | 1.000 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| (none) | | |

