## mealPhoto on `meal_photo/v1` (30 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-opus-5-5` | 90 | 100% | **31%** | 18%–46% | 22%–41% | 27% 27% 40% | 5.8 | 7.6 | 2075 / 0 | 482 | 0.01795 | 17.95 |
| `anthropic:claude-sonnet-5` | 90 | 100% | **43%** | 28%–59% | 34%–54% | 40% 47% 43% | 5.6 | 7.8 | 2238 / 0 | 658 | 0.01106 | 11.06 |
| `anthropic:claude-sonnet-5-5` | 90 | 100% | **29%** | 17%–42% | 21%–39% | 23% 33% 30% | 5.0 | 6.9 | 2074 / 0 | 479 | 0.00894 | 8.94 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-opus-5-5` | 30 | -12.2% | -26.7% to +2.2% |
| `anthropic:claude-sonnet-5-5` | 30 | -14.4% | -26.7% to -2.2% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|
| carbs_abs_error_g | 12.447 | 11.160 | 13.040 |
| confidence_is_valid | 1.000 | 1.000 | 1.000 |
| fat_abs_error_g | 7.747 | 6.453 | 7.373 |
| items_sum_to_total | 0.900 | 1.000 | 0.856 |
| kcal_pct_error | 0.474 | 0.360 | 0.439 |
| kcal_within_20pct | 0.311 | 0.433 | 0.289 |
| protein_abs_error_g | 6.258 | 6.534 | 7.170 |
| range_well_formed | 1.000 | 1.000 | 1.000 |
| truth_in_stated_range | 0.456 | 0.467 | 0.356 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-opus-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` |
|---|---|---|---|
| dish_1557937157 | 1/3 | 0/3 | 2/3 |
| dish_1558375667 | 0/3 | 0/3 | 0/3 |
| dish_1558544663 | 0/3 | 0/3 | 0/3 |
| dish_1558635489 | 2/3 | 0/3 | 0/3 |
| dish_1558722125 | 0/3 | 0/3 | 0/3 |
| dish_1561661377 | 0/3 | 0/3 | 0/3 |
| dish_1561662926 | 0/3 | 0/3 | 0/3 |
| dish_1562009810 | 0/3 | 0/3 | 0/3 |
| dish_1562700593 | 0/3 | 0/3 | 0/3 |
| dish_1562774129 | 1/3 | 1/3 | 0/3 |
| dish_1562774159 | 0/3 | 1/3 | 1/3 |
| dish_1563208459 | 0/3 | 0/3 | 0/3 |
| dish_1563221086 | 0/3 | 3/3 | 1/3 |
| dish_1564428144 | 0/3 | 0/3 | 0/3 |
| dish_1564689138 | 2/3 | 3/3 | 1/3 |
| dish_1564689168 | 0/3 | 0/3 | 0/3 |
| dish_1565020926 | 1/3 | 3/3 | 2/3 |
| dish_1565711498 | 0/3 | 0/3 | 1/3 |
| dish_1565896745 | 3/3 | 2/3 | 3/3 |
| dish_1565898331 | 3/3 | 1/3 | 0/3 |
| dish_1566328805 | 2/3 | 3/3 | 1/3 |
| dish_1566850099 | 1/3 | 2/3 | 2/3 |
| dish_1567007848 | 0/3 | 2/3 | 0/3 |
| dish_1567785654 | 0/3 | 0/3 | 0/3 |
| dish_1567785709 | 0/3 | 3/3 | 2/3 |
| dish_1568305198 | 0/3 | 3/3 | 0/3 |
| dish_1568401233 | 3/3 | 3/3 | 1/3 |

