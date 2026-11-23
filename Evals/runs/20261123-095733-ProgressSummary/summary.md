## progressSummary on `progress_summary/v1` (15 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 45 | 91% | **24%** | 14%–39% | 27% 20% 27% | 2.8 | 3.3 | 1325 / 0 | 229 | 0.00247 | 2.47 |
| `anthropic:claude-sonnet-5` | 45 | 98% | **58%** | 43%–71% | 60% 53% 60% | 3.9 | 4.6 | 1459 / 0 | 316 | 0.00607 | 6.07 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-sonnet-5` |
|---|---|---|
| body_2_to_4_sentences | 0.902 | 1.000 |
| headline_3_to_6_words | 0.951 | 0.955 |
| highlights_3_to_8_words | 1.000 | 1.000 |
| highlights_within_schema | 1.000 | 1.000 |
| names_a_given_figure | 1.000 | 1.000 |
| no_banned_phrase | 0.951 | 1.000 |
| no_number_invented | 0.268 | 0.591 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-sonnet-5` |
|---|---|---|
| alex-drifting-down | 0/3 | 0/3 |
| alex-flat | 0/3 | 0/3 |
| alex-gaining-fast | 0/3 | 3/3 |
| alex-near-goal | 1/3 | 3/3 |
| alex-no-trend-yet | 2/3 | 3/3 |
| alex-on-track | 1/3 | 3/3 |
| alex-weight-only | 1/3 | 0/3 |
| sam-dropping-fast | 0/3 | 2/3 |
| sam-flat | 0/3 | 1/3 |
| sam-maintaining | 0/3 | 3/3 |
| sam-no-trend-yet | 2/3 | 3/3 |
| sam-on-track | 2/3 | 2/3 |
| sam-streak-broken | 0/3 | 3/3 |
| sam-ticking-up | 0/3 | 0/3 |
| sam-weight-only | 2/3 | 0/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: decoding("DecodingError.typeMismatch: expected value of type Array<Any>. Path: highlights. Debug description: Expected to decode Array<Any> but found a string instead.")
- `anthropic:claude-sonnet-5`: decoding("DecodingError.keyNotFound: Key \'highlights\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"highlights\", intValue: nil) (\"highlights\").")

