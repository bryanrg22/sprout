# Research: standards for distribution, CI, evals, testing, and current model line-ups

Research date: 2026-11-22. Every claim carries a source URL; anything not confirmed from a primary source is marked **UNCONFIRMED**.
Sections are written in the order E, A, C, D, B (E is the most time-sensitive).

_Status: in progress — sections are appended as they are completed._

---

## E. Current model line-ups and list prices (fetched 2026-11-22)

### E.1 Anthropic (Claude API) — all fetched live from platform.claude.com

Sources: [models overview](https://platform.claude.com/docs/en/about-claude/models/overview) · [pricing](https://platform.claude.com/docs/en/about-claude/pricing) · [model deprecations](https://platform.claude.com/docs/en/about-claude/model-deprecations)

**Vision:** "All current models support text and image input, text output, multilingual capabilities, vision, and tool use." (models overview)

#### Latest models (the four the docs recommend choosing among)

| Model | API ID | Input $/MTok | Output $/MTok | 5m cache write | 1h cache write | Cache read | Context | Max out | Thinking | Default effort | Retirement "not sooner than" |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Claude Fable 5.2 | `claude-fable-5-2` | 8 | 40 | 10 | 16 | 0.20 (0.025x) | 1M | 128K | Adaptive, always on | high | 2027-11-09 |
| Claude Opus 5.5 | `claude-opus-5-5` | 4 | 20 | 5 | 8 | 0.20 (0.05x) | 1M | 128K | Adaptive, always on | medium | 2027-09-22 |
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | 2 | 10 | 2.50 | 4 | 0.10 (0.05x) | 1M | 128K | Adaptive | high | 2027-09-28 |
| Claude Haiku 5.5 (prompt <= 100k tok) | `claude-haiku-5-5` | 0.10 | 0.50 | 0.125 | 0.20 | 0.01 | 1M | 128K | Adaptive | medium | 2027-10-07 |
| Claude Haiku 5.5 (prompt > 100k tok) | same | 0.50 | 2.50 | 0.625 | 1.00 | 0.05 | | | | | |

- Docs' own guidance: "start with Claude Opus 5.5 for most workloads"; Fable 5.2 "for demanding reasoning and long-horizon agentic work, or when your evals on Claude Opus 5.5 at higher effort still fall short"; Haiku 5.5 "for high-volume, latency-sensitive tasks such as classification, extraction, and routing". (models overview)
- Reliable knowledge cutoff for all four: Jun 2026. (models overview)
- Batch API = 50% off input and output for every model. (pricing)
- Haiku 5.5 is priced per request by prompt length (all input tokens incl. cache reads/writes); over 100,000 tokens the whole request pays the higher tier. Every other 4.6+ model gets the full 1M window at flat pricing. (pricing, "Long context pricing")

#### Older models still served on the Claude API

| Model | API ID | Input | Output | 5m write | 1h write | Cache read | Context | Max out | Status / retirement |
|---|---|---|---|---|---|---|---|---|---|
| Claude Fable 5.1 | `claude-fable-5-1` | 10 | 50 | 12.50 | 20 | 0.25 | 1M | 128K | Active; not sooner than 2027-09-01 |
| Claude Fable 5 | `claude-fable-5` | 10 | 50 | 12.50 | 20 | 1.00 | 1M | 128K | Active; not sooner than 2027-06-09 |
| Claude Mythos 5.2 / 5.1 / 5 | `claude-mythos-5-2` / `-5-1` / `-5` | 8/10/10 | 40/50/50 | as Fable | as Fable | as Fable | 1M | 128K | Active but **limited availability** (verified orgs only) |
| Claude Opus 5 | `claude-opus-5` | 5 | 25 | 6.25 | 10 | 0.50 | 1M | 128K | Active; not sooner than 2027-07-24 |
| Claude Opus 4.8 | `claude-opus-4-8` | 5 | 25 | 6.25 | 10 | 0.50 | 1M | 128K | Active; not sooner than 2027-05-28 |
| Claude Opus 4.7 | `claude-opus-4-7` | 5 | 25 | 6.25 | 10 | 0.50 | 1M | 128K | Active; not sooner than 2027-04-16 |
| Claude Opus 4.6 | `claude-opus-4-6` | 5 | 25 | 6.25 | 10 | 0.50 | 1M | 128K | Active; not sooner than 2027-02-05 |
| Claude Opus 4.5 | `claude-opus-4-5-20251101` | 5 | 25 | 6.25 | 10 | 0.50 | 200K | 64K | Active; not sooner than **2026-11-24** (two days from the research date — no deprecation notice posted yet) |
| Claude Sonnet 5 | `claude-sonnet-5` | 2 | 10 | 2.50 | 4 | 0.20 | 1M | 128K | Active; not sooner than 2027-06-30 |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` | 3 | 15 | 3.75 | 6 | 0.30 | 1M | 128K | Active; not sooner than 2027-02-17 |
| Claude Sonnet 4.5 | `claude-sonnet-4-5-20250929` (and `claude-sonnet-4-5`) | 3 | 15 | 3.75 | 6 | 0.30 | 200K | 64K | **Deprecated 2026-09-30, retires 2026-11-30**; replacement `claude-sonnet-5-5` |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` | 1 | 5 | 1.25 | 2 | 0.10 | 200K | 64K | Active; "not sooner than **2026-10-15**" — that floor has already passed, so a 60-day deprecation notice can arrive at any time |

Retired on the Claude API (requests fail): Opus 4.1 (2026-08-05), Opus 4 and Sonnet 4 (2026-06-15), Haiku 3 (2026-04-20), Haiku 3.5 and Sonnet 3.7 (2026-02-19). (deprecations page)

**The three models named in the brief:**
- `claude-sonnet-5` — Active, $2/$10, not sooner than 2027-06-30. The $2/$10 launch price was made permanent ("The previously scheduled increase to $3/$15 ... on September 1, 2026 will not occur"). Superseded by `claude-sonnet-5-5` at the same $2/$10 but with a cheaper cache read ($0.10 vs $0.20).
- `claude-opus-4-8` — Active, $5/$25, not sooner than 2027-05-28. Superseded by `claude-opus-5-5` at **$4/$20** (cheaper and newer).
- `claude-haiku-4-5` — Active, $1/$5, retirement floor (2026-10-15) already passed. Superseded by `claude-haiku-5-5` at **$0.10/$0.50** for prompts <= 100k tokens — a 10x price cut.

Anthropic's notice policy: "at least 60 days' notice before model retirement for publicly released models." (deprecations page)

#### Anthropic facts that affect an app calling the Messages API directly

- **Sampling parameters removed.** `temperature`, `top_p`, `top_k` are "Removed in API version `2026-10-21`" (400 error). On earlier API versions they return 400 "when set to a non-default value on Claude 4.7 and later models". Replacement: omit them and steer with prompting. (deprecations page, "API parameter deprecations")
- **Thinking.** Fable 5.2 and Opus 5.5 are "Adaptive (always on)"; manual extended thinking (`thinking.type: "enabled"` + `budget_tokens`) "is deprecated on Claude Opus 4.6 and Claude Sonnet 4.6 and not accepted on later models." Depth is steered with the `effort` parameter. (models overview)
- **Tokenizer.** "Claude 4.7 and later models ... use a newer tokenizer ... produces approximately 30% more tokens for the same text." So a like-for-like $/MTok comparison between Sonnet 4.6-and-earlier and anything newer understates the newer model's real cost by up to ~30%. (pricing)
- **Web search tool:** "$10 USD per 1,000 searches, plus standard token costs for search-generated content"; failed searches are not billed. **Web fetch:** no extra charge beyond tokens. (pricing)
- **Tool-use system prompt overhead** (tool_choice auto/none): 286 tokens on Opus 5.5 / Sonnet 5.5 / Haiku 5.5 / Opus 5; 290 on Opus 4.8; 354 on Sonnet 5; 496 on Haiku 4.5. (pricing)
- **Prompt caching multipliers:** 5-minute write 1.25x, 1-hour write 2x, read 0.1x (0.05x on Opus 5.5 / Sonnet 5.5; 0.025x on Fable 5.2 / 5.1). (pricing)
- **Fast mode** (up to 2.5x output speed): Fable 5.2 $16/$80, Opus 5.5 $8/$40. (pricing)
- Model capabilities can be read programmatically from the Models API (`max_input_tokens`, `max_tokens`, `capabilities`). (models overview)

**Does Anthropic offer image generation?** See E.3.

### E.2 OpenAI API — all fetched live (platform.openai.com now 301-redirects to developers.openai.com/api/docs)

Sources: [pricing](https://developers.openai.com/api/docs/pricing) · [models](https://developers.openai.com/api/docs/models) · [all models](https://developers.openai.com/api/docs/models/all) · [deprecations](https://developers.openai.com/api/docs/deprecations) · per-model pages linked in the table · [reasoning guide](https://developers.openai.com/api/docs/guides/reasoning) · [function calling guide](https://developers.openai.com/api/docs/guides/function-calling) · [web search guide](https://developers.openai.com/api/docs/guides/tools-web-search)

Naming changed: the current tiers are **Astra** (top) / **Sol** (everyday flagship) / **Terra** (was "mini") / **Luna** (was "nano"). The gpt-5.6-terra page says it "roughly corresponds to the mini tier in earlier GPT-5 families", gpt-5.6-luna "the nano tier", gpt-5.6-sol "the unsuffixed model tier"; the `gpt-5.6` alias routes to `gpt-5.6-sol`.

#### Text/vision models listed as Active — Standard tier, $ per 1M tokens, "short context" (<= 272K input tokens)

All of these: text + image input, text output; context window 1,050,000 (max input 922,000), max output 128,000; support Chat Completions, Responses and Batch; support streaming, structured outputs, function calling, web search, prompt caching (per the individual model pages).

| Model ID | Input | Cached input | Output | Reasoning model? | Effort values | Knowledge cutoff | Notes |
|---|---|---|---|---|---|---|---|
| [`gpt-6.2-astra`](https://developers.openai.com/api/docs/models/gpt-6.2-astra) | 8.00 | 0.40 | 40.00 | Yes | `none` rejected | 2026-05-18 | current top model |
| [`gpt-6.2-sol`](https://developers.openai.com/api/docs/models/gpt-6.2-sol) | 2.00 | 0.10 | 10.00 | Yes | `none` rejected | 2026-06-01 | "go-to model for everyday work" |
| [`gpt-6.1-terra`](https://developers.openai.com/api/docs/models/gpt-6.1-terra) | 1.00 | 0.05 | 5.00 | Yes | none, low, medium (default), high, xhigh, max | 2026-06-01 | "visual reasoning ... clear, natural writing" |
| [`gpt-6-luna`](https://developers.openai.com/api/docs/models/gpt-6-luna) | 0.10 | 0.01 | 0.50 | Yes | none, low, medium (default), high, xhigh, max | 2026-05-18 | "most efficient model for focused, high-volume tasks" |
| `gpt-6-astra` | 10.00 | 1.00 | 50.00 | Yes | `none` rejected | — | previous top model; **no function calling on Chat Completions** |
| `gpt-6.1-sol` | 2.00 | 0.10 | 10.00 | Yes | `none`/`minimal` rejected | — | **no function calling on Chat Completions** |
| `gpt-6-sol` | 2.00 | 0.20 | 10.00 | Yes | — | — | |
| [`gpt-5.6-sol`](https://developers.openai.com/api/docs/models/gpt-5.6-sol) | 4.00 | 0.40 | 20.00 | Yes | none, low, medium (default), high, xhigh, max | 2026-02-16 | pricing page: "GPT-5.6 Sol **promotional pricing is available until November 30, 2026**" — the post-promo price is not stated on OpenAI's pages. Secondary coverage of the August 2026 cut says the pre-promo list price was $5 / $30 ([community.openai.com](https://community.openai.com/t/20-price-reduction-for-gpt-5-6-sol-api-codex-credits-and-chatgpt-work/1391726/3), [yellow.com](https://yellow.com/news/openai-cuts-gpt-56-sol-prices)), so a reversion to about $5 / $30 from 2026-12-01 is plausible but **UNCONFIRMED** |
| [`gpt-5.6-terra`](https://developers.openai.com/api/docs/models/gpt-5.6-terra) | 2.00 | 0.20 | 12.00 | Yes | same as above | 2026-02-16 | |
| [`gpt-5.6-luna`](https://developers.openai.com/api/docs/models/gpt-5.6-luna) | 0.20 | 0.02 | 1.20 | Yes | same as above | 2026-02-16 | |
| `gpt-5.5` | 5.00 | 0.50 | 30.00 | Yes | default medium | — | |
| `gpt-5.5-pro` | 30.00 | — | 180.00 | Yes | | | |
| `gpt-5.4` | 2.50 | 0.25 | 15.00 | Yes | | | |
| `gpt-5.4-pro` | 30.00 | — | 180.00 | Yes | | | |
| `gpt-5.4-mini` | 0.75 | 0.075 | 4.50 | Yes | | | |
| `gpt-5.2` | 1.75 | 0.175 | 14.00 | Yes | | | |
| `gpt-5.2-pro` | 21.00 | — | 168.00 | Yes | | | |

"—" = not fetched for that model page; prices for every row are from the pricing page. Long-context (>272K input tokens) requests cost 2x input/cache and 1.5x output for the whole request. Batch = 50% of Standard. Cache writes on the 6.x and 5.6 families are billed at 1.25x input (30-minute) — unlike older OpenAI models where caching was automatic and write-free. (pricing page; model pages)

**Notable same-price pairs across vendors (list price only, not a quality claim):** `gpt-6-luna` and `claude-haiku-5-5` are both $0.10 / $0.50; `gpt-6.2-sol` and `claude-sonnet-5-5` are both $2 / $10 with $0.10 cache read; `gpt-6.2-astra` and `claude-fable-5-2` are both $8 / $40.

#### Deprecated but still served (listed under "Deprecated models" on the all-models page)

| Model ID | Input | Cached | Output | Reasoning? | Shutdown | OpenAI's listed replacement |
|---|---|---|---|---|---|---|
| `gpt-4.1-mini` (snapshot `gpt-4.1-mini-2025-04-14`) | 0.40 | 0.10 | 1.60 | **No** ("no reasoning step") | **2027-01-14** (notice 2026-10-14) | `gpt-6-luna` |
| `gpt-4.1` (`gpt-4.1-2025-04-14`) | 2.00 | 0.50 | 8.00 | No | 2027-01-14 | `gpt-6-luna` |
| `gpt-4o` (`-2024-08-06`, `-2024-11-20`) | 2.50 | 1.25 | 10.00 | No | 2027-01-14 | `gpt-6-luna` |
| `gpt-4o-mini` (`-2024-07-18`) | 0.15 | 0.075 | 0.60 | No | 2027-01-14 | `gpt-6-luna` |
| `gpt-5`, `gpt-5-mini`, `gpt-5-nano`, `gpt-5-pro` | 1.25 / 0.25 / 0.05 / 15 | 0.125 / 0.025 / 0.005 / — | 10 / 2 / 0.40 / 120 | Yes | **2026-12-11** | `gpt-6.1-sol` / `gpt-6.1-terra` / `gpt-6-luna` |
| `o3`, `o3-pro` | 2 / 20 | 0.50 / — | 8 / 80 | Yes | 2026-12-11 | `gpt-6.1-sol` |
| `gpt-5.1` | 1.25 | 0.125 | 10.00 | Yes | 2027-04-01 | `gpt-6-sol` |
| `gpt-5.4-nano` | 0.20 | 0.02 | 1.25 | Yes | 2027-04-01 | `gpt-6-luna` |

- The deprecations page lists the gpt-4.1-mini shutdown against the dated snapshot `gpt-4.1-mini-2025-04-14`; the model page marks both the model and that snapshot "Deprecated" and lists no other snapshot. Since the alias has only that one snapshot, treat the alias as going away on 2027-01-14 too (the page does not say so in as many words — **UNCONFIRMED** for the bare alias).
- Already shut down: `gpt-4.1-nano`, `o4-mini`, `o3-mini`, `o1`, `gpt-4`, `gpt-4-turbo`, `gpt-3.5-turbo`, `gpt-image-1` (all 2026-10-23); `dall-e-2` / `dall-e-3` (2026-05-12); Assistants API (2026-08-26).
- **gpt-5.6 family: no deprecation entry** — not on the deprecations page and no note on any of the three model pages; listed Active.
- The OpenAI **Evals dashboard, API and graders** become read-only / shut down 2026-11-30; OpenAI's listed replacement is **Promptfoo**. Relevant to section D: do not build new eval tooling on the hosted OpenAI Evals product. (deprecations page)

#### Responses vs Chat Completions (matters for an app that speaks both)

- "Reasoning models work better with the Responses API. While the Chat Completions API is still supported..." (reasoning guide)
- "Chat Completions does not support function calling with GPT-6 Astra or GPT-6.1 Sol." (reasoning guide); the function calling guide says these two "require the Responses API for tool calling."
- Verbatim from the model pages (re-fetched to confirm): `gpt-6-luna` — "Use the Responses API for built-in tools and function calling. Chat Completions supports function calling only with `reasoning_effort` set to `none`." `gpt-6.1-terra` — "Tool calling requires the Responses API." `gpt-6.2-sol` — "Use it with the Responses API to call tools such as web search and computer use" and "The API rejects requests that set reasoning effort to `none`." Net effect: **for the whole GPT-6 generation, tool calling should go through the Responses API**; a Chat Completions tool-calling path only keeps working on the 5.x models (and on `gpt-6-luna` with reasoning off). The 5.6 pages state no such restriction.
- Strict mode: "Chat Completions requests remain non-strict by default"; Responses normalises schemas to strict where possible. (function calling guide)
- No Chat Completions endpoint deprecation is listed on the deprecations page.
- Reasoning tokens are billed as output tokens and count against `max_output_tokens`; OpenAI recommends "reserving at least 25,000 tokens for reasoning and outputs when you start experimenting". A too-small cap yields status `incomplete` with possibly no visible output. (reasoning guide)
- Sampling parameters (`temperature`, `top_p`): none of the fetched model pages or the reasoning guide states whether they are accepted on the 6.x / 5.6 models — **UNCONFIRMED**; verify with a live call per model.

#### Web search tool

| Variant | Price |
|---|---|
| `web_search` (GA; also the "preview" tool on reasoning models) | **$10.00 / 1k calls** + search content tokens billed at the model's rates |
| `web_search_preview` on non-reasoning models | $25.00 / 1k calls, search content tokens free |

- For `gpt-4o-mini` and `gpt-4.1-mini` with the non-preview tool, search content is billed as a fixed 8,000 input tokens per call. (pricing page)
- Use `{ "type": "web_search" }` on the **Responses API**. On Chat Completions, web search works only through the dedicated search model `gpt-5-search-api` ($1.25 / $10, 200k context) and lacks domain filters. (web search guide; pricing page)
- Web-search context is capped at 128k tokens regardless of model window; domain allow/block lists (up to 100) via `filters`; with `tool_choice: "auto"` search is optional — use `"required"` to force it. (web search guide)
- Display requirement: "you must show inline citations as prominent, clickable links." (web search guide)
- Anthropic's web search is the same list price: $10 / 1,000 searches. (Anthropic pricing page)

### E.3 Image generation (for a "photo -> pixel-art avatar" feature)

**Anthropic: no.** Vision docs FAQ: "Can Claude generate or edit images? No, Claude is an image understanding model only. It can interpret and analyze images, but it cannot generate, produce, edit, manipulate, or create images." ([vision docs](https://platform.claude.com/docs/en/build-with-claude/vision)) — so this feature needs an OpenAI key regardless of which provider the user picked for chat.

**OpenAI current image models** ([pricing](https://developers.openai.com/api/docs/pricing), [image generation guide](https://developers.openai.com/api/docs/guides/image-generation), [gpt-image-2.6-flare](https://developers.openai.com/api/docs/models/gpt-image-2.6-flare)):

| Model ID | Role | Text in | Image in | Image out | Status |
|---|---|---|---|---|---|
| `gpt-image-2.6-sunburst` | detailed / precise editing | $5 | $8 | $30 per 1M tokens | Active |
| `gpt-image-2.6-flare` | fast iteration | $5 | $8 | $30 | Active |
| `gpt-image-2.5-sunburst` / `-flare` | previous line | $5 | $8 | $30 | Active |
| `gpt-image-2` | | $5 | $8 | $30 | Deprecated, shutdown 2027-02-10 |
| `gpt-image-1.5`, `gpt-image-1-mini`, `chatgpt-image-latest` | | | | | Deprecated, shutdown **2026-12-01** |
| `gpt-image-1`, `dall-e-2`, `dall-e-3` | | | | | Shut down |

- Endpoints: `v1/images/generations` and `v1/images/edits` (photo -> avatar is an **edit** with the photo as input image). The image guide also describes an `image_generation` tool on the Responses API where a text model drives the image model.
- Transparent background: `background: "transparent"` with `output_format: "png"` or `"webp"`. Sizes: 1024x1024, 1536x1024, 1024x1536 or custom multiples of 16. Quality: low / medium / high / xhigh / max / auto. Complex prompts "may take up to 2 minutes". Organisation verification "may" be required for GPT Image models. (image guide)
- **Price per image: the vendor does not publish a per-image table for the 2.5 / 2.6 models** — the guide says to use a calculator that is rendered client-side and could not be fetched. **UNCONFIRMED.** The only per-image numbers on the page are a "historical" table; for `gpt-image-2`, which has the same $30/MTok output rate, 1024x1024 is listed at **$0.006 low / $0.053 medium / $0.211 high**. The guide warns "Equal token rates don't mean equal cost per image, because token use varies by model and quality", so treat those as an order-of-magnitude guide only, plus input-image tokens for the source photo at $8/MTok. Measure real cost from the `usage` block of one live call before quoting a number.

---

## A. iOS distribution without the 90-day expiry

### A.1 Current TestFlight rules (Apple primary sources)

| Rule | Value | Source |
|---|---|---|
| Build lifetime | "Each build is available to test for up to 90 days, starting from the day the developer uploads their build." | [testflight.apple.com](https://testflight.apple.com/) |
| After expiry | "When the testing period is over, you'll no longer be able to open the beta build." / "Your build becomes unavailable for testers after 90 days." | [testflight.apple.com](https://testflight.apple.com/), [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview) |
| Internal testers | "up to 100 members of your development team who hold the Account Holder, Admin, App Manager, Developer, or Marketing role" — i.e. they must be App Store Connect users. No TestFlight App Review. | [developer.apple.com/testflight](https://developer.apple.com/testflight/) |
| External testers | "up to 10,000 external testers per app", by email or public link | [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers) |
| External review | "The first build you submit requires a full review, but later builds for the same version might not." Max six builds submitted for TestFlight App Review per 24 h; one build per version in review at a time. | same |
| Devices / builds | up to 30 devices per tester; up to 100 builds shared | [developer.apple.com/testflight](https://developer.apple.com/testflight/) |
| Auto-update | Testers can enable automatic updates "to have the latest beta builds install automatically." | [testflight.apple.com](https://testflight.apple.com/) |

- **Can an expired build still launch?** Apple's tester-facing text says no ("no longer be able to open"). Forum reports are inconsistent (some expired builds keep running for a while), so do not rely on it. ([forum thread](https://developer.apple.com/forums/thread/76958))
- **Does app data survive installing a new build over an expired one?** **UNCONFIRMED from a primary source** — Apple's pages do not say. The only explicit data-loss statement Apple makes concerns App Clips ("some app data may be lost"). Expected platform behaviour is that an in-place update of the same bundle ID keeps the app container (expiry blocks launching; it does not uninstall), and the data is additionally mirrored to the user's private iCloud database, but verify on one device before telling a user "you will not lose anything". The thing that definitely destroys local data is **deleting** the expired app before reinstalling.
- The 90 days are per upload, so the only way to stay on TestFlight indefinitely is to upload a new build at least every ~80 days (A.4).

### A.2 Every realistic way to give the app to a handful of specific people

| Option | App Review? | Expiry | Who can install | Effort | Fit for "few friends, each pastes their own LLM key" |
|---|---|---|---|---|---|
| **TestFlight, internal testers** | None | 90 days per build | People you add as App Store Connect users (roles above) | Low; needs re-upload every <90 days | Good today for 2 people **if automated** (A.4). Gives them an App Store Connect role, which is more access than a friend needs. |
| **TestFlight, external testers** | TestFlight App Review on the first build of a version; later builds "might not" | 90 days per build | Anyone invited by email / public link | Low-medium | Same expiry problem; a scheduled upload can stall in beta review. |
| **App Store, public** | Full App Review, every version | **None** | Everyone | High once (metadata, screenshots, privacy policy + nutrition labels, review notes), low after | Removes expiry permanently but makes the app public and discoverable. |
| **App Store, unlisted** | Full App Review (identical bar), plus a separate request form | **None** | "anyone who has access to the link"; not in search, charts or categories | Same as public + one request | Best technical fit: no expiry, no discoverability, normal App Store updates. Risk: Apple decides eligibility — see below. |
| **Custom App (Apple Business / School Manager)** | App Review ("Once your app is approved...") | None | Only **organizations** you name by Organization ID, who distribute by MDM or redemption codes | High | Not suitable: recipients must be an organisation enrolled in Apple Business; friends are not. |
| **Ad hoc** | None | Tied to the provisioning profile / certificate (about 1 year for paid teams — forum-sourced, see below) | Only devices whose UDIDs you registered; 100 per device family per membership year | Medium: collect UDIDs, export .ipa, re-sign and reinstall yearly | Works, no review, but a yearly manual re-install replaces a 90-day one; no auto-update. |
| **Development-signed install from Xcode** | None | Paid team: profile lasts about a year; free "Personal Team": 7 days | Devices physically/wirelessly paired with your Mac | Low per install, but needs the device in hand | Only practical for your own phone. |
| Enterprise Program (in-house) | None | Cert-bound | Employees of the enrolled organisation only | n/a | Not eligible — "for organizations that require private distribution directly to employees". |

Sources: [unlisted app distribution](https://developer.apple.com/support/unlisted-app-distribution/) · [custom apps](https://developer.apple.com/custom-apps/) · [devices overview](https://developer.apple.com/help/account/devices/devices-overview/) · [distribution methods in Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) · [compare memberships](https://developer.apple.com/support/compare-memberships/) · [certificates support](https://developer.apple.com/support/certificates/)

**Unlisted distribution, in Apple's words:**
- "Release your apps that aren't suited for public distribution as unlisted on the App Store, discoverable only with a direct link."
- Prerequisite: "your app must either already be on the App Store or be ready for final distribution and submitted to App Review." Then "Add a note in the Review Notes section of your submission to indicate that your app is intended for unlisted distribution" and submit the request form at developer.apple.com/contact/request/unlisted-app/.
- "Requests will be declined ... if your app hasn't been submitted to App Review, or if your app is in a beta or prerelease state."
- Once approved the method "will apply to any future versions of the app."
- Apple's own examples are organisational ("partner sales tools, employee resources, or research studies"; "limited audiences (such as part-time employees, franchisees, partners ...)"). Whether Apple approves an unlisted request for a personal app shared with friends is **UNCONFIRMED** — the page neither includes nor excludes it. Apple also advises: "Consider implementing a mechanism within your app to prevent unauthorized use" (a bring-your-own-key app already is one, in effect).

**Ad hoc details:**
- "register up to 100 of the following devices, per product family, per membership year"; disabling a device mid-year "won't increase your number of available devices"; the list can be reset once at membership renewal. (devices overview)
- Profile/cert lifetime: Apple's certificates page does not state validity periods. That paid-team profiles last about one year and Personal Team profiles 7 days comes from Apple's compare-memberships page for the free tier ("Provisioning profiles that enable apps to be installed on a device will expire 7 days from issuance") and from Apple Developer Forums answers for the paid tier ([thread](https://developer.apple.com/forums/thread/62300), [thread](https://developer.apple.com/forums/thread/70282)) — the 1-year figure is **UNCONFIRMED from Apple documentation**, though it is visible on any profile in Xcode.

### A.3 App Review risks for a health/weight app with an AI coach and user-supplied keys

All quotes from the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). These apply to public **and** unlisted App Store distribution, and to external TestFlight builds (which are reviewed against the same guidelines).

1. **5.1.3(ii) — health data in iCloud.** "Apps must not write false or inaccurate data into HealthKit ... and may not store personal health information in iCloud." An app that mirrors weight/nutrition/sleep records to CloudKit is squarely in the scope of this sentence. This is the single biggest review risk for a SwiftData + CloudKit health app; decide the position (e.g. what is and is not synced, whether HealthKit-sourced samples are excluded from the mirrored store) before submitting. How strictly review applies it to user-entered food/weight logs versus HealthKit-sourced records is **UNCONFIRMED**.
2. **5.1.2(i) — third-party AI.** "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so." Needs an explicit in-app consent step naming the provider before the first request that sends meals/photos/weights to Anthropic or OpenAI.
3. **5.1.3(i) — health data use.** Health/fitness data may not be disclosed to third parties "for advertising, marketing, or other use-based data mining purposes other than improving health management ... and then only with permission"; "You must disclose the specific health data that you are collecting from the device."
4. **2.1(a) + "Before you submit" — full access for the reviewer.** "Provide App Review with full access to your app. If your app includes account-based features, provide either an active demo account or fully-featured demo mode, plus any other ... resources that might be needed to review your app (such as login credentials ...)." For a bring-your-own-key app the practical consequence is: put a working, spend-capped API key in the App Review notes (or ship a demo mode), otherwise the reviewer sees every AI feature as non-functional. Applying this wording to API keys is my inference — the guideline names logins, not keys.
5. **1.4.1 — medical scrutiny.** "Apps should remind users to check with a doctor in addition to using the app and before making medical decisions"; accuracy claims about health measurements must disclose methodology. Avoid accuracy claims for photo-based calorie estimates.
6. **2.5.1 — HealthKit purpose.** Apps "should use APIs and frameworks for their intended purposes and indicate that integration in their app description ... HealthKit should be used for health and fitness purposes and integrate with the Health app."
7. **5.1.1(i) — privacy policy** link required in App Store Connect and in-app, covering retention/deletion and each third party.
8. **3.1.1 — "license keys".** "Apps may not use their own mechanisms to unlock content or functionality, such as license keys ...". A user-supplied third-party API key is not a purchase mechanism of the developer's, and bring-your-own-key apps exist on the store, but if AI features look "locked" until a code is pasted a reviewer could raise it. Risk judged low; **UNCONFIRMED** how review treats BYO-key in practice.
9. **5.1.1(ix) — regulated fields.** Apps in "healthcare" "should be submitted by a legal entity ... and not by an individual developer". Consumer fitness/calorie trackers are routinely published by individuals; flagged only because the wording exists.
10. **1.2 / 4.7** mention AI content apps and chatbots (content filtering, reporting, age restriction for software that "exceeds the app's age rating"); a single-user coach with no user-to-user content is at the light end of this.

### A.4 Standard ways to automate a recurring TestFlight upload

**Option 1 — Xcode Cloud scheduled workflow (least secret-handling).**
- Start condition "On a Schedule for a Branch": "specify the frequency, time, and branch"; Apple's own example is exactly this use case — "distribute a new version based on a schedule; for example, once per week." ([Configuring start conditions](https://developer.apple.com/documentation/xcode/configuring-start-conditions))
- Workflow = Archive action + TestFlight (internal or external) post-action. Signing is managed by Apple; no certificates or API keys stored by you. ([Xcode Cloud](https://developer.apple.com/xcode-cloud/))
- Cost: "Apple Developer Program membership includes 25 compute hours per month." Next tier 100 h for US$49.99/month. (same)
- xcodegen projects: Xcode Cloud needs a project to build, so either commit the generated `.xcodeproj` or generate it in `ci_scripts/ci_post_clone.sh` (the documented hook that runs after clone; scripts must live in a `ci_scripts` directory next to the project). ([Writing custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)) Whether a workflow can be created at all when no `.xcodeproj` is committed is **UNCONFIRMED** — the common practice is to commit the project file for Xcode Cloud.
- External testers: "distributing a new version to external testers with TestFlight requires a clean build." ([workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference))

**Option 2 — GitHub Actions `schedule` + fastlane + App Store Connect API key.**
- Trigger: `on: schedule: - cron: ...` (UTC by default; runs on the default branch; may be delayed at the top of the hour). **Pitfall for exactly this use case:** "In a public repository, scheduled workflows are automatically disabled when no repository activity has occurred in 60 days." A keep-alive upload job in a quiet public repo will silently stop — pick an interval and add an alert, or have the job itself make a commit (e.g. the build-number bump). ([GitHub docs: schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows))
- Steps: checkout -> select Xcode -> xcodegen -> bump build number (fastlane `app_store_build_number` + 1, or the run number) -> archive + export -> `pilot`/`upload_to_testflight`.
- **Secrets required:**
  1. App Store Connect API **Team key**: Key ID, Issuer ID, and the `.p8` private key ("cannot be downloaded again"). fastlane consumes them through `app_store_connect_api_key(key_id:, issuer_id:, key_filepath:/key_content:)`; `pilot`, `deliver`, `match`, `cert`, `sigh` all accept API keys. Individual (non-team) keys cannot use provisioning endpoints. ([fastlane ASC API docs](https://docs.fastlane.tools/app-store-connect-api/))
  2. Signing material, by one of: (a) `xcodebuild -allowProvisioningUpdates -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` so Xcode creates/updates certificates and profiles itself with the API key (flags confirmed present in the local Xcode 26.4 `xcodebuild -help`); (b) fastlane `match` (a private repo/bucket of encrypted certs + `MATCH_PASSWORD`); or (c) a base64 distribution `.p12` + its password + the provisioning profile, imported into a temporary keychain.
  3. Nothing else — no Apple ID password or 2FA session is needed when the API key is used.
- fastlane 2.242.0 is preinstalled on the macOS runner image. ([macos-26 image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md))

**Either way:** every upload needs a higher `CFBundleVersion`; internal-tester builds skip review entirely; set testers' TestFlight to automatic updates so the new build lands without action.

---

## C. CI for an iOS app on GitHub Actions (late 2026)

### C.1 Runner images and Xcode versions (from the runner-images repo, image versions dated 2026-11-17/18)

| Label | OS | Arch | Xcode versions installed | Default |
|---|---|---|---|---|
| `macos-latest`, `macos-26` | macOS 26.7.2 | arm64 (M1, 3 vCPU, 7 GB RAM, 14 GB SSD) | 26.0.1, 26.1.1, 26.2, 26.3, **26.4.1**, 26.5, 26.6 | 26.6 |
| `macos-26-intel` | macOS 26 | x64 (4 vCPU, 14 GB) | (same family) | |
| `macos-15` | macOS 15.8.2 | arm64 | 16.0–16.4, 26.0.1–26.3 (no 26.4+) | 16.4 |
| `xcode-27` (public preview) | macOS 27.0.1 | arm64 | 27.0, 27.1, 27.2 | 27.1 |
| `macos-14` | — | — | **retired from GitHub Actions on 2026-11-02** | |

Sources: [runner-images README](https://github.com/actions/runner-images/blob/main/README.md) · [macos-26-arm64 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) · [macos-15-arm64 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md) · [xcode-27 readme](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) · [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

- **Is Xcode 26.4 available?** Yes, on `macos-26` only, as **26.4.1** (build 17E202) at `/Applications/Xcode_26.4.1.app`, with the symlink `/Applications/Xcode_26.4.app`. The exact local build (26.4, 17E192) is not there: the image policy is "when a new patch version is released, the previous patch version will be replaced". It is **not** the default — 26.6 is.
- **How to select it:** `sudo xcode-select -s /Applications/Xcode_26.4.app` (or `DEVELOPER_DIR=/Applications/Xcode_26.4.app/Contents/Developer` as job env), or the `maxim-lobanov/setup-xcode` action with `xcode-version: '26.4'`.
- **Simulators with that Xcode:** runtime **iOS 26.4.1** with iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone 17e, iPhone Air and iPads. Policy: "only three major.minor versions of platform tools and simulator runtimes will be available for installed Xcode" — currently iOS 26.2, 26.4, 26.5 — so pinning an old runtime will eventually break.
- Pin the OS label (`macos-26`), not `macos-latest`: "-latest migration ... happens over 1-2 months", and at most 2 GA + 1 beta macOS images are supported at a time.
- Preinstalled and relevant: Homebrew 7.0.14, fastlane 2.242.0, xcbeautify 3.2.1, SwiftFormat 0.64.7, jq, yq, GitHub CLI, Ruby 3.4. **Not preinstalled: xcodegen** (and SwiftLint is not listed) — `brew install xcodegen` (current release 2.48.0).

### C.2 Cost

- "Standard GitHub-hosted runners are free in public repositories" (usage "does not reduce the included compute usage"). The billing page does not name macOS explicitly in that sentence; the runners reference lists the standard macOS labels (`macos-latest`, `macos-15`, `macos-26`, `xcode-27`) in its **public repositories** table, so standard macOS runners are covered. "Larger runners are billed for public repositories." ([billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners))
- Private repos: macOS is **$0.062 per minute**; included usage is now expressed in dollars (Free $12/month, Pro $18/month) rather than minutes — $12 is roughly 190 macOS minutes. Cache: 10 GB per repository. (billing page)
- macOS jobs "may take longer to start" during high demand; arm64 runners have no static UDID. (runners reference)

### C.3 Known-good minimal workflow shape

Shape only — assembled from the documented pieces above; it has **not** been run against this repository. Action SHAs are the latest releases as of 2026-11-22 (looked up via the GitHub API).

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
permissions:
  contents: read                      # least-privilege GITHUB_TOKEN
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test:
    runs-on: macos-26                 # pinned OS label, not macos-latest
    timeout-minutes: 30
    env:
      DEVELOPER_DIR: /Applications/Xcode_26.4.app/Contents/Developer
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1   # v7.0.1
      - run: brew install xcodegen
      - run: xcodegen generate
      - name: Test
        run: |
          set -o pipefail
          xcodebuild test \
            -project App.xcodeproj -scheme App \
            -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
            -resultBundlePath "$RUNNER_TEMP/test.xcresult" \
            -enableCodeCoverage YES \
            -parallel-testing-enabled NO \
            -retry-tests-on-failure -test-iterations 2 \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify
      - name: Verify counts and write summary        # never trust the pipe alone
        if: always()
        run: |
          xcrun xcresulttool get test-results summary --path "$RUNNER_TEMP/test.xcresult" > summary.json
          jq -r '"Result: \(.result)  total \(.totalTestCount)  passed \(.passedTests)  failed \(.failedTests)  skipped \(.skippedTests)"' summary.json >> "$GITHUB_STEP_SUMMARY"
          xcrun xccov view --report --only-targets "$RUNNER_TEMP/test.xcresult" >> "$GITHUB_STEP_SUMMARY"
          test "$(jq -r .result summary.json)" = "Passed"
          test "$(jq -r .totalTestCount summary.json)" -ge 400     # guard against "0 tests ran, green"
      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9   # v7.0.2
        if: always()
        with: { name: xcresult, path: "${{ runner.temp }}/test.xcresult", retention-days: 7 }
```

Verified locally on Xcode 26.4 (17E192) against an existing result bundle: `xcrun xcresulttool get test-results summary --path X.xcresult` returns JSON with `result`, `totalTestCount`, `passedTests`, `failedTests`, `skippedTests`; `xcrun xccov view --report --only-targets X.xcresult` prints per-target line coverage. `xcodebuild -help` on the same Xcode lists `-resultBundlePath`, `-enableCodeCoverage`, `-retry-tests-on-failure`, `-test-iterations`, `-parallel-testing-enabled`, `-testPlan`, `-test-timeouts-enabled`.

### C.4 Common pitfalls

1. **Wrong Xcode.** The default on `macos-26` is 26.6, not 26.4 — select explicitly, and print `xcodebuild -version` in the log.
2. **Simulator destination names.** Custom-named local simulators do not exist on the runner. Use a stock device from the image list with an explicit `OS=`, or create one in the job (`xcrun simctl create`). A destination that matches nothing fails late with a long list of available destinations.
3. **Code signing.** Simulator builds need no certificate; `CODE_SIGNING_ALLOWED=NO` is the common switch. Caveat (my inference, not from a primary source — **UNCONFIRMED**): with signing fully disabled, entitlements are not applied, so code paths that depend on app groups / keychain access groups / CloudKit can behave differently from a local run. If tests touch an app-group container, prefer ad-hoc signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`) and compare one run each way.
4. **Exit codes through pipes.** `xcodebuild | xcbeautify` hides failure without `set -o pipefail`; independently assert on the xcresult summary (result + a minimum test count).
5. **Flaky simulator boots / slow runner.** Standard arm64 runner is 3 vCPU / 7 GB. Disable parallel testing or cap workers, set a job `timeout-minutes`, enable test timeouts, allow one retry (`-retry-tests-on-failure`) and treat a retried pass as a flake to investigate rather than as green.
6. **Caching.** Cache SwiftPM checkouts keyed on `Package.resolved` if there are package dependencies; caching all of DerivedData is usually not worth it (large, invalidates often; 10 GB cache cap per repo). Practitioner consensus, not a vendor rule.
7. **Generated project drift.** Since sources are globbed by xcodegen, CI regenerating the project catches "file exists locally but not in the committed project".
8. **Secrets and forks.** The test job needs no secrets; keep it that way so fork PRs work, and never use `pull_request_target` to run untrusted code ("Avoid using the `pull_request_target` workflow trigger if it's not necessary"). ([secure use reference](https://docs.github.com/en/actions/reference/security/secure-use))
9. **Unit tests must not hit the network or real LLM APIs** — record/replay (section D.6).

### C.5 Supply-chain and secret gates (standard)

- **Pin actions to a full commit SHA:** "Pin references to actions to a commit SHA in your workflow files"; tags are weaker because "a tag can be moved or deleted if a bad actor gains access to the repository storing the action." ([secure use reference](https://docs.github.com/en/actions/reference/security/secure-use))
- **Dependabot for actions:**
  ```yaml
  version: 2
  updates:
    - package-ecosystem: "github-actions"
      directory: "/"
      schedule: { interval: "weekly" }
  ```
  ([Dependabot docs](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot)). That Dependabot rewrites SHA pins and keeps a trailing `# vX.Y.Z` comment up to date is widely relied on but was not stated on the page fetched — **UNCONFIRMED** from that source.
- **`permissions:` least privilege** — "make sure that the `GITHUB_TOKEN` is granted the minimum required permissions." (secure use reference)
- **Secret scanning:** on public repositories "Secret scanning runs automatically for free", covering the entire Git history on all branches plus issues, PRs, discussions and wikis; partner-pattern secrets "are reported directly to the provider". ([about secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)) Push-protection status for public repos was not on the page fetched — **UNCONFIRMED** here.
- **gitleaks as a CI gate:** `gitleaks/gitleaks-action@v3` (v3.0.0; gitleaks CLI 8.30.1) on `push`/`pull_request` with `fetch-depth: 0`, on an `ubuntu-latest` job (cheap, free). `GITLEAKS_LICENSE` is "required for organizations, not required for user accounts". ([gitleaks-action](https://github.com/gitleaks/gitleaks-action)) For a bring-your-own-key app this is a meaningful gate: the realistic leak is a developer's own test key in a fixture, plist or recorded HTTP response.
- OpenSSF Scorecard "flags risky supply chain practices", including unpinned actions and token permissions. (secure use reference)

### C.6 Alternative: Xcode Cloud

- "Apple Developer Program membership includes 25 compute hours per month"; then US$49.99/month for 100 h. "running 5 tests of 12 minutes each equals one compute hour." ([Xcode Cloud](https://developer.apple.com/xcode-cloud/))
- Strengths: Apple-managed signing and direct TestFlight delivery, scheduled workflows, newest Xcode quickly. Weaknesses for this case: configuration lives in App Store Connect rather than in the repo (less visible in a public portfolio repo than a workflow file and badge), xcodegen needs a `ci_scripts/ci_post_clone.sh`, and gates like gitleaks/Dependabot still need GitHub.
- A reasonable split: GitHub Actions for PR/push tests + security gates (free for a public repo); Xcode Cloud only for the scheduled TestFlight upload, if signing secrets in GitHub are unwanted.

---

## D. LLM evaluation methodology for per-task model selection

Sources: Anthropic [define success criteria and build evaluations](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests) (the old "define success" URL now serves the same page) · Anthropic Engineering [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) · Anthropic Research [A statistical approach to model evals](https://www.anthropic.com/research/statistical-approach-to-model-evals) · OpenAI [evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices) · Hamel Husain [Your AI product needs evals](https://hamel.dev/blog/posts/evals/) · Eugene Yan [Patterns for building LLM-based systems](https://eugeneyan.com/writing/llm-patterns/) · [promptfoo docs](https://www.promptfoo.dev/docs/configuration/expected-outputs/)

### D.1 The loop everyone describes

1. **Define success criteria first**, per task, that are "Specific", "Measurable", "Achievable", "Relevant" — e.g. not "classify sentiments well" but "an F1 score of at least 0.85 ... on a held-out test set". "Most use cases need multidimensional evaluation along several success criteria" — task fidelity, consistency, tone, latency, price. (Anthropic)
2. **Collect a dataset** from "synthetic, domain-specific, purchased, human-curated, production, and historical data", including typical, edge and adversarial cases. (OpenAI)
3. **Define metrics/graders**, **run and compare**, then **continuously evaluate** — "Evaluate early and often." (OpenAI). Eugene Yan calls this Eval-Driven Development: task-specific evals "guide prompt engineering, model selection, and fine-tuning", rerun after every change, with a metric "simple enough to compare across runs with a single number".
4. Anti-patterns named by OpenAI: generic metrics only, datasets that do not reflect production traffic, "vibe-based evals", and not calibrating automated metrics against human judgement.

### D.2 Golden datasets and meaningful sizes for a small project

- Anthropic's three design principles: "Be task-specific ... Don't forget to factor in edge cases!"; "Automate when possible"; "**Prioritize volume over quality**: More questions with slightly lower signal automated grading is better than fewer questions with high-quality human hand-graded evals."
- Where to start: "**20-50 simple tasks drawn from real failures is a great start.**" Early on, changes have large effects, so small samples suffice. (Anthropic Engineering)
- Each task needs an unambiguous pass/fail — "two domain experts would independently reach the same pass/fail verdict" — and a reference answer proving it is solvable; "a 0% pass rate across many trials usually signals a broken task". Build **balanced** sets: cases where a behaviour should occur *and* where it should not. (Anthropic Engineering)
- Synthetic generation with an LLM is endorsed for breadth (Hamel's example prompt generates 50 instructions at a time; Rechat keeps "hundreds of these unit tests"), but seed from real logged inputs and failures. (Hamel)
- Anthropic's worked examples use 50–1,000 items per eval (e.g. 100 inquiries for a tone Likert, 200 articles for ROUGE, 1,000 tweets for exact match). (Anthropic docs)
- **What size buys what resolution** (my arithmetic from the binomial standard error, not a quoted rule): at an 80% pass rate, n=30 gives a 95% CI of about ±14 points, n=50 ±11, n=100 ±8, n=200 ±5.5. So 30–50 items per task detects only large gaps (>15–20 points) between unpaired models; paired analysis (D.4) recovers a lot of power from the same items.

### D.3 Graders: code first, model second, human to calibrate

- Anthropic's ordering: "choose the fastest, most reliable, most scalable method: 1. **Code-based grading**: Fastest and most reliable, extremely scalable, but also lacks nuance ... 2. **Human grading**: Most flexible and high quality, but slow and expensive. Avoid if possible. 3. **LLM-based grading**: Fast and flexible ... Test to ensure reliability first, then scale."
- LLM-judge rules that recur across sources:
  - Detailed rubric; force a discrete output ("output only 'correct' or 'incorrect'"); let the grader reason first ("Use a grader model with thinking on"). (Anthropic docs)
  - Prefer **binary pass/fail or pairwise** over 1–5 scores; ask for reasoning before the verdict; control for response length. (OpenAI; Hamel: "start with binary good/bad labels")
  - "Generally best practice to evaluate with a different model from the one used to generate the evaluated output." (Anthropic docs code comment). Eugene Yan cites self-preference bias (GPT-4 +10% win rate for itself, Claude-v1 +25%) and recommends running pairwise comparisons in both orders to cancel position bias.
  - **Calibrate against human labels before trusting it**: label 25–50 examples per round yourself, measure agreement, and with imbalanced classes measure precision and recall separately. (Hamel). Give the judge an "Unknown" option and use one judge per dimension. (Anthropic Engineering)
- Mapping to typical app tasks (my synthesis):

| Task type | Primary grader | Notes |
|---|---|---|
| Tool-calling chat | Code | tool name in expected set, arguments equal/within tolerance, no call when none expected |
| Photo -> nutrition JSON | Code | schema-valid, then numeric error vs ground truth (D.8) |
| Text meal parsing | Code | item match + numeric tolerance against hand-labelled cases |
| Short insight phrasing | Code + LLM judge | code: length, banned phrases, numbers quoted match the input data; judge: binary rubric for tone/accuracy, calibrated on ~50 human labels |
| Plan generation with web search | LLM judge + code | code: required fields, citations present; judge: rubric per dimension |

### D.4 Repeats, variance, and deciding "within noise"

- Outputs vary run to run, so run **multiple trials per task**. Two summary views: **pass@k** (at least one of k succeeds) and **pass^k** (all k succeed) — "a 75% per-trial success rate over 3 trials gives ... ≈ 42% for pass^3". Use pass^k when users need consistency. (Anthropic Engineering)
- Anthropic's statistical recommendations: (1) report the standard error of the mean with every score; 95% CI = mean ± 1.96 × SEM; (2) cluster standard errors when items are related (several questions from one photo/conversation) — naive errors "can be over three times" too small; (3) reduce variance by resampling each question several times and scoring the per-question average; (4) **compare models with paired differences on the same items**, not two independent means — frontier models' per-question scores correlate 0.3–0.7, which shrinks the error of the difference; (5) do a power analysis to decide how many questions a target effect size needs.
- A workable decision rule that follows from the above (my synthesis): run every candidate on the identical items with k>=3 trials; compute per-item mean score per model; take per-item differences vs the incumbent; if the 95% CI of the mean difference includes 0, the models are **within noise on quality** and the decision goes to cost and latency. Record n, k, the CI and the date next to any claim.
- Sampling parameters can no longer be used to force determinism on current models: Anthropic's `temperature`/`top_p`/`top_k` are removed in API version 2026-10-21 (section E.1), so repeats are the only way to characterise variance there.

### D.5 Measuring cost, tokens and latency per candidate

- Price and latency are first-class success criteria in Anthropic's list ("Latency: what response time is acceptable?", "Price: ... cost per API call"), with example targets like "95% response time < 200ms".
- Capture from each response's `usage`: input, output, cache-read and cache-write tokens (and reasoning tokens on OpenAI, which "are billed as output tokens"), plus wall-clock latency and time-to-first-token if streaming. Compute **$ per task** from the price table at run time and store the price table version with the result.
- Compare **$ per completed task, not $ per token**: tokenizers differ (Claude 4.7+ "produces approximately 30% more tokens for the same text"), reasoning effort changes output-token counts by multiples, and image inputs tokenise differently per vendor and per resolution tier (section E).
- Report median and p95 latency, not the mean; a mobile UI is governed by the tail.
- promptfoo has built-in `cost` ("Cost is below a threshold") and `latency` ("Latency is below a threshold (milliseconds)") assertions if a harness is wanted rather than hand-rolled.

### D.6 Regression evals in CI, and recorded responses

- Hamel's three levels: **Level 1 unit-test-style assertions** that "should run fast and cheaply" "on every code change"; **Level 2 human and model eval** on logged traces at a slower cadence; **Level 3 A/B tests**, "okay to put this stage off". "Your pass rate is a product decision" — Level 1 need not be 100%.
- Anthropic separates **capability evals** (start low, "a hill to climb") from **regression evals** ("a nearly 100% pass rate"); capability tasks that saturate graduate into the regression suite.
- Standard split for an app with an existing XCTest suite (my synthesis of the above plus common practice — no single primary source prescribes it):
  1. **Deterministic replay tests, every PR, no network, no key.** Record real provider responses (success, tool-call, malformed JSON, refusal, truncated/`max_tokens`, 4xx/5xx/429) as fixtures and feed them through the real decoding/tool-dispatch/merge code via an injected `URLProtocol` or client protocol. These test *your code against the wire format*, not the model. Scrub keys and personal data from fixtures (gitleaks gate, C.5).
  2. **Live evals, on demand / nightly / when a prompt or default model changes**, with a key held as a CI secret or run locally. Not on fork PRs. Results stored as dated JSON so regressions are diffable.
  3. Re-record fixtures when a provider wire format or default model changes.
- promptfoo's CI docs show the same shape: `npx promptfoo@latest eval -c promptfooconfig.yaml -o results.json`, a response cache (`PROMPTFOO_CACHE_PATH`) restored with `actions/cache`, and a jq gate on `.results.stats.failures`. ([promptfoo CI docs](https://www.promptfoo.dev/docs/integrations/ci-cd/))
- **Tooling note:** OpenAI states "OpenAI is deprecating the Evals platform" — read-only from 2026-10-31, shutdown 2026-11-30 — and its deprecations page names **Promptfoo** as the replacement. Do not adopt the hosted OpenAI Evals API.

### D.7 Prompt versioning

- Keep prompts in the repository as code, with an explicit version identifier logged with every eval result and (ideally) every production call, so a score is always attributable to (prompt version, model ID, effort, date). OpenAI is retiring its hosted alternative — `/v1/prompts` and reusable prompt objects are deprecated with shutdown 2026-11-30, recommended replacement: "Move prompt content into application code". ([OpenAI deprecations](https://developers.openai.com/api/docs/deprecations))
- Model IDs are part of the version: Anthropic notes "Every Claude model ID is a pinned snapshot, including the dateless IDs used from the 4.6 generation on", so a pinned ID does not drift; OpenAI's current 6.x / 5.6 pages likewise list a single snapshot per ID.
- Re-run the suite whenever any element of that tuple changes (OpenAI: "Run evals on every change").

### D.8 Tool-calling evals

- What to measure (OpenAI, single-agent architecture): **tool selection** ("does the agent pick the right tool?") and **data precision** ("are the arguments correct, usually extracted from conversation history?"), plus instruction-following when the system prompt conflicts with user input.
- Anthropic's caution: "often better to grade what the agent produced, not the path it took" — rigid step-order checks are brittle. Check the **outcome** ("the final state in the environment", e.g. the row that exists in the store after the turn), and use tool-call checks as supplements. Partial credit for multi-step tasks.
- A concrete code-graded checklist (my synthesis):
  - correct tool name; **no hallucinated tool** (name must be in the declared set);
  - arguments validate against the tool's JSON schema (with OpenAI strict mode this is enforced server-side on Responses; "Chat Completions requests remain non-strict by default");
  - argument values correct within tolerance (dates, units, quantities);
  - **negative cases**: no tool call when the user only asks a question; a clarifying question when a required argument is missing; no duplicate call after a tool result;
  - multi-tool turns: set equality on calls rather than order, unless order matters;
  - final state of the data store after applying the calls.
- promptfoo ships `is-valid-openai-tools-call` ("Ensure all tool calls match the tools JSON schema") and `tool-call-f1` ("Tool names meet the F1 threshold").

### D.9 Meal-photo nutrition estimation: public ground truth

**Nutrition5k** ([repo](https://github.com/google-research-datasets/Nutrition5k), [paper abstract](https://arxiv.org/abs/2103.03375), Thames et al., CVPR 2021)
- **Contents:** scans of **5,006 plates** of food from Google cafeterias in California; per dish: total calories, mass, fat, carb, protein, ingredient count, and a per-ingredient list (grams, calories, macros, USDA-based). Imagery: overhead RGB-D images ("when available") and side-angle video from four cameras.
- **Licence:** Creative Commons Attribution 4.0 (CC BY 4.0) — usable as eval ground truth with attribution.
- **Size:** full archive **181.4 GB**; individual files can be pulled with `gsutil -m cp -r "gs://nutrition5k_dataset/nutrition5k_dataset/{PATH}" .`, so a few hundred overhead RGB images plus the metadata CSVs are a small download. Official train/test dish-ID splits are in `dish_ids/splits/`.
- **Official scoring** ([`scripts/compute_eval_statistics.py`](https://github.com/google-research-datasets/Nutrition5k/blob/main/scripts/compute_eval_statistics.py), read directly): for each of calories, mass, fat, carb, protein it reports **MAE** = mean absolute error, and **MAE %** = 100 × mean(abs error) / mean(ground-truth value) — i.e. error normalised by the dataset mean, *not* the mean of per-dish percentage errors. Papers that report "MAPE" usually mean the per-dish version, which is larger and unstable for small dishes; state which one is used.
- **Caveats for app relevance:** cafeteria tray photos under fixed overhead lighting, many small/partial plates; the authors' claim is that a trained model "outperforms professional nutritionists". A study of 40 vision-language models reportedly found standardised laboratory photography (Nutrition5k) gave the *poorest* results across models ([Scientific Reports 2026](https://www.nature.com/articles/s41598-026-58755-w) — paywalled/redirected, seen only as a search snippet: **UNCONFIRMED**). So also keep a small set of your own real phone photos with weighed ground truth.

**Published error rates for general-purpose vision LLMs**

Confirmed by reading the paper ([Mu, Sun, He — "Benchmarking and Improving Foundation Model Dietary Estimates from Meal Images", ACM BCB 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC13401436/)); 505 Nutrition5k test images, per-dish MAPE %, image only, no weight given:

| Model | Calories | Fat | Carbs | Protein |
|---|---|---|---|---|
| GPT-4.1 | 34.6 | 51.2 | 33.0 | 39.3 |
| GPT-4.1 mini | 32.7 | 52.0 | 36.7 | 41.5 |
| GPT-4.1 nano | 43.9 | 56.8 | 83.9 | 54.5 |
| Gemini 2.5 Flash | 42.9 | 58.4 | 60.3 | 43.5 |
| Llama 4 Maverick | 46.7 | 61.3 | 72.4 | 51.0 |
| Specialised RGB-D model trained on Nutrition5k | 16.8 | | | |

- On 78 real phone photos the same paper found the LLMs at ~40–42% calorie MAPE while the specialised RGB-D model degraded to 52.6% — general models transfer better to phone photos. Supplying the true weight cut calorie MAPE to 17–26%, which is the quantitative case for letting users confirm or correct portion size.
- From search-result snippets only, not opened (**UNCONFIRMED**): a three-model study (ChatGPT-4o, Claude 3.5 Sonnet, Gemini 1.5 Pro) reporting ~36–37% MAPE for weight and ~36% for energy for the first two ([PubMed 41081011](https://pubmed.ncbi.nlm.nih.gov/41081011/)); a 2026 bioRxiv ten-model benchmark on 3,229 images with best calorie MAE 80.7 kcal ([bioRxiv](https://www.biorxiv.org/content/10.64898/2026.07.26.740845v1.full)); the Scientific Reports paper above reporting calorie MAEs around 37–46 kcal for GPT-5-chat / GPT-4o / Gemini 2.5 Flash on its own subset. No confirmed number was found for any current Claude model, nor for any 2026-generation model (GPT-6.x, Claude 5.x) — that gap is exactly what an in-repo eval would measure.
- **Takeaway:** roughly **30–45% per-dish calorie error from a single photo is the published norm** for general vision LLMs; fat is consistently the worst macro. A model-selection eval should therefore report calorie MAPE with a CI and treat single-digit-point differences between candidates as noise unless the paired CI excludes zero.

---

## B. iOS testing standard practice (late 2026)

Sources: Apple [Testing (Xcode)](https://developer.apple.com/documentation/xcode/testing) · [Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project) · [Migrating a test from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest) · [Implementing parameterized tests](https://developer.apple.com/documentation/testing/parameterizedtesting) · [Organizing tests into test plans](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback) · [Determining how much code your tests cover](https://developer.apple.com/documentation/xcode/determining-how-much-code-your-tests-cover) · [ModelConfiguration initializer](https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:isstoredinmemoryonly:allowssave:groupcontainer:cloudkitdatabase:)) · [SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan) · [performAccessibilityAudit(for:_:)](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:)) · [Performing accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app) · [XCUIApplication.launchArguments](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launcharguments) · [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) · [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)

(Apple's documentation pages are JavaScript-rendered; they were read through Apple's public documentation JSON endpoint for the same paths.)

### B.1 The test pyramid, in Apple's own words

- "Aim for a 'pyramid' distribution of tests ... a large number of fast, well-isolated unit tests to cover your app's logic, a smaller number of integration tests to demonstrate that smaller parts connect together properly, and UI tests to assert the correct behavior of common use cases."
- "UI tests are the ultimate indicator your app works the way you expect, but they take longer to run than other kinds of tests. There are various app variables that can introduce a failure in the same UI test."
- Integration tests: "use integration tests to assert that components work together to achieve app goals in important situations. Examples include testing that a value received from a controller is stored in the model correctly, and that an error produced by a network request gets passed to and presented by the user interface."
- UI tests: "Design UI tests to replicate the most critical workflows that would affect users if they broke, and to replay reported bugs to avoid regressions."
- "In addition to the test pyramid, write performance tests to provide regression coverage of performance-critical regions of code."

### B.2 Swift Testing vs XCTest

- **They coexist in one target:** "Swift Testing and XCTest can build from the same test target and coexist inside the same test bundle ... you don't need to add a new Unit Testing Bundle ... You can add additional files to the target using Swift Testing and consider converting your old tests as time allows." Even one file can mix them: "A single source file can contain tests written with XCTest as well as other tests written with the testing library."
- **Division of labour per Apple:** Swift Testing — "Use it for your unit tests and integration tests that call your code directly." XCTest remains for UI tests ("Xcode continues to include XCTest to facilitate writing UI tests that control your app's UI using XCUIAutomation") and performance tests.
- **Parameterized tests:** `@Test("...", arguments: Food.allCases) func foodAvailable(_ food: Food)`; each argument is a separately reported test case, and "By default, the test cases of a test function run in parallel with each other." Ranges and zipped collections are supported. This is the direct replacement for table-driven `for` loops inside one XCTest method, where "it may be unclear which value failed".
- **Behavioural differences to plan for when migrating:** "By default, the testing library runs all tests in a suite in parallel. The default behavior of XCTest is to run each test in a suite sequentially. If your tests use shared state such as global variables, you may see unexpected behavior" — use the `.serialized` trait for suites touching shared state (singletons, UserDefaults, a shared container). Setup/teardown become `init`/`deinit`; `XCTestExpectation` becomes `await` or `confirmation`; `XCTExpectFailure` becomes `withKnownIssue`.
- **Practical stance for an existing 440-test XCTest suite:** no rewrite. Write new tests in Swift Testing, convert a file only when it is being touched or when it is a table-driven test that benefits from `arguments:`.

### B.3 SwiftData tests with an in-memory container

- API (confirmed signature): `ModelConfiguration(_ name: String? = nil, schema: Schema? = nil, isStoredInMemoryOnly: Bool = false, allowsSave: Bool = true, groupContainer: .automatic, cloudKitDatabase: .automatic)`; `isStoredInMemoryOnly` — "determines whether the associated persistent storage is ephemeral and exists only in memory."
- For tests in a CloudKit-enabled app, pass `cloudKitDatabase: .none` ("Disables managed CloudKit sync") as well, so the test container neither needs entitlements nor applies CloudKit's schema constraints unexpectedly. Conversely, keep at least one test that builds the container with the **production** configuration's schema, because CloudKit-mirrored models have extra rules (optional or defaulted attributes, optional relationships, no unique constraints) that an in-memory non-CloudKit container will not enforce — the rules themselves are from Apple's CloudKit-sync documentation, not re-fetched here (**UNCONFIRMED** in this pass).
- Standard shape: one fresh `ModelContainer` per test (a factory helper), never a shared global; insert -> operate -> fetch -> assert. With Swift Testing's default parallelism, per-test containers are what make this safe.
- This layer is where idempotent upsert/merge functions get their second line of defence: pure-function unit tests prove the merge logic, in-memory container tests prove that running the same ingest twice leaves one row.

### B.4 XCUITest end-to-end flows and launch-argument seeding

- `XCUIApplication.launchArguments` — "The arguments that pass to the application on launch"; set before `launch()`. The standard pattern is a small set of test-only launch arguments/environment variables that (a) select an in-memory or freshly seeded store, (b) disable animations, (c) stub the network layer, and (d) jump to a screen. An app that already supports seed/demo launch arguments has most of this in place.
- Keep the count small — the critical flows only (first launch/onboarding, log a meal by text, log weight and see it reflected, open the coach and see a canned reply, settings round-trip). Stub the LLM with recorded responses; UI tests must not depend on a live model or a key.
- Prefer accessibility identifiers over label text for queries; wait with `waitForExistence(timeout:)` rather than sleeps.
- In xcodegen the UI test target is type `bundle.ui-testing`; test plans are referenced from the scheme via `testPlans:` (with `defaultPlan`), and `gatherCoverageData` / `coverageTargets` / `randomExecutionOrder` are scheme-level options. (XcodeGen ProjectSpec)

### B.5 Snapshot testing — pros and cons

- Tool of record: pointfreeco/swift-snapshot-testing (1.19.7, Oct 2026): `assertSnapshot(of:as:)` with strategies `.image`, `.recursiveDescription`, `.dump`, `.json`, `.plist`; works under both XCTest and Swift Testing (`@Suite(.snapshots(record: .failed))`). First run records and fails; later runs compare.
- **Pro:** catches unintended visual/layout regressions across many screens/themes/Dynamic Type sizes cheaply; text strategies (`.dump`, `.json`) are a robust way to pin structured output such as prompt payloads or encoded requests.
- **Con (from the README):** "Snapshots must be compared using the exact same simulator that originally took the reference to avoid discrepancies between images." In practice image baselines break on every Xcode/iOS runtime bump and differ between a local Mac and the CI runner, so they need a pinned simulator + runtime and a re-record ritual. That maintenance cost is the usual reason solo developers keep image snapshots to a few high-value screens or skip them.
- Recommendation for a one-person app: use **text** snapshots freely (request bodies, prompt assembly, JSON encodings); add **image** snapshots only for a handful of stable, design-critical screens, and only once CI pins the simulator runtime.

### B.6 Xcode test plans

- "A test plan is a document in your Xcode project that describes which tests Xcode should run ... and the configurations Xcode uses to run the tests." Multiple plans per scheme; select with `xcodebuild -testPlan`.
- Per-configuration settings include launch arguments, environment variables, application language and region, random execution order ("can uncover situations where your test's behavior depends on actions taken in other tests"), repetition mode (until failure / retry on failure / fixed count), code coverage, Address Sanitizer and Thread Sanitizer.
- Useful minimal set: a fast **Unit** plan (unit + integration, random order, coverage on) for every push; a **Full** plan adding UI tests; optionally a second configuration of the unit plan in a different region/time zone/language to flush out locale and date bugs. Tags (Swift Testing) can include/exclude tests per plan.

### B.7 Code coverage

- Enable in the test plan or with `xcodebuild -enableCodeCoverage YES`; read it with `xcrun xccov view --report [--json] X.xcresult` (verified locally on Xcode 26.4) or from the Report navigator.
- Apple's caution: "Although achieving a high level of coverage is an excellent goal, code coverage alone doesn't ensure that your tests are doing their job ... pair high code coverage with well-written tests."
- **Thresholds:** Apple publishes none. The commonly cited industry reference is Google's guideline (60% acceptable / 75% commendable / 90% exemplary, with the advice to focus on coverage of changed code rather than a global number) — the Google Testing Blog post could not be fetched in this pass, so those numbers are **UNCONFIRMED** here.
- Practical guidance for SwiftUI apps (practitioner consensus, not a vendor rule): a whole-app percentage is dominated by declarative view code that unit tests never execute, so measure **logic targets/folders** (services, merge functions, parsers, view models) and aim high there (80%+), while treating whole-app coverage as a trend line rather than a gate. Gate CI on "coverage of logic folders did not drop", not on an absolute app-wide figure.
- Measured data point from an existing result bundle in the session scratchpad (Xcode 26.4, 443 tests, all passing): app target line coverage **18.20% (8,660 / 47,583 lines)**, widget extension 4.11%. This is a real measurement of the current state and illustrates the point above — a large, passing unit suite still yields a low whole-app number when views are in the denominator.

### B.8 Testing migrations

- SwiftData's mechanism: `VersionedSchema` ("describing a specific version of a schema, including the models it contains"), `SchemaMigrationPlan` ("describing the evolution of a schema and how to migrate between specific versions"), `MigrationStage` (lightweight or custom).
- Apple documents the API but publishes no migration-testing recipe; the established practitioner pattern (**UNCONFIRMED** against a primary source) is:
  1. In a temp directory, create an **on-disk** store using the *old* `VersionedSchema` and insert representative rows (including edge cases: nil optionals, duplicates the new schema would forbid).
  2. Close it; reopen the same URL with the *current* schema and the real `SchemaMigrationPlan`.
  3. Assert the container opens, row counts match, and transformed fields have the expected values.
  4. Keep a frozen copy of each shipped schema version in the test target (or a checked-in fixture `.store` file produced by the shipped build) so the test keeps exercising the real historical layout.
- In-memory stores cannot test migration (nothing persists between open and reopen). With CloudKit mirroring, remember that schema changes must stay additive/lightweight for the cloud schema regardless of what the local migration plan can express.
- For an app with real users' data on device, this is high-value even with only one test per shipped schema version: a failed migration is the one bug class that destroys data.

### B.9 Time- and date-dependent code

- The standard is dependency injection of "now" and of the calendar/time zone/locale, never calling `Date()` / `Calendar.current` / `TimeZone.current` inside logic. Minimal form: pass `now: Date` and `calendar: Calendar` parameters (or a `() -> Date` closure) into pure functions. For code that *waits* (debounce, retry backoff, timers), inject a `Clock` — the standard-library protocol "to measure time, and delay work until a given point in time" (concrete `ContinuousClock`, `SuspendingClock`) — and substitute a controllable test clock.
- Then parameterize: the same assertions over several time zones (UTC, a negative-offset zone, a +13/+14 zone), over DST transition days, over midnight boundaries, week-start conventions, and year boundaries. Swift Testing's `arguments:` makes this one test function.
- Streaks, "today's" totals, "night ending today" sleep attribution and day-keyed caches are the classic places these bugs live; test-plan configurations with a different Application Region add a cheap second net.
- (The injection pattern is long-standing community practice — e.g. Point-Free's swift-clocks/Dependencies libraries — rather than something an Apple page prescribes; the `Clock` protocol itself is Apple/Swift API.)

### B.10 Accessibility audits

- API (confirmed signature): `func performAccessibilityAudit(for auditTypes: XCUIAccessibilityAuditType = .all, _ issueHandler: ((XCUIAccessibilityAuditIssue) throws -> Bool)? = nil) throws` on `XCUIApplication`. Called inside a UI test once the screen under test is showing; it throws (fails the test) on issues unless the handler returns `true` to ignore a specific one. Introduced with Xcode 15 / iOS 17 (from background knowledge — the version is not on the page fetched).
- Audit categories (from Apple's Accessibility Inspector documentation, which exposes the same audits): element description (missing labels), hit region (too-small targets), contrast, clipped text at larger Dynamic Type sizes, traits, Dynamic Type support.
- Standard use: one audit call per major screen inside the existing smoke-flow UI tests; start with an `issueHandler` that filters known false positives (decorative images, third-party views) rather than disabling audit types wholesale.

### B.11 Recommended layers for a one-person app, in priority order

1. **Pure-logic unit tests** (already present at ~440). Keep; write new ones in Swift Testing with `arguments:`. Highest value per minute.
2. **LLM wire-format replay tests**: recorded provider responses (tool calls, malformed JSON, refusals, truncation, HTTP errors) through the real client/decoder/tool-dispatch code via an injected transport. No network, no key. This is the unit-test half of section D.6 and protects the riskiest surface in a multi-provider app.
3. **SwiftData integration tests** on an in-memory, CloudKit-disabled container: every ingest path run twice (idempotency), plus one test that builds the production schema.
4. **Injected time/calendar/time-zone tests** for every day-boundary computation, parameterized across zones and DST.
5. **CI** running 1–4 on every push with result-count and coverage summary (section C). A suite that is not run automatically decays.
6. **Migration tests** — add the moment a second `VersionedSchema` exists; one test per shipped version.
7. **3–5 XCUITest smoke flows** using launch-argument seeding and a stubbed LLM, each ending with `performAccessibilityAudit()`. Run on main/nightly rather than every push if they are slow.
8. **Coverage as a trend** on logic folders; no hard global gate.
9. **Text snapshots** for prompt/request assembly; **image snapshots** last and sparingly.
10. **Live model evals** (section D) on demand and whenever a prompt or default model changes — separate from the test suite, never in the PR path.

