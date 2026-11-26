## onboardingNote on `onboarding_note/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 45 | 96% | **96%** | 87%–100% | 85%–99% | 93% 93% 100% | 1.3 | 2.3 | 636 / 0 | 133 | 0.00013 | 0.13 |
| `openai:gpt-6-luna` | 45 | 100% | **100%** | 100%–100% | 92%–100% | 100% 100% 100% | 1.4 | 2.3 | 418 / 0 | 64 | 0.00007 | 0.07 |

**Compared with `anthropic:claude-haiku-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6-luna` | 15 | +4.4% | +0.0% to +13.3% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `openai:gpt-6-luna` |
|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 |
| name_used_once | 1.000 | 1.000 |
| names_only_the_given_goal | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| two_to_four_sentences | 0.953 | 1.000 |
| used | 0.956 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `openai:gpt-6-luna` |
|---|---|---|
| sam-ambitious-note-with-a-figure | 1/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: the sanitiser discarded the reply

