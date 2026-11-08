// Merging on the iPhone engine: the iPhone's own book of the company joins the Mac's book.
//   node test/sync_merge_swift.js <path to bbcheck>
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert'), readline = require('readline');
const { fork, spawn, execFileSync } = require('child_process');
const { server } = require('./fake_firebase');
const BIN = process.argv[2];
if (!BIN || !fs.existsSync(BIN)) { console.error('usage: node test/sync_merge_swift.js <bbcheck>'); process.exit(2); }

(async () => {
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const port = server.address().port;
  const env = (dir) => ({ ...process.env, DATA_DIR: dir, HOME: dir, BILLBOX_FIREBASE_KEY: 'K', BILLBOX_FIREBASE_DB: `http://127.0.0.1:${port}`,
    BILLBOX_FIREBASE_AUTH: `http://127.0.0.1:${port}/v1`, BILLBOX_FIREBASE_TOKEN: `http://127.0.0.1:${port}/token`, NODE_NO_WARNINGS: '1' });
  const dirA = fs.mkdtempSync(path.join(os.tmpdir(), 'mergesw-A-')), dirB = fs.mkdtempSync(path.join(os.tmpdir(), 'mergesw-B-'));
  execFileSync(process.execPath, [path.join(__dirname, '../src/seed.js')], { env: env(dirA), stdio: 'ignore' });
  // the iPhone starts from the same books (as if restored from the Mac's backup)
  const file = fs.readdirSync(dirA).find((f) => /^company_.*\.db$/.test(f));
  fs.copyFileSync(path.join(dirA, file), path.join(dirB, 'distributor.db'));

  const dirC = fs.mkdtempSync(path.join(os.tmpdir(), 'mergesw-C-'));
  fs.copyFileSync(path.join(dirA, file), path.join(dirC, 'distributor.db'));
  const c = fork(path.join(__dirname, 'sync_device.js'), [], { env: env(dirC), stdio: ['ignore', 'ignore', 'inherit', 'ipc'] });
  let nc = 0; const wc = {};
  await new Promise((ok) => c.once('message', ok));
  c.on('message', (m) => { if (m.id && wc[m.id]) { const w = wc[m.id]; delete wc[m.id]; m.err ? w.no(new Error('C: ' + m.err)) : w.ok(m.r); } });
  const C = (code) => new Promise((ok, no) => { const id = ++nc; wc[id] = { ok, no }; c.send({ id, code }); });
  const a = fork(path.join(__dirname, 'sync_device.js'), [], { env: env(dirA), stdio: ['ignore', 'ignore', 'inherit', 'ipc'] });
  let na = 0; const wa = {};
  await new Promise((ok) => a.once('message', ok));
  a.on('message', (m) => { if (m.id && wa[m.id]) { const w = wa[m.id]; delete wa[m.id]; m.err ? w.no(new Error('A: ' + m.err)) : w.ok(m.r); } });
  const A = (code) => new Promise((ok, no) => { const id = ++na; wa[id] = { ok, no }; a.send({ id, code }); });
  const qa = (sql) => A(`return db.withCompany(1, () => db.prepare(${JSON.stringify(sql)}).all())`);

  const b = spawn(BIN, ['--serve', dirB], { env: env(dirB), stdio: ['pipe', 'pipe', 'inherit'] });
  let nb = 0; const wb = {};
  // if the iPhone engine stops (a crash), every waiting step fails instead of waiting for ever
  b.on('exit', (code) => { for (const k of Object.keys(wb)) { wb[k]({ id: k, status: 599, body: { error: `the iPhone engine stopped (${code})` } }); delete wb[k]; } });
  readline.createInterface({ input: b.stdout }).on('line', (l) => { let m; try { m = JSON.parse(l); } catch { return; } if (wb[m.id]) { wb[m.id](m); delete wb[m.id]; } });
  const B = (o) => new Promise((ok) => { const id = ++nb; wb[id] = ok; b.stdin.write(JSON.stringify({ id, ...o }) + '\n'); });
  let cB = 1;
  const api = async (method, p, body, company) => { const r = await B({ method, path: p, body: body || {}, company: company || cB }); if (r.status >= 400) throw new Error(`B ${p}: ${JSON.stringify(r.body)}`); return r.body; };
  const qb = async (sql) => (await B({ sql, company: cB })).body;
  const tick = async () => { for (let i = 0; i < 3; i++) { await A('return S.tick()'); await api('GET', '/api/sync/tick'); await C('return S.tick()'); } };
  const co = { company_gstin: '', state_code: '09', company_address: 'Bijnor', company_phone: '', invoice_terms: 'x' };

  let passed = 0;
  const ok = async (name, fn) => { await fn(); passed++; console.log('  ok  ', name); };
  try {
    await A("db.registry.prepare(\"UPDATE companies SET name='AK Enterprises' WHERE id=1\").run(); db.withCompany(1, () => db.prepare(\"UPDATE settings SET value='AK Enterprises' WHERE key='company_name'\").run()); await S.signIn({ email: 'm@x.in', password: 'secret1', create: true }); return S.turnOn(1)");
    await api('PUT', '/api/companies/1', { name: 'A.K ENTERPRISES', ...co });   // spelt differently: still the same company
    await api('POST', '/api/sync/signin', { email: 'm@x.in', password: 'secret1' });
    await ok('the iPhone cannot start a second book of the same company', async () => {
      await assert.rejects(api('POST', '/api/sync/on'), /already in your sync account/);
    });
    // how older versions got there
    await api('PUT', '/api/companies/1', { name: 'tmp', ...co });
    await api('POST', '/api/sync/on');
    await api('PUT', '/api/companies/1', { name: 'A.K ENTERPRISES', ...co });
    const [bt] = await qa('SELECT id,item_id,qty FROM batches WHERE qty > 20 ORDER BY exp_date, id LIMIT 1');
    await A(`return db.withCompany(1, () => billing.createInvoice({ pay_mode: 'CASH', lines: [{ item_id: ${bt.item_id}, batch_id: ${bt.id}, qty: 2 }] }))`);
    await api('POST', '/api/invoices', { pay_mode: 'CASH', lines: [{ item_id: bt.item_id, batch_id: bt.id, qty: 3 }] });
    await B({ sql: "INSERT INTO parties(name,type) VALUES('Only on iPhone','CUSTOMER')", company: 1 });
    // a third device (Android) with a copy of its own too (set up on its own: other ids), which the iPhone also brought here
    await C(`return db.withCompany(1, () => {
      db.pragma('foreign_keys = OFF');
      const shift = (t, by) => {
        db.prepare(\`UPDATE \${t} SET id = id + \${by}\`).run();
        for (const o of db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all())
          for (const f of db.prepare(\`PRAGMA foreign_key_list(\${o.name})\`).all()) if (f.table === t) db.prepare(\`UPDATE \${o.name} SET \${f.from} = \${f.from} + \${by} WHERE \${f.from} IS NOT NULL\`).run();
      };
      shift('items', 1000); shift('parties', 2000); shift('batches', 3000);
      db.pragma('foreign_keys = ON');
    })`);
    await C(`db.registry.prepare("UPDATE companies SET name='AK Enterprises' WHERE id=1").run(); db.withCompany(1, () => db.prepare("UPDATE settings SET value='AK Enterprises' WHERE key='company_name'").run());
      await S.signIn({ email: 'm@x.in', password: 'secret1' }); db.registry.prepare("UPDATE companies SET name='tmp2' WHERE id=1").run(); await S.turnOn(1);
      db.registry.prepare("UPDATE companies SET name='AK Enterprises' WHERE id=1").run()`);
    await C(`return db.withCompany(1, () => billing.createInvoice({ pay_mode: 'CASH', lines: [{ item_id: ${bt.item_id + 1000}, batch_id: ${bt.id + 3000}, qty: 4 }] }))`);
    await C("return S.tick()");
    const cKey = await C("return JSON.parse(db.registry.prepare(\"SELECT value FROM app_settings WHERE key='sync_map'\").get().value)['1']");
    const androidCopy = (await api('POST', '/api/sync/join', { key: cKey })).company_id;
    // and the Mac's copy was also brought here (so both are "On this iPhone")
    const mac = (await api('GET', '/api/sync/remote')).books.find((x) => x.same_name && !x.on_this_device);
    const joined = (await api('POST', '/api/sync/join', { key: mac.key })).company_id;
    await tick();
    await ok('the Android copy, merged on the iPhone into the Mac\'s copy: Android moves there by itself', async () => {
      cB = joined;
      const r = await api('GET', '/api/sync/remote');
      assert.ok(r.books.find((x) => x.key === cKey && x.same_name), JSON.stringify(r));
      const m = await api('POST', '/api/sync/merge', { key: cKey });
      assert.ok(m.company_id === joined && m.merged > 0, JSON.stringify(m));
      await tick();
      const cNow = await C('return Number(Object.keys(JSON.parse(db.registry.prepare("SELECT value FROM app_settings WHERE key=\'sync_map\'").get().value))[0])');
      assert.ok(cNow !== 1, 'Android moved to another company');
      assert.strictEqual((await qa(`SELECT qty FROM batches WHERE id=${bt.id}`))[0].qty, bt.qty - 6);
      const qc = await C(`return db.withCompany(${cNow}, () => db.prepare('SELECT qty FROM batches WHERE id=${bt.id}').all())`);
      assert.strictEqual(qc[0].qty, bt.qty - 6);
      const list = await api('GET', '/api/companies');
      assert.ok(!list.companies.some((x) => x.id === androidCopy), 'the Android copy is hidden on the iPhone');
    });
    await ok('merging from the Mac\'s copy (open on the iPhone) brings the iPhone\'s own copy into it', async () => {
      cB = joined;
      const own = (await api('GET', '/api/sync/remote')).books.find((x) => x.same_name && x.on_this_device);
      assert.ok(own, 'the iPhone\'s own copy is offered');
      const m = await api('POST', '/api/sync/merge', { key: own.key });
      assert.ok(m.on && m.company_id === joined && m.merged > 0, JSON.stringify(m));
      await tick();
      assert.strictEqual((await qa(`SELECT qty FROM batches WHERE id=${bt.id}`))[0].qty, bt.qty - 9);
      assert.strictEqual((await qa("SELECT COUNT(*) n FROM parties WHERE name='Only on iPhone'"))[0].n, 1);
      const nos = (await qa('SELECT invoice_no FROM invoices')).map((x) => x.invoice_no);
      assert.strictEqual(new Set(nos).size, 3); assert.ok(!nos.some((x) => x.includes('~')), nos.join(' '));
      for (const t of ['items', 'batches', 'parties', 'invoices', 'invoice_lines', 'ledger', 'counters', 'receipts']) {
        assert.deepStrictEqual(await qb(`SELECT * FROM ${t} ORDER BY 1`), JSON.parse(JSON.stringify(await qa(`SELECT * FROM ${t} ORDER BY 1`))), t);
      }
      const list = await api('GET', '/api/companies');
      assert.strictEqual(list.companies.length, 1);
      assert.strictEqual((await api('GET', '/api/sync/remote')).books.length, 1);
    });
    console.log(`sync merge (iPhone engine): ${passed} checks passed`);
  } catch (e) { console.error('  FAIL', e.message); process.exitCode = 1; } finally { a.kill(); b.kill(); c.kill(); server.close(); }
})();
