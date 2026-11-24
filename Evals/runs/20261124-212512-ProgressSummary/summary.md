## progressSummary on `progress_summary/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 75 | 100% | **80%** | 67%–91% | 70%–87% | 87% 80% 67% 80% 87% | 1.8 | 2.0 | 1442 / 0 | 327 | 0.00031 | 0.31 |
| `anthropic:claude-sonnet-5` | 75 | 96% | **88%** | 79%–96% | 79%–94% | 100% 80% 93% 87% 80% | 3.9 | 4.8 | 1508 / 0 | 320 | 0.00622 | 6.22 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 15 | -8.0% | -17.3% to +1.3% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| body_2_to_4_sentences | 1.000 | 1.000 |
| headline_3_to_6_words | 1.000 | 0.972 |
| highlights_3_to_8_words | 0.987 | 0.986 |
| highlights_within_schema | 0.973 | 1.000 |
| names_a_given_figure | 1.000 | 1.000 |
| no_banned_phrase | 0.960 | 0.986 |
| no_number_invented | 0.853 | 0.931 |
| states_a_derived_figure | 0.147 | 0.069 |
| states_a_figure_neither_given_nor_derived | 0.000 | 0.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| alex-flat | 3/5 | 4/5 |
| alex-near-goal | 4/5 | 5/5 |
| alex-on-track | 4/5 | 4/5 |
| sam-dropping-fast | 5/5 | 4/5 |
| sam-flat | 2/5 | 2/5 |
| sam-maintaining | 3/5 | 5/5 |
| sam-no-trend-yet | 4/5 | 5/5 |
| sam-on-track | 1/5 | 3/5 |
| sam-ticking-up | 4/5 | 5/5 |
| sam-weight-only | 5/5 | 4/5 |

**Errors**

- `anthropic:claude-sonnet-5`: decoding("DecodingError.typeMismatch: expected value of type Array<Any>. Path: highlights. Debug description: Expected to decode Array<Any> but found a string instead.")

