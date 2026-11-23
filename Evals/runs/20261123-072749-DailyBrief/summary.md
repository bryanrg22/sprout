## dailyBrief on `daily_brief/v1` (13 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 39 | 100% | **100%** | 91%–100% | 100% 100% 100% | 1.0 | 1.3 | 271 / 0 | 54 | 0.00054 | 0.54 |
| `anthropic:claude-haiku-5-5` | 39 | 92% | **92%** | 80%–97% | 92% 92% 92% | 0.8 | 0.9 | 380 / 0 | 67 | 0.00007 | 0.07 |
| `openai:gpt-4.1-mini` | 39 | 87% | **82%** | 67%–91% | 85% 85% 77% | 1.2 | 1.5 | 251 / 0 | 43 | 0.00017 | 0.17 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `openai:gpt-4.1-mini` |
|---|---|---|---|
| all_numbers_kept | 1.000 | 1.000 | 1.000 |
| body_at_most_two_sentences | 0.256 | 0.583 | 0.353 |
| changed_the_wording | 0.949 | 1.000 | 1.000 |
| headline_at_most_one_number | 1.000 | 0.917 | 0.794 |
| headline_one_sentence | 0.897 | 0.944 | 1.000 |
| no_number_invented | 1.000 | 1.000 | 0.941 |
| used | 1.000 | 0.923 | 0.872 |
| wrong_person_pronoun | 0.000 | 0.000 | 0.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `openai:gpt-4.1-mini` |
|---|---|---|---|
| quiet-day-hr | 3/3 | 3/3 | 2/3 |
| quiet-day-plain | 3/3 | 3/3 | 1/3 |
| streak-14 | 3/3 | 3/3 | 1/3 |
| travel-day0-east | 3/3 | 3/3 | 1/3 |
| trend-eased | 3/3 | 0/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: guardrail discarded the rewrite: no body after the headline
- `openai:gpt-4.1-mini`: guardrail discarded the rewrite: no body after the headline

