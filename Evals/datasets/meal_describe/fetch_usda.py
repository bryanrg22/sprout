#!/usr/bin/env python3
"""Fetch the per-100 g reference values the meal_describe dataset is built from.

Source: USDA FoodData Central, SR Legacy (public domain). One search request per
ingredient; responses are cached in usda_cache.json so a rebuild makes no request.
DEMO_KEY allows about 30 requests an hour; set FDC_API_KEY to use your own.
"""
import json, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "usda_cache.json")
KEY = os.environ.get("FDC_API_KEY", "DEMO_KEY")

# ingredient key -> search query (SR Legacy description wording)
QUERIES = {
    "banana": "Bananas, raw",
    "egg_hard_boiled": "Egg, whole, cooked, hard-boiled",
    "rice_white_cooked": "Rice, white, long-grain, regular, enriched, cooked",
    "chicken_breast_grilled": "Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, grilled",
    "olive_oil": "Oil, olive, salad or cooking",
    "oats_dry": "Cereals, oats, regular and quick, not fortified, dry",
    "milk_whole": "Milk, whole, 3.25% milkfat, with added vitamin D",
    "peanut_butter": "Peanut butter, smooth style, with salt",
    "bread_whole_wheat": "Bread, whole-wheat, commercially prepared",
    "avocado": "Avocados, raw, all commercial varieties",
    "salmon_cooked": "Fish, salmon, Atlantic, farmed, cooked, dry heat",
    "broccoli_cooked": "Broccoli, cooked, boiled, drained, without salt",
    "potato_baked": "Potatoes, baked, flesh and skin, without salt",
    "greek_yogurt_nonfat": "Yogurt, Greek, plain, nonfat",
    "almonds": "Nuts, almonds",
    "apple": "Apples, raw, with skin",
    "beef_85_cooked": "Beef, ground, 85% lean meat / 15% fat, patty, cooked, broiled",
    "spaghetti_cooked": "Spaghetti, cooked, enriched, without added salt",
    "cheddar": "Cheese, cheddar",
    "butter": "Butter, salted",
    "black_beans_cooked": "Beans, black, mature seeds, cooked, boiled, without salt",
    "sweet_potato_baked": "Sweet potato, cooked, baked in skin, flesh, without salt",
    "tortilla_flour": "Tortillas, ready-to-bake or -fry, flour, refrigerated",
    "blueberries": "Blueberries, raw",
}
WANT = {"Energy": "kcal", "Protein": "protein_g",
        "Carbohydrate, by difference": "carbs_g", "Total lipid (fat)": "fat_g"}


def fetch(query):
    url = "https://api.nal.usda.gov/fdc/v1/foods/search?" + urllib.parse.urlencode(
        {"api_key": KEY, "query": query, "dataType": "SR Legacy", "pageSize": 6})
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def main():
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    for key, query in QUERIES.items():
        if key in cache:
            continue
        data = fetch(query)
        hits = []
        for food in data.get("foods", []):
            vals = {}
            for n in food.get("foodNutrients", []):
                name = n.get("nutrientName")
                if name == "Energy" and n.get("unitName", "").upper() != "KCAL":
                    continue
                if name in WANT:
                    vals[WANT[name]] = n.get("value")
            hits.append({"fdcId": food["fdcId"], "description": food["description"], "per100g": vals})
        cache[key] = {"query": query, "hits": hits}
        json.dump(cache, open(CACHE, "w"), indent=1, sort_keys=True)
        time.sleep(0.4)
    for key, entry in cache.items():
        top = entry["hits"][0] if entry["hits"] else None
        exact = next((h for h in entry["hits"] if h["description"].lower() == entry["query"].lower()), None)
        print(("EXACT " if exact else "CHECK ") + key, "|", (exact or top or {}).get("fdcId"),
              "|", (exact or top or {}).get("description"), "|", (exact or top or {}).get("per100g"))


if __name__ == "__main__":
    sys.exit(main())
