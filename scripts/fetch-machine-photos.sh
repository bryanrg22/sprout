#!/usr/bin/env bash
#
# fetch-machine-photos.sh
# -----------------------
# Downloads clean, white-background STUDIO PRODUCT SHOTS of the gym machines in
# MachineCatalog.swift and installs each as an Xcode asset-catalog imageset named
# `machine_<key>` under Victoria/Assets.xcassets/.
#
# The app (Services/MachineCatalog.swift) currently renders each machine with an
# SF Symbol (`machine.icon`). Any machine WITHOUT a `machine_<key>` imageset simply
# keeps falling back to its symbol, so it is always safe to ship a partial set and
# add the rest later — the TODO rows at the bottom are intentionally skipped.
#
# Idempotent: a machine whose .png already exists AND is a valid image is skipped.
# Run again any time to fill in the gaps.
#
#   Usage:   bash scripts/fetch-machine-photos.sh
#   Requires: bash, curl, file.  Optional: sips (macOS) to downscale to <=500px.
#
# ---------------------------------------------------------------------------
# IMAGE SOURCES / ATTRIBUTION
# ---------------------------------------------------------------------------
# These are MANUFACTURER / RETAILER product shots used purely for a PERSONAL,
# two-user iOS app (not redistributed, not commercial). Brands were chosen to
# match the two target gyms: HOIST (ROC-IT) and Hammer Strength / Life Fitness.
# Cardio is any clean commercial product shot. Source per machine:
#
#   chest_press         shop.lifefitness.com  Hammer Strength Select Chest Press
#   bench_press         shop.lifefitness.com  Hammer Strength Flat Bench
#   pec_deck            shop.lifefitness.com  Hammer Strength Select Pectoral Fly
#   incline_chest_press shop.lifefitness.com  Hammer Strength Plate-Loaded Iso-Lateral Incline Press
#   cable_crossover     shop.lifefitness.com  Life Fitness Adjustable Cable Crossover
#   lat_pulldown        shop.lifefitness.com  Hammer Strength Select Lat Pulldown
#   seated_cable_row    shop.lifefitness.com  Hammer Strength Select Seated Row
#   t_bar_row           shop.lifefitness.com  Hammer Strength Plate-Loaded T-Bar Row
#   assisted_pull_up    shop.lifefitness.com  Hammer Strength Select Assist Dip/Chin
#   back_extension      shop.lifefitness.com  Hammer Strength Select Back Extension
#   shoulder_press      shop.lifefitness.com  Hammer Strength Select Shoulder Press
#   lateral_raise       shop.lifefitness.com  Hammer Strength Select Lateral Raise
#   overhead_press      ddbarbell.com         Hoist Fitness ROC-IT Shoulder Press RS-1501
#   reverse_pec_deck    shop.lifefitness.com  Hammer Strength Select Pectoral Fly / Rear Deltoid
#   bicep_curl          ddbarbell.com         Hoist Fitness ROC-IT Biceps Curl RS-1102
#   tricep_pushdown     ddbarbell.com         Hoist Fitness ROC-IT Triceps Extension RS-1103
#   preacher_curl       shop.lifefitness.com  Hammer Strength Seated Arm Curl bench
#   assisted_dip        ultimatefitnessoutlet.com  Hoist ROC-IT Seated Dip RS-1101
#   leg_press           ddbarbell.com         Hoist Fitness ROC-IT Leg Press RS-1403  (verified seed URL)
#   squat_rack          shop.lifefitness.com  Hammer Strength HD Athletic NX Power Rack
#   leg_extension       shop.lifefitness.com  Hammer Strength Select Leg Extension
#   leg_curl            shop.lifefitness.com  Hammer Strength Select Seated Leg Curl
#   hack_squat          shop.lifefitness.com  Hammer Strength Plate-Loaded Hack Squat
#   calf_raise          shop.lifefitness.com  Hammer Strength Select Standing Calf
#   smith_machine       shop.lifefitness.com  Hammer Strength Smith Machine
#   hip_thrust          shop.lifefitness.com  Hammer Strength Plate-Loaded Glute Drive
#   hip_abductor        shop.lifefitness.com  Hammer Strength Select Hip Abduction
#   hip_adductor        shop.lifefitness.com  Hammer Strength Select Hip Adduction
#   ab_crunch_machine   shop.lifefitness.com  Hammer Strength Select Abdominal Crunch
#   captains_chair      xmarkfitness.com      XMark Vertical Knee Raise / Captain's Chair
#   roman_chair         valorfitness.com      Valor Fitness CB-13 Back Extension / Roman Chair
#   treadmill           shop.lifefitness.com  Life Fitness Club Series+ Treadmill
#   bike                shop.lifefitness.com  Life Fitness Club Series+ Upright Lifecycle Bike
#   elliptical          shop.lifefitness.com  Life Fitness E1 Elliptical Cross-Trainer
#   rower               roguefitness.com      Concept2 RowErg (Model D) rower
#   stairmaster         thefitnessoutlet.com  StairMaster 8G Gauntlet StepMill
#
# Source domains used: shop.lifefitness.com, ddbarbell.com, ultimatefitnessoutlet.com,
# xmarkfitness.com, valorfitness.com, roguefitness.com (assets.roguefitness.com),
# thefitnessoutlet.com.
# ---------------------------------------------------------------------------

set -u

# --- Locate the asset catalog (script lives in <repo>/scripts) ---------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DIR="$REPO_ROOT/Victoria/Assets.xcassets"

if [ ! -d "$ASSETS_DIR" ]; then
  echo "✗ Asset catalog not found at: $ASSETS_DIR"
  echo "  (run this from the repo that contains Victoria/Assets.xcassets)"
  exit 1
fi

# --- Tool checks -------------------------------------------------------------
command -v curl >/dev/null 2>&1 || { echo "✗ 'curl' is required"; exit 1; }
command -v file >/dev/null 2>&1 || { echo "✗ 'file' is required"; exit 1; }
HAVE_SIPS=0
if command -v sips >/dev/null 2>&1; then HAVE_SIPS=1; fi

# --- The machine -> source-image map (key|url) -------------------------------
# Each URL was researched to be a DIRECT image link (cdn .png/.jpg/.webp or a
# Shopify /cdn/shop/files/ URL) showing a clean product shot on a white/transparent
# background — no person, no busy gym scene.
PAIRS=(
  "chest_press|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-selectchest-press-charcoal-black-1000x1000.jpg?v=1748945070&width=1000"
  "bench_press|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-benches-and-racksflat-bench-charcoal-black-1000x1000.jpg?v=1748945116&width=1000"
  "pec_deck|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-selectpectoral-flybase_charcoalframe_blackuph_1000x1000_f03bfdfd-af28-4b12-b79f-cb9089223fd7.jpg?v=1748945077&width=1000"
  "incline_chest_press|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-incline-press-charcoal-black-1000x1000.jpg?v=1748945164&width=1000"
  "cable_crossover|https://shop.lifefitness.com/cdn/shop/files/life-fitness-cable-crossover-1000x1000.jpg?v=1748945057&width=1000"
  "lat_pulldown|https://shop.lifefitness.com/cdn/shop/files/outlet-hammer-strength-select-lat-pulldown-charcoal-black-1000x1000.jpg?v=1748945131&width=1000"
  "seated_cable_row|https://shop.lifefitness.com/cdn/shop/files/outlet-hammer-strength-select-seated-row-charcoal-black-1000x1000.jpg?v=1746126337&width=1000"
  "t_bar_row|https://shop.lifefitness.com/cdn/shop/files/t-bar-row-charcoal-1000x1000.jpg?v=1748945102&width=1000"
  "assisted_pull_up|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-select-dip-chin-machine-charcoal-black-1000x1000.jpg?v=1748945293&width=1000"
  "back_extension|https://shop.lifefitness.com/cdn/shop/files/outlet-hammer-strength-selectback-extension-charcoal-black-1000x1000.jpg?v=1748945071&width=1000"
  "shoulder_press|https://shop.lifefitness.com/cdn/shop/files/outlet-hammer-strength-select-shoulder-press-charcoal-black-1000x1000.jpg?v=1748945064&width=1000"
  "lateral_raise|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-selectlateral-raisebase_charcoalframe_blackuph_1000x1000_392bf7fc-4400-4c3d-b056-b9847b89dacf.jpg?v=1748945066&width=1000"
  "overhead_press|https://ddbarbell.com/cdn/shop/files/RS-1501-Shoulder-Press-Selectorized-ROC-IT-Black.webp?v=1695499371&width=800"
  "reverse_pec_deck|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-select-pectoral-fly-rear-deltoid-charcoal-black-1000x1000.jpg?v=1748945069&width=1000"
  "bicep_curl|https://ddbarbell.com/cdn/shop/files/RS-1102-Biceps-Curl-Selectorized-ROC-IT-Black.png?v=1690564127&width=800"
  "tricep_pushdown|https://ddbarbell.com/cdn/shop/files/RS-1103-Triceps-Extension-Selectorized-ROC-IT-Black.png?v=1690566314&width=800"
  "preacher_curl|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-arm-curl-bench-charcoal-black-1000x1000.jpg?v=1748945172&width=1000"
  "assisted_dip|https://www.ultimatefitnessoutlet.com/cdn/shop/products/HOIST_TRICEP_1_1024x1024.jpg?v=1524169371"
  "leg_press|https://ddbarbell.com/cdn/shop/files/RS-1403-Leg-Press-Selectorized-ROC-IT-Black.png?v=1691094750&width=800"
  "squat_rack|https://shop.lifefitness.com/cdn/shop/files/HD_Athletic_NX_-_Standard_Power_Rack_-_Iso-charcoal-1000x1000.jpg?v=1748945132&width=1000"
  "leg_extension|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-select-leg-extension-charcoal-black-1000x1000.jpg?v=1748945140&width=1000"
  "leg_curl|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-selectseated-leg-curlbase_charcoalframe_blackuph_1000x1000_142fbee1-487a-4f8d-b616-4b5f53d23d8b.jpg?v=1748945139&width=1000"
  "hack_squat|https://shop.lifefitness.com/cdn/shop/files/plate-loaded-hammer-strength-hack-squat-black.jpg?v=1748945156&width=960"
  "calf_raise|https://shop.lifefitness.com/cdn/shop/files/outlet-hammer-strength-select-standing-calf-charcoal-black-1000x1000.jpg?v=1748945065&width=1000"
  "smith_machine|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-benches-and-rackssmith-machine-charcoal1000x1000.jpg?v=1748945163&width=1000"
  "hip_thrust|https://shop.lifefitness.com/cdn/shop/files/HS_GLUTE_360_0057_charcoalframe_blackuph_1000x1000_965d0bdc-12be-4762-a055-821aa5673f25.jpg?v=1748945148&width=1000"
  "hip_abductor|https://shop.lifefitness.com/cdn/shop/files/outlet-hammer-strength-select-hip-abduction-charcoal-black-1000x01000.jpg?v=1748945068&width=1000"
  "hip_adductor|https://shop.lifefitness.com/cdn/shop/files/outlet-hammer-strength-select-hip-adduction-charcoal-black-1000x01000.jpg?v=1748945067&width=1000"
  "ab_crunch_machine|https://shop.lifefitness.com/cdn/shop/files/hammer-strength-selectabdominal-crunch-charcoal-black-1000x1000.jpg?v=1748945075&width=1000"
  "captains_chair|https://xmarkfitness.com/cdn/shop/files/4437.2-BLACK-1.jpg?v=1718889983&width=800"
  "roman_chair|https://valorfitness.com/cdn/shop/files/CB-13_MainMain.jpg?v=1755544092&width=800"
  "treadmill|https://shop.lifefitness.com/cdn/shop/files/club-series-treadmill-life-fitness-black-se4-console-black-onyx-1000x1000.jpg?v=1775831264&width=1000"
  "bike|https://shop.lifefitness.com/cdn/shop/files/club-series-plus-upright-bike-se4-black-1000x1000.jpg?v=1769114408&width=1000"
  "elliptical|https://shop.lifefitness.com/cdn/shop/files/E1-Crosstrainer-TrackConnect-console-standardview.jpg?v=1748945392&width=1000"
  "rower|https://assets.roguefitness.com/f_auto,q_auto,c_limit,w_768,b_rgb:f8f8f8/catalog/Conditioning/Endurance%20/Concept%202%20Rowers/C2ROWER-CONFIG/C20003-H-2_la1u4n.png"
  "stairmaster|https://thefitnessoutlet.com/cdn/shop/files/8gside.webp?v=1751314584&width=800"
)

# --- Machines deliberately SKIPPED (no machine = no product shot) -------------
# These are bodyweight or free-weight movements; the app keeps using its SF Symbol.
# Listed here for completeness so the count below is honest.
#   TODO push_up=Push-up                 (bodyweight)
#   TODO deadlift=Deadlift               (free weight / barbell)
#   TODO cable_lateral_raise=Cable lateral raise  (cable attachment, no distinct machine)
#   TODO cable_curl=Cable curl           (cable attachment, no distinct machine)
#   TODO skullcrusher=Skullcrusher       (free weight)
#   TODO cable_crunch=Cable crunch       (cable attachment, no distinct machine)

# --- Helpers -----------------------------------------------------------------

# True if $1 is a real raster image per `file`.
is_image() {
  file -b "$1" 2>/dev/null | grep -qiE 'image|bitmap|PNG|JPEG|JPG|WebP'
}

write_contents_json() {
  # $1 = imageset dir, $2 = png filename
  cat > "$1/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$2",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

# --- Main loop ---------------------------------------------------------------
echo "Installing machine photos into: $ASSETS_DIR"
[ "$HAVE_SIPS" -eq 1 ] && echo "sips found — images will be downscaled to <=500px." \
                       || echo "sips NOT found — images installed at source size."
echo

total=${#PAIRS[@]}
ok=0
skipped=0
failed=0

for pair in "${PAIRS[@]}"; do
  key="${pair%%|*}"
  url="${pair#*|}"

  imageset="$ASSETS_DIR/machine_${key}.imageset"
  png="$imageset/machine_${key}.png"

  # Idempotent: already have a valid image -> skip.
  if [ -f "$png" ] && is_image "$png"; then
    echo "• $key — already present, skipping"
    skipped=$((skipped + 1))
    ok=$((ok + 1))
    continue
  fi

  mkdir -p "$imageset"
  write_contents_json "$imageset" "machine_${key}.png"

  # Download to a temp file first so a half-written file never lands as the asset.
  tmp="$(mktemp "${TMPDIR:-/tmp}/machine_${key}.XXXXXX")"
  if ! curl -sSL --fail -m 30 \
        -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" \
        -o "$tmp" "$url"; then
    echo "✗ $key — download failed ($url)"
    rm -f "$tmp"
    rm -rf "$imageset"
    failed=$((failed + 1))
    continue
  fi

  # Verify we actually got an image (not an HTML error / 404 page).
  if ! is_image "$tmp"; then
    echo "✗ $key — downloaded file is not an image (got $(file -b "$tmp" 2>/dev/null | cut -c1-40))"
    rm -f "$tmp"
    rm -rf "$imageset"
    failed=$((failed + 1))
    continue
  fi

  mv "$tmp" "$png"

  # Downscale in place to keep the app bundle small (max 500px on the long edge).
  if [ "$HAVE_SIPS" -eq 1 ]; then
    sips -Z 500 "$png" >/dev/null 2>&1 || true
    # sips can rewrite a .webp/.jpg payload while keeping the .png name; re-verify.
    if ! is_image "$png"; then
      echo "✗ $key — image became invalid after resize, removing"
      rm -rf "$imageset"
      failed=$((failed + 1))
      continue
    fi
  fi

  echo "✓ $key"
  ok=$((ok + 1))
done

# --- Post-process: white background -> transparent + tight-crop ---------------
# The product shots ship on white; cutting the white to transparent + cropping
# tight lets the machine sit big and clean on any tile (no white box). Needs
# python3 + Pillow; skipped with a warning if unavailable (white-bg still works).
if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" >/dev/null 2>&1; then
  echo
  echo "Cutting white backgrounds (transparent + crop)…"
  python3 - "$ASSETS_DIR" <<'PY'
import sys, glob
from PIL import Image
THRESH = 238
n = 0
for p in glob.glob(sys.argv[1] + "/machine_*.imageset/*.png"):
    im = Image.open(p).convert("RGBA")
    im.putdata([(255, 255, 255, 0) if (r > THRESH and g > THRESH and b > THRESH) else (r, g, b, a)
                for (r, g, b, a) in im.getdata()])
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    im.save(p)
    n += 1
print(f"  transparent-cut {n} images")
PY
else
  echo "NOTE: python3 + Pillow not found — skipping the transparent-background step"
  echo "      (images still install with their white background)."
fi

echo
echo "----------------------------------------"
echo "Done. $ok/$total machine photos in place ($skipped already present, $failed failed)."
echo "Machines left as SF-symbol fallbacks (TODO): push_up, deadlift,"
echo "cable_lateral_raise, cable_curl, skullcrusher, cable_crunch."
echo
echo "Next: open the project in Xcode so it picks up the new imagesets, then have"
echo "the UI prefer UIImage(named:\"machine_<key>\") and fall back to the SF Symbol."
