#!/usr/bin/env python3
"""Write a CloudKit schema that has everything the app's models send.

    tooling/build_cloudkit_schema.py <exported.ckdb> docs/cloudkit/model-manifest.json --out merged.ckdb

Takes an exported schema and ADDS what is missing: a record type per model that has none,
and on the record types that exist, the fields the model has and the schema lacks. It never
removes or changes a definition that is already there. The mapping is Apple's, from
"Reading CloudKit Records for Core Data": the record type is CD_<Entity>, each attribute
is CD_<attribute>, every string, binary and transformable attribute also has
CD_<attribute>_ckAsset for values too large for a field, and CD_entityName names the entity.
"""
import argparse, json, re, sys

FIELD_TYPE = {"string": "STRING", "uuid": "STRING", "uri": "STRING", "double": "DOUBLE",
              "integer": "INT64", "boolean": "INT64", "date": "TIMESTAMP",
              "binary": "BYTES", "transformable": "BYTES"}
ASSET_COMPANION = {"string", "binary", "transformable"}
SYSTEM = ['"___createTime" TIMESTAMP', '"___createdBy"  REFERENCE', '"___etag"       STRING',
          '"___modTime"    TIMESTAMP', '"___modifiedBy" REFERENCE', '"___recordID"   REFERENCE']
GRANTS = ['GRANT WRITE TO "_creator"', 'GRANT CREATE TO "_icloud"', 'GRANT READ TO "_world"']


def index_for(kind):
    if kind == "ASSET":
        return ""
    return " QUERYABLE SEARCHABLE SORTABLE" if kind == "STRING" else " QUERYABLE SORTABLE"


def wanted(attributes):
    rows = {"CD_entityName": "STRING"}
    for attribute, kind in attributes.items():
        rows["CD_" + attribute] = FIELD_TYPE[kind]
        if kind in ASSET_COMPANION:
            rows["CD_" + attribute + "_ckAsset"] = "ASSET"
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("schema"); ap.add_argument("manifest"); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    text = open(a.schema).read()
    manifest = json.load(open(a.manifest))
    added_types, added_fields = [], 0

    for entity in sorted(manifest):
        record_type = "CD_" + entity
        rows = wanted(manifest[entity])
        pattern = re.compile(r"(    RECORD TYPE %s \(\n)(.*?)(\n    \);)" % re.escape(record_type), re.S)
        match = pattern.search(text)
        if match:
            body = match.group(2)
            have = set(re.findall(r'^\s+("?[\w]+"?)\s+[A-Z]', body, re.M))
            have = {h.strip('"') for h in have}
            new = [f"        {name} {kind}{index_for(kind)}," for name, kind in sorted(rows.items()) if name not in have]
            if new:
                added_fields += len(new)
                text = text[:match.start(2)] + "\n".join(new) + "\n" + body + text[match.end(2):]
        else:
            added_types.append(record_type)
            width = max(len(n) for n in rows) + 1
            lines = [f"        {name.ljust(width)}{kind}{index_for(kind)}" for name, kind in sorted(rows.items())]
            lines += ["        " + s for s in SYSTEM] + ["        " + g for g in GRANTS]
            block = f"    RECORD TYPE {record_type} (\n" + ",\n".join(lines) + "\n    );\n\n"
            # insert before the first record type that sorts after it, keeping the file ordered
            position = None
            for other in re.finditer(r"    RECORD TYPE (\S+) \(", text):
                if other.group(1) > record_type:
                    position = other.start(); break
            if position is None:
                position = text.rindex("};") if "};" in text else len(text)
            text = text[:position] + block + text[position:]

    open(a.out, "w").write(text)
    print(f"added {len(added_types)} record types and {added_fields} fields on existing types -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
