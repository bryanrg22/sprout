## weeklyReflection on `weekly_reflection/v1` (16 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 48 | 100% | **100%** | 100%–100% | 93%–100% | 100% 100% 100% | 1.6 | 1.9 | 1077 / 0 | 190 | 0.00020 | 0.20 |
| `anthropic:claude-sonnet-5` | 48 | 98% | **98%** | 94%–100% | 89%–100% | 100% 94% 100% | 3.5 | 4.5 | 1076 / 0 | 201 | 0.00416 | 4.16 |

**Compared with `anthropic:claude-haiku-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5` | 16 | -2.1% | -6.2% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 |
| name_used_once | 0.979 | 0.979 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| repeats_a_given_count | 1.000 | 0.976 |
| three_to_five_sentences | 0.979 | 0.766 |
| used | 1.000 | 0.979 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| alex-fresh-page | 3/3 | 2/3 |

**Errors**

- `anthropic:claude-sonnet-5`: the sanitiser discarded the reply

