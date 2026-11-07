// Runs a parity scenario through the Mac app's own Node code (backend/src routes and services), one JSON line per step.
// usage: node run-node.js <data-dir> <scenario.json> <backup-dir>
const path = require('path'), fs = require('fs'), Module = require('module');
const [dataDir, scenarioFile, backupDir] = process.argv.slice(2);
process.env.DATA_DIR = dataDir;
const shim = path.join(__dirname, 'express-shim.js');
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (req, ...a) { return req === 'express' ? shim : origResolve.call(this, req, ...a); };
const os = require('os');
os.homedir = () => path.dirname(backupDir);           // the backup service's default folder is <home>/DistributorProBackups
globalThis.fetch = () => Promise.reject(new Error('offline'));   // category guesses use the keyword rules only, like the Swift run

const SRC = path.join(__dirname, '../../../backend/src');
const db = require(path.join(SRC, 'db'));
const B = require(path.join(SRC, 'services/backup'));
const { parseInvoicePages } = require(path.join(SRC, 'services/pdfParser'));
const { createMissing } = require(path.join(SRC, 'services/autoCreate'));
const { settings } = require(path.join(SRC, 'services/billing'));
const open = (n) => require(path.join(SRC, 'routes', n));
const pre = ['companies', 'backup'].map(open);
const post = ['items', 'parties', 'salesmen', 'invoices', 'purchases', 'debitNotes', 'import', 'reports'].map(open);

function match(router, method, segs) {
  for (const rt of router.routes) {
    if (rt.m !== method) continue;
    const ps = rt.p.split('/').filter(Boolean);
    if (ps.length !== segs.length) continue;
    const params = {};
    let ok = true;
    ps.forEach((p, i) => { if (p.startsWith(':')) params[p.slice(1)] = decodeURIComponent(segs[i]); else if (p !== segs[i]) ok = false; });
    if (ok) return { rt, params };
  }
  return null;
}

function request(step) {
  return new Promise((resolve) => {
    const method = (step.method || 'GET').toUpperCase();
    const segs = (step.path || '/').split('?')[0].split('/').filter(Boolean);
    const query = {};
    for (const [k, v] of Object.entries(step.query || {})) query[k] = String(v);
    const headers = { 'x-company-id': step.company !== undefined ? String(step.company) : undefined };
    const req = { params: {}, query, body: step.body || {}, get: (h) => headers[h.toLowerCase()] };
    let status = 200, sent = false; const hdr = {};
    const res = {
      status(c) { status = c; return res; },
      json(v) { if (!sent) { sent = true; resolve({ status, body: JSON.parse(JSON.stringify(v === undefined ? null : v)) }); } return res; },
      type() { return res; }, set(h) { Object.assign(hdr, h || {}); return res; },
      send(v) { if (!sent) { sent = true; resolve({ status, file: (/filename="([^"]+)"/.exec(hdr['Content-Disposition'] || '') || [])[1], bytes: Buffer.isBuffer(v) ? v : Buffer.from(String(v)) }); } return res; },
    };
    const onError = (err) => {   // server.js error handler
      if (err && (String(err.code || '').startsWith('SQLITE_CONSTRAINT') || (err.code === 'ERR_SQLITE_ERROR' && (Number(err.errcode) & 255) === 19))) {
        const msg = /UNIQUE/.test(err.message) ? 'That value already exists (for example a duplicate batch number).' : 'Invalid reference or missing value.';
        return res.status(409).json({ error: msg });
      }
      const st = err.status || 500;
      const { HttpError } = require(path.join(SRC, 'utils/misc'));
      res.status(st).json({ error: st === 500 ? 'Server error' : err.message, code: err.code, detail: st === 500 && err instanceof HttpError ? err.message : undefined });
    };
    const run = (m) => { req.params = m.params; try { m.rt.hs[m.rt.hs.length - 1](req, res, (e) => (e ? onError(e) : res.status(404).json({ error: 'Not found' }))); } catch (e) { onError(e); } };
    for (const r of pre) { const m = match(r, method, segs); if (m) return run(m); }
    const id = Number(req.get('x-company-id')) || db.firstCompanyId();
    const d = db.openCompany(id);
    if (!d) return res.status(404).json({ error: 'Company not found' });
    db.withCompany(id, () => {
      for (const r of post) { const m = match(r, method, segs); if (m) return run(m); }
      res.status(404).json({ error: 'Not found' });
    });
  });
}

function dump() {
  const out = {};
  out.registry = db.registry.prepare('SELECT id,name,file,active,fy FROM companies ORDER BY id').all().map((r) => { const x = { ...r }; delete x.file; return x; });
  out.app_settings = db.registry.prepare("SELECT key,value FROM app_settings WHERE key NOT LIKE 'backup_last%' AND key NOT LIKE 'num_follow_checked%' ORDER BY key").all();
  out.companies = {};
  for (const { id } of db.registry.prepare('SELECT id FROM companies ORDER BY id').all()) {
    const d = db.openCompany(id);
    if (!d) continue;
    const t = {};
    for (const { name } of d.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all())
      t[name] = d.prepare(`SELECT * FROM ${name} ORDER BY 1`).all().map((r) => { const x = { ...r }; delete x.created_at; return x; });
    out.companies[String(id)] = t;
  }
  return out;
}

(async () => {
  const steps = JSON.parse(fs.readFileSync(scenarioFile, 'utf8'));
  const emit = (o) => process.stdout.write(JSON.stringify(o) + '\n');
  for (let i = 0; i < steps.length; i++) {
    const st = steps[i];
    try {
      if (st.op === 'dump') { emit({ step: i, dump: dump() }); continue; }
      if (st.op === 'parse') { const c = st.ctx || {}; emit({ step: i, parse: parseInvoicePages(st.pages || [], c) }); continue; }
      if (st.op === 'autocreate') {
        const id = st.company || db.firstCompanyId();
        const r = await db.withCompany(id, async () => {
          const co = settings();
          const parsed = parseInvoicePages(st.pages, { items: db.prepare('SELECT id,name,hsn,gst_rate FROM items WHERE active=1').all(),
            parties: db.prepare("SELECT id,name,gstin FROM parties WHERE active=1 AND type='SUPPLIER'").all(), companyGstin: co.company_gstin, companyName: co.company_name });
          return createMissing(parsed, { online: false });
        });
        emit({ step: i, parse: JSON.parse(JSON.stringify(r)) }); continue;
      }
      if (st.op === 'pagetext') { const { pageTextFromItems } = require(path.join(SRC, 'services/pdfExtract')); emit({ step: i, text: st.pages.map(pageTextFromItems) }); continue; }
      if (st.op === 'backup') { const r = B.backupNow({ reason: 'manual' }); emit({ step: i, folder: r.folder, files: r.files }); continue; }
      const r = await request(st);
      if (r.bytes) { if (st.to) fs.writeFileSync(st.to, r.bytes); emit({ step: i, status: r.status, file: r.file, bytes: r.bytes.length }); }
      else emit({ step: i, status: r.status, body: r.body });
    } catch (e) { emit({ step: i, exception: String(e && e.stack || e) }); }
  }
})();
