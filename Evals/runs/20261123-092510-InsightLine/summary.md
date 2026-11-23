## insightLine on `insight_line/v1` (19 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 0.7 | 0.8 | 296 / 0 | 25 | 0.00042 | 0.42 |
| `anthropic:claude-haiku-5-5` | 57 | 95% | **95%** | 86%–98% | 95% 95% 95% | 0.7 | 0.9 | 409 / 0 | 36 | 0.00006 | 0.06 |
| `anthropic:claude-sonnet-5` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 0.9 | 1.3 | 407 / 0 | 32 | 0.00113 | 1.13 |
| `anthropic:claude-sonnet-5-5` | 57 | 95% | **95%** | 86%–98% | 95% 95% 95% | 0.9 | 1.6 | 409 / 0 | 39 | 0.00121 | 1.21 |
| `openai:gpt-4.1-mini` | 57 | 100% | **96%** | 88%–99% | 95% 100% 95% | 0.9 | 1.4 | 269 / 0 | 21 | 0.00014 | 0.14 |
| `openai:gpt-5.6-luna` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 1.4 | 1.8 | 268 / 0 | 24 | 0.00008 | 0.08 |
| `openai:gpt-5.6-terra` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 1.2 | 1.5 | 268 / 0 | 24 | 0.00082 | 0.82 |
| `openai:gpt-6-luna` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 1.2 | 2.3 | 268 / 0 | 25 | 0.00004 | 0.04 |
| `openai:gpt-6.1-terra` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 1.6 | 2.5 | 268 / 0 | 24 | 0.00039 | 0.39 |
| `openai:gpt-6.2-sol` | 57 | 100% | **100%** | 94%–100% | 100% 100% 100% | 1.7 | 2.0 | 268 / 0 | 24 | 0.00078 | 0.78 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| at_most_22_words | 1.000 | 0.963 | 1.000 | 0.889 | 1.000 | 1.000 | 1.000 | 1.000 | 0.965 | 1.000 |
| at_most_one_emoji | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| changed_the_wording | 0.877 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_hashtag | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 1.000 | 1.000 | 0.965 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| one_sentence | 1.000 | 0.833 | 0.965 | 0.870 | 0.947 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 0.947 | 1.000 | 0.947 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| welcome-back-14 | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| well-fueled-lose | 3/3 | 0/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: the call failed
- `anthropic:claude-sonnet-5-5`: the call failed

