// The licence server against a fake KV store, and its tokens checked by the apps' engine:
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
  LICENSE_KEY_LIVE: live.der, LICENSE_KEY_TEST: test.der, ADMIN_TOKEN: 'adm1n', UPI_VPA: 'ak@upi', BANK_DETAILS: 'AK Enterprises|1234567890|SBIN0000001|SBI',
};
const realFetch = globalThis.fetch;
globalThis.fetch = async (url, opts = {}) => {
  const u = String(url);
  if (u.startsWith('https://billbox-app.pages.dev/api/')) {   // the engine calling the licence server
    const p = u.slice('https://billbox-app.pages.dev/api/'.length).split('/');
    return onRequest({ request: new Request(u, opts), env, params: { path: p } });
  }
  return realFetch(url, opts);
};
const call = async (method, p, body, headers = {}) => {
  const r = await onRequest({ request: new Request(`https://billbox-app.pages.dev/api/${p}`, { method, headers: { 'content-type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined }), env, params: { path: p.split('/') } });
  return { status: r.status, j: await r.json() };
};

let n = 0;
const ok = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { console.log('  FAIL', name, '\n      ', e.stack); process.exitCode = 1; } };

let key;
await ok('config: prices, UPI id and bank; no gateway endpoints', async () => {
  const c = (await call('GET', 'test/config')).j;
  assert.strictEqual(c.plans.yearly_inr.amount, 149900); assert.strictEqual(c.plans.lifetime_inr.amount, 399900); assert.strictEqual(c.plans.yearly_usd, undefined, 'no international plan for now');
  assert.strictEqual(c.key_id, undefined); assert.strictEqual(c.upi_vpa, 'ak@upi');
  for (const p of ['order', 'verify', 'webhook']) assert.strictEqual((await call('POST', `test/${p}`, {})).status, 404, p);
});
await ok('a UPI payment confirmed by the owner gives the licence key', async () => {
  assert.strictEqual((await call('POST', 'test/claim', { plan: 'yearly_inr', email: 'Shop@Example.in', name: 'AK', method: 'upi', ref: '111122223333' })).j.status, 'pending');
  const r = (await call('POST', 'test/admin/approve', { ref: '111122223333' }, { authorization: 'Bearer adm1n' })).j;
  assert.ok(r.license_key.startsWith('BB1.')); assert.strictEqual(r.plan, 'yearly'); assert.ok(r.expires); assert.strictEqual(r.email, 'shop@example.in');
  key = r.license_key;
  assert.strictEqual((await call('POST', 'test/lookup', { email: 'shop@example.in', payment_id: '111122223333' })).j.license_key, key);
  assert.strictEqual((await call('POST', 'test/lookup', { email: 'x@y.in', payment_id: '111122223333' })).status, 404);
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
await ok('direct UPI / bank: claim waits, owner confirms, key found by e-mail + reference; bad ones refused', async () => {
  const A = { authorization: 'Bearer adm1n' };
  const c = (await call('GET', 'test/config')).j;
  assert.deepStrictEqual(c.bank, { name: 'AK Enterprises', account: '1234567890', ifsc: 'SBIN0000001', bank: 'SBI' });
  assert.strictEqual((await call('POST', 'test/claim', { plan: 'yearly_usd', email: 'u@v.in', method: 'upi', ref: '123456789012' })).status, 400, 'no such plan');
  assert.strictEqual((await call('POST', 'test/claim', { plan: 'yearly_inr', email: 'u@v.in', method: 'upi', ref: '12' })).status, 400, 'short ref');
  const r = (await call('POST', 'test/claim', { plan: 'lifetime_inr', email: 'U@v.in', name: 'Shop', method: 'upi', ref: '4321 5678 9012' })).j;
  assert.deepStrictEqual(r, { status: 'pending', ref: '432156789012' });
  assert.strictEqual((await call('POST', 'test/claim', { plan: 'lifetime_inr', email: 'x@y.in', method: 'upi', ref: '432156789012' })).status, 409, 'someone else cannot reuse the ref');
  const wait = await call('POST', 'test/lookup', { email: 'u@v.in', payment_id: '432156789012' });
  assert.strictEqual(wait.status, 404); assert.strictEqual(wait.j.code, 'PENDING');
  assert.strictEqual((await call('GET', 'test/admin/claims')).status, 401);
  const list = (await call('GET', 'test/admin/claims', null, A)).j;
  assert.strictEqual(list[0].ref, '432156789012'); assert.strictEqual(list[0].status, 'pending');
  const ap = (await call('POST', 'test/admin/approve', { ref: '432156789012' }, A)).j;
  assert.strictEqual(ap.plan, 'lifetime'); assert.ok(ap.license_key.startsWith('BB1.'));
  assert.strictEqual((await call('POST', 'test/admin/approve', { ref: '432156789012' }, A)).j.license_key, ap.license_key, 'confirming twice gives the same licence');
  assert.strictEqual((await call('POST', 'test/lookup', { email: 'u@v.in', payment_id: '4321-5678-9012' })).j.license_key, ap.license_key);
  assert.strictEqual((await call('POST', 'test/claim', { plan: 'lifetime_inr', email: 'u@v.in', method: 'upi', ref: '432156789012' })).j.license_key, ap.license_key);
  assert.strictEqual((await L.activate({ key: ap.license_key })).state, 'licensed');
  (await call('POST', 'test/claim', { plan: 'yearly_inr', email: 'b@k.in', method: 'bank', ref: 'SBIN26111200001' }));
  assert.strictEqual((await call('POST', 'test/admin/reject', { ref: 'SBIN26111200001' }, A)).j.status, 'rejected');
  assert.strictEqual((await call('POST', 'test/lookup', { email: 'b@k.in', payment_id: 'SBIN26111200001' })).j.code, 'REJECTED');
  delete env.BANK_DETAILS;
  assert.strictEqual((await call('POST', 'test/claim', { plan: 'yearly_inr', email: 'b@k.in', method: 'bank', ref: 'SBIN26111200002' })).status, 503, 'bank not set up');
  assert.strictEqual((await call('GET', 'test/config')).j.bank, null);
});
await ok('prices: ₹1,499 yearly, ₹3,999 lifetime', async () => {
  assert.deepStrictEqual([PLANS.yearly_inr.amount, PLANS.lifetime_inr.amount], [149900, 399900]);
});
console.log(`${n} licence server checks passed`);
