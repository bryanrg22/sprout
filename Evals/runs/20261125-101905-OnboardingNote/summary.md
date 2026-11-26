## onboardingNote on `onboarding_note/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 45 | 96% | **96%** | 87%–100% | 85%–99% | 100% 93% 93% | 1.2 | 1.5 | 636 / 0 | 132 | 0.00013 | 0.13 |
| `anthropic:claude-sonnet-5` | 45 | 87% | **87%** | 67%–100% | 74%–94% | 87% 87% 87% | 2.5 | 2.9 | 635 / 0 | 132 | 0.00259 | 2.59 |

**Compared with `anthropic:claude-haiku-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5` | 15 | -8.9% | -24.4% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 |
| name_used_once | 0.975 | 1.000 |
| names_only_the_given_goal | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 |
| two_to_four_sentences | 1.000 | 0.974 |
| used | 0.956 | 0.867 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| alex-lean-gain-note-with-a-figure | 3/3 | 0/3 |
| sam-ambitious-note-with-a-figure | 1/3 | 0/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: the sanitiser discarded the reply
- `anthropic:claude-sonnet-5`: the sanitiser discarded the reply

