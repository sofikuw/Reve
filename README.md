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
3. Visit `https://<user>.github.io/reve/`.

`.nojekyll` is already present so no files get filtered.

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

Three supported ways to obtain a token:

1. **Device flow** (Flutter app, Android) — no backend and no secret required.
   Enable *Device flow* in the OAuth App settings and build with
   `--dart-define=OAUTH_CLIENT_ID=Iv1.xxxx`. The app shows a code, you approve
   it at <https://github.com/login/device>.
2. **Popup broker** (web app) — a tiny serverless function performs the
   `code → token` exchange and `postMessage`s the token back to the opener.
   This is the full click-through experience.
3. **Token paste** — paste an OAuth access token (`gho_…`) anywhere the device
   flow is unavailable (e.g. Flutter web).

> GitHub does not allow browser-side `code → token` exchange, which is exactly
> why the broker exists. It is stateless and does not log tokens.

---

## OAuth broker (optional)

Both implementations follow the same contract:

| Request | Result |
| --- | --- |
| `GET /api/oauth?action=start&client_id=…&origin=…&nonce=…` | `302` to GitHub authorize |
| `GET /api/oauth?code=…&state=…` | HTML page that `postMessage`s `{type:'reve:oauth', token, error, state}` to the opener, with a copyable-token fallback |
| `POST /api/oauth` `{code}` | `application/json` exchange (CORS) |
| `GET /api/oauth?action=health` | `{ok:true}` |

`state` is `base64url({o,n,e})` + `.` + `HMAC-SHA256` keyed with
`GITHUB_CLIENT_SECRET`, valid for 10 minutes.

### Option A — Cloudflare Worker

```bash
cd backend/cloudflare-worker
npm install
npx wrangler login

# public vars
#   GITHUB_CLIENT_ID  in wrangler.toml [vars]
# secret
npx wrangler secret put GITHUB_CLIENT_SECRET

npm run deploy
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

### Wiring the web app

Account dialog → **OAuth** tab → set the **broker URL** and **client ID**
(stored in `localStorage`), then press *Sign in with GitHub*.

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
flutter build apk --release --dart-define=OAUTH_CLIENT_ID=Iv1.xxxx
# build/app/outputs/flutter-apk/app-release.apk
```

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
