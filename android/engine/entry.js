// BillBox engine for Android: the Mac's own engine (backend/src) inside the app's hidden WebView.
// The app calls BillBox.handle(json) for each request, one at a time, and gets the reply through AndroidHost.reply(id, json).
// Routing, company selection and error replies are exactly the Mac server's (backend/src/server.js).
'use strict';
const db = require('../../backend/src/db');
const B = require('../../backend/src/services/backup');
const { HttpError } = require('../../backend/src/utils/misc');
const { errorBody } = require('../../backend/src/utils/errors');
const { parseInvoicePages } = require('../../backend/src/services/pdfParser');
const { createMissing } = require('../../backend/src/services/autoCreate');
const { settings } = require('../../backend/src/services/billing');
const { pageTextFromItems } = require('../../backend/src/services/pdfExtract');

const license = require('../../backend/src/services/license');
const pre = [require('../../backend/src/routes/license'), require('../../backend/src/routes/companies'), require('../../backend/src/routes/backup'),
  require('../../backend/src/routes/sync'), require('../../backend/src/routes/update')];
const post = ['items', 'parties', 'salesmen', 'invoices', 'purchases', 'debitNotes', 'import', 'reports']
  .map((n) => ({ items: require('../../backend/src/routes/items'), parties: require('../../backend/src/routes/parties'),
    salesmen: require('../../backend/src/routes/salesmen'), invoices: require('../../backend/src/routes/invoices'),
    purchases: require('../../backend/src/routes/purchases'), debitNotes: require('../../backend/src/routes/debitNotes'),
    import: require('../../backend/src/routes/import'), reports: require('../../backend/src/routes/reports') })[n]);

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

/** One request → { status, body } or { status, file, b64, type } for a file (Excel) or { status, html }. */
function request(step) {
  return new Promise((resolve) => {
    const method = (step.method || 'GET').toUpperCase();
    const segs = (step.path || '/').split('?')[0].split('/').filter(Boolean);
    const query = {};
    for (const [k, v] of Object.entries(step.query || {})) if (v !== null && v !== undefined) query[k] = String(v);
    const headers = { 'x-company-id': step.company !== undefined && step.company !== null ? String(step.company) : undefined };
    const req = { params: {}, query, body: step.body || {}, get: (h) => headers[h.toLowerCase()] };
    let status = 200, sent = false, kind = 'json'; const hdr = {};
    const done = (r) => { if (!sent) { sent = true; globalThis.__bbStore = undefined; resolve(r); } };
    const res = {
      status(c) { status = c; return res; },
      json(v) { done({ status, body: JSON.parse(JSON.stringify(errorBody(status, v === undefined ? null : v))) }); return res; },
      type(t) { kind = t; return res; },
      set(h) { Object.assign(hdr, h || {}); return res; },
      send(v) {
        if (typeof v === 'string' && kind === 'html') return done({ status, html: v }), res;
        const bytes = v instanceof Uint8Array ? Buffer.from(v) : Buffer.from(String(v));
        done({ status, file: (/filename="([^"]+)"/.exec(hdr['Content-Disposition'] || '') || [])[1], type: hdr['Content-Type'] || '', b64: bytes.toString('base64') });
        return res;
      },
    };
    const onError = (err) => {   // backend/src/server.js error handler
      if (err && (String(err.code || '').startsWith('SQLITE_CONSTRAINT') || (err.code === 'ERR_SQLITE_ERROR' && (Number(err.errcode) & 255) === 19))) {
        const msg = /UNIQUE/.test(err.message) ? 'That value already exists (for example a duplicate batch number).' : 'Invalid reference or missing value.';
        return res.status(409).json({ error: msg });
      }
      const st = err.status || 500;
      if (st === 500) console.error(err && err.stack || err);
      res.status(st).json({ error: st === 500 ? 'Server error' : err.message, code: err.code, detail: st === 500 ? String((err && err.message) || err) : undefined });   // the reason, so "Server error" can be traced
    };
    const run = (m) => { req.params = m.params; try { m.rt.hs[m.rt.hs.length - 1](req, res, (e) => (e ? onError(e) : res.status(404).json({ error: 'Not found' }))); } catch (e) { onError(e); } };
    try {
      if (!license.allows(method, '/' + segs.join('/'))) return onError(license.blocked());
      for (const r of pre) { const m = match(r, method, segs); if (m) return run(m); }
      const id = Number(req.get('x-company-id')) || db.firstCompanyId();
      const d = db.openCompany(id);
      if (!d) return res.status(404).json({ error: 'Company not found' });
      globalThis.__bbStore = d;            // the company of this request, until its reply (see shims/async_hooks.js)
      db.withCompany(id, () => {
        for (const r of post) { const m = match(r, method, segs); if (m) return run(m); }
        res.status(404).json({ error: 'Not found' });
      });
    } catch (e) { onError(e); }
  });
}

/** Every table of every company (the parity test compares these with the Mac's). */
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

/** Test steps beyond plain requests, as in ios/tests/parity/run-node.js. */
async function special(st) {
  if (st.op === 'dump') return { dump: dump() };
  if (st.op === 'parse') { const c = st.ctx || {}; return { parse: parseInvoicePages(st.pages || [], c) }; }
  if (st.op === 'autocreate') {
    const id = st.company || db.firstCompanyId();
    globalThis.__bbStore = db.openCompany(id);
    try {
      const r = await db.withCompany(id, async () => {
        const co = settings();
        const parsed = parseInvoicePages(st.pages, { items: db.prepare('SELECT id,name,hsn,gst_rate FROM items WHERE active=1').all(),
          parties: db.prepare("SELECT id,name,gstin FROM parties WHERE active=1 AND type='SUPPLIER'").all(), companyGstin: co.company_gstin, companyName: co.company_name });
        return createMissing(parsed, { online: false });
      });
      return { parse: JSON.parse(JSON.stringify(r)) };
    } finally { globalThis.__bbStore = undefined; }
  }
  if (st.op === 'pagetext') return { text: st.pages.map(pageTextFromItems) };
  if (st.op === 'backup') { const r = B.backupNow({ reason: st.reason || 'manual' }); return { folder: r.folder, files: r.files }; }
  if (st.op === 'tick') { const r = B.tick(); return { ok: true, folder: r ? r.folder : null }; }
  return null;
}

let queue = Promise.resolve();
const BillBox = {
  /** For the app: runs one request (in order) and hands the reply to AndroidHost.reply(id, json). */
  handle(id, json) {
    queue = queue.then(async () => {
      let out;
      try {
        const st = JSON.parse(json);
        out = (st.op ? await special(st) : null) || await request(st);
      } catch (e) {
        out = { status: 500, body: errorBody(500, { error: 'Server error', detail: String(e && e.message || e) }) };
      }
      globalThis.AndroidHost.reply(id, JSON.stringify(out));
    });
  },
  /** For tests in Node: the same, returning the reply. */
  async call(st) { return (st.op ? await special(st) : null) || request(st); },
  version: '15.0',
};
globalThis.BillBox = BillBox;
if (globalThis.AndroidHost && globalThis.AndroidHost.ready) globalThis.AndroidHost.ready();
