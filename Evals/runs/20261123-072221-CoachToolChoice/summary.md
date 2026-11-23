## coachTurn on `coach_tool_choice/v2` (34 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 102 | 100% | **93%** | 87%–97% | 94% 94% 91% | 1.0 | 3.3 | 916 / 7424 | 91 | 0.00259 | 2.59 |
| `anthropic:claude-haiku-5-5` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 0.8 | 2.6 | 834 / 9664 | 155 | 0.00033 | 0.33 |
| `anthropic:claude-sonnet-5` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.5 | 3.8 | 832 / 9829 | 123 | 0.00613 | 6.13 |
| `anthropic:claude-sonnet-5-5` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.5 | 4.2 | 834 / 9865 | 123 | 0.00489 | 4.89 |
| `openai:gpt-4.1-mini` | 102 | 100% | **92%** | 85%–96% | 91% 91% 94% | 1.2 | 1.6 | 1018 / 5050 | 33 | 0.00097 | 0.97 |
| `openai:gpt-5.6-luna` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.4 | 2.2 | 1173 / 4898 | 45 | 0.00039 | 0.39 |
| `openai:gpt-5.6-terra` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.2 | 2.9 | 1173 / 4898 | 42 | 0.00383 | 3.83 |
| `openai:gpt-6-luna` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.3 | 2.2 | 1173 / 4898 | 32 | 0.00018 | 0.18 |
| `openai:gpt-6.1-terra` | 102 | 100% | **97%** | 92%–99% | 97% 97% 97% | 1.7 | 3.2 | 1228 / 4843 | 31 | 0.00162 | 1.62 |
| `openai:gpt-6.2-sol` | 102 | 100% | **98%** | 93%–99% | 97% 100% 97% | 1.5 | 2.9 | 1119 / 4952 | 34 | 0.00307 | 3.07 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| acted_when_should_not | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| arguments_correct | 0.931 | 1.000 | 1.000 | 1.000 | 0.922 | 1.000 | 1.000 | 1.000 | 0.971 | 0.980 |
| call_was_valid | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| decision_correct | 0.941 | 1.000 | 1.000 | 1.000 | 0.931 | 1.000 | 1.000 | 1.000 | 0.971 | 0.980 |
| tool_correct | 0.941 | 1.000 | 1.000 | 1.000 | 0.931 | 1.000 | 1.000 | 1.000 | 0.971 | 0.980 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| direction-switch | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| food-eggs | 2/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 0/3 | 1/3 |
| remember-injury | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| units-metric | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| workout-lift | 0/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

