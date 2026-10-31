/**
 * Local-disk backups. For each company it writes a consistent copy of the SQLite file with VACUUM INTO
 * (safe while the app is running), verifies the copy with PRAGMA integrity_check, records a SHA-256 in a manifest,
 * and prunes old backup folders. Folder layout:
 *   <backup_dir>/FMCG_Backup_YYYYMMDD_HHMMSS/<Company>_<id>.db, registry.db, manifest.json
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const Database = require('../sqlite');
const db = require('../db');
const { HttpError } = require('../utils/misc');

const reg = db.registry;
const PREFIX = 'FMCG_Backup_';
const FOLDER_RE = /^FMCG_Backup_\d{8}_\d{6}(_\d+)?$/;

const getSetting = (k, d) => { const r = reg.prepare('SELECT value FROM app_settings WHERE key=?').get(k); return r ? r.value : d; };
const setSetting = (k, v) => reg.prepare('INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run(k, String(v));

function config() {
  return {
    dir: getSetting('backup_dir', path.join(os.homedir(), 'DistributorProBackups')),
    enabled: getSetting('backup_enabled', '0') === '1',
    time: getSetting('backup_time', '21:00'),
    on_exit: getSetting('backup_on_exit', '0') === '1',
    last_run: getSetting('backup_last_run', ''),
    last_status: getSetting('backup_last_status', ''),
  };
}

function saveConfig(b) {
  if (b.dir !== undefined) {
    if (!path.isAbsolute(b.dir)) throw new HttpError(400, 'Enter the full path of the backup folder, e.g. /Volumes/MyDrive/Backups');
    setSetting('backup_dir', b.dir);
  }
  if (b.enabled !== undefined) setSetting('backup_enabled', b.enabled ? '1' : '0');
  if (b.on_exit !== undefined) setSetting('backup_on_exit', b.on_exit ? '1' : '0');
  if (b.time !== undefined) {
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(b.time)) throw new HttpError(400, 'Time must be HH:MM (24 hour)');
    setSetting('backup_time', b.time);
  }
  return config();
}

const stamp = (d = new Date()) => {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
};
const slug = (s) => String(s).replace(/[^A-Za-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40) || 'Company';
const sqlPath = (p) => p.replace(/'/g, "''");

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function copyAndVerify(rawDb, dest) {
  rawDb.exec(`VACUUM INTO '${sqlPath(dest)}'`);
  const chk = new Database(dest, { readonly: true });
  try {
    const r = chk.prepare('PRAGMA integrity_check').get();
    const v = Object.values(r)[0];
    if (v !== 'ok') throw new HttpError(500, `Backup verification failed for ${path.basename(dest)}: ${v}`);
  } finally { chk.close(); }
  return { file: path.basename(dest), bytes: fs.statSync(dest).size, sha256: sha256(dest) };
}

function backupNow({ reason = 'manual' } = {}) {
  const { dir } = config();
  try {
    fs.mkdirSync(dir, { recursive: true });
    const probe = path.join(dir, `.write-test-${process.pid}`);
    fs.writeFileSync(probe, 'ok'); fs.rmSync(probe);
  } catch (e) {
    const msg = `Cannot write to "${dir}". Is the drive connected and the folder writable?`;
    setSetting('backup_last_status', `FAILED ${new Date().toISOString()}: ${msg}`);
    throw new HttpError(500, msg);
  }
  let folder = path.join(dir, PREFIX + stamp());
  for (let n = 2; fs.existsSync(folder); n++) folder = path.join(dir, `${PREFIX}${stamp()}_${n}`);  // two backups in the same second
  fs.mkdirSync(folder);
  try {
    const files = [];
    const companies = reg.prepare('SELECT * FROM companies WHERE active=1 ORDER BY id').all();
    for (const c of companies) {
      const raw = db.openCompany(c.id);
      files.push({ company_id: c.id, company: c.name, ...(c.fy ? { fy: c.fy } : {}), ...copyAndVerify(raw, path.join(folder, `${slug(c.name)}${c.fy ? '_' + c.fy : ''}_${c.id}.db`)) });
    }
    files.push({ company: '(company list)', ...copyAndVerify(reg, path.join(folder, 'registry.db')) });
    fs.writeFileSync(path.join(folder, 'manifest.json'), JSON.stringify({ created: new Date().toISOString(), reason, files }, null, 2));
    setSetting('backup_last_run', new Date().toISOString());
    setSetting('backup_last_status', `OK ${path.basename(folder)}`);
    return { folder, files };
  } catch (e) {
    fs.rmSync(folder, { recursive: true, force: true }); // never leave a half-written backup looking valid
    setSetting('backup_last_status', `FAILED ${new Date().toISOString()}: ${e.message}`);
    throw e;
  }
}

/** Removes one backup folder, only when the user asks. */
function deleteBackup(name) {
  const { dir } = config();
  const n = path.basename(String(name || ''));
  if (!FOLDER_RE.test(n)) throw new HttpError(400, 'That is not a backup folder made by BillBox.');
  const f = path.join(dir, n);
  if (!fs.existsSync(f)) throw new HttpError(404, 'That backup is already gone.');
  fs.rmSync(f, { recursive: true, force: true });
  return { deleted: n };
}

// Backups are never deleted automatically: every one is kept until you remove its folder yourself.

function listBackups() {
  const { dir } = config();
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => FOLDER_RE.test(f)).sort().reverse().map((f) => {
    let files = 0, bytes = 0, created = null, companies = [];
    try {
      const m = JSON.parse(fs.readFileSync(path.join(dir, f, 'manifest.json'), 'utf8'));
      files = m.files.length; bytes = m.files.reduce((a, x) => a + x.bytes, 0); created = m.created; companies = m.files.filter((x) => x.company_id).map((x) => x.company);
    } catch { /* incomplete folder: shown with zero files */ }
    return { name: f, files, bytes, created, companies };
  });
}

/** Called every minute: runs the daily backup once the configured time has passed and today's has not run yet. */
function tick(now = new Date()) {
  const c = config();
  if (!c.enabled) return null;
  const hhmm = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  const today = now.toLocaleDateString('en-CA');
  const lastDay = c.last_run ? new Date(c.last_run).toLocaleDateString('en-CA') : '';
  if (hhmm >= c.time && lastDay !== today) {
    try {
      const r = backupNow({ reason: 'scheduled' });
      require('./drive').afterBackup(r.folder); // to Google Drive too, when connected (in the background)
      return r;
    } catch (e) { console.error('Scheduled backup failed:', e.message); }
  }
  return null;
}

function startScheduler() {
  const t = setInterval(() => tick(), 60 * 1000);
  t.unref();
  setTimeout(() => tick(), 5000).unref(); // catch up a missed backup shortly after launch
}

/**
 * Restore. Two forms:
 *   folder  - a backup folder made by this app (FMCG_Backup_...): every company in it is restored, companies missing
 *             from this installation are re-created.
 *   file    - a single company .db file: restored into company_id.
 * Every file is integrity-checked first. A safety backup of the current data is taken before anything is replaced,
 * so a wrong restore can itself be undone.
 */
function checkFile(file) {
  let chk;
  try {
    chk = new Database(file, { readonly: true });
    const v = Object.values(chk.prepare('PRAGMA integrity_check').get())[0];
    if (v !== 'ok') throw new HttpError(400, `${path.basename(file)} is damaged (${v}). Nothing was restored.`);
    if (!chk.prepare("SELECT 1 FROM sqlite_master WHERE name='invoices'").get()) throw new HttpError(400, `${path.basename(file)} is not a BillBox company file.`);
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError(400, `${path.basename(file)} cannot be opened as a database. Nothing was restored.`);
  } finally { if (chk) chk.close(); }
}

function swapIn(src, row) {
  const dest = path.join(db.dataDir, row.file);
  db.closeCompany(row.id);
  const tmp = dest + '.restoring';
  fs.copyFileSync(src, tmp);
  for (const ext of ['-wal', '-shm']) fs.rmSync(dest + ext, { force: true });
  fs.renameSync(tmp, dest);
}

const norm = (n) => String(n || '').trim().replace(/\s+/g, ' ').toLowerCase();

/** The company a backup file belongs to is found by NAME, never by number, so a restore cannot overwrite a different company. */
function rowForCompany(name, { create = true, fy = null } = {}) {
  const wanted = norm(name);
  // a company's year books share its name: the year tells them apart (null = books for every year)
  const hit = reg.prepare('SELECT * FROM companies').all().find((c) => norm(c.name) === wanted && (c.fy || null) === (fy || null));
  if (hit) {
    if (!hit.active) reg.prepare('UPDATE companies SET active=1 WHERE id=?').run(hit.id);
    return hit;
  }
  if (!create) return null;
  const id = db.createCompany({ name: String(name || 'Restored company').trim(), fy: fy || null });
  return reg.prepare('SELECT * FROM companies WHERE id=?').get(id);
}

function companyNameInFile(file) {
  return companyInFile(file).name;
}

/** { name, fy } as the file itself records them (fy only for one year's books). */
function companyInFile(file) {
  let d;
  try {
    d = new Database(file, { readonly: true });
    const r = d.prepare("SELECT value FROM settings WHERE key='company_name'").get();
    const y = d.prepare("SELECT value FROM settings WHERE key='books_fy'").get();
    return { name: r && r.value ? String(r.value) : null, fy: y && y.value ? String(y.value) : null };
  } catch { return { name: null, fy: null }; } finally { if (d) d.close(); }
}

/**
 * MERGE: adds what the backup has and these books do not, and changes nothing that already exists.
 * Records are matched by their natural keys (party / item / salesman / route / category by name, bills and vouchers by number,
 * batches by item + batch number), so numbers in the two sets of books never get mixed up.
 * A bill or voucher whose number exists here with different content is reported as a conflict and left alone.
 * Stock of items and batches that already exist here is not changed.
 */
function mergeInto(row, file) {
  const dst = db.openCompany(row.id);
  const src = new Database(file, { readonly: true });
  const stats = { added: {}, skipped: {}, conflicts: [] };
  const add = (k) => { stats.added[k] = (stats.added[k] || 0) + 1; };
  const skip = (k) => { stats.skipped[k] = (stats.skipped[k] || 0) + 1; };
  const all = (t) => { try { return src.prepare(`SELECT * FROM ${t}`).all(); } catch { return []; } };
  const cols = (t) => dst.prepare(`PRAGMA table_info(${t})`).all().map((c) => c.name).filter((c) => c !== 'id');
  const insert = (t, rec) => {
    const cs = cols(t).filter((c) => rec[c] !== undefined);
    const r = dst.prepare(`INSERT INTO ${t}(${cs.join(',')}) VALUES(${cs.map(() => '?').join(',')})`).run(...cs.map((c) => rec[c]));
    return Number(r.lastInsertRowid);
  };
  const key = (v) => norm(v);
  const idx = (t, f) => new Map(dst.prepare(`SELECT id,${f} v FROM ${t}`).all().map((r) => [key(r.v), r.id]));
  const byName = (table, mapOut) => {
    const have = idx(table, 'name');
    for (const r of all(table)) {
      let id = have.get(key(r.name));
      if (id) skip(table); else {
        id = insert(table, { ...r, ...(mapOut ? mapOut(r) : {}) });
        have.set(key(r.name), id); add(table);
      }
      maps[table].set(r.id, id);
    }
  };
  const maps = { categories: new Map(), salesmen: new Map(), routes: new Map(), parties: new Map(), items: new Map(), batches: new Map(), invoices: new Map(), purchases: new Map(), debit_notes: new Map() };
  const newParties = new Set();
  const m = (name, id) => (id == null ? null : (maps[name].get(id) ?? null));

  try {
    dst.transaction(() => {
      byName('categories');
      byName('salesmen');
      byName('routes', (r) => ({ salesman_id: m('salesmen', r.salesman_id) }));
      // parties: matched by name, a customer and a supplier with the same name are different parties
      const haveP = new Map(dst.prepare('SELECT id,name,type FROM parties').all().map((r) => [key(r.name) + '|' + (r.type === 'SUPPLIER' ? 'S' : 'C'), r.id]));
      for (const r of all('parties')) {
        const k = key(r.name) + '|' + (r.type === 'SUPPLIER' ? 'S' : 'C');
        let id = haveP.get(k);
        if (id) skip('parties'); else { id = insert('parties', { ...r, route_id: m('routes', r.route_id) }); haveP.set(k, id); newParties.add(id); add('parties'); }
        maps.parties.set(r.id, id);
      }
      const haveI = idx('items', 'name');
      for (const r of all('items')) {
        let id = haveI.get(key(r.name));
        if (id) skip('items'); else { id = insert('items', { ...r, category_id: m('categories', r.category_id) }); haveI.set(key(r.name), id); add('items'); }
        maps.items.set(r.id, id);
      }
      const haveB = new Map(dst.prepare('SELECT id,item_id,batch_no FROM batches').all().map((r) => [r.item_id + '|' + key(r.batch_no), r.id]));
      for (const r of all('batches')) {
        const itemId = m('items', r.item_id);
        if (!itemId) continue;
        const k = itemId + '|' + key(r.batch_no);
        let id = haveB.get(k);
        if (id) skip('batches'); else { id = insert('batches', { ...r, item_id: itemId }); haveB.set(k, id); add('batches'); }
        maps.batches.set(r.id, id);
      }
      const haveS = new Set(dst.prepare('SELECT item_id,type,buy_qty,free_qty,percent FROM schemes').all().map((r) => [r.item_id, r.type, r.buy_qty, r.free_qty, r.percent].join('|')));
      for (const r of all('schemes')) {
        const itemId = m('items', r.item_id);
        const k = [itemId, r.type, r.buy_qty, r.free_qty, r.percent].join('|');
        if (!itemId || haveS.has(k)) { skip('schemes'); continue; }
        insert('schemes', { ...r, item_id: itemId }); haveS.add(k); add('schemes');
      }

      // documents: by number
      const document = (table, noCol, lineTable, fk, convert, lineConvert, label) => {
        const have = new Map(dst.prepare(`SELECT id,${noCol} no,date,total FROM ${table}`).all().map((r) => [r.no, r]));
        const lines = all(lineTable);
        for (const r of all(table)) {
          const cur = have.get(r[noCol]);
          if (cur) {
            if (cur.date === r.date && Math.abs(cur.total - r.total) < 0.005) skip(table);
            else { stats.conflicts.push(`${label} ${r[noCol]} exists here with different details; left as it is`); skip(table); }
            maps[table].set(r.id, cur.id);
            continue;
          }
          const id = insert(table, convert(r));
          maps[table].set(r.id, id); add(table);
          for (const l of lines.filter((x) => x[fk] === r.id)) {
            const itemId = m('items', l.item_id);
            if (itemId) insert(lineTable, { ...l, [fk]: id, ...lineConvert(l, itemId) });
          }
        }
      };
      document('invoices', 'invoice_no', 'invoice_lines', 'invoice_id',
        (r) => ({ ...r, party_id: m('parties', r.party_id), salesman_id: m('salesmen', r.salesman_id) }),
        (l, itemId) => ({ item_id: itemId, batch_id: m('batches', l.batch_id) }), 'Bill');
      document('purchases', 'purchase_no', 'purchase_lines', 'purchase_id',
        (r) => ({ ...r, party_id: m('parties', r.party_id) }),
        (l, itemId) => ({ item_id: itemId, batch_id: m('batches', l.batch_id) }), 'Purchase');
      // debit notes: by number, with their lines and the batches the pieces left (stock of existing batches is not changed)
      {
        const have = new Map(dst.prepare('SELECT id,note_no no,date,total FROM debit_notes').all().map((r) => [r.no, r]));
        const lines = all('debit_note_lines'), stock = all('debit_note_stock');
        for (const r of all('debit_notes')) {
          const cur = have.get(r.note_no);
          if (cur) {
            if (cur.date === r.date && Math.abs(cur.total - r.total) < 0.005) skip('debit_notes');
            else { stats.conflicts.push(`Debit note ${r.note_no} exists here with different details; left as it is`); skip('debit_notes'); }
            maps.debit_notes.set(r.id, cur.id);
            continue;
          }
          const pid = m('parties', r.party_id);
          if (!pid) continue;
          const id = insert('debit_notes', { ...r, party_id: pid, purchase_id: m('purchases', r.purchase_id) });
          maps.debit_notes.set(r.id, id); add('debit_notes');
          for (const l of lines.filter((x) => x.note_id === r.id)) {
            const itemId = m('items', l.item_id);
            if (!itemId) continue;
            const lid = insert('debit_note_lines', { ...l, note_id: id, item_id: itemId, batch_id: m('batches', l.batch_id) });
            for (const st of stock.filter((x) => x.line_id === l.id)) {
              const b = m('batches', st.batch_id);
              if (b) insert('debit_note_stock', { ...st, line_id: lid, batch_id: b });
            }
          }
        }
      }
      // a bill line must have a batch; drop any invoice line that lost it (it cannot happen with this app's own backups)
      dst.exec('DELETE FROM invoice_lines WHERE batch_id IS NULL');

      const voucher = (table, noCol, extra) => {
        const have = new Set(dst.prepare(`SELECT ${noCol} no FROM ${table}`).all().map((r) => r.no));
        for (const r of all(table)) {
          if (have.has(r[noCol])) { skip(table); continue; }
          const pid = m('parties', r.party_id);
          if (!pid) continue;
          insert(table, { ...r, party_id: pid, salesman_id: m('salesmen', r.salesman_id), ...extra(r) });
          have.add(r[noCol]); add(table);
        }
      };
      voucher('receipts', 'receipt_no', (r) => ({ invoice_id: m('invoices', r.invoice_id) }));
      voucher('payments', 'voucher_no', (r) => ({ purchase_id: m('purchases', r.purchase_id) }));

      // ledger: new parties bring their whole ledger (with opening balance); existing parties only get lines they do not have yet
      const haveL = new Set(dst.prepare('SELECT party_id,type,IFNULL(ref_no,\'\') r,date,debit,credit FROM ledger').all().map((r) => [r.party_id, r.type, r.r, r.date, r.debit, r.credit].join('|')));
      for (const r of all('ledger')) {
        const pid = m('parties', r.party_id);
        if (!pid) continue;
        const k = [pid, r.type, r.ref_no || '', r.date, r.debit, r.credit].join('|');
        if (haveL.has(k) || (!newParties.has(pid) && r.type === 'OPENING')) continue;
        insert('ledger', { ...r, party_id: pid }); haveL.add(k); add('ledger');
      }
      // numbering never goes backwards
      for (const c of all('counters')) {
        dst.prepare('INSERT INTO counters(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=MAX(value,excluded.value)').run(c.key, c.value);
      }
    })();
  } finally { src.close(); }
  return stats;
}

function restore({ name, folder, file, company_id, mode } = {}) {
  const merge = mode === 'merge';
  const merged = [];
  const { dir } = config();
  let restored = [];
  if (file) {
    if (!path.isAbsolute(file) || !fs.existsSync(file) || !fs.statSync(file).isFile()) throw new HttpError(400, 'Choose a company backup file (.db).');
    checkFile(file);
    // the file knows which company it belongs to; only if it does not is the chosen company used
    const inFile = companyInFile(file);
    const own = inFile.name;
    const row = own ? rowForCompany(own, { create: false, fy: inFile.fy }) || null : null;
    const target = row || reg.prepare('SELECT * FROM companies WHERE id=?').get(Number(company_id) || db.firstCompanyId());
    if (!target) throw new HttpError(404, 'Company not found');
    backupNow({ reason: 'before-restore' });
    if (merge) merged.push({ company: target.name, ...mergeInto(target, file) }); else swapIn(file, target);
    restored.push(target.name);
  } else {
    const f = folder || (name && path.join(dir, path.basename(name)));
    if (!f || !path.isAbsolute(f) || !fs.existsSync(f) || !fs.statSync(f).isDirectory()) throw new HttpError(400, 'Choose a backup folder (one that contains manifest.json).');
    let manifest;
    try { manifest = JSON.parse(fs.readFileSync(path.join(f, 'manifest.json'), 'utf8')); }
    catch { throw new HttpError(400, 'That folder has no readable manifest.json, so it is not a BillBox backup.'); }
    const items = manifest.files.filter((x) => x.company_id);
    if (!items.length) throw new HttpError(400, 'That backup contains no company data.');
    for (const x of items) {
      const p = path.join(f, x.file);
      if (!fs.existsSync(p)) throw new HttpError(400, `${x.file} is missing from the backup folder. Nothing was restored.`);
      if (x.sha256 && sha256(p) !== x.sha256) throw new HttpError(400, `${x.file} does not match its checksum (it was changed or damaged). Nothing was restored.`);
      checkFile(p);
    }
    // companies that exist in the backup but not here are re-created from the backup's own company list
    let bReg = null;
    const regFile = path.join(f, 'registry.db');
    if (fs.existsSync(regFile)) bReg = new Database(regFile, { readonly: true });
    try {
      backupNow({ reason: 'before-restore' });
      for (const x of items) {
        const row = rowForCompany(x.company || (bReg && (bReg.prepare('SELECT name FROM companies WHERE id=?').get(x.company_id) || {}).name),
          { fy: x.fy || companyInFile(path.join(f, x.file)).fy });
        if (merge) merged.push({ company: row.name, ...mergeInto(row, path.join(f, x.file)) }); else swapIn(path.join(f, x.file), row);
        restored.push(row.name);
      }
    } finally { if (bReg) bReg.close(); }
  }
  for (const id of reg.prepare('SELECT id FROM companies').all().map((r) => r.id)) db.openCompany(id);  // reopen + apply schema upgrades
  return { restored, mode: merge ? 'merge' : 'replace', merged };
}

module.exports = { deleteBackup, restore, config, saveConfig, backupNow, listBackups, tick, startScheduler };
