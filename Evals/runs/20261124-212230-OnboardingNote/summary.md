## onboardingNote on `onboarding_note/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 75 | 95% | **95%** | 84%–100% | 87%–98% | 93% 100% 93% 93% 93% | 1.6 | 1.9 | 458 / 0 | 90 | 0.00091 | 0.91 |
| `anthropic:claude-haiku-5-5` | 75 | 97% | **97%** | 92%–100% | 91%–99% | 100% 93% 93% 100% 100% | 1.2 | 1.4 | 636 / 0 | 130 | 0.00013 | 0.13 |

**Compared with `anthropic:claude-haiku-4-5-20251001` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 15 | +2.7% | +0.0% to +8.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 |
| name_used_once | 0.773 | 0.985 |
| names_only_the_given_goal | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| two_to_four_sentences | 0.986 | 0.986 |
| used | 0.947 | 0.973 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` |
|---|---|---|
| sam-ambitious-note-with-a-figure | 1/5 | 3/5 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: the sanitiser discarded the reply
- `anthropic:claude-haiku-5-5`: the sanitiser discarded the reply

