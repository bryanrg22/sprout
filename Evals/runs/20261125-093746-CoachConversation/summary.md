## coachTurn on `coach_conversations/v1` (30 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 90 | 100% | **100%** | 100%–100% | 96%–100% | 100% 100% 100% | 2.4 | 3.8 | 1171 / 13687 | 359 | 0.00047 | 0.47 |
| `anthropic:claude-sonnet-5` | 90 | 100% | **100%** | 100%–100% | 96%–100% | 100% 100% 100% | 4.3 | 6.9 | 1160 / 13770 | 280 | 0.00852 | 8.52 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 30 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| assistant_messages | 0.933 | 0.989 |
| fallback_shown | 0.000 | 0.000 |
| reply_chars | 437.111 | 465.067 |
| reply_non_empty | 0.933 | 0.933 |
| reply_sentences | 6.544 | 5.611 |
| reply_words | 80.144 | 79.456 |
| tool_applied_count | 0.189 | 0.178 |
| tool_as_expected | 1.000 | 0.986 |
| tool_call_count | 0.256 | 0.256 |
| tool_called | 0.256 | 0.256 |
| tool_calls_dropped_by_app | 0.000 | 0.000 |
| tool_invalid_count | 0.000 | 0.011 |
| tool_proposed | 0.067 | 0.067 |
| used | 1.000 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| (none) | | |

