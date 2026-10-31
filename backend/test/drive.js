// Google Drive backups against a fake Google (no internet): node test/drive.js
const os = require('os'), fs = require('fs'), path = require('path');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'drive-test-'));
const assert = require('assert');
const B = require('../src/services/backup');
const D = require('../src/services/drive');

const calls = [];
let approved = false, nextId = 1;
const files = {};
globalThis.fetch = async (url, opts = {}) => {
  const u = new URL(url), body = opts.body;
  calls.push({ url: u.pathname, method: opts.method || 'GET' });
  const json = (status, o) => ({ status, text: async () => JSON.stringify(o) });
  if (u.pathname === '/device/code') return json(200, { device_code: 'DEV', user_code: 'ABCD-EFGH', verification_url: 'https://www.google.com/device', interval: 5, expires_in: 1800 });
  if (u.pathname === '/token') {
    const p = new URLSearchParams(body);
    if (p.get('grant_type') === 'refresh_token') return json(p.get('refresh_token') === 'R1' ? 200 : 400, p.get('refresh_token') === 'R1' ? { access_token: 'A2' } : { error: 'invalid_grant' });
    return approved ? json(200, { access_token: 'A1', refresh_token: 'R1' }) : json(428, { error: 'authorization_pending' });
  }
  if (u.pathname === '/drive/v3/files' && opts.method === 'POST') {
    const m = JSON.parse(body); const id = 'F' + nextId++; files[id] = m; return json(200, { id });
  }
  if (u.pathname.startsWith('/drive/v3/files/')) { const id = decodeURIComponent(u.pathname.split('/').pop()); return files[id] ? json(200, { id, trashed: false }) : json(404, {}); }
  if (u.pathname === '/upload/drive/v3/files') {
    assert.match(opts.headers['content-type'], /^multipart\/related; boundary=/);
    const meta = JSON.parse(String(body).split('\r\n\r\n')[1].split('\r\n')[0]);
    const id = 'F' + nextId++; files[id] = { ...meta, bytes: body.length }; return json(200, { id });
  }
  return json(404, {});
};

let n = 0;
const ok = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { console.log('  FAIL', name, '\n      ', e.message); process.exitCode = 1; } };
const fails = async (fn, status) => { try { await fn(); } catch (e) { return e.status === status; } return false; };

(async () => {
  B.saveConfig({ dir: path.join(process.env.DATA_DIR, 'bk') });
  await ok('not set up: status, and connect asks for the keys', async () => {
    assert.deepStrictEqual(D.status().connected, false);
    assert.ok(await fails(() => D.connect(), 400));
  });
  await ok('a wrong Client ID is refused', async () => { assert.ok(await fails(() => D.saveClient({ client_id: 'abc', client_secret: 'x' }), 400)); });
  await ok('keys saved; connect gives the code', async () => {
    D.saveClient({ client_id: '123-abc.apps.googleusercontent.com', client_secret: 'SECRET' });
    const r = await D.connect();
    assert.strictEqual(r.user_code, 'ABCD-EFGH');
    assert.strictEqual(D.status().waiting, true);
  });
  await ok('poll waits until approved, then makes BillBox Backups', async () => {
    assert.deepStrictEqual(await D.poll(), { connected: false, waiting: true });
    approved = true;
    const r = await D.poll();
    assert.strictEqual(r.connected, true);
    assert.strictEqual(files.F1.name, 'BillBox Backups');
    assert.strictEqual(files.F1.mimeType, 'application/vnd.google-apps.folder');
    const s = D.status();
    assert.ok(s.connected && !s.waiting && s.folder === 'BillBox Backups');
  });
  await ok('upload puts every file of the newest backup in its own folder', async () => {
    const b = B.backupNow({ reason: 'manual' });
    const r = await D.upload({});
    assert.strictEqual(r.folder, path.basename(b.folder));
    assert.strictEqual(r.files, fs.readdirSync(b.folder).length);
    const sub = Object.entries(files).find(([, f]) => f.name === path.basename(b.folder));
    assert.ok(sub && sub[1].parents[0] === 'F1');
    const up = Object.values(files).filter((f) => f.parents && f.parents[0] === sub[0]).map((f) => f.name).sort();
    assert.deepStrictEqual(up, fs.readdirSync(b.folder).sort());
    assert.strictEqual(D.status().last_status, 'ok');
  });
  await ok('the Drive folder is made again when it was deleted', async () => {
    delete files.F1;
    await D.upload({});
    assert.ok(Object.values(files).filter((f) => f.name === 'BillBox Backups').length === 1);
  });
  await ok('offline: 503 OFFLINE', async () => {
    const f = globalThis.fetch; globalThis.fetch = () => Promise.reject(new Error('offline'));
    try { await D.upload({}); assert.fail('no error'); } catch (e) { assert.strictEqual(e.status, 503); assert.strictEqual(e.code, 'OFFLINE'); }
    globalThis.fetch = f;
  });
  await ok('afterBackup never throws and records a failure', async () => {
    const f = globalThis.fetch; globalThis.fetch = () => Promise.reject(new Error('offline'));
    assert.strictEqual(await D.afterBackup('nope'), null);
    assert.match(D.status().last_status, /^failed/);
    globalThis.fetch = f;
  });
  await ok('disconnect forgets the permission but keeps the keys', async () => {
    const s = D.disconnect();
    assert.ok(!s.connected && s.client_id && s.has_secret);
    assert.ok(await fails(() => D.upload({}), 400));
  });
  console.log(`${n} drive checks passed`);
})();
