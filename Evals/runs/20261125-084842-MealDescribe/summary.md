## mealDescribe on `meal_describe/v3` (14 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 42 | 100% | **100%** | 100%–100% | 92%–100% | 100% 100% 100% | 1.9 | 2.5 | 1591 / 0 | 519 | 0.00042 | 0.42 |
| `anthropic:claude-sonnet-5` | 42 | 100% | **100%** | 100%–100% | 92%–100% | 100% 100% 100% | 3.9 | 5.1 | 1657 / 0 | 493 | 0.00824 | 8.24 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 14 | +0.0% | +0.0% to +0.0% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| carbs_abs_error_g | 0.314 | 0.226 |
| confidence_is_valid | 1.000 | 1.000 |
| fat_abs_error_g | 0.281 | 0.226 |
| fiber_g_abs_error | 0.331 | 0.155 |
| fiber_g_answered | 1.000 | 1.000 |
| items_sum_to_total | 1.000 | 1.000 |
| kcal_pct_error | 0.021 | 0.019 |
| kcal_within_20pct | 1.000 | 1.000 |
| protein_abs_error_g | 0.214 | 0.450 |
| range_well_formed | 1.000 | 1.000 |
| saturated_fat_g_abs_error | 0.181 | 0.090 |
| saturated_fat_g_answered | 1.000 | 1.000 |
| sodium_mg_abs_error | 19.994 | 11.856 |
| sodium_mg_answered | 1.000 | 1.000 |
| sugars_g_abs_error | 0.867 | 0.393 |
| sugars_g_answered | 1.000 | 1.000 |
| truth_in_stated_range | 0.881 | 1.000 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| (none) | | |

