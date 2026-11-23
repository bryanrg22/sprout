#!/usr/bin/env python3
"""Fetch the per-100 g reference values the meal_describe dataset is built from,
the household portion weights ("1 medium", "1 cup", "1 tbsp") v2 is built from, and the
label nutrients beyond the macros (fiber, sugars, saturated fat, sodium and the rest of
the Nutrition Facts panel) that v3 is built from.

Source: USDA FoodData Central, SR Legacy (public domain). One search request per
ingredient, then one food-detail request (up to 20 foods each) for the `foodPortions`
and the full `foodNutrients` of every ingredient that does not have them yet; responses
are cached in usda_cache.json so a rebuild makes no request. The detail is stored beside
`hits` and never changes it, so build_v1.py keeps producing the same file. DEMO_KEY allowed 10 requests an hour on 2026-11-22 (the limit is in
the X-Ratelimit-Limit response header); set FDC_API_KEY to use your own. A rate-limited
run stops, keeps what is cached, and can be re-run later.
"""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "usda_cache.json")
KEY = os.environ.get("FDC_API_KEY", "DEMO_KEY")
# `--details-only` fills in portions and label nutrients for what is already cached and
# searches for nothing new: one request for up to 20 foods.
DETAILS_ONLY = "--details-only" in sys.argv

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

# USDA nutrient number -> (dataset field, the unit the field is stated in). Matched by
# number, which is stable across data types; the names differ ("Sugars, total including
# NLEA" in SR Legacy, "Total Sugars" elsewhere). A number a record does not list is left
# out of the cache, and stays null in the dataset: absent is "USDA does not say", not 0.
DETAIL = {
    "291": ("fiber_g", "G"),            # Fiber, total dietary
    "269": ("sugars_g", "G"),           # Sugars, total
    "539": ("added_sugars_g", "G"),     # Sugars, added (rarely present in SR Legacy)
    "606": ("saturated_fat_g", "G"),    # Fatty acids, total saturated
    "605": ("trans_fat_g", "G"),        # Fatty acids, total trans
    "601": ("cholesterol_mg", "MG"),    # Cholesterol
    "307": ("sodium_mg", "MG"),         # Sodium, Na
    "306": ("potassium_mg", "MG"),      # Potassium, K
    "301": ("calcium_mg", "MG"),        # Calcium, Ca
    "303": ("iron_mg", "MG"),           # Iron, Fe
    "328": ("vitamin_d_mcg", "UG"),     # Vitamin D (D2 + D3)
}


def fetch(query):
    url = "https://api.nal.usda.gov/fdc/v1/foods/search?" + urllib.parse.urlencode(
        {"api_key": KEY, "query": query, "dataType": "SR Legacy", "pageSize": 6})
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def chosen(entry):
    """The hit a build script uses for an ingredient: the exact description, else the first."""
    exact = next((h for h in entry["hits"] if h["description"].lower() == entry["query"].lower()), None)
    return exact or (entry["hits"][0] if entry["hits"] else None)


def unit_name(raw):
    """The API's unit spelling as G / MG / UG: it writes micrograms as "µg", "UG" or "mcg"."""
    text = str(raw or "").strip().lower().replace("µ", "u").replace("μ", "u")
    return {"g": "G", "mg": "MG", "ug": "UG", "mcg": "UG"}.get(text, text.upper())


def fetch_details(fdc_ids):
    """Household portions and label nutrients per 100 g for up to 20 foods in one request.

    Returns {fdcId: {"portions": [...], "detail": {field: value}}}. A nutrient whose unit is
    not the one the field is stated in is skipped and reported, never converted silently.

    The response shape (`foodNutrients[].nutrient.number` as a string, `.nutrient.unitName`,
    `.amount`; `foodPortions[].amount/modifier/gramWeight/sequenceNumber`) is the published
    one: https://fdc.nal.usda.gov/api-spec/fdc_api.yaml. This function had not been run
    against the live API when it was written (the demo key was rate-limited); build_v3.py
    refuses a record for which it matched nothing.
    """
    url = "https://api.nal.usda.gov/fdc/v1/foods?" + urllib.parse.urlencode(
        [("api_key", KEY), ("format", "full")] + [("fdcIds", i) for i in fdc_ids])
    with urllib.request.urlopen(url, timeout=60) as r:
        foods = json.load(r)
    out = {}
    for food in foods:
        portions = sorted(food.get("foodPortions", []), key=lambda p: p.get("sequenceNumber", 0))
        detail = {}
        for n in food.get("foodNutrients", []):
            nutrient = n.get("nutrient", {})
            wanted = DETAIL.get(str(nutrient.get("number")))
            if not wanted or n.get("amount") is None:
                continue
            field, unit = wanted
            if unit_name(nutrient.get("unitName")) != unit:
                print("UNIT MISMATCH", food.get("fdcId"), field, nutrient.get("unitName"), "- skipped")
                continue
            detail[field] = n["amount"]
        out[food["fdcId"]] = {
            "portions": [{"amount": p.get("amount"), "modifier": p.get("modifier"),
                          "gramWeight": p.get("gramWeight")} for p in portions],
            "detail": detail,
        }
    return out


def save(cache):
    json.dump(cache, open(CACHE, "w"), indent=1, sort_keys=True)


def fill_details(cache):
    """Household portions and label nutrients of the hit each build script uses, 20 foods
    per request (both come back in the same food-detail response). False when rate-limited."""
    missing = [(key, chosen(entry)["fdcId"]) for key, entry in cache.items()
               if ("portions" not in entry or "detail" not in entry) and chosen(entry)]
    while missing:
        batch, missing = missing[:20], missing[20:]
        try:
            details = fetch_details([fdc_id for _, fdc_id in batch])
        except urllib.error.HTTPError as error:
            print("RATE LIMITED" if error.code == 429 else f"HTTP {error.code}",
                  "fetching food details - keeping the cache; run again later")
            return False
        for key, fdc_id in batch:
            if fdc_id in details:
                cache[key]["portions"] = {"fdcId": fdc_id, "items": details[fdc_id]["portions"]}
                cache[key]["detail"] = {"fdcId": fdc_id, "per100g": details[fdc_id]["detail"]}
        save(cache)
        time.sleep(0.4)
    return True


def main():
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    # Details first: the foods already cached are the ones the datasets use, and the demo
    # key's hourly allowance is smaller than the list of ingredients still to search for.
    limited = not fill_details(cache)
    for key, query in QUERIES.items():
        if key in cache or limited or DETAILS_ONLY:
            continue
        try:
            data = fetch(query)
        except urllib.error.HTTPError as error:
            if error.code == 429:
                print("RATE LIMITED at", key, "- keeping the cache; run again later")
                limited = True
                break
            # The API answers 400 to some query strings ("85% lean meat / 15% fat").
            print("SKIPPED", key, "| HTTP", error.code, "|", query)
            continue
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
        save(cache)
        time.sleep(0.4)

    if not limited:
        fill_details(cache)

    for key, entry in cache.items():
        top = entry["hits"][0] if entry["hits"] else None
        exact = next((h for h in entry["hits"] if h["description"].lower() == entry["query"].lower()), None)
        print(("EXACT " if exact else "CHECK ") + key, "|", (exact or top or {}).get("fdcId"),
              "|", (exact or top or {}).get("description"), "|", (exact or top or {}).get("per100g"),
              "|", len(entry.get("portions", {}).get("items", [])) if "portions" in entry else "no", "portions",
              "|", len(entry.get("detail", {}).get("per100g", {})) if "detail" in entry else "no", "detail nutrients")


if __name__ == "__main__":
    sys.exit(main())
