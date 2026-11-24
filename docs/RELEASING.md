# Releasing without doing it by hand

Goal: a merge to `main` puts a new build on both phones with nobody tapping anything, and
no build is ever old enough to expire (TestFlight builds stop opening 90 days after upload,
EVAL_REPORT 7).

## The setup (once, about 15 minutes, needs the Apple account)

1. **Xcode Cloud workflow.** In Xcode: Product → Xcode Cloud → Create Workflow, for the
   `Sprout` scheme of this repository (the project and its shared schemes are committed,
   which Xcode Cloud needs).
   - Start conditions: **Branch changes** on `main`, and **On a schedule** for `main`
     (weekly or monthly). The schedule is what stops expiry when nothing has been merged
     for a while: each run uploads a fresh 90-day build.
   - Action: **Archive**, iOS, distribution **TestFlight (Internal Testing Only)**.
   - Post-action: **TestFlight Internal Testing**, the group the two phones are in.
   - Let Xcode Cloud manage signing and build numbers (each build needs a higher number
     than the last; confirm the setting on the first run).
   - Cost: the Apple Developer Program includes 25 compute hours a month. A build of this
     app takes minutes, so a merge a day plus a weekly schedule fits.
2. **On each phone, once:** TestFlight → Sprout → turn on **Automatic Updates** (also in
   TestFlight → Settings → Automatic Updates for New Apps). New builds then install by
   themselves, with a notification.

After that: a merged pull request (CI green) becomes a build, the build reaches TestFlight,
and the phones update themselves. Nobody deletes the app; an update keeps everything
(EVAL_REPORT 27).

## What this does not cover

- **The personal onboarding note** is not in the repository, so builds made by Xcode Cloud
  do not have it (`PersonalNote.swift`). It only matters to someone onboarding for the
  first time; it is not shown to anyone who already has data.
- **Automatic updates have failed for some people** (Apple developer forums, thread
  716912). If a phone says the beta has expired, opening TestFlight and tapping Update
  fixes it.
- **No expiry at all** needs the App Store (public or unlisted): App Review for every
  version, and the review findings in EVAL_REPORT 7 (health data in iCloud, consent before
  sending data to an AI provider, a reviewer needs a key or a demo mode) would have to be
  addressed first.

## Sources

- TestFlight automatic updates: <https://developer.apple.com/testflight/testers/>
- Xcode Cloud start conditions, including on a schedule:
  <https://developer.apple.com/documentation/xcode/configuring-start-conditions>
- Scheduled workflow that archives and distributes to internal TestFlight testers:
  <https://developer.apple.com/news/?id=u6sj76ew>
- 25 compute hours included: <https://developer.apple.com/news?id=ik9z4ll6>
