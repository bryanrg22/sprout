# Recorded Open Food Facts responses

Each file is the body of one request made on 2026-11-22 (US Pacific) to

    https://world.openfoodfacts.org/api/v2/product/<barcode>.json?fields=product_name,brands,serving_size,serving_quantity,nutriments,code

which is the request `OpenFoodFactsService.product(barcode:)` makes. The bodies are stored as
received, re-indented with sorted keys and otherwise unedited. Open Food Facts data is under
the Open Database License. `OpenFoodFactsDetailTests` reads them.

| File | Barcode | Why it is here |
|---|---|---|
| `cereal-per-serving.json` | 0016000275287 | A US product with `_serving` and `_100g` values and a 39 g serving; sodium and salt both listed. |
| `spread-per-100g-only.json` | 3017620422003 | Per-100 g values only, no serving size or quantity. |
| `diet-soda-few-keys.json` | 0049000028911 | Lists no fiber, sugars or saturated fat at all (the keys are absent), and a serving in millilitres. |
| `crisps-minerals.json` | 0038000138416 | Iron, potassium, calcium and vitamin D, all stated in grams as Open Food Facts does. |
| `soup-cholesterol.json` | 0041196910759 | Cholesterol and added sugars above zero. |

A case no recorded product showed (salt listed without sodium; a product with a serving
weight but no `_serving` values) is made in the test by removing keys from one of these,
and the test says so.
