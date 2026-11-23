#!/usr/bin/env python3
"""Compare an exported CloudKit schema with what the app's models will send.

    xcrun cktool export-schema --team-id <team> --container-id iCloud.com.bryanram.victoria \
        --environment production --output-file /tmp/production.ckdb
    tooling/check_cloudkit_schema.py /tmp/production.ckdb docs/cloudkit/model-manifest.json

Core Data mirrors each model as the record type `CD_<Entity>` and each attribute as the
field `CD_<attribute>`. A record type or field the schema lacks is rejected in Production,
where the schema cannot be changed by the app, and the app is not told. This exits 1 and
lists every one that is missing or has the wrong type.

`--emit <file>` writes the missing definitions in schema language, for review; it is a
draft to compare with what Apple's own initializer creates, never something to import
into Production unread.
"""
import argparse, json, re, sys

# Core Data attribute type -> the CloudKit field type the mirror uses for it (the types
# of the fields Core Data itself created in the existing schema).
FIELD_TYPE = {"string": "STRING", "uuid": "STRING", "uri": "STRING", "double": "DOUBLE",
              "integer": "INT64", "boolean": "INT64", "date": "TIMESTAMP",
              "binary": "BYTES", "transformable": "BYTES"}
# Values too large for a field travel as an asset in a companion field.
ASSET_COMPANION = {"string", "binary", "transformable"}
INDEX = {"STRING": "QUERYABLE SEARCHABLE SORTABLE"}
DEFAULT_INDEX = "QUERYABLE SORTABLE"


def parse_schema(text):
    types = {}
    for match in re.finditer(r"RECORD TYPE (\S+) \((.*?)\n\s*\);", text, re.S):
        fields = {}
        for line in match.group(2).splitlines():
            m = re.match(r'\s+("?[\w]+"?)\s+([A-Z0-9_<>]+)', line)
            if m and not line.strip().startswith("GRANT"):
                fields[m.group(1).strip('"')] = m.group(2)
        types[match.group(1)] = fields
    return types


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("schema")
    ap.add_argument("manifest")
    ap.add_argument("--emit")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()

    schema = parse_schema(open(a.schema).read())
    manifest = json.load(open(a.manifest))

    missing_types, missing_fields, wrong_types, missing_assets = [], [], [], []
    for entity in sorted(manifest):
        record_type = "CD_" + entity
        have = schema.get(record_type)
        if have is None:
            missing_types.append(record_type)
            continue
        if "CD_entityName" not in have:
            missing_fields.append((record_type, "CD_entityName", "STRING"))
        for attribute, kind in sorted(manifest[entity].items()):
            field, want = "CD_" + attribute, FIELD_TYPE[kind]
            if field not in have:
                missing_fields.append((record_type, field, want))
            elif have[field] != want:
                wrong_types.append((record_type, field, have[field], want))
            if kind in ASSET_COMPANION and field + "_ckAsset" not in have:
                missing_assets.append((record_type, field + "_ckAsset"))

    total_fields = sum(len(v) for v in manifest.values())
    print(f"models: {len(manifest)} record types, {total_fields} attributes")
    print(f"schema: {len([t for t in schema if t.startswith('CD_')])} CD_ record types present")
    print(f"missing record types ({len(missing_types)}): {', '.join(missing_types) or 'none'}")
    print(f"missing fields on existing types ({len(missing_fields)}):")
    for record_type, field, want in missing_fields:
        print(f"  {record_type}.{field} {want}")
    print(f"fields with the wrong type ({len(wrong_types)}):")
    for record_type, field, have_type, want in wrong_types:
        print(f"  {record_type}.{field} is {have_type}, the model sends {want}")
    print(f"asset companions absent on existing types ({len(missing_assets)}): "
          "large strings, photos and blobs on these fields cannot sync")
    for record_type, field in missing_assets[:12]:
        print(f"  {record_type}.{field}")
    if len(missing_assets) > 12:
        print(f"  ... and {len(missing_assets) - 12} more")

    if a.emit:
        with open(a.emit, "w") as out:
            out.write("// DRAFT generated from docs/cloudkit/model-manifest.json. Compare with what\n"
                      "// NSPersistentCloudKitContainer.initializeCloudKitSchema creates in Development\n"
                      "// before trusting it. Never import into Production unread.\n\n")
            for entity in sorted(manifest):
                rows = [("CD_entityName", "STRING")]
                for attribute, kind in sorted(manifest[entity].items()):
                    rows.append(("CD_" + attribute, FIELD_TYPE[kind]))
                    if kind in ASSET_COMPANION:
                        rows.append(("CD_" + attribute + "_ckAsset", "ASSET"))
                width = max(len(name) for name, _ in rows) + 1
                out.write(f"RECORD TYPE CD_{entity} (\n")
                for name, kind in sorted(rows):
                    index = "" if kind == "ASSET" else " " + INDEX.get(kind, DEFAULT_INDEX)
                    out.write(f"    {name.ljust(width)}{kind}{index},\n")
                out.write('    GRANT WRITE TO "_creator",\n    GRANT CREATE TO "_icloud",\n    GRANT READ TO "_world"\n);\n\n')
        print("draft written to", a.emit)

    return 1 if (missing_types or missing_fields or wrong_types) else 0


if __name__ == "__main__":
    sys.exit(main())
