/**
 * The little DER reading App Attest needs: Node's `X509Certificate` checks chains and
 * signatures but does not expose arbitrary extensions, and the attestation's nonce lives in
 * one (OID 1.2.840.113635.100.8.2). Definite lengths only, which is all DER allows.
 */

export interface Tlv {
  tag: number
  /** Offset of the value's first byte. */
  start: number
  /** Offset one past the value's last byte. */
  end: number
}

export function readTlv(buf: Uint8Array, offset: number): Tlv | undefined {
  if (offset + 2 > buf.length) return undefined
  const tag = buf[offset]!
  let length = buf[offset + 1]!
  let start = offset + 2
  if (length & 0x80) {
    const count = length & 0x7f
    if (count === 0 || count > 4 || start + count > buf.length) return undefined
    length = 0
    for (let i = 0; i < count; i++) length = length * 256 + buf[start + i]!
    start += count
  }
  const end = start + length
  if (end > buf.length) return undefined
  return { tag, start, end }
}

/** The TLVs directly inside a constructed TLV. */
export function children(buf: Uint8Array, parent: Tlv): Tlv[] | undefined {
  const out: Tlv[] = []
  let at = parent.start
  while (at < parent.end) {
    const child = readTlv(buf, at)
    if (!child || child.end > parent.end) return undefined
    out.push(child)
    at = child.end
  }
  return out
}

const TAG_SEQUENCE = 0x30
const TAG_OID = 0x06
const TAG_BOOLEAN = 0x01
const TAG_OCTET_STRING = 0x04
const TAG_EXTENSIONS = 0xa3 // [3] EXPLICIT in TBSCertificate
const TAG_CONTEXT_1 = 0xa1 // [1] EXPLICIT

/** DER of an OID's value bytes, e.g. "1.2.840.113635.100.8.2". */
export function encodeOid(oid: string): Uint8Array {
  const parts = oid.split(".").map(Number)
  const bytes: number[] = [parts[0]! * 40 + parts[1]!]
  for (const part of parts.slice(2)) {
    const stack: number[] = []
    let v = part
    do {
      stack.unshift(v & 0x7f)
      v = Math.floor(v / 128)
    } while (v > 0)
    for (let i = 0; i < stack.length - 1; i++) stack[i]! |= 0x80
    bytes.push(...stack)
  }
  return Uint8Array.from(bytes)
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i])
}

/**
 * The value (the bytes inside the OCTET STRING) of the certificate extension `oid`, walking
 * Certificate → TBSCertificate → [3] Extensions → Extension { OID, critical?, OCTET STRING }.
 */
export function extensionValue(certDer: Uint8Array, oid: string): Uint8Array | undefined {
  const cert = readTlv(certDer, 0)
  if (!cert || cert.tag !== TAG_SEQUENCE) return undefined
  const tbs = children(certDer, cert)?.[0]
  if (!tbs || tbs.tag !== TAG_SEQUENCE) return undefined
  const extsTagged = children(certDer, tbs)?.find((t) => t.tag === TAG_EXTENSIONS)
  if (!extsTagged) return undefined
  const exts = children(certDer, extsTagged)?.[0]
  if (!exts || exts.tag !== TAG_SEQUENCE) return undefined
  const want = encodeOid(oid)
  for (const ext of children(certDer, exts) ?? []) {
    const parts = children(certDer, ext)
    if (!parts || parts.length < 2) continue
    const [id, second, third] = parts
    if (id!.tag !== TAG_OID || !equal(certDer.subarray(id!.start, id!.end), want)) continue
    const octets = second!.tag === TAG_BOOLEAN ? third : second
    if (!octets || octets.tag !== TAG_OCTET_STRING) return undefined
    return certDer.subarray(octets.start, octets.end)
  }
  return undefined
}

/** App Attest's nonce extension: `SEQUENCE { [1] EXPLICIT OCTET STRING nonce }`. */
export function appAttestNonce(extension: Uint8Array): Uint8Array | undefined {
  const seq = readTlv(extension, 0)
  if (!seq || seq.tag !== TAG_SEQUENCE) return undefined
  const tagged = children(extension, seq)?.[0]
  if (!tagged || tagged.tag !== TAG_CONTEXT_1) return undefined
  const octets = children(extension, tagged)?.[0]
  if (!octets || octets.tag !== TAG_OCTET_STRING) return undefined
  return extension.subarray(octets.start, octets.end)
}
