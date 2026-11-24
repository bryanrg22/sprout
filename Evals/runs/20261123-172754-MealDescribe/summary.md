## mealDescribe on `meal_describe/v1` (14 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 14 | 100% | **100%** | 78%–100% | 100% | 4.5 | 5.5 | 1492 / 0 | 285 | 0.00584 | 5.84 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` |
|---|---|
| carbs_abs_error_g | 0.557 |
| confidence_is_valid | 1.000 |
| fat_abs_error_g | 0.443 |
| items_sum_to_total | 0.857 |
| kcal_pct_error | 0.029 |
| kcal_within_20pct | 1.000 |
| protein_abs_error_g | 0.771 |
| range_well_formed | 1.000 |
| truth_in_stated_range | 0.929 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` |
|---|---|
| (none) | |

