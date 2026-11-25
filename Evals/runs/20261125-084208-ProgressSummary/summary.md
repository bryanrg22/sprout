## progressSummary on `progress_summary/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 45 | 100% | **73%** | 58%–87% | 59%–84% | 80% 73% 67% | 1.9 | 2.1 | 1442 / 0 | 329 | 0.00031 | 0.31 |
| `anthropic:claude-sonnet-5` | 45 | 98% | **93%** | 82%–100% | 82%–98% | 87% 100% 93% | 3.9 | 4.5 | 1508 / 0 | 319 | 0.00620 | 6.20 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 15 | -20.0% | -40.0% to -2.2% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| body_2_to_4_sentences | 1.000 | 1.000 |
| headline_3_to_6_words | 1.000 | 0.977 |
| highlights_3_to_8_words | 1.000 | 1.000 |
| highlights_within_schema | 0.978 | 1.000 |
| names_a_given_figure | 1.000 | 1.000 |
| no_banned_phrase | 0.933 | 1.000 |
| no_number_invented | 0.822 | 0.955 |
| states_a_derived_figure | 0.178 | 0.045 |
| states_a_figure_neither_given_nor_derived | 0.000 | 0.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| alex-drifting-down | 2/3 | 3/3 |
| alex-flat | 1/3 | 3/3 |
| alex-gaining-fast | 2/3 | 3/3 |
| sam-flat | 0/3 | 3/3 |
| sam-maintaining | 2/3 | 3/3 |
| sam-no-trend-yet | 2/3 | 3/3 |
| sam-on-track | 1/3 | 3/3 |
| sam-streak-broken | 3/3 | 2/3 |
| sam-ticking-up | 2/3 | 1/3 |

**Errors**

- `anthropic:claude-sonnet-5`: decoding("DecodingError.keyNotFound: Key \'highlights\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"highlights\", intValue: nil) (\"highlights\").")

