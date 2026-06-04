# Workout rebuild — design (for sign-off)

Bryan's big ask (2026-06-04). He chose: **design-first**, **new bottom tab**, label **"Exercise"**,
**declutter Progress** too. This doc is the design to approve BEFORE building.

## The vision (his words, distilled)
A workout log that learns your training. Pick the **type** (gym / run / soccer / …). For a **gym**
session, tap the **focus** (push / pull / legs / arms / core), then a grid of **small square machine
icons** — tap the ones you actually did, with an **optional weight** each. Focus does NOT lock you in
(did legs but also some forearm → still tappable). The machine list is huge, so **your most-recent /
most-popular surface first**; a missing machine → **describe it to Vita → logged for us to add**
(optional photo). Over time it **tracks strength per machine** (going up?), and Vita **suggests the
day** ("legs are overdue" / "you've hit everything — maybe a rest day, your call"). **Tap any past day
to see everything you did**, like the food log.

## Data model (new)
- `WorkoutSession` (@Model): `id`, `date` (startOfDay + time), `type` (enum: gym, run, walk, cycle,
  swim, sport, yoga, other), `focuses` (gym only — Set<MuscleFocus>: **Chest, Back, Shoulders, Arms,
  Legs, Core, + Other (custom)** — body-part split, covers PPL too; stored as a string for CloudKit),
  `durationMinutes?`, `distance?`/`pace?` (cardio), `notes?`. CloudKit-safe
  defaults throughout (mirror BuddySnapshot/ChecklistItem).
- `ExerciseEntry` (@Model): `id`, belongs-to `WorkoutSession`, `machineKey` (stable id into the
  catalog), `displayName`, `iconName` (SF Symbol or asset), optional `weightLbs?`, optional `reps?` /
  `sets?`. One row per machine done. (Strength-over-time = query ExerciseEntry by machineKey, chart
  `weightLbs` over date.)
- `MachineCatalog` (static, in-code to start): a curated list of common machines/exercises, each
  `{key, name, icon, muscleFocus, isCardio}`. "Popular/recent first" = sort by the user's own
  `ExerciseEntry` history (most-recent + most-frequent), then the curated defaults.
- `MachineRequest` (@Model, Phase 3): `name`, `notes`, optional `imageData`, `date` — synced so we
  can collect + implement them.

## Screens
### 1. Log flow (the core — like food logging: tap icons → save)
```
  ┌─ New workout ───────────────┐     ┌─ Gym · pick focus ──────────┐     ┌─ Machines (tap what you did)┐
  │  What did you do?           │     │  [Push] [Pull] [Legs✓]      │     │  ⊞ Leg press ✓   ⊞ Squat    │
  │  ⊞ Gym   ⊞ Run   ⊞ Soccer   │ →   │  [Arms] [Core]              │ →   │  ⊞ Leg curl ✓    ⊞ Calf     │
  │  ⊞ Walk  ⊞ Cycle ⊞ Yoga …   │     │  (tap any — not locked)     │     │  ⊞ Hip thrust    ⊞ + more   │
  └─────────────────────────────┘     └─────────────────────────────┘     │  tap ✓ → optional weight ▸  │
                                                                          │  [ Save workout ]           │
                                                                          └─────────────────────────────┘
```
- Square machine icons in a wrapping grid; tap toggles ✓; a tapped one reveals an optional weight
  field (a stepper / quick keypad). Your recent machines float to the top. A "＋ add a machine"
  tile → the request-to-Vita flow.
- Cardio types (run/soccer/…) skip focus+machines → a simple duration/distance entry.

### 2. Day detail (tap a past day)
```
  ┌─ Thu, Jun 4 · Gym (Legs) ───┐
  │  💪 Leg press   135 lb       │
  │  💪 Leg curl     90 lb       │
  │  💪 Hip thrust   — (no wt)   │
  │  45 min · 3 machines         │
  └──────────────────────────────┘
```

### 3. Strength + suggestions (Phase 2)
- Per-machine mini line-chart of `weightLbs` over time + a PR badge.
- Vita day-suggestion card: "Legs are overdue (last: 6 days ago)" / "You've trained every group —
  today could be a rest day 💛 (optional)". Driven by the focus history, surfaced on Home/Workouts +
  available to the coach context.

## Placement
New **bottom tab** → Today · Nutrients · Progress · **Workouts** · Vita · Buddy (6 tabs). The dumbbell
icon. (Trade-off: 6 tabs is tighter; if it feels crowded we can merge Workouts under Progress.)

## Phases
1. **Foundation + gym logging:** the models, the catalog, the log flow (type→focus→machines→optional
   weight), the day-detail view, the new tab. Cross-day machines allowed.
2. **Intelligence:** strength-over-time charts + PRs; Vita's day-type / rest-day suggestions.
3. **Catalog + community:** describe-a-missing-machine → MachineRequest (+ optional image); grow the
   catalog.

## Machine catalog (web-researched — 24 Hour Fitness / LA Fitness / USC rec / commercial)
Seed list; "Other" + the describe-to-Vita flow covers anything missing. Each machine is tagged by
muscle group; the log grid shows YOUR recents first, then these defaults.

- **Chest:** Chest press · Incline chest press · Pec deck (chest fly) · Cable crossover · Bench press · Push-up
- **Back:** Lat pulldown · Seated cable row · Assisted pull-up · T-bar / row machine · Back extension · Deadlift
- **Shoulders:** Shoulder press · Lateral raise · Reverse pec deck (rear delt) · Cable lateral raise · Overhead press
- **Arms:** Bicep curl · Preacher curl · Tricep pushdown · Assisted dip · Cable curl · Skullcrusher
- **Legs:** Leg press · Leg extension · Leg curl · Hack squat · Smith machine · Calf raise · Hip thrust · Hip abductor · Hip adductor · Squat rack
- **Core:** Ab crunch machine · Cable crunch · Captain's chair (leg raise) · Roman chair / back extension
- **Cardio (run / other types):** Treadmill · Bike · Elliptical · Rower · Stairmaster

(Sources: bestusedgymequipment.com, xcelerategyms.com, vasafitness.com gym-machine lists; 24 Hour
Fitness uses Hoist selectorized machines per setforset.com.)

## Open questions for Bryan
- Reps/sets: track them, or **just optional weight** to start (simpler)?
- Machine icons: SF Symbols (fast, consistent) vs custom pixel/asset icons (cuter, lots of art)?
