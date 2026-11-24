/**
 * The gateway: the app calls these routes instead of api.anthropic.com / api.openai.com, with
 * no key. Every model call carries an App Attest assertion; the gateway checks it, checks the
 * device's daily allowance and the model allowlist, adds the owner's key and forwards the call
 * unchanged. Bodies are never logged or stored.
 *
 * Signed request (the app's `AIGatewayTransport` builds exactly this):
 *   X-Sprout-Key-Id:    the App Attest key id (base64, as `DCAppAttestService` gives it)
 *   X-Sprout-Timestamp: milliseconds since 1970, within 5 minutes of the server's clock
 *   X-Sprout-Assertion: base64 of `generateAssertion(keyId, SHA-256(clientData))`, where
 *   clientData = UTF-8("POST\n<path>\n<timestamp>\n") followed by the raw body bytes.
 * The body is bound into the signature, so it cannot be swapped; the counter inside the
 * assertion is accepted once (`Store.acceptCounter`), so it cannot be replayed.
 */
import { Hono, type Context } from "hono"
import { AttestError, sha256, verifyAssertion, verifyAttestation } from "./appattest.js"
import type { Config } from "./config.js"
import {
  ANTHROPIC_MODELS,
  ANTHROPIC_WEB_SEARCH,
  MAX_OUTPUT_TOKENS,
  OPENAI_IMAGE,
  anthropicCost,
  type Upstream,
} from "./pricing.js"
import type { Store } from "./store.js"

export interface Deps {
  config: Config
  store: Store
  fetch: typeof fetch
  now: () => number
  /** The App Attest trust anchor; Apple's root unless a test supplies its own. */
  rootPem?: string
  log?: (line: Record<string, unknown>) => void
}

export const CLOCK_SKEW_MS = 5 * 60 * 1000
export const CHALLENGE_TTL_MS = 5 * 60 * 1000
const ANTHROPIC_BASE = "https://api.anthropic.com"
const OPENAI_BASE = "https://api.openai.com"
const DEFAULT_ANTHROPIC_VERSION = "2023-06-01"

export const utcDay = (ms: number) => new Date(ms).toISOString().slice(0, 10)
const secondsToNextUtcDay = (ms: number) => {
  const next = new Date(ms)
  next.setUTCHours(24, 0, 0, 0)
  return Math.max(1, Math.ceil((next.getTime() - ms) / 1000))
}

/** An error in the shape the app already parses for that provider (`AIHTTPFailure`). */
function errorBody(upstream: Upstream | "gateway", type: string, message: string) {
  if (upstream === "openai") return { error: { message, type, code: type } }
  return { type: "error", error: { type, message } }
}

interface Route {
  upstream: Upstream
  /** Path on the provider, e.g. "/v1/messages". */
  path: string
  kind: "json" | "image"
}

const ROUTES: Record<string, Route> = {
  "/anthropic/v1/messages": { upstream: "anthropic", path: "/v1/messages", kind: "json" },
  "/openai/v1/images/edits": { upstream: "openai", path: "/v1/images/edits", kind: "image" },
}

/** A small fixed-window limit per client IP for the unauthenticated attestation routes. */
class IpLimiter {
  private hits = new Map<string, { windowStart: number; count: number }>()
  constructor(private limit: number, private windowMs: number) {}
  allow(ip: string, now: number): boolean {
    const h = this.hits.get(ip)
    if (!h || now - h.windowStart >= this.windowMs) {
      this.hits.set(ip, { windowStart: now, count: 1 })
      if (this.hits.size > 10_000) this.hits.clear()
      return true
    }
    h.count += 1
    return h.count <= this.limit
  }
}

function clientIp(c: Context): string {
  // Caddy sets X-Real-IP to the connecting address (Caddyfile); the app itself is only
  // reachable through it.
  return c.req.header("x-real-ip") ?? "unknown"
}

/** Why a Messages body is refused, or undefined when the gateway will pay for it. */
function refusal(body: Record<string, unknown>): string | undefined {
  const model = body.model
  if (typeof model !== "string") return "The request names no model."
  if (body.stream === true) return "Streaming is not supported through the gateway."
  if (!(model in ANTHROPIC_MODELS)) return `The model ${model} is not available through the gateway.`
  if (typeof body.max_tokens !== "number") return "max_tokens is required."
  if (body.max_tokens > MAX_OUTPUT_TOKENS) return `max_tokens must be at most ${MAX_OUTPUT_TOKENS}.`
  const tools = Array.isArray(body.tools) ? (body.tools as Record<string, unknown>[]) : []
  for (const tool of tools) {
    const type = tool?.type
    // Client tools carry no type (or "custom"); the only server tool paid for is web search.
    if (type === undefined || type === "custom") continue
    if (type === ANTHROPIC_WEB_SEARCH.type && typeof tool.max_uses === "number" && tool.max_uses <= ANTHROPIC_WEB_SEARCH.maxUses) continue
    return `The tool ${String(type)} is not available through the gateway.`
  }
  return undefined
}

async function imageRefusal(bytes: Uint8Array<ArrayBuffer>, contentType: string): Promise<string | undefined> {
  let form: FormData
  try {
    form = await new Request("http://local/", { method: "POST", body: bytes, headers: { "content-type": contentType } }).formData()
  } catch {
    return "The image request is not a multipart form."
  }
  if (form.get("model") !== OPENAI_IMAGE.model) return "That image model is not available through the gateway."
  if (form.get("quality") !== OPENAI_IMAGE.quality) return "That image quality is not available through the gateway."
  const n = form.get("n")
  if (n !== null && n !== "1") return "One image per request."
  return undefined
}

export function createApp(deps: Deps) {
  const { config, store } = deps
  const log = deps.log ?? ((line) => console.log(JSON.stringify(line)))
  const attestLimiter = new IpLimiter(30, 10 * 60 * 1000)
  const app = new Hono()

  app.get("/health", (c) => c.json({ ok: true, anthropic: true, openai: !!config.openaiKey }))

  app.post("/v1/attest/challenge", (c) => {
    const now = deps.now()
    if (!attestLimiter.allow(clientIp(c), now)) {
      return c.json(errorBody("gateway", "rate_limited", "Too many registrations from this network."), 429)
    }
    return c.json({ challenge: store.issueChallenge(now, CHALLENGE_TTL_MS), expiresInSeconds: CHALLENGE_TTL_MS / 1000 })
  })

  app.post("/v1/attest/register", async (c) => {
    const now = deps.now()
    if (!attestLimiter.allow(clientIp(c), now)) {
      return c.json(errorBody("gateway", "rate_limited", "Too many registrations from this network."), 429)
    }
    let input: { keyId?: unknown; attestation?: unknown; challenge?: unknown }
    try {
      input = await c.req.json()
    } catch {
      return c.json(errorBody("gateway", "bad_request", "The body is not JSON."), 400)
    }
    const { keyId, attestation, challenge } = input
    if (typeof keyId !== "string" || typeof attestation !== "string" || typeof challenge !== "string") {
      return c.json(errorBody("gateway", "bad_request", "keyId, attestation and challenge are required."), 400)
    }
    if (!store.consumeChallenge(challenge, now)) {
      return c.json(errorBody("gateway", "challenge_invalid", "The challenge is unknown, used or expired."), 401)
    }
    try {
      const result = verifyAttestation({
        attestation: Buffer.from(attestation, "base64"),
        keyId: Buffer.from(keyId, "base64"),
        clientDataHash: sha256(Buffer.from(challenge, "utf8")),
        appIds: config.appIds,
        allowDevelopment: config.allowDevelopment,
        now: new Date(now),
        rootPem: deps.rootPem,
      })
      store.addDevice({ keyId, publicKeyPem: result.publicKeyPem, appId: result.appId, environment: result.environment }, now)
      log({ event: "registered", key: keyId.slice(0, 8), environment: result.environment })
      return c.json({ ok: true, environment: result.environment }, 201)
    } catch (error) {
      if (error instanceof AttestError) {
        log({ event: "attestation_refused", reason: error.reason })
        return c.json(errorBody("gateway", "attestation_invalid", `${error.reason}: ${error.message}`), 401)
      }
      throw error
    }
  })

  for (const [gatewayPath, route] of Object.entries(ROUTES)) {
    app.post(gatewayPath, async (c) => {
      const now = deps.now()
      const fail = (status: 400 | 401 | 413 | 429 | 502 | 503, type: string, message: string, headers?: Record<string, string>) => {
        log({ event: "refused", route: gatewayPath, status, type })
        return c.json(errorBody(route.upstream, type, message), status, headers)
      }

      if (route.upstream === "openai" && !config.openaiKey) {
        return fail(503, "provider_disabled", "OpenAI is not available through the gateway.")
      }
      const declared = Number(c.req.header("content-length") ?? "0")
      if (declared > config.maxBodyBytes) return fail(413, "too_large", "The request is too large.")
      const body = new Uint8Array(await c.req.arrayBuffer())
      if (body.length > config.maxBodyBytes) return fail(413, "too_large", "The request is too large.")

      // 1. Who is asking: a registered device key, signing this exact request.
      const keyId = c.req.header("x-sprout-key-id")
      const timestamp = c.req.header("x-sprout-timestamp")
      const assertion = c.req.header("x-sprout-assertion")
      if (!keyId || !timestamp || !assertion) return fail(401, "unauthenticated", "The request is not signed.")
      const ts = Number(timestamp)
      if (!Number.isFinite(ts) || Math.abs(now - ts) > CLOCK_SKEW_MS) {
        return fail(401, "assertion_rejected", "The request's timestamp is too far from the server's clock.")
      }
      const device = store.device(keyId)
      if (!device || device.revoked) return fail(401, "unknown_device", "This device is not registered.")
      const clientData = Buffer.concat([Buffer.from(`POST\n${gatewayPath}\n${timestamp}\n`, "utf8"), body])
      let counter: number
      try {
        counter = verifyAssertion({
          assertion: Buffer.from(assertion, "base64"),
          clientData,
          publicKeyPem: device.publicKeyPem,
          appId: device.appId,
        }).counter
      } catch (error) {
        if (error instanceof AttestError) return fail(401, "assertion_rejected", `${error.reason}: ${error.message}`)
        throw error
      }
      if (!store.acceptCounter(keyId, counter, now)) {
        return fail(401, "assertion_rejected", "This request was already used.")
      }

      // 2. The allowance: this device's, then everyone's.
      const day = utcDay(now)
      const retryAfter = String(secondsToNextUtcDay(now))
      if (store.spentToday(day, keyId) >= config.deviceDailyCapUsd) {
        return fail(429, "daily_limit", "You've used today's AI allowance. It resets at midnight UTC.", { "retry-after": retryAfter })
      }
      if (store.totalToday(day) >= config.totalDailyCapUsd) {
        return fail(429, "service_limit", "The AI is resting for today. It's back at midnight UTC.", { "retry-after": retryAfter })
      }

      // 3. What is asked for: an allowed model, a bounded output, no unpriced tools.
      const contentType = c.req.header("content-type") ?? ""
      let model: string
      if (route.kind === "json") {
        let parsed: unknown
        try {
          parsed = JSON.parse(Buffer.from(body).toString("utf8"))
        } catch {
          return fail(400, "bad_request", "The body is not JSON.")
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return fail(400, "bad_request", "The body is not a JSON object.")
        const why = refusal(parsed as Record<string, unknown>)
        if (why) return fail(400, "not_allowed", why)
        model = (parsed as { model: string }).model
      } else {
        const why = await imageRefusal(body, contentType)
        if (why) return fail(400, "not_allowed", why)
        model = OPENAI_IMAGE.model
      }

      // 4. Forward with the owner's key.
      const headers: Record<string, string> = { "content-type": contentType }
      let url: string
      if (route.upstream === "anthropic") {
        url = ANTHROPIC_BASE + route.path
        headers["x-api-key"] = config.anthropicKey
        headers["anthropic-version"] = c.req.header("anthropic-version") ?? DEFAULT_ANTHROPIC_VERSION
      } else {
        url = OPENAI_BASE + route.path
        headers["authorization"] = `Bearer ${config.openaiKey}`
      }
      let upstream: Response
      try {
        upstream = await deps.fetch(url, { method: "POST", headers, body, signal: AbortSignal.timeout(180_000) })
      } catch {
        return fail(502, "upstream_unreachable", "The AI provider could not be reached.")
      }
      const responseBytes = new Uint8Array(await upstream.arrayBuffer())

      // 5. Count what it cost (from the provider's own usage report).
      let usd = 0
      if (upstream.ok) {
        if (route.kind === "image") {
          usd = OPENAI_IMAGE.usdPerCall
        } else {
          try {
            const usage = (JSON.parse(Buffer.from(responseBytes).toString("utf8")) as { usage?: unknown }).usage
            // Priced by the model we allowed; the provider may echo a dated snapshot name.
            usd = anthropicCost(model, usage)
          } catch {
            usd = 0
          }
        }
        store.addSpend(day, keyId, usd)
      }
      log({ event: "forwarded", route: gatewayPath, status: upstream.status, key: keyId.slice(0, 8), model, usd: Number(usd.toFixed(5)) })

      const out: Record<string, string> = { "content-type": upstream.headers.get("content-type") ?? "application/json" }
      const upstreamRetry = upstream.headers.get("retry-after")
      if (upstreamRetry) out["retry-after"] = upstreamRetry
      return new Response(responseBytes, { status: upstream.status, headers: out })
    })
  }

  return app
}
