## planResearch on `plan_build/v1` (8 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 8 | 100% | **100%** | 100%–100% | 68%–100% | 100% | 15.1 | 16.7 | 70417 / 0 | 2500 | 0.00829 | 8.29 |
| `anthropic:claude-opus-4-8` | 8 | 100% | **100%** | 100%–100% | 68%–100% | 100% | 29.7 | 32.0 | 77467 / 0 | 2217 | 0.44275 | 442.75 |
| `anthropic:claude-opus-5-5` | 8 | 100% | **100%** | 100%–100% | 68%–100% | 100% | 23.8 | 24.6 | 82242 / 0 | 2390 | 0.37677 | 376.77 |
| `anthropic:claude-sonnet-5` | 8 | 100% | **100%** | 100%–100% | 68%–100% | 100% | 27.8 | 31.9 | 80717 / 0 | 2588 | 0.18732 | 187.32 |

**Compared with `anthropic:claude-opus-4-8` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 8 | +0.0% | +0.0% to +0.0% |
| `anthropic:claude-opus-5-5` | 8 | +0.0% | +0.0% to +0.0% |
| `anthropic:claude-sonnet-5` | 8 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| brief_chars | 929.750 | 4461.125 | 3400.625 | 4356.125 |
| brief_words | 152.875 | 679.125 | 542.250 | 658.250 |
| cited_sources | 2.375 | 12.250 | 12.375 | 10.375 |
| mentions_a_rate | 0.875 | 1.000 | 1.000 | 1.000 |
| mentions_protein | 0.500 | 0.875 | 0.875 | 0.875 |
| searched | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| web_search_requests | 4.625 | 4.750 | 5.000 | 5.000 |
| web_search_usd | 0.046 | 0.048 | 0.050 | 0.050 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| (none) | | | | |

