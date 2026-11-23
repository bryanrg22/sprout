## coachTurn on `coach_tool_choice/v2` (34 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 102 | 100% | **90%** | 83%–95% | 88% 94% 88% | 1.0 | 3.5 | 916 / 7294 | 93 | 0.00268 | 2.68 |
| `anthropic:claude-haiku-5-5` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 0.8 | 2.5 | 835 / 9595 | 143 | 0.00033 | 0.33 |
| `anthropic:claude-sonnet-5` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.4 | 4.7 | 833 / 9759 | 126 | 0.00614 | 6.14 |
| `anthropic:claude-sonnet-5-5` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.6 | 3.8 | 835 / 9694 | 120 | 0.00509 | 5.09 |
| `openai:gpt-4.1-mini` | 102 | 100% | **87%** | 79%–92% | 85% 91% 85% | 1.0 | 1.3 | 671 / 5348 | 32 | 0.00085 | 0.85 |
| `openai:gpt-5.6-luna` | 102 | 100% | **99%** | 95%–100% | 97% 100% 100% | 1.3 | 2.3 | 1169 / 4855 | 47 | 0.00039 | 0.39 |
| `openai:gpt-5.6-terra` | 102 | 100% | **99%** | 95%–100% | 100% 97% 100% | 1.2 | 2.8 | 1169 / 4855 | 42 | 0.00382 | 3.82 |
| `openai:gpt-6-luna` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.3 | 2.4 | 1385 / 4639 | 32 | 0.00020 | 0.20 |
| `openai:gpt-6.1-terra` | 102 | 100% | **97%** | 92%–99% | 97% 97% 97% | 1.5 | 3.5 | 1169 / 4855 | 32 | 0.00157 | 1.57 |
| `openai:gpt-6.2-sol` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.5 | 2.8 | 1223 / 4801 | 34 | 0.00327 | 3.27 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| acted_when_should_not | 0.000 | 0.000 | 0.000 | 0.000 | 0.020 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| arguments_correct | 0.902 | 1.000 | 1.000 | 1.000 | 0.873 | 0.990 | 0.990 | 1.000 | 0.971 | 1.000 |
| call_was_valid | 0.990 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| decision_correct | 0.922 | 1.000 | 1.000 | 1.000 | 0.902 | 0.990 | 0.990 | 1.000 | 0.971 | 1.000 |
| tool_correct | 0.912 | 1.000 | 1.000 | 1.000 | 0.902 | 0.990 | 0.990 | 1.000 | 0.971 | 1.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| direction-switch | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| food-eggs | 1/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 2/3 | 3/3 | 0/3 | 3/3 |
| musing-step-goal | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| pace-faster | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| remember-injury | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| units-metric | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| workout-lift | 0/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| workout-run | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

