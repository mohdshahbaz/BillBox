// A synced company's copy is deleted from the sync account only when no other device is still linked to it:
//   node test/sync_delete.js
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert');
const { fork, execFileSync } = require('child_process');
const { server } = require('./fake_firebase');

(async () => {
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const port = server.address().port;
  const mk = (name, host) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), `delete-${name}-`));
    const env = { ...process.env, DATA_DIR: dir, BILLBOX_FIREBASE_KEY: 'K', BILLBOX_FIREBASE_DB: `http://127.0.0.1:${port}`,
      BILLBOX_FIREBASE_AUTH: `http://127.0.0.1:${port}/v1`, BILLBOX_FIREBASE_TOKEN: `http://127.0.0.1:${port}/token`, NODE_NO_WARNINGS: '1', TEST_HOSTNAME: host, NODE_OPTIONS: `--require ${path.join(__dirname, 'hostname_preload.js')}` };
    execFileSync(process.execPath, [path.join(__dirname, '../src/seed.js')], { env, stdio: 'ignore' });
    const p = fork(path.join(__dirname, 'sync_device.js'), [], { env, stdio: ['ignore', 'ignore', 'inherit', 'ipc'] });
    let n = 0; const wait = {};
    const ready = new Promise((ok) => p.once('message', ok));
    p.on('message', (m) => { if (m.id && wait[m.id]) { const w = wait[m.id]; delete wait[m.id]; m.err ? w.no(new Error(`${name}: ${m.err}`)) : w.ok(m.r); } });
    return { run: (code) => new Promise((ok, no) => { const id = ++n; wait[id] = { ok, no }; p.send({ id, code }); }), ready, kill: () => p.kill() };
  };
  const A = mk('A', 'shop-mac'), B = mk('B', 'shop-iphone');
  await Promise.all([A.ready, B.ready]);
  let passed = 0;
  const ok = async (name, fn) => { await fn(); passed++; console.log('  ok  ', name); };
  try {
    await A.run("await S.signIn({ email: 'd@x.in', password: 'secret1', create: true }); return S.turnOn(1)");
    await B.run("await S.signIn({ email: 'd@x.in', password: 'secret1' })");
    const { books } = await A.run('return S.remote(1)');
    const key = books[0].key;
    const joined = await B.run(`return S.join(${JSON.stringify(key)})`);
    await A.run('return S.tick()'); await B.run('return S.tick()');
    const bCid = joined.company_id;

    await ok('a copy another device still uses cannot be deleted', async () => {
      await assert.rejects(A.run(`return S.removeBook(${JSON.stringify(key)})`), /still in use by/);
      const after = await A.run('return S.remote(1)');
      assert.strictEqual(after.books.length, 1);
    });

    await ok('once the other device stops syncing it, the copy is deleted from the account', async () => {
      await B.run(`return S.turnOff(${bCid})`);
      await A.run(`return S.removeBook(${JSON.stringify(key)})`);
      const after = await A.run('return S.remote(1)');
      assert.strictEqual(after.books.length, 0);
      const st = await A.run('return S.status(1)');
      assert.strictEqual(st.on, false);
    });

    await ok('deleting an unknown copy says so', async () => {
      await assert.rejects(A.run(`return S.removeBook(${JSON.stringify(key)})`), /no longer in the sync account/);
    });

    console.log(`sync delete: ${passed} checks passed`);
  } catch (e) {
    console.error('FAILED:', e.message);
    process.exitCode = 1;
  } finally {
    A.kill(); B.kill(); server.close();
  }
})();
