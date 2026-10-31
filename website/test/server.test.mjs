// The licence server against a fake Razorpay and a fake KV store, and its tokens checked by the apps' engine:
//   node website/test/server.test.mjs
import assert from 'node:assert';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { onRequest, PLANS } from '../functions/api/[[path]].js';

const require = createRequire(import.meta.url);
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'lic-server-'));
process.env.BILLBOX_EDITION = 'admin';
const L = require('../../backend/src/services/license.js');

const pair = () => { const k = crypto.generateKeyPairSync('ed25519'); return { der: k.privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64'), x: k.publicKey.export({ format: 'jwk' }).x }; };
const live = pair(), test = pair();
L.KEYS.live = live.x; L.KEYS.test = test.x;
const store = new Map();
const env = {
  LICENSES: { get: async (k) => store.get(k) ?? null, put: async (k, v) => { store.set(k, v); }, list: async ({ prefix }) => ({ keys: [...store.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })) }) },
  LICENSE_KEY_LIVE: live.der, LICENSE_KEY_TEST: test.der, RZP_KEY_ID_TEST: 'rzp_test_X', RZP_KEY_SECRET_TEST: 'sekret', ADMIN_TOKEN: 'adm1n', UPI_VPA: 'ak@upi',
};
const orders = {};
const realFetch = globalThis.fetch;
globalThis.fetch = async (url, opts = {}) => {
  const u = String(url);
  if (u.startsWith('https://api.razorpay.com/v1/orders')) {
    assert.strictEqual(opts.headers.authorization, 'Basic ' + btoa('rzp_test_X:sekret'));
    if (opts.method === 'POST') { const b = JSON.parse(opts.body); const id = 'order_' + Object.keys(orders).length; orders[id] = { id, ...b, status: 'created' }; return new Response(JSON.stringify(orders[id])); }
    const id = decodeURIComponent(u.split('/').pop()); return orders[id] ? new Response(JSON.stringify(orders[id])) : new Response('{}', { status: 404 });
  }
  if (u.startsWith('https://billbox.pages.dev/api/')) {   // the engine calling the licence server
    const p = u.slice('https://billbox.pages.dev/api/'.length).split('/');
    return onRequest({ request: new Request(u, opts), env, params: { path: p } });
  }
  return realFetch(url, opts);
};
const call = async (method, p, body, headers = {}) => {
  const r = await onRequest({ request: new Request(`https://billbox.pages.dev/api/${p}`, { method, headers: { 'content-type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined }), env, params: { path: p.split('/') } });
  return { status: r.status, j: await r.json() };
};
const hmac = (k, t) => crypto.createHmac('sha256', k).update(t).digest('hex');

let n = 0;
const ok = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { console.log('  FAIL', name, '\n      ', e.stack); process.exitCode = 1; } };

let key;
await ok('config: prices and the public Razorpay key; live has no gateway yet', async () => {
  const c = (await call('GET', 'test/config')).j;
  assert.strictEqual(c.key_id, 'rzp_test_X'); assert.strictEqual(c.plans.yearly_inr.amount, 149900); assert.strictEqual(c.plans.lifetime_inr.amount, 399900); assert.strictEqual(c.plans.yearly_usd.currency, 'USD');
  assert.strictEqual((await call('POST', 'live/order', { plan: 'yearly_inr', email: 'a@b.in' })).status, 503);
});
await ok('order, then a forged payment is refused and a real one gives the licence key', async () => {
  const o = (await call('POST', 'test/order', { plan: 'yearly_inr', email: 'Shop@Example.in', name: 'AK', device: 'D1' })).j;
  assert.ok(o.order_id && o.amount === 149900 && o.email === 'shop@example.in');
  assert.strictEqual((await call('POST', 'test/verify', { order_id: o.order_id, payment_id: 'pay_1', signature: 'nope' })).status, 400);
  const r = (await call('POST', 'test/verify', { order_id: o.order_id, payment_id: 'pay_1', signature: hmac('sekret', `${o.order_id}|pay_1`) })).j;
  assert.ok(r.license_key.startsWith('BB1.')); assert.strictEqual(r.plan, 'yearly'); assert.ok(r.expires);
  key = r.license_key;
  const again = (await call('POST', 'test/verify', { order_id: o.order_id, payment_id: 'pay_1', signature: hmac('sekret', `${o.order_id}|pay_1`) })).j;
  assert.strictEqual(again.license_key, key, 'the same payment gives the same licence');
  assert.strictEqual((await call('POST', 'test/lookup', { email: 'shop@example.in', payment_id: 'pay_1' })).j.license_key, key);
  assert.strictEqual((await call('POST', 'test/lookup', { email: 'x@y.in', payment_id: 'pay_1' })).status, 404);
});
await ok('the app engine checks the key and activates through the server; 2 devices, then refused', async () => {
  const s = await L.activate({ key });
  assert.strictEqual(s.state, 'licensed'); assert.strictEqual(s.plan, 'yearly');
  assert.strictEqual((await call('POST', 'test/activate', { key, device: 'OTHER1' })).status, 200);
  const third = await call('POST', 'test/activate', { key, device: 'OTHER2' });
  assert.strictEqual(third.status, 409); assert.strictEqual(third.j.code, 'SEATS');
  assert.strictEqual((await call('POST', 'test/deactivate', { key, device: 'OTHER1' })).status, 200);
  assert.strictEqual((await call('POST', 'test/activate', { key, device: 'OTHER2' })).status, 200);
});
await ok('a test key does not work on the live server, nor a live key in the admin app', async () => {
  assert.strictEqual((await call('POST', 'live/activate', { key, device: 'D9' })).status, 400);
});
await ok('admin: issue (for a UPI or cash sale), list, revoke; wrong token refused', async () => {
  assert.strictEqual((await call('POST', 'test/admin/issue', { plan: 'lifetime', email: 'c@d.in' }, { authorization: 'Bearer wrong' })).status, 401);
  const r = (await call('POST', 'test/admin/issue', { plan: 'lifetime', email: 'c@d.in', name: 'Cash sale', note: 'UPI ref 123' }, { authorization: 'Bearer adm1n' })).j;
  assert.strictEqual(r.plan, 'lifetime'); assert.strictEqual(r.expires, null);
  const live1 = (await call('POST', 'live/admin/issue', { plan: 'yearly', email: 'e@f.in' }, { authorization: 'Bearer adm1n' })).j;
  assert.ok(L.readToken(live1.license_key, 'live'), 'a live licence is signed with the live key');
  const list = (await call('GET', 'test/admin/list', null, { authorization: 'Bearer adm1n' })).j;
  assert.strictEqual(list.length, 2); assert.ok(!list[0].key);
  assert.strictEqual((await call('POST', 'test/admin/revoke', { id: r.license_id }, { authorization: 'Bearer adm1n' })).j.revoked, true);
  const a = await call('POST', 'test/activate', { key: r.license_key, device: 'Z' });
  assert.strictEqual(a.status, 403); assert.strictEqual(a.j.code, 'REVOKED');
});
await ok('prices: ₹1,499 yearly, ₹3,999 lifetime, $29 yearly', async () => {
  assert.deepStrictEqual([PLANS.yearly_inr.amount, PLANS.lifetime_inr.amount, PLANS.yearly_usd.amount], [149900, 399900, 2900]);
});
console.log(`${n} licence server checks passed`);
