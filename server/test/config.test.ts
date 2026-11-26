import { describe, expect, it } from "vitest"
import { loadConfig } from "../src/config.js"

const base = { APPLE_TEAM_ID: "TEAM", BUNDLE_IDS: "com.example.app", ANTHROPIC_API_KEY: "k" }

describe("loadConfig", () => {
  it("listens on every interface by default, as inside Docker behind Caddy", () => {
    expect(loadConfig(base).host).toBe("0.0.0.0")
    expect(loadConfig({ ...base, HOST: "  " }).host).toBe("0.0.0.0")
  })

  it("listens where HOST says, so a host install behind a local proxy is never public", () => {
    const c = loadConfig({ ...base, HOST: "127.0.0.1", PORT: "8790" })
    expect(c.host).toBe("127.0.0.1")
    expect(c.port).toBe(8790)
  })

  it("still requires the App ID parts and the Anthropic key", () => {
    expect(() => loadConfig({ ...base, ANTHROPIC_API_KEY: "" })).toThrow("ANTHROPIC_API_KEY is required")
    expect(() => loadConfig({ ...base, APPLE_TEAM_ID: undefined })).toThrow("APPLE_TEAM_ID is required")
    expect(loadConfig(base).appIds).toEqual(["TEAM.com.example.app"])
  })
})
