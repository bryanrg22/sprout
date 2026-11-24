## weeklyReflection on `weekly_reflection/v1` (16 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 80 | 100% | **99%** | 96%–100% | 93%–100% | 100% 94% 100% 100% 100% | 2.3 | 3.0 | 778 / 0 | 149 | 0.00152 | 1.52 |
| `anthropic:claude-haiku-5-5` | 80 | 100% | **100%** | 100%–100% | 95%–100% | 100% 100% 100% 100% 100% | 1.5 | 1.8 | 1077 / 0 | 191 | 0.00020 | 0.20 |

**Compared with `anthropic:claude-haiku-4-5-20251001` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 16 | +1.2% | +0.0% to +3.7% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| at_most_one_emoji | 0.988 | 1.000 |
| name_used_once | 1.000 | 0.988 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 0.988 | 1.000 |
| repeats_a_given_count | 0.986 | 1.000 |
| three_to_five_sentences | 0.850 | 0.988 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| sam-quiet-week | 4/5 | 5/5 |

