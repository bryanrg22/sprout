import { mkdirSync } from "node:fs"
import { dirname } from "node:path"
import { serve } from "@hono/node-server"
import { createApp } from "./app.js"
import { loadConfig } from "./config.js"
import { Store } from "./store.js"

const config = loadConfig()
mkdirSync(dirname(config.dbPath), { recursive: true })
const store = new Store(config.dbPath)
const app = createApp({ config, store, fetch: globalThis.fetch, now: () => Date.now() })

serve({ fetch: app.fetch, port: config.port }, ({ port }) => {
  console.log(
    JSON.stringify({
      event: "listening",
      port,
      appIds: config.appIds,
      allowDevelopment: config.allowDevelopment,
      openai: !!config.openaiKey,
      deviceDailyCapUsd: config.deviceDailyCapUsd,
      totalDailyCapUsd: config.totalDailyCapUsd,
    }),
  )
})

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    store.close()
    process.exit(0)
  })
}
