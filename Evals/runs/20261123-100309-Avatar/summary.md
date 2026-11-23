## avatar on `avatar/photos` (3 cases)

| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | in (uncached / cached) | out | $ / call | $ / 1k calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `openai:gpt-image-2.6-flare@low` | 3 | 100% | **0%** | 0%–56% | 0% | 7.4 | 9.0 | 1454 / 0 | 824 |  |  |
| `openai:gpt-image-2.6-flare@medium` | 3 | 100% | **0%** | 0%–56% | 0% | 8.8 | 9.0 | 1454 / 0 | 1449 |  |  |
| `openai:gpt-image-2.6-sunburst@medium` | 3 | 100% | **0%** | 0%–56% | 0% | 20.1 | 21.1 | 1454 / 0 | 1449 |  |  |

**Mean of each score** (0–1 unless the name says otherwise)

| score | `openai:gpt-image-2.6-flare@low` | `openai:gpt-image-2.6-flare@medium` | `openai:gpt-image-2.6-sunburst@medium` |
|---|---|---|---|
| cost_usd | 0.035 | 0.054 | 0.054 |
| decodable | 1.000 | 1.000 | 1.000 |
| distinct_colours | 0.000 | 0.000 | 0.000 |
| generation_latency_ms | 7669.000 | 8763.667 | 20303.667 |
| generator_accepted | 1.000 | 1.000 | 1.000 |
| has_alpha | 1.000 | 1.000 | 1.000 |
| input_image_tokens | 1024.000 | 1024.000 | 1024.000 |
| input_text_tokens | 430.000 | 430.000 | 430.000 |
| input_tokens | 1454.000 | 1454.000 | 1454.000 |
| is_pixel_art | 0.000 | 0.000 | 0.000 |
| output_tokens | 824.000 | 1449.000 | 1449.000 |
| square_1024 | 1.000 | 1.000 | 1.000 |
| transparent_corners | 0.000 | 0.000 | 0.333 |
| transparent_share | 0.414 | 0.416 | 0.417 |
| transparent_top_corners | 1.000 | 1.000 | 0.667 |

**Cases not passed every time** (passes / attempts)

| case | `openai:gpt-image-2.6-flare@low` | `openai:gpt-image-2.6-flare@medium` | `openai:gpt-image-2.6-sunburst@medium` |
|---|---|---|---|
| synthetic-man-30s-beard | 0/1 | 0/1 | 0/1 |
| synthetic-man-50s-glasses | 0/1 | 0/1 | 0/1 |
| synthetic-woman-20s-ponytail | 0/1 | 0/1 | 0/1 |

