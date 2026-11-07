/**
 * Multi-company database layer.
 *   data/registry.db        -> list of companies + app-level settings (backup config, last company)
 *   data/<company>.db       -> one complete SQLite database per company (fully isolated books)
 *
 * Every existing module still does `const db = require('../db')`. That `db` is a thin proxy that forwards
 * to the database of the company selected for the current request (AsyncLocalStorage), so no query code
 * had to change. The Flutter app sends the company id in the X-Company-Id header.
 */
const Database = require('./sqlite');
const { AsyncLocalStorage } = require('node:async_hooks');
const path = require('path');
const fs = require('fs');
const { applySchema } = require('./schema');

const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(dataDir, { recursive: true });

const registry = new Database(path.join(dataDir, 'registry.db'));
registry.pragma('journal_mode = WAL');
registry.exec(`
CREATE TABLE IF NOT EXISTS companies (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, file TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1, created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT);
`);
// v9: each financial year of a company can be its own set of books (Marg style): fy = "2026-27", or null for books
// that hold every year (all books made before v9)
if (!registry.prepare('PRAGMA table_info(companies)').all().some((c) => c.name === 'fy')) registry.exec('ALTER TABLE companies ADD COLUMN fy TEXT');

const als = new AsyncLocalStorage();
// live sync (services/sync.js) tracks the changes of synced companies; it loads once this module is complete
let syncReady = false;
function syncAttach(id, d) {
  if (!syncReady) return;
  try {
    const S = require('./services/sync');
    if (typeof S.attach === 'function') S.attach(id, d); // (still loading when it was required first: it attaches the open books itself)
  } catch (e) { console.error('sync attach:', e && e.message); }
}
const open = new Map(); // company id -> raw database handle

function companyRow(id) {
  return registry.prepare('SELECT * FROM companies WHERE id=? AND active=1').get(id);
}

/** Pieces-per-box is read from names like "(1X144)"; units are always PCS (boxes are shown from pieces-per-box). */
function tidyItems(d) {
  const { packFromName } = require('./services/pdfParser');
  const up = d.prepare('UPDATE items SET pcs_per_box=? WHERE id=?');
  for (const it of d.prepare('SELECT id,name,pcs_per_box FROM items').all()) {
    const pk = packFromName(it.name);
    if (pk && it.pcs_per_box !== pk) up.run(pk, it.id);
  }
  d.exec("UPDATE items SET unit='PCS' WHERE unit IS NOT 'PCS'");
}

/**
 * Books that came from Marg before numbering followed it: once, the next bill of every series carries on from the last
 * one (A000423 after Marg's A000422) instead of starting INV/26-27/00001 (utils/misc.js followLast).
 */
function followMargOnce(d, file) {
  // remembered per company file in the registry (the books themselves stay as they were)
  const mark = `num_follow_checked:${file}`;
  try {
    if (registry.prepare('SELECT 1 AS x FROM app_settings WHERE key=?').get(mark)) return;
    const marg = d.prepare("SELECT 1 AS x FROM batches WHERE batch_no='MARG' LIMIT 1").get() || d.prepare("SELECT 1 AS x FROM purchases WHERE source='MARG' LIMIT 1").get();
    if (marg) als.run(d, () => require('./utils/misc').followLast());
    registry.prepare("INSERT INTO app_settings(key,value) VALUES(?,'1') ON CONFLICT(key) DO NOTHING").run(mark);
  } catch (e) { console.error('numbering:', e && e.message); }
}

function openCompany(id) {
  if (open.has(id)) return open.get(id);
  const row = companyRow(id);
  if (!row) return null;
  const d = new Database(path.join(dataDir, row.file));
  applySchema(d); // also upgrades older databases in place
  tidyItems(d);
  followMargOnce(d, row.file);
  open.set(id, d);
  syncAttach(id, d);
  return d;
}

/** Closes a company's open handle so its file can be replaced (restore). It reopens on the next request. */
function closeCompany(id) {
  const d = open.get(id);
  if (d) { try { d.close(); } catch { /* already closed */ } open.delete(id); }
}

function firstCompanyId() {
  const r = registry.prepare('SELECT id FROM companies WHERE active=1 ORDER BY id LIMIT 1').get();
  return r ? r.id : null;
}

function createCompany({ name, fy = null, ...settings }) {
  let file = `company_${Date.now()}.db`;
  for (let n = 2; fs.existsSync(path.join(dataDir, file)); n++) file = `company_${Date.now()}_${n}.db`;
  const id = Number(registry.prepare('INSERT INTO companies(name,file,fy) VALUES(?,?,?)').run(name, file, fy).lastInsertRowid);
  const d = new Database(path.join(dataDir, file));
  applySchema(d, { company_name: name, ...(fy ? { books_fy: fy } : {}), ...settings });
  open.set(id, d);
  return id;
}

function withCompany(id, fn) {
  const d = openCompany(id);
  if (!d) throw new Error(`Company ${id} not found`);
  return als.run(d, fn);
}

// First start: adopt a pre-v2 single database as company #1, or create an empty company.
if (!firstCompanyId()) {
  const legacy = path.join(dataDir, 'distributor.db');
  if (fs.existsSync(legacy)) {
    const id = Number(registry.prepare('INSERT INTO companies(name,file) VALUES(?,?)').run('My Company', 'distributor.db').lastInsertRowid);
    const d = openCompany(id);
    const nm = d.prepare("SELECT value FROM settings WHERE key='company_name'").get();
    if (nm && nm.value) registry.prepare('UPDATE companies SET name=? WHERE id=?').run(nm.value, id);
  } else {
    createCompany({ name: 'My Company' });
  }
}

const current = () => {
  const d = als.getStore();
  if (!d) throw new Error('No company selected for this request');
  return d;
};

const db = {
  prepare: (s) => current().prepare(s),
  exec: (s) => current().exec(s),
  pragma: (s) => current().pragma(s),
  transaction: (fn) => (...a) => current().transaction(fn)(...a),
  // multi-company helpers
  registry, dataDir, openHandles: () => [...open], openCompany, closeCompany, createCompany, withCompany, firstCompanyId, companyRow,
  middleware(req, res, next) {
    const id = Number(req.get('x-company-id')) || firstCompanyId();
    const d = openCompany(id);
    if (!d) return res.status(404).json({ error: 'Company not found' });
    als.run(d, next);
  },
};

module.exports = db;
syncReady = true;
for (const [id, d] of open) syncAttach(id, d);
