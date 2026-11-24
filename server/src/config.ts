/** Settings, all from the environment (the droplet's `.env`, which the owner writes). */
export interface Config {
  port: number
  /** Accepted App IDs, `<TeamID>.<bundle id>`. */
  appIds: string[]
  /** Accept attestations from development-signed builds (Xcode installs) as well as TestFlight. */
  allowDevelopment: boolean
  anthropicKey: string
  /** Optional: without it the OpenAI routes answer 503 and the app keeps OpenAI features off. */
  openaiKey?: string
  /** Per device key, per UTC day. */
  deviceDailyCapUsd: number
  /** Across every device, per UTC day: the backstop if many keys are made. */
  totalDailyCapUsd: number
  dbPath: string
  maxBodyBytes: number
}

function number(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const raw = env[key]
  if (raw === undefined || raw === "") return fallback
  const n = Number(raw)
  if (!Number.isFinite(n) || n < 0) throw new Error(`${key} must be a non-negative number, got "${raw}"`)
  return n
}

function required(env: NodeJS.ProcessEnv, key: string): string {
  const v = env[key]?.trim()
  if (!v) throw new Error(`${key} is required`)
  return v
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const team = required(env, "APPLE_TEAM_ID")
  const bundles = required(env, "BUNDLE_IDS")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
  return {
    port: number(env, "PORT", 8787),
    appIds: bundles.map((b) => `${team}.${b}`),
    allowDevelopment: (env.ALLOW_DEVELOPMENT ?? "true").toLowerCase() === "true",
    anthropicKey: required(env, "ANTHROPIC_API_KEY"),
    openaiKey: env.OPENAI_API_KEY?.trim() || undefined,
    deviceDailyCapUsd: number(env, "DEVICE_DAILY_CAP_USD", 1),
    totalDailyCapUsd: number(env, "TOTAL_DAILY_CAP_USD", 20),
    dbPath: env.DB_PATH ?? "./data/gateway.sqlite",
    maxBodyBytes: number(env, "MAX_BODY_BYTES", 20 * 1024 * 1024),
  }
}
