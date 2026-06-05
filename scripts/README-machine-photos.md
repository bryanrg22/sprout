# Machine photos

`fetch-machine-photos.sh` downloads clean, white-background **studio product shots**
of the gym machines in `Victoria/Services/MachineCatalog.swift` and installs each as
an Xcode imageset named `machine_<key>` under `Victoria/Assets.xcassets/`.

## Run it

```bash
bash scripts/fetch-machine-photos.sh
```

Requirements: `bash`, `curl`, `file`. Optional `sips` (ships with macOS) downscales
each image to a max of 500px on the long edge to keep the app bundle small.

The script is **idempotent**: a machine whose `.png` already exists and is a valid
image is skipped, so you can re-run it any time to fill in gaps. It prints `✓`/`✗`/`•`
per machine and a final success count, and it cleans up (removes the imageset) for
any URL that fails or returns a non-image (e.g. a 404 HTML page).

## What you get

Real product images for **36** machines. Brands were chosen to match the two target
gyms — **HOIST (ROC-IT)** and **Hammer Strength / Life Fitness** — with any clean
commercial shot for cardio. Per-machine source URLs (attribution) are in the header
comment of the script.

These are manufacturer / retailer product shots used purely for a **personal,
two-user app** (not redistributed, not commercial).

### Source domains

- `shop.lifefitness.com` (official Life Fitness / Hammer Strength store — most strength + cardio)
- `ddbarbell.com` (Hoist ROC-IT: leg press, shoulder press, biceps curl, triceps extension)
- `ultimatefitnessoutlet.com` (Hoist seated dip)
- `xmarkfitness.com` (captain's chair / vertical knee raise)
- `valorfitness.com` (roman chair / back extension)
- `roguefitness.com` / `assets.roguefitness.com` (Concept2 rower)
- `thefitnessoutlet.com` (StairMaster stepmill)

## Skipped (SF-symbol fallback)

These stay as their SF Symbol because they're bodyweight or free-weight movements
with no distinct machine to photograph (listed as `# TODO` in the script):

`push_up`, `deadlift`, `cable_lateral_raise`, `cable_curl`, `skullcrusher`,
`cable_crunch`.

## Hooking the images up in the UI

The app today renders every machine with `Image(systemName: machine.icon)`. Once the
imagesets exist, prefer the photo and fall back to the symbol, e.g.:

```swift
if UIImage(named: "machine_\(machine.key)") != nil {
    Image("machine_\(machine.key)").resizable().scaledToFit()
} else {
    Image(systemName: machine.icon)
}
```

So machines without a photo (the TODO list above, or any that fail to download) keep
working unchanged.
