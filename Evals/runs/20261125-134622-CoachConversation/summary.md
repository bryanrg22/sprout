## coachTurn on `coach_conversations/v1` (30 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 90 | 100% | **100%** | 100%–100% | 96%–100% | 100% 100% 100% | 2.5 | 4.1 | 1175 / 13166 | 366 | 0.00053 | 0.53 |
| `openai:gpt-6-luna` | 90 | 100% | **100%** | 100%–100% | 96%–100% | 100% 100% 100% | 1.9 | 3.3 | 2051 / 6134 | 79 | 0.00031 | 0.31 |

**Compared with `anthropic:claude-haiku-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6-luna` | 30 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `openai:gpt-6-luna` |
|---|---|---|
| assistant_messages | 0.956 | 0.933 |
| fallback_shown | 0.000 | 0.000 |
| reply_chars | 433.811 | 253.567 |
| reply_non_empty | 0.933 | 0.933 |
| reply_sentences | 6.644 | 2.611 |
| reply_words | 79.500 | 43.844 |
| tool_applied_count | 0.189 | 0.167 |
| tool_as_expected | 1.000 | 1.000 |
| tool_call_count | 0.256 | 0.233 |
| tool_called | 0.244 | 0.233 |
| tool_calls_dropped_by_app | 0.011 | 0.000 |
| tool_invalid_count | 0.000 | 0.000 |
| tool_proposed | 0.067 | 0.067 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `openai:gpt-6-luna` |
|---|---|---|
| (none) | | |

