# Buddy sync: pairing, publishing, and what the user sees when it fails

How two people pair, how each one's day reaches the other, how a pairing ends, and for
every way it can fail, what the code does and what is on screen. When this file and the
code disagree, the code is right and this file is fixed in the same change.

**What is verified and what is not.** Every decision described here is made in code that
the unit tests run against a server in the test process (`VictoriaTests/Support/BuddySyncTestSupport.swift`).
The CloudKit calls themselves (`CloudKitSyncService`, `CloudKitPairingStore`) have **never
been run by a test or, for the parts changed here, on a device**: they were read, not run.
The last two sections say what has to be checked on a device and in the CloudKit Dashboard.

## 1. The pieces

| File (`Victoria/Features/Buddy/`) | What it is |
|---|---|
| `Services/BuddySyncService.swift` | The protocol the app talks to, the snapshot payload, the error cases. |
| `Services/BuddyPairing.swift` | The pairing handshake (`BuddyPairingEngine`), the store it runs over (`BuddyPairingStore`), where the link is kept on the device (`BuddyLinkStorage`), the code format. |
| `Services/CloudKitSyncService.swift` | The real backend on a device: the CloudKit **public** database. |
| `Services/LocalMockSyncService.swift` | The Simulator's stand-in (it cannot sign in to iCloud): the same handshake over an in-memory store, with a simulated buddy "Sam". |
| `Services/BuddyPublishCoordinator.swift` | One publish at a time per user, and the sync health every screen reports. |
| `Services/BuddyMilestones.swift` | Which goals were just crossed, and which cheers were already sent. |
| `Services/BuddyFreshness.swift` | How old the buddy's last published day is. |
| `Services/BuddyRemoteChange.swift` | CloudKit pushes: which are about the buddy, and waiting for the refresh they cause. |
| `Services/BuddyLog.swift` | Keeps a failure that repeats on every poll from flooding the Diagnostics log. |
| `Views/BuddyViewModel.swift` | State and sentences for every Buddy screen. |
| `Views/BuddyAutoPublisher.swift` | Publishes my day from any tab; mounted at the root. |

## 2. What is stored where

**On the device (`UserDefaults`).** Nothing below survives deleting the app; see
`docs/buddy-identity.md`.

| Key | Holds |
|---|---|
| `buddyMyUserID` | My id, a UUID minted at first use. |
| `buddy.myPairingCode.<me>` | My pairing code. Kept across launches; replaced when I unpair, or when it turns out to belong to someone else. |
| `buddy.ck.linkedTo.<me>` | My buddy's id. Present means paired. Written only after the pairing is real (section 3). |
| `buddy.ck.linkedVia.code.<me>`, `…role.<me>` | Which pairing record the link went through and whether I showed the code (`owner`) or typed it (`claimant`). Missing for a pairing made by an earlier build. |
| `buddy.lastPublishOK.<me>` | When my day last reached the backend. |
| `buddy.milestone.<me>.<goal>.<yyyy-MM-dd>` | A daily-goal cheer was sent that day. |
| `buddy.milestone.<me>.<streakN>.from.<yyyy-MM-dd>` | A streak-tier cheer was sent for the streak that began that day. |

**In the CloudKit public database.** Three record types, each addressed by record name.

| Record | Name | Fields | Written by |
|---|---|---|---|
| `BuddyPairing` | `pairing-<code>` | `pairingCode`, `ownerUserID`, `buddyUserID` (the claimant; `""` = unclaimed) | Created by the owner of the code. Claimed, and unclaimed on unpair, by the **other** user. Deleted by the owner on unpair. |
| `BuddySnapshot` | `snapshot-<userID>` | name, streak, mood, logged-today, last-active, steps, water, workout; and the full-stats block (weight trend, goal weight, weekly rate, calories, macros, food names) | Its owner only. Deleted by its owner on unpair. |
| `Nudge` | `<uuid>` | `fromUserID`, `toUserID`, `kindRaw`, `text`, `createdAt`, `isRead` | Created by the sender. `isRead` is set by the **recipient**. |

The full-stats block is opt-in ("Share my full stats with your buddy" in Settings).
A snapshot is built through `BuddySnapshotPayload.init`, which blanks every field of the
block unless the switch is on, and `CloudKitSyncService.publish` strips it again at the
upload. Flipping the switch is itself a reason to publish (`BuddyAutoPublisher.signature`),
so turning sharing off replaces the published snapshot within seconds.

The public database is readable by any signed-in user of the app who knows a record's
name. Pairing is a convenience, not an access control: see "Not solved here" at the end.

## 3. Pairing

A code is `VITA-` and four characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0, O, 1,
I, L). The person who **shows** a code owns its record; the person who **types** it claims it.

```
Sam (shows the code)                    public database                     Alex (types it)
--------------------                    ---------------                     ---------------
open Buddy / pairing screen
announce(VITA-7F3K)  ── fetch ────────▶ pairing-VITA-7F3K: none
                     ── create ───────▶ {owner: sam, claimant: ""}
                                                                            types VITA-7F3K, Connect
                                        ◀──────────────── fetch ──────────  claim(VITA-7F3K)
                                        {owner: sam, claimant: ""}
                                        ◀──────────────── save ───────────  {owner: sam, claimant: alex}
                                                                            save succeeded → write
                                                                            buddy.ck.linkedTo = sam
                                                                            "You're connected! 💚"
poll (every 4 s on the pairing
screen, 20 s on the hub)
resolveClaimant()    ── fetch ────────▶ {owner: sam, claimant: alex}
write buddy.ck.linkedTo = alex
"They got your code — you're connected! 💚"
```

The rules, each pinned by a test in `BuddyPairingTests`:

1. **Only the owner creates a record.** Typing a code never creates one. (It used to: a
   typo created the record with the typer as owner and answered "You're connected!".)
2. **A code connects only when** its record exists, belongs to someone else, and is
   unclaimed or already claimed by me.
3. **The device is linked only after the claim is saved.** A failed save leaves no trace
   and the user can try again.
4. **Two claims that race:** the save carries the record's change tag, so the second is
   refused, re-reads the record, and is told the code is already paired.
5. **Typing the same code twice** finds my own claim and writes nothing.

`announce` runs when a Buddy screen's model is created while unpaired and at every poll
while unpaired. If the record under my code belongs to someone else (two users minted the
same code, or a record left by a build that let the typer create one), I mint a new code
and announce that.

## 4. Publishing my day

`BuddyStateComposer.compose` builds my day from the same data the Today tab reads;
`BuddyViewModel.publishIfLinked` publishes it. Triggers:

| Trigger | Where |
|---|---|
| 6 s after anything publish-worthy changes (a log on any tab, or the sharing switch) | `BuddyAutoPublisher` |
| The app goes to the background | `BuddyAutoPublisher`, and the Buddy screen if it is open |
| The app comes to the front and the last publish failed, or the last success is over 6 h old | `BuddyAutoPublisher` |
| The Buddy screen opens; a new day begins while it is open; a pairing has just been made | `BuddyHomeView` |

Each trigger asks the service whether this phone is paired **at that moment**; it is not
remembered from launch. (It used to be: the auto-publisher did not learn about a pairing
made on the Buddy screen until the next cold launch.)

All of them go through one `BuddyPublishCoordinator`. While one publish runs, a newer one
waits (only the newest is kept) and runs after it, so two fetch-modify-saves of
`snapshot-<me>` never overlap. The coordinator also holds "last published at" and "last
publish failed", so the Buddy screen's footer reports a failure wherever it happened.

After a publish, `BuddyMilestones.pending` lists the goals met that have not been cheered:
calories, protein, steps, water (once a day each) and the streak tiers 3, 7, 14, 30 (once
per streak each). Each is sent as a nudge, and **recorded as sent only if the send
succeeded**, so one that failed is tried at the next publish. A streak tier sent late says
the real number of days.

## 5. Reading the buddy's day

`BuddyViewModel.refresh` → `service.fetchBuddySnapshot()`:

1. `resolveClaimant`: if I am unpaired and someone claimed my code, I am now paired.
2. `verifyLink`: if the pairing record is known (`linkedVia`), read it. If it no longer
   names the two of us, the buddy ended the pairing: clear my link and report it. A read
   that fails proves nothing and changes nothing. A pairing from an earlier build has no
   `linkedVia` and is never unlinked by this check.
3. Fetch `snapshot-<buddy>`. None yet is a normal state.

What is shown depends on how old the snapshot is (`BuddyFreshness`, whole calendar days in
my time zone):

| Last publish | Shown |
|---|---|
| Today | The buddy's day and the face-off. |
| 1 or 2 days ago | The same, with the time in amber and a footer line: "Sam's last update was 1 day ago, so what you see is from then." |
| 3 or more days ago | Their numbers are **not** shown. A card says "Sam hasn't shared an update since Nov 14", why that can happen, and offers **Unpair from Sam**. |
| Never | "You're paired. Waiting for their first update". Notes can already be sent. |

Nudges are fetched by a query on `toUserID`; the app-icon badge is set to the unread count
whenever the inbox loads and when a note is read.

## 6. Unpairing

Buddy screen → ⋯ → **Unpair from Sam** (or the button on the stale card) → an alert:
*"You two will stop seeing each other's day and notes, and the day you shared is removed
from iCloud. Everything you logged stays on your phone. To pair again, one of you types the
other's new code."* → **Unpair** / **Stay paired**.

`BuddyViewModel.unpair` → `service.unlink()`:

1. Forget the link **on this device first**. Leaving never waits for the network.
2. Best-effort, in the backend: if I typed the code, take my claim off the buddy's pairing
   record; delete the pairing record of my own code; remove the per-buddy push
   subscription; delete `snapshot-<me>`.
3. Mint a new pairing code and announce it. The code that was shared no longer works.

One exception to "delete my own code": if someone **other** than the buddy I am leaving
has typed my code and is waiting, their claim is kept, my code stays, and I am paired with
them straight away. That is the buddy who reinstalled, came back under a new id, and typed
my code while my phone was still linked to their old one.

While unpaired the inbox is not fetched and the badge is cleared: notes are between me
and a buddy.

The other side finds out at its next refresh, through step 2 of section 5: "Sam ended the
pairing. You can pair again whenever you both like." If step 2 could not reach the backend,
or the other side's pairing predates `linkedVia`, the other side is not told; it keeps a
link whose data goes stale, and the stale card offers it the way out.

## 7. Pushes

Two CloudKit query subscriptions: a nudge addressed to me (an alert), and my buddy's
snapshot changing (silent). `AppDelegate` classifies an incoming push (`BuddyPush`), and
for one that is or may be about the buddy calls `BuddyRemoteChangeCenter.deliver`, which
runs every registered refresh and returns **when they have finished, or after 20 seconds**.
Only then does iOS get its answer (`.newData`, `.noData` when no Buddy screen is in memory,
`.failed` on the timeout). The private-database mirror's own pushes start no buddy refresh.

A refresh is registered by the Buddy screen's model only. With no Buddy screen in memory a
push refreshes nothing; the next time the screen opens it fetches.

## 8. Every failure, and what the user sees

Pairing failures are shown under the code field and stay until the code is edited.

| What happened | What the code does | What the user sees |
|---|---|---|
| Typed something that cannot be a code (`VITA-10OL`, `sam`) | Refused before any network call. | "That doesn't look like a pairing code. A code is VITA- and four more characters, like VITA-7F3K; codes never use 0, O, 1, I or L." |
| Typed a well-formed code nobody has shared: a typo, **or** the buddy's phone has not uploaded it yet. The typer's device cannot tell these apart. | Nothing created, nothing persisted. | "Nobody has shared that code. Check the letters with your buddy. If they opened their pairing screen only a moment ago, their phone may still be uploading it: wait a few seconds and try again." |
| Typed my own code | Nothing written. (If my buddy has already typed it, that pairing is adopted instead.) | "That's your own code. Share it with your buddy, and type theirs here." |
| The code is already paired with someone else, including losing a race | The existing claim is left alone. | "That code is already paired with someone else. If your buddy was paired before, ask them to tap Unpair on their Buddy screen, then use the new code they see." |
| The claim could not be saved (offline, throttled, **or the security role does not allow it**, section 10) | Nothing persisted; retry works once the cause is gone. `buddy/ck pairing.update: CKError …` in Diagnostics. | "Couldn't reach iCloud just now. Nothing was changed; check your connection and try again." After two failures the screen offers "Still stuck? Check the connection", which runs the CloudKit diagnosis. |
| Not signed in to iCloud | Every call fails before it starts. | Section 9. |
| My code's record belongs to someone else | A new code is minted and announced. | The code on the pairing screen changes. |
| A publish fails (offline; **or the Production schema lacks a field**, section 10) | Recorded as failed; retried when the app next comes to the front, and at the next change. A schema failure fails the same way every time until the schema is deployed. | Footer: "Your last update hasn't reached iCloud yet — it'll retry on its own." |
| A background poll cannot reach iCloud | The notes and the buddy's day already on screen are kept. Logged once, then counted. | One banner per outage: "Can't reach iCloud right now. What you see here may be out of date; it will catch up on its own." |
| A nudge fails to send | Nothing is queued; the user can tap again. | "Couldn't reach iCloud just now. Nothing was changed; check your connection and try again." |
| An automatic cheer fails to send | Not recorded as sent; tried again at the next publish. | Nothing. |
| Marking a note read fails (**or is not allowed**, section 10) | The note shows as read on this phone until the next fetch, then as unread again. | The "new" dot comes back. |
| The buddy unpaired | My link is cleared at my next refresh. | "Sam ended the pairing. You can pair again whenever you both like." and the pairing screen. |
| The buddy reinstalled or changed phones | Nothing tells my phone. If they type my code meanwhile, their phone pairs and mine follows when I unpair from the old id. | After 3 days, the stale card (section 5). |
| Tapping a nudge before the buddy has published | Sent: the recipient is known from the link. | "Sent cheer 💛" |

The Diagnostics log (Settings → tap the version line seven times) has the exact `CKError`
behind every "couldn't reach iCloud". Being unpaired is not written to it, and a line that
repeats is written once and then counted for five minutes.

## 9. Signed out of iCloud

`CKContainer.accountStatus()` is checked before every call. `noAccount` and `restricted`
become `BuddySyncError.iCloudAccountMissing`; `couldNotDetermine` and
`temporarilyUnavailable` are treated as an outage.

- The pairing screen shows, at the top and for as long as it is true: "Buddy needs iCloud.
  Sign in to iCloud in the Settings app (your name at the top), then come back and try
  again." The code is shown but has not been uploaded, so nobody can claim it yet.
- Tapping Connect shows the same sentence under the field. Nothing is persisted.
- A paired user who signs out keeps their link (it is on the device) and sees the last
  fetched data, with the same sentence in the hub's footer. Nothing is published and no
  notes arrive until they sign in.
- No crash and no hang. There is no observer of `CKAccountChanged`; the state is noticed
  at the next call, which is at most 20 seconds away while a Buddy screen is open.
- The id is not tied to the iCloud account: signing in as someone else on the same install
  keeps the same buddy id and link.

The Simulator never reaches this code: it uses the stand-in.

## 10. What only the owner can check, in the CloudKit Dashboard

Container `iCloud.com.bryanram.victoria`. Neither can be seen from the code or a test.

**1. The Production schema has every field this build writes.** CloudKit creates types and
fields on first write in Development only. A Production save that carries a field the
schema lacks fails whole.

- Public database, **Production**: `BuddyPairing` (`pairingCode`, `ownerUserID`,
  `buddyUserID`), `Nudge` (`fromUserID`, `toUserID`, `kindRaw`, `text`, `createdAt`,
  `isRead`), `BuddySnapshot` (`ownerUserID`, `displayName`, `dayStreak`, `characterMoodRaw`,
  `loggedToday`, `lastActive`, `stepsToday`, `stepGoal`, `waterToday`, `waterGoal`,
  `workedOutToday`, `workoutSummary`, `sharesFullData`, `trendWeightLbs`, `goalWeightLbs`,
  `weeklyRateLbs`, `caloriesEaten`, `calorieTarget`, `proteinEaten`, `proteinTarget`,
  `carbsEaten`, `carbTarget`, `fatEaten`, `fatTarget`, `todayFoods`).
- Indexes: `Nudge.toUserID` Queryable, `Nudge.createdAt` Sortable,
  `BuddySnapshot.ownerUserID` Queryable.
- This change adds **no** field and no record type.
- Symptom when one is missing: `buddy/ck publish.save: CKError 12` (invalidArguments) in
  Diagnostics, and the footer's "hasn't reached iCloud yet" that never clears. The
  diagnosis in Settings → Diagnostics runs a real publish and names the step that fails.
- The audit's S1 is the same question for the private database: that the `CD_*` record
  types of the newer SwiftData models exist in Production.

**2. The public database's security roles let one iCloud user write a record another
created.** With the default roles only a record's creator may write it. Three writes in
this app are by the other user:

| Write | Record | Created by | Written by |
|---|---|---|---|
| Claiming a code | `BuddyPairing` | the owner of the code | the one who types it |
| Unpairing as the one who typed it | `BuddyPairing` | the owner of the code | the one who typed it |
| Marking a nudge read | `Nudge` | the sender | the recipient |

Check under Schema → Security Roles that the authenticated role (`_icloud`) has **Write**
on `BuddyPairing` and `Nudge`, in **Production**. Two devices signed in to the same Apple
ID hide the problem, because then the creator and the writer are the same user.

- Symptom for the claim: Connect always answers "Couldn't reach iCloud just now", and
  Diagnostics has `buddy/ck pairing.update: CKError 10` (permissionFailure). Before this
  change the same failure left a one-sided link that the next poll announced as
  "connected"; now it leaves the user unpaired.
- Symptom for read receipts: `buddy/ck markRead: CKError 10`, and the "new" dot returning
  after every fetch.

Deleting my own pairing record and my own snapshot on unpair needs nothing: the creator
may always write.

## 11. The Simulator, and looking at each state

The Simulator uses `LocalMockSyncService`: the real handshake over an in-memory store that
holds the simulated buddy's code **`VITA-SAM2`** and one that is taken, **`VITA-TAKN`**.
Typing `VITA-SAM2` pairs; anything else fails as on a device.

DEBUG launch arguments, on top of `--seed-demo --demo-gain --demo-screen buddy`:

| Argument | State |
|---|---|
| `--demo-buddy` | Paired, with two notes in the inbox. |
| `--demo-buddy-state stale` | Paired; Sam last published nine days ago. |
| `--demo-buddy-state silent` | Paired; Sam has never published. |
| `--demo-buddy-state unpaired` | No buddy. |
| `--demo-buddy-ui unpair` | The unpair confirmation, open. |
| `--demo-buddy-ui unpair-confirmed` | Does what its Unpair button does. |
| `--demo-buddy-ui pairing-wrong` / `-own` / `-claimed` / `-shape` | The pairing screen after that failed attempt. |
| `--no-reminder-prompt` | Keeps the notification permission alert off the screen. |

Screenshots of each are in `docs/screenshots/review/buddy-*.png`.

## 12. Not verified, and not solved here

- **No CloudKit call in this change has been run.** `CloudKitPairingStore` (fetch, create,
  the change-tag-conditional update, delete), the snapshot delete on unpair, and the
  account-status mapping were read against Apple's documentation, not executed. In
  particular: that saving a fetched `CKRecord` whose server copy changed fails with
  `serverRecordChanged`, and that saving a new record over an existing name does too.
- **Push classification on a real payload.** `BuddyPush` uses CloudKit's parser; anything
  it cannot place is treated as possibly about the buddy, so nothing that refreshed before
  stops refreshing. Whether the private mirror's pushes parse as database notifications
  was not observed.
- **The badge.** The app now sets it to the unread count when the inbox loads. The nudge
  subscription still asks CloudKit to badge (`shouldBadge`), and that server-side count
  only grows, so a push that arrives while the app is closed can show a number larger than
  the unread count until the Buddy screen is opened. Turning `shouldBadge` off means
  re-creating the subscription on every device, which was not done without a device to
  test it on.
- **A background publish has no background-task assertion** (audit S5), and the inbox
  query has no limit or age filter.
- **The public database is not private.** Any signed-in user of the app who knows or
  guesses a user id can read `snapshot-<id>` and create a `Nudge` addressed to it, paired
  or not; a pairing code has about 920,000 values. Unpairing removes my snapshot and
  retires my code, which limits what an ex-buddy holds, but the fix is a CKShare or a
  shared zone between the two users.
- **"Share my full stats" is on by default** (`UserProfile.shareFullStatsWithBuddy`). The
  pairing screen now says what will be shared for the current setting; whether the default
  should be off is the owner's decision.
- **Identity does not survive a reinstall**: `docs/buddy-identity.md`.
