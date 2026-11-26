## progressSummary on `progress_summary/v1` (15 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 45 | 100% | **93%** | 87%–100% | 82%–98% | 93% 93% 93% | 3.8 | 4.8 | 1508 / 0 | 318 | 0.00620 | 6.20 |
| `openai:gpt-6.2-sol` | 45 | 100% | **100%** | 100%–100% | 92%–100% | 100% 100% 100% | 3.3 | 4.3 | 670 / 0 | 150 | 0.00284 | 2.84 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 15 | +6.7% | +0.0% to +13.3% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| body_2_to_4_sentences | 0.978 | 1.000 |
| headline_3_to_6_words | 0.978 | 1.000 |
| highlights_3_to_8_words | 1.000 | 1.000 |
| highlights_within_schema | 1.000 | 1.000 |
| names_a_given_figure | 1.000 | 1.000 |
| no_banned_phrase | 0.978 | 1.000 |
| no_number_invented | 0.956 | 1.000 |
| states_a_derived_figure | 0.044 | 0.000 |
| states_a_figure_neither_given_nor_derived | 0.000 | 0.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| sam-flat | 2/3 | 3/3 |
| sam-on-track | 2/3 | 3/3 |
| sam-ticking-up | 2/3 | 3/3 |

