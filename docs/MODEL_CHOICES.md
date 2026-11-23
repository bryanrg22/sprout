# Model selection — decision record

> **Superseded as a method on 2026-11-22.** This document argued each default from price
> and release notes; none was measured against a test set. Defaults are now chosen by
> running the candidates on labelled cases (`Evals/`, results in `docs/EVAL_REPORT.md`).
> It is kept as the record of the reasoning at the time. Several facts in it are out of
> date: `gpt-4.1-mini` is deprecated and shuts down 2027-01-14, and newer, cheaper models
> exist on both providers (EVAL_REPORT 6).

*Last revisited: **2026-07-12**. Every default below is a deliberate choice with a rejected alternative. Users can override any model string in Settings without a rebuild; these are the defaults a new user gets.*

## The framework

Three questions decide every tier, in order:

1. **What does the task actually need?** Rewording a precomputed fact needs zero reasoning. A tool call needs schema reliability. A once-a-month plan build deserves the best available thinking.
2. **What's the cheapest model that clears that bar?** Frontier benchmark deltas (agentic evals, competition math) rarely transfer to consumer-app tasks operating on 2k tokens of curated context.
3. **Is it actually available to a BYOK user?** A preview-gated model can't be a default when every user brings their own key.

## Current defaults

| Tier | Anthropic | OpenAI | Runs |
|---|---|---|---|
| Cheap | `claude-haiku-4-5` ($1/$5) | `gpt-4.1-mini` | daily brief polish, insights, reflections, onboarding note, memory folding — many×/day |
| Strong | `claude-sonnet-5` ($3/$15; intro $2/$10 → Aug 31) | `gpt-5.6-terra` ($2.50/$15) | Vita chat + tools, meal-photo vision, checklist, quick prompts — a few×/day |
| Heavy | `claude-opus-4-8` ($5/$25) | `gpt-5.6-sol` ($5/$30) | plan build/review + web research — a few×/**ever** |

## The defenses (per decision)

### Cheap tier: `gpt-4.1-mini` — deliberately NOT a reasoning mini
`gpt-5.4-mini` ($0.75/$4.50) exists and is newer. We keep a **non-reasoning** mini anyway: this tier rewords facts the app already computed, inside tight 80–420-token output budgets. On reasoning models, hidden thinking tokens (a) bill as output and (b) count against `max_completion_tokens` — a reasoning mini can spend the entire 80-token budget thinking about a rewording task, returning nothing, at higher latency. Zero quality upside for a task with no reasoning content. *Revisit if the 4.1 family is deprecated → `gpt-5.4-mini` with `reasoning_effort: "low"` (or `none` if offered), or `gpt-5.6-luna` at GA.*

### Strong tier: `claude-sonnet-5` (from Sonnet 4.6) and `gpt-5.6-terra` (from gpt-4.1, via gpt-5.4 for one day)
Rule: **upgrade the workhorse the moment a newer generation hits price parity.** Sonnet 5 landed at Sonnet 4.6's list price ($3/$15) with intro pricing *below* it — the upgrade was free. gpt-4.1 → gpt-5.4 costs +$0.50/1M input but moves a full frontier generation (better tool-call reliability, 1M context), keeping both providers in the same $2.50–3 price class.

On gpt-5.x we pin `reasoning_effort: "low"` (and `"none"` on 5.6 tool turns — see the 07-12 note): a consumer chat loop ("log 2 waters") needs snappy, reliable tool calls, not deliberation — and uncapped effort would silently eat our output budgets. Depth is a *feature budget*, not a model property.

### Heavy tier: `claude-opus-4-8` and `gpt-5.6-sol` — and why NOT the frontier-plus models
The plan build runs a handful of times per user, ever — the one place expensive tokens are rational. But we still rejected the tier above:

- **Claude Fable 5** ($10/$50): 2× Opus pricing, always-on thinking, and refusal-fallback operational complexity — for a benchmark edge (frontier agentic evals) that doesn't transfer to "author a structured coaching plan from a small, curated context."
- **Claude Fable 5's OpenAI analog would be Sol Ultra-style spend**: same logic applies — the marginal capability doesn't transfer to this workload's shape.

### 2026-07-12 correction & adoption: GPT-5.6 went GA — verified on a real key, adopted same day
The June announcement described a rep-gated preview; the July 9 release opened it to everyone. **The written availability claim was wrong for ~a day and was corrected by empirical test, not by another article**: key verification and a full chat + tool-call loop ran against `gpt-5.6-terra` on a personal BYOK key in the simulator. Terra (same $2.50/$15 as gpt-5.4, a generation newer) became the strong tier; Sol (same $5/$30 as gpt-5.5) became the heavy tier, per this doc's own pre-registered revisit trigger.

**Constraint discovered live, not in any docs we'd read:** on Chat Completions, the 5.6 family rejects function tools combined with a reasoning effort (400: *"use /v1/responses or set reasoning_effort to 'none'"*). Tool-carrying requests now pin `reasoning_effort: "none"` on 5.6 — which matches the doctrine anyway (chat tool turns shouldn't deliberate). Regression-tested.

**~~Known open item~~ → SHIPPED same day — the Responses API port, with the receipt:** gpt-5.6 models now run on `/v1/responses` with an explicit `prompt_cache_breakpoint` after the stable system prefix (`prompt_cache_options: {mode: "explicit", ttl: "30m"}`), because [explicit breakpoints are Responses-only](https://learn.microsoft.com/en-in/answers/questions/5942997/gpt-5-6-implicit-prompt-caching-and-explicit-promp) and Chat Completions implicit caching measured `cached 0` across every live test. Result, measured on a real key in the on-device logs: `in 6747 … cached 5512` — **82% of the coach prompt served from cache at the 90% discount, cutting a coach turn from ~1.69¢ to ~0.45¢ (−73%)**. Reasoning effort and tools also legally coexist on this surface (low effort, vs the forced `none` on Chat Completions). Older gpt-4.x models stay on Chat Completions. The whole translation layer is fixture-tested including echo round-trips.

The plan's quality lever isn't model IQ — it's **context engineering** (a curated data summary + live web-search grounding) feeding an already-strong model.

### Research model: `gpt-5.6-sol` on Responses / Anthropic `web_search` server tool
Web search requires specific surfaces: OpenAI's `web_search` tool runs on gpt-5.x Responses models, Anthropic's on the Messages API. Research is best-effort by contract — if the model or tool is unavailable to a user's key, the plan builds un-grounded rather than failing.

## Standing revisit triggers

| Trigger | Action |
|---|---|
| ~~GPT-5.6 family GA~~ ✅ done 2026-07-12 | Terra → strong ✅, Sol → heavy ✅, Responses-API port ✅ (cached 5512/6747 measured). Remaining: Luna evaluation for the cheap tier. |
| Sonnet 5 intro pricing ends (2026-08-31) | No action — $3/$15 list was already the accepted price. |
| gpt-4.1 family deprecation notice | Move cheap tier per the note above. |
| Any provider price cut ≥25% on a higher tier | Re-run this table. |

## How this stays honest

Every API call logs `in / out / cacheRead / cacheWrite` tokens to on-device diagnostics — so a model change's real cost is measurable on a phone, not estimated on a whiteboard. (This observability caught the OpenAI cache-shard miss that led to `prompt_cache_key`; see README → Cost engineering.)
