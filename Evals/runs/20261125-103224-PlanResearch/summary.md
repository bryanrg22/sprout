## planResearch on `plan_build/v1` (1 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 15.4 | 15.4 | 84946 / 0 | 2530 | 0.00976 | 9.76 |
| `anthropic:claude-opus-4-8` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 29.4 | 29.4 | 85071 / 0 | 2223 | 0.48093 | 480.93 |
| `anthropic:claude-opus-5-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 24.4 | 24.4 | 86012 / 0 | 2418 | 0.39241 | 392.41 |
| `anthropic:claude-sonnet-5` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 29.3 | 29.3 | 69225 / 0 | 2641 | 0.16486 | 164.86 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| brief_chars | 1777.000 | 4576.000 | 3068.000 | 4229.000 |
| brief_words | 280.000 | 708.000 | 497.000 | 640.000 |
| cited_sources | 0.000 | 13.000 | 14.000 | 13.000 |
| mentions_a_rate | 1.000 | 1.000 | 1.000 | 1.000 |
| mentions_protein | 1.000 | 1.000 | 1.000 | 1.000 |
| searched | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 1.000 | 1.000 | 1.000 |
| web_search_requests | 5.000 | 5.000 | 5.000 | 5.000 |
| web_search_usd | 0.050 | 0.050 | 0.050 | 0.050 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-opus-4-8` | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|---|---|
| (none) | | | | |

