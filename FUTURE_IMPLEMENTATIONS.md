# Sprout — Future Implementations

What we've discussed but haven't built yet. (Shipped ideas were removed — the social/buddy
layer and the pixel-art avatars are done and live on TestFlight.) Ordered roughly by priority.

---

## 1. Workout intelligence — Phase 2 & 3  *(biggest real feature left)*

Phase 1 shipped (Workouts tab, gym/cardio logging, machine grid, day detail, recents-first).
Still to build (full spec in `docs/workout-redesign.md`):
- **Strength over time:** per-machine mini line-chart of `weightLbs` over date + a PR badge
  (the data is already there in `ExerciseEntry` — this is the view + query).
- **Vita day suggestions:** "legs are overdue (last: 6 days ago)" / "you've trained everything —
  today could be a rest day 💛," driven by focus history, surfaced on Workouts + in Vita's context.
- **Phase 3 — request-a-machine:** describe a missing machine → `MachineRequest` (+ optional photo),
  synced so we can grow the catalog.
- **Streak gap:** logged workouts don't yet count toward the logging streak — wire them in.

## 2. Deeper meal personalization

- Ask what she normally eats / her typical meals → recommend similar but **healthier** swaps;
  meal-prep tips; best times to eat. (Photo→macros, smart food suggestions, and nearby places
  already exist — this is the "learn her usual meals and coach them" layer.)
- Photo logging upgrade: if she adds context ("it's Chipotle") → web-search real nutrition;
  if no context → AI guesses (never block asking for more).

## 3. AI that learns & evolves over weeks

- The proactive insight engine (on-device rules), CoachMemory, and the adaptive Plan (adapts on
  review) are in. The next step is an agent that **accumulates a model of her over weeks** —
  multi-week patterns ("you tend to under-eat on Mondays — want to prep Sunday night?").
- Build cost-consciously per `RESEARCH_ai_native.md` (cheap on-device gate → occasional cached LLM call).

## 4. Pixel-art people roster  *(art BUILT — in-app placement still TBD)*

A roster of hand-authored pixel sprites of artists Bryan likes, in the same `PixelArtView` format
as pixel-Victoria / pixel-Bryan (mood + blink machinery, so they animate the same). **Built so far,
in `Victoria/Features/Companion/PixelArtists.swift`** (verify any time with `--pixel-gallery`):
- **Peso Pluma** (`PixelPeso`) — textured fade, freckles, black adidas track jacket.
- **Tito Doble P** (`PixelTito`) — signature thin gold glasses, wavy hair, light beard, quarter-zip.
- **JOP** (`PixelJOP`, Fuerza Regida) — slicked-back-with-length hair, goatee, earring, cream sweater.
- **Chuyin** (`PixelChuyin`, the FR mascot) — cream ball-head, Burberry beanie + red band, huge eyes, R chain.

Reference photos live under `docs/pixel-art-refs/<name>/`. STILL TBD: **where they actually get used**
(collectible companions? cameo Easter eggs? buddy-page guests? a `companionAvatar`-style picker?),
plus more artists Bryan will name (he adds ref photos → spin a subagent that iterates via the
`/tmp/render_pixel.swift` renderer, same as these). The `PixelGalleryView` + `--pixel-gallery` flag
are DEBUG-only scaffolding for previewing the roster.

## 5. Personality / Easter eggs / polish

- **Wire the opt-in daily push toggle** — `NotificationService` already has the daily check-in;
  it just needs a Settings switch (0–1/day, off by default).
- Selective blue accents (don't make everything blue).
- Easter eggs + personal/funny touches — make it feel personal to her.

---

*See also: `docs/workout-redesign.md`, `RESEARCH_ai_native.md`, `DESIGN_SPEC.md`.*
