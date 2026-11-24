/**
 * Apple App Attest, server side, following Apple's "Validating apps that connect to your
 * server": an attestation once per device key (steps 1-9 below), then an assertion on every
 * request. Only Node's crypto; no network calls.
 *
 * What it proves: the request was signed by a key that lives in the Secure Enclave of a real
 * Apple device, created by a genuine copy of an app with one of our App IDs (Team ID + bundle
 * ID). It does not identify the person.
 */
import { createHash, createPublicKey, verify as verifySignature, X509Certificate } from "node:crypto"
import { decode as decodeCbor } from "cbor-x"
import { appAttestNonce, extensionValue } from "./der.js"

/**
 * Apple App Attestation Root CA, from https://www.apple.com/certificateauthority/
 * (downloaded 2026-11-24; SHA-256 fingerprint
 * 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32,
 * byte-identical to the copy in independent open-source verifiers). Valid to 2045-03-15.
 */
export const APPLE_APP_ATTEST_ROOT_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----
`

const NONCE_OID = "1.2.840.113635.100.8.2"
const AAGUID_PRODUCTION = Buffer.concat([Buffer.from("appattest"), Buffer.alloc(7)])
/**
 * Development (sandbox) builds. Apple's validation steps name "appattestdevelop"; its newer
 * pages call the environment "sandbox" ("appattestsandbox"). Both are accepted, and only when
 * the deployment allows development builds.
 */
const AAGUID_DEVELOPMENT = [Buffer.from("appattestdevelop"), Buffer.from("appattestsandbox")]

export type AttestEnvironment = "production" | "development"

/** Why a check failed; `reason` is a short stable code the client and the logs can use. */
export class AttestError extends Error {
  constructor(readonly reason: string, message: string) {
    super(message)
  }
}

export const sha256 = (...parts: Uint8Array[]): Buffer => {
  const h = createHash("sha256")
  for (const p of parts) h.update(p)
  return h.digest()
}

function asBuffer(value: unknown): Buffer | undefined {
  if (Buffer.isBuffer(value)) return value
  if (value instanceof Uint8Array) return Buffer.from(value.buffer, value.byteOffset, value.byteLength)
  return undefined
}

function field(obj: unknown, key: string): unknown {
  if (obj instanceof Map) return obj.get(key)
  if (obj && typeof obj === "object") return (obj as Record<string, unknown>)[key]
  return undefined
}

function validAt(cert: X509Certificate, now: Date): boolean {
  return new Date(cert.validFrom) <= now && now <= new Date(cert.validTo)
}

/** The uncompressed EC point (0x04 || X || Y) of a P-256 certificate key. */
function publicKeyPoint(cert: X509Certificate): Buffer {
  const jwk = cert.publicKey.export({ format: "jwk" })
  if (jwk.kty !== "EC" || jwk.crv !== "P-256" || !jwk.x || !jwk.y) {
    throw new AttestError("key_type", "The attested key is not a P-256 key.")
  }
  return Buffer.concat([Buffer.from([0x04]), Buffer.from(jwk.x, "base64url"), Buffer.from(jwk.y, "base64url")])
}

export interface AttestationInput {
  /** The attestation object from `DCAppAttestService.attestKey`, raw bytes. */
  attestation: Uint8Array
  /** The key id from `generateKey`, raw bytes (SHA-256 of the public key). */
  keyId: Uint8Array
  /** The SHA-256 the client passed to `attestKey` (we compute it from our challenge). */
  clientDataHash: Uint8Array
  /** Accepted App IDs: `<TeamID>.<bundle id>`. */
  appIds: readonly string[]
  allowDevelopment: boolean
  now: Date
  /** The trust anchor; Apple's root unless a test supplies its own. */
  rootPem?: string
}

export interface AttestationResult {
  appId: string
  environment: AttestEnvironment
  /** SPKI PEM of the device key, stored to check every later assertion. */
  publicKeyPem: string
}

export function verifyAttestation(input: AttestationInput): AttestationResult {
  let decoded: unknown
  try {
    decoded = decodeCbor(Buffer.from(input.attestation))
  } catch {
    throw new AttestError("format", "The attestation is not CBOR.")
  }
  const attStmt = field(decoded, "attStmt")
  const authData = asBuffer(field(decoded, "authData"))
  if (field(decoded, "fmt") !== "apple-appattest" || !attStmt || !authData) {
    throw new AttestError("format", "The attestation is not an apple-appattest attestation.")
  }
  const x5c = field(attStmt, "x5c")
  if (!Array.isArray(x5c) || x5c.length < 2) {
    throw new AttestError("format", "The attestation must carry a leaf and an intermediate certificate.")
  }
  const leafDer = asBuffer(x5c[0])
  const intermediateDer = asBuffer(x5c[1])
  if (!leafDer || !intermediateDer) throw new AttestError("format", "A certificate is not bytes.")

  // Step 1: leaf → intermediate → Apple's root, each signed by the next and valid now.
  let leaf: X509Certificate, intermediate: X509Certificate, root: X509Certificate
  try {
    leaf = new X509Certificate(leafDer)
    intermediate = new X509Certificate(intermediateDer)
    root = new X509Certificate(input.rootPem ?? APPLE_APP_ATTEST_ROOT_PEM)
  } catch {
    throw new AttestError("chain", "A certificate does not parse.")
  }
  const chainOk =
    validAt(root, input.now) &&
    validAt(intermediate, input.now) &&
    validAt(leaf, input.now) &&
    intermediate.ca &&
    intermediate.checkIssued(root) &&
    intermediate.verify(root.publicKey) &&
    leaf.checkIssued(intermediate) &&
    leaf.verify(intermediate.publicKey)
  if (!chainOk) throw new AttestError("chain", "The certificate chain does not lead to the App Attest root.")

  // Steps 2-4: nonce = SHA-256(authData || clientDataHash) is the leaf's nonce extension.
  const extension = extensionValue(leafDer, NONCE_OID)
  const nonce = extension && appAttestNonce(extension)
  if (!nonce || !sha256(authData, input.clientDataHash).equals(nonce)) {
    throw new AttestError("nonce", "The attestation does not cover this challenge.")
  }

  // Step 5: the key id is the SHA-256 of the leaf's public key.
  const point = publicKeyPoint(leaf)
  const keyId = Buffer.from(input.keyId)
  if (!sha256(point).equals(keyId)) throw new AttestError("key_id", "The attested key does not match the key id.")

  // authData: rpIdHash(32) flags(1) signCount(4) aaguid(16) credIdLen(2) credId(credIdLen) …
  if (authData.length < 55) throw new AttestError("auth_data", "The authenticator data is truncated.")

  // Step 6: the RP ID hash is the SHA-256 of one of our App IDs.
  const rpIdHash = authData.subarray(0, 32)
  const appId = input.appIds.find((id) => sha256(Buffer.from(id)).equals(rpIdHash))
  if (!appId) throw new AttestError("app_id", "The attestation is for a different app.")

  // Step 7: a fresh key has signed nothing yet.
  if (authData.readUInt32BE(33) !== 0) throw new AttestError("counter", "The attestation counter is not zero.")

  // Step 8: the App Attest environment.
  const aaguid = authData.subarray(37, 53)
  let environment: AttestEnvironment
  if (aaguid.equals(AAGUID_PRODUCTION)) environment = "production"
  else if (AAGUID_DEVELOPMENT.some((a) => a.equals(aaguid)) && input.allowDevelopment) environment = "development"
  else throw new AttestError("environment", "The App Attest environment is not accepted.")

  // Step 9: the credential id is the key id.
  const credIdLength = authData.readUInt16BE(53)
  const credId = authData.subarray(55, 55 + credIdLength)
  if (credId.length !== credIdLength || !credId.equals(keyId)) {
    throw new AttestError("credential_id", "The credential id does not match the key id.")
  }

  const publicKeyPem = leaf.publicKey.export({ format: "pem", type: "spki" }).toString()
  return { appId, environment, publicKeyPem }
}

export interface AssertionInput {
  /** The assertion from `DCAppAttestService.generateAssertion`, raw bytes. */
  assertion: Uint8Array
  /** The exact bytes whose SHA-256 the client passed to `generateAssertion`. */
  clientData: Uint8Array
  publicKeyPem: string
  appId: string
}

/**
 * Checks one assertion and returns its counter. The caller must then accept the counter
 * against what it has seen for this key (`Store.acceptCounter`); that is what stops a replay.
 */
export function verifyAssertion(input: AssertionInput): { counter: number } {
  let decoded: unknown
  try {
    decoded = decodeCbor(Buffer.from(input.assertion))
  } catch {
    throw new AttestError("format", "The assertion is not CBOR.")
  }
  const signature = asBuffer(field(decoded, "signature"))
  const authData = asBuffer(field(decoded, "authenticatorData"))
  if (!signature || !authData || authData.length < 37) {
    throw new AttestError("format", "The assertion is missing its signature or authenticator data.")
  }
  // nonce = SHA-256(authenticatorData || SHA-256(clientData)); the device signed it (ECDSA
  // P-256 with SHA-256, so the signature is over SHA-256(nonce), as Apple's sample does).
  const nonce = sha256(authData, sha256(input.clientData))
  let ok = false
  try {
    ok = verifySignature("sha256", nonce, { key: createPublicKey(input.publicKeyPem), dsaEncoding: "der" }, signature)
  } catch {
    ok = false
  }
  if (!ok) throw new AttestError("signature", "The assertion signature is not valid.")
  if (!sha256(Buffer.from(input.appId)).equals(authData.subarray(0, 32))) {
    throw new AttestError("app_id", "The assertion is for a different app.")
  }
  return { counter: authData.readUInt32BE(33) }
}
