/**
 * Which models the gateway will pay for, and what a call costs. A model not listed here is
 * refused, so nobody can run an expensive model on the owner's bill.
 *
 * Exactly the models the app sends: the tier defaults in `AIProvider`
 * (Sprout/Services/AI/AIConfig.swift) and the measured per-task defaults in
 * `AIConfig.measuredDefaults` (AITask.swift, with the docs/EVAL_REPORT.md section that chose
 * each). `AIGatewayTests` fails when the app resolves a model that is missing here, so change
 * them together.
 *
 * Prices are list prices in US dollars per million tokens, as in Evals/prices.json (verified
 * 2026-11-22 against each vendor's pricing page). Anthropic: cache reads 0.1x and five-minute
 * cache writes 1.25x the input price, as on Anthropic's pricing page on 2026-11-24. Sonnet 5's
 * $2/$10 launch price became its standard price (the planned rise to $3/$15 on 2026-09-01 was
 * cancelled). OpenAI: cached input 0.1x the input price.
 */

export type Upstream = "anthropic" | "openai"

export interface TokenPrice {
  input: number
  output: number
  cacheRead: number
  cacheWrite: number
}

export const ANTHROPIC_MODELS: Record<string, TokenPrice> = {
  // Meal photos, food suggestions, the recap, the daily brief, the insight line, the memory fold.
  "claude-sonnet-5": { input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5 },
  // The checklist and a typed meal (EVAL_REPORT 39).
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 },
  // Vita's chat, the chat chips, the weekly note, the onboarding note (EVAL_REPORT 35-38).
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125 },
  // The cheap tier's default; no task resolves to it now, kept as the tier default in the app.
  "claude-haiku-4-5-20251001": { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 },
  "claude-haiku-4-5": { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 },
  // The rare plan build and review.
  "claude-opus-4-8": { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
  // The plan's web research (EVAL_REPORT 39).
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
}

/**
 * OpenAI text models, on `/v1/responses` (gpt-5.6 and later, which is all of these; see
 * `OpenAIModelProfile` in Sprout/Services/AI/OpenAIClient.swift) or `/v1/chat/completions`.
 *
 * `cacheWrite` is OpenAI's 30-minute cache write for the 5.6 and 6.x families (1.25x input,
 * Evals/prices.json). The usage block reports only `cached_tokens` (reads); no field for the
 * tokens written is known. So every uncached input token is charged at the higher of the input
 * and cache-write prices: for a spending cap, counting up to 0.25x input too much on those
 * tokens is the safe direction, and counting too little is not.
 */
export const OPENAI_MODELS: Record<string, TokenPrice> = {
  "gpt-6-luna": { input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125 },
  "gpt-6.2-sol": { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 },
  // The plan's web research (`OpenAIClient.researchModel`).
  // PROMOTIONAL: Evals/prices.json says "promotional price until 2026-11-30; later price not
  // published". RE-CHECK https://developers.openai.com/api/docs/pricing after 2026-11-30 and
  // update this line (and prices.json) to the price then in force.
  "gpt-5.6-sol": { input: 4, output: 20, cacheRead: 0.4, cacheWrite: 5 },
}

/**
 * The custom character: one image per call. Measured at $0.035 for this model at `low`
 * (docs/EVAL_REPORT.md section 27); charged a little above that so the cap is conservative.
 */
export const OPENAI_IMAGE = { model: "gpt-image-2.6-sunburst", quality: "low", usdPerCall: 0.04 }

/** The largest output the app asks for is 2,200 tokens; anything far above it is refused. */
export const MAX_OUTPUT_TOKENS = 8192

/**
 * Anthropic's web search, the one server tool allowed (the plan build grounds itself with up
 * to 5 searches): $10 per 1,000 searches, reported as `usage.server_tool_use.web_search_requests`.
 */
export const ANTHROPIC_WEB_SEARCH = { type: "web_search_20250305", maxUses: 5, usdPerSearch: 0.01 }

/**
 * OpenAI's web search on the Responses API (the plan's research call): `{ "type": "web_search" }`,
 * charged per completed `web_search_call` item in the response's `output`, at the same $10 per
 * 1,000 calls as Anthropic's. The price is from docs/audits/2026-11-22/research-standards.md
 * (OpenAI's pricing page: "$10.00 / 1k calls + search content tokens billed at the model's
 * rates"; the content tokens arrive in `usage.input_tokens`); not re-checked live. If the
 * request sets `max_tool_calls`, it must be at most `maxCalls`.
 */
export const OPENAI_WEB_SEARCH = { type: "web_search", maxCalls: 5, usdPerCall: 0.01 }

const perMillion = (tokens: number, usd: number) => (Math.max(0, tokens) * usd) / 1_000_000

/** Cost of an Anthropic Messages response, from its `usage` block. */
export function anthropicCost(model: string, usage: unknown): number {
  const price = ANTHROPIC_MODELS[model]
  if (!price || !usage || typeof usage !== "object") return 0
  const u = usage as Record<string, unknown>
  const n = (k: string) => (typeof u[k] === "number" ? (u[k] as number) : 0)
  const serverTools = u.server_tool_use as Record<string, unknown> | undefined
  const searches = typeof serverTools?.web_search_requests === "number" ? serverTools.web_search_requests : 0
  // `input_tokens` excludes the cached part, which is reported beside it.
  return (
    searches * ANTHROPIC_WEB_SEARCH.usdPerSearch +
    perMillion(n("input_tokens"), price.input) +
    perMillion(n("cache_read_input_tokens"), price.cacheRead) +
    perMillion(n("cache_creation_input_tokens"), price.cacheWrite) +
    perMillion(n("output_tokens"), price.output)
  )
}

/** Completed web searches in a Responses API reply (failed or unfinished ones are not billed). */
export function openaiWebSearches(output: unknown): number {
  if (!Array.isArray(output)) return 0
  return output.filter(
    (item) => item && typeof item === "object" && (item as Record<string, unknown>).type === "web_search_call" && (item as Record<string, unknown>).status === "completed",
  ).length
}

/** Cost of an OpenAI Responses or Chat Completions reply, from its `usage` (and `output`). */
export function openaiCost(model: string, response: unknown): number {
  const price = OPENAI_MODELS[model]
  if (!price || !response || typeof response !== "object") return 0
  const r = response as Record<string, unknown>
  const searches = openaiWebSearches(r.output) * OPENAI_WEB_SEARCH.usdPerCall
  const usage = r.usage
  if (!usage || typeof usage !== "object") return searches
  const u = usage as Record<string, unknown>
  const num = (v: unknown) => (typeof v === "number" ? v : 0)
  // Chat Completions: prompt_tokens / completion_tokens; Responses: input_tokens / output_tokens.
  // Both include the cached part in the input count, reported in a details block; the output
  // count includes reasoning tokens.
  const input = num(u.prompt_tokens ?? u.input_tokens)
  const output = num(u.completion_tokens ?? u.output_tokens)
  const details = (u.prompt_tokens_details ?? u.input_tokens_details) as Record<string, unknown> | undefined
  const cached = Math.min(input, num(details?.cached_tokens))
  // Any uncached token may have been written to the 30-minute cache (see OPENAI_MODELS).
  const fresh = Math.max(price.input, price.cacheWrite)
  return searches + perMillion(input - cached, fresh) + perMillion(cached, price.cacheRead) + perMillion(output, price.output)
}
