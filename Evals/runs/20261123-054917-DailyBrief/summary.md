## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.0 | 1.2 | 243 / 0 | 53 | 0.00051 | 0.51 |
| `anthropic:claude-haiku-5-5` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 0.8 | 1.0 | 341 / 0 | 72 | 0.00007 | 0.07 |
| `anthropic:claude-sonnet-5` | 39 | 100% | **97%** | 87%–100% | 100% 100% 92% | 1.1 | 1.4 | 339 / 0 | 67 | 0.00134 | 1.34 |
| `anthropic:claude-sonnet-5-5` | 39 | 97% | **97%** | 87%–100% | 100% 92% 100% | 1.6 | 2.2 | 341 / 0 | 80 | 0.00148 | 1.48 |
| `openai:gpt-4.1-mini` | 39 | 95% | **90%** | 76%–96% | 92% 85% 92% | 1.2 | 1.6 | 225 / 0 | 43 | 0.00016 | 0.16 |
| `openai:gpt-5.6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.4 | 2.8 | 224 / 0 | 42 | 0.00010 | 0.10 |
| `openai:gpt-5.6-terra` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.4 | 1.7 | 224 / 0 | 43 | 0.00096 | 0.96 |
| `openai:gpt-6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.2 | 1.8 | 224 / 0 | 42 | 0.00004 | 0.04 |
| `openai:gpt-6.1-terra` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.7 | 2.0 | 224 / 0 | 42 | 0.00043 | 0.43 |
| `openai:gpt-6.2-sol` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.8 | 4.7 | 224 / 0 | 45 | 0.00089 | 0.89 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 1.000 | 1.000 | 0.946 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.359 | 0.308 | 1.000 | 0.895 | 0.595 | 0.923 | 1.000 | 0.923 | 1.000 | 1.000 |
| changed_the_wording | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_at_most_one_number | 0.974 | 1.000 | 0.923 | 1.000 | 0.892 | 0.974 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_one_sentence | 0.949 | 0.718 | 0.846 | 0.711 | 1.000 | 1.000 | 0.923 | 1.000 | 0.974 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 0.974 | 1.000 | 0.946 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 1.000 | 1.000 | 0.974 | 0.949 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| big-steps-steady-hr | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| check-in-no-name | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| deep-sleep | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| streak-14 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-sonnet-5-5`: rephrase returned nil (call failed or guardrail rejected it)
- `openai:gpt-4.1-mini`: rephrase returned nil (call failed or guardrail rejected it)

