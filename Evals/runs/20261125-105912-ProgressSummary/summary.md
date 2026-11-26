## progressSummary on `progress_summary/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 45 | 93% | **91%** | 84%–98% | 79%–96% | 80% 100% 93% | 3.8 | 4.5 | 1508 / 0 | 318 | 0.00619 | 6.19 |
| `anthropic:claude-sonnet-5-5` | 45 | 100% | **87%** | 76%–96% | 74%–94% | 100% 73% 87% | 3.8 | 6.6 | 1154 / 0 | 277 | 0.00508 | 5.08 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 15 | -4.4% | -17.8% to +8.9% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| body_2_to_4_sentences | 1.000 | 0.956 |
| headline_3_to_6_words | 1.000 | 1.000 |
| highlights_3_to_8_words | 1.000 | 1.000 |
| highlights_within_schema | 1.000 | 1.000 |
| names_a_given_figure | 1.000 | 1.000 |
| no_banned_phrase | 1.000 | 0.933 |
| no_number_invented | 0.976 | 0.933 |
| states_a_derived_figure | 0.024 | 0.067 |
| states_a_figure_neither_given_nor_derived | 0.000 | 0.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| alex-drifting-down | 2/3 | 3/3 |
| alex-gaining-fast | 3/3 | 2/3 |
| alex-on-track | 3/3 | 2/3 |
| sam-flat | 2/3 | 2/3 |
| sam-maintaining | 3/3 | 2/3 |
| sam-no-trend-yet | 2/3 | 3/3 |
| sam-on-track | 3/3 | 1/3 |
| sam-ticking-up | 2/3 | 3/3 |

**Errors**

- `anthropic:claude-sonnet-5`: decoding("DecodingError.keyNotFound: Key \'highlights\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"highlights\", intValue: nil) (\"highlights\").")
- `anthropic:claude-sonnet-5`: decoding("DecodingError.typeMismatch: expected value of type Array<Any>. Path: highlights. Debug description: Expected to decode Array<Any> but found a string instead.")

