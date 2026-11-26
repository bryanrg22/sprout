## coachTurn on `coach_conversations/v1` (2 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 2 | 100% | **100%** | 100%–100% | 34%–100% | 100% | 1.4 | 1.6 | 1401 / 5876 | 158 | 0.00175 | 1.75 |
| `anthropic:claude-sonnet-5` | 2 | 100% | **100%** | 100%–100% | 34%–100% | 100% | 1.8 | 2.3 | 1398 / 5910 | 114 | 0.03465 | 34.65 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| assistant_messages | 1.000 | 1.000 |
| fallback_shown | 0.000 | 0.000 |
| reply_chars | 235.500 | 184.000 |
| reply_non_empty | 1.000 | 1.000 |
| reply_sentences | 4.000 | 2.500 |
| reply_words | 46.000 | 33.500 |
| tool_applied_count | 0.500 | 0.500 |
| tool_as_expected | 1.000 | 1.000 |
| tool_call_count | 0.500 | 0.500 |
| tool_called | 0.500 | 0.500 |
| tool_calls_dropped_by_app | 0.000 | 0.000 |
| tool_invalid_count | 0.000 | 0.000 |
| tool_proposed | 0.000 | 0.000 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| (none) | | |

