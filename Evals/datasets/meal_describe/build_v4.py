#!/usr/bin/env python3
"""Build meal_describe/v4.jsonl from the cached USDA values (no network).

v1 and v3 state every portion in grams, so they measure arithmetic, and on 2026-11-25 both
models passed every attempt within about 2% (EVAL_REPORT 36). v4 describes the same foods the
way people type them, in household measures with no weight given ("a medium banana", "a cup
of cooked rice", "half a salmon fillet"). The model now has to know how much that is.

The truth is still USDA's: each measure is one of the household portions FoodData Central
lists for that very record (`usda_cache.json`, "portions"), with its gram weight, times the
record's per-100 g values. Nothing comes from memory. A case that uses a measure USDA does not
list for the record fails the build. The label nutrients are added exactly as in v3
(`build_v3.build`).
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_v3  # noqa: E402  (only its functions; it writes nothing on import)

cache = json.load(open(os.path.join(HERE, "usda_cache.json")))


def ref(key):
    entry = cache[key]
    exact = next((h for h in entry["hits"] if h["description"].lower() == entry["query"].lower()), None)
    return exact or entry["hits"][0]


def grams(key, modifier, units):
    """`units` of the USDA measure `modifier` of `key`, in grams. A measure is stored as an
    amount and its weight (peanut butter: 2 tbsp = 32 g, broccoli: 0.5 cup = 78 g), so the
    weight of one unit is gramWeight / amount. Where USDA lists the same modifier twice (dry
    oats: 1 cup = 81 g and 0.33 cup = 27 g), the entry whose amount is `units` is used."""
    items = [p for p in cache[key]["portions"]["items"] if p["modifier"] == modifier]
    if len(items) > 1:
        items = [p for p in items if abs(p["amount"] - units) < 1e-9]
    if len(items) != 1:
        raise LookupError(f"{key}: USDA lists no single portion {modifier!r} for {units}; it lists "
                          + ", ".join(f"{p['amount']} {p['modifier']!r}" for p in cache[key]["portions"]["items"]))
    p = items[0]
    return units * p["gramWeight"] / p["amount"]


# id, what the user types (no weights), [(ingredient key, USDA measure, how many of its unit)]
M_BANANA = "medium (7\" to 7-7/8\" long)"
AVOCADO = "avocado, NS as to Florida or California"
CASES = [
    ("banana-medium", "a medium banana", [("banana", M_BANANA, 1)]),
    ("banana-large", "a large banana", [("banana", "large (8\" to 8-7/8\" long)", 1)]),
    ("apple-medium", "a medium apple, peeled", [("apple", "medium (3\" dia)", 1)]),
    ("avocado-half", "half an avocado", [("avocado", AVOCADO, 0.5)]),
    ("eggs-2-large", "two large hard-boiled eggs", [("egg_hard_boiled", "large", 2)]),
    ("toast-2-slices", "two slices of whole-wheat toast", [("bread_whole_wheat", "slice", 2)]),
    ("milk-cup", "a cup of whole milk", [("milk_whole", "cup", 1)]),
    ("rice-cup", "a cup of cooked white rice", [("rice_white_cooked", "cup", 1)]),
    ("rice-2-cups", "two cups of cooked white rice", [("rice_white_cooked", "cup", 2)]),
    ("olive-oil-tbsp", "a tablespoon of olive oil", [("olive_oil", "tablespoon", 1)]),
    ("pb-2tbsp", "two tablespoons of peanut butter", [("peanut_butter", "tbsp", 2)]),
    ("almonds-oz", "an ounce of almonds", [("almonds", "oz (23 whole kernels)", 1)]),
    ("potato-medium", "a medium baked potato with the skin", [("potato_baked", "potato medium", 1)]),
    ("salmon-half-fillet", "half a salmon fillet, baked", [("salmon_cooked", "fillet", 0.5)]),
    ("chicken-3oz", "3 oz of grilled chicken breast", [("chicken_breast_grilled", "oz", 3)]),
    ("broccoli-half-cup", "half a cup of chopped cooked broccoli", [("broccoli_cooked", "cup, chopped", 0.5)]),
    ("banana-pb", "a medium banana with two tablespoons of peanut butter",
     [("banana", M_BANANA, 1), ("peanut_butter", "tbsp", 2)]),
    ("eggs-toast", "two large boiled eggs and two slices of whole-wheat toast",
     [("egg_hard_boiled", "large", 2), ("bread_whole_wheat", "slice", 2)]),
    ("oatmeal-milk", "a bowl of oatmeal made with a third of a cup of dry oats and a cup of whole milk",
     [("oats_dry", "cup", 0.33), ("milk_whole", "cup", 1)]),
    ("chicken-rice-broccoli", "3 oz of grilled chicken with a cup of white rice and half a cup of broccoli",
     [("chicken_breast_grilled", "oz", 3), ("rice_white_cooked", "cup", 1), ("broccoli_cooked", "cup, chopped", 0.5)]),
    ("salmon-potato", "half a salmon fillet with a medium baked potato",
     [("salmon_cooked", "fillet", 0.5), ("potato_baked", "potato medium", 1)]),
    ("avocado-toast", "avocado toast: two slices of whole-wheat bread with half an avocado and a teaspoon of olive oil",
     [("bread_whole_wheat", "slice", 2), ("avocado", AVOCADO, 0.5), ("olive_oil", "tsp", 1)]),
]


def rows():
    out = []
    for case_id, text, parts in CASES:
        total = {"kcal": 0.0, "protein_g": 0.0, "carbs_g": 0.0, "fat_g": 0.0}
        sources = []
        for key, modifier, units in parts:
            g = round(grams(key, modifier, units), 2)
            r = ref(key)
            for field in total:
                total[field] += r["per100g"][field] * g / 100.0
            sources.append(f"FDC {r['fdcId']} {r['description']} x {g:g} g")
        out.append({"id": case_id, "description": text,
                    "kcal": round(total["kcal"], 1), "protein_g": round(total["protein_g"], 1),
                    "carbs_g": round(total["carbs_g"], 1), "fat_g": round(total["fat_g"], 1),
                    "source": "; ".join(sources)})
    return out


def main():
    built = build_v3.build(rows(), build_v3.details_by_fdc_id(cache))
    with open(os.path.join(HERE, "v4.jsonl"), "w") as out:
        for row in built:
            out.write(json.dumps(row) + "\n")
            print(row["id"], row["kcal"], "|", row["source"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
