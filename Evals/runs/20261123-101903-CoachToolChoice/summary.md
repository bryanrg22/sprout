## coachTurn on `coach_tool_choice/v2` (34 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 102 | 100% | **91%** | 84%–95% | 91% 91% 91% | 1.0 | 3.7 | 916 / 8541 | 96 | 0.00269 | 2.69 |
| `anthropic:claude-haiku-5-5` | 102 | 100% | **99%** | 95%–100% | 97% 100% 100% | 0.8 | 2.6 | 833 / 11296 | 157 | 0.00033 | 0.33 |
| `anthropic:claude-sonnet-5` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.8 | 4.5 | 831 / 11245 | 123 | 0.00659 | 6.59 |
| `openai:gpt-5.6-terra` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.5 | 2.9 | 1277 / 5674 | 43 | 0.00420 | 4.20 |
| `openai:gpt-6-luna` | 102 | 100% | **100%** | 96%–100% | 100% 100% 100% | 1.2 | 2.9 | 1214 / 5737 | 31 | 0.00019 | 0.19 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` |
|---|---|---|---|---|---|
| acted_when_should_not | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| arguments_correct | 0.912 | 0.990 | 1.000 | 1.000 | 1.000 |
| call_was_valid | 0.990 | 1.000 | 1.000 | 1.000 | 1.000 |
| decision_correct | 0.941 | 1.000 | 1.000 | 1.000 | 1.000 |
| tool_correct | 0.931 | 1.000 | 1.000 | 1.000 | 1.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` |
|---|---|---|---|---|---|
| direction-switch | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| food-eggs | 0/3 | 2/3 | 3/3 | 3/3 | 3/3 |
| workout-lift | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 |

