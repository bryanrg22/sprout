## mealDescribe on `meal_describe/v4` (22 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 66 | 100% | **94%** | 85%–100% | 85%–98% | 95% 91% 95% | 3.9 | 5.2 | 1647 / 0 | 481 | 0.00811 | 8.11 |
| `anthropic:claude-sonnet-5-5` | 66 | 100% | **94%** | 83%–100% | 85%–98% | 95% 91% 95% | 3.1 | 4.6 | 1483 / 0 | 278 | 0.00575 | 5.75 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 22 | +0.0% | -6.1% to +7.6% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| carbs_abs_error_g | 1.185 | 0.485 |
| confidence_is_valid | 1.000 | 1.000 |
| fat_abs_error_g | 0.744 | 1.168 |
| fiber_g_abs_error | 0.153 | 0.218 |
| fiber_g_answered | 1.000 | 1.000 |
| items_sum_to_total | 1.000 | 0.848 |
| kcal_pct_error | 0.049 | 0.049 |
| kcal_within_20pct | 0.939 | 0.939 |
| protein_abs_error_g | 1.368 | 1.108 |
| range_well_formed | 1.000 | 1.000 |
| saturated_fat_g_abs_error | 0.202 | 0.195 |
| saturated_fat_g_answered | 1.000 | 0.985 |
| sodium_mg_abs_error | 11.708 | 17.745 |
| sodium_mg_answered | 1.000 | 1.000 |
| sugars_g_abs_error | 0.341 | 0.406 |
| sugars_g_answered | 1.000 | 1.000 |
| truth_in_stated_range | 0.894 | 0.879 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|
| oatmeal-milk | 3/3 | 2/3 |
| salmon-half-fillet | 1/3 | 0/3 |
| salmon-potato | 1/3 | 3/3 |

