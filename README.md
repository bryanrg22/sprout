# 🌱 Sprout – *An AI Health Coach That Actually Knows You*

<div align="center">

[![Swift](https://img.shields.io/badge/Swift-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-0071e3?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![SwiftData](https://img.shields.io/badge/SwiftData-8e44ad?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/documentation/swiftdata)
[![Claude](https://img.shields.io/badge/Claude-d97757?style=flat-square&logo=anthropic&logoColor=white)](https://www.anthropic.com)
[![OpenAI](https://img.shields.io/badge/GPT--5.6-412991?style=flat-square&logo=openai&logoColor=white)](https://openai.com)
[![Tests](https://img.shields.io/badge/tests-443%20passing-2f7d4f?style=flat-square)]()
[![BYOK](https://img.shields.io/badge/keys-bring%20your%20own-555?style=flat-square)]()

</div>

---

> **A warm, AI-coached health companion for iOS — and a working case study in doing consumer AI *right*: the correct model for each job, aggressive cost engineering, real tool use with safety rails, and graceful degradation everywhere.**

Built native in SwiftUI + SwiftData as my own daily-driver health app, running every day on my real Fitbit data. Not a demo: every AI surface below is live, unit-tested, and verified end-to-end against both the Anthropic and OpenAI production APIs.

---

## System Architecture

<img src="docs/architecture.svg" alt="System architecture diagram" width="900"/>

---

## Table of Contents

* [What is Sprout?](#what-is-sprout)
* [The AI System](#the-ai-system)
  * [One abstraction, two providers](#one-abstraction-two-providers)
  * [Right-sized models (the tiering)](#right-sized-models-the-tiering)
  * [Cost engineering](#cost-engineering-the-part-that-makes-it-shippable)
  * [Tool use with safety rails](#tool-use-with-safety-rails)
  * [Data → context → coaching](#reading-the-body-data--context--coaching)
* [The Data Platform](#the-data-platform)
* [Verification Culture](#verification-culture)
* [How This Compares to the Industry](#how-this-compares-to-the-industry)
* [Project Structure](#project-structure)
* [Getting Started (Dev)](#getting-started-dev)

---

## What is Sprout?

| Today | AI Coach with tool use | Trend + AI plan | AI-personalized checklist |
|---|---|---|---|
| ![Today dashboard](docs/screenshots/today-dashboard.png) | ![Vita executing a tool call](docs/screenshots/vita-tool-call.png) | ![Progress trend](docs/screenshots/progress-trend.png) | ![AI checklist](docs/screenshots/ai-checklist.png) |

> The second screenshot is the interesting one: *"Please log 2 bottles of water for me"* → the model emits a **function call**, the app validates + applies it to the local store (with undo), returns a tool result, and the model confirms — a full agentic round-trip inside a consumer chat UI. Works identically on Claude and GPT.

**Sprout** is a weight-loss / healthy-habits companion built around **Vita**, an AI coach that reads the user's real data (food, water, weight trend, Fitbit sleep + recovery, workouts, even timezone changes) and acts on it through validated tools. It celebrates comebacks instead of shaming streaks, writes one warm proactive note per day, and degrades gracefully at every layer — no API key, no tracker, no iCloud? Still a complete app.

---

## The AI System

**Design stance:** an LLM is a component, not a product. Every feature below was designed backwards from *"what's the cheapest thing that does this job honestly?"* — templates first, small models second, big models only where they earn it, and a working fallback when there's no key or no network.

### One abstraction, two providers

The user picks Anthropic or OpenAI in Settings (bring-your-own-key; keys live only in the Keychain). Every AI feature — chat with tools, vision, structured outputs, web-search research — runs on either vendor:

```mermaid
flowchart LR
    subgraph Features
        A[Vita chat + tools]
        B[Meal-photo vision]
        C[Adaptive plan + web research]
        D[Daily brief / insights / reflections]
        E[Checklist + quick prompts]
        F[Memory consolidation]
    end
    Features --> G{{"AIClient factory<br/>(reads provider from Settings)"}}
    G --> H[AnthropicClient<br/>Messages API]
    G --> I[OpenAIClient<br/>Chat Completions + Responses]
    H -. "native wire format" .-> J[(Anthropic-shaped<br/>wire vocabulary)]
    I -. "translates at the boundary" .-> J
```

The trick that keeps this cheap to maintain: the app speaks **one internal wire vocabulary** (Anthropic's content-block format — messages, tool schemas, tool results). `OpenAIClient` translates at its boundary: tool schemas → function declarations, `tool_use` echoes → `tool_calls` with JSON-string arguments, `tool_result` → `role:"tool"` messages, base64 image blocks → data-URL parts. Call sites never branch on the vendor. The translation layer is pinned by fixture tests, including a full round-trip test (response → parse → echo → identical request).

### Right-sized models (the tiering)

<img src="docs/technique_tiering.svg" alt="Model tiering diagram" width="900"/>

| Tier | Anthropic | OpenAI | What runs on it | Why |
|---|---|---|---|---|
| **Cheap/fast** | Haiku 4.5 | gpt-4.1-mini *(deliberately non-reasoning)* | Daily brief polish, insight phrasing, weekly reflection, onboarding note, memory folding | Rewording precomputed facts needs zero reasoning — a reasoning mini would burn hidden thinking tokens inside 80–420-token budgets |
| **Strong** | Sonnet 5 | gpt-5.6-terra *(reasoning pinned low; none on tool turns — a live-discovered 5.6 constraint)* | Vita chat + tools, meal-photo vision, checklist, quick prompts | The $2.50–3 workhorse class; upgraded the moment newer generations hit price parity |
| **Heavy (rare)** | Opus 4.8 | gpt-5.6-sol | The one-time adaptive plan build/review + live web-search research | Runs a handful of times *ever* per user — worth the tokens. Fable 5 evaluated and rejected (2× price, no transfer to this workload) |

The expensive model is reserved for the feature invoked a few times per month; the model invoked many times per day is the cheap one. Users can override any model string in Settings without a rebuild. **Every choice here has a written defense with rejected alternatives and standing revisit triggers: [docs/MODEL_CHOICES.md](docs/MODEL_CHOICES.md).**

### Cost engineering (the part that makes it shippable)

<img src="docs/technique_cost.svg" alt="Cost engineering diagram" width="900"/>

| Technique | Where | Effect |
|---|---|---|
| **Template-first generation** | Daily brief, insights, reflections, onboarding | The deterministic template *is* the product; the LLM may only re-warm the same fact. No key / no network → template ships. AI polish costs ≤1 cheap-model call per surface per day. |
| **Response caching (per-day)** | Daily brief | One generation per calendar day, cached in `UserDefaults` — reopening the app 20× costs zero. |
| **Prompt caching, stable/volatile split** | Coach chat (~6.5k-token prompt) | The system prompt is split into a byte-stable prefix (persona, rules, tool guidance) and a volatile tail (today's data). On Anthropic the prefix carries an explicit `cache_control` breakpoint → cached reads bill at ~10% of input price. |
| **Explicit cache breakpoints (Responses API)** | Coach chat on OpenAI | Our usage logs caught `cached 0` on every 6.5k-token coach turn — Chat Completions implicit caching simply wasn't hitting, even with a [`prompt_cache_key`](https://developers.openai.com/api/docs/guides/prompt-caching) routing hint. Fix: gpt-5.6 models route to the **Responses API** with an explicit `prompt_cache_breakpoint` after the stable prefix. Measured result on a real key: **`cached 5512` of 6,747 input tokens (82%) at the 90% discount — a coach turn dropped from ~1.7¢ to ~0.45¢**. |
| **Sliding window + memory folding** | Coach chat | Only recent turns are sent verbatim; older turns are folded into compact long-term notes by the *cheap* model, off the user's turn, with a lost-update guard. Context stays bounded forever. |
| **Bounded outputs** | Every structured call | Tight `max_tokens` per feature (300–2,200) — a schema-forced call can't ramble. |
| **Priority ladder, one message** | Daily brief | Google-Health-style proactive note picks ONE topic per day (comeback > milestone > cross-signal > quiet-day > check-in) instead of spamming generations. |
| **Token observability** | Every call | `in / out / cacheRead / cacheWrite` logged per request to on-device diagnostics — "what does a day of AI cost" is answerable from the phone. This observability is literally how the cache-shard bug above was found. |

### Tool use with safety rails

<img src="docs/agent_loop.svg" alt="Tool loop with safety rails diagram" width="900"/>

Vita has a real toolbelt (log food/water/weight/workouts, edit entries, change goals, remember facts, adjust the plan). The loop is engineered around trust:

```mermaid
sequenceDiagram
    participant U as User
    participant App as CoachView
    participant LLM as Claude / GPT
    U->>App: "log 2 bottles of water"
    App->>LLM: system (cached prefix + live data) + history + tool schemas
    LLM-->>App: tool_use: log_water {bottles: 2}
    App->>App: validate against profile (bounds, ambiguity)
    alt destructive / goal-changing
        App->>U: one-tap confirm card (Yes / Not now)
    else quick reversible log
        App->>App: apply immediately + Undo toast
    end
    App->>LLM: tool_result ("Applied…" or decline)
    LLM-->>U: warm follow-up grounded in what actually happened
```

- **Validation before execution** — out-of-range or ambiguous requests bounce back to the model as in-band tool errors; the user never sees a confirm for something unsafe.
- **Confirm-or-undo, never silent** — destructive changes require a tap; quick logs apply instantly with an undo toast. Declines are told to the model so it responds gracefully.
- **Depth-capped chaining** with `tool_choice: none` on the final turn (schemas stay in the request — required when history contains tool blocks — but the model must finalize in prose).
- **Truncation guard** — a turn cut off mid-tool-call is never acted on.

### Reading the body: data → context → coaching

The AI is only as good as what it can see. Vita's context window gets a compact, pre-digested snapshot — not raw streams:

- **Sparse daily aggregates by design**: one row per night of sleep (with deep/REM/light stages), one per day of resting HR + HRV, one per detected workout. Enough signal for coaching; tiny prompt/storage/privacy footprint.
- **Recovery signal** (Whoop's idea at honest resolution): today's RHR/HRV vs the user's own 14-day baseline → rested / steady / tender. Requires ≥5 baseline days; refuses to guess. A copy-contract unit test bans clinical/alarming language.
- **Gap awareness**: `daysSinceLastLog` reframes a comeback ("she was away, don't read missing logs as not eating") — the streak logic, charts, insights, and Vita's tone all shift together.

---

## The Data Platform

```mermaid
flowchart TD
    FB[Fitbit Air] --> GH["Google Health API v4<br/>OAuth 2.0 PKCE · no bridge app"]
    GH -->|"sleep + stages · daily RHR/HRV · workouts"| P["Wire parsers<br/>(int64-as-string, civil-time filters,<br/>google-duration — fixture-tested)"]
    AH[Apple Health<br/>optional second pipe] --> HK[HealthKit importers]
    P --> M["Pure merge functions<br/>idempotent upserts · cross-source dedup"]
    HK --> M
    M --> SD[(SwiftData store)]
    SD --> V[Vita context]
    SD --> T[Tracker card + charts]
    SD --> W[Home-screen widgets]
    SD <--> CK1[CloudKit private DB<br/>personal data mirror]
    SD --> CK2[CloudKit public DB<br/>buddy sync]
```

| Fitbit, connected direct | Real sleep + recovery, same night |
|---|---|
| ![Fitbit via Google Health, connected](docs/screenshots/fitbit-connect.png) | ![Sleep & recovery with real Fitbit data](docs/screenshots/sleep-recovery.png) |

**Direct Google Health integration** — OAuth 2.0 with PKCE in `ASWebAuthenticationSession`, tokens Keychain-only, single-flight refresh, `invalid_grant` auto-disconnect, and a zombie-token guard (a disconnect during an in-flight refresh can't resurrect the connection). The wire layer was built from Google's own discovery document, and its quirks — int64s as JSON strings, `"1234s"` durations, civil-time filter grammar — are pinned by tests so a parser regression is caught in CI, not on a phone.

**Idempotency as a contract** — every ingest path funnels through pure, unit-tested merge functions: re-running any sync N times produces identical rows (proven by a two-pass integration test against a real store). Workouts arriving through *both* pipes are deduped symmetrically by time-window, whichever pipe delivered first.

**Buddy sync** — two paired users share daily snapshots through CloudKit's public DB with deterministic record IDs and silent-push refresh; a privacy toggle controls whether a buddy sees everything or only the activity face-off. Sync health is user-visible (publish status, staleness warnings, one-tap diagnostic).

**Design decision: serverless by design.** There is no backend anywhere in this app — deliberately. AI is bring-your-own-key straight to the provider; buddy sync rides CloudKit's public database (deterministic record IDs, silent-push refresh, dev→prod schema discipline) instead of a custom service. The trade-offs are understood and documented: at consumer scale you'd want a dedicated service (server-side validation, E2E encryption, abuse controls) — for a two-user product, a backend would add an operational surface, a privacy liability, and a monthly bill while delivering nothing the platform doesn't already provide. Same doctrine as the AI layer: use the most boring infrastructure that honestly does the job.

**Every feature degrades gracefully** — no key → templates and manual logging still work; no network → the coach apologizes kindly; no tracker → the app is still a complete manual logger. AI is seasoning, not a dependency.

---

## Verification Culture

- **423 unit tests** — wire-format fixtures for both providers, the RFC 7636 PKCE test vector, timezone-crossing sleep bucketing, idempotent-merge integration tests against real SwiftData stores, and copy-contract tests (the recovery signal's own test once caught the word "medical" in coach copy and failed the build).
- **Live end-to-end, both vendors** — chat, tool calls, and data persistence verified against production APIs; results cross-checked three ways: UI screenshots, direct SQLite inspection of the store (zero duplicate rows after concurrent syncs), and the on-device diagnostics log.
- **Field diagnostics** — tap the version number 7× for a shareable log of every AI call (with token counts), sync outcome, and lifecycle event. Several real bugs in this repo were found by reading it.
- **Adversarial review loop** — independent review passes over every major feature; findings get fixed *with* regression tests (see the git history: the launch-race, cache-shard, and provider-parity fixes all landed with tests pinning them).

## How This Compares to the Industry

| Pattern | Who else does it | Here |
|---|---|---|
| LLM coach over wearable aggregates | [Whoop Coach (GPT-4, OpenAI partnership)](https://www.whoop.com/us/en/thelocker/whoop-unveils-the-new-whoop-coach-powered-by-openai/) | Vita: same architecture, plus *write* access via validated tools — Whoop's coach only reads |
| One proactive daily AI note | Google Health app's daily brief | Priority-ladder brief, template-first, ≤1 cheap call/day |
| AI memory of the user | [Whoop's 2025 roadmap](https://www.whoop.com/us/en/thelocker/inside-look-whats-next-for-whoop-in-2025/) | Shipped: consolidated long-term notes + explicit `remember_about_user` tool |
| Model routing by task complexity | [Standard cost-optimization practice](https://www.truefoundry.com/blog/llm-cost-optimization) (cache → route → compress) | Three explicit tiers per provider; heavy tier gated to a rare feature |
| Prompt caching | Anthropic/OpenAI native | Both: explicit breakpoints on Anthropic, shard-routing keys on OpenAI — with on-device logs proving hit rates |

## Project Structure

```
Victoria/
├── App/                  # Entry, root refresh orchestration (single-flight, ordered pipes)
├── Features/
│   ├── Coach/            # Vita: chat UI, tool loop, context builder, toolbelt (12+ tools)
│   ├── Dashboard/        # Today: brief, tracker card, checklist, companion
│   ├── Buddy/            # CloudKit public-DB pairing + daily snapshot sync
│   ├── Plan/             # Adaptive plan: intake → heavy build w/ web research → review
│   ├── Weight/ Food/ Workout/ …
│   └── Settings/         # AI provider picker, Fitbit connect, Apple Health, goals
├── Services/
│   ├── AI/               # the provider layer: AIConfig, LLMClient, Anthropic + OpenAI clients
│   ├── GoogleHealth/     # OAuth PKCE + REST client + sync orchestration
│   ├── DailyBriefService / DailyInsightEngine / RecoverySignal / CoachMemoryService
│   └── HealthKit* / StreakCalculator / Diagnostics …
├── VictoriaTests/        # 443 tests
└── docs/                 # screenshots, deep-dives, GOOGLE_HEALTH_SETUP.md
```

## Getting Started (Dev)

Anyone can clone and run this — there's no server to stand up and no secrets in the repo (AI is bring-your-own-key).

1. `brew install xcodegen`
2. In `project.yml`, make three identifiers yours, then `xcodegen generate`:
   - `DEVELOPMENT_TEAM` → your Apple Team ID
   - `bundleIdPrefix` / `PRODUCT_BUNDLE_IDENTIFIER` → your reverse-DNS prefix
   - the iCloud container (`iCloud.com.bryanram.victoria`) and app group (`group.com.bryanram.victoria`) → your own (also referenced in `Victoria/Features/Buddy/Services/CloudKitSyncService.swift` and the widget) — or skip iCloud entirely; the app runs fully local without it
3. Open `Victoria.xcodeproj`, let automatic signing register the App IDs, Run.
4. AI: Settings → AI Provider → pick a vendor, paste your own API key (Keychain-only).
5. Fitbit (optional): follow [GOOGLE_HEALTH_SETUP.md](GOOGLE_HEALTH_SETUP.md) (~15 min, one-time Google Cloud setup for YOUR account).
6. Everything works without steps 4–5 — graceful degradation is the point.

---

*Built by Bryan Ramirez-Gonzalez as a daily-use app for myself first, and a demonstration of production AI engineering second. AI pair-engineering was used heavily in development — with every change gated behind the test suite and live verification, which is rather the point.*
