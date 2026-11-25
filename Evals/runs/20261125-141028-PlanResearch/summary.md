## planResearch on `plan_build/v1` (8 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-opus-5-5` | 8 | 100% | **100%** | 100%–100% | 68%–100% | 100% | 35.9 | 35.9 | 77752 / 0 | 3349 | 0.37799 | 377.99 |
| `openai:gpt-5.6-sol` | 8 | 100% | **100%** | 100%–100% | 68%–100% | 100% | 23.5 | 31.6 | 20728 / 4540 | 1415 | 0.11303 | 113.03 |

**Compared with `anthropic:claude-opus-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-5.6-sol` | 8 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-opus-5-5` | `openai:gpt-5.6-sol` |
|---|---|---|
| brief_chars | 5628.250 | 4413.500 |
| brief_words | 880.500 | 490.000 |
| cited_sources | 17.500 | 6.375 |
| mentions_a_rate | 1.000 | 1.000 |
| mentions_protein | 1.000 | 1.000 |
| searched | 1.000 | 1.000 |
| used | 1.000 | 1.000 |
| web_search_requests | 5.000 | 2.625 |
| web_search_usd | 0.050 | 0.026 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-opus-5-5` | `openai:gpt-5.6-sol` |
|---|---|---|
| (none) | | |

