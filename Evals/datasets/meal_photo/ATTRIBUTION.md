# Meal photos: Nutrition5k

The 30 photos in `photos/` and the truth in `v1.jsonl` come from **Nutrition5k**
(Google Research), released under the
[Creative Commons Attribution 4.0 International license](https://creativecommons.org/licenses/by/4.0/):

> Quin Thames, Arjun Karpur, Wade Norris, Fangting Xia, Liviu Panait, Tobias Weyand and
> Jack Sim. "Nutrition5k: Towards Automatic Nutritional Understanding of Generic Food."
> CVPR 2021. https://arxiv.org/abs/2103.03375 — data: https://github.com/google-research-datasets/Nutrition5k

**Changes made here:** 30 plates chosen from cafe 1's `depth_test` split (see
`build_v1.py` for the screen and the seed); each overhead `rgb.png` (640×480) converted to
JPEG at quality 85 with `sips`; the truth copied from `dish_metadata_cafe1.csv` (totals, and
each ingredient's name, grams and calories), rounded to one decimal place. Every photo was
looked at: all 30 show a whole plate of food. The source URL of each photo is in its row.

Re-fetching (about 11 MB of PNGs and the 2.2 MB metadata file):

```bash
B=https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset
curl -O "$B/dish_ids/splits/depth_test_ids.txt" -O "$B/metadata/dish_metadata_cafe1.csv"
python3 -I Evals/datasets/meal_photo/build_v1.py .
```
