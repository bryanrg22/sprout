#!/bin/bash
# Grade again the characters a past Avatar run saved, with the graders as they are now.
#
#   Evals/regrade-avatars.sh Evals/runs/<run>
#
# No model is called and nothing is spent. The run's records are not touched; the new
# scores are written to <run>/regrade-avatar.json together with the grader settings.
# The characters themselves are never committed (see Evals/datasets/avatar/photos/README.md),
# so this only works on the machine that made the run.
set -euo pipefail

RUN="${1:?a run directory, e.g. Evals/runs/20261123-100309-Avatar}"
RUN="$(cd "$RUN" && pwd)"
[ -d "$RUN/avatars" ] || { echo "no saved characters in $RUN/avatars"; exit 1; }
SIM="${SPROUT_SIM:-Sprout-Dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${SPROUT_DERIVED_DATA:-$ROOT/build/evals-derived}"
LOG="$(mktemp)"

cd "$ROOT"
xcodegen generate >/dev/null
rm -f "$RUN/regrade-avatar.json"

set +e
TEST_RUNNER_SPROUT_EVAL_REGRADE="$RUN" \
xcodebuild test -project Sprout.xcodeproj -scheme SproutEvals \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DERIVED" \
  -only-testing:"SproutEvals/AvatarRegrade/testAvatarRegrade" \
  > "$LOG" 2>&1
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] || [ ! -f "$RUN/regrade-avatar.json" ]; then
  tail -n 40 "$LOG"; rm -f "$LOG"
  echo "regrade failed (xcodebuild exit $STATUS)"; exit 1
fi
rm -f "$LOG"

python3 - "$RUN/regrade-avatar.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("graders:", d["graders"])
for i in d["images"]:
    s = i["scores"]
    print("%-34s %-44s pass=%-5s colours=%3d top_corners=%d clear=%.3f" % (
        i["candidate"], i["file"], i["pass"], s["distinct_colours"], s["transparent_top_corners"], s["transparent_share"]))
print("passed %d of %d" % (sum(i["pass"] for i in d["images"]), len(d["images"])))
PY
