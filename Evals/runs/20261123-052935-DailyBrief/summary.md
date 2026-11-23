## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.0 | 1.4 | 243 / 0 | 54 | 0.00051 | 0.51 |
| `anthropic:claude-haiku-5-5` | 39 | 92% | **85%** | 70%–93% | 85% 92% 77% | 0.7 | 1.0 | 341 / 0 | 71 | 0.00007 | 0.07 |
| `anthropic:claude-sonnet-5` | 39 | 97% | **95%** | 83%–99% | 92% 92% 100% | 1.2 | 1.5 | 339 / 0 | 68 | 0.00136 | 1.36 |
| `anthropic:claude-sonnet-5-5` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.7 | 2.0 | 341 / 0 | 72 | 0.00141 | 1.41 |
| `openai:gpt-4.1-mini` | 39 | 87% | **77%** | 62%–87% | 85% 69% 77% | 1.2 | 1.4 | 225 / 0 | 43 | 0.00016 | 0.16 |
| `openai:gpt-5.6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.5 | 3.0 | 224 / 0 | 43 | 0.00010 | 0.10 |
| `openai:gpt-5.6-terra` | 39 | 100% | **95%** | 83%–99% | 100% 92% 92% | 1.4 | 1.7 | 224 / 0 | 43 | 0.00096 | 0.96 |
| `openai:gpt-6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.2 | 1.5 | 224 / 0 | 43 | 0.00004 | 0.04 |
| `openai:gpt-6.1-terra` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.8 | 2.1 | 224 / 0 | 43 | 0.00044 | 0.44 |
| `openai:gpt-6.2-sol` | 39 | 92% | **92%** | 80%–97% | 92% 92% 92% | 1.8 | 2.4 | 224 / 0 | 44 | 0.00089 | 0.89 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| all_numbers_kept | 1.000 | 0.917 | 0.974 | 1.000 | 0.971 | 1.000 | 0.949 | 1.000 | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.308 | 0.500 | 0.921 | 0.897 | 0.500 | 0.949 | 1.000 | 0.949 | 1.000 | 1.000 |
| changed_the_wording | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_at_most_one_number | 0.974 | 1.000 | 0.947 | 1.000 | 0.824 | 0.974 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_one_sentence | 0.897 | 0.611 | 0.868 | 0.641 | 0.971 | 1.000 | 0.949 | 1.000 | 0.923 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 1.000 | 1.000 | 0.912 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 0.923 | 0.974 | 1.000 | 0.872 | 1.000 | 1.000 | 1.000 | 1.000 | 0.923 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| big-steps-steady-hr | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| gap-return | 3/3 | 0/3 | 2/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 |
| long-sleep | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| quiet-day-hr | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| quiet-day-plain | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| streak-14 | 3/3 | 2/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| travel-day0-east | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 |
| travel-day2-west | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: rephrase returned nil (call failed or guardrail rejected it)
- `anthropic:claude-sonnet-5`: rephrase returned nil (call failed or guardrail rejected it)
- `openai:gpt-4.1-mini`: rephrase returned nil (call failed or guardrail rejected it)
- `openai:gpt-6.2-sol`: rephrase returned nil (call failed or guardrail rejected it)

