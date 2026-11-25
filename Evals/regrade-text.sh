#!/bin/bash
# Grade again the text past runs recorded, with the graders as they are now.
#
#   Evals/regrade-text.sh Evals/runs/<run> [Evals/runs/<run> ...]
#
# Covers the daily brief, insight line, weekly reflection, onboarding note, progress
# recap and memory fold. No model is called and nothing is spent. A run's records are not
# touched; the new scores go to <run>/regrade-text.json, and a table of old against new
# pass counts per candidate is printed. A reply the app discarded, or a failed call, keeps its old result.
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: $0 Evals/runs/<run> [...]"; exit 1; }
RUNS=""
for r in "$@"; do RUNS="${RUNS:+$RUNS:}$(cd "$r" && pwd)"; done
SIM="${SPROUT_SIM:-Sprout-Dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${SPROUT_DERIVED_DATA:-$ROOT/build/evals-derived}"
LOG="$(mktemp)"

cd "$ROOT"
xcodegen generate >/dev/null

# One more try when the simulator refuses to launch the test runner (see run.sh).
set +e
for ATTEMPT in 1 2; do
TEST_RUNNER_SPROUT_EVAL_REGRADE_TEXT="$RUNS" \
xcodebuild test -project Sprout.xcodeproj -scheme SproutEvals \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DERIVED" \
  -only-testing:"SproutEvals/TextRegradeRun/testTextRegrade" \
  > "$LOG" 2>&1
STATUS=$?
[ "$STATUS" -ne 0 ] && [ "$ATTEMPT" -eq 1 ] && grep -q "failed preflight checks" "$LOG" && continue
break
done
set -e
if [ "$STATUS" -ne 0 ]; then
  tail -n 40 "$LOG"; rm -f "$LOG"
  echo "regrade failed (xcodebuild exit $STATUS)"; exit 1
fi
rm -f "$LOG"

python3 - "$@" <<'PY'
import json, os, sys
for run in sys.argv[1:]:
    path = os.path.join(run, "regrade-text.json")
    if not os.path.exists(path):
        print(f"{run}: no text task to regrade"); continue
    d = json.load(open(path))
    print(f"\n{os.path.basename(run.rstrip('/'))} ({d['task']}, {d['dataset']})")
    print(f"  {'candidate':42} {'attempts':>8} {'old pass':>9} {'new pass':>9} {'not regradable':>15}")
    for cand, t in sorted(d["byCandidate"].items()):
        print(f"  {cand:42} {t['attempts']:>8} {t['oldPassed']:>9} {t['newPassed']:>9} {t['notRegradable']:>15}")
    flipped = [r for r in d["rows"] if r["oldPass"] != r["newPass"]]
    for r in flipped[:12]:
        print(f"    {'fail → pass' if r['newPass'] else 'pass → fail'}: {r['candidate']} {r['caseID']} #{r['repeatIndex']}")
    if len(flipped) > 12: print(f"    … and {len(flipped) - 12} more")
PY
