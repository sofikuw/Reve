/**
 * reve OAuth broker — Cloudflare Worker.
 *
 * Same contract as api/oauth.js (Vercel), so the web app can point at either:
 *
 *   GET  /api/oauth?action=start&client_id=…&origin=…&nonce=…
 *   GET  /api/oauth?code=…&state=…          (GitHub callback)
 *   POST /api/oauth  { "code": "…" }        (native clients, CORS)
 *   GET  /api/oauth?action=health
 *
 * Configure with wrangler secrets:
 *   wrangler secret put GITHUB_CLIENT_ID
 *   wrangler secret put GITHUB_CLIENT_SECRET
 * and optionally:
 *   wrangler secret put ALLOWED_ORIGINS     # https://me.github.io,https://reve.vercel.app
 *
 * Register  https://<worker-host>/api/oauth  as the OAuth App callback URL.
 *
 * Copyright (C) 2026  reve contributors — GPL-3.0-or-later
 */

const GH_AUTHORIZE = 'https://github.com/login/oauth/authorize';
const GH_TOKEN = 'https://github.com/login/oauth/access_token';
const STATE_TTL_MS = 10 * 60 * 1000;

const enc = encodeURIComponent;

function b64urlFromBytes(bytes) {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlEncodeText(text) {
  return b64urlFromBytes(new TextEncoder().encode(text));
}

function b64urlDecodeText(str) {
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
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
  return b64urlFromBytes(sig);
}

function sameString(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function makeState({ origin, nonce }, secret) {
  const body = b64urlEncodeText(JSON.stringify({ o: origin, n: nonce, e: Date.now() + STATE_TTL_MS }));
  return `${body}.${await sign(body, secret)}`;
}

async function readState(state, secret) {
  if (!state) throw new Error('Missing state');
  const dot = state.lastIndexOf('.');
  if (dot < 1) throw new Error('Malformed state');
  const body = state.slice(0, dot);
  if (!sameString(state.slice(dot + 1), await sign(body, secret))) throw new Error('Bad state signature');
  const payload = JSON.parse(b64urlDecodeText(body));
  if (!payload.e || Date.now() > payload.e) throw new Error('State expired, please retry');
  if (!payload.o || !payload.n) throw new Error('Incomplete state');
  return payload;
}

function allowedOrigins(env) {
  const raw = (env.ALLOWED_ORIGINS || '*').trim();
  if (raw === '*') return '*';
  return raw.split(',').map((o) => o.trim().replace(/\/+$/, '')).filter(Boolean);
}

function corsOrigin(request, env) {
  const allowed = allowedOrigins(env);
  const origin = (request.headers.get('Origin') || '').replace(/\/+$/, '');
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

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      ...extra,
    },
  });
}

function handoffHtml({ token, error, nonce, origin }) {
  const payload = JSON.stringify({ type: 'reve:oauth', token: token || '', error: error || '', state: nonce || '' });
  const target = JSON.stringify(origin || '');
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
  var token = ${JSON.stringify(token || '')};
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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const q = url.searchParams;

    if (url.pathname !== '/api/oauth' && url.pathname !== '/') {
      return json({ error: 'Not found', hint: 'Use /api/oauth' }, 404);
    }

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': corsOrigin(request, env),
          'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    const configured = Boolean(env.GITHUB_CLIENT_ID && env.GITHUB_CLIENT_SECRET);
    const callbackUri = `${url.origin}/api/oauth`;

    try {
      /* health */
      if (request.method === 'GET' && q.get('action') === 'health') {
        return json({ ok: true, configured, service: 'reve-oauth' });
      }

      /* start */
      if (request.method === 'GET' && q.get('action') === 'start') {
        if (!configured) return json({ error: 'Worker is missing GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET' }, 500);

        const clientId = q.get('client_id') || env.GITHUB_CLIENT_ID;
        const origin = (q.get('origin') || '').replace(/\/+$/, '');
        const nonce = q.get('nonce') || '';
        if (!origin || !nonce) return json({ error: 'origin and nonce are required' }, 400);

        const allow = allowedOrigins(env);
        if (allow !== '*' && !allow.includes(origin)) {
          return json({ error: `Origin ${origin} is not in ALLOWED_ORIGINS` }, 403);
        }

        const state = await makeState({ origin, nonce }, env.GITHUB_CLIENT_SECRET);
        const target = `${GH_AUTHORIZE}?client_id=${enc(clientId)}` +
          `&redirect_uri=${enc(callbackUri)}` +
          `&scope=${enc(q.get('scope') || 'repo')}` +
          `&state=${enc(state)}`;
        return Response.redirect(target, 302);
      }

      /* callback */
      if (request.method === 'GET' && q.get('code')) {
        const html = (body) => new Response(body, {
          status: 200,
          headers: {
            'Content-Type': 'text/html; charset=utf-8',
            'Cache-Control': 'no-store',
            'Referrer-Policy': 'no-referrer',
            'X-Content-Type-Options': 'nosniff',
          },
        });

        let state;
        try {
          state = await readState(q.get('state'), env.GITHUB_CLIENT_SECRET);
        } catch (e) {
          return new Response(handoffHtml({ error: e.message }), {
            status: 400,
            headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
          });
        }

        if (q.get('error')) {
          return html(handoffHtml({ error: q.get('error_description') || q.get('error'), nonce: state.n, origin: state.o }));
        }

        try {
          const data = await exchangeCode(q.get('code'), callbackUri, env);
          return html(handoffHtml({ token: data.access_token, nonce: state.n, origin: state.o }));
        } catch (e) {
          return html(handoffHtml({ error: e.message, nonce: state.n, origin: state.o }));
        }
      }

      /* JSON exchange for native clients */
      if (request.method === 'POST') {
        const cors = { 'Access-Control-Allow-Origin': corsOrigin(request, env) };
        if (!configured) return json({ error: 'Worker is not configured' }, 500, cors);
        const body = await request.json().catch(() => ({}));
        const code = body.code || q.get('code');
        if (!code) return json({ error: 'code is required' }, 400, cors);
        const data = await exchangeCode(code, body.redirect_uri || callbackUri, env);
        return json({
          access_token: data.access_token,
          token_type: data.token_type,
          scope: data.scope,
        }, 200, cors);
      }

      /* docs */
      if (request.method === 'GET') {
        return json({
          service: 'reve-oauth',
          configured,
          endpoints: {
            start: '/api/oauth?action=start&client_id=…&origin=…&nonce=…',
            callback: '/api/oauth (register this as the OAuth App callback URL)',
            exchange: 'POST /api/oauth {"code":"…"}',
            health: '/api/oauth?action=health',
          },
        });
      }

      return json({ error: 'Method not allowed' }, 405);
    } catch (e) {
      return json({ error: e.message || 'Unexpected server error' }, 500);
    }
  },
};
