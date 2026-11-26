## mealPhoto on `meal_photo/v1` (1 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `openai:gpt-6.2-sol` | 1 | 100% | **100%** | 100%–100% | 21%–100% | 100% | 7.1 | 7.1 | 1051 / 0 | 351 | 0.00561 | 5.61 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `openai:gpt-6.2-sol` |
|---|---|
| carbs_abs_error_g | 1.300 |
| confidence_is_valid | 1.000 |
| fat_abs_error_g | 4.900 |
| items_sum_to_total | 1.000 |
| kcal_pct_error | 0.140 |
| kcal_within_20pct | 1.000 |
| protein_abs_error_g | 0.700 |
| range_well_formed | 1.000 |
| truth_in_stated_range | 1.000 |

**Cases not passed every time** (passes / attempts)

| case | `openai:gpt-6.2-sol` |
|---|---|
| (none) | |

