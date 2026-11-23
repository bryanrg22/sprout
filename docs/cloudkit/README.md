# CloudKit schema

The app's 20 models mirror to the user's private iCloud database (SwiftData on Core
Data's CloudKit mirror), and three public record types carry buddy sync. CloudKit has two
environments. A Debug build run from Xcode talks to **Development**, where a new record
type or field is created the first time the app saves one. TestFlight and App Store
builds talk to **Production**, where the schema is fixed: a record type or a field it
does not have is rejected, and the app is not told. Production changes only when someone
deploys Development to it in the CloudKit Console, and a deployed type or field can never
be removed.

## What is here

| File | What it is |
|---|---|
| `model-manifest.json` | Every entity and attribute the models will send, as Core Data sees them. `CloudKitSchemaManifestTests` fails if it does not match the models, so a model change cannot land without it. |
| `schema-production-<date>.ckdb` | Production as exported on that date. |
| `schema-development-<date>.ckdb` | Development as imported on that date. |
| `../../tooling/check_cloudkit_schema.py` | Compares an exported schema with the manifest; exits 1 and lists what is missing. |
| `../../tooling/build_cloudkit_schema.py` | Adds what is missing to an exported schema, changing nothing that is there. |

## Before any build goes to TestFlight

```bash
xcrun cktool export-schema --team-id <team> --container-id iCloud.com.bryanram.victoria \
  --environment production --output-file /tmp/production.ckdb
python3 tooling/check_cloudkit_schema.py /tmp/production.ckdb docs/cloudkit/model-manifest.json
```

It must exit 0. If it lists anything, Production is behind the models and that data will
not reach iCloud from the build.

## When a model changes

1. Regenerate the manifest: run `CloudKitSchemaManifestTests` with
   `TEST_RUNNER_SPROUT_WRITE_CLOUDKIT_MANIFEST=1`, and commit it.
2. Get the change into Development. Either run a Debug build on a device signed in to
   iCloud and use it (Core Data creates what it saves), or export Development, run
   `build_cloudkit_schema.py`, and `cktool import-schema --environment development --validate`.
3. Check Development with `check_cloudkit_schema.py`.
4. Deploy Development to Production in the CloudKit Console ("Deploy Schema Changes"),
   then run the check above against Production.

`cktool` needs a management token saved once with `xcrun cktool save-token`.
