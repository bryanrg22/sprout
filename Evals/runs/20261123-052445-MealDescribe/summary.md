## mealDescribe on `meal_describe/v1` (2 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 2 | 100% | **100%** | 34%–100% | 100% | 1.8 | 1.8 | 1146 / 0 | 366 | 0.00030 | 0.30 |
| `openai:gpt-4.1-mini` | 2 | 100% | **100%** | 34%–100% | 100% | 2.0 | 3.0 | 332 / 0 | 112 | 0.00031 | 0.31 |
| `openai:gpt-6-luna` | 2 | 100% | **100%** | 34%–100% | 100% | 3.0 | 3.1 | 326 / 0 | 131 | 0.00010 | 0.10 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-6-luna` |
|---|---|---|---|
| carbs_abs_error_g | 0.250 | 0.050 | 0.050 |
| confidence_is_valid | 1.000 | 1.000 | 1.000 |
| fat_abs_error_g | 0.550 | 0.350 | 0.000 |
| items_sum_to_total | 1.000 | 1.000 | 1.000 |
| kcal_pct_error | 0.039 | 0.016 | 0.000 |
| kcal_within_20pct | 1.000 | 1.000 | 1.000 |
| protein_abs_error_g | 0.000 | 0.200 | 0.000 |
| range_well_formed | 1.000 | 1.000 | 1.000 |
| truth_in_stated_range | 1.000 | 1.000 | 1.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-6-luna` |
|---|---|---|---|
| (none) | | | |

