#!/bin/bash
# Rebuilds learn/sql/sprout-demo.sqlite from the app's real schema and the fictional "Alex"
# demo (DemoSeed), then re-records expected.json from solutions/.
#
#   learn/sql/build_demo_db.sh [simulator name, default Sprout-Dev]
#
# Needed only after a model changes. The seed draws some values at random and dates the data
# from today, so a rebuild changes the answers: re-check solutions/ (and the dates in
# exercises 05 and 12 and TODAY_START in check.py) before committing.
set -euo pipefail
cd "$(dirname "$0")/../.."
SIM="${1:-Sprout-Dev}"
OUT="$PWD/learn/sql/sprout-demo.sqlite"
RESULT="$(mktemp -d)/shape.xcresult"
TEST_RUNNER_SPROUT_SQL_DEMO_OUT="$OUT" xcodebuild test -project Sprout.xcodeproj -scheme Sprout \
  -only-testing:SproutTests/SQLStoreShapeTests \
  -destination "platform=iOS Simulator,name=$SIM" -resultBundlePath "$RESULT" -quiet
python3 tooling/check_xcresult.py "$RESULT" --min-tests 1
rm -rf "${RESULT:?}"
python3 learn/sql/check.py --record
python3 learn/sql/check.py --self-test
