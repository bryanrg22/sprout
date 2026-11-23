## checklistPlan on `checklist_plan/v1` (16 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 48 | 100% | **100%** | 93%–100% | 100% 100% 100% | 2.4 | 3.1 | 1889 / 0 | 306 | 0.00342 | 3.42 |
| `anthropic:claude-sonnet-5` | 48 | 71% | **71%** | 57%–82% | 75% 62% 75% | 3.5 | 4.0 | 2236 / 0 | 365 | 0.00812 | 8.12 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-sonnet-5` |
|---|---|---|
| chips_within_schema | 1.000 | 1.000 |
| icons_known_share | 0.865 | 0.939 |
| no_number_outside_the_data | 0.938 | 1.000 |
| none_cut_short | 0.979 | 1.000 |
| none_dropped_by_the_app | 1.000 | 0.765 |
| reflects_the_routine | 1.000 | 1.000 |
| tasks_within_schema | 1.000 | 1.000 |
| titles_at_most_four_words | 0.917 | 0.824 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-sonnet-5` |
|---|---|---|
| alex-lifter-bio-and-notes | 3/3 | 0/3 |
| alex-nothing-logged-today | 3/3 | 2/3 |
| alex-soccer-bio | 3/3 | 0/3 |
| sam-lifter-notes | 3/3 | 0/3 |
| sam-runner-bio | 3/3 | 0/3 |
| sam-walker-no-bio-no-notes | 3/3 | 2/3 |

**Errors**

- `anthropic:claude-sonnet-5`: decoding("DecodingError.keyNotFound: Key \'chips\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"chips\", intValue: nil) (\"chips\").")
- `anthropic:claude-sonnet-5`: decoding("DecodingError.keyNotFound: Key \'tasks\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"tasks\", intValue: nil) (\"tasks\").")

