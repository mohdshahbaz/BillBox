// Runs a parity scenario through the Android engine bundle (assets/engine/engine.js) in a clean JavaScript context, with
// bridges that follow the Android app's rules (android/app/.../engine/*Bridge.kt): one SQL statement per call, numbers bound
// as REAL, BLOBs as base64, files through AndroidFS, no network. Output lines match ios/tests/parity/run-node.js.
// usage: node run-bundle.js <bundle.js> <data-dir> <scenario.json> <backup-dir>
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { DatabaseSync } = require('node:sqlite');
const [bundle, dataDir, scenarioFile, backupDir] = process.argv.slice(2);
fs.mkdirSync(dataDir, { recursive: true });

const ok = (v) => JSON.stringify({ ok: v === undefined ? null : v });
const err = (e) => JSON.stringify({ error: { code: e.code || 'EIO', message: e.message } });
const wrap = (f) => (...a) => { try { return ok(f(...a)); } catch (e) { return err(e); } };

const AndroidFS = {
  exists: wrap((p) => fs.existsSync(p)),
  stat: wrap((p) => { const s = fs.statSync(p); return { size: s.size, mtime: s.mtimeMs, dir: s.isDirectory() }; }),
  read: wrap((p) => fs.readFileSync(p).toString('base64')),
  write: wrap((p, b64) => { fs.writeFileSync(p, Buffer.from(b64, 'base64')); }),
  mkdir: wrap((p, rec) => { fs.mkdirSync(p, { recursive: rec === 'true' || rec === true }); }),
  readdir: wrap((p) => fs.readdirSync(p).sort()),
  rm: wrap((p, rec, force) => { fs.rmSync(p, { recursive: rec === 'true' || rec === true, force: force === 'true' || force === true }); }),
  rename: wrap((a, b) => fs.renameSync(a, b)),
  copy: wrap((a, b) => fs.copyFileSync(a, b)),
  mkdtemp: wrap((prefix) => fs.mkdtempSync(prefix)),
};

const dbs = new Map(); let next = 1;
const sqlErr = (e) => JSON.stringify({ error: { message: e.message, errcode: e.errcode || 1 } });
const blobIn = (v) => (v && typeof v === 'object' && v.$b64 !== undefined ? new Uint8Array(Buffer.from(v.$b64, 'base64')) : v);
const blobOut = (r) => { const o = {}; for (const [k, v] of Object.entries(r)) o[k] = v instanceof Uint8Array ? { $b64: Buffer.from(v).toString('base64') } : v; return o; };
const AndroidSQL = {
  open(file, ro) { try { const h = next++; dbs.set(h, new DatabaseSync(file, { readOnly: ro === true || ro === 'true' })); return JSON.stringify({ handle: h }); } catch (e) { return sqlErr(e); } },
  exec(h, sql) {
    try {
      const d = dbs.get(Number(h));
      if (/^\s*PRAGMA/i.test(sql)) d.prepare(sql).all(); else d.exec(sql);   // Android: PRAGMA through a query, others executed
      return '{}';
    } catch (e) { return sqlErr(e); }
  },
  query(h, sql, args, mode) {
    try {
      const st = dbs.get(Number(h)).prepare(sql);
      const a = JSON.parse(args).map(blobIn);
      if (mode === 'run') { const r = st.run(...a); return JSON.stringify({ changes: Number(r.changes), lastInsertRowid: Number(r.lastInsertRowid) }); }
      const rows = mode === 'get' ? [st.get(...a)].filter((x) => x !== undefined) : st.all(...a);
      return JSON.stringify({ rows: rows.map(blobOut) });
    } catch (e) { return sqlErr(e); }
  },
  close(h) { try { dbs.get(Number(h)).close(); dbs.delete(Number(h)); return '{}'; } catch (e) { return sqlErr(e); } },
};
const AndroidHost = { dataDir: () => dataDir, home: () => path.dirname(backupDir), tmp: () => require('os').tmpdir(), reply() {}, ready() {} };

const ctx = vm.createContext({
  AndroidHost, AndroidSQL, AndroidFS, console: { log() {}, warn() {}, error: (...a) => process.env.BBDEBUG && process.stderr.write(a.join(' ') + '\n') },
  setTimeout, clearTimeout, setInterval: () => ({ unref() {} }), clearInterval() {},
  TextEncoder, TextDecoder, atob, btoa, URL, URLSearchParams, AbortSignal, AbortController, Intl, crypto: globalThis.crypto,
});
ctx.globalThis = ctx;
vm.runInContext(fs.readFileSync(bundle, 'utf8'), ctx, { filename: 'engine.js' });

(async () => {
  const steps = JSON.parse(fs.readFileSync(scenarioFile, 'utf8'));
  const emit = (o) => process.stdout.write(JSON.stringify(o) + '\n');
  for (let i = 0; i < steps.length; i++) {
    const st = steps[i];
    try {
      const r = JSON.parse(JSON.stringify(await ctx.BillBox.call(st)));
      if (st.op) { emit({ step: i, ...r }); continue; }
      if (r.b64 !== undefined) { const bytes = Buffer.from(r.b64, 'base64'); if (st.to) fs.writeFileSync(st.to, bytes); emit({ step: i, status: r.status, file: r.file, bytes: bytes.length }); }
      else if (r.html !== undefined) emit({ step: i, status: r.status, bytes: r.html.length });
      else emit({ step: i, status: r.status, body: r.body });
    } catch (e) { emit({ step: i, exception: String(e && e.stack || e) }); }
  }
})();
