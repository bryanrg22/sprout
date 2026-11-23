## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 39 | 100% | **97%** | 87%–100% | 100% 100% 92% | 1.0 | 1.4 | 271 / 0 | 54 | 0.00054 | 0.54 |
| `anthropic:claude-haiku-5-5` | 39 | 92% | **92%** | 80%–97% | 92% 92% 92% | 0.7 | 0.9 | 380 / 0 | 68 | 0.00007 | 0.07 |
| `anthropic:claude-sonnet-5` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.3 | 1.6 | 378 / 0 | 66 | 0.00142 | 1.42 |
| `anthropic:claude-sonnet-5-5` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.1 | 1.7 | 380 / 0 | 72 | 0.00148 | 1.48 |
| `openai:gpt-4.1-mini` | 39 | 77% | **72%** | 56%–83% | 62% 69% 85% | 1.2 | 1.6 | 231 / 0 | 39 | 0.00016 | 0.16 |
| `openai:gpt-5.6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.3 | 1.6 | 250 / 0 | 42 | 0.00010 | 0.10 |
| `openai:gpt-5.6-terra` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.2 | 1.5 | 250 / 0 | 43 | 0.00101 | 1.01 |
| `openai:gpt-6-luna` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.5 | 3.4 | 250 / 0 | 43 | 0.00005 | 0.05 |
| `openai:gpt-6.1-terra` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.9 | 2.4 | 250 / 0 | 43 | 0.00046 | 0.46 |
| `openai:gpt-6.2-sol` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.9 | 2.5 | 250 / 0 | 45 | 0.00095 | 0.95 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.231 | 0.500 | 0.949 | 0.923 | 0.367 | 0.974 | 1.000 | 0.949 | 1.000 | 1.000 |
| changed_the_wording | 0.949 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_at_most_one_number | 1.000 | 0.917 | 0.974 | 0.949 | 0.800 | 0.974 | 1.000 | 0.949 | 1.000 | 1.000 |
| headline_one_sentence | 0.923 | 0.972 | 0.872 | 0.590 | 1.000 | 1.000 | 0.923 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 0.974 | 1.000 | 1.000 | 1.000 | 0.933 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 1.000 | 0.923 | 1.000 | 1.000 | 0.769 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| big-steps-steady-hr | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| check-in-named | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| check-in-no-name | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| deep-sleep | 2/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| quiet-day-plain | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| streak-14 | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| travel-day0-east | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| travel-day2-west | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| trend-eased | 3/3 | 0/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: rephrase returned nil (call failed or guardrail rejected it)
- `openai:gpt-4.1-mini`: rephrase returned nil (call failed or guardrail rejected it)

