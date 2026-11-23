## mealDescribe on `meal_describe/v1` (14 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `anthropic:claude-haiku-4-5-20251001` | 42 | 83% | **81%** | 67%–90% | 86% 86% 71% | 2.5 | 3.6 | 1153 / 0 | 319 | 0.00275 | 2.75 |
| `anthropic:claude-haiku-5-5` | 42 | 100% | **100%** | 92%–100% | 100% 100% 100% | 1.6 | 2.1 | 1156 / 0 | 405 | 0.00032 | 0.32 |
| `anthropic:claude-sonnet-5` | 42 | 98% | **98%** | 88%–100% | 100% 93% 100% | 3.3 | 4.0 | 1222 / 0 | 372 | 0.00617 | 6.17 |
| `anthropic:claude-sonnet-5-5` | 42 | 0% | **0%** | 0%–8% | 0% 0% 0% | 0.0 | 0.0 | 0 / 0 | 0 | 0.00000 | 0.00 |
| `openai:gpt-4.1-mini` | 42 | 100% | **100%** | 92%–100% | 100% 100% 100% | 1.6 | 2.1 | 337 / 0 | 131 | 0.00034 | 0.34 |
| `openai:gpt-5.6-luna` | 42 | 100% | **98%** | 88%–100% | 100% 93% 100% | 2.4 | 3.5 | 331 / 0 | 170 | 0.00027 | 0.27 |
| `openai:gpt-5.6-terra` | 42 | 100% | **100%** | 92%–100% | 100% 100% 100% | 2.7 | 3.9 | 331 / 0 | 203 | 0.00309 | 3.09 |
| `openai:gpt-6-luna` | 42 | 100% | **100%** | 92%–100% | 100% 100% 100% | 2.2 | 2.9 | 331 / 0 | 153 | 0.00011 | 0.11 |
| `openai:gpt-6.1-terra` | 42 | 100% | **100%** | 92%–100% | 100% 100% 100% | 2.8 | 4.4 | 331 / 0 | 152 | 0.00109 | 1.09 |
| `openai:gpt-6.2-sol` | 42 | 100% | **100%** | 92%–100% | 100% 100% 100% | 2.6 | 3.6 | 356 / 0 | 140 | 0.00211 | 2.11 |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| carbs_abs_error_g | 0.274 | 0.302 | 0.244 |  | 0.617 | 2.090 | 0.214 | 0.838 | 0.255 | 0.238 |
| confidence_is_valid | 1.000 | 1.000 | 1.000 |  | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| fat_abs_error_g | 0.407 | 0.264 | 0.237 |  | 0.410 | 0.338 | 0.333 | 0.505 | 0.479 | 0.321 |
| items_sum_to_total | 1.000 | 1.000 | 1.000 |  | 1.000 | 0.952 | 1.000 | 1.000 | 1.000 | 1.000 |
| kcal_pct_error | 0.023 | 0.017 | 0.014 |  | 0.022 | 0.031 | 0.019 | 0.020 | 0.021 | 0.017 |
| kcal_within_20pct | 0.971 | 1.000 | 1.000 |  | 1.000 | 0.976 | 1.000 | 1.000 | 1.000 | 1.000 |
| protein_abs_error_g | 1.877 | 0.290 | 0.415 |  | 0.431 | 0.214 | 0.431 | 0.267 | 0.545 | 0.229 |
| range_well_formed | 1.000 | 1.000 | 1.000 |  | 1.000 | 0.810 | 1.000 | 0.905 | 0.929 | 1.000 |
| truth_in_stated_range | 0.686 | 0.929 | 1.000 |  | 0.738 | 0.714 | 0.929 | 0.762 | 0.810 | 0.905 |

**Cases not passed every time** (passes / attempts)

| case | `anthropic:claude-haiku-4-5-20251001` | `anthropic:claude-haiku-5-5` | `anthropic:claude-sonnet-5` | `anthropic:claude-sonnet-5-5` | `openai:gpt-4.1-mini` | `openai:gpt-5.6-luna` | `openai:gpt-5.6-terra` | `openai:gpt-6-luna` | `openai:gpt-6.1-terra` | `openai:gpt-6.2-sol` |
|---|---|---|---|---|---|---|---|---|---|---|
| banana-118g | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| bread-2-slices | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| chicken-150g | 2/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| chicken-rice | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| eggs-2-boiled | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| eggs-toast | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| milk-1cup | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| oatmeal-milk-banana | 2/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| oats-40g-dry | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| olive-oil-1tbsp | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| pb-sandwich | 0/3 | 3/3 | 3/3 | 0/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| peanut-butter-2tbsp | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| rice-1cup | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| rice-chicken-oil | 0/3 | 3/3 | 2/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

**Errors**

- `anthropic:claude-haiku-4-5-20251001`: decoding("DecodingError.keyNotFound: Key \'total_calories\' not found in keyed decoding container. Debug description: No value associated with key CodingKeys(stringValue: \"total_calories\", intValue: nil) (\"total_calories\").")
- `anthropic:claude-sonnet-5`: decoding("DecodingError.typeMismatch: expected value of type Array<Any>. Path: items. Debug description: Expected to decode Array<Any> but found a string instead.")
- `anthropic:claude-sonnet-5-5`: badResponse("tool_choice: type \"tool\" and \"any\" are not supported for this model.")

