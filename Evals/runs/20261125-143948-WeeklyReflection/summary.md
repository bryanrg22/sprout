## weeklyReflection on `weekly_reflection/v1` (16 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 1.6 | 2.0 | 1077 / 0 | 187 | 0.00020 | 0.20 |
| `openai:gpt-6-luna` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 2.1 | 2.8 | 709 / 0 | 116 | 0.00013 | 0.13 |

**Compared with `anthropic:claude-haiku-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6-luna` | 16 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `openai:gpt-6-luna` |
|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 |
| name_used_once | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| repeats_a_given_count | 1.000 | 1.000 |
| three_to_five_sentences | 0.938 | 1.000 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `openai:gpt-6-luna` |
|---|---|---|
| (none) | | |

