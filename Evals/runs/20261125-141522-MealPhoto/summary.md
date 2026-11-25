## mealPhoto on `meal_photo/v1` (30 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-sonnet-5` | 90 | 100% | **47%** | 30%–63% | 37%–57% | 50% 50% 40% | 5.4 | 7.7 | 2238 / 0 | 655 | 0.01103 | 11.03 |
| `openai:gpt-6.2-sol` | 90 | 100% | **51%** | 36%–67% | 41%–61% | 57% 50% 47% | 6.6 | 8.7 | 1050 / 0 | 276 | 0.00486 | 4.86 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `openai:gpt-6.2-sol` | 30 | +4.4% | -8.9% to +18.9% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-sonnet-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| carbs_abs_error_g | 11.678 | 8.291 |
| confidence_is_valid | 1.000 | 1.000 |
| fat_abs_error_g | 6.288 | 5.580 |
| items_sum_to_total | 1.000 | 1.000 |
| kcal_pct_error | 0.364 | 0.280 |
| kcal_within_20pct | 0.467 | 0.511 |
| protein_abs_error_g | 6.452 | 4.726 |
| range_well_formed | 1.000 | 1.000 |
| truth_in_stated_range | 0.478 | 0.756 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-sonnet-5` | `openai:gpt-6.2-sol` |
|---|---|---|
| dish_1557937157 | 0/3 | 1/3 |
| dish_1558375667 | 0/3 | 0/3 |
| dish_1558544663 | 0/3 | 0/3 |
| dish_1558635489 | 0/3 | 3/3 |
| dish_1558722125 | 0/3 | 0/3 |
| dish_1561661377 | 0/3 | 0/3 |
| dish_1561662926 | 0/3 | 0/3 |
| dish_1562009810 | 0/3 | 0/3 |
| dish_1562700593 | 0/3 | 0/3 |
| dish_1562774129 | 1/3 | 3/3 |
| dish_1562774159 | 1/3 | 2/3 |
| dish_1563208459 | 0/3 | 0/3 |
| dish_1563221086 | 3/3 | 0/3 |
| dish_1564428144 | 0/3 | 0/3 |
| dish_1564689168 | 0/3 | 0/3 |
| dish_1565020926 | 3/3 | 2/3 |
| dish_1565711498 | 0/3 | 3/3 |
| dish_1565896745 | 2/3 | 3/3 |
| dish_1567007848 | 2/3 | 1/3 |
| dish_1567785654 | 0/3 | 1/3 |
| dish_1567785709 | 3/3 | 1/3 |
| dish_1568305198 | 3/3 | 2/3 |

