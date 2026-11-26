## mealDescribe on `meal_describe/v4` (22 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5-5` | 66 | 100% | **92%** | 80%–100% | 83%–97% | 95% 91% 91% | 3.0 | 4.7 | 1482 / 0 | 272 | 0.00568 | 5.68 |
| `openai:gpt-6.2-sol` | 66 | 100% | **86%** | 73%–100% | 76%–93% | 86% 86% 86% | 4.4 | 5.9 | 583 / 0 | 173 | 0.00290 | 2.90 |

**Compared with `anthropic:claude-sonnet-5-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 22 | -6.1% | -21.2% to +6.1% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| carbs_abs_error_g | 1.111 | 0.542 |
| confidence_is_valid | 1.000 | 1.000 |
| fat_abs_error_g | 0.847 | 1.459 |
| fiber_g_abs_error | 0.280 | 0.247 |
| fiber_g_answered | 1.000 | 1.000 |
| items_sum_to_total | 0.894 | 1.000 |
| kcal_pct_error | 0.048 | 0.068 |
| kcal_within_20pct | 0.924 | 0.864 |
| protein_abs_error_g | 1.383 | 2.035 |
| range_well_formed | 1.000 | 1.000 |
| saturated_fat_g_abs_error | 0.216 | 0.276 |
| saturated_fat_g_answered | 1.000 | 1.000 |
| sodium_mg_abs_error | 17.108 | 3.753 |
| sodium_mg_answered | 1.000 | 0.750 |
| sugars_g_abs_error | 0.258 | 0.211 |
| sugars_g_answered | 1.000 | 1.000 |
| truth_in_stated_range | 0.864 | 0.848 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| avocado-half | 3/3 | 0/3 |
| oatmeal-milk | 1/3 | 3/3 |
| salmon-half-fillet | 0/3 | 0/3 |
| salmon-potato | 3/3 | 0/3 |

