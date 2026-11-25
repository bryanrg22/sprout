## weeklyReflection on `weekly_reflection/v1` (16 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 48 | 100% | **98%** | 94%–100% | 89%–100% | 94% 100% 100% | 2.3 | 3.2 | 778 / 0 | 152 | 0.00154 | 1.54 |
| `anthropic:claude-haiku-5-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 1.6 | 1.9 | 1077 / 0 | 186 | 0.00020 | 0.20 |

**Compared with `anthropic:claude-haiku-4-5-20251001` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 16 | +2.1% | +0.0% to +6.2% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 |
| name_used_once | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 0.979 | 1.000 |
| repeats_a_given_count | 0.905 | 1.000 |
| three_to_five_sentences | 0.917 | 0.938 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| alex-fresh-page | 2/3 | 3/3 |

