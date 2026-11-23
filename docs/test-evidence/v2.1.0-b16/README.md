# Test evidence: v2.1.0-b16

Captured 2026-11-23T04:57:55+00:00 on macOS 26.6 (arm64).
Commit `bee78579db418628c8e6759dc6fc42a20c077c94` on `bryan/verification-reset` (bee7857-dirty); app 2.1 (16).

**The working tree had 8 uncommitted file(s)** (listed in `manifest.json`); this evidence describes that tree, not the commit alone.

## What was under test

- Xcode 26.4 Build version 17E192, xcodegen Version: 2.45.4
- Simulator: Victoria-Dev (iPhone 17 Pro, iOS 26.4 23E244)
- 193 tracked Swift files

## Commands

- `xcodegen generate`
- `xcodebuild test -project Victoria.xcodeproj -scheme Victoria -destination 'platform=iOS Simulator,name=Victoria-Dev' -enableCodeCoverage YES -parallel-testing-enabled NO`
- `xcodebuild test -project Victoria.xcodeproj -scheme VictoriaEvals -destination 'platform=iOS Simulator,name=Victoria-Dev' -parallel-testing-enabled NO`
- `xcodebuild build -scheme Victoria -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- `gitleaks git --redact .`

## Result

- Unit tests: **491 passed**, 0 failed, 0 skipped (of 491), result `Passed`
- Evaluation harness self-tests (offline): **16 passed**, 0 failed, 3 skipped (of 19), result `Passed`. The skipped tests are the live evaluations, which need a key and are never part of this capture.
- Gate exit codes: xcodegen=0, unit_tests=0, unit_counts=0, eval_self_tests=0, eval_counts=0, release_build=0, secret_scan=0 (secret_scan -1 means gitleaks was not installed)

### Line coverage by target

- `Victoria.app`: 19.1% (9143 of 47820 lines)
- `VictoriaTests.xctest`: 97.1% (7441 of 7660 lines)
- `VictoriaWidgets.appex`: 4.1% (43 of 1046 lines)

### Failed

- none

### Compiler warnings in app and test code: 11

- `Victoria/App/AppDelegate.swift:44:10: warning: non-Sendable parameter type '[AnyHashable : Any]' cannot be sent from caller of protocol requirement 'application(_:didReceiveRemoteNotification:)' into main actor-isolated implementation; this is an error in the `
- `Victoria/Features/Buddy/Services/CloudKitSyncService.swift:289:9: warning: result of 'try?' is unused`
- `Victoria/Features/Buddy/Services/CloudKitSyncService.swift:430:13: warning: result of 'try?' is unused`
- `Victoria/Features/Buddy/Services/CloudKitSyncService.swift:436:10: warning: non-Sendable parameter type 'Nudge' cannot be sent from caller of protocol requirement 'sendNudge' into main actor-isolated implementation; this is an error in the Swift 6 language mod`
- `Victoria/Features/Buddy/Services/CloudKitSyncService.swift:463:10: warning: non-Sendable type '[Nudge]' cannot be returned from main actor-isolated implementation to caller of protocol requirement 'fetchInbox()'; this is an error in the Swift 6 language mode`
- `Victoria/Features/Buddy/Services/LocalMockSyncService.swift:119:10: warning: non-Sendable parameter type 'Nudge' cannot be sent from caller of protocol requirement 'sendNudge' into main actor-isolated implementation; this is an error in the Swift 6 language mo`
- `Victoria/Features/Buddy/Services/LocalMockSyncService.swift:132:10: warning: non-Sendable type '[Nudge]' cannot be returned from main actor-isolated implementation to caller of protocol requirement 'fetchInbox()'; this is an error in the Swift 6 language mode`
- `Victoria/Features/Buddy/Services/LocalMockSyncService.swift:212:10: warning: main actor-isolated property 'defaults' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode`
- `Victoria/Features/Buddy/Views/BuddyViewModel.swift:132:5: warning: 'nonisolated(unsafe)' has no effect on property 'pushObserver', consider using 'nonisolated'`
- `Victoria/Features/Coach/CoachContext.swift:304:13: warning: initialization of immutable value 'calTarget' was never used; consider replacing with assignment to '_' or removing it`
- `Victoria/Services/GoogleHealth/GoogleHealthAuth.swift:127:48: warning: main actor-isolated static property 'scopes' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode`

### Evaluation datasets at this commit

- `Evals/datasets/daily_brief/v1.jsonl`: 13 cases, sha256 `e1a5238033d797b4…`
- `Evals/datasets/meal_describe/v1.jsonl`: 14 cases, sha256 `40e5590a2a5e21af…`
- `Evals/datasets/coach_tool_choice/v1.jsonl`: 34 cases, sha256 `7e7ae9895e3ed48a…`

Files: `manifest.json`, `summary.json`, `summary_evals.json`, `tests.txt`, `tests_evals.txt`, `coverage.txt`, `compiler_warnings.txt`.
