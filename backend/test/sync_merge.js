// Two devices that turned sync on for their own copy of one company (two books) are merged into one book:
//   node test/sync_merge.js
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert');
const { fork, execFileSync } = require('child_process');
const { server } = require('./fake_firebase');

(async () => {
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const port = server.address().port;
  const mk = (name, from) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), `merge-${name}-`));
    const env = { ...process.env, DATA_DIR: dir, BILLBOX_FIREBASE_KEY: 'K', BILLBOX_FIREBASE_DB: `http://127.0.0.1:${port}`,
      BILLBOX_FIREBASE_AUTH: `http://127.0.0.1:${port}/v1`, BILLBOX_FIREBASE_TOKEN: `http://127.0.0.1:${port}/token`, NODE_NO_WARNINGS: '1' };
    execFileSync(process.execPath, [path.join(__dirname, '../src/seed.js')], { env, stdio: 'ignore' });   // the same starting books on both
    if (from) { const f = fs.readdirSync(dir).find((x) => /^company_.*\.db$/.test(x)); fs.copyFileSync(path.join(from, fs.readdirSync(from).find((x) => /^company_.*\.db$/.test(x))), path.join(dir, f)); }
    const p = fork(path.join(__dirname, 'sync_device.js'), [], { env, stdio: ['ignore', 'ignore', 'inherit', 'ipc'] });
    let n = 0; const wait = {};
    const ready = new Promise((ok) => p.once('message', ok));
    p.on('message', (m) => { if (m.id && wait[m.id]) { const w = wait[m.id]; delete wait[m.id]; m.err ? w.no(new Error(`${name}: ${m.err}`)) : w.ok(m.r); } });
    return { dir, run: (code) => new Promise((ok, no) => { const id = ++n; wait[id] = { ok, no }; p.send({ id, code }); }), ready, kill: () => p.kill() };
  };
  const A = mk('A'), B = mk('B'), C = mk('C');
  await Promise.all([A.ready, B.ready, C.ready]);
  // C set its books up on its own: the same items, parties and batches under other ids
  await C.run(`return db.withCompany(1, () => {
    db.pragma('foreign_keys = OFF');
    const shift = (t, by) => {
      db.prepare(\`UPDATE \${t} SET id = id + \${by}\`).run();
      for (const o of db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all())
        for (const f of db.prepare(\`PRAGMA foreign_key_list(\${o.name})\`).all()) if (f.table === t) db.prepare(\`UPDATE \${o.name} SET \${f.from} = \${f.from} + \${by} WHERE \${f.from} IS NOT NULL\`).run();
    };
    shift('items', 1000); shift('parties', 2000); shift('batches', 3000); shift('categories', 400);
    db.pragma('foreign_keys = ON');
  })`);
  let cB = 1, cA = 1;
  const q = (dev, sql, c) => dev.run(`return db.withCompany(${c || (dev === A ? cA : cB)}, () => db.prepare(${JSON.stringify(sql)}).all())`);
  const tick = async () => { for (let i = 0; i < 3; i++) { await A.run('return S.tick()'); await B.run('return S.tick()'); } };
  let passed = 0;
  const ok = async (name, fn) => { await fn(); passed++; console.log('  ok  ', name); };
  try {
    const rename = (n) => `db.registry.prepare('UPDATE companies SET name=? WHERE id=1').run(${JSON.stringify(n)}); db.withCompany(1, () => db.prepare("UPDATE settings SET value=? WHERE key='company_name'").run(${JSON.stringify(n)}))`;
    await A.run(rename('AK Enterprises')); await B.run(rename('AK Enterprises'));
    const [bt] = await q(A, 'SELECT id,item_id,qty FROM batches WHERE qty > 20 ORDER BY exp_date, id LIMIT 1');

    await ok('a second device cannot start another book of the same company', async () => {
      await A.run("await S.signIn({ email: 'm@x.in', password: 'secret1', create: true }); return S.turnOn(1)");
      await B.run("await S.signIn({ email: 'm@x.in', password: 'secret1' })");
      await assert.rejects(B.run('return S.turnOn(1)'), /already in your sync account/);
    });
    // how older versions got there: each device turned on sync for its own copy
    await B.run("db.registry.prepare(\"UPDATE companies SET name='tmp' WHERE id=1\").run(); await S.turnOn(1); db.registry.prepare(\"UPDATE companies SET name='AK Enterprises' WHERE id=1\").run()");
    const sell = (dev, n) => dev.run(`return db.withCompany(1, () => billing.createInvoice({ pay_mode: 'CASH', lines: [{ item_id: ${bt.item_id}, batch_id: ${bt.id}, qty: ${n} }] }))`);
    await sell(A, 2); await sell(B, 3);
    await B.run("db.withCompany(1, () => db.prepare(\"INSERT INTO parties(name,type) VALUES('Only on B','CUSTOMER')\").run())");
    await tick();
    assert.strictEqual((await q(A, "SELECT COUNT(*) n FROM parties WHERE name='Only on B'"))[0].n, 0, 'two books: nothing crosses');

    await ok('the other copy is offered for merging', async () => {
      const r = await B.run('return S.remote(1)');
      assert.ok(r.can_merge);
      assert.strictEqual(r.books.filter((b) => b.same_name).length, 1);
    });
    await ok('merging on B (its copy open): A\'s bills come in, A moves to B\'s copy by itself, stock counts both, numbers differ', async () => {
      const r = await B.run('const l = await S.remote(1); return S.merge(1, l.books.find((b) => b.same_name).key)');
      cB = r.company_id;
      assert.ok(r.on && cB === 1 && r.merged > 0, JSON.stringify(r));
      await tick();
      const t = await A.run('return S.tick()');
      cA = Number(t.moved[1]);
      assert.ok(cA && cA !== 1, JSON.stringify(t));
      await tick();
      const [x] = await q(A, `SELECT qty FROM batches WHERE id=${bt.id}`);
      assert.strictEqual(x.qty, bt.qty - 5);
      assert.strictEqual((await q(A, "SELECT COUNT(*) n FROM parties WHERE name='Only on B'"))[0].n, 1);
      const nos = (await q(A, 'SELECT invoice_no FROM invoices')).map((y) => y.invoice_no);
      assert.strictEqual(nos.length, 2); assert.strictEqual(new Set(nos).size, 2); assert.ok(!nos.some((y) => y.includes('~')), nos.join(' '));
      for (const t of ['items', 'batches', 'parties', 'invoices', 'invoice_lines', 'ledger', 'counters', 'settings', 'receipts']) {
        assert.deepStrictEqual(await q(B, `SELECT * FROM ${t} ORDER BY 1`), await q(A, `SELECT * FROM ${t} ORDER BY 1`), t);
      }
    });
    await ok('each device shows one AK Enterprises (the old copy is kept, hidden), and the account lists one book', async () => {
      for (const dev of [A, B]) {
        const list = await dev.run('return db.registry.prepare("SELECT id,name FROM companies WHERE active=1").all()');
        assert.deepStrictEqual(list.map((c) => c.name).sort(), ['AK Enterprises']);
      }
      assert.strictEqual((await B.run(`return S.remote(${cB})`)).books.length, 1);
      // and they keep syncing
      await A.run(`db.withCompany(${cA}, () => db.prepare("INSERT INTO categories(name) VALUES('After merge')").run())`);
      await tick();
      assert.strictEqual((await q(B, "SELECT COUNT(*) n FROM categories WHERE name='After merge'"))[0].n, 1);
    });
    await ok('a copy set up on its own (other ids) is merged by names: its sale and new party come in, nothing doubles', async () => {
      await C.run(`const n = 'AK Enterprises'; db.registry.prepare("UPDATE companies SET name='tmp3' WHERE id=1").run();
        db.withCompany(1, () => db.prepare("UPDATE settings SET value=? WHERE key='company_name'").run(n));
        await S.signIn({ email: 'm@x.in', password: 'secret1' }); await S.turnOn(1); db.registry.prepare("UPDATE companies SET name=? WHERE id=1").run(n)`);
      await C.run(`return db.withCompany(1, () => billing.createInvoice({ pay_mode: 'CASH', lines: [{ item_id: ${bt.item_id + 1000}, batch_id: ${bt.id + 3000}, qty: 4 }] }))`);
      await C.run("db.withCompany(1, () => db.prepare(\"INSERT INTO parties(name,type) VALUES('Only on C','CUSTOMER')\").run())");
      await C.run('return S.tick()');
      const items = (await q(A, 'SELECT COUNT(*) n FROM items'))[0].n, parties = (await q(A, 'SELECT COUNT(*) n FROM parties'))[0].n;
      const cKey = await C.run("return JSON.parse(db.registry.prepare(\"SELECT value FROM app_settings WHERE key='sync_map'\").get().value)['1']");
      const r = await B.run(`return S.merge(${cB}, ${JSON.stringify(cKey)})`);
      assert.ok(r.merged > 0, JSON.stringify(r));
      for (let i = 0; i < 3; i++) { await tick(); await C.run('return S.tick()'); }
      assert.strictEqual((await q(A, `SELECT qty FROM batches WHERE id=${bt.id}`))[0].qty, bt.qty - 9);
      assert.strictEqual((await q(A, 'SELECT COUNT(*) n FROM items'))[0].n, items, 'no item doubled');
      assert.strictEqual((await q(A, 'SELECT COUNT(*) n FROM parties'))[0].n, parties + 1, 'only the new party');
      const nos = (await q(A, 'SELECT invoice_no FROM invoices')).map((y) => y.invoice_no);
      assert.strictEqual(new Set(nos).size, nos.length); assert.ok(!nos.some((y) => y.includes('~')), nos.join(' '));
      const lines = await q(A, 'SELECT item_id, batch_id FROM invoice_lines ORDER BY id DESC LIMIT 1');
      assert.deepStrictEqual(lines[0], { item_id: bt.item_id, batch_id: bt.id }, 'C\'s bill points at the items here');
      const cNow = Number((await C.run('return S.tick()')).moved[1]);
      assert.ok(cNow > 1, 'C moved to the kept copy');
      assert.deepStrictEqual(await C.run(`return db.withCompany(${cNow}, () => db.prepare('SELECT * FROM batches ORDER BY 1').all())`), await q(A, 'SELECT * FROM batches ORDER BY 1'));
    });
    console.log(`sync merge: ${passed} checks passed`);
  } catch (e) { console.error('  FAIL', e.message); process.exitCode = 1; } finally { A.kill(); B.kill(); C.kill(); server.close(); }
})();
