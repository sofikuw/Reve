/**
 * reve OAuth broker — Vercel serverless function.
 *
 * Route: /api/oauth
 *
 *   GET  /api/oauth?action=start&client_id=…&origin=…&nonce=…
 *        -> 302 to github.com/login/oauth/authorize
 *   GET  /api/oauth?code=…&state=…
 *        -> GitHub callback: exchanges the code and hands the token to the
 *           opener window with postMessage (or shows it for manual copy).
 *   POST /api/oauth  { "code": "…" }
 *        -> JSON token exchange for native clients (CORS enabled).
 *
 *   Device flow (public client, no secret required):
 *   GET  /api/oauth?action=device_start&client_id=…&scope=repo
 *        -> JSON { device_code, user_code, verification_uri, interval, expires_in }
 *   POST /api/oauth  { "client_id": "…", "device_code": "…" }
 *        -> JSON { access_token } or { error: 'authorization_pending' | … }
 *
 *   Browsers cannot call github.com/login/device/code directly (no CORS), so the
 *   web client proxies those two calls through this function. Native clients
 *   (Android/iOS) may call GitHub directly with the same client_id.
 *
 * Environment variables (Vercel → Project → Settings → Environment Variables):
 *   GITHUB_CLIENT_ID      required
 *   GITHUB_CLIENT_SECRET  required
 *   ALLOWED_ORIGINS       optional, comma separated. Defaults to '*'.
 *
 * Copyright (C) 2026  reve contributors — GPL-3.0-or-later
 */

const GH_AUTHORIZE = 'https://github.com/login/oauth/authorize';
const GH_TOKEN = 'https://github.com/login/oauth/access_token';
const GH_DEVICE_CODE = 'https://github.com/login/device/code';
const STATE_TTL_MS = 10 * 60 * 1000;

const enc = encodeURIComponent;

function base64url(bytes) {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return Buffer.from(s, 'binary').toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64url(str) {
  return Buffer.from(str.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

async function sign(payload, secret) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload));
  return base64url(sig);
}

function sameString(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function makeState({ origin, nonce }, secret) {
  const body = base64url(Buffer.from(JSON.stringify({
    o: origin,
    n: nonce,
    e: Date.now() + STATE_TTL_MS,
  }), 'utf8'));
  return `${body}.${await sign(body, secret)}`;
}

async function readState(state, secret) {
  if (!state || typeof state !== 'string') throw new Error('Missing state');
  const dot = state.lastIndexOf('.');
  if (dot < 1) throw new Error('Malformed state');
  const body = state.slice(0, dot);
  const sig = state.slice(dot + 1);
  if (!sameString(sig, await sign(body, secret))) throw new Error('Bad state signature');
  const payload = JSON.parse(fromBase64url(body).toString('utf8'));
  if (!payload.e || Date.now() > payload.e) throw new Error('State expired, please retry');
  if (!payload.o || !payload.n) throw new Error('Incomplete state');
  return payload;
}

function allowedOrigins(env) {
  const raw = (env.ALLOWED_ORIGINS || '*').trim();
  if (raw === '*') return '*';
  return raw.split(',').map((o) => o.trim().replace(/\/+$/, '')).filter(Boolean);
}

function corsOrigin(req, env) {
  const allowed = allowedOrigins(env);
  const origin = (req.headers.origin || '').replace(/\/+$/, '');
  if (allowed === '*') return origin || '*';
  return allowed.includes(origin) ? origin : allowed[0] || '';
}

async function exchangeCode(code, redirectUri, env) {
  const res = await fetch(GH_TOKEN, {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: env.GITHUB_CLIENT_ID,
      client_secret: env.GITHUB_CLIENT_SECRET,
      code,
      redirect_uri: redirectUri,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.error) {
    throw new Error(data.error_description || data.error || `GitHub token exchange failed (${res.status})`);
  }
  if (!data.access_token) throw new Error('GitHub did not return an access token');
  return data;
}

async function deviceStart(clientId, scope, env) {
  const res = await fetch(GH_DEVICE_CODE, {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_id: clientId, scope: scope || 'repo' }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.error) {
    throw new Error(data.error_description || data.error || `Could not start device flow (${res.status})`);
  }
  return {
    device_code: data.device_code,
    user_code: data.user_code,
    verification_uri: data.verification_uri || 'https://github.com/login/device',
    interval: data.interval || 5,
    expires_in: data.expires_in || 900,
  };
}

async function devicePoll(clientId, deviceCode, env) {
  const res = await fetch(GH_TOKEN, {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: clientId,
      device_code: deviceCode,
      grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (data.access_token) {
    return { access_token: data.access_token, token_type: data.token_type, scope: data.scope };
  }
  return { error: data.error || 'unknown_error', error_description: data.error_description || '' };
}

function deviceErrorHint(message) {
  if (/not found/i.test(message)) {
    return 'GitHub returned 404 for this client ID. Check the OAuth App client ID and make sure "Device flow" is enabled in its settings.';
  }
  return message;
}

function clientIdAllowed(clientId, env) {
  if (!env.GITHUB_CLIENT_ID) return true;
  return clientId === env.GITHUB_CLIENT_ID;
}

function readJsonBody(body) {
  if (!body) return {};
  if (typeof body === 'object') return body;
  try {
    return JSON.parse(body);
  } catch (_) {
    return {};
  }
}

function handoffHtml({ token, error, nonce, origin }) {
  const payload = JSON.stringify({ type: 'reve:oauth', token: token || '', error: error || '', state: nonce || '' });
  const target = JSON.stringify(origin || '');
  const safeToken = JSON.stringify(token || '');
  return `<!doctype html>
<meta charset="utf-8">
<meta name="referrer" content="no-referrer">
<title>reve — ${error ? 'sign-in failed' : 'signing you in'}</title>
<style>
  body{margin:0;min-height:100vh;display:grid;place-items:center;background:#101014;color:#e5e1e9;
       font:14px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;padding:24px;text-align:center}
  .box{max-width:440px;width:100%}
  h1{font-size:17px;margin:0 0 8px;font-weight:650}
  p{color:#c8c5d0;font-size:13px;margin:0 0 16px}
  textarea{width:100%;height:86px;background:#1c1c22;color:#e5e1e9;border:1px solid #46464f;
           border-radius:10px;padding:10px;font:12px/1.5 ui-monospace,Menlo,Consolas,monospace;resize:vertical}
  .dot{display:inline-block;width:9px;height:9px;border-radius:50%;background:#3ecf8e;margin-right:7px}
  .err{background:#93000a;color:#ffdad6;border-radius:10px;padding:10px 12px;font-size:12.5px}
  [hidden]{display:none}
</style>
<div class="box">
  <h1 id="title"><span class="dot"></span>Completing sign-in…</h1>
  <p id="msg">This window closes automatically.</p>
  <div id="fallback" hidden>
    <p>Your browser blocked the hand-off. Copy this token and paste it in
       <b>reve → Accounts → OAuth → Paste an OAuth access token</b>.</p>
    <textarea readonly id="tok"></textarea>
  </div>
  <div class="err" id="err" hidden></div>
</div>
<script>
  var message = ${payload};
  var targetOrigin = ${target};
  var token = ${safeToken};
  var delivered = false;
  try {
    if (window.opener && !window.opener.closed) {
      window.opener.postMessage(message, targetOrigin || '*');
      delivered = true;
    }
  } catch (e) { delivered = false; }

  if (message.error) {
    document.getElementById('title').textContent = 'Sign-in failed';
    document.getElementById('msg').remove();
    var box = document.getElementById('err');
    box.hidden = false;
    box.textContent = message.error;
  } else if (!delivered) {
    document.getElementById('title').textContent = 'Signed in — manual step needed';
    document.getElementById('msg').hidden = true;
    document.getElementById('fallback').hidden = false;
    document.getElementById('tok').value = token;
    document.getElementById('tok').select();
  } else {
    setTimeout(function () { try { window.close(); } catch (e) {} }, 700);
  }
</script>`;
}

module.exports = async function handler(req, res) {
  const env = process.env;
  const url = new URL(req.url, `https://${req.headers.host || 'localhost'}`);
  const q = url.searchParams;

  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Content-Type-Options', 'nosniff');

  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Origin', corsOrigin(req, env));
    res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    res.setHeader('Access-Control-Max-Age', '86400');
    return res.status(204).end();
  }

  const configured = Boolean(env.GITHUB_CLIENT_ID && env.GITHUB_CLIENT_SECRET);
  const callbackUri = `${url.origin}/api/oauth`;

  try {
    /* ---------- health ---------- */
    if (req.method === 'GET' && q.get('action') === 'health') {
      return res.status(200).json({ ok: true, configured, service: 'reve-oauth' });
    }

    /* ---------- device flow: start ---------- */
    if (req.method === 'GET' && q.get('action') === 'device_start') {
      res.setHeader('Access-Control-Allow-Origin', corsOrigin(req, env));
      const clientId = q.get('client_id') || env.GITHUB_CLIENT_ID || '';
      if (!clientId) return res.status(400).json({ error: 'client_id is required' });
      if (!clientIdAllowed(clientId, env)) {
        return res.status(403).json({ error: 'This broker only serves the configured GITHUB_CLIENT_ID' });
      }
      try {
        return res.status(200).json(await deviceStart(clientId, q.get('scope') || 'repo', env));
      } catch (e) {
        return res.status(400).json({ error: deviceErrorHint(e.message) });
      }
    }

    /* ---------- start ---------- */
    if (req.method === 'GET' && q.get('action') === 'start') {
      if (!configured) {
        return res.status(500).json({ error: 'Server is missing GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET' });
      }
      const clientId = q.get('client_id') || env.GITHUB_CLIENT_ID;
      const origin = (q.get('origin') || '').replace(/\/+$/, '');
      const nonce = q.get('nonce') || '';
      if (!origin || !nonce) return res.status(400).json({ error: 'origin and nonce are required' });

      const allow = allowedOrigins(env);
      if (allow !== '*' && !allow.includes(origin)) {
        return res.status(403).json({ error: `Origin ${origin} is not in ALLOWED_ORIGINS` });
      }

      const state = await makeState({ origin, nonce }, env.GITHUB_CLIENT_SECRET);
      const target = `${GH_AUTHORIZE}?client_id=${enc(clientId)}` +
        `&redirect_uri=${enc(callbackUri)}` +
        `&scope=${enc(q.get('scope') || 'repo')}` +
        `&state=${enc(state)}`;
      res.setHeader('Location', target);
      return res.status(302).end();
    }

    /* ---------- callback ---------- */
    if (req.method === 'GET' && q.get('code')) {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      let state;
      try {
        state = await readState(q.get('state'), env.GITHUB_CLIENT_SECRET);
      } catch (e) {
        return res.status(400).send(handoffHtml({ error: e.message }));
      }
      if (q.get('error')) {
        return res.status(200).send(handoffHtml({ error: q.get('error_description') || q.get('error'), nonce: state.n, origin: state.o }));
      }
      try {
        const data = await exchangeCode(q.get('code'), callbackUri, env);
        return res.status(200).send(handoffHtml({ token: data.access_token, nonce: state.n, origin: state.o }));
      } catch (e) {
        return res.status(200).send(handoffHtml({ error: e.message, nonce: state.n, origin: state.o }));
      }
    }

    /* ---------- JSON endpoints for native / browser clients ---------- */
    if (req.method === 'POST') {
      res.setHeader('Access-Control-Allow-Origin', corsOrigin(req, env));
      const body = readJsonBody(req.body);

      // Device-flow polling needs no secret, only the public client id.
      if (body.device_code) {
        const clientId = body.client_id || env.GITHUB_CLIENT_ID || q.get('client_id') || '';
        if (!clientId) return res.status(400).json({ error: 'client_id is required' });
        if (!clientIdAllowed(clientId, env)) {
          return res.status(403).json({ error: 'This broker only serves the configured GITHUB_CLIENT_ID' });
        }
        return res.status(200).json(await devicePoll(clientId, body.device_code, env));
      }

      if (!configured) return res.status(500).json({ error: 'Server is not configured' });
      const code = body.code || q.get('code');
      if (!code) return res.status(400).json({ error: 'code or device_code is required' });
      const data = await exchangeCode(code, body.redirect_uri || callbackUri, env);
      return res.status(200).json({
        access_token: data.access_token,
        token_type: data.token_type,
        scope: data.scope,
      });
    }

    /* ---------- docs ---------- */
    if (req.method === 'GET') {
      return res.status(200).json({
        service: 'reve-oauth',
        configured,
        endpoints: {
          start: '/api/oauth?action=start&client_id=…&origin=…&nonce=…',
          callback: '/api/oauth (register this as the OAuth App callback URL)',
          exchange: 'POST /api/oauth {"code":"…"}',
          device_start: '/api/oauth?action=device_start&client_id=…&scope=repo',
          device_poll: 'POST /api/oauth {"client_id":"…","device_code":"…"}',
          health: '/api/oauth?action=health',
        },
      });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (e) {
    return res.status(500).json({ error: e.message || 'Unexpected server error' });
  }
};
