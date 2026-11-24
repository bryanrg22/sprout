# Adaptive Plan — spec

The leap from tracker → coach. A per-user **Plan** the AI authors from her real data + goals,
that lives on **Progress**, that **Vita** can read and edit, and that **adapts over time**.

Direction-agnostic: works for loss and gain — same machinery, different targets.

## Why (the gap)
Adaptive coaching works (AI-adaptive plans → 40–60% more adherence) and the "agent keeps a living
plan file" pattern is proven (MemGPT/Letta memory blocks, `task_plan.md`). But no fitness app exposes
a **persistent, reasoned, conversable plan** that a Progress view and a chat coach both share, grounded
in the user's logged data. That's the opening. Our `CoachMemory` already proves the per-user-text-block
pattern; this is its richer sibling.

## The Plan doc
One record per user (`CoachPlan`), CloudKit-synced. Authored as **structured output** (reliable for the
UI) whose prose sections are markdown (the "doc" feel; rendered with `MarkdownMessage`).

Fields:
- `headline` — one line ("On track for 135 by Sept").
- `assessment` — the current read on whether it's working (markdown prose).
- `strategy` — the approach / the *why* behind the numbers (markdown prose).
- `calorieMin` / `calorieMax` — the **target range** (not a point). Floor (no under-eating) + soft ceiling.
- `proteinTarget` — g/day.
- `insights` — `[PlanInsight]` (title, body, tone: win/watch/nudge). The "tickets" Progress shows.
- `changelog` — `[PlanChange]` (date, what changed + why). Adaptation is visible.
- `goalSummary` / `timeframe` — captured intent.
- `dataPointsAtBuild` — # logged days that informed it → drives confidence ("early read" when low).
- `createdAt` / `updatedAt`.

Arrays persisted as JSON strings (SwiftData + CloudKit-safe; decoded in the view).

## Three call types touch the doc
1. **Build (once, heavy — Opus 4.8).** Prompt = profile + goal + timeframe + intake free-text + a summary
   of every logged day (reuse `CoachContext` data helpers). Reason deeply → emit the structured plan.
   If the data trips a **safety flag** (intake very low, rate very fast), do a targeted web check and fold
   it in. Uses `AnthropicClient.structured()` (forced tool use) with the plan schema.
2. **Review (light, cadence/button — Opus or Sonnet).** Prompt = current plan + data since `updatedAt` →
   "on target? adjust the range, refresh insights, add a changelog line." Re-emit the structured plan.
   This *is* the "are we on target" review.
3. **Vita edits live (on command).** Vita gets two tools on top of her existing belt:
   - `read_plan` — not strictly needed (the plan is auto-injected into her context, like memory), but
     available so she can quote it precisely.
   - `update_plan` — fold in a context change ("started creatine", "less time now") + log it; can trigger
     a light re-review. Vita literally opens + edits the file.

## Vita integration
`CoachContext.system` injects a compact plan summary (headline + range + top insights + "she can ask me to
adjust it") right after the memory block — so every Vita turn already knows the plan. Tapping a Progress
insight deep-links into Vita with that topic (reuse the existing `AskVita` bus).

## Intake (hybrid — not a rigid Q&A)
- Small **structured confirm**: pre-filled goal weight / current / timeframe (editable).
- **Open talk-boxes**: "Tell us about your day-to-day" + "Your exercise & schedule" — free text she dumps.
- Submit → Build pass runs behind a real "thinking it through" state → lands on the new Progress.
- The model chases gaps later *through Vita* ("I don't see gym logs — do you train?").

## Progress surface
Becomes the plan, not charts-that-restate-data:
- headline + assessment up top,
- **insight cards** (the tickets; tap → Vita),
- the **range** target with "why this number / changed N days ago",
- weight-trend chart kept, in service of the story,
- a gentle **"refresh your plan"** nudge when the timeframe milestone nears or the trend drifts.

## Targets as a range + goal-aware framing
The plan outputs a **range**; both users aim to land in it (floor + soft ceiling), never undershoot.
Loss tone = "fuel up to your goal" (a floor to meet), not a countdown to zero (the ED-framing risk).

## Phases
- **P1 (this pass):** `CoachPlan` model · `PlanService` (build input + schema + generate + decode) ·
  plan injected into Vita's context · `update_plan` tool · a Progress "Plan" card that renders it +
  a "Build my plan" intake sheet. Tested + live-verified end to end.
- **P2:** insight cards as tappable tickets → deep-link to Vita · richer insight types (under-eating catch,
  protein-short, behavior→outcome, fueling-great).
- **P3:** the Review pass on a cadence + button · changelog UI · the safety web-check.
- **P4:** full Progress redesign polish · goal-aware calorie framing on the dashboard hero · the
  What's-New → "let's personalize you" entry moment.

## Testing
- Pure/unit: `CoachPlan` encode/decode of insight + changelog JSON; `PlanService` input-building from data;
  the plan schema shape; decoding a model response into `CoachPlan`; `update_plan` tool parse/apply;
  range/confidence helpers.
- Integration (live, DEBUG key): run a real Build pass in the sim, confirm a coherent plan renders.
- UI: screenshot the intake + the Progress plan card.

## Models / cost
Build = Opus 4.8 (rare, high-value — worth the tokens). Review = lighter. Vita edits = her normal model.
