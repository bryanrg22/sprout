/**
 * The gateway's state, in one SQLite file (Node's built-in `node:sqlite`): registered device
 * keys, one-time challenges, the assertion counters seen, and each day's spend. Everything
 * here is about a device key, never about a person: no request or response body is stored.
 */
import { randomBytes } from "node:crypto"
import { DatabaseSync } from "node:sqlite"
import type { AttestEnvironment } from "./appattest.js"

export interface Device {
  keyId: string
  publicKeyPem: string
  appId: string
  environment: AttestEnvironment
  maxCounter: number
  revoked: boolean
}

/**
 * How far behind the highest counter seen an assertion may arrive. Requests run concurrently
 * (the app makes several model calls at once), so assertions can reach the server out of order;
 * each counter is still accepted only once, which is what stops a replay (the same idea as
 * IPsec's anti-replay window, RFC 4303 section 3.4.3).
 */
export const COUNTER_WINDOW = 64

export class Store {
  private db: DatabaseSync

  constructor(path: string) {
    this.db = new DatabaseSync(path)
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS challenges (value TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS devices (
        key_id TEXT PRIMARY KEY, public_key TEXT NOT NULL, app_id TEXT NOT NULL,
        environment TEXT NOT NULL, max_counter INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL, last_seen_at INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS seen_counters (
        key_id TEXT NOT NULL, counter INTEGER NOT NULL, PRIMARY KEY (key_id, counter));
      CREATE TABLE IF NOT EXISTS spend (
        day TEXT NOT NULL, key_id TEXT NOT NULL, usd REAL NOT NULL DEFAULT 0,
        requests INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, key_id));
    `)
  }

  close() {
    this.db.close()
  }

  /** A fresh single-use challenge, valid for `ttlMs`. */
  issueChallenge(nowMs: number, ttlMs: number): string {
    this.db.prepare("DELETE FROM challenges WHERE expires_at < ?").run(nowMs)
    const value = randomBytes(32).toString("base64url")
    this.db.prepare("INSERT INTO challenges (value, expires_at) VALUES (?, ?)").run(value, nowMs + ttlMs)
    return value
  }

  /** True once for a challenge we issued that has not expired; it cannot be used again. */
  consumeChallenge(value: string, nowMs: number): boolean {
    const row = this.db.prepare("DELETE FROM challenges WHERE value = ? RETURNING expires_at").get(value) as
      | { expires_at: number }
      | undefined
    return !!row && row.expires_at >= nowMs
  }

  /** Registers (or re-registers, after an app reinstall makes a new key) a device key. */
  addDevice(d: Omit<Device, "maxCounter" | "revoked">, nowMs: number) {
    this.db
      .prepare(
        `INSERT INTO devices (key_id, public_key, app_id, environment, max_counter, created_at, last_seen_at)
         VALUES (?, ?, ?, ?, 0, ?, ?)
         ON CONFLICT(key_id) DO UPDATE SET public_key = excluded.public_key, app_id = excluded.app_id,
           environment = excluded.environment, max_counter = 0, last_seen_at = excluded.last_seen_at`,
      )
      .run(d.keyId, d.publicKeyPem, d.appId, d.environment, nowMs, nowMs)
    this.db.prepare("DELETE FROM seen_counters WHERE key_id = ?").run(d.keyId)
  }

  device(keyId: string): Device | undefined {
    const row = this.db.prepare("SELECT * FROM devices WHERE key_id = ?").get(keyId) as
      | Record<string, unknown>
      | undefined
    if (!row) return undefined
    return {
      keyId: row.key_id as string,
      publicKeyPem: row.public_key as string,
      appId: row.app_id as string,
      environment: row.environment as AttestEnvironment,
      maxCounter: Number(row.max_counter),
      revoked: Number(row.revoked) === 1,
    }
  }

  revoke(keyId: string) {
    this.db.prepare("UPDATE devices SET revoked = 1 WHERE key_id = ?").run(keyId)
  }

  /**
   * Accepts an assertion counter for a key exactly once: higher than the highest seen, or
   * within `COUNTER_WINDOW` below it and not seen before. Counter 0 belongs to the attestation.
   */
  acceptCounter(keyId: string, counter: number, nowMs: number): boolean {
    if (!Number.isInteger(counter) || counter <= 0) return false
    this.db.exec("BEGIN IMMEDIATE")
    try {
      const row = this.db.prepare("SELECT max_counter FROM devices WHERE key_id = ?").get(keyId) as
        | { max_counter: number }
        | undefined
      if (!row) {
        this.db.exec("ROLLBACK")
        return false
      }
      const max = Number(row.max_counter)
      if (counter <= max - COUNTER_WINDOW) {
        this.db.exec("ROLLBACK")
        return false
      }
      const inserted = this.db
        .prepare("INSERT OR IGNORE INTO seen_counters (key_id, counter) VALUES (?, ?)")
        .run(keyId, counter)
      if (Number(inserted.changes) === 0) {
        this.db.exec("ROLLBACK")
        return false
      }
      const newMax = Math.max(max, counter)
      this.db.prepare("UPDATE devices SET max_counter = ?, last_seen_at = ? WHERE key_id = ?").run(newMax, nowMs, keyId)
      this.db.prepare("DELETE FROM seen_counters WHERE key_id = ? AND counter <= ?").run(keyId, newMax - COUNTER_WINDOW)
      this.db.exec("COMMIT")
      return true
    } catch (error) {
      this.db.exec("ROLLBACK")
      throw error
    }
  }

  spentToday(day: string, keyId: string): number {
    const row = this.db.prepare("SELECT usd FROM spend WHERE day = ? AND key_id = ?").get(day, keyId) as
      | { usd: number }
      | undefined
    return row ? Number(row.usd) : 0
  }

  totalToday(day: string): number {
    const row = this.db.prepare("SELECT COALESCE(SUM(usd), 0) AS usd FROM spend WHERE day = ?").get(day) as {
      usd: number
    }
    return Number(row.usd)
  }

  addSpend(day: string, keyId: string, usd: number) {
    this.db
      .prepare(
        `INSERT INTO spend (day, key_id, usd, requests) VALUES (?, ?, ?, 1)
         ON CONFLICT(day, key_id) DO UPDATE SET usd = usd + excluded.usd, requests = requests + 1`,
      )
      .run(day, keyId, usd)
  }
}
