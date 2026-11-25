#!/bin/bash
# Run one live evaluation: the app's real code path for a task, against every listed
# model, on a labelled dataset. Every run leaves a record directory under Evals/runs/.
#
#   Evals/run.sh <eval> "<provider:model[@effort]>[,...]" [repeats] [limit]
#
#   eval      MealDescribe | MealDescribeHousehold | MealPhoto | CoachToolChoice | DailyBrief | Avatar
#             | InsightLine | WeeklyReflection | OnboardingNote | MemoryFold    (cheap-tier wording tasks)
#             | ProgressSummary | FoodSuggestions | CoachPrompts | ChecklistPlan (structured tasks: a forced
#               tool call, or the JSON-schema format on the models that refuse one, EVAL_REPORT 30)
#             (Avatar: image models; the @suffix is the image quality, e.g.
#              "openai:gpt-image-2.6-flare@low,openai:gpt-image-2.6-sunburst@medium";
#              the cases are the photos in Evals/datasets/avatar/photos/, see its README)
#             (Anthropic text models: "anthropic:<model>@default" leaves thinking at the model's own
#              default on the plain-text tasks, where the app turns it off; use it to measure the difference)
#   repeats   how many times each case runs per model (default 1; use 3 to see variance)
#   limit     only the first N cases (a cheap pilot); omit for the whole dataset
#   SPROUT_EVAL_CASES=id1,id2 in the environment runs only those cases (to chase one failure)
#   SPROUT_EVAL_BASELINE=<provider:model> adds a paired comparison with that candidate to the summary
#
# THIS SPENDS MONEY on the keys in the environment (ANTHROPIC_API_KEY, OPENAI_API_KEY).
# The keys are read from the environment only; they are never written to a record.
set -euo pipefail

EVAL="${1:?eval name: one of those listed at the top of this script, e.g. MealDescribe or InsightLine}"
MODELS="${2:?models, e.g. anthropic:claude-haiku-4-5,openai:gpt-4.1-mini}"
REPEATS="${3:-1}"
LIMIT="${4:-}"
SIM="${SPROUT_SIM:-Sprout-Dev}"

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
        # A labelled dataset, or (for the Avatar evaluation) one of its photos.
        if f.endswith(".jsonl") or (base.endswith("avatar/photos") and f != "README.md"):
            p = os.path.join(base, f)
            datasets[p] = hashlib.sha256(open(p, "rb").read()).hexdigest()
json.dump({
    "run_id": os.path.basename(out), "eval": name, "models": models.split(","),
    "repeats": int(repeats), "limit": int(limit) if limit else None,
    "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "commit": sh("git", "rev-parse", "HEAD"), "branch": sh("git", "rev-parse", "--abbrev-ref", "HEAD"),
    "dirty_files": [l for l in sh("git", "status", "--porcelain").splitlines() if l],
    "xcode": sh("xcodebuild", "-version").replace("\n", " "),
    # What the answers depend on, pinned: the app's code (its prompts), the harness and its
    # graders, and the price table. Git tree ids, so equal ids mean byte-identical folders;
    # they describe the commit, so read them together with dirty_files.
    "app_tree": sh("git", "rev-parse", "HEAD:Sprout"),
    "harness_tree": sh("git", "rev-parse", "HEAD:SproutEvals"),
    "prices_sha256": hashlib.sha256(open("Evals/prices.json", "rb").read()).hexdigest(),
    "dataset_sha256": datasets,
}, open(os.path.join(out, "manifest.json"), "w"), indent=1)
PY

# The simulator sometimes refuses to launch the test runner ("Application failed preflight
# checks") before any test starts. That attempt calls no model and writes no record, so it
# is run once more; any other failure, or one after records were written, is not.
set +e
for ATTEMPT in 1 2; do
TEST_RUNNER_SPROUT_EVAL_MODELS="$MODELS" \
TEST_RUNNER_SPROUT_EVAL_REPEATS="$REPEATS" \
TEST_RUNNER_SPROUT_EVAL_LIMIT="$LIMIT" \
TEST_RUNNER_SPROUT_EVAL_CASES="${SPROUT_EVAL_CASES:-}" \
TEST_RUNNER_SPROUT_EVAL_ROOT="$ROOT/Evals" \
TEST_RUNNER_SPROUT_EVAL_OUT="$OUT" \
TEST_RUNNER_SPROUT_EVAL_CONCURRENCY="${SPROUT_EVAL_CONCURRENCY:-4}" \
TEST_RUNNER_ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
TEST_RUNNER_OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
xcodebuild test -project Sprout.xcodeproj -scheme SproutEvals \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DERIVED" \
  -only-testing:"SproutEvals/LiveEvals/test${EVAL}" \
  > "$OUT/xcodebuild.log" 2>&1
STATUS=$?
if [ "$STATUS" -ne 0 ] && [ "$ATTEMPT" -eq 1 ] && ! ls "$OUT"/records-*.jsonl >/dev/null 2>&1 \
   && grep -q "failed preflight checks" "$OUT/xcodebuild.log"; then
  echo "the simulator refused to launch the test runner; trying once more"; continue
fi
break
done
set -e

# The build log can echo the environment of the test runner; never keep it if it does.
# Every key-shaped string is masked first, so the tail survives for diagnosis; a tail that
# still holds one after masking is deleted.
sed -E 's/sk-[A-Za-z0-9_-]{8,}/[key]/g' "$OUT/xcodebuild.log" | tail -c 4000 > "$OUT/xcodebuild-tail.log"
rm -f "$OUT/xcodebuild.log"
if grep -q -E 'sk-ant-|sk-proj-|sk-[A-Za-z0-9]{32,}' "$OUT/xcodebuild-tail.log"; then
  rm -f "$OUT/xcodebuild-tail.log"
  echo "the build log still held a key-shaped string after masking and was deleted"
fi

# SPROUT_EVAL_BASELINE=<provider:model> compares every candidate with the model that ships.
python3 "$ROOT/Evals/summarize.py" "$OUT" ${SPROUT_EVAL_BASELINE:+--baseline "$SPROUT_EVAL_BASELINE"}
echo "xcodebuild exit: $STATUS"
echo "records: $OUT"
