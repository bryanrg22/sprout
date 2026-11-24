/**
 * Which models the gateway will pay for, and what a call costs. A model not listed here is
 * refused, so nobody can run an expensive model on the owner's bill.
 *
 * Prices are list prices in US dollars per million tokens (Anthropic: cache reads 0.1× and
 * five-minute cache writes 1.25× the input price; OpenAI: cached input as listed). They match
 * the app's own defaults (`AIProvider` in Victoria/Services/AI/AIConfig.swift and
 * docs/MODEL_CHOICES.md). Change them together.
 */

export type Upstream = "anthropic" | "openai"

export interface TokenPrice {
  input: number
  output: number
  cacheRead: number
  cacheWrite: number
}

export const ANTHROPIC_MODELS: Record<string, TokenPrice> = {
  // Coach, meal photos, checklist (the strong tier).
  "claude-sonnet-5": { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
  // Daily brief, insights, reflections (the cheap tier).
  "claude-haiku-4-5-20251001": { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 },
  "claude-haiku-4-5": { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 },
  // The rare plan build.
  "claude-opus-4-8": { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
}

export const OPENAI_MODELS: Record<string, TokenPrice> = {
  "gpt-5.6-terra": { input: 2.5, output: 15, cacheRead: 0.25, cacheWrite: 0 },
  "gpt-5.6-sol": { input: 5, output: 30, cacheRead: 0.5, cacheWrite: 0 },
  "gpt-4.1-mini": { input: 0.4, output: 1.6, cacheRead: 0.1, cacheWrite: 0 },
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

/** Cost of an OpenAI Chat Completions or Responses response, from its `usage` block. */
export function openaiCost(model: string, usage: unknown): number {
  const price = OPENAI_MODELS[model]
  if (!price || !usage || typeof usage !== "object") return 0
  const u = usage as Record<string, unknown>
  const num = (v: unknown) => (typeof v === "number" ? v : 0)
  // Chat Completions: prompt_tokens / completion_tokens; Responses: input_tokens / output_tokens.
  // Both include the cached part in the input count, reported in a details block.
  const input = num(u.prompt_tokens ?? u.input_tokens)
  const output = num(u.completion_tokens ?? u.output_tokens)
  const details = (u.prompt_tokens_details ?? u.input_tokens_details) as Record<string, unknown> | undefined
  const cached = Math.min(input, num(details?.cached_tokens))
  return perMillion(input - cached, price.input) + perMillion(cached, price.cacheRead) + perMillion(output, price.output)
}
