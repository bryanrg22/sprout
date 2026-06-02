# What an "AI-native" consumer app actually does with an LLM — and how to be proactive without burning money

Research brief for the Victoria weight-loss app (solo dev, one user, iOS, Claude-backed "Vita" coach).
Date: 2026-06-01. All load-bearing claims verified against 2+ sources; uncertainty flagged inline. Sources at bottom.

---

## TL;DR (read this if nothing else)

1. **"AI-native" does NOT mean "LLM running constantly."** The good apps (Whoop, Oura) are proactive on a **fixed daily rhythm** — a **morning outlook** and an **evening recap** — plus **on-demand chat**. They do **not** poll your data every 30 min and fire an LLM each time. ([Whoop](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/), [Oura](https://support.ouraring.com/hc/en-us/articles/39512345699219-Oura-Advisor))

2. **The winning architecture is "cheap gate, expensive brain":** plain deterministic code (rules over the health profile) runs for free, computes candidate insights, and **only when something crosses a threshold do you spend one LLM call** to phrase it warmly. The LLM is the *writer*, not the *detector*. ([Morph](https://www.morphllm.com/llm-cost-optimization), [agentblueprint](https://agentblueprint.substack.com/p/event-driven-vs-polling-architectures))

3. **Cadence to ship: one batched daily digest.** A nightly (or first-open-of-day) job runs the rules engine, and if there's something worth saying, makes **at most one Claude call** to write a 1-line dashboard greeting. That's **~30 LLM calls/user/month**, dominated by a cached system prompt.

4. **Cost at this scale is effectively zero.** With prompt caching (cache read = **10%** of input price) on Haiku/Sonnet, the proactive layer for one user lands around **$0.01–0.05/month**. Even 1,000 users is a few dollars. The dominant cost in this app stays the **food-photo vision calls**, not the proactive coach. ([Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing), [Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching))

5. **Notifications have a hard ceiling of ~3–5/day across ALL apps combined** — and proactive AI must live inside that budget. For a wellness app, **0–1 proactive push/day** is the safe number; surface the rest silently on the dashboard. ([TianPan](https://tianpan.co/blog/2026-05-13-background-agents-notification-budget-attention-economy), [Glean](https://www.glean.com/perspectives/how-to-use-ai-for-proactive-customer-support-notifications))

6. **For an under-eater, every insight must celebrate sufficiency** (you ate enough, you hit protein, you stayed hydrated, you showed up) and **never restriction**. Health-tracking apps are a documented pipeline to disordered eating; "good food / bad food" labels and guilt mechanics are exactly what to avoid. ([The Swaddle](https://www.theswaddle.com/health-tracking-apps-provide-a-worrying-pipeline-to-eating-disorders-better-tech-design-can-fix-that), [PMC focus-group study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12895151/))

---

## 1. What proactive AI looks like in real apps (and the actual cadence)

| App | Proactive mechanism | Cadence | Notes |
|---|---|---|---|
| **Whoop Coach** | **Daily Outlook** (morning: when to push/rest) + **Day in Review** (evening recap of strain/recovery/sleep) | **2× daily, fixed** (AM + PM) + on-demand chat | Explicitly "proactively guides you"; built on OpenAI. The proactivity is *scheduled*, not reactive-to-every-datapoint. ([1](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/), [2](https://www.whoop.com/us/en/thelocker/introducing-whoop-coach-powered-by-openai/)) |
| **Oura Advisor** | Check-ins + trend analysis across days/weeks/months | **User-chosen: daily / 3× week / weekly / off** + on-demand chat anytime | Crucial design choice: **the user picks the cadence**, and can turn proactivity off. ([1](https://support.ouraring.com/hc/en-us/articles/39512345699219-Oura-Advisor), [2](https://ouraring.com/blog/oura-advisor/)) |
| **MyFitnessPal AI** (now owns Cal AI) | Built-in AI nutrition coach for guidance based on goals/history | On-demand + goal-based | Cal AI's whole value prop is **photo→calories** (camera does the work, not chat). MFP acquired it March 2026. ([1](https://thenextweb.com/news/myfitnesspal-acquires-cal-ai-the-viral-calorie-tracking-app-built-by-teens), [2](https://apps.apple.com/us/app/myfitnesspal-calorie-counter/id341232718)) |
| **Noom** | Human + AI goal coach check-ins | **~2× weekly** scheduled | Pairs habit psychology with a low-frequency check-in cadence, not constant pinging. ([1](https://www.nutrola.app/en/blog/noom-vs-myfitnesspal-which-is-better-2026)) |
| **Stoic (journaling)** | Morning prep + evening review prompts; AI insights over entries | **1–2× daily, user-chosen** | Same morning/evening rhythm as Whoop, applied to journaling. ([1](https://www.getstoic.com/), [2](https://apps.apple.com/us/app/stoic-journal-mental-health/id1312926037)) |
| **Bearable** | Correlations/"Impacts" between habits and symptoms | **Weekly reports** + on-rotate comparison graphs | Insights are **computed correlations** (deterministic stats), surfaced on a weekly cadence — not an LLM narrating every day. ([1](https://bearable.app/support/howto/how-to-find-correlations/), [2](https://appsreviewnest.com/app-review/bearable-app-best-symptom-tracker/)) |
| **Gentler Streak** | Weekly / monthly / yearly **Recaps** comparing to prior period | **Weekly + monthly + yearly** | Recap-driven; the "intelligence" is period-over-period comparison. ([1](https://docs.gentler.app/using-insights-and-recaps/understand-your-monthly-recap)) |

**Pattern that emerges across all of them:**
- **Fixed daily rhythm** (morning outlook / evening recap) is the dominant proactive shape for wearables/coaches. ([Whoop](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/))
- **Weekly recap** is the dominant shape for trackers/journals where daily would be noise. ([Bearable](https://bearable.app/support/howto/how-to-find-correlations/), [Gentler Streak](https://docs.gentler.app/using-insights-and-recaps/understand-your-monthly-recap))
- **The user controls cadence and can turn it off.** (Oura's daily/3×/weekly/off is the gold standard.) ([Oura](https://support.ouraring.com/hc/en-us/articles/39512345699219-Oura-Advisor))
- **"Proactive" = scheduled + event-worthy, NOT continuous.** None of these run an LLM on a tight polling loop.

---

## 2. The token-economics playbook (most important section)

### (a) Event-triggered / scheduled — NOT polling every 30 min
"Check every 30 min" is almost always wrong because **most checks find no new data**, each check still costs a model call (especially with reasoning models), and frequent firing trains the user to ignore you. The documented evolution is: teams start with a polling cron, hit cost/latency pain, then move to **event subscriptions / a single scheduled batch**. A silent cron that runs *plain code* costs **zero tokens**; the mistake is invoking the LLM on every poll. ([agentblueprint](https://agentblueprint.substack.com/p/event-driven-vs-polling-architectures), [James Carr — agent hosting patterns](https://james-carr.org/posts/2026-03-01-agent-hosting-patterns/), [ilylabs — minimal LLM cron](https://ilylabs.com/hermes%20agent/ai/local%20llm/hermes-cron-trick/))

**Rule:** the *scheduler* and the *rules engine* are free. The *LLM* is the last, gated step.

### (b) Deterministic pre-filtering — "cheap gate, expensive brain"
Compute insights with ordinary code/SQL first; **only call the LLM when a value crosses a threshold worth talking about.** This is the single biggest lever. Industry framing: a router/gate sits in front of the model, classifies whether work is even needed, and most requests never reach the expensive model — routing ~70% of traffic away from the big model cuts blended cost **40–70%**. For this app, the gate isn't even a model — it's `if` statements over the health profile. ([Morph — 70–85% savings](https://www.morphllm.com/llm-cost-optimization), [Uptech](https://www.uptech.team/blog/how-to-reduce-llm-costs), [Redis LLMOps](https://redis.io/blog/large-language-model-operations-guide/))

> The LLM should never *decide whether* there's an insight. Code decides that. The LLM only *phrases* the insight you already found.

### (c) Batching / once-daily digest vs realtime
Bundle the day's signals into **one** call instead of many small ones. If you can tolerate up to 24h latency (a nightly digest can), Anthropic's **Message Batches API is a flat 50% off** input and output, and **stacks with prompt caching** for up to ~95% input savings. A nightly "write tomorrow's greeting" job is a textbook batch workload. ([Anthropic — Message Batches](https://www.anthropic.com/news/message-batches-api), [Finout](https://www.finout.io/blog/anthropic-api-pricing), [batch docs](https://platform.claude.com/docs/en/build-with-claude/batch-processing))

### (d) Prompt caching (the big one for repeated calls)
Verified from Anthropic's docs: a **cache write costs 1.25×** base input (5-min TTL) or **2×** (1-hr TTL); a **cache read costs 0.1× (10%)** of base input; the cache **refreshes for free each time it's used**; minimum cacheable block is **1,024 tokens** for Sonnet-class models (4,096 for Opus 4.7 / Haiku 4.5). So if your system prompt + Vita persona + the stable parts of the health profile are cached, every subsequent daily call pays **10%** for that chunk instead of 100% — up to ~**90% off** the repeated portion. ([Anthropic prompt caching docs — primary](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing), [MasterPrompting](https://masterprompting.net/blog/prompt-caching-claude-api-cost-reduction))

**How to apply it here:** put the **persona + rules-output schema + user's stable profile** (name, goals, baseline targets, the "never talk restriction" guardrails) in a cached system block; put only **today's numbers** in the uncached user turn. Across a daily cadence the cached block is tiny money. (Caveat: the 5-min default TTL won't survive between once-a-day calls, so caching helps most *within a session / burst*; for truly once-daily calls the absolute token volume is already so low that cost is negligible regardless — see §4.)

### (e) Small/cheap model for routine, big model only when needed
2026 Claude API pricing (per million tokens): **Haiku 4.5 = $1 in / $5 out**, **Sonnet 4.6 = $3 / $15**, **Opus 4.7 = $5 / $25** — Haiku is **3× cheaper than Sonnet** on both. Haiku matches Sonnet on classification/extraction/formatting/short-generation tasks ("write a warm 1-liner from these numbers" is exactly that). Three-tier routing (Haiku routine / Sonnet real reasoning / Opus hardest) cuts cost **60–70%** vs. Opus-everywhere. **Use Haiku for the daily greeting; reserve Sonnet for the interactive Vita chat where nuance matters.** ([BenchLM pricing](https://benchlm.ai/blog/posts/claude-api-pricing), [tech-insider model comparison](https://tech-insider.org/claude-opus-vs-sonnet-vs-haiku-2026/), [Morph — Sonnet vs Haiku](https://www.morphllm.com/sonnet-vs-haiku))

### (f) On-device / no-LLM for the 90% case
Most "insights" don't need an LLM at all. Trend math (7-day weight slope, protein-target hit-rate, hydration streak, "logged 5 days running") is plain arithmetic on data the app already has — like **Bearable's correlations** and **Gentler Streak's recaps**, which are computed, not generated. Render those for free; spend a token only on the *one* thing worth a warm human sentence today. ([Bearable](https://bearable.app/support/howto/how-to-find-correlations/), [Gentler Streak](https://docs.gentler.app/using-insights-and-recaps/understand-your-monthly-recap))

---

## 3. What's been TRIED AND FAILED (learn from these)

**Notification spam → uninstalls (the #1 killer).**
- There is a **hard ceiling of ~3–5 unsolicited notifications/day across ALL apps combined**; phones already push **46–63/day**, so a new proactive agent is fighting for scraps of attention. Treat a per-user daily budget (start at **3**, cap at **5**) as a hard limit, and rank candidates by **expected value (probability the user acts × value of acting)**, not by how many you *can* send. The metric that predicts retention is **"notifications acted on," not "sent."** ([TianPan — notification budget](https://tianpan.co/blog/2026-05-13-background-agents-notification-budget-attention-economy), [Glean](https://www.glean.com/perspectives/how-to-use-ai-for-proactive-customer-support-notifications))
- Frequency directly drives uninstalls: industry stats indicate **~2–5 pushes/week makes ~42–46% of users disable notifications**, and **5+/week makes a majority consider deleting the app**; letting users pick topics/frequency cuts opt-out materially. *(Directional — these figures come largely from marketing-stat aggregators, so treat the exact percentages as ballpark, not gospel; the direction is well-corroborated.)* ([Sci-Tech Today](https://www.sci-tech-today.com/stats/push-notification-statistics/), [Business of Apps](https://www.businessofapps.com/marketplace/push-notifications/research/push-notifications-statistics/))
- Rule of thumb: **"three high-value notifications/day beat thirty medium-value ones."** When an AI emits 50 "insights"/day, users stop reading **all** of them — you've trained them to mute you. ([Glean](https://www.glean.com/perspectives/how-to-use-ai-for-proactive-customer-support-notifications), [Groovyweb — AI UI mistakes](https://www.groovyweb.co/blog/ui-mistakes-ai-apps-2026))

**Generic / obvious insights ("you ate carbs today!").**
- Filler is information that's *obvious AND already known*. A real insight is **"obvious but UNKNOWN"** — it makes the penny drop ("huh, never thought of it that way") by connecting things (e.g., *"your best-energy days this month were the days you topped 1,800 cal — your body likes being fed"*). It must go beyond restating a number the user can already see on the dashboard. ([Basic Arts — definition of insight](https://basicarts.org/a-definition-of-insight-thats-actually-useful/), [Insights in Marketing](https://insightsinmarketing.com/good-vs-great-how-to-uncover-identify-truly-great-insights/))

**Hallucinated health advice (the dangerous failure).**
- LLMs predict plausible text, not truth; the worst hallucinations are the ones that **sound right**. Real harms are documented: AI offering **dieting advice to someone with a restrictive eating disorder**, "therapy" bots giving catastrophic guidance, AI Overviews giving "very dangerous" eating-disorder/psychosis advice. The CMA calls AI health advice "dangerous"; APA called mental-health chatbots "a dangerous trend." **Never let the LLM invent calorie targets, macros, or medical claims** — feed it the app's already-computed numbers and constrain it to *encouragement/framing only*. ([Psychology Today](https://www.psychologytoday.com/us/blog/psych-unseen/202506/ai-hallucinations-in-medicine-and-mental-health), [Futurism — Google AI Overviews](https://futurism.com/artificial-intelligence/google-ai-overviews-dangerous-health-advice), [Duke Med](https://medschool.duke.edu/stories/hidden-risks-asking-ai-health-advice))

**Cost blowups.** Polling an LLM on a timer, sending the full profile uncached on every call, and using a frontier model for trivial phrasing are the three classic ways the bill explodes — all avoidable with §2(a)/(d)/(e).

**Eating-disorder-unsafe design (critical for THIS user).**
- Health-tracking apps are a documented **pipeline to disordered eating**. Avoid **"good food/bad food" labels**, guilt/punishment mechanics, and data overload; support **personal agency** (user controls reminder frequency) and a holistic, non-condescending tone. *(Note: Noom's red/yellow/green food system is exactly the labeling pattern ED researchers warn against — do **not** copy it for an under-eater.)* ([The Swaddle](https://www.theswaddle.com/health-tracking-apps-provide-a-worrying-pipeline-to-eating-disorders-better-tech-design-can-fix-that), [PMC focus groups](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12895151/), [Center for Health Research](https://www.center4research.org/fitness-tracking-apps-eating-disorders/))

**What separates "wow" from filler:** specificity + a connection the user hadn't made + warmth, anchored to **real numbers from their own data**, delivered **rarely enough to feel intentional**.

---

## 4. Concrete recommended architecture for THIS app

### The shape: "cheap gate, expensive brain," once per day, batched, cached

```
                         ┌─────────────────────────────────────────────┐
   Nightly (or on        │  1. SCHEDULER (free)                         │
   first app open        │     iOS BGTaskScheduler nightly, or run on   │
   of the day) ─────────▶│     first foreground after local midnight    │
                         └───────────────────┬─────────────────────────┘
                                             ▼
                         ┌─────────────────────────────────────────────┐
                         │  2. RULES ENGINE (free, on-device Swift)     │
                         │     Reads the centralized health profile and │
                         │     computes candidate insights with plain   │
                         │     code. Scores each by "value" + novelty.  │
                         │     Picks the SINGLE best candidate (or none).│
                         └───────────────────┬─────────────────────────┘
                              none worth it?  │  yes → exactly one candidate
                              ▼               ▼
                    show computed         ┌─────────────────────────────────┐
                    recap only            │  3. ONE CLAUDE CALL (gated)      │
                    (no LLM)              │     Haiku 4.5, cached system     │
                                          │     block (persona + guardrails  │
                                          │     + stable profile). User turn │
                                          │     = the chosen candidate +     │
                                          │     today's numbers. Output: ONE │
                                          │     warm sentence.               │
                                          └───────────────┬─────────────────┘
                                                          ▼
                         ┌─────────────────────────────────────────────┐
                         │  4. SURFACE                                   │
                         │     • Always: warm line on the dashboard      │
                         │     • At most ~1×/day, only if "celebration-  │
                         │       worthy": a gentle push notification     │
                         │     • Interactive Vita chat stays on Sonnet   │
                         └─────────────────────────────────────────────┘
```

### Cadence
- **Proactive write: once per day.** Run the rules engine nightly (BGTaskScheduler) or on first open after local midnight. One candidate max.
- **Dashboard:** always shows *something* (free computed recap + the warm line if one was generated). This is where "the AI oversees everything" feeling actually comes from — a fresh, specific, kind line every morning.
- **Push notification:** **0–1/day**, sent only when the rules engine flags a genuine celebration (hit protein 3 days running; ate enough every day this week; longest logging streak yet). Stay far under the 3–5/day attention ceiling. Make cadence user-configurable (daily / few-times-week / off), copying Oura.
- **Weekly recap (optional, high value):** a Sunday "this week you showed up N days and your weight trend is gently down" — computed, with one optional Claude line. Mirrors Bearable/Gentler Streak.

### Trigger conditions (the rules engine — all plain Swift, no LLM), tuned for an UNDER-eater
Compute these from the profile; fire the LLM only if one is both **true** and **fresh** (didn't fire it in the last N days):

- **Ate enough:** `calories >= floor` (a *minimum*, never a ceiling) → "You fueled yourself well today."
- **Protein win:** `protein >= target` (esp. multi-day streak) → celebrate consistency.
- **Hydration:** `water >= goal`, or a new hydration streak.
- **Consistency / showing up:** logged N days in a row; longest streak yet. (Showing up > perfection.)
- **Gentle trend:** 7-day weight slope, framed softly and only if it supports the user's own goal — **never** as "you should eat less."
- **Movement:** steps/workout milestone.
- **Quiet days:** if nothing crosses a threshold, **say nothing new** (or show an unconditional kind line). Silence is a feature.

**Hard guardrails baked into the cached system prompt:**
- Celebrate **sufficiency, fueling, protein, hydration, consistency** — **never** restriction, deficits, "cutting," or "good/bad" foods.
- The LLM may **only reframe numbers the app computed**; it must **not** invent calorie/macro targets or give medical advice.
- One warm sentence. No nagging, no guilt, no streak-loss shaming.

### Rough per-user monthly token cost
Assume the daily proactive call on **Haiku 4.5** ($1 in / $5 out per MTok):
- Cached system block (persona + guardrails + stable profile) ≈ 1.5k tokens, paid at **10%** on reads ≈ 150 effective tokens/call.
- Fresh daily numbers + chosen candidate ≈ 300 input tokens.
- Output ≈ 60 tokens (one sentence).
- Per call ≈ ~450 effective input + 60 output → roughly **$0.0005–0.0008/day**.
- **× ~30 days ≈ $0.015–0.025 / user / month.** With the **50% Batch API** discount on the nightly job, ~**$0.01/user/month**. Call it **1–3 cents/user/month** for the entire proactive layer.

> Sanity check: even **1,000 users ≈ $10–30/month** for proactive AI. The real spend in this app remains the **food-photo vision calls** (per-image, per-meal), which dwarf the coaching layer. The proactive coach is essentially free; don't over-engineer it.

### How prompt caching + cheap model apply here (concretely)
- **Cheap model:** Haiku 4.5 for the daily greeting (3× cheaper than Sonnet, equal quality for short warm phrasing); keep Sonnet for interactive Vita chat. ([Morph](https://www.morphllm.com/sonnet-vs-haiku))
- **Caching:** mark the persona + guardrails + stable profile as a cached block so repeated calls pay 10% on it. Caching delivers the biggest win **within bursts** (e.g., a back-and-forth Vita chat session, where the 5-min TTL keeps re-hitting); for strictly once-daily calls the volume is already trivial. ([Anthropic](https://platform.claude.com/docs/en/build-with-claude/prompt-caching))
- **Batch:** run the nightly greeting through the Message Batches API for a flat 50% off (24h latency is fine for "tomorrow's dashboard line"). ([Anthropic](https://www.anthropic.com/news/message-batches-api))

### Why this delivers the "AI is overseeing everything" feeling
The *perception* of constant oversight comes from a **fresh, specific, kind, data-grounded line every single morning** — not from actually running a model all day. The rules engine watches everything (free, continuously, on-device); the LLM is just the warm voice that occasionally speaks. That's exactly how Whoop's Daily Outlook / Day in Review feels alive while staying on a fixed, cheap cadence. ([Whoop](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/))

---

## Sources

WHOOP / Oura / coaching apps
- https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/
- https://www.whoop.com/us/en/thelocker/introducing-whoop-coach-powered-by-openai/
- https://support.ouraring.com/hc/en-us/articles/39512345699219-Oura-Advisor
- https://ouraring.com/blog/oura-advisor/
- https://thenextweb.com/news/myfitnesspal-acquires-cal-ai-the-viral-calorie-tracking-app-built-by-teens
- https://apps.apple.com/us/app/myfitnesspal-calorie-counter/id341232718
- https://www.nutrola.app/en/blog/noom-vs-myfitnesspal-which-is-better-2026
- https://www.getstoic.com/
- https://apps.apple.com/us/app/stoic-journal-mental-health/id1312926037
- https://bearable.app/support/howto/how-to-find-correlations/
- https://appsreviewnest.com/app-review/bearable-app-best-symptom-tracker/
- https://docs.gentler.app/using-insights-and-recaps/understand-your-monthly-recap

Token economics / architecture
- https://platform.claude.com/docs/en/build-with-claude/prompt-caching  (primary — caching mechanics)
- https://platform.claude.com/docs/en/about-claude/pricing
- https://www.anthropic.com/news/message-batches-api
- https://platform.claude.com/docs/en/build-with-claude/batch-processing
- https://www.finout.io/blog/anthropic-api-pricing
- https://www.morphllm.com/llm-cost-optimization
- https://www.morphllm.com/sonnet-vs-haiku
- https://www.uptech.team/blog/how-to-reduce-llm-costs
- https://redis.io/blog/large-language-model-operations-guide/
- https://benchlm.ai/blog/posts/claude-api-pricing
- https://tech-insider.org/claude-opus-vs-sonnet-vs-haiku-2026/
- https://agentblueprint.substack.com/p/event-driven-vs-polling-architectures
- https://james-carr.org/posts/2026-03-01-agent-hosting-patterns/
- https://ilylabs.com/hermes%20agent/ai/local%20llm/hermes-cron-trick/

What fails / notifications / insight quality / safety
- https://tianpan.co/blog/2026-05-13-background-agents-notification-budget-attention-economy
- https://www.glean.com/perspectives/how-to-use-ai-for-proactive-customer-support-notifications
- https://www.groovyweb.co/blog/ui-mistakes-ai-apps-2026
- https://www.sci-tech-today.com/stats/push-notification-statistics/
- https://www.businessofapps.com/marketplace/push-notifications/research/push-notifications-statistics/
- https://basicarts.org/a-definition-of-insight-thats-actually-useful/
- https://insightsinmarketing.com/good-vs-great-how-to-uncover-identify-truly-great-insights/
- https://www.psychologytoday.com/us/blog/psych-unseen/202506/ai-hallucinations-in-medicine-and-mental-health
- https://futurism.com/artificial-intelligence/google-ai-overviews-dangerous-health-advice
- https://medschool.duke.edu/stories/hidden-risks-asking-ai-health-advice

Eating-disorder-safe design
- https://www.theswaddle.com/health-tracking-apps-provide-a-worrying-pipeline-to-eating-disorders-better-tech-design-can-fix-that
- https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12895151/
- https://www.center4research.org/fitness-tracking-apps-eating-disorders/

### Confidence / caveats
- **High confidence (primary source / 2+ independent):** prompt-caching mechanics (Anthropic docs); Claude 2026 pricing; Batch API 50%; Whoop AM/PM cadence; Oura user-set cadence; notification budget ~3–5/day; cheap-gate routing; ED-safe design principles.
- **Directional only:** the specific push-notification uninstall percentages (marketing-stat aggregators; direction is corroborated, exact numbers are not authoritative).
- **Inference (not a cited fact):** the dollar figures in §4 are my arithmetic from published per-token prices applied to this app's assumed token volumes — order-of-magnitude, not a quote.
