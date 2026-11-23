#!/usr/bin/env python3
"""Build meal_describe/v3.jsonl: the cases of v1 with the label nutrients added (no network).

v3 is v1's fourteen cases, unchanged (same ids, descriptions, calories, macros and source
records), plus eleven columns from the SAME USDA SR Legacy records: saturated fat, trans
fat, cholesterol, sodium, fiber, total sugars, added sugars, vitamin D, calcium, iron and
potassium. The rows are read from v1.jsonl itself, so the two files cannot drift apart, and
each ingredient's record is found by the FDC id in the row's `source`.

A column is the sum over the case's ingredients of (USDA value per 100 g) x grams / 100.
When the record of ANY ingredient does not list a nutrient, that column is null for the
case: USDA not listing a value is "not known", not zero, and a null column is not graded.
(SR Legacy lists added sugars for almost nothing, so that column is mostly null.) One value
is withheld on purpose: see WITHHELD.

The values come from the `detail` block fetch_usda.py caches. If an ingredient has no such
block yet (the fetch was rate-limited), this script stops and writes nothing: a dataset with
columns silently missing must not exist.

    python3 Evals/datasets/meal_describe/fetch_usda.py --details-only   # one request
    python3 Evals/datasets/meal_describe/build_v3.py
    python3 Evals/datasets/meal_describe/build_v3.py --self-test        # the arithmetic, on made-up records
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))

# column -> decimals kept. Grams to 0.1 like the macros in v1; milligrams of the minerals
# to 0.1 (iron is a few mg); micrograms of vitamin D to 0.01.
COLUMNS = {
    "saturated_fat_g": 1, "trans_fat_g": 1, "cholesterol_mg": 1, "sodium_mg": 1,
    "fiber_g": 1, "sugars_g": 1, "added_sugars_g": 1,
    "vitamin_d_mcg": 2, "calcium_mg": 1, "iron_mg": 1, "potassium_mg": 1,
}
# (FDC id, column) pairs left null although the record lists a value, because the value
# does not describe the food the case names. Kept in step with `withheldColumns` in
# VictoriaEvals/GraderTests.swift, which recomputes every column from the cache.
WITHHELD = {
    # v1 chose "Peanut butter, smooth style, WITHOUT SALT" (the search for "with salt" did
    # not return an exact match), but its two cases say only "smooth peanut butter". An
    # unsalted record's sodium is not the sodium of what the user typed, so it is not graded.
    172470: ["sodium_mg"],
}
PART = re.compile(r"FDC (\d+) .*? x ([0-9.]+) g$")


def details_by_fdc_id(cache):
    """fdcId -> per-100 g label nutrients, for every cached ingredient that has them."""
    return {entry["detail"]["fdcId"]: entry["detail"]["per100g"]
            for entry in cache.values() if "detail" in entry}


def parts_of(row):
    """[(fdcId, grams)] from a v1 row's source: 'FDC 173944 Bananas, raw x 118 g; ...'."""
    parts = []
    for text in row["source"].split("; "):
        match = PART.search(text)
        if not match:
            raise ValueError(f"{row['id']}: cannot read a source part: {text!r}")
        parts.append((int(match.group(1)), float(match.group(2))))
    return parts


def build(v1_rows, details):
    """The v3 rows, or raises LookupError naming the records that have no cached detail."""
    missing = sorted({fdc_id for row in v1_rows for fdc_id, _ in parts_of(row) if fdc_id not in details})
    if missing:
        raise LookupError("no cached label nutrients for FDC " + ", ".join(map(str, missing))
                          + " - run fetch_usda.py --details-only, then build again")
    # Every SR Legacy record of a whole food lists sodium and fiber. A record with neither
    # means the fetch matched nothing (a wrong nutrient number or unit), and a dataset built
    # from it would be all nulls that look like "USDA does not say".
    needed = sorted({fdc_id for row in v1_rows for fdc_id, _ in parts_of(row)})
    hollow = [fdc_id for fdc_id in needed
              if "sodium_mg" not in details[fdc_id] and "fiber_g" not in details[fdc_id]]
    if hollow:
        raise LookupError("the cached detail lists neither sodium nor fiber for FDC "
                          + ", ".join(map(str, hollow)) + " - check DETAIL in fetch_usda.py")
    out = []
    for row in v1_rows:
        new = dict(row)
        for column, places in COLUMNS.items():
            total = 0.0
            for fdc_id, grams in parts_of(row):
                value = None if column in WITHHELD.get(fdc_id, []) else details[fdc_id].get(column)
                if value is None:          # not listed (or withheld): the total is not known
                    total = None
                    break
                total += value * grams / 100.0
            new[column] = None if total is None else round(total, places)
        out.append(new)
    return out


def self_test():
    """The arithmetic and the two ways a column stays null, on made-up records."""
    rows = [{"id": "t", "description": "d", "kcal": 1, "protein_g": 1, "carbs_g": 1, "fat_g": 1,
             "source": "FDC 1 Food, one x 150 g; FDC 172470 Food two, 2 x 4 kinds x 50 g"}]
    assert parts_of(rows[0]) == [(1, 150.0), (172470, 50.0)], parts_of(rows[0])
    details = {1: {"fiber_g": 2.0, "sodium_mg": 10, "sugars_g": 0.0, "vitamin_d_mcg": 0.123},
               172470: {"fiber_g": 1.0, "sodium_mg": 400, "vitamin_d_mcg": 0.0}}
    row = build(rows, details)[0]
    assert row["fiber_g"] == 3.5, row                # 2.0 x 1.5 + 1.0 x 0.5
    assert row["sugars_g"] is None, row              # the second record does not list it
    assert row["sodium_mg"] is None, row             # listed, but withheld for record 172470
    assert row["vitamin_d_mcg"] == 0.18, row         # 0.1845 kept to two places
    assert row["added_sugars_g"] is None, row        # neither record lists it
    assert {k: row[k] for k in rows[0]} == rows[0], "the v1 columns are carried over unchanged"
    for broken, word in [({1: details[1]}, "no cached label nutrients for FDC 172470"),
                         ({1: details[1], 172470: {"calcium_mg": 5}}, "neither sodium nor fiber for FDC 172470")]:
        try:
            build(rows, broken)
        except LookupError as error:
            assert word in str(error), error
        else:
            raise AssertionError("a record with no usable cached detail must stop the build")
    print("OK")
    return 0


def main():
    if "--self-test" in sys.argv:
        return self_test()
    cache = json.load(open(os.path.join(HERE, "usda_cache.json")))
    v1_rows = [json.loads(line) for line in open(os.path.join(HERE, "v1.jsonl")) if line.strip()]
    try:
        rows = build(v1_rows, details_by_fdc_id(cache))
    except LookupError as error:
        print("NOT BUILT:", error)
        return 1
    with open(os.path.join(HERE, "v3.jsonl"), "w") as out:
        for row in rows:
            out.write(json.dumps(row) + "\n")
            known = [c for c in COLUMNS if row[c] is not None]
            print(row["id"], "|", ", ".join(f"{c}={row[c]}" for c in known) or "nothing known",
                  "| null:", ", ".join(c for c in COLUMNS if row[c] is None) or "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
