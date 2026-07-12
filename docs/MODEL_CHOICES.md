# Model selection — decision record

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
| Strong | `claude-sonnet-5` ($3/$15; intro $2/$10 → Aug 31) | `gpt-5.4` ($2.50/$15) | Vita chat + tools, meal-photo vision, checklist, quick prompts — a few×/day |
| Heavy | `claude-opus-4-8` ($5/$25) | `gpt-5.5` ($5/$30) | plan build/review + web research — a few×/**ever** |

## The defenses (per decision)

### Cheap tier: `gpt-4.1-mini` — deliberately NOT a reasoning mini
`gpt-5.4-mini` ($0.75/$4.50) exists and is newer. We keep a **non-reasoning** mini anyway: this tier rewords facts the app already computed, inside tight 80–420-token output budgets. On reasoning models, hidden thinking tokens (a) bill as output and (b) count against `max_completion_tokens` — a reasoning mini can spend the entire 80-token budget thinking about a rewording task, returning nothing, at higher latency. Zero quality upside for a task with no reasoning content. *Revisit if the 4.1 family is deprecated → `gpt-5.4-mini` with `reasoning_effort: "low"` (or `none` if offered), or `gpt-5.6-luna` at GA.*

### Strong tier: `claude-sonnet-5` (from Sonnet 4.6) and `gpt-5.4` (from gpt-4.1)
Rule: **upgrade the workhorse the moment a newer generation hits price parity.** Sonnet 5 landed at Sonnet 4.6's list price ($3/$15) with intro pricing *below* it — the upgrade was free. gpt-4.1 → gpt-5.4 costs +$0.50/1M input but moves a full frontier generation (better tool-call reliability, 1M context), keeping both providers in the same $2.50–3 price class.

On gpt-5.4 we pin `reasoning_effort: "low"`: a consumer chat loop ("log 2 waters") needs snappy, reliable tool calls, not deliberation — and uncapped effort would silently eat our output budgets. Depth is a *feature budget*, not a model property.

### Heavy tier: `claude-opus-4-8` and `gpt-5.5` — and why NOT the frontier-plus models
The plan build runs a handful of times per user, ever — the one place expensive tokens are rational. But we still rejected the tier above:

- **Claude Fable 5** ($10/$50): 2× Opus pricing, always-on thinking, and refusal-fallback operational complexity — for a benchmark edge (frontier agentic evals) that doesn't transfer to "author a structured coaching plan from a small, curated context."
- **GPT-5.6 Sol** ($5/$30): [preview-gated as of July 2026](https://www.eesel.ai/blog/gpt-5-6-pricing) — access requires an OpenAI account representative. A BYOK default must be callable by any user's key. Its Agents-Last-Exam record ([53.6, per Simon Willison's write-up](https://simonwillison.net/2026/Jul/9/gpt-5-6/)) is impressive and irrelevant to this workload.

The plan's quality lever isn't model IQ — it's **context engineering** (a curated data summary + live web-search grounding) feeding an already-strong model.

### Research model: `gpt-5.5` on Responses / Anthropic `web_search` server tool
Web search requires specific surfaces: OpenAI's `web_search` tool runs on gpt-5.x Responses models, Anthropic's on the Messages API. Research is best-effort by contract — if the model or tool is unavailable to a user's key, the plan builds un-grounded rather than failing.

## Standing revisit triggers

| Trigger | Action |
|---|---|
| GPT-5.6 family GA | Terra → strong tier (same $2.50/$15, newer), Luna → evaluate for cheap tier, Sol → evaluate for heavy. Also adopt its explicit cache breakpoints + 30-min cache life. |
| Sonnet 5 intro pricing ends (2026-08-31) | No action — $3/$15 list was already the accepted price. |
| gpt-4.1 family deprecation notice | Move cheap tier per the note above. |
| Any provider price cut ≥25% on a higher tier | Re-run this table. |

## How this stays honest

Every API call logs `in / out / cacheRead / cacheWrite` tokens to on-device diagnostics — so a model change's real cost is measurable on a phone, not estimated on a whiteboard. (This observability caught the OpenAI cache-shard miss that led to `prompt_cache_key`; see README → Cost engineering.)
