# Sprout AI gateway

The app's built-in AI. It holds the Anthropic (and optionally OpenAI) API keys so a person
who installs Sprout from TestFlight can use every AI feature without a key of their own.

A key inside the app could be pulled out of any build, and this repository is public, so
the key lives here instead. To stop the gateway from becoming free AI for anyone who finds
its address, every call must come from a genuine copy of the app on a real iPhone (Apple's
App Attest), each device has a daily allowance, there is a daily total for everyone, and
only the app's own models are paid for.

```
iPhone (no key) ──signed──▶ gateway (keys, caps, allowlist) ──▶ api.anthropic.com / api.openai.com
```

A person who adds their own key in Settings → AI goes straight to the provider, as before.

## How a call is checked

1. **Registration, once per install.** The app makes an App Attest key in the Secure
   Enclave, asks the gateway for a one-time challenge, has Apple attest the key over it,
   and sends the attestation. The gateway checks it the way Apple specifies ("Validating
   apps that connect to your server", steps 1–9): the certificate chain to Apple's App
   Attestation root, the nonce, the key id, our App ID (Team ID + bundle ID), counter 0,
   the environment, the credential id. It stores the device's public key.
2. **Every model call** carries `X-Sprout-Key-Id`, `X-Sprout-Timestamp` and
   `X-Sprout-Assertion`: the device's signature over `POST\n<route>\n<timestamp>\n` and
   the body. The gateway checks the signature with the stored key, that it is for our app,
   that the timestamp is within 5 minutes, and that the assertion's counter has not been
   used (each is accepted once, within a 64-wide window for concurrent calls).
3. **The allowance:** this device's spend today (UTC) is under `DEVICE_DAILY_CAP_USD`, and
   everyone's under `TOTAL_DAILY_CAP_USD`. Otherwise 429 `daily_limit` / `service_limit`,
   which the app shows as "That's all the AI for today".
4. **The request:** an allowed model (`src/pricing.ts`), output at most 8,192 tokens, no
   streaming, no server tools except Anthropic web search with at most 5 uses; for the
   character picture, the one image model at `low` and one image.
5. **Forward** with the owner's key; the provider's answer goes back unchanged. The cost is
   computed from the provider's own `usage` report and added to the device's day.

Nothing about a person is stored: no body, no name, no IP. The database holds device public
keys, used counters, challenges and per-day dollar totals. Logs hold the route, status,
model, cost and the first 8 characters of the key id.

### Choices, and why

- **Counter + timestamp instead of a challenge per call.** Apple's example asks the server
  for a fresh challenge before each assertion. Replay protection here comes from the counter
  (accepted once) instead, which is Apple's own step for assertions, and the body is bound
  into the signature, so a captured request can neither be replayed nor altered. It saves a
  round trip on every model call.
- **No streaming.** The app does not stream, and a whole response is what lets the gateway
  price the call from `usage`.
- **SQLite (`node:sqlite`) in a Docker volume.** One small file, no database server, no
  native module. Node 24 LTS.
- **Development builds allowed** (`ALLOW_DEVELOPMENT=true`): a build installed from Xcode
  attests in Apple's sandbox. TestFlight and App Store builds always attest in production.

### Limits worth knowing

- App Attest identifies a genuine install, not a person. Someone who reinstalls the app gets
  a new key and a new daily allowance; `TOTAL_DAILY_CAP_USD` is the backstop. Set a monthly
  spend limit in the Anthropic console too.
- A device that does not support App Attest (the Simulator, very old hardware) cannot use
  the built-in AI; it can still use a key of its own.

## Running it on the droplet

Needs Docker with the compose plugin, ports 80 and 443 free, and a hostname whose A record
points at the droplet (any subdomain you own; or `<ip-with-dashes>.sslip.io` with no DNS).

```bash
git clone https://github.com/bryanrg22/sprout.git && cd sprout/server
cp .env.example .env
nano .env        # DOMAIN, ANTHROPIC_API_KEY (pasted by you), optional OPENAI_API_KEY
docker compose up -d --build
curl https://$DOMAIN/health   # {"ok":true,"anthropic":true,"openai":false}
```

Caddy gets the HTTPS certificate on first start. Then set `AIGateway.address` in
`Victoria/Services/AI/AIGateway.swift` to `https://<DOMAIN>` and ship a build.

Update: `git pull && docker compose up -d --build`. Logs: `docker compose logs -f gateway`.
Today's spend: `docker compose exec gateway node -e "const {DatabaseSync}=require('node:sqlite');console.log(new DatabaseSync('/data/gateway.sqlite').prepare('select key_id, usd, requests from spend where day=date()').all())"`.

## Developing

```bash
npm ci
npm test          # 57 tests: App Attest checks, the store, every route
npm run typecheck
```

The tests build App Attest objects the way a device does, under a test root CA
(`test/fakeAttest.ts`), and check that each of Apple's steps refuses what it should.
