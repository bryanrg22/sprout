import "reflect-metadata"
/**
 * App Attest objects built the way a device builds them, under a test root instead of Apple's:
 * a root and an intermediate CA, a P-256 device key in a leaf certificate carrying the nonce
 * extension, the authenticator data, and assertions signed by the device key.
 */
import { createHash, createPrivateKey, sign, webcrypto } from "node:crypto"
import * as x509 from "@peculiar/x509"
import { encode } from "cbor-x"

x509.cryptoProvider.set(webcrypto as unknown as Crypto)

const subtle = webcrypto.subtle
export const sha = (...parts: Uint8Array[]) => {
  const h = createHash("sha256")
  for (const p of parts) h.update(p)
  return h.digest()
}

export const TEAM = "TEAM123456"
export const BUNDLE = "com.example.sprout"
export const APP_ID = `${TEAM}.${BUNDLE}`
export const AAGUID_PROD = Buffer.concat([Buffer.from("appattest"), Buffer.alloc(7)])
export const AAGUID_DEV = Buffer.from("appattestdevelop")

type KeyPair = CryptoKeyPair

async function ecKey(namedCurve: "P-256" | "P-384"): Promise<KeyPair> {
  return (await subtle.generateKey({ name: "ECDSA", namedCurve }, true, ["sign", "verify"])) as KeyPair
}

export interface TestCA {
  rootPem: string
  root: x509.X509Certificate
  intermediate: x509.X509Certificate
  intermediateKeys: KeyPair
}

export async function makeCA(opts: { notAfter?: Date } = {}): Promise<TestCA> {
  const rootKeys = await ecKey("P-384")
  const notBefore = new Date("2020-01-01T00:00:00Z")
  const notAfter = opts.notAfter ?? new Date("2045-01-01T00:00:00Z")
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test App Attestation Root CA",
    notBefore,
    notAfter,
    keys: rootKeys,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-384" },
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  })
  const intermediateKeys = await ecKey("P-384")
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test App Attestation CA 1",
    issuer: root.subject,
    notBefore,
    notAfter,
    publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-384" },
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  })
  return { rootPem: root.toString("pem"), root, intermediate, intermediateKeys }
}

export interface TestDevice {
  keyId: Buffer
  keyIdB64: string
  privateKeyPem: string
}

export async function makeDevice(): Promise<TestDevice & { keys: KeyPair; point: Buffer }> {
  const keys = await ecKey("P-256")
  const point = Buffer.from(await subtle.exportKey("raw", keys.publicKey)) // 0x04 || X || Y
  const keyId = sha(point)
  const pkcs8 = Buffer.from(await subtle.exportKey("pkcs8", keys.privateKey))
  const privateKeyPem = createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" }).export({ format: "pem", type: "pkcs8" }).toString()
  return { keys, point, keyId, keyIdB64: keyId.toString("base64"), privateKeyPem }
}

export interface AttestationOptions {
  appId?: string
  aaguid?: Buffer
  counter?: number
  /** Put another key's id in the credential id. */
  credentialId?: Buffer
  /** Sign the nonce of a different clientDataHash than the one given. */
  nonceClientDataHash?: Buffer
  leafNotAfter?: Date
}

/** The attestation object `attestKey(keyId, clientDataHash)` returns. */
export async function makeAttestation(
  ca: TestCA,
  device: Awaited<ReturnType<typeof makeDevice>>,
  clientDataHash: Buffer,
  opts: AttestationOptions = {},
): Promise<Buffer> {
  const counter = Buffer.alloc(4)
  counter.writeUInt32BE(opts.counter ?? 0)
  const credId = opts.credentialId ?? device.keyId
  const credLen = Buffer.alloc(2)
  credLen.writeUInt16BE(credId.length)
  const authData = Buffer.concat([
    sha(Buffer.from(opts.appId ?? APP_ID)),
    Buffer.from([0x40]),
    counter,
    opts.aaguid ?? AAGUID_PROD,
    credLen,
    credId,
    Buffer.from([0xa5, 0x01, 0x02]), // the start of a COSE key; not read by the verifier
  ])
  const nonce = sha(authData, opts.nonceClientDataHash ?? clientDataHash)
  // SEQUENCE { [1] EXPLICIT OCTET STRING (32) nonce }
  const ext = Buffer.concat([Buffer.from([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]), nonce])
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03",
    subject: "CN=" + device.keyId.toString("hex"),
    issuer: ca.intermediate.subject,
    notBefore: new Date("2020-01-01T00:00:00Z"),
    notAfter: opts.leafNotAfter ?? new Date("2040-01-01T00:00:00Z"),
    publicKey: device.keys.publicKey,
    signingKey: ca.intermediateKeys.privateKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
    extensions: [new x509.Extension("1.2.840.113635.100.8.2", false, ext)],
  })
  return Buffer.from(
    encode({
      fmt: "apple-appattest",
      attStmt: { x5c: [Buffer.from(leaf.rawData), Buffer.from(ca.intermediate.rawData)], receipt: Buffer.from("receipt") },
      authData,
    }),
  )
}

/** The assertion `generateAssertion(keyId, SHA-256(clientData))` returns. */
export function makeAssertion(
  device: TestDevice,
  clientData: Buffer,
  counterValue: number,
  opts: { appId?: string } = {},
): Buffer {
  const counter = Buffer.alloc(4)
  counter.writeUInt32BE(counterValue)
  const authenticatorData = Buffer.concat([sha(Buffer.from(opts.appId ?? APP_ID)), Buffer.from([0x40]), counter])
  const nonce = sha(authenticatorData, sha(clientData))
  const signature = sign("sha256", nonce, { key: device.privateKeyPem, dsaEncoding: "der" })
  return Buffer.from(encode({ signature, authenticatorData }))
}
