import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { COUNTER_WINDOW, Store } from "../src/store.js"

let store: Store
const NOW = Date.parse("2026-11-24T12:00:00Z")
const device = { keyId: "key-A", publicKeyPem: "pem", appId: "T.app", environment: "production" as const }

beforeEach(() => {
  store = new Store(":memory:")
  store.addDevice(device, NOW)
})
afterEach(() => store.close())

describe("challenges", () => {
  it("are accepted once", () => {
    const c = store.issueChallenge(NOW, 60_000)
    expect(store.consumeChallenge(c, NOW + 1)).toBe(true)
    expect(store.consumeChallenge(c, NOW + 2)).toBe(false)
  })

  it("expire", () => {
    const c = store.issueChallenge(NOW, 60_000)
    expect(store.consumeChallenge(c, NOW + 60_001)).toBe(false)
  })

  it("must be ones we issued, and are not guessable", () => {
    expect(store.consumeChallenge("made-up", NOW)).toBe(false)
    const a = store.issueChallenge(NOW, 60_000)
    const b = store.issueChallenge(NOW, 60_000)
    expect(a).not.toBe(b)
    expect(Buffer.from(a, "base64url").length).toBe(32)
  })
})

describe("acceptCounter", () => {
  it("accepts increasing counters and each only once", () => {
    expect(store.acceptCounter("key-A", 1, NOW)).toBe(true)
    expect(store.acceptCounter("key-A", 2, NOW)).toBe(true)
    expect(store.acceptCounter("key-A", 2, NOW)).toBe(false)
    expect(store.device("key-A")!.maxCounter).toBe(2)
  })

  it("accepts a counter that arrives late, once, inside the window", () => {
    expect(store.acceptCounter("key-A", 10, NOW)).toBe(true)
    expect(store.acceptCounter("key-A", 8, NOW)).toBe(true) // concurrent request, arrived second
    expect(store.acceptCounter("key-A", 8, NOW)).toBe(false) // its replay
    expect(store.acceptCounter("key-A", 9, NOW)).toBe(true)
    expect(store.device("key-A")!.maxCounter).toBe(10)
  })

  it("refuses a counter older than the window, even one never seen", () => {
    expect(store.acceptCounter("key-A", 100, NOW)).toBe(true)
    expect(store.acceptCounter("key-A", 100 - COUNTER_WINDOW, NOW)).toBe(false)
    expect(store.acceptCounter("key-A", 100 - COUNTER_WINDOW + 1, NOW)).toBe(true)
  })

  it("refuses zero (the attestation's), negatives, fractions and unknown keys", () => {
    expect(store.acceptCounter("key-A", 0, NOW)).toBe(false)
    expect(store.acceptCounter("key-A", -1, NOW)).toBe(false)
    expect(store.acceptCounter("key-A", 1.5, NOW)).toBe(false)
    expect(store.acceptCounter("key-B", 1, NOW)).toBe(false)
  })

  it("starts again for a key registered again", () => {
    expect(store.acceptCounter("key-A", 5, NOW)).toBe(true)
    store.addDevice(device, NOW)
    expect(store.device("key-A")!.maxCounter).toBe(0)
    expect(store.acceptCounter("key-A", 1, NOW)).toBe(true)
  })
})

describe("devices", () => {
  it("are read back as registered and can be revoked", () => {
    expect(store.device("key-A")).toMatchObject({ ...device, maxCounter: 0, revoked: false })
    expect(store.device("nobody")).toBeUndefined()
    store.revoke("key-A")
    expect(store.device("key-A")!.revoked).toBe(true)
  })
})

describe("spend", () => {
  it("adds up per device per day, and in total per day", () => {
    store.addSpend("2026-11-24", "key-A", 0.25)
    store.addSpend("2026-11-24", "key-A", 0.5)
    store.addSpend("2026-11-24", "key-B", 0.1)
    store.addSpend("2026-11-25", "key-A", 0.9)
    expect(store.spentToday("2026-11-24", "key-A")).toBeCloseTo(0.75)
    expect(store.spentToday("2026-11-24", "key-B")).toBeCloseTo(0.1)
    expect(store.spentToday("2026-11-24", "key-C")).toBe(0)
    expect(store.totalToday("2026-11-24")).toBeCloseTo(0.85)
    expect(store.totalToday("2026-11-25")).toBeCloseTo(0.9)
    expect(store.totalToday("2026-11-26")).toBe(0)
  })
})
