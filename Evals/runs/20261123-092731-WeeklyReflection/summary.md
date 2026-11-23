## weeklyReflection on `weekly_reflection/v1` (16 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 48 | 94% | **92%** | 80%–97% | 94% 94% 88% | 2.2 | 3.0 | 754 / 0 | 147 | 0.00149 | 1.49 |
| `anthropic:claude-haiku-5-5` | 48 | 85% | **85%** | 73%–93% | 81% 81% 94% | 1.6 | 2.8 | 1047 / 0 | 255 | 0.00023 | 0.23 |
| `anthropic:claude-sonnet-5` | 48 | 94% | **92%** | 80%–97% | 88% 94% 94% | 3.3 | 4.0 | 1045 / 0 | 204 | 0.00413 | 4.13 |
| `anthropic:claude-sonnet-5-5` | 48 | 73% | **69%** | 55%–80% | 69% 56% 81% | 2.7 | 3.8 | 1047 / 0 | 225 | 0.00434 | 4.34 |
| `openai:gpt-4.1-mini` | 48 | 96% | **96%** | 86%–99% | 94% 94% 100% | 1.9 | 2.6 | 687 / 0 | 120 | 0.00047 | 0.47 |
| `openai:gpt-5.6-luna` | 48 | 94% | **94%** | 83%–98% | 94% 94% 94% | 2.0 | 2.4 | 686 / 0 | 112 | 0.00027 | 0.27 |
| `openai:gpt-5.6-terra` | 48 | 73% | **73%** | 59%–83% | 75% 75% 69% | 2.6 | 3.0 | 686 / 0 | 111 | 0.00270 | 2.70 |
| `openai:gpt-6-luna` | 48 | 98% | **98%** | 89%–100% | 100% 100% 94% | 2.0 | 2.7 | 686 / 0 | 115 | 0.00013 | 0.13 |
| `openai:gpt-6.1-terra` | 48 | 94% | **92%** | 80%–97% | 88% 94% 94% | 2.8 | 6.1 | 686 / 0 | 106 | 0.00122 | 1.22 |
| `openai:gpt-6.2-sol` | 48 | 94% | **94%** | 83%–98% | 94% 94% 94% | 3.4 | 4.3 | 686 / 0 | 114 | 0.00251 | 2.51 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| name_used_once | 0.978 | 1.000 | 0.956 | 1.000 | 0.978 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 0.978 | 1.000 | 0.978 | 0.943 | 1.000 | 1.000 | 1.000 | 1.000 | 0.978 | 1.000 |
| repeats_a_given_count | 0.897 | 1.000 | 0.923 | 1.000 | 0.675 | 1.000 | 0.897 | 1.000 | 1.000 | 1.000 |
| three_to_five_sentences | 0.933 | 0.878 | 0.600 | 0.914 | 0.957 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 0.938 | 0.854 | 0.938 | 0.729 | 0.958 | 0.938 | 0.729 | 0.979 | 0.938 | 0.938 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| alex-climbing-consistent | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 |
| alex-dropped-fast | 0/3 | 2/3 | 0/3 | 0/3 | 1/3 | 2/3 | 0/3 | 3/3 | 0/3 | 0/3 |
| alex-eased-down | 3/3 | 2/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-fresh-page | 2/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 |
| alex-maintain-eased-down | 3/3 | 1/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-plateau | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-dropping-fast | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 0/3 | 3/3 | 3/3 | 3/3 |
| sam-easing-down-consistent | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 2/3 | 3/3 | 3/3 |
| sam-maintain-steady | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 |
| sam-plateau | 3/3 | 2/3 | 3/3 | 1/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 |
| sam-quiet-week | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-ticked-up | 3/3 | 1/3 | 3/3 | 0/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: the sanitiser discarded the reply
- `anthropic:claude-haiku-5-5`: the call failed
- `anthropic:claude-sonnet-5`: the sanitiser discarded the reply
- `anthropic:claude-sonnet-5-5`: the sanitiser discarded the reply
- `openai:gpt-4.1-mini`: the sanitiser discarded the reply
- `openai:gpt-5.6-luna`: the sanitiser discarded the reply
- `openai:gpt-5.6-terra`: the sanitiser discarded the reply
- `openai:gpt-6-luna`: the sanitiser discarded the reply
- `openai:gpt-6.1-terra`: the sanitiser discarded the reply
- `openai:gpt-6.2-sol`: the sanitiser discarded the reply

