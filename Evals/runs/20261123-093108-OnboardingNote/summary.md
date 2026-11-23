## onboardingNote on `onboarding_note/v1` (15 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 45 | 96% | **96%** | 85%–99% | 100% 93% 93% | 1.5 | 1.9 | 458 / 0 | 88 | 0.00090 | 0.90 |
| `anthropic:claude-haiku-5-5` | 45 | 91% | **89%** | 77%–95% | 100% 80% 87% | 1.2 | 1.5 | 637 / 0 | 135 | 0.00013 | 0.13 |
| `anthropic:claude-sonnet-5` | 45 | 89% | **89%** | 77%–95% | 87% 93% 87% | 2.3 | 2.7 | 635 / 0 | 127 | 0.00254 | 2.54 |
| `anthropic:claude-sonnet-5-5` | 45 | 76% | **76%** | 61%–86% | 80% 73% 73% | 2.4 | 3.5 | 637 / 0 | 187 | 0.00315 | 3.15 |
| `openai:gpt-4.1-mini` | 45 | 100% | **100%** | 92%–100% | 100% 100% 100% | 1.5 | 2.2 | 419 / 0 | 78 | 0.00029 | 0.29 |
| `openai:gpt-5.6-luna` | 45 | 98% | **98%** | 88%–100% | 93% 100% 100% | 1.8 | 2.2 | 418 / 0 | 68 | 0.00016 | 0.16 |
| `openai:gpt-5.6-terra` | 45 | 96% | **96%** | 85%–99% | 93% 93% 100% | 1.7 | 2.1 | 418 / 0 | 71 | 0.00169 | 1.69 |
| `openai:gpt-6-luna` | 45 | 100% | **100%** | 92%–100% | 100% 100% 100% | 1.6 | 2.3 | 418 / 0 | 64 | 0.00007 | 0.07 |
| `openai:gpt-6.1-terra` | 45 | 100% | **100%** | 92%–100% | 100% 100% 100% | 2.4 | 3.1 | 418 / 0 | 62 | 0.00073 | 0.73 |
| `openai:gpt-6.2-sol` | 45 | 100% | **100%** | 92%–100% | 100% 100% 100% | 2.5 | 3.0 | 418 / 0 | 60 | 0.00144 | 1.44 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| name_used_once | 0.850 | 1.000 | 1.000 | 1.000 | 0.976 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| names_only_the_given_goal | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 1.000 | 0.976 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| two_to_four_sentences | 1.000 | 0.902 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| used | 0.956 | 0.911 | 0.889 | 0.756 | 1.000 | 0.978 | 0.956 | 1.000 | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| alex-lean-gain-note | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-lean-gain-note-with-a-figure | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-steady-gain-note | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-ambitious-no-note | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-ambitious-note-with-a-figure | 1/3 | 1/3 | 0/3 | 3/3 | 3/3 | 2/3 | 1/3 | 3/3 | 3/3 | 3/3 |
| sam-relaxed-no-note | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-steady-note | 3/3 | 3/3 | 3/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| unnamed-relaxed-note | 3/3 | 1/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: the sanitiser discarded the reply
- `anthropic:claude-haiku-5-5`: the call failed
- `anthropic:claude-haiku-5-5`: the sanitiser discarded the reply
- `anthropic:claude-sonnet-5`: the sanitiser discarded the reply
- `anthropic:claude-sonnet-5-5`: the call failed
- `openai:gpt-5.6-luna`: the sanitiser discarded the reply
- `openai:gpt-5.6-terra`: the sanitiser discarded the reply

