#!/usr/bin/env python3
"""Assert on a test result bundle instead of trusting an exit code through a pipe.

    tooling/check_xcresult.py <bundle.xcresult> --min-tests 470 [--max-skipped 0]
                              [--summary-out summary.json] [--markdown]

Fails (exit 1) unless the bundle says Passed, nothing failed, at least --min-tests
ran, and no more than --max-skipped were skipped. The minimum is what stops a run
in which no tests were found from reading as green.
"""
import argparse, json, subprocess, sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bundle")
    ap.add_argument("--min-tests", type=int, required=True)
    ap.add_argument("--max-skipped", type=int, default=0)
    ap.add_argument("--summary-out")
    ap.add_argument("--markdown", action="store_true")
    a = ap.parse_args()

    raw = subprocess.check_output(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", a.bundle], text=True)
    s = json.loads(raw)
    if a.summary_out:
        open(a.summary_out, "w").write(json.dumps(s, indent=1, sort_keys=True) + "\n")

    passed, failed, skipped = s.get("passedTests", 0), s.get("failedTests", 0), s.get("skippedTests", 0)
    total = s.get("totalTestCount", passed + failed + skipped)
    expected = s.get("expectedFailures", 0)
    line = f"{s.get('result')}: {total} tests, {passed} passed, {failed} failed, {skipped} skipped"
    if expected:
        # A known defect pinned with XCTExpectFailure: counted, shown, and not a pass.
        line += f", {expected} expected failures (known defects)"
    print(("**" + line + "**") if a.markdown else line)
    for f in s.get("testFailures", []):
        print(("- " if a.markdown else "  FAILED ") + f.get("testName", "?") + ": "
              + f.get("failureText", "").replace("\n", " ")[:400])

    problems = []
    if s.get("result") != "Passed":
        problems.append(f"result is {s.get('result')}")
    if failed:
        problems.append(f"{failed} failed")
    if total < a.min_tests:
        problems.append(f"only {total} tests ran, expected at least {a.min_tests}")
    if skipped > a.max_skipped:
        problems.append(f"{skipped} skipped, at most {a.max_skipped} allowed")
    if problems:
        print("CHECK FAILED: " + "; ".join(problems), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
