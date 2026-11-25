## onboardingNote on `onboarding_note/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 45 | 96% | **96%** | 87%–100% | 85%–99% | 93% 100% 93% | 1.5 | 1.9 | 458 / 0 | 89 | 0.00090 | 0.90 |
| `anthropic:claude-haiku-5-5` | 45 | 98% | **98%** | 93%–100% | 88%–100% | 100% 93% 100% | 1.2 | 1.7 | 636 / 0 | 129 | 0.00013 | 0.13 |

**Compared with `anthropic:claude-haiku-4-5-20251001` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 15 | +2.2% | +0.0% to +6.7% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 |
| name_used_once | 0.900 | 1.000 |
| names_only_the_given_goal | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| two_to_four_sentences | 0.953 | 0.977 |
| used | 0.956 | 0.978 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| sam-ambitious-note-with-a-figure | 1/3 | 2/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: the sanitiser discarded the reply
- `anthropic:claude-haiku-5-5`: the sanitiser discarded the reply

