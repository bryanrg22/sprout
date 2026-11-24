# Nutrition detail: the label beyond the macros

*"I want to be as specific as possible when it comes to the metrics of what you eat, like the macros."*

A food entry carried calories, protein, carbohydrate and fat. This is the research behind
adding the rest of the Nutrition Facts panel, the field set that came out of it, and how
each source fills it. Written 2026-11-23. Every claim has its source beside it; where a
page could not be read in the session, that is said.

The rule the whole feature rests on: **a value that is not known is shown as unknown and
is never counted as zero.** A day's total for a nutrient counts only the foods that state
it, and says how many that is ("Fiber 18 g, from 4 of 6 foods").

## 1. What the US label requires, and in what order

The Nutrition Facts panel prints, top to bottom: serving size, calories, total fat,
saturated fat, trans fat, cholesterol, sodium, total carbohydrate, dietary fiber, total
sugars, added sugars ("Includes X g Added Sugars"), protein, then vitamin D, calcium, iron
and potassium. Source: the FDA's label reference, read from its sample label
(<https://www.fda.gov/food/nutrition-facts-label/how-understand-and-use-nutrition-facts-label>).

The regulation behind it is 21 CFR 101.9(c)
(<https://www.law.cornell.edu/cfr/text/21/101.9>; the eCFR's own page redirected the
fetcher to a block page, so the Cornell copy was read):

| Line | Paragraph | Unit | Declared to | May be declared as zero below |
|---|---|---|---|---|
| Calories | (c)(1) | kcal | nearest 5 up to 50, nearest 10 above | 5 kcal |
| Total fat | (c)(2) | g | nearest 0.5 g below 5 g, nearest 1 g above | 0.5 g |
| Saturated fat | (c)(2)(i) | g | as total fat | 0.5 g |
| Trans fat | (c)(2)(ii) | g | as total fat | 0.5 g |
| Cholesterol | (c)(3) | mg | nearest 5 mg | 2 mg ("less than 5 milligrams" from 2 to 5) |
| Sodium | (c)(4) | mg | nearest 5 mg to 140 mg, nearest 10 mg above | 5 mg |
| Total carbohydrate | (c)(6) | g | nearest gram | 0.5 g ("less than 1 gram" below 1) |
| Dietary fiber | (c)(6)(i) | g | nearest gram | 0.5 g ("less than 1 gram" below 1) |
| Total sugars | (c)(6)(ii) | g | nearest gram | 0.5 g |
| Added sugars | (c)(6)(iii) | g | nearest gram | 0.5 g |
| Protein | (c)(7) | g | nearest gram | 0.5 g ("less than 1 gram" below 1) |
| Vitamin D, calcium, iron, potassium | (c)(8) | mcg, mg, mg, mg | with a % Daily Value | under 2% of the reference intake |

Three more facts from the same text that the code depends on:

- **The label is itself approximate.** A product is misbranded only when calories, sugars,
  fat, saturated fat, cholesterol or sodium are more than 20% above the declared value, or a
  naturally occurring vitamin, mineral, protein or fiber is below 80% of it (101.9(g)(4)
  and (g)(5)). The app's calorie pass rule for the estimator already uses that 20%.
- **"Not a significant source of ..."** is the required closing sentence of a simplified
  label. An "insignificant amount" is "that amount that allows a declaration of zero",
  except for total carbohydrate, dietary fiber and protein, where it is an amount that
  allows "less than 1 gram" (101.9(f)(1), (f)(4)). So the sentence declares zero for the
  nutrients it names, and "less than 1 gram" for fiber.
- **Vitamin D is declared in micrograms.** Older labels used International Units; the FDA's
  conversion is 1 mcg = 40 IU
  (<https://www.fda.gov/media/129863/download>, "1 mcg cholecalciferol = 40 IU vitamin D").

Vitamins A and C, the polyunsaturated and monounsaturated fats, soluble and insoluble fiber
and sugar alcohol are voluntary or conditional, and are left out here.

## 2. What a consumer tracker commonly shows

- **Apple Health** has a dietary type for every line above except two: there is no type for
  added sugars and none for trans fat. Read from `HKTypeIdentifiers.h` in the iOS 26.4 SDK,
  which has `HKQuantityTypeIdentifierDietaryFiber`, `…DietarySugar`, `…DietaryFatSaturated`,
  `…DietarySodium`, `…DietaryCholesterol`, `…DietaryPotassium`, `…DietaryCalcium`,
  `…DietaryIron` and `…DietaryVitaminD` among 39 dietary identifiers (reference page:
  <https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier>, which the
  fetcher could not render; the header was read instead).
- **MyFitnessPal** says it tracks "a wide variety of nutrients" but shows a handful of
  columns in the diary at a time, and that it tracks vitamin A, vitamin C, calcium, iron and
  potassium
  (<https://support.myfitnesspal.com/hc/en-us/articles/360032621991-How-can-I-change-the-nutrients-that-are-tracked-in-my-diary>,
  <https://support.myfitnesspal.com/hc/en-us/articles/360032625091-Nutrition-101-Vitamins-Minerals>).
  Both pages answered the fetcher with HTTP 403; this is from the search engine's excerpts
  of them, so treat it as read second-hand.
- **Cronometer** describes itself as tracking "up to 84 nutrients" (<https://cronometer.com/>,
  also from a search excerpt). It is the micronutrient end of the market; its numbers come
  from curated databases, not from estimates.

What was not found anywhere: a tracker that states how many of a day's foods a nutrient
total covers. They show a total, and a food with no value for a nutrient silently
contributes zero. That is the behaviour this feature refuses.

## 3. What Open Food Facts returns

Read from five product responses recorded from the live API on 2026-11-22
(`SproutTests/Fixtures/OpenFoodFacts/`, barcodes in its README) and from the project's
schema page (<https://openfoodfacts.github.io/documentation/docs/Product-Opener/schemas/schemas/product_nutrition/>).

- The product's `nutriments` object has, for each nutrient, `<name>_100g`, `<name>_serving`,
  `<name>_value`, `<name>_unit` and a bare `<name>`. The schema page says to use
  `_100g` or `_serving`, "The normalized value of the nutrient for ... in a standard unit",
  and not `_value` / `_unit`, which hold what a contributor typed and "can be in different
  units".
- **The standard unit is grams for everything measured by weight**, including the nutrients
  a label states in milligrams or micrograms. Recorded: a cereal's `sodium_serving` is
  `0.19` (190 mg on the box); a crisp's `iron_serving` is `0.0001` (0.1 mg). So the app
  multiplies by 1,000 for cholesterol, sodium, calcium, iron and potassium, and by
  1,000,000 for vitamin D.
- The key names: `saturated-fat`, `trans-fat`, `cholesterol`, `sodium`, `salt`, `fiber`,
  `sugars`, `added-sugars`, `vitamin-d`, `calcium`, `iron`, `potassium`.
- **Salt and sodium.** All five recorded products list both, in the ratio 2.5 exactly
  (cereal: `salt_serving` 0.475, `sodium_serving` 0.19). The factor is the one EU labelling
  defines, salt = sodium × 2.5 (Regulation (EU) 1169/2011, Annex I,
  <https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32011R1169>; that page came
  back empty to the fetcher, so the factor rests on the recorded data). The app reads
  `sodium`; only when a product has no sodium key does it take `salt ÷ 2.5`, and then the
  confirm sheet says "Sodium worked out from the listed salt (salt ÷ 2.5)."
- **Missing keys are common.** The recorded diet soda has no `fiber`, `sugars`,
  `saturated-fat`, `trans-fat` or `cholesterol` key at all; the cereal has no vitamin or
  mineral keys; the spread has per-100 g values only and no serving. A missing key is "not
  known". The existing macro mapping turns a missing macro into 0; the new mapping does not.
- Per serving vs per 100 g is resolved per nutrient exactly as the calories already are:
  `_serving` if present, else `_100g` × `serving_quantity` ÷ 100, else the per-100 g value
  with the serving described as "100 g".

## 4. What USDA FoodData Central provides

The API (<https://fdc.nal.usda.gov/api-guide>) serves four data types (Foundation, SR
Legacy, FNDDS, Branded) through `/fdc/v1/foods/search`, `/fdc/v1/food/{fdcId}` and
`/fdc/v1/foods`; the data are public domain. Each food carries a `foodNutrients` list keyed
by a nutrient number that is the same across data types: 291 fiber, 269 total sugars, 539
added sugars, 606 saturated fat, 605 trans fat, 601 cholesterol, 307 sodium, 306
potassium, 301 calcium, 303 iron, 328 vitamin D (mcg). `fetch_usda.py` matches on the
number. A record that does not list a nutrient simply has no entry for it, which this
project keeps as null.

The response shape the script reads (`foodNutrients[].nutrient.number` as a string,
`.nutrient.unitName`, `.amount`, at most 20 ids a request) is the published one
(<https://fdc.nal.usda.gov/api-spec/fdc_api.yaml>).

**Not verified in this session:** the nutrient numbers above are written from knowledge of
the database, not read from a response, and the new fetch code has not run against the
live API. The demo key answered HTTP 429 with
`x-ratelimit-limit: 10`, `x-ratelimit-remaining: 0` and `retry-after: 58739` (about 16
hours) on the first request, so no food detail could be fetched. The guide states the demo
key's allowance as 30 requests an hour and 50 a day per IP address. Section 8 says what
that left undone.

## 5. What is honest to estimate

Two published evaluations of a general model estimating nutrients from meal photos:

- O'Hara et al., *Nutrients* 2025, 114 photographs of 38 meals of known composition
  (<https://pmc.ncbi.nlm.nih.gov/articles/PMC11858203/>). Difference from the true value:
  energy +0.1%, fat +14.8%, saturated fat +30.8%, sodium +18.8%, fibre −20.0%, sugar
  −32.2%, iron −19.4%, calcium −27.8%, potassium −49.5%, vitamin D −100%. Rank correlation
  with the truth: sodium 0.78, saturated fat 0.77, sugar 0.75, fibre 0.64, iron 0.53,
  calcium 0.39, vitamin D 0.31. The model under-estimated the weight of medium and large
  portions, and "consequently underestimated nutrient content for most nutrients".
- The ZOE PREDICT abstract, 10,000 meals from 2,124 people against weighed logs
  (<https://www.cambridge.org/core/journals/proceedings-of-the-nutrition-society/article/leveraging-imagebased-ai-for-dietary-assessment-evaluating-a-large-language-model-with-realworld-meal-photos-from-the-zoe-predict-cohorts/64BD22D52D629009CED6A8EF65B3E75A>):
  per-meal differences of 139 kcal, 2.30 g fibre, 6.83 g sugar and 0.23 g sodium. An
  abstract from the company that makes the product, described by its authors as preliminary.

What this supports:

- **Fiber, total sugars, saturated fat and sodium** follow from which food it is and how
  much of it there is, the same two things the calories and macros follow from. Their error
  is larger than the macros' (20 to 30% in the controlled study) but they track the truth
  (correlations 0.64 to 0.78). They can be estimated, shown as estimates, and measured.
  Sodium is the weakest of the four in principle: most of it is added in preparation
  ("over 70%" of dietary sodium comes from packaged and prepared foods,
  <https://www.fda.gov/food/nutrition-education-resources-materials/sodium-your-diet>), so
  the model is told it may answer "not known".
- **Vitamin D, calcium, iron and potassium** were estimated badly: calcium, iron and
  vitamin D barely track the truth (correlations 0.31 to 0.53) and potassium came out at
  half. They depend on fortification and variety, which a photo does not show. Not estimated.
- **Added sugars, trans fat and cholesterol** were not in either study. Added sugars are a
  fact about a recipe, not about what is on the plate; the USDA reference records this
  project grades against do not list them, so an estimate could not be measured either. By
  the repository's rule that a claim is measured, they are not estimated.

## 6. The decision

**Stored on every food entry (eleven optional fields, per serving like the calories):** the
whole mandatory panel below the macros, in label order: saturated fat (g), trans fat (g),
cholesterol (mg), sodium (mg), fiber (g), total sugars (g), added sugars (g), vitamin D
(mcg), calcium (mg), iron (mg), potassium (mg). `nil` means not known.

Why all eleven and not only the five named in the goal: a barcode and a scanned label state
all of them, and "as specific as possible" is not served by reading a row off a label and
throwing it away. They cost nothing when absent (the row is not shown).

**Always given a row** (known or "not known"): saturated fat, sodium, fiber, total sugars,
added sugars. The other six appear when something states them.

**The photo and description estimator is asked for four:** fiber, total sugars, saturated
fat, sodium, as totals for the meal, each allowed to be null. **It is not asked for** added
sugars, trans fat, cholesterol, vitamin D, calcium, iron or potassium, and its prompt says
not to report any other nutrient. An entry from a photo therefore always shows those seven
as not known until the user adds them.

**The coach's `log_food` and `edit_food`** accept all eleven as optional arguments. Their
descriptions draw the same line: the four may be given when the user states them or the
model can work them out from the food; the other seven only when the user gives the number.

How "not known" is represented at each source:

| Source | Not known is | What makes a value known |
|---|---|---|
| Barcode and food search (Open Food Facts) | no `_serving` and no `_100g` key for the nutrient; or a negative or implausibly large figure | a listed value, converted from grams |
| Label scan | a row that is absent, or whose amount cannot be read with its unit; a % Daily Value alone | a printed amount; "less than X" as X ÷ 2; "not a significant source of" as 0 (0.5 g for fiber) |
| Photo and description | `null` in a required, nullable field; a missing key; a negative, a non-number, an impossible amount, or four exact zeros on a meal of 50 kcal or more | a plausible number |
| Coach tools | the argument absent, null or not a number | a number in range; an out-of-range number refuses the call |
| Manual entry and edit | an empty field | a number typed, including 0 |
| Recents and favourites | copied as it was | copied as it was |
| Export | the key is absent from the JSON | the key with its number |
| Store (and CloudKit) | `nil` in an optional field | the number |

**The estimator's "not known".** EVAL_REPORT section 10 recorded that OpenAI's Responses API
normalises a tool schema into strict mode, where every property is required, and that an
optional number then arrives filled with a placeholder. OpenAI's guide gives the remedy:
"You can denote optional fields by adding `null` as a `type` option"
(<https://developers.openai.com/api/docs/guides/function-calling>). So the four fields are
typed `["number", "null"]` and listed as **required**: the field is always present and null
is always a legal answer, on every provider and with or without strict mode. Anthropic's
`input_schema` is "a JSON Schema object"
(<https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools>), in which a
type union is ordinary; without strict tool use a forced call does not guarantee the
arguments conform, which is why the decoder is lenient about these four and strict about
the original nine. The decoder's rules and their tests are in `FoodPhotoAnalyzer.swift` and
`MealEstimateDetailTests`.

One rule there is a judgement and should be read as one: four exact zeros on a meal of 50
kcal or more are treated as a placeholder block. Plain cooked rice could honestly round to
four zeros and would be shown as "not known". That errs toward the rule: unknown is
acceptable, a false zero is not.

## 7. Verified by running

- **An existing store opens.** A store written by the app before this change (ten food rows,
  no label columns) was opened by the new build on the simulator: the ten rows were kept,
  the eleven columns were added, every one of them NULL, and the Nutrients tab showed the
  day with "None of this day's foods list these yet"
  (`docs/screenshots/review/nutrition-day-none-known.png`).
- **Not known is NULL on disk and a stated zero is 0.** Read with `sqlite3` from the
  simulator's store after seeding the demo day: the food with no detail has NULL in all
  eleven columns, and the food with a stated vitamin D of zero has `0.0`.
- **The screens.** Six states were opened in the simulator with DEBUG launch arguments and
  looked at (`docs/screenshots/review/nutrition-*.png`): a day with partial coverage, the
  same day with every row, a food with the whole label, one with part of it, one with none,
  and the edit sheet's label rows.
- **The tests.** 111 unit tests and 7 evaluation self-tests were added; both suites pass.

## 8. Not done, and not verified

- **`Evals/datasets/meal_describe/v3.jsonl` is not built.** It needs the label nutrients of
  nine USDA records, and the demo key was rate-limited for the rest of the day (section 4).
  `fetch_usda.py --details-only` (one request) and then `build_v3.py` produce it. The
  script that builds it was checked with made-up records only. `GraderTests` holds the
  cache, v1 and v3 to one another in either state: without cached detail v3 must not exist;
  with it, v3 must exist and every column must equal the arithmetic on the cache.
- **No model has been asked for the new fields.** The schema, the prompt paragraph and the
  decoder are tested against scripted replies on all three wire formats; whether real
  models answer null when they should, and how large their error is, is what the paid
  evaluation measures.
- **The label parser was tested on typed OCR text**, including misreads, not on a camera
  frame: the simulator has no camera. The sample is the FDA's own label.
- One v1 record does not match its description: the peanut-butter cases use USDA's "without
  salt" record while the text says only "smooth peanut butter". `build_v3.py` leaves sodium
  null for those two cases rather than grade a model against the wrong food.
- No daily values or targets are shown for the new nutrients. A percentage of a daily value
  computed from a partial total would present an incomplete number as a complete one.
- The values are not written to Apple Health.
- A scanned non-US label that lists "Salt" and no sodium row leaves sodium not known (the
  barcode path does convert).
- The coach cannot set a known value back to "not known"; the edit sheet can (clear the field).
