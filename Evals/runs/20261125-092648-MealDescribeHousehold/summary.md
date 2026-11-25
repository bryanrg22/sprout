## mealDescribe on `meal_describe/v4` (22 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 66 | 97% | **83%** | 68%–95% | 73%–90% | 77% 86% 86% | 2.0 | 2.5 | 1581 / 0 | 507 | 0.00041 | 0.41 |
| `anthropic:claude-sonnet-5` | 66 | 100% | **92%** | 82%–100% | 83%–97% | 91% 95% 91% | 3.9 | 5.1 | 1647 / 0 | 480 | 0.00809 | 8.09 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 22 | -9.1% | -19.7% to -1.5% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| carbs_abs_error_g | 1.888 | 1.159 |
| confidence_is_valid | 1.000 | 1.000 |
| fat_abs_error_g | 1.530 | 0.876 |
| fiber_g_abs_error | 0.494 | 0.158 |
| fiber_g_answered | 1.000 | 1.000 |
| items_sum_to_total | 1.000 | 0.985 |
| kcal_pct_error | 0.094 | 0.055 |
| kcal_within_20pct | 0.859 | 0.924 |
| protein_abs_error_g | 2.089 | 1.605 |
| range_well_formed | 1.000 | 1.000 |
| saturated_fat_g_abs_error | 0.306 | 0.220 |
| saturated_fat_g_answered | 1.000 | 1.000 |
| sodium_mg_abs_error | 12.878 | 15.347 |
| sodium_mg_answered | 1.000 | 1.000 |
| sugars_g_abs_error | 0.375 | 0.282 |
| sugars_g_answered | 1.000 | 1.000 |
| truth_in_stated_range | 0.766 | 0.879 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| avocado-half | 0/3 | 3/3 |
| eggs-2-large | 2/3 | 3/3 |
| oatmeal-milk | 2/3 | 3/3 |
| salmon-half-fillet | 0/3 | 0/3 |
| salmon-potato | 0/3 | 1/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: decoding("DecodingError.keyNotFound: Key \'notes\' not found in keyed decoding container. Debug description: No value associated with key Key(stringValue: \"notes\", intValue: nil) (\"notes\").")

