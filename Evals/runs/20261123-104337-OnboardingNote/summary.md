## onboardingNote on `onboarding_note/v1` (15 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 45 | 93% | **93%** | 82%–98% | 93% 93% 93% | 1.6 | 1.9 | 458 / 0 | 89 | 0.00090 | 0.90 |
| `anthropic:claude-haiku-5-5` | 45 | 98% | **98%** | 88%–100% | 100% 100% 93% | 1.2 | 1.5 | 636 / 0 | 129 | 0.00013 | 0.13 |
| `anthropic:claude-sonnet-5` | 45 | 87% | **84%** | 71%–92% | 87% 87% 80% | 2.5 | 2.9 | 635 / 0 | 132 | 0.00259 | 2.59 |
| `anthropic:claude-sonnet-5-5` | 45 | 100% | **100%** | 92%–100% | 100% 100% 100% | 2.2 | 4.3 | 636 / 0 | 139 | 0.00266 | 2.66 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| at_most_one_emoji | 1.000 | 1.000 | 1.000 | 1.000 |
| name_used_once | 0.872 | 1.000 | 1.000 | 0.976 |
| names_only_the_given_goal | 1.000 | 1.000 | 1.000 | 1.000 |
| no_list_or_header | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 0.974 | 1.000 |
| two_to_four_sentences | 1.000 | 0.955 | 0.974 | 0.778 |
| used | 0.933 | 0.978 | 0.867 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|---|
| alex-lean-gain-note-with-a-figure | 3/3 | 3/3 | 0/3 | 3/3 |
| sam-ambitious-note-with-a-figure | 0/3 | 2/3 | 0/3 | 3/3 |
| unnamed-relaxed-note | 3/3 | 3/3 | 2/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: the sanitiser discarded the reply
- `anthropic:claude-haiku-5-5`: the sanitiser discarded the reply
- `anthropic:claude-sonnet-5`: the sanitiser discarded the reply

