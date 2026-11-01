/**
 * BillBox licence server (Cloudflare Pages Functions, at billbox-app.pages.dev/api/…). Two separate worlds:
 *
 *   /api/live/…   the public apps and the website: live Razorpay keys, licences signed with the live key
 *   /api/test/…   the owner's admin (test) apps: Razorpay test mode, licences signed with the test key
 *
 *   GET  /api/<env>/config                         prices, the Razorpay key id (public) and the UPI id for the buy page
 *   POST /api/<env>/order      {plan, email, name, device}         a Razorpay order for that plan
 *   POST /api/<env>/verify     {order_id, payment_id, signature}   checks the payment, returns the licence key
 *   POST /api/<env>/lookup     {email, payment_id}                 the licence key of a payment again
 *   POST /api/<env>/activate   {key, device, name}                 an activation for one device (at most `devices`)
 *   POST /api/<env>/deactivate {key, device}                       frees that device's place
 *   POST /api/<env>/webhook    (Razorpay: payment.captured)         issues the licence even if the buyer closed the page
 *   POST /api/<env>/admin/issue  {plan, email, name, days?, devices?, note?}   (Authorization: Bearer ADMIN_TOKEN)
 *   POST /api/<env>/admin/revoke {id}     GET /api/<env>/admin/list
 *
 * Bindings: KV namespace LICENSES; secrets RZP_KEY_ID_LIVE, RZP_KEY_SECRET_LIVE, RZP_KEY_ID_TEST, RZP_KEY_SECRET_TEST,
 * RZP_WEBHOOK_SECRET (optional), LICENSE_KEY_LIVE, LICENSE_KEY_TEST (Ed25519 private keys, PKCS#8 in base64),
 * ADMIN_TOKEN, UPI_VPA (optional, shown for direct UPI payment).
 *
 * Token: "BB1." + base64url(JSON) + "." + base64url(Ed25519 signature of the part before the second dot). The apps
 * check tokens with the matching public key (backend/src/services/license.js, ios/BillBoxCore/License.swift).
 */

export const PLANS = {
  yearly_inr: { plan: 'yearly', amount: 149900, currency: 'INR', label: 'BillBox — 1 year', days: 365 },
  lifetime_inr: { plan: 'lifetime', amount: 399900, currency: 'INR', label: 'BillBox — lifetime', days: null },
  yearly_usd: { plan: 'yearly', amount: 2900, currency: 'USD', label: 'BillBox — 1 year', days: 365 },
};
const DEVICES = 2;
const DAY = 86400000;
const ACTIVATION_DAYS = 60;

const enc = new TextEncoder();
const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const fromB64url = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4)), (c) => c.charCodeAt(0));
const fromB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');

class Fail extends Error { constructor(status, message, code) { super(message); this.status = status; this.code = code; } }
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'cache-control': 'no-store' } });

// ---------------------------------------------------------------- signing
const keyCache = {};
async function keys(env, which) {
  if (keyCache[which]) return keyCache[which];
  const der = env[which === 'live' ? 'LICENSE_KEY_LIVE' : 'LICENSE_KEY_TEST'];
  if (!der) throw new Fail(500, 'The licence key of this server is not set up yet.');
  const priv = await crypto.subtle.importKey('pkcs8', fromB64(der), { name: 'Ed25519' }, true, ['sign']);
  const jwk = await crypto.subtle.exportKey('jwk', priv);
  const pub = await crypto.subtle.importKey('jwk', { kty: 'OKP', crv: 'Ed25519', x: jwk.x }, { name: 'Ed25519' }, true, ['verify']);
  return (keyCache[which] = { priv, pub, x: jwk.x });
}
async function sign(env, which, payload) {
  const body = 'BB1.' + b64url(enc.encode(JSON.stringify({ ...payload, env: which })));
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, (await keys(env, which)).priv, enc.encode(body));
  return body + '.' + b64url(sig);
}
async function read(env, which, token) {
  const parts = String(token || '').replace(/\s+/g, '').split('.');
  if (parts.length !== 3 || parts[0] !== 'BB1') return null;
  let p;
  try { p = JSON.parse(new TextDecoder().decode(fromB64url(parts[1]))); } catch (_) { return null; }
  if (!p || p.env !== which) return null;
  const ok = await crypto.subtle.verify({ name: 'Ed25519' }, (await keys(env, which)).pub, fromB64url(parts[2]), enc.encode(`${parts[0]}.${parts[1]}`));
  return ok ? p : null;
}
async function hmac(secret, text) {
  const k = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', k, enc.encode(text)));
}
function same(a, b) { if (a.length !== b.length) return false; let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i); return d === 0; }

// ---------------------------------------------------------------- store
const kvGet = async (env, k) => { const v = await env.LICENSES.get(k); return v ? JSON.parse(v) : null; };
const kvPut = (env, k, v) => env.LICENSES.put(k, JSON.stringify(v));

function rzp(env, which) {
  const id = env[which === 'live' ? 'RZP_KEY_ID_LIVE' : 'RZP_KEY_ID_TEST'], secret = env[which === 'live' ? 'RZP_KEY_SECRET_LIVE' : 'RZP_KEY_SECRET_TEST'];
  return { id, secret, auth: 'Basic ' + btoa(`${id}:${secret}`) };
}
async function rzpCall(env, which, method, path, body) {
  const r = rzp(env, which);
  if (!r.id || !r.secret) throw new Fail(503, 'Online payment is not set up yet. Pay by UPI and send the reference to the seller, or try again later.', 'NO_GATEWAY');
  const res = await fetch(`https://api.razorpay.com/v1${path}`, { method, headers: { authorization: r.auth, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) throw new Fail(502, `Razorpay: ${(j.error && j.error.description) || res.status}`);
  return j;
}

const cleanEmail = (e) => String(e || '').trim().toLowerCase().slice(0, 120);
const newId = () => 'L' + Date.now().toString(36).toUpperCase() + Math.random().toString(36).slice(2, 7).toUpperCase();

/** Makes a licence (idempotent per payment: the same payment always gives the same licence). */
async function issue(env, which, { plan, email, name, days, devices, payment, order, note, by }) {
  if (payment) { const had = await kvGet(env, `${which}:payment:${payment}`); if (had) return await kvGet(env, `${which}:licence:${had}`); }
  const id = newId(), now = Date.now();
  const exp = plan === 'lifetime' ? null : now + (Number(days) || 365) * DAY;
  const key = await sign(env, which, { t: 'lic', id, plan, email, name: String(name || '').slice(0, 80), devices: Number(devices) || DEVICES, iss: now, exp });
  const rec = { id, key, plan, email, name: String(name || '').slice(0, 80), exp, devices: Number(devices) || DEVICES, seats: [], revoked: false, payment: payment || '', order: order || '', note: note || '', by: by || 'payment', created: new Date(now).toISOString() };
  await kvPut(env, `${which}:licence:${id}`, rec);
  if (payment) await kvPut(env, `${which}:payment:${payment}`, id);
  if (email) {
    const list = (await kvGet(env, `${which}:email:${email}`)) || [];
    list.push(id); await kvPut(env, `${which}:email:${email}`, list);
  }
  return rec;
}
const out = (rec) => ({ license_key: rec.key, license_id: rec.id, plan: rec.plan, email: rec.email, expires: rec.exp ? new Date(rec.exp).toISOString().slice(0, 10) : null, devices: rec.devices });

// ---------------------------------------------------------------- routes
async function handle(request, env, which, path) {
  const method = request.method;
  const body = method === 'POST' ? await request.clone().json().catch(() => ({})) : {};

  if (path === 'config' && method === 'GET') {
    return json({ env: which, key_id: rzp(env, which).id || '', upi_vpa: env.UPI_VPA || '', devices: DEVICES,
      plans: Object.fromEntries(Object.entries(PLANS).map(([k, p]) => [k, { plan: p.plan, amount: p.amount, currency: p.currency, label: p.label }])) });
  }

  if (path === 'order' && method === 'POST') {
    const p = PLANS[body.plan];
    if (!p) throw new Fail(400, 'Choose a plan.');
    const email = cleanEmail(body.email);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new Fail(400, 'Enter your e-mail address: the licence key is kept for it.');
    const o = await rzpCall(env, which, 'POST', '/orders', { amount: p.amount, currency: p.currency, receipt: `bb_${Date.now()}`,
      notes: { plan_key: body.plan, plan: p.plan, email, name: String(body.name || '').slice(0, 80), device: String(body.device || '').slice(0, 40) } });
    return json({ order_id: o.id, key_id: rzp(env, which).id, amount: o.amount, currency: o.currency, label: p.label, email });
  }

  if (path === 'verify' && method === 'POST') {
    const { order_id, payment_id, signature } = body;
    if (!order_id || !payment_id || !signature) throw new Fail(400, 'The payment details are missing.');
    const expect = await hmac(rzp(env, which).secret || '', `${order_id}|${payment_id}`);
    if (!same(expect, String(signature))) throw new Fail(400, 'The payment could not be confirmed. If money was taken, write to the seller with the payment ID.');
    const o = await rzpCall(env, which, 'GET', `/orders/${encodeURIComponent(order_id)}`);
    const p = PLANS[o.notes && o.notes.plan_key];
    if (!p || o.amount !== p.amount || o.currency !== p.currency) throw new Fail(400, 'The order does not match a BillBox plan.');
    const rec = await issue(env, which, { plan: p.plan, days: p.days, email: o.notes.email, name: o.notes.name, payment: payment_id, order: order_id });
    return json(out(rec));
  }

  if (path === 'webhook' && method === 'POST') {
    const raw = await request.text();
    if (!env.RZP_WEBHOOK_SECRET) return json({ ok: true, skipped: 'no webhook secret' });
    if (!same(await hmac(env.RZP_WEBHOOK_SECRET, raw), String(request.headers.get('x-razorpay-signature') || ''))) throw new Fail(400, 'bad signature');
    const ev = JSON.parse(raw);
    const pay = ev.payload && ev.payload.payment && ev.payload.payment.entity;
    if ((ev.event === 'payment.captured' || ev.event === 'order.paid') && pay && pay.order_id) {
      const o = await rzpCall(env, which, 'GET', `/orders/${encodeURIComponent(pay.order_id)}`);
      const p = PLANS[o.notes && o.notes.plan_key];
      if (p && o.amount === p.amount) await issue(env, which, { plan: p.plan, days: p.days, email: o.notes.email, name: o.notes.name, payment: pay.id, order: o.id });
    }
    return json({ ok: true });
  }

  if (path === 'lookup' && method === 'POST') {
    const id = await kvGet(env, `${which}:payment:${String(body.payment_id || '').trim()}`);
    const rec = id && (await kvGet(env, `${which}:licence:${id}`));
    if (!rec || rec.email !== cleanEmail(body.email)) throw new Fail(404, 'No licence for that e-mail and payment ID.');
    return json(out(rec));
  }

  if ((path === 'activate' || path === 'deactivate') && method === 'POST') {
    const lic = await read(env, which, body.key);
    if (!lic || lic.t !== 'lic') throw new Fail(400, 'That is not a BillBox licence key.');
    const rec = await kvGet(env, `${which}:licence:${lic.id}`);
    if (!rec) throw new Fail(400, 'This licence is not known to the licence server.');
    const dev = String(body.device || '').trim().slice(0, 40);
    if (!dev) throw new Fail(400, 'The device is missing.');
    if (path === 'deactivate') {
      rec.seats = rec.seats.filter((s) => s.dev !== dev); await kvPut(env, `${which}:licence:${rec.id}`, rec);
      return json({ ok: true, seats: rec.seats.length });
    }
    if (rec.revoked) throw new Fail(403, 'This licence was cancelled. Write to the seller if this is a mistake.', 'REVOKED');
    if (rec.exp && rec.exp <= Date.now()) throw new Fail(400, `This licence ran out on ${new Date(rec.exp).toISOString().slice(0, 10)}. Renew it on the website.`, 'EXPIRED');
    const now = Date.now();
    const seat = rec.seats.find((s) => s.dev === dev);
    if (seat) { seat.seen = now; if (body.name) seat.name = String(body.name).slice(0, 60); }
    else {
      if (rec.seats.length >= rec.devices) throw new Fail(409, `This licence is already used on ${rec.devices} devices. Remove it from one of them (Settings › Licence) first.`, 'SEATS');
      rec.seats.push({ dev, name: String(body.name || '').slice(0, 60), since: now, seen: now });
    }
    await kvPut(env, `${which}:licence:${rec.id}`, rec);
    const exp = Math.min(rec.exp || Infinity, now + ACTIVATION_DAYS * DAY);
    const activation = await sign(env, which, { t: 'act', lic: rec.id, dev, plan: rec.plan, email: rec.email, name: rec.name, lexp: rec.exp, exp });
    return json({ activation, seats: rec.seats.length, devices: rec.devices });
  }

  if (path.startsWith('admin/')) {
    const tok = String(request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (!env.ADMIN_TOKEN || !same(tok, env.ADMIN_TOKEN)) throw new Fail(401, 'Not allowed.');
    const what = path.slice(6);
    if (what === 'issue' && method === 'POST') {
      if (!['yearly', 'lifetime'].includes(body.plan)) throw new Fail(400, 'plan must be yearly or lifetime');
      const rec = await issue(env, which, { plan: body.plan, days: body.days, devices: body.devices, email: cleanEmail(body.email), name: body.name, note: body.note, by: 'admin' });
      return json(out(rec));
    }
    if (what === 'revoke' && method === 'POST') {
      const rec = await kvGet(env, `${which}:licence:${body.id}`);
      if (!rec) throw new Fail(404, 'No such licence.');
      rec.revoked = body.undo ? false : true; await kvPut(env, `${which}:licence:${rec.id}`, rec);
      return json({ ok: true, revoked: rec.revoked });
    }
    if (what === 'list' && method === 'GET') {
      const l = await env.LICENSES.list({ prefix: `${which}:licence:` });
      const rows = [];
      for (const k of l.keys.slice(0, 500)) { const r = await kvGet(env, k.name); if (r) rows.push({ ...r, key: undefined, seats: r.seats.length }); }
      return json(rows.sort((a, b) => (a.created < b.created ? 1 : -1)));
    }
  }
  throw new Fail(404, 'Not found');
}

export async function onRequest(context) {
  const { request, env, params } = context;
  if (request.method === 'OPTIONS') return new Response(null, { headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type, authorization', 'access-control-allow-methods': 'GET, POST' } });
  const segs = [].concat(params.path || []);
  const which = segs[0];
  if (which !== 'live' && which !== 'test') return json({ error: 'Not found' }, 404);
  try {
    if (!env.LICENSES) throw new Fail(503, 'The licence store is not set up yet.');
    return await handle(request, env, which, segs.slice(1).join('/'));
  } catch (e) {
    if (e instanceof Fail) return json({ error: e.message, code: e.code }, e.status);
    return json({ error: 'The licence server had a problem. Try again in a minute.' }, 500);
  }
}
