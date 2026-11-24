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
    // 1,000 input at $3/M + 500 output at $15/M = $0.0105
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.0105, 6)
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
    const req = signed("/openai/v1/chat/completions", message())
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
    const a = app({ deviceDailyCapUsd: 0.02 })
    await register(a)
    expect((await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))).status).toBe(200) // $0.0105
    expect((await a.request("/anthropic/v1/messages", signed("/anthropic/v1/messages", message()))).status).toBe(200) // $0.021
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
    const res = await a.request("/openai/v1/chat/completions", signed("/openai/v1/chat/completions", "{}"))
    expect(res.status).toBe(503)
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("provider_disabled")
  })

  it("forwards chat with the server's bearer key and prices cached input", async () => {
    const a = app()
    await register(a)
    upstreamReply = () =>
      new Response(JSON.stringify({ usage: { prompt_tokens: 2000, prompt_tokens_details: { cached_tokens: 1000 }, completion_tokens: 100 } }), {
        status: 200,
      })
    const body = JSON.stringify({ model: "gpt-4.1-mini", max_tokens: 300, messages: [] })
    const res = await a.request("/openai/v1/chat/completions", signed("/openai/v1/chat/completions", body))
    expect(res.status).toBe(200)
    expect(sent[0]!.url).toBe("https://api.openai.com/v1/chat/completions")
    expect(sent[0]!.headers.authorization).toBe(`Bearer ${SERVER_OPENAI_KEY}`)
    // 1,000 uncached × $0.40 + 1,000 cached × $0.10 + 100 out × $1.60 (per M)
    expect(store.spentToday(utcDay(NOW), device.keyIdB64)).toBeCloseTo(0.00066, 8)
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
