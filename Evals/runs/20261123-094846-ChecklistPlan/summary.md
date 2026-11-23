## checklistPlan on `checklist_plan/v1` (16 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 48 | 85% | **85%** | 73%–93% | 88% 81% 88% | 8.4 | 20.2 | 1624 / 0 | 252 | 0.00288 | 2.88 |
| `anthropic:claude-haiku-5-5` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 1.9 | 2.1 | 2170 / 0 | 359 | 0.00040 | 0.40 |
| `anthropic:claude-sonnet-5` | 48 | 71% | **71%** | 57%–82% | 62% 75% 75% | 3.7 | 4.8 | 2236 / 0 | 367 | 0.00814 | 8.14 |
| `anthropic:claude-sonnet-5-5` | 48 | 0% | **0%** | 0%–7% | 0% 0% 0% | 0.0 | 0.0 | 0 / 0 | 0 | 0.00000 | 0.00 |
| `openai:gpt-4.1-mini` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.1 | 2.4 | 646 / 427 | 143 | 0.00053 | 0.53 |
| `openai:gpt-5.6-luna` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.2 | 2.6 | 1066 / 0 | 144 | 0.00039 | 0.39 |
| `openai:gpt-5.6-terra` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.7 | 3.8 | 1066 / 0 | 202 | 0.00456 | 4.56 |
| `openai:gpt-6-luna` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.0 | 2.7 | 1066 / 0 | 141 | 0.00018 | 0.18 |
| `openai:gpt-6.1-terra` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.9 | 4.1 | 1066 / 0 | 126 | 0.00170 | 1.70 |
| `openai:gpt-6.2-sol` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 3.1 | 4.6 | 1099 / 0 | 124 | 0.00344 | 3.44 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| chips_within_schema | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| icons_known_share | 0.884 | 0.932 | 0.930 |  | 0.819 | 0.972 | 0.962 | 0.968 | 0.982 | 0.963 |
| no_number_outside_the_data | 0.951 | 0.729 | 0.941 |  | 0.771 | 0.917 | 0.917 | 1.000 | 1.000 | 1.000 |
| none_cut_short | 1.000 | 0.812 | 0.971 |  | 0.979 | 0.979 | 1.000 | 1.000 | 0.979 | 0.979 |
| none_dropped_by_the_app | 0.976 | 0.833 | 0.735 |  | 0.812 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| reflects_the_routine | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| tasks_within_schema | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| titles_at_most_four_words | 0.854 | 0.104 | 0.941 |  | 0.896 | 0.958 | 1.000 | 0.938 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 |  | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| alex-brand-new | 3/3 | 3/3 | 2/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-lifter-bio-and-notes | 3/3 | 3/3 | 0/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-lifter-no-bio-no-notes | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-no-training-notes-only | 3/3 | 3/3 | 2/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-nothing-logged-today | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-soccer-bio | 3/3 | 3/3 | 0/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-swimmer-maintain | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-brand-new | 1/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-lifter-notes | 3/3 | 3/3 | 0/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-no-training-bio-only | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-nothing-logged-today | 1/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-runner-bio | 3/3 | 3/3 | 1/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-soccer-maintain | 1/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-walker-bio-and-notes | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-walker-no-bio-no-notes | 3/3 | 3/3 | 2/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| unnamed-walker | 2/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: badResponse("Overloaded")
- `anthropic:claude-sonnet-5`: decoding("DecodingError.typeMismatch: expected value of type Array<Any>. Path: tasks. Debug description: Expected to decode Array<Any> but found a string instead.")
- `anthropic:claude-sonnet-5-5`: badResponse("tool_choice: type \"tool\" and \"any\" are not supported for this model.")

