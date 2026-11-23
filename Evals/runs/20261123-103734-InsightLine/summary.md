## insightLine on `insight_line/v1` (1 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 3 | 0% | **0%** | 0%–56% | 0% 0% 0% | 0.0 | 0.0 | 416 / 0 | 80 | 0.00008 | 0.08 |
| `anthropic:claude-sonnet-5` | 3 | 100% | **100%** | 44%–100% | 100% 100% 100% | 1.4 | 1.4 | 414 / 0 | 30 | 0.00113 | 1.13 |
| `anthropic:claude-sonnet-5-5` | 3 | 0% | **0%** | 0%–56% | 0% 0% 0% | 0.0 | 0.0 | 416 / 0 | 80 | 0.00163 | 1.63 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|
| all_numbers_kept |  | 1.000 |  |
| at_most_22_words |  | 1.000 |  |
| at_most_one_emoji |  | 1.000 |  |
| changed_the_wording |  | 1.000 |  |
| no_hashtag |  | 1.000 |  |
| no_number_invented |  | 1.000 |  |
| one_sentence |  | 1.000 |  |
| used | 0.000 | 1.000 | 0.000 |
| wrong_person_pronoun |  | 0.000 |  |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|
| well-fueled-lose | 0/3 | 3/3 | 0/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: the call failed
- `anthropic:claude-sonnet-5-5`: the call failed

