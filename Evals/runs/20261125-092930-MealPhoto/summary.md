## mealPhoto on `meal_photo/v1` (30 cases)

| candidate | attempts | usable | pass | case CI | attempt CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 90 | 97% | **19%** | 8%–32% | 12%–28% | 20% 17% 20% | 3.0 | 4.1 | 2172 / 0 | 727 | 0.00058 | 0.58 |
| `anthropic:claude-sonnet-5` | 90 | 100% | **46%** | 30%–61% | 36%–56% | 50% 43% 43% | 5.7 | 7.7 | 2238 / 0 | 655 | 0.01103 | 11.03 |

**Compared with `anthropic:claude-sonnet-5` on the same cases** (pass-rate difference, case-bootstrap 95% interval; one that includes 0 cannot tell them apart)

| candidate | shared cases | difference | 95% interval |
|---|---|---|---|
| `anthropic:claude-haiku-5-5` | 30 | -26.7% | -42.2% to -12.2% |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| carbs_abs_error_g | 19.537 | 11.490 |
| confidence_is_valid | 1.000 | 1.000 |
| fat_abs_error_g | 8.390 | 6.183 |
| items_sum_to_total | 1.000 | 1.000 |
| kcal_pct_error | 0.562 | 0.352 |
| kcal_within_20pct | 0.195 | 0.456 |
| protein_abs_error_g | 7.059 | 6.592 |
| range_well_formed | 1.000 | 1.000 |
| truth_in_stated_range | 0.276 | 0.467 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` |
|---|---|---|
| dish_1557937157 | 0/3 | 0/3 |
| dish_1558375667 | 0/3 | 0/3 |
| dish_1558544663 | 0/3 | 0/3 |
| dish_1558635489 | 0/3 | 0/3 |
| dish_1558722125 | 0/3 | 0/3 |
| dish_1561661377 | 0/3 | 0/3 |
| dish_1561662926 | 0/3 | 0/3 |
| dish_1562009810 | 0/3 | 0/3 |
| dish_1562700593 | 0/3 | 0/3 |
| dish_1562774129 | 0/3 | 2/3 |
| dish_1562774159 | 2/3 | 2/3 |
| dish_1563208459 | 0/3 | 0/3 |
| dish_1563221086 | 0/3 | 3/3 |
| dish_1564428144 | 1/3 | 0/3 |
| dish_1564689138 | 0/3 | 3/3 |
| dish_1564689168 | 0/3 | 0/3 |
| dish_1564773942 | 1/3 | 3/3 |
| dish_1565020926 | 0/3 | 3/3 |
| dish_1565711498 | 0/3 | 0/3 |
| dish_1565896745 | 1/3 | 2/3 |
| dish_1565898331 | 0/3 | 3/3 |
| dish_1566328805 | 0/3 | 2/3 |
| dish_1567007848 | 0/3 | 2/3 |
| dish_1567785654 | 0/3 | 0/3 |
| dish_1567785709 | 3/3 | 2/3 |
| dish_1568305198 | 0/3 | 3/3 |
| dish_1568401233 | 0/3 | 2/3 |

**Errors**

- `anthropic:claude-haiku-5-5`: decoding("DecodingError.keyNotFound: Key \'fat_g\' not found in keyed decoding container. Path: items[3]. Debug description: No value associated with key CodingKeys(stringValue: \"fat_g\", intValue: nil) (\"fat_g\").")
- `anthropic:claude-haiku-5-5`: decoding("DecodingError.keyNotFound: Key \'notes\' not found in keyed decoding container. Debug description: No value associated with key Key(stringValue: \"notes\", intValue: nil) (\"notes\").")

