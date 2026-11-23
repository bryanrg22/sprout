# Buddy identity: why a reinstall strands the partner, and what a durable id would take

**Status: a design, not implemented.** What is implemented is the honest fallback: the
partner's screen stops showing old data as current and offers to unpair
(`docs/buddy-sync.md`, sections 5 and 6). This file says why the durable fix was not built
in the same change, and what it is.

## The defect (audit D-V4, L-B11)

A user's buddy id is a UUID minted into `UserDefaults` at first use
(`BuddyViewModel.resolveMyUserID`, key `buddyMyUserID`), and the link to a buddy is in
`UserDefaults` too. Deleting the app deletes both.

Sam and Alex are paired. Sam deletes Sprout and installs it again, or moves to a new phone
without restoring a backup. Sam's install now has a new id, a new pairing code and no
link. Alex's phone is still linked to the old id. Nothing publishes under the old id again,
so Alex's phone keeps fetching `snapshot-<old id>`, which never changes, and Alex's nudges
are addressed to an id nobody reads.

Before this change Alex saw the frozen snapshot presented as Sam's day, with no way out
short of deleting the app as well: `unlink()` had no caller.

## What is implemented

- After 3 days without a publish, Alex's Buddy screen replaces Sam's numbers with "Sam
  hasn't shared an update since <date>", says a reinstall or a new phone is a likely
  cause, and offers **Unpair** (`BuddyFreshness`, `BuddyStaleCard`).
- **Unpair** exists (toolbar menu and the stale card). After it Alex types Sam's new code,
  or Sam types Alex's new one.
- If Sam, back under the new id, types Alex's code before Alex has unpaired:
  - when the old pairing went through that code (Alex showed it, old Sam typed it), Sam is
    told the code is already paired and to ask Alex to unpair;
  - when it did not (Alex typed old Sam's code, so Alex's own code was never claimed),
    Sam's phone pairs at once, and Alex's phone, which does not switch buddies by itself,
    pairs with the new id the moment Alex unpairs from the old one.

`BuddyPairingTests` walks through both with simulated phones:
`testAfterAReinstallThePartnerSeesStaleNotCurrentAndCanPairAgain` and
`testABuddyWhoCameBackAndTypedMyCodeIsWhoIAmPairedWithOnceIUnpair`.

What it does not do: nothing tells Alex's phone on the day Sam reinstalls. Alex finds out
three days later, from the stale card.

## Where a durable identity could live

| Option | Survives delete + reinstall | Survives a new phone | Cost and risk |
|---|---|---|---|
| **A. Keychain** (`kSecAttrAccessibleAfterFirstUnlock`, this device only) | Yes, today | Only through an encrypted backup restore | Apple documents no guarantee that keychain items outlive the app, and has said the behaviour may change. A user who deletes the app to start over keeps their old public id. The repository already has a case of state split between Keychain and `UserDefaults` going wrong after a reinstall (audit L-B9, L-B10). |
| **B. Keychain, iCloud-synchronised** | Yes | Yes, if iCloud Keychain is on | As A, plus: depends on a setting the app cannot see, arrives late on a new device, and two of the user's devices now publish under one id. |
| **C. The CloudKit user record id** (`CKContainer.userRecordID()`) | Yes | Yes | Nothing to store. It is the same on every device signed in to the account, for this container. It needs a signed-in account and a network round trip before the id is known, so first use is asynchronous. Changing ids breaks every existing pairing unless migrated. |
| **D. The SwiftData `BuddyLink` model**, mirrored to the private database | Yes, once the import arrives | Yes, once the import arrives | The model exists and is unused. The id is unknown until the private-database import lands, which can be seconds or minutes after first launch; minting a temporary id in the meantime recreates the defect. |

## Recommended: C, the CloudKit user record id

It is the only option that needs no storage of its own and is correct by construction: the
buddy feature is CloudKit, the id is CloudKit's own name for the user in this container,
and every record the user creates in the public database is already stamped with it
(`creatorUserRecordID`), so using it as the buddy id exposes nothing new.

What it changes:

1. **`myUserID` becomes asynchronous.** Today `BuddyViewModel` has its id in `init`. With
   C the first launch has no id until `userRecordID()` returns, so the view model needs an
   "identity not known yet" state, and the service is created after it resolves. The id is
   then cached in `UserDefaults` so later launches are synchronous.
2. **Migration.** An existing user has a UUID id that their buddy's phone is linked to.
   On first launch of the new build: fetch the user record id; if `buddyMyUserID` holds a
   different value, keep publishing `snapshot-<old id>` as well for a transition period,
   and write the new id onto the pairing record so the buddy's phone can follow it
   (`verifyLink` already re-reads that record; it would adopt a changed id instead of
   unlinking). Both phones need the new build before the old id can be dropped.
3. **The link moves with it.** With a stable id the partner's phone is still linked to the
   right user after a reinstall; the reinstalled phone needs to recover *its* link. The
   pairing record already names both users, so the reinstalled phone can find it by
   querying `BuddyPairing` for its own id, which needs `ownerUserID` and `buddyUserID`
   marked Queryable in the Dashboard.
4. **Two devices, one user.** Both publish `snapshot-<id>`. The publish is already a
   fetch-modify-save, so the later one wins; that is the right answer for one person's day.

## Why it was not built here

The rule for this change was that a durable identity is implemented only if it can be
tested. C cannot be tested without a CloudKit container: `userRecordID()`, the migration
on two real installs, the query-by-id recovery and the new indexes all need a device, two
iCloud accounts and the Dashboard. A, which could be unit-tested, is the option with the
worst trade-off: it works by relying on behaviour Apple does not promise, and it would have
to be migrated away from to reach C.

## What it takes to do

- Two devices on different iCloud accounts, and Dashboard access.
- An `identity` seam in front of `BuddyViewModel` (`resolve() async throws -> String`),
  with the current UUID behaviour as one implementation, so the asynchronous path can be
  tested with a scripted resolver before CloudKit is involved.
- The migration in step 2 above, tested with the two-phone double in
  `VictoriaTests/Support/BuddySyncTestSupport.swift` (old-id phone, new-id phone, one
  pairing record), then once on devices.
- Dashboard: `BuddyPairing.ownerUserID` and `buddyUserID` Queryable, deployed to Production.
