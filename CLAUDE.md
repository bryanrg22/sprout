# CLAUDE.md — Sprout (victoria-weightloss-app)

iOS app, SwiftUI + SwiftData, xcodegen-generated project. Owner: Bryan. The repo doubles
as his AI-engineering portfolio — README quality and honest, measured claims matter as
much as the code. Model-tier decisions live in `docs/MODEL_CHOICES.md`; update it (with
the why + rejected alternatives) whenever a default model changes.

## Build & test

```bash
xcodegen generate                       # after adding/moving ANY file (sources are globbed)
xcodebuild test -project Victoria.xcodeproj -scheme Victoria \
  -destination 'platform=iOS Simulator,name=Victoria-Dev' \
  -resultBundlePath /tmp/t.xcresult
# NEVER trust the pipe's exit code — verify counts:
xcrun xcresulttool get test-results summary --path /tmp/t.xcresult
```

- Sim: **Victoria-Dev**, UDID `E55E737A-8A6C-4178-8063-7F4612321B4C` (iOS 26.4).
- Install gotcha (FinderInfo detritus): before `simctl install`, run
  `xattr -cr "$APP" && codesign --force --deep --sign - "$APP"`.

## Driving the simulator UI (screenshots, tap-throughs)

The runner is an XCTest HTTP server on **:22087** from the `ios-agent_automation` repo.

```bash
cd ~/Documents/GitHub/ios-agent_automation
bash scripts/start-sim-runner.sh --udid E55E737A-8A6C-4178-8063-7F4612321B4C   # background it
# ⚠️ The flag is --udid. `UDID=` / no flag silently falls back to a DIFFERENT default sim
#    (it will boot iPhone 17 Pro, shut nothing down, and you'll drive the wrong device —
#    symptoms: fresh-install onboarding screen, wrong timezone, "where did the data go").
```

Drive it with the CLI directly (works even when the ios-tester MCP tools are gone):

```bash
node ios-exec.mjs --udid <UDID> --steps '[{"tapText":"Settings"},{"sleep":1},{"screenshot":true}]'
```

- Verbs: `tap:[x%,y%]`, `tapText`, `type` (needs a FOCUSED field — tap it first),
  `replaceText:["Label","value"]`, `swipe:[x1,y1,x2,y2]`, `scroll`, `waitText`,
  `hierarchy` (labels + % coords), `screenshot`, `launch`, `eraseText`, `key`.
- Chat send button sits at ~`[91,58]` with keyboard up; message field ~`[50,87]` without.
  Typed sends can land DELAYED — check the transcript before retyping (double-send risk).
- SpringBoard alerts aren't in the app hierarchy — tap by % coordinates.
- Keyboard covers buttons; dismiss by scrolling the list or cold-restarting the app.
- `open -a Simulator --args -CurrentDeviceUDID <UDID>` if the window isn't visible
  (headless boot is common after runner restarts).

## Demo profiles & the two variants

```bash
xcrun simctl launch <UDID> com.bryanram.victoria --seed-demo               # Victoria: cute/light, loss goal
xcrun simctl launch <UDID> com.bryanram.victoria --seed-demo --demo-gain   # Bryan: Cool/DARK, lean-gain
# also: --demo-fueled, --demo-tab <name>, --demo-screen <workout|achievements|buddy>
```

- Seeding only happens when no profile exists. To reseed: terminate app, then delete the
  store — it lives in the **app group** container:
  `…/Containers/Shared/AppGroup/<id>/Library/Application Support/default.store*`
  (back it up first; also delete the `dailyBrief.v1` key from the app's Preferences plist
  or yesterday's cached brief survives).
- **Keychain survives store wipes**: Google Health OAuth tokens + AI keys persist, so the
  Fitbit connection auto-heals into a fresh profile on next launch. UserDefaults
  (client ID, provider choice) also survive — only SwiftData rows reset.
- `simctl spawn <UDID> defaults` CANNOT reach the app's preferences domain — edit the
  plist in the app container with PlistBuddy (app terminated first, or cfprefsd
  resurrects the old values).

## 📸 Public screenshots — hard rules

- **Bryan variant ONLY** (`--seed-demo --demo-gain`, dark theme). Never ship Victoria's
  name, data, or the cute variant publicly; the public story is "built for myself."
- Best AI surfaces to shoot: Today (greeting + daily-brief card, dismiss the widget promo
  first), Vita tool-call exchange, Progress AI recap (wait ~8s past the "Reading your
  trends…" spinner), Today's checklist (Vita's plan), Settings → Fitbit connected page,
  tracker card → Sleep & recovery (real Fitbit data; card self-hides when no night ending
  today exists yet).
- Destination: `docs/screenshots/`, downscale `sips -Z 720`, wire into README.

## Secrets & live testing

- NEVER type/paste API keys or handle the user's credentials — Bryan enters keys himself
  (sim clipboard: `xcrun simctl pbsync host <UDID>` moves his Mac clipboard over unread).
- AI provider/model checks: Settings → AI Provider → "Verify key works" pings the
  DEFAULT coach model live. Per-call token usage (`in/out/cached`) is in hidden
  Diagnostics: Settings → tap the version line 7×. The store is directly inspectable:
  `sqlite3 -readonly ".../default.store"` (dates are Apple epoch: +978307200).
- OpenAI prompt-cache verification needs ≥60s between calls (write → readable lag);
  back-to-back `cached 0` is not a failure signal.

## Conventions

- Every ingest path goes through pure, unit-tested merge functions (idempotent upserts);
  new data sources reuse them — never write parallel insert logic.
- The AI layer speaks Anthropic's wire vocabulary internally; other providers translate
  at the client boundary (`Services/AI/`). New AI features go through `AIClient.make()`/
  `makeFull()` — never construct a vendor client at a call site (grep for stragglers
  when adding provider features; `PlanService.review()` was missed once).
- Every optional AI feature gates on `AIConfig.hasActiveKey` (not the Anthropic-only
  `KeychainStore.hasAPIKey` shim) and has a template/manual fallback.
- Demo/seed content must be variant-aware — no hardcoded names or goal-direction copy.
- Claims in README/docs must be measured or live-verified, never estimated silently.
