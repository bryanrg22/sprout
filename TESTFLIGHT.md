# Shipping Victoria to TestFlight

Everything in the code is TestFlight-ready. The remaining steps need **your Apple Developer
account + signing**, so they have to be done by you in Xcode / App Store Connect. Follow in
order — it's ~30–45 min the first time, minutes for every update after.

## 0. Prereqs (one-time)
- Paid **Apple Developer Program** membership (you have this). ✅
- A Mac with **Xcode 16+** (iOS 18 SDK).
- **Confirm Victoria's iPhone runs iOS 18+** — the app's deployment target is **iOS 18.0**.
  If her phone is older, lower `deploymentTarget` in `project.yml` (try 17.0) and re-run
  `xcodegen generate`, OR have her update iOS. (TestFlight itself needs iOS 16+.)

## 1. Set your Team + signing (Xcode)
1. `xcodegen generate --spec project.yml` then open `Victoria.xcodeproj`.
2. Select the **Victoria** target → Signing & Capabilities → check **Automatically manage
   signing** → pick your **Team**. Repeat for the **VictoriaWidgets** target (same Team).
   - (Optional: bake it in by setting `DEVELOPMENT_TEAM:` in `project.yml` to your Team ID,
     then `xcodegen generate` — but doing it in Xcode is enough.)
3. Bundle IDs are already set: app `com.bryanram.victoria`, widgets
   `com.bryanram.victoria.widgets`. Let Xcode register them on first signing.

## 2. Capabilities the App IDs need (Xcode usually auto-adds these)
- **iCloud → CloudKit**, container **`iCloud.com.bryanram.victoria`** (for the Buddy sync).
- **Push Notifications** (for buddy nudges).
- **App Groups** `group.com.bryanram.victoria` (already in entitlements — for the widget data
  share). Make sure it's enabled on BOTH the app and widget App IDs.
- **HealthKit** (NEW — for Apple Health weight sync). The `com.apple.developer.healthkit`
  entitlement is now in `project.yml`. With **Automatically manage signing** on, Xcode adds
  the HealthKit capability to the App ID for you; if a signing error mentions HealthKit,
  open Signing & Capabilities → **+ Capability → HealthKit** on the **Victoria** target.
  (Widgets don't need it.)
- **Location — nothing to enable.** "When In Use" location is requested in onboarding for the
  (upcoming) nearby-healthy-food suggestions; the usage string is already in `project.yml`.
  No App ID capability needed. Note for App Review: the feature that *uses* the location isn't
  live yet, so if a reviewer ever flags an unused permission, either ship the nearby feature
  or temporarily remove the location step — it's isolated to the onboarding "Connect" screen.
- **Push for TestFlight:** ✅ already done — `aps-environment` is set to `production` in
  `project.yml`, so archived builds use the production APNs environment with no extra step.

## 3. CloudKit Dashboard (one-time, for buddy sync to work cross-device)
At <https://icloud.developer.apple.com> → your container:
1. Let the schema auto-create by running the app on a device once (it creates record types
   on first write), OR add them manually: **Nudge**, **BuddyPairing**, **BuddySnapshot**.
2. Add indexes (Schema → Indexes):
   - `Nudge`: `toUserID` **Queryable**, `createdAt` **Sortable** (+ `Queryable` on the
     record's system fields as prompted).
   - `BuddySnapshot`: `ownerUserID` **Queryable** — REQUIRED for the silent "your buddy just
     logged" push (the snapshot subscription predicates on it). Without it the hub only
     updates via its 20-second poll while the page is open; live updates never arrive.
   - `BuddyPairing`: `recordName`/pairing code **Queryable**.
3. **Deploy Schema to Production** (Dashboard → Deploy). Without this, buddy sync works in
   dev but not for TestFlight users.
   ⚠️ **Re-deploy EVERY time an app update adds a new CloudKit field** (e.g. the v2
   full-share fields: carbs/fat/workoutSummary). Production schema is frozen; if an updated
   app writes a field Production doesn't know, the ENTIRE snapshot save fails on TestFlight —
   silently — and the buddy sees a frozen, weeks-old snapshot. Fix: run the DEBUG build's
   Settings → "Seed CloudKit Schema" once (registers all current fields in Development),
   then Dashboard → **Deploy Schema Changes to Production**.
   If buddy data ever looks frozen: on the STALE person's phone, Settings → tap the version
   line 7× → **Run buddy sync check** — it prints the exact CloudKit error.
4. Both you and Victoria must be **signed into iCloud** on your devices.

## 4. Archive + upload
1. In Xcode: set the run destination to **Any iOS Device (arm64)**.
2. **Product → Archive**. When it finishes, the Organizer opens.
3. **Distribute App → App Store Connect → Upload**. Let Xcode manage signing.
4. In **App Store Connect** (<https://appstoreconnect.apple.com>): the build appears under
   your app → **TestFlight** tab after processing (~5–15 min). Fill the **"What to test"**
   note + the **Export Compliance** prompt (this app uses only standard HTTPS → usually
   "no" to custom encryption).

## 5. Invite Victoria
- TestFlight tab → **Internal Testing** (add her Apple ID as a tester — fastest, no review),
  or **External Testing** with a **public link** (needs a quick Beta App Review first).
- She installs the **TestFlight** app from the App Store, opens your invite, taps **Install**.
- **Updates:** you upload a new build → she taps **Update** in TestFlight. (Builds expire
  ~90 days.)

## 6. First-run per person
- **Victoria:** in onboarding she **picks the cute look** (cream/coral) + a **lose** goal →
  cute skin + her pixel companion + a sensible deficit she fuels *up to*. On the **"Connect
  Vita's brain"** step she pastes the **Anthropic key you texted her** (one-tap Paste button),
  or taps "Maybe later" and adds it from the **"Almost there — connect Vita"** card on Today.
- **You:** **pick the cool look** (dark/lime) + a **gain** goal → cool skin + pixel-Bryan
  (with his chain/cross/scapular) + a lean surplus. (Same app, your own profile/data on your
  own phone + iCloud.)
- The **look is a real choice** in onboarding now (not auto-derived), so either person can
  pick either skin; it's changeable anytime in Settings → Appearance, and the app icon in
  Settings → App Icon.

## What's verified vs. needs your device
- **Verified on the simulator:** full onboarding (incl. the new look-picker + Connect step) →
  finish → app, both skins, the new **food suggestions** section (no-key state; live needs a
  key), **coach memory** (build + logic), **companion tap-to-talk catchphrases**, the
  **Strava run-card**, food/photo/describe/favorites/label flows, fitness, all 5 tabs (no
  crashes), home widgets (via the in-app gallery — `--widget-preview`), **108 unit tests**.
- **Needs a real device (test after install):** the camera (photo/barcode/label scan), LiDAR
  (future), **push notifications**, **CloudKit buddy sync between two phones**, **Apple Health
  sync**, **location prompt**, live LLM (coach replies, food-suggestion generation, memory
  consolidation — all need the key), and placing real widgets on the Home screen.
- **API key:** the coach + food suggestions + photo/describe estimates need an **Anthropic**
  key (default), entered in onboarding's **Connect** step, the Today **finish-setup card**, or
  **Settings → AI Provider** (stored only in the device Keychain; OpenAI also supported).
  ⚠️ Rotate the key you shared in chat earlier + set a monthly spend cap.
- **App name is "Sprout"** (display name + icon); the Xcode target/bundle stays `Victoria` /
  `com.bryanram.victoria` — that's expected, don't rename them.
