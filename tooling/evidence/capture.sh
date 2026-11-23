#!/bin/bash
# Capture the test evidence for a version into docs/test-evidence/<label>/.
#
#   tooling/evidence/capture.sh v2.1.0-b16
#
# Runs every gate from a regenerated project and writes what was run, on what, and
# what it returned: manifest.json, summary.json, tests.txt, coverage.txt, README.md.
# Exits non-zero if any gate failed; the files are written either way, so a failing
# capture is still a record.
set -uo pipefail

LABEL="${1:?version label, e.g. v2.1.0-b16}"
SIM="${SPROUT_SIM:-Victoria-Dev}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/test-evidence/$LABEL"
WORK="$(mktemp -d)"
DERIVED="${SPROUT_DERIVED_DATA:-$ROOT/build/evidence-derived}"
mkdir -p "$OUT"
cd "$ROOT"

xcodegen generate > "$WORK/xcodegen.log" 2>&1; GEN=$?

xcodebuild test -project Victoria.xcodeproj -scheme Victoria \
  -destination "platform=iOS Simulator,name=$SIM" \
  -resultBundlePath "$WORK/unit.xcresult" -enableCodeCoverage YES \
  -parallel-testing-enabled NO -derivedDataPath "$DERIVED" > "$WORK/unit.log" 2>&1; UNIT=$?

xcodebuild test -project Victoria.xcodeproj -scheme VictoriaEvals \
  -destination "platform=iOS Simulator,name=$SIM" \
  -resultBundlePath "$WORK/evals.xcresult" \
  -parallel-testing-enabled NO -derivedDataPath "$DERIVED" > "$WORK/evals.log" 2>&1; EVALS=$?

xcodebuild build -project Victoria.xcodeproj -scheme Victoria -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO > "$WORK/release.log" 2>&1; RELEASE=$?

if command -v gitleaks >/dev/null; then
  gitleaks git --redact --no-banner . > "$WORK/gitleaks.log" 2>&1; LEAKS=$?
else
  echo "gitleaks not installed" > "$WORK/gitleaks.log"; LEAKS=-1
fi

python3 tooling/check_xcresult.py "$WORK/unit.xcresult" --min-tests 1 --max-skipped 9999 \
  --summary-out "$OUT/summary.json" > "$WORK/unit.check" 2>&1; UNIT_CHECK=$?
python3 tooling/check_xcresult.py "$WORK/evals.xcresult" --min-tests 1 --max-skipped 9999 \
  --summary-out "$OUT/summary_evals.json" > "$WORK/evals.check" 2>&1; EVALS_CHECK=$?
xcrun xccov view --report --only-targets "$WORK/unit.xcresult" > "$OUT/coverage.txt" 2>/dev/null
xcrun xccov view --report --json "$WORK/unit.xcresult" > "$WORK/coverage.json" 2>/dev/null
grep -E "^Test Case '.*' (passed|failed|skipped)" "$WORK/unit.log" \
  | sed -E "s/^Test Case '-\[([^]]+)\]' (passed|failed|skipped).*/\2 \1/" | sort > "$OUT/tests.txt"
grep -E "^Test Case '.*' (passed|failed|skipped)" "$WORK/evals.log" \
  | sed -E "s/^Test Case '-\[([^]]+)\]' (passed|failed|skipped).*/\2 \1/" | sort > "$OUT/tests_evals.txt"
WARNINGS=$(grep -E '\.swift:[0-9]+:[0-9]+: warning:' "$WORK/unit.log" | sed -E 's#^.*/(Victoria|Shared|VictoriaWidgets|VictoriaTests)/#\1/#' | sort -u)
echo "$WARNINGS" > "$OUT/compiler_warnings.txt"

python3 - "$OUT" "$LABEL" "$SIM" "$GEN" "$UNIT" "$EVALS" "$RELEASE" "$LEAKS" "$UNIT_CHECK" "$EVALS_CHECK" "$WORK" <<'PY'
import datetime, hashlib, json, os, platform, subprocess, sys
out, label, sim, gen, unit, evals, release, leaks, unit_check, evals_check, work = sys.argv[1:12]
def sh(*a):
    try: return subprocess.check_output(a, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception: return ""
def load(name):
    try: return json.load(open(os.path.join(out, name)))
    except Exception: return {}
s, e = load("summary.json"), load("summary_evals.json")
device = (s.get("devicesAndConfigurations") or [{}])[0].get("device", {})
cov = {}
try:
    for t in json.load(open(os.path.join(work, "coverage.json"))).get("targets", []):
        cov[t["name"]] = {"lineCoverage": round(t["lineCoverage"], 4),
                          "coveredLines": t["coveredLines"], "executableLines": t["executableLines"]}
except Exception:
    pass
datasets = {}
for base, _, files in os.walk("Evals/datasets"):
    for f in sorted(files):
        if f.endswith(".jsonl"):
            p = os.path.join(base, f)
            datasets[p] = {"sha256": hashlib.sha256(open(p, "rb").read()).hexdigest(),
                           "cases": sum(1 for l in open(p) if l.strip())}
swift_files = [l for l in sh("git", "ls-files", "*.swift").splitlines()]
gates = {"xcodegen": int(gen), "unit_tests": int(unit), "unit_counts": int(unit_check),
         "eval_self_tests": int(evals), "eval_counts": int(evals_check),
         "release_build": int(release), "secret_scan": int(leaks)}
manifest = {
    "label": label,
    "captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "commit": sh("git", "rev-parse", "HEAD"), "describe": sh("git", "describe", "--always", "--dirty"),
    "branch": sh("git", "rev-parse", "--abbrev-ref", "HEAD"),
    "uncommitted_files": [l for l in sh("git", "status", "--porcelain").splitlines() if l],
    "host": {"macos": platform.mac_ver()[0], "arch": platform.machine()},
    "xcode": sh("xcodebuild", "-version").replace("\n", " "), "xcodegen": sh("xcodegen", "--version"),
    "simulator": {"name": device.get("deviceName", sim), "model": device.get("modelName"),
                  "os": device.get("osVersion"), "os_build": device.get("osBuildNumber")},
    "app_version": sh("sh", "-c", "grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/[^0-9.]//g'"),
    "app_build": sh("sh", "-c", "grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed -E 's/[^0-9]//g'"),
    "swift_files": len(swift_files),
    "gate_exit_codes": gates,
    "unit": {k: s.get(k) for k in ("result", "totalTestCount", "passedTests", "failedTests", "skippedTests")},
    "eval_self_tests": {k: e.get(k) for k in ("result", "totalTestCount", "passedTests", "failedTests", "skippedTests")},
    "coverage": cov, "eval_datasets": datasets,
}
json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)

def counts(d):
    return (f"**{d.get('passedTests')} passed**, {d.get('failedTests')} failed, {d.get('skippedTests')} skipped "
            f"(of {d.get('totalTestCount')}), result `{d.get('result')}`")
warnings = [l for l in open(os.path.join(out, "compiler_warnings.txt")).read().splitlines() if l.strip()]
lines = [
    f"# Test evidence: {label}", "",
    f"Captured {manifest['captured_utc']} on macOS {manifest['host']['macos']} ({manifest['host']['arch']}).",
    f"Commit `{manifest['commit']}` on `{manifest['branch']}` ({manifest['describe']}); app {manifest['app_version']} ({manifest['app_build']}).",
]
if manifest["uncommitted_files"]:
    lines += ["", f"**The working tree had {len(manifest['uncommitted_files'])} uncommitted file(s)** (listed in `manifest.json`); "
              "this evidence describes that tree, not the commit alone."]
lines += ["", "## What was under test", "",
          f"- {manifest['xcode']}, xcodegen {manifest['xcodegen']}",
          f"- Simulator: {manifest['simulator']['name']} ({manifest['simulator']['model']}, iOS {manifest['simulator']['os']} {manifest['simulator']['os_build']})",
          f"- {manifest['swift_files']} tracked Swift files",
          "", "## Commands", "",
          "- `xcodegen generate`",
          f"- `xcodebuild test -project Victoria.xcodeproj -scheme Victoria -destination 'platform=iOS Simulator,name={sim}' -enableCodeCoverage YES -parallel-testing-enabled NO`",
          f"- `xcodebuild test -project Victoria.xcodeproj -scheme VictoriaEvals -destination 'platform=iOS Simulator,name={sim}' -parallel-testing-enabled NO`",
          "- `xcodebuild build -scheme Victoria -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`",
          "- `gitleaks git --redact .`",
          "", "## Result", "",
          f"- Unit tests: {counts(manifest['unit'])}",
          f"- Evaluation harness self-tests (offline): {counts(manifest['eval_self_tests'])}. The skipped tests are the live evaluations, which need a key and are never part of this capture.",
          "- Gate exit codes: " + ", ".join(f"{k}={v}" for k, v in gates.items()) + " (secret_scan -1 means gitleaks was not installed)",
          "", "### Line coverage by target", ""]
for name, c in cov.items():
    lines.append(f"- `{name}`: {c['lineCoverage']:.1%} ({c['coveredLines']} of {c['executableLines']} lines)")
lines += ["", "### Failed", ""]
failures = s.get("testFailures", []) + e.get("testFailures", [])
lines += [f"- `{f.get('testName')}`: {f.get('failureText', '')[:300]}" for f in failures] or ["- none"]
lines += ["", f"### Compiler warnings in app and test code: {len(warnings)}", ""]
lines += [f"- `{w[:260]}`" for w in warnings[:40]] or ["- none"]
lines += ["", "### Evaluation datasets at this commit", ""]
lines += [f"- `{p}`: {d['cases']} cases, sha256 `{d['sha256'][:16]}…`" for p, d in datasets.items()]
lines += ["", "Files: `manifest.json`, `summary.json`, `summary_evals.json`, `tests.txt`, `tests_evals.txt`, `coverage.txt`, `compiler_warnings.txt`.", ""]
open(os.path.join(out, "README.md"), "w").write("\n".join(lines))
print("\n".join(lines[:28]))
sys.exit(0 if all(v == 0 for k, v in gates.items() if not (k == "secret_scan" and v == -1)) else 1)
PY
STATUS=$?
rm -rf "$WORK"
exit $STATUS
