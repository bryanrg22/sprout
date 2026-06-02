# Victoria — Future Implementations

A running list of ideas we've discussed but deliberately deferred, so we don't lose them.
Ordered roughly by when we'd tackle them. Nothing here is built yet.

---

## 1. Social / "accountability buddy" layer  *(the big one — last major phase)*

Origin: Victoria once used an app with an ex where both people had to check in daily and
keep a shared character alive — a fun, unique couple thing. We want that energy, done kindly.

- **Bryan builds his own version** on the same platform, personalized to him (different
  targets/goals — he and Victoria don't do the same things).
- **See each other's day**: steps, progress, stats. Mutual **nudges** (she nudges him, he nudges her).
- **Shared companion character**: extends the solo "Sprout" companion — BOTH must hit their
  goals to keep it thriving; if one slips, it droops. Keep it health-POSITIVE — never weaponize
  it to shame her ("thrives when nourished," gentle when not).
- Maybe small shared games / a couple mini-activity.
- **Needs a backend/sync** (two devices sharing state). The app is currently fully local
  (SwiftData + App Group, no account). Research cheapest path when we get there:
  CloudKit shared records vs. a tiny serverless backend.
- Tone: friendly accountability + fun, never pressure/guilt.

## 2. Pixel-art avatar of Victoria

- Turn the companion ("Sprout") — and/or a profile avatar — into a **pixel-art version of
  Victoria herself**. Bryan will provide a photo to base it on.
- Companion mechanic already built with placeholder SF-Symbol art; there's a
  `// TODO: swap in pixel-art` seam in `CompanionCard.swift`.
- Could also use pixel-art for achievements / milestone celebrations.

## 3. Deeper meal personalization  *(later phase)*

- Ask what she normally eats / her typical meals → recommend similar but **healthier** swaps.
- How to meal-prep; best times to eat.
- Thesis: existing apps lack deep personalization. This app is a CENTRALIZED personal health
  profile an AI agent can consume to truly understand her and coach specifically.
- Photo logging upgrade: if she adds context ("it's Chipotle") → web-search real nutrition;
  if no context → AI just guesses (never block asking for more).

## 4. AI that learns & evolves over time

- The proactive insight engine (built, v1, on-device rules) should grow into an agent that
  **accumulates a model of her over weeks** — notices multi-week patterns, adapts suggestions
  ("you tend to under-eat on Mondays — want to prep Sunday night?").
- Persistent, evolving memory of the user — not a stateless daily recap.
- Build cost-consciously per `RESEARCH_ai_native.md` (cheap on-device gate → occasional cached LLM call).

## 5. Personality / Easter eggs / polish

- Selective blue accents (don't make everything blue).
- Easter eggs + personal/funny touches (Bryan is funny) — make it feel personal to her.
- Opt-in daily push notification for the proactive insight (0–1/day, off by default).

---

*See also: `RESEARCH_onboarding.md`, `RESEARCH_ai_native.md`, `DESIGN_SPEC.md`.*
