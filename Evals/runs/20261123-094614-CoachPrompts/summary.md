## coachPrompts on `coach_prompts/v1` (16 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.5 | 10.7 | 1752 / 0 | 60 | 0.00205 | 2.05 |
| `anthropic:claude-haiku-5-5` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 1.0 | 1.1 | 1976 / 0 | 74 | 0.00023 | 0.23 |
| `anthropic:claude-sonnet-5` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 1.7 | 7.4 | 2042 / 0 | 77 | 0.00485 | 4.85 |
| `anthropic:claude-sonnet-5-5` | 48 | 0% | **0%** | 0%–7% | 0% 0% 0% | 0.0 | 0.0 | 0 / 0 | 0 | 0.00000 | 0.00 |
| `openai:gpt-4.1-mini` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 1.5 | 2.1 | 879 / 128 | 32 | 0.00042 | 0.42 |
| `openai:gpt-5.6-luna` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 1.4 | 2.7 | 999 / 0 | 42 | 0.00025 | 0.25 |
| `openai:gpt-5.6-terra` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.3 | 3.1 | 999 / 0 | 121 | 0.00345 | 3.45 |
| `openai:gpt-6-luna` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 1.3 | 1.8 | 999 / 0 | 46 | 0.00012 | 0.12 |
| `openai:gpt-6.1-terra` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.3 | 2.8 | 999 / 0 | 44 | 0.00122 | 1.22 |
| `openai:gpt-6.2-sol` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.0 | 2.5 | 1009 / 0 | 44 | 0.00246 | 2.46 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| chips_at_most_six_words | 0.667 | 0.438 | 0.854 |  | 0.208 | 0.896 | 0.938 | 0.479 | 0.854 | 0.958 |
| count_within_bounds | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| model_count_within_schema | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| nods_to_the_routine | 0.889 | 0.917 | 0.944 |  | 0.833 | 1.000 | 1.000 | 1.000 | 1.000 | 0.972 |
| none_cut_short | 0.979 | 1.000 | 1.000 |  | 0.917 | 1.000 | 1.000 | 0.979 | 1.000 | 1.000 |
| none_dropped_by_the_app | 1.000 | 0.958 | 0.979 |  | 0.854 | 0.896 | 0.875 | 0.938 | 1.000 | 1.000 |
| returned_the_count_asked | 1.000 | 0.958 | 0.979 |  | 0.854 | 0.896 | 0.875 | 0.938 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 |  | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| alex-brand-new | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-lifter-bio-and-notes | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-lifter-no-bio-no-notes | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-no-training-notes-only | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-nothing-logged-today | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-soccer-bio | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-swimmer-maintain | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-brand-new | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-lifter-notes | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-no-training-bio-only | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-nothing-logged-today | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-runner-bio | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-soccer-maintain | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-walker-bio-and-notes | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-walker-no-bio-no-notes | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| unnamed-walker | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-sonnet-5-5`: badResponse("tool_choice: type \"tool\" and \"any\" are not supported for this model.")

