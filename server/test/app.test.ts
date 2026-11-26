import { afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest"
import { createApp, utcDay } from "../src/app.js"
import type { Config } from "../src/config.js"
import { Store } from "../src/store.js"
import { APP_ID, makeAssertion, makeAttestation, makeCA, makeDevice, sha, type TestCA } from "./fakeAttest.js"

const NOW = Date.parse("2026-11-24T12:00:00Z")
const SERVER_ANTHROPIC_KEY = "sk-ant-server-test"
const SERVER_OPENAI_KEY = "sk-openai-server-test"

let ca: TestCA
let device: Awaited<ReturnType<typeof makeDevice>>

beforeAll(async () => {
  ca = await makeCA()
  device = await makeDevice()
})

interface Sent {
  url: string
  headers: Record<string, string>
  body: Uint8Array
}

let store: Store
let sent: Sent[]
let upstreamReply: () => Response
let now: number
let config: Config
let logs: Record<string, unknown>[]

function app(overrides: Partial<Config> = {}) {
  config = {
    port: 0,
    host: "127.0.0.1",
    appIds: [APP_ID],
    allowDevelopment: true,
    anthropicKey: SERVER_ANTHROPIC_KEY,
    openaiKey: SERVER_OPENAI_KEY,
    deviceDailyCapUsd: 1,
    totalDailyCapUsd: 20,
    dbPath: ":memory:",
    maxBodyBytes: 1024 * 1024,
    ...overrides,
  }
  return createApp({
    config,
    store,
    now: () => now,
    rootPem: ca.rootPem,
    log: (line) => logs.push(line),
    fetch: (async (url: string | URL | Request, init?: RequestInit) => {
      const headers = Object.fromEntries(Object.entries((init?.headers ?? {}) as Record<string, string>).map(([k, v]) => [k.toLowerCase(), v]))
      sent.push({ url: String(url), headers, body: init?.body as Uint8Array })
      return upstreamReply()
    }) as typeof fetch,
  })
}

const anthropicOk = (usage: Record<string, unknown> = { input_tokens: 1000, output_tokens: 500 }) =>
  new Response(JSON.stringify({ id: "msg_1", model: "claude-sonnet-5", content: [{ type: "text", text: "hi" }], usage }), {
    status: 200,
    headers: { "content-type": "application/json" },
  })

beforeEach(() => {
  store = new Store(":memory:")
  sent = []
  logs = []
  now = NOW
  upstreamReply = () => anthropicOk()
})
afterEach(() => store.close())

async function register(a = app()) {
  const { challenge } = (await (await a.request("/v1/attest/challenge", { method: "POST" })).json()) as { challenge: string }
  const attestation = await makeAttestation(ca, device, sha(Buffer.from(challenge, "utf8")))
  const res = await a.request("/v1/attest/register", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ keyId: device.keyIdB64, attestation: attestation.toString("base64"), challenge }),
  })
  return { res, challenge, attestation }
}

let counter = 0
/** A request signed the way the app signs it. */
function signed(path: string, body: Buffer | string, opts: { counter?: number; timestamp?: number; contentType?: string; signBody?: Buffer } = {}) {
  const bytes = Buffer.isBuffer(body) ? body : Buffer.from(body)
  const ts = String(opts.timestamp ?? now)
  const clientData = Buffer.concat([Buffer.from(`POST\n${path}\n${ts}\n`), opts.signBody ?? bytes])
  const assertion = makeAssertion(device, clientData, opts.counter ?? ++counter)
  return {
    method: "POST",
    headers: {
      "content-type": opts.contentType ?? "application/json",
      "x-sprout-key-id": device.keyIdB64,
      "x-sprout-timestamp": ts,
      "x-sprout-assertion": assertion.toString("base64"),
      "anthropic-version": "2023-06-01",
      "x-api-key": "sk-ant-should-never-be-forwarded",
    },
    body: new Uint8Array(bytes),
  }
}

const message = (extra: Record<string, unknown> = {}) =>
  JSON.stringify({ model: "claude-sonnet-5", max_tokens: 700, messages: [{ role: "user", content: "hi" }], ...extra })

async function errorType(res: Response): Promise<string> {
  const json = (await res.json()) as { error?: { type?: string } }
  return json.error?.type ?? "none"
}

describe("health", () => {
  it("says which providers are on", async () => {
    expect(await (await app().request("/health")).json()).toEqual({ ok: true, anthropic: true, openai: true })
    expect(await (await app({ openaiKey: undefined }).request("/health")).json()).toEqual({ ok: true, anthropic: true, openai: false })
  })
})

describe("registration", () => {
  it("registers a device from a genuine attestation of our challenge", async () => {
    const { res } = await register()
    expect(res.status).toBe(201)
    expect(store.device(device.keyIdB64)?.environment).toBe("production")
  })

  it("refuses a challenge used twice", async () => {
    const a = app()
    const { challenge, attestation } = await register(a)
    const again = await a.request("/v1/attest/register", {
      method: "POST",
      body: JSON.stringify({ keyId: device.keyIdB64, attestation: attestation.toString("base64"), challenge }),
    })
    expect(again.status).toBe(401)
    expect(await errorType(again)).toBe("challenge_invalid")
  })

  it("refuses an attestation of a different challenge", async () => {
    const a = app()
    const { challenge } = (await (await a.request("/v1/attest/challenge", { method: "POST" })).json()) as { challenge: string }
    const attestation = await makeAttestation(ca, device, sha(Buffer.from("some other challenge")))
    const res = await a.request("/v1/attest/register", {
      method: "POST",
      body: JSON.stringify({ keyId: device.keyIdB64, attestation: attestation.toString("base64"), challenge }),
    })
    expect(res.status).toBe(401)
    expect(await errorType(res)).toBe("attestation_invalid")
    expect(store.device(device.keyIdB64)).toBeUndefined()
  })

  it("refuses a malformed body", async () => {
    const res = await app().request("/v1/attest/register", { method: "POST", body: "{" })
    expect(res.status).toBe(400)
  })

  it("limits registrations per network", async () => {
    const a = app()
    const statuses: number[] = []
    for (let i = 0; i < 31; i++) statuses.push((await a.request("/v1/attest/challenge", { method: "POST", headers: { "x-real-ip": "1.2.3.4" } })).status)
    expect(statuses.slice(0, 30).every((s) => s === 200)).toBe(true)
    expect(statuses[30]).toBe(429)
    expect((await a.request("/v1/attest/challenge", { method: "POST", headers: { "x-real-ip": "5.6.7.8" } })).status).toBe(200)
  })
})

describe("a model call", () => {
  it("is forwarded with the server's key, not the app's headers, and its cost is counted", async () => {
    const a = app()
    await register(a)
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))
    expect(res.status).toBe(200)
    expect(((await res.json()) as { id: string }).id).toBe("msg_1")
    expect(sent).toHaveLength(1)
    expect(sent[0]!.url).toBe("https://api.anthropic.com/v1/messages")
    expect(sent[0]!.headers["x-api-key"]).toBe(SERVER_ANTHROPIC_KEY)
    expect(sent[0]!.headers["anthropic-version"]).toBe("2023-06-01")
    expect(Object.keys(sent[0]!.headers).some((h) => h.startsWith("x-sprout"))).toBe(false)
    expect(Buffer.from(sent[0]!.body).toString()).toBe(message())
    // 1,000 input at $2/M + 500 output at $10/M = $0.007
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.007, 6)
  })

  it("counts cached tokens and web searches at their own prices", async () => {
    const a = app()
    await register(a)
    upstreamReply = () =>
      anthropicOk({
        input_tokens: 100,
        cache_read_input_tokens: 10_000,
        cache_creation_input_tokens: 2_000,
        output_tokens: 300,
        server_tool_use: { web_search_requests: 3 },
      })
    const body = message({ model: "claude-opus-4-8", tools: [{ type: "web_search_20250305", name: "web_search", max_uses: 5 }] })
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", body))
    expect(res.status).toBe(200)
    // Opus 4.8: 100×5 + 10,000×0.5 + 2,000×6.25 + 300×25 (per M) = $0.0255, + 3 searches × $0.01
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.0255 + 0.03, 6)
  })

  it("passes a provider error through and counts nothing", async () => {
    const a = app()
    await register(a)
    upstreamReply = () =>
      new Response(JSON.stringify({ type: "error", error: { type: "overloaded_error", message: "Overloaded" } }), {
        status: 529,
        headers: { "content-type": "application/json", "retry-after": "2" },
      })
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))
    expect(res.status).toBe(529)
    expect(res.headers.get("retry-after")).toBe("2")
    expect(await errorType(res)).toBe("overloaded_error")
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBe(0)
  })
})

describe("who may call", () => {
  it("refuses an unsigned request", async () => {
    const a = app()
    await register(a)
    const res = await a.request("/anthropic/v1/messages", { method: "POST", body: message() })
    expect(res.status).toBe(401)
    expect(await errorType(res)).toBe("unauthenticated")
    expect(sent).toHaveLength(0)
  })

  it("tells an unregistered device to register", async () => {
    const res = await app().request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))
    expect(res.status).toBe(401)
    expect(await errorType(res)).toBe("unknown_device")
  })

  it("refuses a revoked device", async () => {
    const a = app()
    await register(a)
    store.revoke(device.keyIdB64)
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))
    expect(await errorType(res)).toBe("unknown_device")
  })

  it("refuses the same signed request twice (a replay)", async () => {
    const a = app()
    await register(a)
    const req = signed("/anthropic/v1/messages", message())
    expect((await a.request("/anthropic/v1/messages", req)).status).toBe(200)
    const replay = await a.request("/anthropic/v1/messages", req)
    expect(replay.status).toBe(401)
    expect(await errorType(replay)).toBe("assertion_rejected")
    expect(sent).toHaveLength(1)
  })

  it("refuses a body other than the one signed", async () => {
    const a = app()
    await register(a)
    const req = signed("/anthropic/v1/messages", message({ model: "claude-opus-4-8" }), { signBody: Buffer.from(message()) })
    const res = await a.request("/anthropic/v1/messages", req)
    expect(res.status).toBe(401)
    expect(await errorType(res)).toBe("assertion_rejected")
  })

  it("refuses a request signed for another route", async () => {
    const a = app()
    await register(a)
    const req = signed("/openai/v1/images/edits", message())
    const res = await a.request("/anthropic/v1/messages", req)
    expect(await errorType(res)).toBe("assertion_rejected")
  })

  it("refuses a timestamp more than five minutes off", async () => {
    const a = app()
    await register(a)
    const old = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message(), { timestamp: NOW - 5 * 60_000 - 1 }))
    expect(await errorType(old)).toBe("assertion_rejected")
    const edge = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message(), { timestamp: NOW - 5 * 60_000 }))
    expect(edge.status).toBe(200)
  })
})

describe("the daily allowance", () => {
  it("stops a device at its cap until the next UTC day", async () => {
    const a = app({ deviceDailyCapUsd: 0.013 })
    await register(a)
    expect((await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))).status).toBe(200) // $0.007
    expect((await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))).status).toBe(200) // $0.014
    const third = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))
    expect(third.status).toBe(429)
    expect(await errorType(third)).toBe("daily_limit")
    expect(third.headers.get("retry-after")).toBe(String(12 * 3600)) // noon → midnight UTC
    expect(sent).toHaveLength(2)
    now = Date.parse("2026-11-25T00:00:01Z")
    expect((await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))).status).toBe(200)
  })

  it("stops everyone at the total cap", async () => {
    const a = app({ totalDailyCapUsd: 0.5 })
    await register(a)
    store.addSpend(utcDay(NOW), "some-other-device", 0.5)
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))
    expect(res.status).toBe(429)
    expect(await errorType(res)).toBe("service_limit")
  })
})

describe("what may be asked for", () => {
  const refused = async (body: string) => {
    const a = app()
    await register(a)
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", body))
    return { status: res.status, type: await errorType(res) }
  }

  it("the daily brief's model is allowed and priced at its own rate", async () => {
    const a = app()
    await register(a)
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message({ model: "claude-haiku-5-5" })))
    expect(res.status).toBe(200)
    // The stub's usage (1,000 in, 500 out) at $0.10 / $0.50 per million.
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.00035, 8)
  })

  it("only the app's models", async () => {
    expect(await refused(message({ model: "claude-fable-5" }))).toEqual({ status: 400, type: "not_allowed" })
    expect(await refused(JSON.stringify({ max_tokens: 10, messages: [] }))).toEqual({ status: 400, type: "not_allowed" })
  })

  it("a bounded output", async () => {
    expect(await refused(message({ max_tokens: 8193 }))).toEqual({ status: 400, type: "not_allowed" })
    expect(await refused(JSON.stringify({ model: "claude-sonnet-5", messages: [] }))).toEqual({ status: 400, type: "not_allowed" })
  })

  it("no streaming and no unpriced server tools", async () => {
    expect(await refused(message({ stream: true }))).toEqual({ status: 400, type: "not_allowed" })
    expect(await refused(message({ tools: [{ type: "code_execution_20250825", name: "code" }] }))).toEqual({ status: 400, type: "not_allowed" })
    expect(await refused(message({ tools: [{ type: "web_search_20250305", name: "web_search", max_uses: 50 }] }))).toEqual({
      status: 400,
      type: "not_allowed",
    })
  })

  it("the app's own tools are fine", async () => {
    const a = app()
    await register(a)
    const body = message({ tools: [{ name: "log_weight", description: "x", input_schema: { type: "object" } }] })
    expect((await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", body))).status).toBe(200)
  })

  it("not JSON is refused", async () => {
    expect(await refused("not json")).toEqual({ status: 400, type: "bad_request" })
  })

  it("a body over the limit is refused", async () => {
    const a = app({ maxBodyBytes: 100 })
    await register(a)
    const res = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message({ pad: "x".repeat(200) })))
    expect(res.status).toBe(413)
  })
})

describe("OpenAI", () => {
  it("is off without a key", async () => {
    const a = app({ openaiKey: undefined })
    await register(a)
    for (const path of ["/openai/v1/responses", "/openai/v1/chat/completions", "/openai/v1/images/edits"]) {
      const res = await a.request(path, signed(path, "{}"))
      expect(res.status).toBe(503)
      expect(((await res.json()) as { error: { code: string } }).error.code).toBe("provider_disabled")
    }
    expect(sent).toHaveLength(0)
  })

  const responsesOk = (body: Record<string, unknown>) =>
    new Response(JSON.stringify({ id: "resp_1", object: "response", status: "completed", ...body }), {
      status: 200,
      headers: { "content-type": "application/json" },
    })
  /** A Responses body the way `OpenAIClient.responsesBody` builds it, with one function tool. */
  const responsesRequest = (extra: Record<string, unknown> = {}) =>
    JSON.stringify({
      model: "gpt-6.2-sol",
      input: [{ type: "message", role: "user", content: [{ type: "input_text", text: "hi" }] }],
      max_output_tokens: 700,
      prompt_cache_key: "vita-coach",
      prompt_cache_options: { mode: "explicit", ttl: "30m" },
      reasoning: { effort: "low" },
      tools: [{ type: "function", name: "log_weight", description: "x", parameters: { type: "object" } }],
      ...extra,
    })
  const responses = async (body: string, a = app()) => {
    await register(a)
    return a.request("/openai/v1/responses", signed("/openai/v1/responses", body))
  }

  it("forwards a Responses call unchanged with the server's bearer key and prices gpt-6.2-sol", async () => {
    upstreamReply = () =>
      responsesOk({
        model: "gpt-6.2-sol",
        output: [{ type: "message", content: [{ type: "output_text", text: "hi" }] }],
        usage: {
          input_tokens: 3000,
          input_tokens_details: { cached_tokens: 1000 },
          output_tokens: 400,
          output_tokens_details: { reasoning_tokens: 100 },
        },
      })
    const res = await responses(responsesRequest())
    expect(res.status).toBe(200)
    expect(((await res.json()) as { id: string }).id).toBe("resp_1")
    expect(sent).toHaveLength(1)
    expect(sent[0]!.url).toBe("https://api.openai.com/v1/responses")
    expect(sent[0]!.headers.authorization).toBe(`Bearer ${SERVER_OPENAI_KEY}`)
    expect(sent[0]!.headers["x-api-key"]).toBeUndefined()
    expect(Object.keys(sent[0]!.headers).some((h) => h.startsWith("x-sprout") || h.startsWith("anthropic"))).toBe(false)
    expect(Buffer.from(sent[0]!.body).toString()).toBe(responsesRequest())
    // 2,000 uncached × $2.50 (the cache-write rate, the upper bound) + 1,000 cached × $0.10
    // + 400 out (reasoning included) × $10 (per M)
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.0091, 8)
  })

  it("charges each completed web_search_call of the plan's research at $0.01", async () => {
    upstreamReply = () =>
      responsesOk({
        model: "gpt-5.6-sol",
        output: [
          { type: "reasoning", id: "rs_1", summary: [] },
          { type: "web_search_call", id: "ws_1", status: "completed", action: { type: "search", query: "a" } },
          { type: "web_search_call", id: "ws_2", status: "completed", action: { type: "search", query: "b" } },
          { type: "web_search_call", id: "ws_3", status: "failed" },
          { type: "web_search_call", id: "ws_4", status: "completed", action: { type: "open_page" } },
          { type: "message", content: [{ type: "output_text", text: "sources…", annotations: [] }] },
        ],
        usage: { input_tokens: 5000, input_tokens_details: { cached_tokens: 0 }, output_tokens: 1000 },
      })
    // `OpenAIClient.research`'s body.
    const body = JSON.stringify({
      model: "gpt-5.6-sol",
      instructions: "research",
      input: "the person",
      tools: [{ type: "web_search" }],
      max_tool_calls: 5,
      max_output_tokens: 1800,
      reasoning: { effort: "low" },
    })
    const res = await responses(body)
    expect(res.status).toBe(200)
    // 5,000 in × $5 (cache-write rate) + 1,000 out × $20 (per M) = $0.045, + 3 completed searches
    // × $0.01 (the failed one is free)
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.045 + 0.03, 8)
  })

  it("refuses web search without a search limit, so one call cannot run up searches", async () => {
    const body = JSON.stringify({
      model: "gpt-5.6-sol", instructions: "research", input: "the person",
      tools: [{ type: "web_search" }], max_output_tokens: 1800,
    })
    const res = await responses(body)
    expect(res.status).toBe(400)
    expect(await res.text()).toContain("max_tool_calls")
    expect(sent).toHaveLength(0)
  })

  it("prices gpt-6-luna at its own rate", async () => {
    upstreamReply = () => responsesOk({ model: "gpt-6-luna", usage: { input_tokens: 10_000, output_tokens: 2000 } })
    expect((await responses(responsesRequest({ model: "gpt-6-luna" }))).status).toBe(200)
    // 10,000 × $0.125 (cache-write rate) + 2,000 × $0.50 (per M)
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.00225, 8)
  })

  it("forwards Chat Completions for an allowlisted model and prices cached input", async () => {
    const a = app()
    await register(a)
    upstreamReply = () =>
      new Response(
        JSON.stringify({ model: "gpt-6-luna", usage: { prompt_tokens: 2000, prompt_tokens_details: { cached_tokens: 1000 }, completion_tokens: 100 } }),
        { status: 200 },
      )
    // The shape `OpenAIClient.chat` builds for a reasoning model on Chat Completions.
    const body = JSON.stringify({
      model: "gpt-6-luna",
      messages: [{ role: "user", content: "hi" }],
      max_completion_tokens: 300,
      tools: [{ type: "function", function: { name: "log_weight", parameters: { type: "object" } } }],
    })
    const res = await a.request("/openai/v1/chat/completions", signed("/openai/v1/chat/completions", body))
    expect(res.status).toBe(200)
    expect(sent[0]!.url).toBe("https://api.openai.com/v1/chat/completions")
    expect(sent[0]!.headers.authorization).toBe(`Bearer ${SERVER_OPENAI_KEY}`)
    // 1,000 uncached × $0.125 + 1,000 cached × $0.01 + 100 out × $0.50 (per M)
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.000185, 10)
  })

  it("refuses a model that is not allowlisted, on either text route", async () => {
    const a = app()
    await register(a)
    const cases: [string, string][] = [
      ["/openai/v1/responses", responsesRequest({ model: "gpt-4.1-mini" })],
      ["/openai/v1/chat/completions", JSON.stringify({ model: "gpt-4.1-mini", max_tokens: 300, messages: [] })],
      ["/openai/v1/responses", responsesRequest({ model: "gpt-5.6-terra" })],
      ["/openai/v1/responses", responsesRequest({ model: "gpt-6.2-astra" })],
      // An Anthropic model on an OpenAI route, and an OpenAI model on the Anthropic route.
      ["/openai/v1/responses", responsesRequest({ model: "claude-sonnet-5" })],
      ["/anthropic/v1/messages", message({ model: "gpt-6.2-sol" })],
    ]
    for (const [path, body] of cases) {
      const res = await a.request(path, signed(path, body))
      expect(res.status).toBe(400)
      expect(await errorType(res)).toBe("not_allowed")
    }
    expect(sent).toHaveLength(0)
  })

  it("refuses what it cannot price or bound", async () => {
    const a = app()
    await register(a)
    const refusedBodies = [
      responsesRequest({ max_output_tokens: undefined }), // no output cap
      responsesRequest({ max_output_tokens: 8193 }),
      responsesRequest({ stream: true }),
      responsesRequest({ background: true }),
      responsesRequest({ service_tier: "priority" }),
      responsesRequest({ tools: [{ type: "web_search_preview" }] }),
      responsesRequest({ tools: [{ type: "code_interpreter", container: { type: "auto" } }] }),
      responsesRequest({ tools: [{ type: "web_search" }], max_tool_calls: 50 }),
    ]
    for (const body of refusedBodies) {
      const res = await a.request("/openai/v1/responses", signed("/openai/v1/responses", body))
      expect(res.status).toBe(400)
      expect(await errorType(res)).toBe("not_allowed")
    }
    const chatBodies = [
      JSON.stringify({ model: "gpt-6-luna", messages: [] }), // no output cap
      JSON.stringify({ model: "gpt-6-luna", max_completion_tokens: 9000, messages: [] }),
      // Web search is paid for on Responses only.
      JSON.stringify({ model: "gpt-6-luna", max_completion_tokens: 300, messages: [], tools: [{ type: "web_search" }] }),
    ]
    for (const body of chatBodies) {
      const res = await a.request("/openai/v1/chat/completions", signed("/openai/v1/chat/completions", body))
      expect(res.status).toBe(400)
      expect(await errorType(res)).toBe("not_allowed")
    }
    const notJson = await a.request("/openai/v1/responses", signed("/openai/v1/responses", "not json"))
    expect(await errorType(notJson)).toBe("bad_request")
    expect(sent).toHaveLength(0)
    // A bounded web search is fine.
    const ok = await a.request(
      "/openai/v1/responses",
      signed("/openai/v1/responses", responsesRequest({ tools: [{ type: "web_search" }], max_tool_calls: 5 })),
    )
    expect(ok.status).toBe(200)
  })

  it("refuses a body over the limit", async () => {
    const res = await responses(responsesRequest({ pad: "x".repeat(2000) }), app({ maxBodyBytes: 1000 }))
    expect(res.status).toBe(413)
    expect(await errorType(res)).toBe("too_large")
    expect(sent).toHaveLength(0)
  })

  it("stops at the caps with the same error, in OpenAI's error shape", async () => {
    const a = app({ deviceDailyCapUsd: 0.5 })
    await register(a)
    store.addSpend(utcDay(NOW), device.keyIdB64, 0.5)
    const anthropic = await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))
    const anthropicJson = (await anthropic.json()) as { type: string; error: { type: string; message: string } }
    for (const path of ["/openai/v1/responses", "/openai/v1/chat/completions"]) {
      const res = await a.request(path, signed(path, responsesRequest()))
      expect(res.status).toBe(429)
      expect(res.headers.get("retry-after")).toBe(String(12 * 3600))
      // `AIHTTPFailure` and `AIGatewayTransport.errorType` read `error.type` in either shape.
      expect(await res.json()).toEqual({ error: { type: "daily_limit", code: "daily_limit", message: anthropicJson.error.message } })
    }
    expect(anthropicJson.error.type).toBe("daily_limit")

    const b = app({ totalDailyCapUsd: 0.5 })
    store.addSpend(utcDay(NOW), "some-other-device", 0.5)
    const res = await b.request("/openai/v1/responses", signed("/openai/v1/responses", responsesRequest()))
    expect(res.status).toBe(429)
    expect(await errorType(res)).toBe("service_limit")
    expect(sent).toHaveLength(0)
  })

  it("checks the signature: unsigned, signed for the other text route, another body, a replay", async () => {
    const a = app()
    await register(a)
    upstreamReply = () => responsesOk({ usage: { input_tokens: 1, output_tokens: 1 } })
    const unsigned = await a.request("/openai/v1/responses", { method: "POST", body: responsesRequest() })
    expect(await errorType(unsigned)).toBe("unauthenticated")
    const otherRoute = await a.request("/openai/v1/responses", signed("/openai/v1/chat/completions", responsesRequest()))
    expect(await errorType(otherRoute)).toBe("assertion_rejected")
    const swapped = signed("/openai/v1/responses", responsesRequest({ model: "gpt-5.6-sol" }), { signBody: Buffer.from(responsesRequest()) })
    expect(await errorType(await a.request("/openai/v1/responses", swapped))).toBe("assertion_rejected")
    const req = signed("/openai/v1/responses", responsesRequest())
    expect((await a.request("/openai/v1/responses", req)).status).toBe(200)
    expect(await errorType(await a.request("/openai/v1/responses", req))).toBe("assertion_rejected")
    expect(sent).toHaveLength(1)
  })

  it("passes an OpenAI error through and counts nothing", async () => {
    upstreamReply = () =>
      new Response(JSON.stringify({ error: { message: "Slow down", type: "requests", code: "rate_limit_exceeded" } }), {
        status: 429,
        headers: { "content-type": "application/json", "retry-after": "3" },
      })
    const res = await responses(responsesRequest())
    expect(res.status).toBe(429)
    expect(res.headers.get("retry-after")).toBe("3")
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("rate_limit_exceeded")
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBe(0)
  })

  function imageForm(fields: Record<string, string>) {
    const boundary = "sprout-test"
    let text = ""
    for (const [k, v] of Object.entries(fields)) text += `--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`
    const body = Buffer.concat([
      Buffer.from(text + `--${boundary}\r\nContent-Disposition: form-data; name="image"; filename="photo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`),
      Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
      Buffer.from(`\r\n--${boundary}--\r\n`),
    ])
    return { body, contentType: `multipart/form-data; boundary=${boundary}` }
  }

  it("forwards the character image as sent and charges it flat", async () => {
    const a = app()
    await register(a)
    upstreamReply = () => new Response(JSON.stringify({ data: [{ b64_json: "AAAA" }] }), { status: 200 })
    const { body, contentType } = imageForm({ model: "gpt-image-2.6-sunburst", quality: "low", size: "1024x1024" })
    const res = await a.request("/openai/v1/images/edits", signed("/openai/v1/images/edits", body, { contentType }))
    expect(res.status).toBe(200)
    expect(sent[0]!.headers["content-type"]).toBe(contentType)
    expect(Buffer.from(sent[0]!.body).equals(body)).toBe(true)
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.04, 6)
  })

  it("refuses another image model or quality", async () => {
    const a = app()
    await register(a)
    const cases: Record<string, string>[] = [
      { model: "gpt-image-2", quality: "low" },
      { model: "gpt-image-2.6-sunburst", quality: "high" },
      { model: "gpt-image-2.6-sunburst", quality: "low", n: "4" },
    ]
    for (const fields of cases) {
      const { body, contentType } = imageForm(fields)
      const res = await a.request("/openai/v1/images/edits", signed("/openai/v1/images/edits", body, { contentType }))
      expect(res.status).toBe(400)
    }
    expect(sent).toHaveLength(0)
  })
})

describe("logs", () => {
  it("never contain a key or a body", async () => {
    const a = app()
    await register(a)
    await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message({ messages: [{ role: "user", content: "my weight is 172" }] })))
    const text = JSON.stringify(logs)
    expect(text).not.toContain(SERVER_ANTHROPIC_KEY)
    expect(text).not.toContain("172")
    expect(text).not.toContain(device.keyIdB64) // only a short prefix is logged
  })
})
