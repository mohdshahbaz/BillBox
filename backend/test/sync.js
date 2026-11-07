// Live sync between two devices through a fake Firebase (auth + Realtime Database REST): node test/sync.js
const os = require('os'), fs = require('fs'), path = require('path'), http = require('http'), assert = require('assert');
const { fork, execFileSync } = require('child_process');

// ---------- fake Firebase ----------
const tree = {};
const users = {};
let pushN = 0, lastMs = 0;
const PUSH = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';
function pushId() {
  let ms = Math.max(Date.now(), lastMs); lastMs = ms; let s = '';
  for (let i = 0; i < 8; i++) { s = PUSH[ms % 64] + s; ms = Math.floor(ms / 64); }
  const n = String(pushN++).padStart(12, '0'); return s + n;
}
const at = (parts, make) => { let o = tree; for (const p of parts) { if (o[p] === undefined || o[p] === null || typeof o[p] !== 'object') { if (!make) return undefined; o[p] = {}; } o = o[p]; } return o; };
const strip = (v) => {
  if (v && typeof v === 'object' && v['.sv'] === 'timestamp') return Date.now();
  if (Array.isArray(v)) return v.map(strip);
  if (v && typeof v === 'object') { const o = {}; for (const [k, x] of Object.entries(v)) if (x !== null) o[k] = strip(x); return o; }
  return v;
};
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const u = new URL(req.url, 'http://x');
    const send = (st, o) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (u.pathname.startsWith('/v1/accounts:')) {
      const b = JSON.parse(body), kind = u.pathname.split(':')[1];
      if (kind === 'signUp') { if (users[b.email]) return send(400, { error: { message: 'EMAIL_EXISTS' } }); users[b.email] = { pw: b.password, uid: 'U' + Object.keys(users).length }; }
      const x = users[b.email];
      if (!x || x.pw !== b.password) return send(400, { error: { message: 'INVALID_LOGIN_CREDENTIALS' } });
      return send(200, { idToken: 'T:' + x.uid, refreshToken: 'R:' + x.uid, localId: x.uid, expiresIn: '3600' });
    }
    if (u.pathname === '/token') { const p = new URLSearchParams(body); const uid = p.get('refresh_token').slice(2); return send(200, { id_token: 'T:' + uid, refresh_token: 'R:' + uid, expires_in: '3600' }); }
    const m = /^\/users\/([^/]+)\/(.*)\.json$/.exec(u.pathname);
    if (!m) return send(404, { error: 'nope' });
    if (u.searchParams.get('auth') !== 'T:' + m[1]) return send(401, { error: 'Permission denied' });
    const parts = ['users', m[1], ...m[2].split('/')];
    if (req.method === 'PUT') { const parent = at(parts.slice(0, -1), true); parent[parts[parts.length - 1]] = strip(JSON.parse(body)); return send(200, JSON.parse(body)); }
    if (req.method === 'POST') { const o = at(parts, true); const k = pushId(); o[k] = strip(JSON.parse(body)); return send(200, { name: k }); }
    let v = parts.reduce((o, p) => (o && typeof o === 'object' ? o[p] : undefined), tree);
    if (v === undefined) return send(200, null);
    if (u.searchParams.get('shallow') === 'true' && v && typeof v === 'object') return send(200, Object.fromEntries(Object.keys(v).map((k) => [k, true])));
    if (u.searchParams.get('orderBy') === '"$key"') {
      let keys = Object.keys(v).sort();
      if (u.searchParams.has('startAt')) { const s = JSON.parse(u.searchParams.get('startAt')); keys = keys.filter((k) => k >= s); }
      if (u.searchParams.has('limitToFirst')) keys = keys.slice(0, Number(u.searchParams.get('limitToFirst')));
      v = Object.fromEntries(keys.map((k) => [k, v[k]]));
    }
    send(200, v);
  });
});

// ---------- two devices ----------
function device(name, port) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `sync-${name}-`));
  const env = { ...process.env, DATA_DIR: dir, BILLBOX_FIREBASE_KEY: 'K', BILLBOX_FIREBASE_DB: `http://127.0.0.1:${port}`,
    BILLBOX_FIREBASE_AUTH: `http://127.0.0.1:${port}/v1`, BILLBOX_FIREBASE_TOKEN: `http://127.0.0.1:${port}/token`, NODE_NO_WARNINGS: '1' };
  if (name === 'A') execFileSync(process.execPath, [path.join(__dirname, '../src/seed.js')], { env, stdio: 'ignore' });
  const p = fork(path.join(__dirname, 'sync_device.js'), [], { env, stdio: ['ignore', 'ignore', 'inherit', 'ipc'] });
  let n = 0; const wait = {};
  const ready = new Promise((ok) => p.once('message', ok));
  p.on('message', (m) => { if (m.id && wait[m.id]) { const w = wait[m.id]; delete wait[m.id]; m.err ? w.no(new Error(`${name}: ${m.err}`)) : w.ok(m.r); } });
  const run = (code) => new Promise((ok, no) => { const id = ++n; wait[id] = { ok, no }; p.send({ id, code }); });
  return { run, ready, kill: () => p.kill() };
}

(async () => {
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const port = server.address().port;
  const A = device('A', port), B = device('B', port);
  await Promise.all([A.ready, B.ready]);
  let passed = 0;
  const ok = async (name, fn) => { await fn(); passed++; console.log('  ok  ', name); };
  const q = (dev, sql, ...args) => dev.run(`return db.withCompany(${dev === A ? 'db.firstCompanyId()' : 'Object.keys(JSON.parse(db.registry.prepare("SELECT value FROM app_settings WHERE key=\'sync_map\'").get().value))[0]*1'}, () => db.prepare(${JSON.stringify(sql)}).all(...${JSON.stringify(args)}))`);
  const both = () => Promise.all([A.run('return S.tick()'), B.run('return S.tick()')]).then(() => Promise.all([A.run('return S.tick()'), B.run('return S.tick()')]));

  await ok('A creates a sync account and turns sync on for its company', async () => {
    const s = await A.run("await S.signIn({ email: 'a@x.in', password: 'secret1', create: true }); return S.turnOn(db.firstCompanyId())");
    assert.ok(s.on && s.slot === 1, JSON.stringify(s));
    assert.strictEqual(s.last_error, null);
  });
  await ok('B signs in to the same account and gets its own slot', async () => {
    const s = await B.run("return S.signIn({ email: 'a@x.in', password: 'secret1' })");
    assert.strictEqual(s.slot, 2);
    await assert.rejects(B.run("return S.signIn({ email: 'a@x.in', password: 'wrong' })"), /Wrong e-mail or password/);
  });
  await ok('B joins the company and gets all of its books', async () => {
    const r = await B.run('const l = await S.remote(); return S.join(l.books[0].key)');
    assert.ok(r.on && r.company_id);
    for (const t of ['items', 'batches', 'parties', 'settings', 'categories']) {
      const [a, b] = [await q(A, `SELECT * FROM ${t} ORDER BY 1`), await q(B, `SELECT * FROM ${t} ORDER BY 1`)];
      assert.ok(a.length > 0, t);
      assert.deepStrictEqual(b, a, t);
    }
  });
  await ok('new rows on each device take ids from that device\'s own range', async () => {
    await A.run("db.withCompany(db.firstCompanyId(), () => db.prepare(\"INSERT INTO categories(name) VALUES('From A')\").run())");
    const bid = await B.run("const c = Object.keys(JSON.parse(db.registry.prepare(\"SELECT value FROM app_settings WHERE key='sync_map'\").get().value))[0]*1; return db.withCompany(c, () => Number(db.prepare('INSERT INTO categories(name) VALUES(?)').run('From B').lastInsertRowid))");
    assert.ok(bid > 20000000 && bid < 30000000, String(bid));
    await both();
    const a = await q(A, 'SELECT id,name FROM categories WHERE name LIKE ? ORDER BY id', 'From %');
    assert.deepStrictEqual(a.map((x) => x.name), ['From A', 'From B']);
    assert.ok(a[0].id > 10000000 && a[0].id < 20000000);
    assert.deepStrictEqual(await q(B, 'SELECT id,name FROM categories ORDER BY id'), await q(A, 'SELECT id,name FROM categories ORDER BY id'));
  });
  await ok('both devices sell from the same batch: stock counts both sales', async () => {
    const [batch] = await q(A, 'SELECT id,item_id,qty FROM batches WHERE qty > 20 ORDER BY id LIMIT 1');
    const sell = (dev, n) => dev.run(`const c = ${dev === A ? 'db.firstCompanyId()' : 'Object.keys(JSON.parse(db.registry.prepare("SELECT value FROM app_settings WHERE key=\'sync_map\'").get().value))[0]*1'};
      return db.withCompany(c, () => billing.createInvoice({ pay_mode: 'CASH', lines: [{ item_id: ${batch.item_id}, batch_id: ${batch.id}, qty: ${n} }] }))`);
    const [ia, ib] = [await sell(A, 3), await sell(B, 4)];
    assert.ok(ia && ib);
    await both();
    const [qa] = await q(A, 'SELECT qty FROM batches WHERE id=?', batch.id), [qb] = await q(B, 'SELECT qty FROM batches WHERE id=?', batch.id);
    assert.strictEqual(qa.qty, qb.qty);
    assert.strictEqual(qa.qty, batch.qty - 7);
    assert.strictEqual((await q(A, 'SELECT COUNT(*) n FROM invoices'))[0].n, (await q(B, 'SELECT COUNT(*) n FROM invoices'))[0].n);
    assert.deepStrictEqual(await q(B, 'SELECT * FROM invoice_lines ORDER BY id'), await q(A, 'SELECT * FROM invoice_lines ORDER BY id'));
    assert.deepStrictEqual(await q(B, 'SELECT * FROM ledger ORDER BY id'), await q(A, 'SELECT * FROM ledger ORDER BY id'));
  });
  await ok('an edit and a delete on one device show on the other', async () => {
    const [p] = await q(B, 'SELECT id FROM parties ORDER BY id LIMIT 1');
    await B.run(`const c = Object.keys(JSON.parse(db.registry.prepare("SELECT value FROM app_settings WHERE key='sync_map'").get().value))[0]*1;
      db.withCompany(c, () => { db.prepare("UPDATE parties SET name='Renamed on B', gstin=NULL WHERE id=?").run(${p.id}); db.prepare("DELETE FROM categories WHERE name='From A'").run(); })`);
    const v0 = (await A.run('return S.tick()')).version;
    await both();
    const [pa] = await q(A, 'SELECT name,gstin FROM parties WHERE id=?', p.id);
    assert.deepStrictEqual(pa, { name: 'Renamed on B', gstin: null });
    assert.strictEqual((await q(A, "SELECT COUNT(*) n FROM categories WHERE name='From A'"))[0].n, 0);
    assert.ok((await A.run('return S.tick()')).version > v0 - 1);
  });
  await ok('the books stay identical table by table', async () => {
    for (const t of ['items', 'batches', 'parties', 'invoices', 'invoice_lines', 'ledger', 'counters', 'categories', 'receipts']) {
      assert.deepStrictEqual(await q(B, `SELECT * FROM ${t} ORDER BY 1`), await q(A, `SELECT * FROM ${t} ORDER BY 1`), t);
    }
    const nos = (await q(A, 'SELECT invoice_no FROM invoices ORDER BY id')).map((x) => x.invoice_no);
    assert.strictEqual(new Set(nos).size, nos.length, 'two bills made at once keep different numbers');
    assert.ok(!nos.some((x) => x.includes('~')), nos.join(' '));
    const s = await A.run('return S.status(db.firstCompanyId())');
    assert.strictEqual(s.pending, 0); assert.strictEqual(s.errors, 0);
  });
  await ok('turning sync off stops tracking and gives SQLite ids back', async () => {
    const s = await A.run("const c = db.firstCompanyId(); S.turnOff(c); return db.withCompany(c, () => Number(db.prepare(\"INSERT INTO categories(name) VALUES('local')\").run().lastInsertRowid))");
    assert.ok(s > 20000000, 'continues after the highest id'); // plain SQLite rowid
    const t = await q(A, "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'bbsync_%'");
    assert.strictEqual(t.length, 0);
  });
  console.log(`sync: ${passed} checks passed`);
  A.kill(); B.kill(); server.close();
})().catch((e) => { console.error('  FAIL', e.message); process.exitCode = 1; process.exit(1); });
