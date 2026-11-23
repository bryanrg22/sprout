#!/bin/bash
# Run one live evaluation: the app's real code path for a task, against every listed
# model, on a labelled dataset. Every run leaves a record directory under Evals/runs/.
#
#   Evals/run.sh <eval> "<provider:model[@effort]>[,...]" [repeats] [limit]
#
#   eval      MealDescribe | CoachToolChoice | DailyBrief
#   repeats   how many times each case runs per model (default 1; use 3 to see variance)
#   limit     only the first N cases (a cheap pilot); omit for the whole dataset
#
# THIS SPENDS MONEY on the keys in the environment (ANTHROPIC_API_KEY, OPENAI_API_KEY).
# The keys are read from the environment only; they are never written to a record.
set -euo pipefail

EVAL="${1:?eval name: MealDescribe | CoachToolChoice | DailyBrief}"
MODELS="${2:?models, e.g. anthropic:claude-haiku-4-5,openai:gpt-4.1-mini}"
REPEATS="${3:-1}"
LIMIT="${4:-}"
SIM="${SPROUT_SIM:-Victoria-Dev}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ID="$(date -u +%Y%m%d-%H%M%S)-${EVAL}"
OUT="$ROOT/Evals/runs/$RUN_ID"
DERIVED="${SPROUT_DERIVED_DATA:-$ROOT/build/evals-derived}"
mkdir -p "$OUT"

case "$MODELS" in *anthropic:*) : "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is not set}";; esac
case "$MODELS" in *openai:*)    : "${OPENAI_API_KEY:?OPENAI_API_KEY is not set}";; esac

cd "$ROOT"
xcodegen generate >/dev/null

python3 - "$OUT" "$EVAL" "$MODELS" "$REPEATS" "$LIMIT" <<'PY'
import hashlib, json, os, subprocess, sys, datetime
out, name, models, repeats, limit = sys.argv[1:6]
def sh(*a):
    try: return subprocess.check_output(a, text=True).strip()
    except Exception: return ""
datasets = {}
for base, _, files in os.walk("Evals/datasets"):
    for f in files:
        if f.endswith(".jsonl"):
            p = os.path.join(base, f)
            datasets[p] = hashlib.sha256(open(p, "rb").read()).hexdigest()
json.dump({
    "run_id": os.path.basename(out), "eval": name, "models": models.split(","),
    "repeats": int(repeats), "limit": int(limit) if limit else None,
    "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "commit": sh("git", "rev-parse", "HEAD"), "branch": sh("git", "rev-parse", "--abbrev-ref", "HEAD"),
    "dirty_files": [l for l in sh("git", "status", "--porcelain").splitlines() if l],
    "xcode": sh("xcodebuild", "-version").replace("\n", " "),
    "dataset_sha256": datasets,
}, open(os.path.join(out, "manifest.json"), "w"), indent=1)
PY

set +e
TEST_RUNNER_SPROUT_EVAL_MODELS="$MODELS" \
TEST_RUNNER_SPROUT_EVAL_REPEATS="$REPEATS" \
TEST_RUNNER_SPROUT_EVAL_LIMIT="$LIMIT" \
TEST_RUNNER_SPROUT_EVAL_ROOT="$ROOT/Evals" \
TEST_RUNNER_SPROUT_EVAL_OUT="$OUT" \
TEST_RUNNER_SPROUT_EVAL_CONCURRENCY="${SPROUT_EVAL_CONCURRENCY:-4}" \
TEST_RUNNER_ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
TEST_RUNNER_OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
xcodebuild test -project Victoria.xcodeproj -scheme VictoriaEvals \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DERIVED" \
  -only-testing:"VictoriaEvals/LiveEvals/test${EVAL}" \
  > "$OUT/xcodebuild.log" 2>&1
STATUS=$?
set -e

# The build log can echo the environment of the test runner; never keep it if it does.
if grep -q -E 'sk-ant-|sk-proj-|sk-[A-Za-z0-9]{32,}' "$OUT/xcodebuild.log"; then
  rm -f "$OUT/xcodebuild.log"
  echo "xcodebuild.log contained a key-shaped string and was deleted"
else
  tail -c 4000 "$OUT/xcodebuild.log" > "$OUT/xcodebuild-tail.log"; rm -f "$OUT/xcodebuild.log"
fi

python3 "$ROOT/Evals/summarize.py" "$OUT"
echo "xcodebuild exit: $STATUS"
echo "records: $OUT"
