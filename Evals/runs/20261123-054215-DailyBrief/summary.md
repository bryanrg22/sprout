## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.0 | 1.3 | 243 / 0 | 54 | 0.00051 | 0.51 |
| `anthropic:claude-haiku-5-5` | 39 | 92% | **92%** | 80%–97% | 92% 92% 92% | 0.7 | 1.0 | 341 / 0 | 75 | 0.00007 | 0.07 |
| `anthropic:claude-sonnet-5` | 39 | 100% | **95%** | 83%–99% | 92% 92% 100% | 1.2 | 1.4 | 339 / 0 | 68 | 0.00136 | 1.36 |
| `anthropic:claude-sonnet-5-5` | 39 | 97% | **97%** | 87%–100% | 100% 92% 100% | 1.6 | 1.8 | 341 / 0 | 73 | 0.00141 | 1.41 |
| `openai:gpt-4.1-mini` | 39 | 95% | **92%** | 80%–97% | 85% 100% 92% | 1.1 | 1.4 | 225 / 0 | 43 | 0.00016 | 0.16 |
| `openai:gpt-5.6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.4 | 1.7 | 224 / 0 | 43 | 0.00010 | 0.10 |
| `openai:gpt-5.6-terra` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.4 | 1.7 | 224 / 0 | 42 | 0.00095 | 0.95 |
| `openai:gpt-6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.2 | 1.7 | 224 / 0 | 43 | 0.00004 | 0.04 |
| `openai:gpt-6.1-terra` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.7 | 2.1 | 224 / 0 | 42 | 0.00044 | 0.44 |
| `openai:gpt-6.2-sol` | 39 | 92% | **92%** | 80%–97% | 92% 92% 92% | 1.8 | 2.0 | 224 / 0 | 45 | 0.00090 | 0.90 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 0.974 | 1.000 | 0.973 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.308 | 0.528 | 1.000 | 0.921 | 0.568 | 0.923 | 1.000 | 0.923 | 1.000 | 1.000 |
| changed_the_wording | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_at_most_one_number | 1.000 | 1.000 | 0.923 | 1.000 | 0.811 | 0.974 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_one_sentence | 0.949 | 0.667 | 0.897 | 0.711 | 1.000 | 1.000 | 0.949 | 0.974 | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 0.949 | 1.000 | 0.973 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 0.923 | 1.000 | 0.974 | 0.949 | 1.000 | 1.000 | 1.000 | 1.000 | 0.923 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| big-steps-steady-hr | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| deep-sleep | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| gap-return | 3/3 | 0/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 |
| quiet-day-hr | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| streak-14 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: rephrase returned nil (call failed or guardrail rejected it)
- `anthropic:claude-sonnet-5-5`: rephrase returned nil (call failed or guardrail rejected it)
- `openai:gpt-4.1-mini`: rephrase returned nil (call failed or guardrail rejected it)
- `openai:gpt-6.2-sol`: rephrase returned nil (call failed or guardrail rejected it)

