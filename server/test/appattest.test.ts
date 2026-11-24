import { X509Certificate } from "node:crypto"
import { beforeAll, describe, expect, it } from "vitest"
import { APPLE_APP_ATTEST_ROOT_PEM, AttestError, verifyAssertion, verifyAttestation } from "../src/appattest.js"
import {
  AAGUID_DEV,
  APP_ID,
  makeAssertion,
  makeAttestation,
  makeCA,
  makeDevice,
  sha,
  type TestCA,
} from "./fakeAttest.js"

const NOW = new Date("2026-11-24T12:00:00Z")
let ca: TestCA
let device: Awaited<ReturnType<typeof makeDevice>>
const challengeHash = sha(Buffer.from("challenge-1"))

/** A genuine attestation of `device` for `challengeHash`, and one with a non-zero counter. */
let attestation: Buffer
let counterOne: Buffer

beforeAll(async () => {
  ca = await makeCA()
  device = await makeDevice()
  attestation = await makeAttestation(ca, device, challengeHash)
  counterOne = await makeAttestation(ca, device, challengeHash, { counter: 1 })
})

function attest(attestation: Buffer, overrides: Partial<Parameters<typeof verifyAttestation>[0]> = {}) {
  return verifyAttestation({
    attestation,
    keyId: device.keyId,
    clientDataHash: challengeHash,
    appIds: [APP_ID],
    allowDevelopment: false,
    now: NOW,
    rootPem: ca.rootPem,
    ...overrides,
  })
}

function reason(fn: () => unknown): string {
  try {
    fn()
  } catch (error) {
    if (error instanceof AttestError) return error.reason
    throw error
  }
  return "accepted"
}

describe("Apple's root", () => {
  it("is the App Attestation root and valid today", () => {
    const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM)
    expect(root.subject).toContain("Apple App Attestation Root CA")
    expect(root.fingerprint256).toBe(
      "1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32",
    )
    expect(new Date(root.validTo) > NOW).toBe(true)
  })
})

describe("verifyAttestation", () => {
  const make = (opts?: Parameters<typeof makeAttestation>[3]) => makeAttestation(ca, device, challengeHash, opts)

  it("accepts a production attestation for our app and returns the device key", async () => {
    const result = attest(await make())
    expect(result.environment).toBe("production")
    expect(result.appId).toBe(APP_ID)
    expect(result.publicKeyPem).toContain("BEGIN PUBLIC KEY")
  })

  it("picks the matching App ID out of several", async () => {
    expect(attest(await make(), { appIds: ["OTHER.app", APP_ID] }).appId).toBe(APP_ID)
  })

  it("accepts a development attestation only when allowed (step 8)", async () => {
    const dev = await make({ aaguid: AAGUID_DEV })
    expect(reason(() => attest(dev))).toBe("environment")
    expect(attest(dev, { allowDevelopment: true }).environment).toBe("development")
    const sandbox = await make({ aaguid: Buffer.from("appattestsandbox") })
    expect(reason(() => attest(sandbox))).toBe("environment")
    expect(attest(sandbox, { allowDevelopment: true }).environment).toBe("development")
  })

  it("refuses an unknown environment (step 8)", async () => {
    const odd = await make({ aaguid: Buffer.alloc(16) })
    expect(reason(() => attest(odd, { allowDevelopment: true }))).toBe("environment")
  })

  it("refuses an attestation of another challenge (steps 2-4)", async () => {
    const signedOther = await make({ nonceClientDataHash: sha(Buffer.from("other")) })
    expect(reason(() => attest(signedOther))).toBe("nonce")
    const genuine = await make()
    expect(reason(() => attest(genuine, { clientDataHash: sha(Buffer.from("other")) }))).toBe("nonce")
  })

  it("refuses a key id that is not the attested key (step 5)", async () => {
    const other = await makeDevice()
    expect(reason(() => attest(attestation, { keyId: other.keyId }))).toBe("key_id")
  })

  it("refuses another app's attestation (step 6)", async () => {
    expect(reason(() => attest(attestation, { appIds: ["TEAM123456.com.someone.else"] }))).toBe("app_id")
  })

  it("refuses a non-zero counter (step 7)", async () => {
    expect(reason(() => attest(attestation))).toBe("accepted")
    expect(reason(() => attest(counterOne))).toBe("counter")
  })

  it("refuses a credential id that is not the key id (step 9)", async () => {
    const wrong = await make({ credentialId: sha(Buffer.from("x")) })
    expect(reason(() => attest(wrong))).toBe("credential_id")
  })

  it("refuses a chain from another root (step 1)", async () => {
    const stranger = await makeCA()
    expect(reason(() => attest(attestation, { rootPem: stranger.rootPem }))).toBe("chain")
    // Our test chain is refused against Apple's real root, which is the production default.
    expect(reason(() => attest(attestation, { rootPem: undefined }))).toBe("chain")
  })

  it("refuses an expired leaf (step 1)", async () => {
    const expired = await make({ leafNotAfter: new Date("2026-01-01T00:00:00Z") })
    expect(reason(() => attest(expired))).toBe("chain")
  })

  it("refuses bytes that are not an attestation", () => {
    expect(reason(() => attest(Buffer.from("not cbor at all")))).toBe("format")
    expect(reason(() => attest(Buffer.from([0xa1, 0x63, 0x66, 0x6d, 0x74, 0x61, 0x78])))).toBe("format")
  })
})

describe("verifyAssertion", () => {
  const clientData = Buffer.from("POST\n/anthropic/v1/messages\n1764000000000\n{\"model\":\"x\"}")

  function check(assertion: Buffer, overrides: Partial<Parameters<typeof verifyAssertion>[0]> = {}) {
    const { publicKeyPem } = attest(attestation)
    return verifyAssertion({ assertion, clientData, publicKeyPem, appId: APP_ID, ...overrides })
  }

  it("accepts the device's signature over this request and returns the counter", () => {
    expect(check(makeAssertion(device, clientData, 7)).counter).toBe(7)
  })

  it("refuses the assertion for a changed request", () => {
    const changed = Buffer.from(clientData.toString().replace("x", "y"))
    expect(reason(() => check(makeAssertion(device, clientData, 1), { clientData: changed }))).toBe("signature")
  })

  it("refuses another device's signature", async () => {
    const other = await makeDevice()
    expect(reason(() => check(makeAssertion(other, clientData, 1)))).toBe("signature")
  })

  it("refuses an assertion made for another app", () => {
    expect(reason(() => check(makeAssertion(device, clientData, 1, { appId: "TEAM123456.com.someone.else" })))).toBe("app_id")
  })

  it("refuses bytes that are not an assertion", () => {
    expect(reason(() => check(Buffer.from("nope")))).toBe("format")
  })
})
