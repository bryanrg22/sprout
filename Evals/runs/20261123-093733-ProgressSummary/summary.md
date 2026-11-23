## progressSummary on `progress_summary/v1` (15 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 45 | 87% | **33%** | 21%–48% | 33% 20% 47% | 2.8 | 3.5 | 1325 / 0 | 230 | 0.00248 | 2.48 |
| `anthropic:claude-haiku-5-5` | 45 | 100% | **73%** | 59%–84% | 80% 67% 73% | 1.8 | 2.2 | 1393 / 0 | 333 | 0.00031 | 0.31 |
| `anthropic:claude-sonnet-5` | 45 | 96% | **64%** | 50%–77% | 40% 73% 80% | 3.9 | 4.9 | 1459 / 0 | 321 | 0.00612 | 6.12 |
| `anthropic:claude-sonnet-5-5` | 45 | 0% | **0%** | 0%–8% | 0% 0% 0% | 0.0 | 0.0 | 0 / 0 | 0 | 0.00000 | 0.00 |
| `openai:gpt-4.1-mini` | 45 | 100% | **82%** | 69%–91% | 87% 67% 93% | 5.0 | 5.3 | 628 / 0 | 148 | 0.00049 | 0.49 |
| `openai:gpt-5.6-luna` | 45 | 100% | **96%** | 85%–99% | 93% 100% 93% | 2.7 | 3.3 | 622 / 0 | 177 | 0.00034 | 0.34 |
| `openai:gpt-5.6-terra` | 45 | 100% | **89%** | 77%–95% | 80% 93% 93% | 3.6 | 5.4 | 622 / 0 | 213 | 0.00380 | 3.80 |
| `openai:gpt-6-luna` | 45 | 100% | **93%** | 82%–98% | 93% 93% 93% | 2.7 | 3.5 | 622 / 0 | 164 | 0.00014 | 0.14 |
| `openai:gpt-6.1-terra` | 45 | 100% | **93%** | 82%–98% | 93% 87% 100% | 3.8 | 4.4 | 622 / 0 | 151 | 0.00138 | 1.38 |
| `openai:gpt-6.2-sol` | 45 | 100% | **62%** | 48%–75% | 53% 53% 80% | 3.9 | 4.7 | 632 / 0 | 161 | 0.00287 | 2.87 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| body_2_to_4_sentences | 0.949 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| headline_3_to_6_words | 0.949 | 0.978 | 0.977 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| highlights_3_to_8_words | 1.000 | 0.978 | 1.000 |  | 1.000 | 1.000 | 0.978 | 1.000 | 1.000 | 1.000 |
| highlights_within_schema | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| names_a_given_figure | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_banned_phrase | 1.000 | 0.956 | 0.907 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| no_number_invented | 0.385 | 0.778 | 0.744 |  | 0.822 | 0.956 | 0.889 | 0.933 | 0.933 | 0.622 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 |  | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| alex-drifting-down | 0/3 | 0/3 | 0/3 | 0/3 | 3/3 | 2/3 | 2/3 | 3/3 | 3/3 | 0/3 |
| alex-flat | 0/3 | 1/3 | 1/3 | 0/3 | 1/3 | 3/3 | 2/3 | 2/3 | 2/3 | 0/3 |
| alex-gaining-fast | 0/3 | 3/3 | 2/3 | 0/3 | 1/3 | 2/3 | 3/3 | 3/3 | 3/3 | 2/3 |
| alex-near-goal | 0/3 | 3/3 | 2/3 | 0/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-no-trend-yet | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-on-track | 1/3 | 2/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| alex-weight-only | 3/3 | 3/3 | 0/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-dropping-fast | 0/3 | 1/3 | 1/3 | 0/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-flat | 1/3 | 1/3 | 1/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 1/3 |
| sam-maintaining | 1/3 | 3/3 | 2/3 | 0/3 | 3/3 | 3/3 | 1/3 | 1/3 | 1/3 | 1/3 |
| sam-no-trend-yet | 2/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 0/3 |
| sam-on-track | 0/3 | 2/3 | 3/3 | 0/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 1/3 |
| sam-streak-broken | 1/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 |
| sam-ticking-up | 0/3 | 2/3 | 3/3 | 0/3 | 1/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| sam-weight-only | 3/3 | 3/3 | 2/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: decoding("DecodingError.keyNotFound: Key \'highlights\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"highlights\", intValue: nil) (\"highlights\").")
- `anthropic:claude-haiku-4-5-20251001`: decoding("DecodingError.typeMismatch: expected value of type Array<Any>. Path: highlights. Debug description: Expected to decode Array<Any> but found a string instead.")
- `anthropic:claude-sonnet-5`: decoding("DecodingError.keyNotFound: Key \'highlights\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"highlights\", intValue: nil) (\"highlights\").")
- `anthropic:claude-sonnet-5`: decoding("DecodingError.typeMismatch: expected value of type Array<Any>. Path: highlights. Debug description: Expected to decode Array<Any> but found a string instead.")
- `anthropic:claude-sonnet-5-5`: badResponse("tool_choice: type \"tool\" and \"any\" are not supported for this model.")

