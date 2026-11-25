#!/usr/bin/env python3
"""Builds meal_photo/v1.jsonl: 30 plates from Nutrition5k with their measured truth.

    python3 -I Evals/datasets/meal_photo/build_v1.py <dir with dish_metadata_cafe1.csv and depth_test_ids.txt>

Source: Nutrition5k (Thames et al., "Nutrition5k: Towards Automatic Nutritional Understanding
of Generic Food", CVPR 2021), released under CC BY 4.0; see ATTRIBUTION.md. Every plate was
weighed ingredient by ingredient as it was assembled in a cafeteria, and its calories and
macros are the sum of those ingredients (USDA values per gram), which is the truth here.

Which plates:
- Only cafe 1's `depth_test` dishes: they have an overhead photo (the `rgb_*` split lists
  include dishes that do not) and are in the dataset's own test split; cafe 2 lists no totals.
- Screened for label noise: the total equals the sum of the ingredients (to 1%), calories per
  gram between 0.3 and 9, at least 40 g and 50 kcal and at most 1,500 kcal.
- 30 chosen with a fixed seed, six from each fifth of the screened plates ranked by calories,
  so small and large plates are both in it.

The photo of each plate is fetched separately (the URL is in each row) and converted to JPEG,
the format the app uploads. This script writes only the JSONL; it is deterministic for a
given metadata file.
"""
import csv, json, os, random, sys

def main():
    src = sys.argv[1]
    ids = {l.strip() for l in open(os.path.join(src, "depth_test_ids.txt")) if l.strip()}
    plates = []
    for row in csv.reader(open(os.path.join(src, "dish_metadata_cafe1.csv"))):
        dish = row[0]
        if dish not in ids:
            continue
        kcal, mass, fat, carb, protein = map(float, row[1:6])
        rest = row[6:]
        if len(rest) % 7:
            continue
        ingredients = []
        for i in range(0, len(rest), 7):
            g = rest[i:i + 7]
            ingredients.append({"name": g[1], "grams": round(float(g[2]), 1), "kcal": round(float(g[3]), 1)})
        summed = sum(x["kcal"] for x in ingredients)
        if not (40 <= mass and 50 <= kcal <= 1500 and 0.3 <= kcal / mass <= 9):
            continue
        if abs(summed - kcal) > 0.01 * kcal + 1:
            continue
        plates.append({"id": dish, "kcal": round(kcal, 1), "mass_g": round(mass, 1), "fat_g": round(fat, 1),
                       "carbs_g": round(carb, 1), "protein_g": round(protein, 1), "ingredients": ingredients})
    plates.sort(key=lambda p: (p["kcal"], p["id"]))
    rng = random.Random(5)
    chosen = []
    fifth = len(plates) / 5
    for k in range(5):
        band = plates[int(k * fifth):int((k + 1) * fifth)]
        chosen += rng.sample(band, 6)
    chosen.sort(key=lambda p: p["id"])
    base = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset/imagery/realsense_overhead"
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "v1.jsonl")
    with open(out, "w") as f:
        for p in chosen:
            p["photo"] = f"photos/{p['id']}.jpg"
            p["source_url"] = f"{base}/{p['id']}/rgb.png"
            f.write(json.dumps(p, sort_keys=True) + "\n")
    print(f"{len(plates)} plates passed the screen; {len(chosen)} written to {out}")
    print("kcal:", sorted(p["kcal"] for p in chosen))

if __name__ == "__main__":
    main()
