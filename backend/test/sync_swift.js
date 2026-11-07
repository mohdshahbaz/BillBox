// Live sync between the Mac's engine (Node) and the iPhone's (BillBoxCore, Swift) through a fake Firebase:
//   node test/sync_swift.js <path to bbcheck>     (bbcheck: swift build in ios/BillBoxCore)
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert'), readline = require('readline');
const { fork, spawn, execFileSync } = require('child_process');
const { server } = require('./fake_firebase');
const BIN = process.argv[2];
if (!BIN || !fs.existsSync(BIN)) { console.error('usage: node test/sync_swift.js <bbcheck>'); process.exit(2); }

(async () => {
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const port = server.address().port;
  const env = (dir) => ({ ...process.env, DATA_DIR: dir, BILLBOX_FIREBASE_KEY: 'K', BILLBOX_FIREBASE_DB: `http://127.0.0.1:${port}`,
    BILLBOX_FIREBASE_AUTH: `http://127.0.0.1:${port}/v1`, BILLBOX_FIREBASE_TOKEN: `http://127.0.0.1:${port}/token`, NODE_NO_WARNINGS: '1' });

  // A: the Mac (Node), seeded with the demo books
  const dirA = fs.mkdtempSync(path.join(os.tmpdir(), 'syncsw-A-'));
  execFileSync(process.execPath, [path.join(__dirname, '../src/seed.js')], { env: env(dirA), stdio: 'ignore' });
  const a = fork(path.join(__dirname, 'sync_device.js'), [], { env: env(dirA), stdio: ['ignore', 'ignore', 'inherit', 'ipc'] });
  let na = 0; const wa = {};
  await new Promise((ok) => a.once('message', ok));
  a.on('message', (m) => { if (m.id && wa[m.id]) { const w = wa[m.id]; delete wa[m.id]; m.err ? w.no(new Error('A: ' + m.err)) : w.ok(m.r); } });
  const A = (code) => new Promise((ok, no) => { const id = ++na; wa[id] = { ok, no }; a.send({ id, code }); });
  const qa = (sql) => A(`return db.withCompany(db.firstCompanyId(), () => db.prepare(${JSON.stringify(sql)}).all())`);

  // B: the iPhone engine
  const dirB = fs.mkdtempSync(path.join(os.tmpdir(), 'syncsw-B-'));
  const b = spawn(BIN, ['--serve', dirB], { env: { ...env(dirB), HOME: dirB }, stdio: ['pipe', 'pipe', 'inherit'] });
  let nb = 0; const wb = {};
  readline.createInterface({ input: b.stdout }).on('line', (l) => { let m; try { m = JSON.parse(l); } catch { return; } if (wb[m.id]) { wb[m.id](m); delete wb[m.id]; } });
  const B = (o) => new Promise((ok) => { const id = ++nb; wb[id] = ok; b.stdin.write(JSON.stringify({ id, ...o }) + '\n'); });
  const api = async (method, p, body, company) => { const r = await B({ method, path: p, body: body || {}, company }); if (r.status >= 400) throw new Error(`B ${p}: ${JSON.stringify(r.body)}`); return r.body; };
  let cB = null;
  const qb = async (sql) => (await B({ sql, company: cB })).body;
  const both = async () => { for (let i = 0; i < 3; i++) { await A('return S.tick()'); await api('GET', '/api/sync/tick'); } };
  const same = async (t) => assert.deepStrictEqual(await qb(`SELECT * FROM ${t} ORDER BY 1`), JSON.parse(JSON.stringify(await qa(`SELECT * FROM ${t} ORDER BY 1`))), t);

  let passed = 0;
  const ok = async (name, fn) => { await fn(); passed++; console.log('  ok  ', name); };
  try {
    await ok('the Mac makes the sync account and syncs its company', async () => {
      // (a real shop's name: the iPhone's own empty "My Company" is another company)
      const s = await A(`const c = db.firstCompanyId(); db.registry.prepare("UPDATE companies SET name='AK Enterprises' WHERE id=?").run(c);
        db.withCompany(c, () => db.prepare("UPDATE settings SET value='AK Enterprises' WHERE key='company_name'").run());
        await S.signIn({ email: 'shop@x.in', password: 'secret1', create: true }); return S.turnOn(c)`);
      assert.ok(s.on && s.slot === 1);
    });
    await ok('the iPhone signs in (its own slot) and brings the company here', async () => {
      await assert.rejects(api('POST', '/api/sync/signin', { email: 'shop@x.in', password: 'nope' }), /Wrong e-mail or password/);
      const s = await api('POST', '/api/sync/signin', { email: 'shop@x.in', password: 'secret1' });
      assert.strictEqual(s.slot, 2);
      const r = await api('GET', '/api/sync/remote');
      assert.strictEqual(r.books.length, 1);
      const j = await api('POST', '/api/sync/join', { key: r.books[0].key });
      cB = j.company_id;
      assert.ok(j.on && cB, JSON.stringify(j));
      for (const t of ['items', 'batches', 'parties', 'settings', 'categories', 'counters']) await same(t);
    });
    await ok('bills on the iPhone and the Mac at the same moment: both reach both, stock counts both, numbers differ', async () => {
      const [bt] = await qa('SELECT id,item_id,qty FROM batches WHERE qty > 20 ORDER BY id LIMIT 1');
      const inv = await api('POST', '/api/invoices', { pay_mode: 'CASH', lines: [{ item_id: bt.item_id, batch_id: bt.id, qty: 5 }] }, cB);
      assert.ok(inv.id > 20000000 && inv.id < 30000000, String(inv.id));
      await A(`return db.withCompany(db.firstCompanyId(), () => billing.createInvoice({ pay_mode: 'CASH', lines: [{ item_id: ${bt.item_id}, batch_id: ${bt.id}, qty: 2 }] }))`);
      await both();
      const [x] = await qa(`SELECT qty FROM batches WHERE id=${bt.id}`), [y] = await qb(`SELECT qty FROM batches WHERE id=${bt.id}`);
      assert.strictEqual(x.qty, bt.qty - 7); assert.strictEqual(y.qty, bt.qty - 7);
      for (const t of ['invoices', 'invoice_lines', 'ledger', 'receipts', 'counters', 'batches']) await same(t);
      const nos = (await qa('SELECT invoice_no FROM invoices')).map((r) => r.invoice_no);
      assert.strictEqual(new Set(nos).size, 2); assert.ok(!nos.some((n) => n.includes('~')), nos.join(' '));
    });
    await ok('an edit on the iPhone and a delete on the Mac show on the other', async () => {
      const [p] = await qb('SELECT id FROM parties ORDER BY id LIMIT 1');
      await B({ sql: `UPDATE parties SET name='From iPhone', phone=NULL WHERE id=${p.id}`, company: cB });
      await A("db.withCompany(db.firstCompanyId(), () => db.prepare(\"INSERT INTO categories(name) VALUES('Temp')\").run())");
      await both();
      await A("db.withCompany(db.firstCompanyId(), () => db.prepare(\"DELETE FROM categories WHERE name='Temp'\").run())");
      await both();
      assert.deepStrictEqual((await qa(`SELECT name,phone FROM parties WHERE id=${p.id}`))[0], { name: 'From iPhone', phone: null });
      for (const t of ['parties', 'categories']) await same(t);
      const s = await api('GET', '/api/sync', null, cB);
      assert.strictEqual(s.pending, 0); assert.strictEqual(s.errors, 0);
    });
    await ok('the company edited on the iPhone (name, GSTIN) shows edited on the Mac, and back', async () => {
      await api('PUT', `/api/companies/${cB}`, { name: 'AK Enterprises Bijnor', company_gstin: '09ABCDE1234F1Z5', state_code: '09', company_address: 'Civil Lines', company_phone: '', invoice_terms: 'x' }, cB);
      await both();
      const ma = await A("return db.registry.prepare('SELECT name FROM companies WHERE id=?').get(db.firstCompanyId()).name");
      assert.strictEqual(ma, 'AK Enterprises Bijnor');
      assert.deepStrictEqual(await qa("SELECT value FROM settings WHERE key='company_gstin'"), [{ value: '09ABCDE1234F1Z5' }]);
      await A(`db.withCompany(db.firstCompanyId(), () => db.prepare("UPDATE settings SET value='AK Enterprises' WHERE key='company_name'").run())`);
      await both();
      const list = await api('GET', '/api/companies');
      assert.strictEqual(list.companies.find((c) => c.id === cB).name, 'AK Enterprises');
    });
    await ok('the same category and batch made on the Mac and the iPhone at once become one', async () => {
      const [it] = await qa('SELECT id FROM items ORDER BY id LIMIT 1');
      const exp = new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10);
      await A(`return db.withCompany(db.firstCompanyId(), () => { db.prepare("INSERT INTO categories(name) VALUES('Same')").run();
        db.prepare('INSERT INTO batches(item_id,batch_no,exp_date,qty) VALUES(?,?,?,?)').run(${it.id}, 'B-SAME', '${exp}', 10); })`);
      await B({ sql: "INSERT INTO categories(name) VALUES('Same')", company: cB });
      await B({ sql: 'INSERT INTO batches(item_id,batch_no,exp_date,qty) VALUES(?,?,?,?)', args: [it.id, 'B-SAME', exp, 20], company: cB });
      await api('POST', '/api/invoices', { pay_mode: 'CASH', lines: [{ item_id: it.id, qty: 3 }] }, cB);
      await both();
      for (const rows of [await qa("SELECT qty FROM batches WHERE batch_no='B-SAME'"), await qb("SELECT qty FROM batches WHERE batch_no='B-SAME'")]) assert.deepStrictEqual(rows, [{ qty: 27 }]);
      for (const t of ['batches', 'categories', 'invoice_lines', 'invoices', 'ledger']) await same(t);
    });
    await ok('a backup restored (Replace) on the iPhone replaces the books on the Mac too', async () => {
      const run = await api('POST', '/api/backup/run', {});
      await A("db.withCompany(db.firstCompanyId(), () => db.prepare(\"INSERT INTO categories(name) VALUES('After backup')\").run())");
      await both();
      assert.strictEqual((await qb("SELECT COUNT(*) n FROM categories WHERE name='After backup'"))[0].n, 1);
      const rr = await api('POST', '/api/backup/restore', { folder: run.folder, mode: 'replace' });
      assert.ok(rr.restored.includes('AK Enterprises'), JSON.stringify(rr));
      await both();
      assert.strictEqual((await qa("SELECT COUNT(*) n FROM categories WHERE name='After backup'"))[0].n, 0);
      for (const t of ['items', 'batches', 'parties', 'invoices', 'invoice_lines', 'ledger', 'categories', 'settings', 'counters']) await same(t);
      await B({ sql: "INSERT INTO categories(name) VALUES('After restore')", company: cB });
      await both();
      assert.strictEqual((await qa("SELECT COUNT(*) n FROM categories WHERE name='After restore'"))[0].n, 1);
    });
    console.log(`sync (Mac ⇄ iPhone engine): ${passed} checks passed`);
  } catch (e) {
    console.error('  FAIL', e.message); process.exitCode = 1;
  } finally { a.kill(); b.kill(); server.close(); }
})();
