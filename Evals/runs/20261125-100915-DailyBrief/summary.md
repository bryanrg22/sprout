## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 39 | 97% | **97%** | 92%–100% | 87%–100% | 100% 100% 92% | 0.8 | 1.2 | 379 / 0 | 70 | 0.00007 | 0.07 |
| `anthropic:claude-sonnet-5` | 39 | 100% | **100%** | 100%–100% | 91%–100% | 100% 100% 100% | 1.3 | 1.7 | 378 / 0 | 62 | 0.00138 | 1.38 |

**Compared with `anthropic:claude-haiku-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5` | 13 | +2.6% | +0.0% to +7.7% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| all_numbers_kept | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.553 | 0.974 |
| changed_the_wording | 1.000 | 1.000 |
| headline_at_most_one_number | 0.974 | 1.000 |
| headline_one_sentence | 0.553 | 0.923 |
| no_number_invented | 1.000 | 1.000 |
| used | 0.974 | 1.000 |
| wrong_person_pronoun | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| quiet-day-plain | 2/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: guardrail discarded the rewrite: contains "make up for"

