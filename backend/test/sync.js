// Live sync between two devices through a fake Firebase (auth + Realtime Database REST): node test/sync.js
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert');
const { fork, execFileSync } = require('child_process');

const { server } = require('./fake_firebase');

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
  const cB = 'Object.keys(JSON.parse(db.registry.prepare("SELECT value FROM app_settings WHERE key=\'sync_map\'").get().value))[0]*1';
  await ok('the same category and batch made on both devices at once become one (stock of both kept, bills follow)', async () => {
    const [it] = await q(A, 'SELECT id FROM items ORDER BY id LIMIT 1');
    const make = (dev, c, qty) => dev.run(`return db.withCompany(${c}, () => {
      db.prepare("INSERT INTO categories(name) VALUES('Same')").run();
      const b = Number(db.prepare("INSERT INTO batches(item_id,batch_no,exp_date,qty) VALUES(?,?,?,?)").run(${it.id}, 'B-SAME', new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10), ${qty}).lastInsertRowid);
      return b; })`);
    const ba = await make(A, 'db.firstCompanyId()', 10), bb = await make(B, cB, 20);
    // B sells 3 from its own copy before anything is synced
    await B.run(`return db.withCompany(${cB}, () => billing.createInvoice({ pay_mode: 'CASH', lines: [{ item_id: ${it.id}, batch_id: ${bb}, qty: 3 }] }))`);
    await both(); await both();
    for (const dev of [A, B]) {
      const bs = await q(dev, "SELECT id,qty FROM batches WHERE batch_no='B-SAME'");
      assert.deepStrictEqual(bs, [{ id: ba, qty: 27 }], JSON.stringify(bs));
      assert.strictEqual((await q(dev, "SELECT COUNT(*) n FROM categories WHERE name='Same'"))[0].n, 1);
    }
    assert.strictEqual((await q(A, `SELECT COUNT(*) n FROM invoice_lines WHERE batch_id=${ba}`))[0].n, 1, JSON.stringify(await q(A, 'SELECT id,batch_id,qty FROM invoice_lines ORDER BY id DESC LIMIT 2')) + JSON.stringify(await q(B, 'SELECT id,batch_id,qty FROM invoice_lines ORDER BY id DESC LIMIT 2')) + ba + ' ' + bb);
    for (const t of ['batches', 'categories', 'invoice_lines', 'invoices']) assert.deepStrictEqual(await q(B, `SELECT * FROM ${t} ORDER BY 1`), await q(A, `SELECT * FROM ${t} ORDER BY 1`), t);
  });
  await ok('a backup restored (Replace) on one device replaces the books on the other too', async () => {
    const folder = await A.run("return require('../src/services/backup').backupNow({ reason: 'manual' }).folder");
    await A.run("db.withCompany(db.firstCompanyId(), () => db.prepare(\"INSERT INTO categories(name) VALUES('After backup')\").run())");
    await both();
    assert.strictEqual((await q(B, "SELECT COUNT(*) n FROM categories WHERE name='After backup'"))[0].n, 1);
    await A.run(`return require('../src/services/backup').restore({ folder: ${JSON.stringify(folder)}, mode: 'replace' })`);
    await both(); await both();
    for (const dev of [A, B]) assert.strictEqual((await q(dev, "SELECT COUNT(*) n FROM categories WHERE name='After backup'"))[0].n, 0);
    for (const t of ['items', 'batches', 'parties', 'invoices', 'invoice_lines', 'ledger', 'categories', 'settings', 'counters']) {
      assert.deepStrictEqual(await q(B, `SELECT * FROM ${t} ORDER BY 1`), await q(A, `SELECT * FROM ${t} ORDER BY 1`), t);
    }
    // and syncing goes on as before
    await A.run("db.withCompany(db.firstCompanyId(), () => db.prepare(\"INSERT INTO categories(name) VALUES('After restore')\").run())");
    await both();
    assert.strictEqual((await q(B, "SELECT COUNT(*) n FROM categories WHERE name='After restore'"))[0].n, 1);
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
