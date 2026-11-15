<p align="center"><img src="assets/icon-192.png" width="104" height="104" alt="reve logo"></p>

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
  Sign in with a personal access token, or with GitHub's device flow (one button,
  a copied code, no token to paste).
- **Downloads with progress** — the same thin bar that tracks uploads reports
  each download byte-for-byte, on the web and in the app. Files are read through
  the API, so private repositories work and the bar is real, not a spinner.
- **Smart auto-sorting uploads** — files are filed into `images/`, `documents/`,
  `media/`, `archives/`, `code/`, `others/` based on extension (toggleable).
- **Fast folder navigation** — listings are cached per branch+path, in-flight
  requests are de-duped, folders are prefetched on hover and the browser
  back/forward buttons (and a shareable `#/folder` URL) work without refetching.
- **Rich previews** — every file gets a viewer. Images (pinch/wheel zoom, pan,
  swipe through the folder), video and audio streamed by the platform player,
  Markdown, pretty-printed JSON, CSV/TSV tables, fonts, source and plain text,
  PDF, plus a hex dump for anything else. Photos, videos and songs the decoder
  rejects still get an inline card with the format badge, size, *Save* and
  *Open in a new tab* instead of a dump.
- **Repository management** — create public/private repos with `auto_init`,
  switch branches, follow the default branch automatically.
- **Full file operations** — upload (multi-file + drag and drop), download,
  create folder, rename, recursive delete, list and grid views.
- **Device-code OAuth** — no client secret, no redirect juggling; enabled in this
  repo, works in the APK directly and on the web through the broker.
- **In-app updates** — the APK compares itself with the published releases on
  start-up and on every refresh, with a switch for alpha/beta builds.
- **Resilient networking** — Android builds retry a failed `api.github.com`
  lookup through DNS-over-HTTPS, which fixes the `Failed host lookup` error on
  phones whose private DNS or VPN breaks name resolution.
- **Honest limits** — GitHub's Contents API caps a single file at 100 MB;
  `reve` warns at 95 MB before wasting an upload.
- **Material 3** — light/dark/auto themes, responsive layout, keyboard friendly.

### Brand assets

One artwork file is the source of truth: put the PNG at
`assets/logo.png` (the script falls back to `assets/icon.png`) and run

```bash
python3 tools/make_icons.py
```

It resizes **those exact pixels** — no redraw, no re-trace — into
`assets/icon.png` (1024 store art), `icon-512.png`/`icon-192.png` (app + README),
`assets/android/mipmap-*/ic_launcher.png` and `ic_launcher_foreground.png`, the adaptive-icon XML plus its background colour
sampled from the artwork's corners, and `web/icons/` including the maskable
variants. Android therefore gets a proper adaptive icon, so every launcher mask
shape (circle, squircle, rounded square) crops cleanly. The web client inlines
the 192 px PNG as its brand mark and the 32 px one as its favicon, so
`index.html` stays a single self-contained file.

---

## Quick start (web)

1. Clone the repo or download `index.html`.
2. Open the file, or serve it: `python3 -m http.server 8080`.
3. Click **Sign in with GitHub**, press the code that is copied for you, and
   pick a repository.

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

Two ways in, both in the app and in `index.html`:

1. **Personal access token.** Paste a classic token with the `repo` scope, or a
   fine-grained token with *Contents: Read and write*, into the sign-in sheet.
   The token never leaves the device (Hive in the app, `localStorage` in the
   browser).
2. **Sign in with GitHub (device flow).** One button copies an 8-character code
   to the clipboard, opens <https://github.com/login/device> and polls until you
   approve. Native builds talk to GitHub directly; browsers go through the
   broker because GitHub sends no CORS headers for `/login/device/code`.

OAuth needs an OAuth App (<https://github.com/settings/developers>). The
**client ID is public** and is baked into the build (`DEFAULT_CLIENT_ID` in
`index.html`, `AppConfig.oauthClientId` in the app); the **client secret never
leaves the backend**, and the device flow does not need one at all.

> The broker still implements the authorization-code (`start` + callback)
> endpoints for custom clients, but the bundled UI no longer needs them.

---

## Device flow

Device flow is **enabled and verified** for this deployment:

| | |
| --- | --- |
| OAuth App client ID | `Ov23liKqKI4YQP1Ie3OQ` (public identifier, not a secret) |
| Baked into | `index.html` (`DEFAULT_CLIENT_ID`) and `lib/config.dart` |
| Actions variable | `OAUTH_CLIENT_ID` (used by both build workflows) |
| Verified | `POST github.com/login/device/code` → user code; broker poll → `authorization_pending` |

No client secret is involved. The client ID is compile-time configuration
(`--dart-define=OAUTH_CLIENT_ID`), so swapping OAuth Apps means rebuilding; the
Settings sheet only holds the broker URL.

### Where it works

- **Android APK / desktop** — talks to `github.com` directly. Works out of the box.
- **Web** — GitHub sends no CORS headers for `/login/device/code`, so the browser
  must proxy the two calls through the broker. A default broker is baked into
  `index.html`, so this works without any setup.

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

Account dialog → **Sign in with GitHub** → the client ID and broker URL are
pre-filled; press the button. Both values live in `localStorage`, so a
self-hosted broker only needs the URL pasted in **Settings**.

Verify a deployment with
`curl https://<broker>/api/oauth?action=health` →
`{"ok":true,"configured":…,"service":"reve-oauth"}`.

---

## Build the Android APK

### GitHub Actions (recommended)

**Actions → Release Android APKs → Run workflow** builds split APKs and
publishes them as a GitHub release. Three inputs:

| Input | Meaning |
| --- | --- |
| `release_channel` | `alpha`, `beta` or `stable` — alpha/beta are marked as pre-releases, stable becomes *latest* |
| `version` | version **name**, e.g. `1.0.0`; blank uses `pubspec.yaml`. Passed as `--build-name`, so the pubspec is never edited |
| `version_code` | Android version code; blank derives `(major*10000 + minor*100 + patch) * 10000 + rank*1000 + build` (see below) |

Each run numbers itself per version **and** channel (`#001`, `#002`, …) by
looking at the existing tags, so the release title always says which build is
newest:

```
v1.0.0-alpha.001   release "reve 1.0.0 · alpha #001"   pre-release
v1.0.0-alpha.002   release "reve 1.0.0 · alpha #002"   pre-release
v1.0.0-beta.001    release "reve 1.0.0 · beta #001"    pre-release
v1.0.0-stable.001  release "reve 1.0.0 · stable #001"  latest
```

Every release carries three APKs — install the one matching the phone's CPU:

```
reve-1.0.0-beta-001-arm64-v8a.apk     almost every phone from ~2016 on
reve-1.0.0-beta-001-armeabi-v7a.apk   older 32-bit phones
reve-1.0.0-beta-001-x86_64.apk        emulators and Intel tablets
```

The channel rank (alpha 0, beta 1, stable 2) is baked into the version code, so
stable installs over beta and beta over alpha of the same version instead of
being rejected as a downgrade.

Flutter then adds its own ABI offset on top of `--build-number` — `armeabi-v7a`
+1000, `arm64-v8a` +2000, `x86_64` +4000 — so each APK carries a slightly
different code. The workflow reads the real one back with `aapt2 dump badging`
and lists it per APK in the release notes, rather than quoting the number it
computed.

- Optional repository variable `OAUTH_CLIENT_ID` enables the device flow.
- Required repository secret `ANDROID_KEYSTORE_B64`: a base64 PKCS12 keystore
  written to `~/.android/debug.keystore` before the build. Every release must be
  signed with the **same** key, otherwise Android rejects the new APK over the
  old one with "app not installed". The workflow publishes the signing
  certificate's SHA-256 in the release notes, so a mismatch is visible at a
  glance. Create the key once:

  ```bash
  keytool -genkeypair -keystore debug.keystore -storetype PKCS12 \
    -storepass android -keypass android -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10950 \
    -dname "CN=Android Debug,O=Android,C=US"
  base64 -w0 debug.keystore   # → ANDROID_KEYSTORE_B64
  ```

- The first run generates the missing `android/` platform folder with
  `flutter create --platforms=android .`, so nothing extra is committed.

### Locally

```bash
flutter pub get
flutter create --platforms=android --org com.sofikuw --project-name reve .
# swap the Flutter launcher logo for reve's (mipmaps + adaptive-icon XML):
cp -r assets/android/. android/app/src/main/res/
# release builds need the permission the template omits:
#   add <uses-permission android:name="android.permission.INTERNET"/>
#   to android/app/src/main/AndroidManifest.xml
flutter build apk --release --dart-define=OAUTH_CLIENT_ID=Ov23liKqKI4YQP1Ie3OQ
# build/app/outputs/flutter-apk/app-release.apk
```

> Without that permission a release APK fails with
> `SocketException: Failed host lookup: 'github.com'`. The CI workflow adds it
> automatically, and `lib/services/dns_fallback_io.dart` retries a lookup that
> still fails through DNS-over-HTTPS.

### Flutter web

```bash
flutter build web --release --dart-define=OAUTH_CLIENT_ID=Iv1.xxxx \
                          --dart-define=OAUTH_BACKEND=https://reve-oauth.example.workers.dev
```

`.github/workflows/deploy-web.yml` uploads `build/web` as an artifact.
The flagship web experience remains the root `index.html`.

---

## In-app updates

The app knows its own version (`--dart-define=APP_VERSION` / `APP_BUILD`, baked
in by the release workflow) and asks GitHub for the published releases on
start-up and on every refresh. When something newer exists, a snackbar offers
*Get it*, and the overflow menu grows an *Update …* entry.

**Updates → Beta and alpha builds** switches the channel:

| Switch | Sees |
| --- | --- |
| off | stable releases only |
| on | alpha + beta + stable, newest of them wins |

Comparison is semver first, then channel (alpha < beta < stable), then build
number, so a stable `1.3.0` beats `1.3.0-beta.004`, which beats
`1.3.0-alpha.004`. *Download* opens the release page in the browser; pick the
APK that matches the phone's CPU and it installs over the current build without
touching accounts, as long as both builds were signed with the same key (see
`ANDROID_KEYSTORE_B64` above).

`index.html` stays a single static file; the update check lives only in the
Flutter app.

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
lib/services/github_service.dart  GitHub REST, byte reads, streamed uploads
lib/services/dns_fallback*.dart   DNS-over-HTTPS retry for native builds
lib/providers/reve_provider.dart  app state (accounts, repos, files, progress)
lib/ui/screens/                   explorer, accounts and preview screens
tools/make_icons.py               regenerates every icon from one PNG
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
