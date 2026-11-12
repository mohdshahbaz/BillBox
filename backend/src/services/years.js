const db = require('../db');
const { r2 } = require('../utils/gst');
const { HttpError } = require('../utils/misc');
const { fyRange } = require('../utils/fy');

/**
 * Financial years as separate books (Marg style). A company's year books share its name; each has its own file and
 * registry row with fy = "2026-27".
 *   carry: true  -> "Start the next year": settings and every master (categories, salesmen, routes, parties, items, schemes)
 *                   are copied, each party's balance before the year's first day becomes its opening balance, and the stock
 *                   on hand (every batch with pieces) becomes the opening stock.
 *   carry: false -> "Add an earlier (or any) year": empty books with the company's settings, e.g. for that year's Marg data.
 */
const reg = db.registry;
const norm = (n) => String(n || '').trim().replace(/\s+/g, ' ').toLowerCase();
const MASTERS = ['categories', 'salesmen', 'routes', 'parties', 'party_routes', 'items', 'schemes'];

/** Rows of `table` from one raw database into another, same ids, columns matched by name. */
function copyRows(src, dst, table, where = '') {
  const have = new Set(dst.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name));
  const cols = src.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name).filter((c) => have.has(c));
  const ins = dst.prepare(`INSERT INTO ${table}(${cols.join(',')}) VALUES(${cols.map(() => '?').join(',')})`);
  let n = 0;
  for (const r of src.prepare(`SELECT ${cols.join(',')} FROM ${table} ${where} ORDER BY id`).all()) { ins.run(...cols.map((c) => r[c])); n++; }
  return n;
}

function addYear(id, b = {}) {
  const src = db.companyRow(id);
  if (!src) throw new HttpError(404, 'Company not found');
  if (!b.fy) throw new HttpError(400, 'Choose the financial year');
  const fy = fyRange(b.fy);
  const siblings = reg.prepare('SELECT * FROM companies WHERE active=1').all().filter((c) => norm(c.name) === norm(src.name));
  if (siblings.some((c) => c.fy === fy.label)) throw new HttpError(409, `${src.name} already has books for ${fy.label}.`, 'YEAR_EXISTS');
  const carry = !(b.carry === false || b.carry === 0);
  const raw = db.openCompany(src.id);
  const settings = {};
  for (const r of raw.prepare('SELECT key,value FROM settings').all()) if (r.key !== 'company_name' && r.key !== 'books_fy') settings[r.key] = r.value;
  const newId = db.createCompany({ name: src.name, fy: fy.label, ...settings });
  const dst = db.openCompany(newId);
  const carried = { masters: 0, opening_balances: 0, stock_batches: 0 };
  if (carry) {
    dst.transaction(() => {
      for (const t of MASTERS) carried.masters += copyRows(raw, dst, t);
      carried.stock_batches = copyRows(raw, dst, 'batches', 'WHERE qty <> 0');
      const lg = dst.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,'OPENING','OPENING',?,?,?)");
      const from = src.fy || 'the earlier books';
      for (const p of raw.prepare('SELECT party_id, SUM(debit)-SUM(credit) b FROM ledger WHERE date < ? GROUP BY party_id ORDER BY party_id').all(fy.from)) {
        const bal = r2(p.b);
        if (Math.abs(bal) < 0.005) continue;
        lg.run(p.party_id, fy.from, bal > 0 ? bal : 0, bal < 0 ? -bal : 0, `Opening balance (carried from ${from})`);
        carried.opening_balances++;
      }
    })();
  }
  return { id: newId, name: src.name, fy: fy.label, carried: carry ? carried : null };
}

/** A company's renamed: every year's books keep the same name. */
function renameAll(oldName, newName) {
  for (const c of reg.prepare('SELECT * FROM companies').all().filter((x) => norm(x.name) === norm(oldName))) {
    reg.prepare('UPDATE companies SET name=? WHERE id=?').run(newName, c.id);
    const d = db.openCompany(c.id);
    if (d) d.prepare("INSERT INTO settings(key,value) VALUES('company_name',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(newName);
  }
}

module.exports = { addYear, renameAll };
