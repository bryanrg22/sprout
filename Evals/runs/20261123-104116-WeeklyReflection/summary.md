## weeklyReflection on `weekly_reflection/v1` (16 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 48 | 92% | **85%** | 73%–93% | 81% 88% 88% | 2.3 | 2.9 | 754 / 0 | 151 | 0.00151 | 1.51 |
| `anthropic:claude-haiku-5-5` | 48 | 100% | **96%** | 86%–99% | 94% 100% 94% | 1.6 | 1.8 | 1046 / 0 | 183 | 0.00020 | 0.20 |
| `anthropic:claude-sonnet-5` | 48 | 90% | **83%** | 70%–91% | 88% 69% 94% | 3.4 | 3.9 | 1045 / 0 | 203 | 0.00412 | 4.12 |
| `anthropic:claude-sonnet-5-5` | 48 | 88% | **85%** | 73%–93% | 81% 81% 94% | 3.0 | 8.2 | 1046 / 0 | 219 | 0.00428 | 4.28 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 | 1.000 | 1.000 |
| name_used_once | 1.000 | 0.979 | 0.953 | 1.000 |
| no_list_or_header | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 0.932 | 0.958 | 0.930 | 0.976 |
| repeats_a_given_count | 0.895 | 1.000 | 0.973 | 1.000 |
| three_to_five_sentences | 0.955 | 1.000 | 0.721 | 0.643 |
| used | 0.917 | 1.000 | 0.896 | 0.875 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| alex-climbing-consistent | 2/3 | 3/3 | 2/3 | 3/3 |
| alex-dropped-fast | 0/3 | 3/3 | 0/3 | 2/3 |
| alex-fresh-page | 3/3 | 2/3 | 1/3 | 2/3 |
| alex-maintain-eased-down | 3/3 | 3/3 | 3/3 | 1/3 |
| sam-dropping-fast | 2/3 | 3/3 | 2/3 | 3/3 |
| sam-plateau | 3/3 | 3/3 | 3/3 | 2/3 |
| sam-quiet-week | 1/3 | 2/3 | 2/3 | 3/3 |
| sam-ticked-up | 3/3 | 3/3 | 3/3 | 1/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: the sanitiser discarded the reply
- `anthropic:claude-sonnet-5`: the sanitiser discarded the reply
- `anthropic:claude-sonnet-5-5`: the sanitiser discarded the reply

