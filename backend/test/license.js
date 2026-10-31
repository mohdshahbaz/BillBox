// Licence checks against a fake licence server (no internet): node test/license.js
const os = require('os'), fs = require('fs'), path = require('path'), crypto = require('crypto');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'license-test-'));
process.env.BILLBOX_EDITION = 'admin';
const assert = require('assert');
const L = require('../src/services/license');

// a key pair for the test: the engine is told it is the test key
const keys = { test: crypto.generateKeyPairSync('ed25519'), live: crypto.generateKeyPairSync('ed25519') };
for (const e of ['test', 'live']) L.KEYS[e] = keys[e].publicKey.export({ format: 'jwk' }).x;
const sign = (payload, e = 'test') => {
  const body = 'BB1.' + Buffer.from(JSON.stringify({ ...payload, env: e })).toString('base64url');
  return body + '.' + crypto.sign(null, Buffer.from(body), keys[e].privateKey).toString('base64url');
};
const DAY = 86400000;
let seats = new Set(), maxSeats = 2;
globalThis.fetch = async (url, opts) => {
  const b = JSON.parse(opts.body);
  const json = (status, o) => ({ status, text: async () => JSON.stringify(o) });
  if (url.endsWith('/api/test/activate')) {
    const lic = L.readToken(b.key);
    if (!lic) return json(400, { error: 'bad key' });
    if (!seats.has(b.device) && seats.size >= maxSeats) return json(409, { error: 'All devices used', code: 'SEATS' });
    seats.add(b.device);
    return json(200, { activation: sign({ t: 'act', lic: lic.id, dev: b.device, plan: lic.plan, email: lic.email, lexp: lic.exp, exp: Date.now() + 60 * DAY }) });
  }
  if (url.endsWith('/api/test/deactivate')) { seats.delete(b.device); return json(200, { ok: true }); }
  return json(404, {});
};

let n = 0;
const ok = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { console.log('  FAIL', name, '\n      ', e.message); process.exitCode = 1; } };
const fails = async (fn, status) => { try { await fn(); } catch (e) { return e.status === status ? e : false; } return false; };

(async () => {
  await ok('a new install is on a 15-day trial and may save', async () => {
    const s = L.status();
    assert.strictEqual(s.state, 'trial'); assert.strictEqual(s.trial_days_left, 15); assert.ok(L.allows('POST', '/api/invoices'));
  });
  await ok('the trial ends after 15 days: read-only, but backups, printing marks and the licence still work', async () => {
    require('../src/db').registry.prepare("UPDATE app_settings SET value=? WHERE key='license_trial_start'").run(String(Date.now() - 16 * DAY));
    const s = L.status();
    assert.strictEqual(s.state, 'expired'); assert.strictEqual(s.writable, false);
    assert.ok(!L.allows('POST', '/api/invoices')); assert.ok(!L.allows('PUT', '/items/4'));
    assert.ok(L.allows('GET', '/api/invoices')); assert.ok(L.allows('POST', '/backup/run')); assert.ok(L.allows('POST', '/license/activate'));
    assert.ok(L.allows('POST', '/invoices/12/printed')); assert.ok(L.allows('POST', '/invoices/preview'));
    assert.strictEqual(L.blocked().status, 402);
  });
  await ok('a key that is not a licence, a forged one and a live key in the test edition are refused', async () => {
    assert.ok(await fails(() => L.activate({ key: 'hello' }), 400));
    const good = sign({ t: 'lic', id: 'L1', plan: 'yearly', exp: Date.now() + 365 * DAY });
    const forged = good.slice(0, -4) + (good.slice(-4) === 'AAAA' ? 'BBBB' : 'AAAA');
    assert.ok(await fails(() => L.activate({ key: forged }), 400));
    const e = await fails(() => L.activate({ key: sign({ t: 'lic', id: 'L2', plan: 'yearly', exp: null }, 'live') }), 400);
    assert.ok(e && /live licence key/.test(e.message));
  });
  await ok('an expired licence key is refused', async () => {
    assert.ok(await fails(() => L.activate({ key: sign({ t: 'lic', id: 'L3', plan: 'yearly', exp: Date.now() - DAY }) }), 400));
  });
  const key = sign({ t: 'lic', id: 'L9', plan: 'yearly', email: 'a@b.in', exp: Date.now() + 365 * DAY, devices: 2 });
  await ok('a licence key activates this device: licensed and writable again', async () => {
    const s = await L.activate({ key });
    assert.strictEqual(s.state, 'licensed'); assert.strictEqual(s.plan, 'yearly'); assert.ok(s.writable); assert.ok(L.allows('POST', '/invoices'));
    assert.ok(!s.needs_renewal);
  });
  await ok('an activation copied from another device does not count here', async () => {
    const reg = require('../src/db').registry;
    const other = sign({ t: 'act', lic: 'L9', dev: 'SOMEONEELSE', plan: 'yearly', lexp: null, exp: Date.now() + 60 * DAY });
    const mine = reg.prepare("SELECT value FROM app_settings WHERE key='license_activation'").get().value;
    reg.prepare("UPDATE app_settings SET value=? WHERE key='license_activation'").run(other);
    assert.strictEqual(L.status().state, 'expired');
    reg.prepare("UPDATE app_settings SET value=? WHERE key='license_activation'").run(mine);
    assert.strictEqual(L.status().state, 'licensed');
  });
  await ok('the device limit is the server\'s: a third device is refused', async () => {
    seats.add('X1');
    maxSeats = 2;
    const reg = require('../src/db').registry;
    const dev = reg.prepare("SELECT value FROM app_settings WHERE key='license_device'").get().value;
    seats = new Set(['X1', 'X2']);
    assert.ok(await fails(() => L.activate({ key }), 409));
    seats = new Set([dev]);
  });
  await ok('renew does nothing while the activation is fresh, and renews it near its end', async () => {
    assert.strictEqual((await L.renew()).state, 'licensed');
    const reg = require('../src/db').registry;
    const dev = reg.prepare("SELECT value FROM app_settings WHERE key='license_device'").get().value;
    reg.prepare("UPDATE app_settings SET value=? WHERE key='license_activation'").run(sign({ t: 'act', lic: 'L9', dev, plan: 'yearly', lexp: null, exp: Date.now() + 3 * DAY }));
    assert.ok(L.status().needs_renewal);
    const s = await L.renew();
    assert.ok(!s.needs_renewal && s.state === 'licensed');
  });
  await ok('offline: renewing fails quietly and BillBox keeps working until the activation runs out', async () => {
    const f = globalThis.fetch; globalThis.fetch = () => Promise.reject(new Error('offline'));
    const e = await fails(() => L.activate({ key }), 503); assert.ok(e && e.code === 'OFFLINE');
    assert.strictEqual(L.status().state, 'licensed');
    globalThis.fetch = f;
  });
  await ok('deactivate frees the seat; reset trial (admin edition) starts over', async () => {
    const s = await L.deactivate();
    assert.notStrictEqual(s.state, 'licensed'); assert.strictEqual(seats.size, 0);
    assert.strictEqual(L.resetTrial().trial_days_left, 15);
  });
  console.log(`${n} licence checks passed`);
})();
