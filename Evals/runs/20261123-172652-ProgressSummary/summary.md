## progressSummary on `progress_summary/v1` (15 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 15 | 100% | **73%** | 48%–89% | 73% | 4.2 | 5.0 | 1105 / 0 | 271 | 0.00492 | 4.92 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` |
|---|---|
| body_2_to_4_sentences | 1.000 |
| headline_3_to_6_words | 1.000 |
| highlights_3_to_8_words | 1.000 |
| highlights_within_schema | 1.000 |
| names_a_given_figure | 1.000 |
| no_banned_phrase | 1.000 |
| no_number_invented | 0.733 |
| wrong_person_pronoun | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` |
|---|---|
| alex-drifting-down | 0/1 |
| alex-near-goal | 0/1 |
| sam-flat | 0/1 |
| sam-on-track | 0/1 |

