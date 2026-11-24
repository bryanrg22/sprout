# First-time TestFlight setup

The one-time steps that need the Apple Developer account, in Xcode and App Store Connect.
About 30–45 minutes the first time. After that, releases are automatic
([`RELEASING.md`](RELEASING.md)), and the AI server has its own setup
([`server/README.md`](../server/README.md)).

The app's display name is **Sprout**. Its bundle id, iCloud container and App Group keep
the `com.bryanram.victoria` names they shipped under: changing them would make TestFlight
install a different app and leave every tester's data behind. Do not rename them.

## 0. Prereqs (one-time)
- Paid **Apple Developer Program** membership (you have this). ✅
- A Mac with **Xcode 16+** (iOS 18 SDK).
- **Testers' iPhones need iOS 18+**: the app's deployment target is **iOS 18.0**.
  (TestFlight itself needs iOS 16+.)

## 1. Set your Team + signing (Xcode)
1. `xcodegen generate --spec project.yml` then open `Sprout.xcodeproj`.
2. Select the **Sprout** target → Signing & Capabilities → check **Automatically manage
   signing** → pick your **Team**. Repeat for the **SproutWidgets** target (same Team).
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
  open Signing & Capabilities → **+ Capability → HealthKit** on the **Sprout** target.
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
4. **Security roles** (Schema → Security Roles, in Production): the signed-in role
   (`_icloud`) needs **Write** on `BuddyPairing` and `Nudge`. Claiming a code, unpairing
   as the one who typed it, and marking a nudge read each write to a record the OTHER
   iCloud user created; with the default roles only the creator may. Not verified from the
   code, and two devices on one Apple ID hide it. Symptoms and the full list:
   `docs/buddy-sync.md`, section 10.
5. Testers must be **signed into iCloud** on their devices.

## 4. Archive + upload
1. In Xcode: set the run destination to **Any iOS Device (arm64)**.
2. **Product → Archive**. When it finishes, the Organizer opens.
3. **Distribute App → App Store Connect → Upload**. Let Xcode manage signing.
4. In **App Store Connect** (<https://appstoreconnect.apple.com>): the build appears under
   your app → **TestFlight** tab after processing (~5–15 min). Fill the **"What to test"**
   note + the **Export Compliance** prompt (this app uses only standard HTTPS → usually
   "no" to custom encryption).

## 5. Invite testers
- TestFlight tab → **Internal Testing** (add their Apple ID: fastest, no review), or
  **External Testing** with a **public link** (needs a short Beta App Review first).
- They install the **TestFlight** app, open the invite and tap **Install**.
- **Updates:** a new build shows up in TestFlight; with Automatic Updates on, it installs
  by itself (builds expire after 90 days, see `RELEASING.md`).

## 6. First run
- Onboarding asks for a look (cute or cool), a goal (lose, maintain or gain) and the
  basics, then offers Apple Health and location (both optional).
- There is **no API key to enter**: the AI is built in, through the gateway in `server/`.
  A phone that cannot do App Attest (very old hardware) works without the AI features.

## What needs a real device
The camera (photo, barcode and label scan), push notifications, CloudKit buddy sync between
two phones, Apple Health sync, the location prompt, App Attest (so the built-in AI), and
widgets on the Home screen. Everything else is covered by the unit and UI tests
(`docs/DEVELOPING.md`).
