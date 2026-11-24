# Fitbit direct connection — Google Cloud setup (one-time, ~15 min)

The app now talks straight to the **Google Health API** (`health.googleapis.com/v4`) —
the API where the Fitbit Air's data lives. No bridge app. Your only job is to create
the OAuth client in Google Cloud and paste its ID into the app once.

Everything below happens at https://console.cloud.google.com, signed in with the
**same Google account your Fitbit app uses**.

## 1. Create a project
- Top bar → project picker → **New project** → name it e.g. `sprout-fitbit` → Create.
- Make sure it's the selected project before continuing.

## 2. Enable the Google Health API
- **APIs & Services → Library** → search **"Google Health"** → open **Google Health API**
  (the one for `health.googleapis.com`) → **Enable**.

## 3. Configure the OAuth consent screen (Testing mode)
- **APIs & Services → OAuth consent screen** (Google may call it "Google Auth Platform → Branding/Audience").
- User type: **External** → app name `Sprout`, your email for both contact fields → Save.
- **Audience / Publishing status: keep it in "Testing".** Do NOT publish. Testing mode
  allows up to 100 test users with **no verification review**, which is exactly right
  for personal use — even though the health scopes are "restricted".
- Under **Test users** → **+ Add users** → add `<email>` (the Google
  account with your Fitbit data).
- If there's a "Data Access / Scopes" step, you can skip adding scopes — the app
  requests them at sign-in time. If you prefer to add them, they are:
  - `.../auth/googlehealth.sleep.readonly`
  - `.../auth/googlehealth.health_metrics_and_measurements.readonly`
  - `.../auth/googlehealth.activity_and_fitness.readonly`

## 4. Create the iOS OAuth client ID
- **APIs & Services → Credentials → + Create credentials → OAuth client ID**.
- Application type: **iOS**.
- Bundle ID: `com.bryanram.victoria`
- Team ID: `C924TNC23B` (App Store ID / other fields can stay empty).
- Create → copy the **Client ID** (looks like `1234567890-abc123.apps.googleusercontent.com`).
- No client secret exists for iOS clients — that's correct and expected; the app
  uses PKCE instead.

## 5. Connect in the app
- Sprout → **Settings → Fitbit (Google Health)** → paste the client ID → **Sign in with Google**.
- Sign in on Google's page. You'll see an **"unverified app"** warning — that's the
  Testing-mode banner; tap **Continue** (you added yourself as a test user, this is you
  authorizing yourself).
- Approve the three read-only permissions. The app pulls the last 14 days immediately
  and re-syncs every time it opens.

## Where the data shows up
Same places as before — the pipe changed, not the features: the Today tracker card,
sleep charts, recovery signal, Vita's context, the daily brief.

## Gotchas
- **Testing-mode refresh tokens expire after 7 days** on some Google configurations.
  If the app says the connection expired, just tap Sign in again. If that gets
  annoying, tell Claude — the alternative is going through Google's verification,
  or we live with a weekly re-tap.
- If Google says **"access_denied"** at sign-in: your email isn't in Test users, or
  you signed into the wrong Google account.
- If sync returns **403**: the Google Health API isn't enabled on the project (step 2),
  or the consent screen scopes were restricted differently — the exact error is logged
  in the hidden Diagnostics screen (Settings → tap version 7×).
