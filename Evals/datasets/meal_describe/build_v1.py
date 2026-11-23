#!/usr/bin/env python3
"""Build meal_describe/v1.jsonl from the cached USDA values (no network).

Every case states its portions in grams, so the truth is arithmetic on USDA
SR Legacy per-100 g values and involves no judgement about portion size. That makes
v1 the floor of the task (food knowledge + arithmetic), not a test of portion
estimation; vague and photo cases need a different ground truth (see README.md).
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
cache = json.load(open(os.path.join(HERE, "usda_cache.json")))


def ref(key):
    entry = cache[key]
    exact = next((h for h in entry["hits"] if h["description"].lower() == entry["query"].lower()), None)
    return exact or entry["hits"][0]


# id, what the user types, [(ingredient key, grams)]
CASES = [
    ("banana-118g", "a medium banana, about 118 g", [("banana", 118)]),
    ("eggs-2-boiled", "two hard-boiled eggs, 100 g total", [("egg_hard_boiled", 100)]),
    ("rice-1cup", "one cup of cooked white rice (158 g)", [("rice_white_cooked", 158)]),
    ("chicken-150g", "150 g of grilled skinless chicken breast", [("chicken_breast_grilled", 150)]),
    ("olive-oil-1tbsp", "one tablespoon of olive oil (13.5 g)", [("olive_oil", 13.5)]),
    ("oats-40g-dry", "40 g of dry rolled oats", [("oats_dry", 40)]),
    ("milk-1cup", "a cup of whole milk (244 g)", [("milk_whole", 244)]),
    ("peanut-butter-2tbsp", "two tablespoons of smooth peanut butter (32 g)", [("peanut_butter", 32)]),
    ("bread-2-slices", "two slices of whole-wheat bread, 64 g total", [("bread_whole_wheat", 64)]),
    ("chicken-rice", "150 g grilled chicken breast with one cup (158 g) of cooked white rice",
     [("chicken_breast_grilled", 150), ("rice_white_cooked", 158)]),
    ("pb-sandwich", "a peanut butter sandwich: two slices of whole-wheat bread (64 g) with two tablespoons (32 g) of peanut butter",
     [("bread_whole_wheat", 64), ("peanut_butter", 32)]),
    ("oatmeal-milk-banana", "oatmeal made from 40 g dry oats and a cup (244 g) of whole milk, plus a medium banana (118 g)",
     [("oats_dry", 40), ("milk_whole", 244), ("banana", 118)]),
    ("eggs-toast", "three hard-boiled eggs (150 g) and two slices of whole-wheat toast (64 g)",
     [("egg_hard_boiled", 150), ("bread_whole_wheat", 64)]),
    ("rice-chicken-oil", "200 g cooked white rice with 120 g grilled chicken breast, cooked in one tablespoon (13.5 g) of olive oil",
     [("rice_white_cooked", 200), ("chicken_breast_grilled", 120), ("olive_oil", 13.5)]),
]

with open(os.path.join(HERE, "v1.jsonl"), "w") as out:
    for case_id, text, parts in CASES:
        total = {"kcal": 0.0, "protein_g": 0.0, "carbs_g": 0.0, "fat_g": 0.0}
        sources = []
        for key, grams in parts:
            r = ref(key)
            for field in total:
                total[field] += r["per100g"][field] * grams / 100.0
            sources.append(f"FDC {r['fdcId']} {r['description']} x {grams} g")
        row = {"id": case_id, "description": text,
               "kcal": round(total["kcal"], 1), "protein_g": round(total["protein_g"], 1),
               "carbs_g": round(total["carbs_g"], 1), "fat_g": round(total["fat_g"], 1),
               "source": "; ".join(sources)}
        out.write(json.dumps(row) + "\n")
        print(case_id, row["kcal"], row["protein_g"], row["carbs_g"], row["fat_g"])
