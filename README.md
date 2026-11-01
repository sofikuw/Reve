# reve

**Turn GitHub repositories into personal cloud storage.**

`reve` gives you a MiXplorer-style file manager on top of the GitHub REST API:
browse repositories and branches, upload files with automatic sorting, preview
media inline, create folders and repositories, and delete with a single commit.
There is no storage server in the middle — your files live in your own repos.

Two clients ship in this repo:

| Client | Path | Stack |
| --- | --- | --- |
| Web app (single file) | [`index.html`](index.html) | Vanilla JS, Material 3 CSS |
| Android / desktop app | [`lib/`](lib) | Flutter, Material 3 |

---

## Features

- **Zero-backend** — the web client is one static `index.html`, hosted anywhere.
- **Multi-account** — several GitHub accounts at once, switch in one tap.
  Personal access tokens *and* OAuth (popup broker or device flow).
- **Smart auto-sorting uploads** — files are filed into `images/`, `documents/`,
  `media/`, `archives/`, `code/`, `others/` based on extension (toggleable).
- **Rich previews** — images, video, audio, PDF, Markdown and source code
  without an extra download.
- **Repository management** — create public/private repos with `auto_init`,
  switch branches, follow the default branch automatically.
- **Full file operations** — upload (multi-file + drag and drop), download,
  create folder, rename, recursive delete, list and grid views.
- **Device-code OAuth** — no client secret, no redirect juggling; enabled in this
  repo, works in the APK directly and on the web through the broker.
- **Honest limits** — GitHub's Contents API caps a single file at 100 MB;
  `reve` warns at 95 MB before wasting an upload.
- **Material 3** — light/dark/auto themes, responsive layout, keyboard friendly.

---

## Quick start (web)

1. Clone the repo or download `index.html`.
2. Open the file, or serve it: `python3 -m http.server 8080`.
3. Click **Add account**, paste a GitHub token, pick a repository.

### Host on GitHub Pages

1. Push this repo to GitHub.
2. **Settings → Pages → Source: Deploy from a branch → `main` / `/ (root)`**.
3. Visit `https://<user>.github.io/reve/` (this repo already serves
   `https://sofikuw.is-not-a.dev/Reve/`).

`.nojekyll` is already present so no files get filtered.

Live now: <https://sofikuw.is-not-a.dev/Reve/> and
<https://sofikuw.github.io/Reve/>.

### Host on Vercel (web app + OAuth broker)

`vercel.json` + `api/oauth.js` are configured for a same-origin deploy: the
static app is served from the repo root and the OAuth function from `/api/oauth`.
See [OAuth broker](#oauth-broker-optional) for the environment variables.

---

## Authentication

### Personal access token (fastest)

Create a token at <https://github.com/settings/tokens>:

- **Classic**: `repo` scope.
- **Fine-grained**: *Repository permissions → Contents: Read and write*
  (plus *Metadata: Read*), scoped to the repos you want to use.

Paste it into the app. `reve` verifies it against `/user` and stores it locally.

### OAuth

OAuth needs an OAuth App (<https://github.com/settings/developers>). The
**client ID is public**; the **client secret never leaves your backend**.

Both clients use **device flow**: one button copies an 8-character code to your
clipboard, opens <https://github.com/login/device>, and polls until you approve.
Native builds talk to GitHub directly; browsers go through the broker because
GitHub sends no CORS headers for `/login/device/code`.

> The broker still implements the authorization-code (`start` + callback)
> endpoints for custom clients, but the bundled UI no longer needs them — device
> flow requires no client secret.

---

## Device flow

Device flow is **enabled and verified** for this deployment:

| | |
| --- | --- |
| OAuth App client ID | `Ov23liKqKI4YQP1Ie3OQ` (public identifier, not a secret) |
| Baked into | `index.html` (`DEFAULT_CLIENT_ID`) and `lib/config.dart` |
| Actions variable | `OAUTH_CLIENT_ID` (used by both build workflows) |
| Verified | `POST github.com/login/device/code` → user code; broker poll → `authorization_pending` |

No client secret is involved, and the client ID is stored locally after first use
(`localStorage` / Hive), so changing it needs no rebuild.

### Where it works

- **Android APK / desktop** — talks to `github.com` directly. Works out of the box.
- **Web** — GitHub sends no CORS headers for `/login/device/code`, so the browser
  must proxy the two calls through the broker. Until a broker URL is set in
  **Settings**, the web client offers a personal access token instead.

### Deploy the broker (needed once for web device flow)

```bash
cd backend/cloudflare-worker
npm install
npx wrangler login
npx wrangler secret put GITHUB_CLIENT_ID      # Ov23liKqKI4YQP1Ie3OQ
npx wrangler deploy                            # prints https://reve-oauth.<sub>.workers.dev
```

Then open the web app → **Settings** → paste that URL as the *Backend base URL*.
`GITHUB_CLIENT_SECRET` is **not** required for device flow — only for the popup
flow, whose callback URL must be `<broker>/api/oauth` exactly.

## OAuth broker (optional)

Both implementations follow the same contract:

| Request | Result |
| --- | --- |
| `GET /api/oauth?action=start&client_id=…&origin=…&nonce=…` | `302` to GitHub authorize |
| `GET /api/oauth?code=…&state=…` | HTML page that `postMessage`s `{type:'reve:oauth', token, error, state}` to the opener, with a copyable-token fallback |
| `POST /api/oauth` `{code}` | `application/json` exchange (CORS) |
| `GET /api/oauth?action=device_start&client_id=…&scope=repo` | device code + user code (CORS) |
| `POST /api/oauth` `{client_id, device_code}` | token, or `{error:'authorization_pending' \| 'slow_down' \| …}` |
| `GET /api/oauth?action=health` | `{ok:true}` |

`state` is `base64url({o,n,e})` + `.` + `HMAC-SHA256` keyed with
`GITHUB_CLIENT_SECRET`, valid for 10 minutes.

**Device flow needs no secret at all** — only the public client ID. A broker
deployed for device codes alone can run with `GITHUB_CLIENT_ID` only; the
popup flow additionally needs `GITHUB_CLIENT_SECRET`. When `GITHUB_CLIENT_ID`
is set, the broker refuses other client IDs so it cannot be used as an open
relay.

### Option A — Cloudflare Worker

```bash
cd backend/cloudflare-worker
npm install
npx wrangler login

npx wrangler secret put GITHUB_CLIENT_ID      # device flow needs only this
npx wrangler secret put GITHUB_CLIENT_SECRET  # popup flow only
npx wrangler deploy
```

Then set the OAuth App **Authorization callback URL** to
`https://reve-oauth.<your-subdomain>.workers.dev/api/oauth`.

Optional: `ALLOWED_ORIGINS=https://you.github.io` to restrict which origins may
use the broker (defaults to `*`).

### Option B — Vercel

```bash
vercel                    # link the project
vercel env add GITHUB_CLIENT_ID
vercel env add GITHUB_CLIENT_SECRET
vercel --prod
```

Same-origin deploy: callback URL `https://<project>.vercel.app/api/oauth`.

### Live broker

`https://reve-oauth.sofikuw.workers.dev` (worker `reve-oauth`) is deployed and is
the default backend baked into `index.html` and `lib/config.dart`, so neither
client needs setup. `ALLOWED_ORIGINS` must list every origin that calls it:

```bash
npx wrangler deploy          # uses [vars] ALLOWED_ORIGINS from wrangler.toml
npx wrangler secret put GITHUB_CLIENT_ID
```

### Wiring the web app

Account dialog → **OAuth** tab → the client ID and broker URL are pre-filled;
press *Sign in with GitHub*. Both values live in `localStorage`, so a self-hosted
broker only needs the URL pasted in **Settings**.

Verify a deployment with
`curl https://<broker>/api/oauth?action=health` →
`{"ok":true,"configured":…,"service":"reve-oauth"}`.

---

## Build the Android APK

### GitHub Actions (recommended)

`.github/workflows/build-android.yml` builds a release APK on every push to
`main`, on tags, or manually from **Actions → Build Android APK → Run workflow**.

- Optional repository variable `OAUTH_CLIENT_ID` enables the device flow.
- The APK is uploaded as the `reve-apk` artifact.

> The first run generates the missing `android/` platform folder with
> `flutter create --platforms=android .`, so nothing extra is committed.

### Locally

```bash
flutter pub get
flutter create --platforms=android --org com.sofikuw --project-name reve .
# release builds need the permission the template omits:
#   add <uses-permission android:name="android.permission.INTERNET"/>
#   to android/app/src/main/AndroidManifest.xml
flutter build apk --release --dart-define=OAUTH_CLIENT_ID=Ov23liKqKI4YQP1Ie3OQ
# build/app/outputs/flutter-apk/app-release.apk
```

> Without that permission a release APK fails with
> `SocketException: Failed host lookup: 'github.com'`. The CI workflow adds it
> automatically.

### Flutter web

```bash
flutter build web --release --dart-define=OAUTH_CLIENT_ID=Iv1.xxxx \
                          --dart-define=OAUTH_BACKEND=https://reve-oauth.example.workers.dev
```

`.github/workflows/deploy-web.yml` uploads `build/web` as an artifact.
The flagship web experience remains the root `index.html`.

---

## How uploads are stored

| Extension group | Folder |
| --- | --- |
| images (png, jpg, gif, webp, svg, …) | `images/` |
| video + audio (mp4, webm, mp3, flac, …) | `media/` |
| documents (pdf, md, json, csv, …) | `documents/` |
| archives (zip, tar, gz, …) | `archives/` |
| source code (dart, ts, go, py, …) | `code/` |
| everything else | `others/` |

Auto-sort applies to the current folder; sharing a filename overwrites the
existing blob by looking up its SHA (409 → retry). Folders are real folders:
`reve` writes a `.gitkeep` so git can track an otherwise empty directory.

---

## Security

- Tokens are stored **locally only** — `localStorage` (web) or app-private
  storage (Flutter/Hive). They are not encrypted at rest on either platform.
- All traffic goes directly to `api.github.com` (plus the optional OAuth broker
  you deploy yourself).
- Use fine-grained tokens limited to storage repositories, and revoke them when
  you stop using a device.
- The OAuth **client secret** belongs in backend environment variables only.
- `reve` never asks for your GitHub password.

Rate limits are shown in the web app; the Contents API allows 5 000 requests per
hour per authenticated user.

---

## Project layout

```
index.html                        standalone web app (HTML + CSS + JS)
api/oauth.js                      Vercel serverless OAuth broker
vercel.json                       same-origin deploy config
backend/cloudflare-worker/        Cloudflare Worker OAuth broker
lib/main.dart                     Flutter entry point (Material 3)
lib/config.dart                   --dart-define configuration
lib/models/                       account + file models
lib/services/github_service.dart  GitHub REST + device flow
lib/providers/reve_provider.dart  app state (accounts, repos, files, uploads)
lib/ui/screens/                   explorer + accounts screens
web/                              Flutter web shell (index.html, manifest)
.github/workflows/                APK + Flutter web builds
```

---

## License

Copyright (C) 2026 the reve contributors.

Licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE).
This program is free software: you can redistribute it and/or modify it under
the terms of the GPL as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.
