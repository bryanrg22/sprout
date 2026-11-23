# Changelog

What changed, per version, for the people using the app and for the people building it.
Sections cited as "EVAL_REPORT n" are in `docs/EVAL_REPORT.md`.

## Unreleased (will ship as 2.1, build 16)

### Fixed

- VoiceOver no longer reaches the hidden half of the Home | Gym switch (its content; one
  tab button is still under check), and secondary text in the light look is darker so it
  meets the contrast minimum (EVAL_REPORT 29).

- **Updating never starts you over.** An update installed over the old app keeps
  everything and goes straight to Today (measured from build 15). If an update cannot
  open your data, the app now says so instead of showing onboarding on an empty app; a
  reinstall first looks for your profile in iCloud; and if two profiles exist the older
  one is used (EVAL_REPORT 27).
- Onboarding no longer chooses "Female" for you: the sex used for the calorie estimate
  is a required choice with nothing pre-selected.

- **Today's checklist was silently falling back to the generic one about three times in
  ten on Claude.** The model's answer came back in a shape the app could not read; the
  app now reads it (EVAL_REPORT 22).
- **Buddy pairing tells the truth.** A wrong code no longer says "You're connected!", you
  can unpair, and a buddy who has stopped sharing is shown as such instead of looking
  current. Nudges for a milestone are sent once (EVAL_REPORT 19).
- Reminders are set up on the first launch after onboarding, not the second.
- The 7- and 14-day achievements no longer unlock from imported step counts.
- **Changing your goal changes your targets.** With a plan, switching between losing and
  gaining left the old plan's calories in force. The plan's numbers now apply only to the
  direction they were written for, and Settings says what a change does (EVAL_REPORT 16).
- **Asking Vita to switch to kilograms can no longer corrupt your weights.** Kilograms
  are not supported yet, and Vita now says so instead of relabelling pounds.
- A key pasted after a reinstall is saved for the right provider.
- Prompts no longer assume who you are: no "her", no weight-loss framing for someone gaining.
- Vita's tools no longer describe every user as "she" (EVAL_REPORT 24).
- The closing note of onboarding no longer starts with a lower-case "friend," when no name was given.
- **A short note is no longer lost when a newer Claude model is selected.** Those models
  could spend a note's whole length limit thinking and return nothing; the app showed its
  built-in wording and said nothing. They are now asked not to think for these one-line
  rewrites, and a reply lost this way is logged by name (EVAL_REPORT 25).
- The daily brief is no longer thrown away when the model forgets a line break.
- The food lookup no longer sends a personal email address with each request.

- **The widget no longer shows someone else's numbers.** When it could not read your
  data (after a phone restart, before the first unlock) it drew a built-in sample profile
  as if it were yours. It now shows "Open Sprout to refresh" and retries in five minutes
  (EVAL_REPORT 11).
- The widget's calories, steps and water reset at midnight instead of showing yesterday's
  totals until the app is opened.
- **On OpenAI's newer models, "log 20 oz of water" logged one bottle instead.** Found by
  the model comparison, fixed, and re-measured on five models (EVAL_REPORT 10).
- The "good to see you" note after a few days away is no longer thrown away after being
  rewritten (its own wording tripped the app's guardrail).
- **Privacy:** turning off "Share my full stats with your buddy" now actually stops
  your weight, calories, macros and food names from being uploaded. Before, they were
  uploaded and only hidden on your buddy's screen (EVAL_REPORT 3, D-V1).
- The Nutrients tab no longer saves a meal to yesterday when the app was left open
  overnight (L-B1).
- The "your goals changed since this plan was built" notice clears after a rebuild (L-B3).
- A protein target set through Vita without a plan is kept after a relaunch (L-B4).
- OpenAI models from the 6.x families can be used: the client chose the endpoint and
  token parameter by name prefix and would have sent them a request they reject
  (EVAL_REPORT 4).

### Added

- **A weekly competition with your buddy**, in the Buddy hub: a point a day for each of
  your own targets you hit (calories in your range, protein, water, steps, being active),
  Monday to Sunday, with last week's result. Only which targets were hit is shared, never
  a number (EVAL_REPORT 29).

- **Your week on Workouts:** how many of its 7 days you were active (anything logged, or a
  workout Apple Health or your tracker saw), each day tappable to see what you did, and
  arrows back through past weeks. Workouts your tracker detected now show on each day
  (EVAL_REPORT 28).

- **A chat that holds up.** Select text in Vita's replies and ask about just that part;
  copy, share or quote any message; long conversations open fast and load earlier
  messages as you scroll up; and when something fails Vita says what (offline, a rejected
  key, a rate limit with a countdown) and lets you retry without retyping (EVAL_REPORT 20).
- **More of the label.** Fiber, sugars and added sugars, saturated and trans fat, sodium,
  cholesterol, potassium, calcium, iron and vitamin D, per food and per day, from
  barcodes, label scans, photos, descriptions, Vita and manual entry. A value nobody knows
  is shown as unknown, never as zero, and each daily total says how many of the day's
  foods it covers (EVAL_REPORT 18).
- **Your own character.** A new step in onboarding, and "Make my character" in More → You,
  turns a photo into a pixel character. It needs an OpenAI key, asks before the photo is
  sent, never keeps the photo, and falls back to a built-in character if anything goes
  wrong (EVAL_REPORT 15). No real image has been generated yet.

- **Home and Gym.** A switch at the top of Today and of Workouts moves between everyday
  tracking (Today, Nutrients, Progress, the coach) and the workout screens. The app
  reopens on whichever you left it on (EVAL_REPORT 12).

### Changed

- New characters are drawn by `gpt-image-2.6-sunburst` at low quality: $0.035 each and
  closest to the built-in style, about 17 seconds (EVAL_REPORT 27).
- The personal note in onboarding is no longer in the source and is shown only to the
  person it is written for.

- On OpenAI, the insight line, weekly reflection, onboarding note and memory now run on
  current models chosen by measurement; nothing defaults to the deprecated
  `gpt-4.1-mini` any more (EVAL_REPORT 22).
- The daily brief is written by `claude-haiku-5-5` (Anthropic) or `gpt-6-luna` (OpenAI),
  chosen by measurement: equal or better on every case at a seventh and a quarter of the
  cost of the models they replace (EVAL_REPORT 10).

### For developers

- The AI clients can run under a scoped runtime (key, provider, model, transport,
  usage sink), so they are testable without a network or a stored key.
- Every model call names its task (`AITask`); per-task defaults are chosen by
  measurement (`AIConfig.measuredDefaults`, empty until the first evaluation is run).
- An evaluation harness (`Evals/`, `VictoriaEvals/`) with three datasets and their graders.
- CI (`.github/workflows/ci.yml`): tests with a minimum count, a Release build, a secret
  scan, tooling checks.
- Records: `docs/EVAL_REPORT.md`, `VictoriaTests/LEDGER.md`, `docs/test-evidence/`,
  `docs/DEVELOPING.md`, `AGENTS.md` as the single instruction file.
- Tests: 443 → 1,180 unit tests (3 are known defects pinned as expected failures), plus 18 offline evaluation self-tests.
- UI smoke flows: 24 end-to-end flows against a scripted model (EVAL_REPORT 17, 26), five of them
  through onboarding; each flow now starts from empty app defaults.
- Store verification: 44 tests through the production schema, and `tooling/verify_store.py`,
  which checks a store by SQL (EVAL_REPORT 13).
- First live model comparison: ten models, three tasks, 3,636 graded attempts, $6.23
  (EVAL_REPORT 10). `docs/GOALS.md` lists the objectives and the `/goal` condition that
  works through them.
- The character call was made for real: 18 images from three generated faces, all usable,
  $0.035 to $0.054 each. The image grader could not see them (the models return "solid"
  at alpha 253, not 255); it is fixed, calibrated, and a past run can be graded again for
  free with `Evals/regrade-avatars.sh` (EVAL_REPORT 23).

### Known and open

Listed with severity in EVAL_REPORT 3. The ones a user is most likely to meet: with a
plan, changing your goal does not change your targets until the plan is rebuilt (L-B2);
asking Vita to switch to kilograms corrupts weights (L-B7); widgets show yesterday's
numbers until the app is opened (L-B5); a mistyped buddy code says "You're connected!"
(D-V2).

## 2.1 (build 15), uploaded 2026-07-13

Travel-aware insights, the editable "What Vita has learned" notes, a full plan rebuild
when goals change, and a cache for plan research. This TestFlight build stopped opening
on 2026-10-11, 90 days after upload (EVAL_REPORT 7).

## 2.0 (build 14) and earlier

See `git log`.
