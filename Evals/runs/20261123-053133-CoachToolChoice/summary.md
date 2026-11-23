## coachTurn on `coach_tool_choice/v1` (34 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 102 | 100% | **92%** | 85%–96% | 91% 94% 91% | 1.0 | 3.4 | 916 / 7370 | 95 | 0.00260 | 2.60 |
| `anthropic:claude-haiku-5-5` | 102 | 100% | **97%** | 92%–99% | 97% 97% 97% | 0.8 | 2.5 | 835 / 9595 | 145 | 0.00033 | 0.33 |
| `anthropic:claude-sonnet-5` | 102 | 100% | **98%** | 93%–99% | 100% 97% 97% | 1.4 | 4.3 | 833 / 9860 | 125 | 0.00589 | 5.89 |
| `anthropic:claude-sonnet-5-5` | 102 | 100% | **99%** | 95%–100% | 100% 100% 97% | 1.6 | 4.3 | 835 / 9994 | 120 | 0.00437 | 4.37 |
| `openai:gpt-4.1-mini` | 102 | 100% | **90%** | 83%–95% | 91% 88% 91% | 1.0 | 1.7 | 1115 / 4903 | 32 | 0.00099 | 0.99 |
| `openai:gpt-5.6-luna` | 102 | 100% | **93%** | 87%–97% | 91% 94% 94% | 1.4 | 2.9 | 1169 / 4853 | 52 | 0.00039 | 0.39 |
| `openai:gpt-5.6-terra` | 102 | 100% | **94%** | 88%–97% | 94% 94% 94% | 1.3 | 2.9 | 1061 / 4961 | 47 | 0.00368 | 3.68 |
| `openai:gpt-6-luna` | 102 | 100% | **96%** | 90%–98% | 97% 97% 94% | 1.4 | 2.4 | 1115 / 4907 | 38 | 0.00018 | 0.18 |
| `openai:gpt-6.1-terra` | 102 | 100% | **93%** | 87%–97% | 91% 94% 94% | 1.6 | 2.8 | 1169 / 4853 | 35 | 0.00159 | 1.59 |
| `openai:gpt-6.2-sol` | 102 | 100% | **94%** | 88%–97% | 94% 94% 94% | 1.6 | 2.7 | 1149 / 5189 | 37 | 0.00318 | 3.18 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| acted_when_should_not | 0.000 | 0.000 | 0.000 | 0.000 | 0.020 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| arguments_correct | 0.922 | 0.971 | 0.980 | 0.990 | 0.902 | 0.931 | 0.941 | 0.961 | 0.931 | 0.941 |
| call_was_valid | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.990 | 1.000 | 1.000 | 1.000 | 1.000 |
| decision_correct | 0.941 | 1.000 | 1.000 | 1.000 | 0.912 | 0.990 | 0.990 | 0.990 | 0.961 | 1.000 |
| tool_correct | 0.941 | 1.000 | 1.000 | 1.000 | 0.912 | 0.980 | 0.990 | 0.990 | 0.961 | 1.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| direction-switch | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 |
| food-edit-calories | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| food-eggs | 1/3 | 0/3 | 1/3 | 2/3 | 2/3 | 0/3 | 0/3 | 2/3 | 0/3 | 0/3 |
| musing-step-goal | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| pace-faster | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| remember-injury | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| water-20oz | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 | 0/3 | 0/3 | 0/3 | 0/3 |
| workout-lift | 1/3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| workout-run | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

