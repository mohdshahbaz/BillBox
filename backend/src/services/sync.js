/**
 * Live sync between devices through Firebase Realtime Database (REST, no SDK): a change made on one device shows on the
 * others within a few seconds. Each device keeps its own SQLite books (works offline) and swaps changes:
 *
 *   users/<uid>/devices/<pushId>           one entry per device install; its place in the list is the device's slot
 *   users/<uid>/books/<key>/info           { name, fy } of a synced company
 *   users/<uid>/books/<key>/log/<pushId>   { s: slot, c: [{ t: table, k: key, r: row, z: "null,columns", q: stock delta }] }
 *
 * - Ids: with sync on, every row this device adds takes an id from its own range (sqlite.js idBase = slot × 10 000 000),
 *   so devices never pick the same id.
 * - Changes: SQLite triggers note every insert, update and delete in sync_out; a sync step sends the rows as they are now
 *   and reads the other devices' entries (the apps call GET /sync/tick every few seconds).
 * - Stock: a batch's quantity travels as the change (sold 5 → −5), so two devices selling the same batch both count.
 *   Counters (bill numbers) keep the higher value. Everything else: the newest change wins.
 * - Sign-in: Firebase e-mail and password (Identity Toolkit REST); the refresh token stays in registry app_settings.
 */
const db = require('../db');
const { HttpError, nextNo } = require('../utils/misc');

const CONFIG = {
  apiKey: process.env.BILLBOX_FIREBASE_KEY || 'AIzaSyC0bS-ytJeaXl6PbE0cxzTa6FoOC2wTYo0',
  databaseURL: (process.env.BILLBOX_FIREBASE_DB || 'https://billbox-fd2c0-default-rtdb.asia-southeast1.firebasedatabase.app').replace(/\/$/, ''),
  authURL: process.env.BILLBOX_FIREBASE_AUTH || 'https://identitytoolkit.googleapis.com/v1',
  tokenURL: process.env.BILLBOX_FIREBASE_TOKEN || 'https://securetoken.googleapis.com/v1/token',
};
const RANGE = 10000000;
const MAX_SLOT = 210;
const LOCAL = new Set(['sync_out', 'sync_state', 'sync_seen', 'sync_alias']);
const CHUNK = 400; // changes per log entry

// ---------- small helpers ----------
const reg = db.registry;
const getApp = (k) => { const r = reg.prepare('SELECT value FROM app_settings WHERE key=?').get(k); return r ? r.value : null; };
const setApp = (k, v) => {
  if (v === null || v === undefined) reg.prepare('DELETE FROM app_settings WHERE key=?').run(k);
  else reg.prepare('INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run(k, String(v));
};
const map = () => { try { return JSON.parse(getApp('sync_map') || '{}'); } catch { return {}; } };
const setMap = (m) => setApp('sync_map', JSON.stringify(m));
const now = () => new Date().toISOString();
const randomKey = () => { const A = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'; let k = 'b'; for (let i = 0; i < 15; i++) k += A[Math.floor(Math.random() * A.length)]; return k; };
const state = { moved: {}, companies: 0, version: 0, lastSync: null, lastError: null, running: null, errors: 0, token: null, tokenExp: 0 };

const offline = () => new HttpError(503, 'No internet: BillBox could not reach the sync server. Your books are safe here and sync again when the internet is back.');
async function call(url, opts = {}) {
  let r;
  try { r = await fetch(url, { ...opts, timeoutMs: 8000 }); } catch (_) { throw offline(); }
  const text = await r.text();
  let j = null;
  try { j = text ? JSON.parse(text) : null; } catch { j = null; }
  return { status: r.status, j };
}

// ---------- sign-in ----------
const AUTH_ERR = {
  EMAIL_EXISTS: 'That e-mail already has a BillBox sync account: sign in instead.',
  EMAIL_NOT_FOUND: 'No sync account with that e-mail: create one first.',
  INVALID_PASSWORD: 'Wrong password.', INVALID_LOGIN_CREDENTIALS: 'Wrong e-mail or password.',
  INVALID_EMAIL: 'That e-mail address is not valid.', WEAK_PASSWORD: 'Choose a password of at least 6 characters.',
  OPERATION_NOT_ALLOWED: 'E-mail sign-in is off in Firebase: turn on Authentication › Sign-in method › Email/Password.',
  TOO_MANY_ATTEMPTS_TRY_LATER: 'Too many tries: wait a few minutes.',
  CONFIGURATION_NOT_FOUND: 'Firebase Authentication is not set up yet: open Authentication in the Firebase console and press Get started.',
};
function authError(j) {
  const m = String((j && j.error && j.error.message) || 'Sign-in failed');
  const code = m.split(' ')[0].split(':')[0];
  return new HttpError(400, AUTH_ERR[code] || m);
}

async function signIn({ email, password, create } = {}) {
  email = String(email || '').trim().toLowerCase();
  if (!email || !password) throw new HttpError(400, 'Enter the e-mail and password of your sync account.');
  const r = await call(`${CONFIG.authURL}/accounts:${create ? 'signUp' : 'signInWithPassword'}?key=${CONFIG.apiKey}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  if (r.status !== 200 || !r.j || !r.j.idToken) throw authError(r.j);
  if (getApp('sync_uid') && getApp('sync_uid') !== r.j.localId) { setApp('sync_slot', null); setMap({}); }
  setApp('sync_email', email); setApp('sync_uid', r.j.localId); setApp('sync_refresh', r.j.refreshToken);
  state.token = r.j.idToken; state.tokenExp = Date.now() + (Number(r.j.expiresIn || 3600) - 120) * 1000;
  await slot();
  return status();
}

function signOut() {
  for (const cid of Object.keys(map())) detach(Number(cid));
  for (const k of ['sync_email', 'sync_uid', 'sync_refresh', 'sync_slot', 'sync_map']) setApp(k, null);
  state.token = null; state.tokenExp = 0; state.lastError = null;
  return status();
}

async function token(force) {
  if (!force && state.token && Date.now() < state.tokenExp) return state.token;
  const rt = getApp('sync_refresh');
  if (!rt) throw new HttpError(401, 'Sign in to sync first (Settings › Sync).');
  const r = await call(`${CONFIG.tokenURL}?key=${CONFIG.apiKey}`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(rt)}`,
  });
  if (r.status !== 200 || !r.j || !r.j.id_token) {
    if (r.status === 400) { state.token = null; throw new HttpError(401, 'Your sync sign-in has expired: sign in again (Settings › Sync).'); }
    throw new HttpError(502, `The sync server answered ${r.status}.`);
  }
  if (r.j.refresh_token) setApp('sync_refresh', r.j.refresh_token);
  state.token = r.j.id_token; state.tokenExp = Date.now() + (Number(r.j.expires_in || 3600) - 120) * 1000;
  return state.token;
}

/** Realtime Database REST call under users/<uid>/. */
async function rtdb(method, rel, body, query = '') {
  const uid = getApp('sync_uid');
  if (!uid) throw new HttpError(401, 'Sign in to sync first (Settings › Sync).');
  for (let attempt = 0; attempt < 2; attempt++) {
    const t = await token(attempt > 0);
    const r = await call(`${CONFIG.databaseURL}/users/${uid}/${rel}.json?auth=${encodeURIComponent(t)}${query}`, {
      method, headers: { 'content-type': 'application/json' }, ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
    if (r.status === 401 && attempt === 0) continue;
    if (r.status === 401 || r.status === 403) throw new HttpError(403, 'The sync database refused BillBox: set its rules (Firebase › Realtime Database › Rules) as shown in Settings › Sync.');
    if (r.status === 404) throw new HttpError(502, 'The sync database was not found: create the Realtime Database in the Firebase console.');
    if (r.status >= 400) throw new HttpError(502, `The sync server answered ${r.status}${r.j && r.j.error ? ': ' + r.j.error : ''}.`);
    return r.j;
  }
  return null;
}

/** "darwin · Shop-Mac" (the platform, and the computer's name where there is one): tells this device's installs apart. */
function deviceName() {
  const p = String((typeof process !== 'undefined' && process.platform) || 'device');
  let h = '';
  try { const os = require('os'); h = typeof os.hostname === 'function' ? String(os.hostname() || '') : ''; } catch { h = ''; }
  return h ? `${p} · ${h}` : p;
}

/** This device's slot: its place among the account's devices (each install adds itself once). */
async function slot() {
  const have = Number(getApp('sync_slot') || 0);
  if (have) return have;
  let mine = getApp('sync_device');
  if (!mine) {
    const r = await rtdb('POST', 'devices', { at: { '.sv': 'timestamp' }, name: deviceName() });
    mine = r.name; setApp('sync_device', mine);
  }
  const all = Object.keys((await rtdb('GET', 'devices', undefined, '&shallow=true')) || {}).sort();
  const n = all.indexOf(mine) + 1;
  if (n <= 0) { setApp('sync_device', null); throw new HttpError(502, 'This device could not register for sync: try again.'); }
  if (n > MAX_SLOT) throw new HttpError(400, `This sync account already has ${MAX_SLOT} device installs: use a new sync account.`);
  setApp('sync_slot', n);
  return n;
}

// ---------- local tracking ----------
function tables(d) {
  const out = [];
  for (const { name } of d.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all()) {
    if (LOCAL.has(name) || /_new$|_old$/.test(name)) continue;
    const cols = d.prepare(`PRAGMA table_info(${name})`).all();
    const pk = cols.filter((c) => c.pk);
    if (pk.length !== 1) continue;
    // UNIQUE column sets (a category name, a batch number of an item) and the columns that point at other tables
    const uniq = d.prepare(`PRAGMA index_list(${name})`).all().filter((x) => x.unique && x.origin === 'u')
      .map((x) => d.prepare(`PRAGMA index_info(${x.name})`).all().map((c) => c.name));
    const fks = d.prepare(`PRAGMA foreign_key_list(${name})`).all().map((f) => ({ col: f.from, ref: f.table }));
    out.push({ name, pk: pk[0].name, intId: pk[0].name === 'id' && /INT/i.test(pk[0].type), cols: cols.map((c) => c.name), uniq, fks });
  }
  return out;
}

/** Called for every company opened (db.openCompany): turns tracking on for the synced ones. */
function attach(cid, d) {
  const key = map()[cid];
  const sl = Number(getApp('sync_slot') || 0);
  if (!key || !sl) { d.idBase = 0; return; }
  d.exec(`CREATE TABLE IF NOT EXISTS sync_out (seq INTEGER PRIMARY KEY, tbl TEXT NOT NULL, rid, op TEXT NOT NULL, dq REAL);
CREATE TABLE IF NOT EXISTS sync_state (k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS sync_seen (k TEXT PRIMARY KEY, at INTEGER);
CREATE TABLE IF NOT EXISTS sync_alias (tbl TEXT NOT NULL, from_id INTEGER NOT NULL, to_id INTEGER NOT NULL, PRIMARY KEY (tbl, from_id))`);
  const ts = tables(d);
  for (const { name } of d.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'bbsync_%'").all()) d.exec(`DROP TRIGGER IF EXISTS ${name}`);
  for (const t of ts) {
    const dq = t.name === 'batches' && t.cols.includes('qty') ? 'NEW.qty - OLD.qty' : 'NULL';
    d.exec(`CREATE TRIGGER bbsync_${t.name}_i AFTER INSERT ON ${t.name} BEGIN INSERT INTO sync_out(tbl,rid,op) VALUES('${t.name}', NEW.${t.pk}, 'i'); END`);
    d.exec(`CREATE TRIGGER bbsync_${t.name}_u AFTER UPDATE ON ${t.name} BEGIN INSERT INTO sync_out(tbl,rid,op,dq) VALUES('${t.name}', NEW.${t.pk}, 'u', ${dq}); `
      + `INSERT INTO sync_out(tbl,rid,op) SELECT '${t.name}', OLD.${t.pk}, 'd' WHERE OLD.${t.pk} IS NOT NEW.${t.pk}; END`);
    d.exec(`CREATE TRIGGER bbsync_${t.name}_d AFTER DELETE ON ${t.name} BEGIN INSERT INTO sync_out(tbl,rid,op) VALUES('${t.name}', OLD.${t.pk}, 'd'); END`);
  }
  d.idTables = new Set(ts.filter((t) => t.intId).map((t) => t.name));
  d.idNext = {};
  d.idBase = sl * RANGE;
}

function detach(cid) {
  const d = db.openCompany(cid);
  if (!d) return;
  for (const { name } of d.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'bbsync_%'").all()) d.exec(`DROP TRIGGER IF EXISTS ${name}`);
  d.exec('DROP TABLE IF EXISTS sync_out; DROP TABLE IF EXISTS sync_seen; DROP TABLE IF EXISTS sync_state; DROP TABLE IF EXISTS sync_alias');
  d.idBase = 0;
}

const getState = (d, k) => { const r = d.prepare('SELECT v FROM sync_state WHERE k=?').get(k); return r ? r.v : null; };
const putState = (d, k, v) => {
  if (d.prepare('SELECT 1 AS x FROM sync_state WHERE k=?').get(k)) d.prepare('UPDATE sync_state SET v=? WHERE k=?').run(String(v), k);
  else d.prepare('INSERT INTO sync_state(k,v) VALUES(?,?)').run(k, String(v));
};

/** A row as it travels: values without nulls (the database drops nulls), the null columns named in z. */
function pack(t, row) {
  const r = {}, z = [];
  for (const [c, v] of Object.entries(row)) {
    if (v === null || v === undefined) z.push(c);
    else if (typeof v === 'bigint') r[c] = Number(v);
    else if (v instanceof Uint8Array) continue;
    else r[c] = v;
  }
  return z.length ? { r, z: z.join(',') } : { r };
}

/** Local changes not sent yet → log entries (at most `limit` sync_out rows). */
function outgoing(d, limit = 4000) {
  const rows = d.prepare('SELECT seq,tbl,rid,op,dq FROM sync_out ORDER BY seq LIMIT ?').all(limit);
  if (!rows.length) return { changes: [], upTo: 0 };
  const info = Object.fromEntries(tables(d).map((t) => [t.name, t]));
  const groups = new Map();
  for (const x of rows) {
    const g = groups.get(x.tbl + '\u0000' + x.rid) || { tbl: x.tbl, rid: x.rid, ins: false, dq: 0, last: 0 };
    if (x.op === 'i') { g.ins = true; g.dq = 0; } else if (x.op === 'u' && x.dq != null) g.dq += Number(x.dq);
    g.last = x.seq;
    groups.set(x.tbl + '\u0000' + x.rid, g);
  }
  const changes = [];
  for (const g of [...groups.values()].sort((a, b) => a.last - b.last)) {
    const t = info[g.tbl];
    if (!t) continue;
    if (g.tbl === 'settings' && /^sync_/.test(String(g.rid))) continue;
    const row = d.prepare(`SELECT * FROM ${g.tbl} WHERE ${t.pk}=?`).get(g.rid);
    if (!row) { changes.push({ t: g.tbl, k: g.rid }); continue; }
    const c = { t: g.tbl, k: g.rid, ...pack(t, row) };
    if (g.tbl === 'batches' && !g.ins) c.q = Math.round(g.dq * 1000) / 1000;
    changes.push(c);
  }
  return { changes, upTo: rows[rows.length - 1].seq };
}

/** Another device's changes → this company's books (inside one transaction; tracking of these writes is dropped). */
function apply(cid, d, entries) {
  const info = Object.fromEntries(tables(d).map((t) => [t.name, t]));
  const ctx = { cid, slot: Number(getApp('sync_slot') || 0), resend: [] };
  let applied = 0, failed = 0;
  d.pragma('foreign_keys = OFF');
  try {
    db.withCompany(cid, () => d.transaction(() => {
      const before = (d.prepare('SELECT MAX(seq) AS m FROM sync_out').get() || {}).m || 0;
      for (const e of entries) {
        if (e.x) resetBooks(d, info);   // another device restored a backup over these books: start again from its copy
        for (const c of [].concat(e.c || []).filter(Boolean)) {
          const t = info[c.t];
          if (!t || (c.t === 'settings' && /^sync_/.test(String(c.k)))) continue;
          try {
            d.transaction(() => applyOne(d, t, c, ctx, info))();
            applied++;
          } catch (err) {
            failed++;
            console.error('sync: could not apply', c.t, c.k, err && err.message);
          }
        }
      }
      d.prepare('DELETE FROM sync_out WHERE seq > ?').run(before);
      // bills of this device that had to take a new number go out again
      for (const [tbl, rid] of ctx.resend) d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'u')").run(tbl, rid);
    })());
  } finally { d.pragma('foreign_keys = ON'); }
  state.errors += failed;
  // the company was renamed on another device: the company list here shows the new name too
  const nm = d.prepare("SELECT value FROM settings WHERE key='company_name'").get();
  if (nm && nm.value && String(nm.value).trim()) reg.prepare('UPDATE companies SET name=? WHERE id=? AND name<>?').run(String(nm.value).trim(), cid, String(nm.value).trim());
  return applied;
}

/** Empties every synced table (another device restored a backup: its full copy follows). */
function resetBooks(d, info) {
  for (const t of Object.values(info)) {
    d.exec(`DELETE FROM ${t.name}`);
  }
  d.exec('DELETE FROM sync_out');
  d.idNext = {};
}

/**
 * A backup was restored over a synced company (Replace): its books go out whole, after a reset that empties the other
 * devices' copies, and this device reads on from that point (not the changes made before the restore).
 */
function afterReplace(cid) {
  const key = map()[cid];
  if (!key) return;
  const d = db.openCompany(cid);
  if (!d) return;
  attach(cid, d);
  d.exec('DELETE FROM sync_out; DELETE FROM sync_seen');
  for (const t of tables(d)) d.prepare(`INSERT INTO sync_out(tbl,rid,op) SELECT '${t.name}', ${t.pk}, 'i' FROM ${t.name}`).run();
  d.prepare('DELETE FROM sync_state WHERE k=?').run('cursor');
  putState(d, 'reset', '1');
}

// numbered documents: two devices that make a bill at the same moment (or offline) can pick the same number
const NUMBERED = { invoices: ['invoice_no', 'INV'], receipts: ['receipt_no', 'RCT'], purchases: ['purchase_no', 'PUR'], payments: ['voucher_no', 'PAY'], debit_notes: ['note_no', 'DN'] };

/**
 * The same number on two bills: the older bill (lower id) keeps it. The other one, if it was made here, takes this
 * device's next number (ledger lines follow) and goes out again; if another device made it, it is marked "no~id" here
 * until that device's renumbered copy arrives.
 */
function settleNumber(d, t, c, vals, ctx) {
  const [col, series] = NUMBERED[t.name];
  const no = vals[col];
  if (no == null) return;
  const other = d.prepare(`SELECT id, date FROM ${t.name} WHERE ${col}=? AND id<>?`).get(no, c.k);
  if (!other) return;
  const mine = (id) => ctx.slot && Math.floor(Number(id) / RANGE) === ctx.slot;
  if (Number(other.id) < Number(c.k)) { vals[col] = `${no}~${c.k}`; return; }
  if (mine(other.id)) {
    const fresh = nextNo(series, other.date);
    d.prepare(`UPDATE ${t.name} SET ${col}=? WHERE id=?`).run(fresh, other.id);
    ctx.resend.push([t.name, other.id]);
    for (const k of d.prepare('SELECT key FROM counters').all()) ctx.resend.push(['counters', k.key]);
    for (const l of d.prepare('SELECT id FROM ledger WHERE ref_no=? AND id > ? AND id < ?').all(no, ctx.slot * RANGE, (ctx.slot + 1) * RANGE)) {
      d.prepare('UPDATE ledger SET ref_no=?, narration=REPLACE(narration, ?, ?) WHERE id=?').run(fresh, no, fresh, l.id);
      ctx.resend.push(['ledger', l.id]);
    }
  } else {
    d.prepare(`UPDATE ${t.name} SET ${col}=? WHERE id=?`).run(`${no}~${other.id}`, other.id);
  }
}

// ---------- the same category or batch made on two devices at once ----------
const aliasOf = (d, tbl, id) => { const r = d.prepare('SELECT to_id FROM sync_alias WHERE tbl=? AND from_id=?').get(tbl, id); return r ? r.to_id : null; };

/** Row `loser` of t becomes `winner`: everything pointing at it follows, a batch's stock is added, later changes follow too. */
function fold(d, t, info, loser, winner) {
  for (const o of Object.values(info)) for (const f of o.fks) if (f.ref === t.name) d.prepare(`UPDATE ${o.name} SET ${f.col}=? WHERE ${f.col}=?`).run(winner, loser);
  d.prepare('UPDATE sync_alias SET to_id=? WHERE tbl=? AND to_id=?').run(winner, t.name, loser);
  d.prepare('INSERT OR REPLACE INTO sync_alias(tbl,from_id,to_id) VALUES(?,?,?)').run(t.name, loser, winner);
}

/**
 * The incoming row has the same name / batch number as another row here: the two are one record. The older one (lower id)
 * stays on every device; the other is folded into it (bills that use it follow; a batch's stock is added). Every device
 * decides the same way, so the books stay alike without anything more being sent. true = done.
 */
function merged(d, t, c, vals, info) {
  for (const cols of t.uniq) {
    const here = d.prepare(`SELECT * FROM ${t.name} WHERE ${t.pk}=?`).get(c.k);
    const v = cols.map((col) => (col in vals ? vals[col] : here ? here[col] : null));
    if (v.some((x) => x == null)) continue;
    const other = d.prepare(`SELECT * FROM ${t.name} WHERE ${cols.map((x) => `${x}=?`).join(' AND ')} AND ${t.pk}<>?`).get(...v, c.k);
    if (!other) continue;
    const stock = t.name === 'batches';
    if (Number(other[t.pk]) < Number(c.k)) {
      // the incoming row is the newer copy: its stock goes to the older one
      const add = here ? Number(here.qty || 0) + Number(c.q || 0) : Number(vals.qty || 0);
      if (stock && add) d.prepare('UPDATE batches SET qty = qty + ? WHERE id=?').run(add, other[t.pk]);
      fold(d, t, info, c.k, other[t.pk]);   // (rows that arrived before it may already point at it)
      if (here) d.prepare(`DELETE FROM ${t.name} WHERE ${t.pk}=?`).run(c.k);
      return true;
    }
    // the copy here is the newer one: it gives way to the incoming row
    if (stock) vals.qty = (here && c.q != null ? Number(here.qty || 0) + Number(c.q) : Number(vals.qty || 0)) + Number(other.qty || 0);
    d.prepare(`DELETE FROM ${t.name} WHERE ${t.pk}=?`).run(other[t.pk]);
    fold(d, t, info, other[t.pk], c.k);
    if (stock) c = { ...c, q: null };
    write(d, t, c, vals);
    return true;
  }
  return false;
}

function applyOne(d, t, c, ctx, info) {
  // a row that was folded into another one: its stock changes go to the kept row, nothing else
  const al = t.intId ? aliasOf(d, t.name, c.k) : null;
  if (al != null) {
    if (c.r && t.name === 'batches' && c.q) d.prepare('UPDATE batches SET qty = qty + ? WHERE id=?').run(c.q, al);
    return;
  }
  if (!c.r) { d.prepare(`DELETE FROM ${t.name} WHERE ${t.pk}=?`).run(c.k); return; }
  const vals = {};
  for (const [k, v] of Object.entries(c.r)) if (t.cols.includes(k) && k !== t.pk) vals[k] = typeof v === 'object' && v !== null ? JSON.stringify(v) : (typeof v === 'boolean' ? (v ? 1 : 0) : v);
  for (const k of String(c.z || '').split(',').filter(Boolean)) if (t.cols.includes(k) && k !== t.pk) vals[k] = null;
  for (const f of t.fks) if (vals[f.col] != null) { const a = aliasOf(d, f.ref, vals[f.col]); if (a != null) vals[f.col] = a; }
  if (NUMBERED[t.name]) settleNumber(d, t, c, vals, ctx);
  else if (t.uniq.length && merged(d, t, c, vals, info)) return;
  write(d, t, c, vals);
}

function write(d, t, c, vals) {
  const exists = d.prepare(`SELECT 1 AS x FROM ${t.name} WHERE ${t.pk}=?`).get(c.k);
  if (exists) {
    const sets = [], args = [];
    for (const [k, v] of Object.entries(vals)) {
      if (t.name === 'batches' && k === 'qty' && c.q != null) continue;
      if (t.name === 'counters' && k === 'value') { sets.push('value = MAX(value, ?)'); args.push(v); continue; }
      sets.push(`${k}=?`); args.push(v);
    }
    if (t.name === 'batches' && c.q != null && c.q !== 0) { sets.push('qty = qty + ?'); args.push(c.q); }
    if (sets.length) d.prepare(`UPDATE ${t.name} SET ${sets.join(',')} WHERE ${t.pk}=?`).run(...args, c.k);
  } else {
    const cols = [t.pk, ...Object.keys(vals)];
    d.prepare(`INSERT INTO ${t.name}(${cols.join(',')}) VALUES(${cols.map(() => '?').join(',')})`).run(c.k, ...Object.values(vals));
  }
}

// ---------- push ids (Firebase keys start with the time they were made) ----------
const PUSH = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';
function pushTime(k) { let t = 0; for (let i = 0; i < 8; i++) t = t * 64 + PUSH.indexOf(k[i]); return t; }
function pushPrefix(ms) { let s = ''; for (let i = 0; i < 8; i++) { s = PUSH[ms % 64] + s; ms = Math.floor(ms / 64); } return s; }

// ---------- sync steps ----------
async function push(d, key, sl) {
  let sent = 0, last = null;
  if (getState(d, 'reset') === '1') {
    const r = await rtdb('POST', `books/${key}/log`, { s: sl, x: 1 });
    if (r && r.name) { putState(d, 'cursor', r.name); putState(d, 'floor', r.name); d.prepare('INSERT OR IGNORE INTO sync_seen(k,at) VALUES(?,?)').run(r.name, pushTime(r.name)); }
    d.prepare('DELETE FROM sync_state WHERE k=?').run('reset');
  }
  for (let round = 0; round < 20; round++) {
    const { changes, upTo } = outgoing(d);
    if (!changes.length) { if (upTo) d.prepare('DELETE FROM sync_out WHERE seq <= ?').run(upTo); break; }
    for (let i = 0; i < changes.length; i += CHUNK) {
      const r = await rtdb('POST', `books/${key}/log`, { s: sl, c: changes.slice(i, i + CHUNK) });
      if (r && r.name) { d.prepare('INSERT OR IGNORE INTO sync_seen(k,at) VALUES(?,?)').run(r.name, pushTime(r.name)); last = r.name; }
    }
    d.prepare('DELETE FROM sync_out WHERE seq <= ?').run(upTo);
    sent += changes.length;
  }
  return { sent, last };
}

async function pull(cid, d, key, sl) {
  let got = 0;
  for (let round = 0; round < 40; round++) {
    const cursor = getState(d, 'cursor');
    // first read goes back 15 s before the newest entry seen, so an entry that reached the server a moment late is not
    // missed; later reads (catching up) go on from the newest entry
    const from = !cursor ? null : round === 0 ? pushPrefix(Math.max(0, pushTime(cursor) - 15000)) : cursor;
    const limit = cursor && round === 0 ? 200 : 40;
    const q = `&orderBy=${encodeURIComponent('"$key"')}${from ? `&startAt=${encodeURIComponent(JSON.stringify(from))}` : ''}&limitToFirst=${limit}`;
    const page = (await rtdb('GET', `books/${key}/log`, undefined, q)) || {};
    const keys = Object.keys(page).sort();
    const seen = new Set();
    for (let i = 0; i < keys.length; i += 200) {
      const part = keys.slice(i, i + 200);
      for (const x of d.prepare(`SELECT k FROM sync_seen WHERE k IN (${part.map(() => '?').join(',')})`).all(...part)) seen.add(x.k);
    }
    const floor = getState(d, 'floor');
    const fresh = keys.filter((k) => !seen.has(k) && (!floor || k >= floor));
    const theirs = fresh.filter((k) => page[k] && Number(page[k].s) !== sl).map((k) => page[k]);
    if (theirs.length) got += apply(cid, d, theirs);
    for (const k of fresh) d.prepare('INSERT OR IGNORE INTO sync_seen(k,at) VALUES(?,?)').run(k, pushTime(k));
    const last = keys[keys.length - 1];
    const moved = last && (!cursor || last > cursor);
    if (moved) putState(d, 'cursor', last);
    if (last) d.prepare('DELETE FROM sync_seen WHERE at < ?').run(pushTime(getState(d, 'cursor')) - 120000);
    if (keys.length < limit || (!moved && round > 0)) break;
  }
  return got;
}

async function syncCompany(cid) {
  const key = map()[cid];
  const d = db.openCompany(cid);
  if (!key || !d) return 0;
  // merged into another book on another device: move there
  const into = await rtdb('GET', `books/${key}/info/merged_into`);
  if (into && into !== key) return follow(cid, key, into);
  if (!d.idBase) attach(cid, d);
  const sl = Number(getApp('sync_slot'));
  await push(d, key, sl);
  const got = await pull(cid, d, key, sl);
  if (got) state.version++;
  // the company's name in the account follows renames (Companies in your sync account)
  const row = db.companyRow(cid);
  if (row && row.name && getState(d, 'info_name') !== row.name) {
    await rtdb('PUT', `books/${key}/info/name`, row.name);
    putState(d, 'info_name', row.name);
  }
  return got;
}

/** One round for every synced company: the apps call this every few seconds (GET /sync/tick). */
async function tick() {
  if (!getApp('sync_uid') || !Object.keys(map()).length) return brief();
  if (state.running) { await state.running.catch(() => {}); return brief(); }
  state.running = (async () => {
    for (const cid of Object.keys(map())) await syncCompany(Number(cid));
  })();
  try {
    await state.running;
    state.lastSync = now(); state.lastError = null;
  } catch (e) {
    state.lastError = e.message || String(e);
  } finally { state.running = null; }
  return brief();
}
const brief = () => ({ on: !!getApp('sync_uid') && Object.keys(map()).length > 0, version: state.version, companies: state.companies, moved: state.moved, last_sync: state.lastSync, last_error: state.lastError });

/** Sync this company: the first device sends all of its books, other devices then join them. */
async function turnOn(cid) {
  const row = db.companyRow(cid);
  if (!row) throw new HttpError(404, 'Company not found');
  await slot();
  const m = map();
  if (m[cid]) return status(cid);
  // the account already has this company (from another device): two books of one company would never meet
  const same = (await remote(cid)).books.find((b) => b.same_name && !b.on_this_device);
  if (same) {
    throw new HttpError(409, `${row.name} is already in your sync account from another device. Use "Bring here" under Companies in your sync account `
      + 'to use that copy on this device (back up first if this copy has bills the other one does not).');
  }
  const key = randomKey();
  await rtdb('PUT', `books/${key}/info`, { name: row.name, fy: row.fy || null, at: { '.sv': 'timestamp' }, by: getApp('sync_slot') });
  m[cid] = key; setMap(m);
  const d = db.openCompany(cid);
  try {
    attach(cid, d);
    d.exec('DELETE FROM sync_out');
    // everything already in the books goes up once, as the starting point for the other devices
    for (const t of tables(d)) {
      d.prepare(`INSERT INTO sync_out(tbl,rid,op) SELECT '${t.name}', ${t.pk}, 'i' FROM ${t.name}`).run();
    }
    const { last } = await push(d, key, Number(getApp('sync_slot')));
    // where the starting copy ends in the log: a later merge (below) replays only the changes after it
    if (last) await rtdb('PUT', `books/${key}/info/snap`, last);
  } catch (e) {
    state.lastError = e.message;
  }
  return status(cid);
}

function turnOff(cid) {
  const m = map();
  if (!m[cid]) return status(cid);
  delete m[cid]; setMap(m);
  detach(cid);
  return status(cid);
}

/** Books of this account that are not on this device yet. */
async function remote(cid) {
  const books = (await rtdb('GET', 'books', undefined, '&shallow=true')) || {};
  const m = map();
  const here = new Set(Object.values(m));
  const row = cid ? db.companyRow(cid) : null;
  const norm = (x) => String(x || '').toLowerCase().replace(/[^a-z0-9]/g, '');   // "A.K Enterprises" = "AK ENTERPRISES"
  const out = [];
  // which devices write to each book ("Mac, iPhone (this one)"), from its latest entries
  const dev = (await rtdb('GET', 'devices')) || {};
  const slots = Object.keys(dev).sort();
  const mine = await mySlots();
  const kind = (n) => (/^darwin/.test(n) ? 'Mac' : /^iphone/i.test(n) ? 'iPhone' : /^android/.test(n) ? 'Android' : /^win32/.test(n) ? 'Windows' : /^linux/.test(n) ? 'Linux' : 'Device');
  for (const key of Object.keys(books)) {
    const info = (await rtdb('GET', `books/${key}/info`)) || {};
    if (info.merged_into) continue;   // its changes were moved into another book (merge)
    const last = (await rtdb('GET', `books/${key}/log`, undefined, `&orderBy=${encodeURIComponent('"$key"')}&limitToLast=300`)) || {};
    const used = new Set();
    for (const e of Object.values(last)) if (e && e.s) { const d = dev[slots[Number(e.s) - 1]]; used.add(mine.has(Number(e.s)) ? 'this device' : kind(String((d && d.name) || ''))); }
    out.push({
      key, name: info.name || 'Company', fy: info.fy || null, on_this_device: here.has(key), open: !!cid && m[cid] === key, used_by: [...used].sort(),
      // the open company has the same name but syncs into another book (or none): it can be merged into this one;
      // a copy with no year (set up before years were kept, or imported) still matches
      same_name: !!row && norm(info.name) === norm(row.name) && (!info.fy || !row.fy || info.fy === row.fy) && m[cid] !== key,
    });
  }
  return { books: out, can_merge: !!(cid && m[cid]) };
}

/** Where the starting copy ends in a book's log: info.snap, or (older books) the first run of entries sent together. */
function snapshotEnd(keys, log, info) {
  if (info && info.snap && keys.includes(info.snap)) return info.snap;
  if (!keys.length) return null;
  let end = keys[0];
  for (let i = 1; i < keys.length; i++) {
    const a = log[keys[i - 1]], b = log[keys[i]];
    if (!b || b.x || Number(b.s) !== Number(log[keys[0]].s) || pushTime(keys[i]) - pushTime(keys[i - 1]) > 10000) break;
    end = keys[i];
    if (a && a.x) break;
  }
  return end;
}

/**
 * Two devices turned sync on for their own copy of one company, so it synced into two books. Merging (on one of them)
 * makes the open company part of the other book: that book comes here as a fresh company, every change this company's
 * book had after its starting copy is replayed on it (bills keep their stock, a bill number taken there gets the next
 * one) and goes out to the other devices; this company's old copy is kept as a backup and hidden from the list.
 */
/**
 * The slots that are this device: its own, and earlier installs of the same kind (an iPhone that signed out and in again
 * registered anew). A book written only by these is this device's own copy.
 */
async function mySlots() {
  const dev = (await rtdb('GET', 'devices')) || {};
  const me = getApp('sync_device');
  const name = me && dev[me] ? dev[me].name : null;
  const out = new Set([Number(getApp('sync_slot'))]);
  Object.keys(dev).sort().forEach((k, i) => { if (name && dev[k] && dev[k].name === name) out.add(i + 1); });
  return out;
}

async function merge(cid, key) {
  // one merge at a time: a second tap (or a retry after the app stopped waiting) would replay the same bills twice
  if (state.merging) throw new HttpError(409, 'The merge is still running. Wait a minute, then tap Look again.');
  state.merging = true;
  try { return await mergeNow(cid, key); } finally { state.merging = false; }
}
async function mergeNow(cid, key) {
  const m = map();
  const tKey = m[cid];
  if (!tKey) throw new HttpError(400, 'Turn on sync for this company first, or use Bring here.');
  if (!key || key === tKey) throw new HttpError(400, 'Choose the other copy of this company.');
  const row = db.companyRow(cid);
  const srcInfo = await rtdb('GET', `books/${key}/info`);
  if (!srcInfo) throw new HttpError(404, 'That company is no longer in the sync account.');
  if (srcInfo.merged_into) throw new HttpError(409, 'That copy is already merged. Tap Look again.');
  const srcCid = Number((Object.entries(m).find(([, v]) => v === key) || [])[0]) || null;
  if (srcCid) await syncCompany(srcCid);                    // that copy's last changes here are in its book first
  await syncCompany(cid);
  const log = (await rtdb('GET', `books/${key}/log`)) || {};
  const keys = Object.keys(log).sort();
  const end = snapshotEnd(keys, log, srcInfo);
  const after = end ? keys.filter((k) => k > end) : [];
  if (after.some((k) => log[k] && log[k].x)) throw new HttpError(409, 'A backup was restored on that copy after sync was turned on, so it cannot be merged.');
  const entries = after.map((k) => log[k]).filter((e) => e && e.c);
  const snap = keys.filter((k) => !end || k <= end).map((k) => log[k]).filter((e) => e && e.c);
  const d = db.openCompany(cid);
  // the same starting books (same items and parties under the same ids), or each made its own (two Marg imports):
  // then the other copy's items, parties and batches are matched to these by name, and its new rows get ids here
  const probe = [];
  for (const e of snap) for (const c of [].concat(e.c || [])) if (c && c.r && (c.t === 'items' || c.t === 'parties')) probe.push(c);
  const same = probe.filter((c) => { const x = d.prepare(`SELECT name FROM ${c.t} WHERE id=?`).get(c.k); return x && x.name === c.r.name; }).length;
  let replay = entries;
  if (probe.length && same / probe.length < 0.8) replay = db.withCompany(cid, () => d.transaction(() => crossTranslate(d, snap, entries))());
  require('./backup').backupNow({ reason: 'before-merge' });
  replayInto(cid, d, replay);
  // the devices still on that copy move to this one by themselves on their next sync (follow, below)
  await rtdb('PUT', `books/${key}/info/merged_at`, keys[keys.length - 1] || '');
  await rtdb('PUT', `books/${key}/info/merged_into`, tKey);
  if (srcCid) moved(srcCid, cid);
  syncCompany(cid).catch((e) => { state.lastError = e.message; });
  state.version++;
  return { company_id: cid, merged: entries.length, ...status(cid) };
}

// rows matched by what they are, when two copies were set up separately (their ids mean different things)
const NATURAL = { items: ['name'], parties: ['name'], categories: ['name'], salesmen: ['name'], routes: ['name'], batches: ['item_id', 'batch_no'] };
const norm = (v) => String(v == null ? '' : v).trim().toLowerCase().replace(/\s+/g, ' ');

/**
 * The other copy was set up on its own (its starting rows have ids that mean other things here): its changes are
 * rewritten for these books. Its starting items, parties, categories, salesmen, routes and batches are matched to these
 * by name (batch: item and batch number); a starting row with no match is added here with a new id. Rows it made later
 * keep their ids (each device has its own range). Its settings and counters stay out (this copy's numbering goes on).
 */
function crossTranslate(d, snap, entries) {
  const info = Object.fromEntries(tables(d).map((t) => [t.name, t]));
  const base = {};   // table → id → its starting row
  for (const e of snap) for (const c of [].concat(e.c || []).filter(Boolean)) {
    if (!c.r) continue;
    const row = { ...c.r };
    for (const z of String(c.z || '').split(',').filter(Boolean)) row[z] = null;
    (base[c.t] = base[c.t] || {})[c.k] = row;
  }
  const map = {};    // table → their id → id here
  const tr = (tbl, id) => {
    if (id == null || !info[tbl] || !info[tbl].intId || Number(id) >= RANGE) return id;   // ids of later rows are the same everywhere
    const m = (map[tbl] = map[tbl] || {});
    if (m[id] != null) return m[id];
    const row = base[tbl] && base[tbl][id];
    const t = info[tbl];
    const vals = {};
    if (row) for (const [k, v] of Object.entries(row)) if (t.cols.includes(k) && k !== t.pk) vals[k] = typeof v === 'object' && v !== null ? JSON.stringify(v) : v;
    for (const f of t.fks) if (vals[f.col] != null) vals[f.col] = tr(f.ref, vals[f.col]);
    const keys = NATURAL[tbl];
    if (row && keys && keys.every((k) => vals[k] != null)) {
      const hit = d.prepare(`SELECT ${t.pk} AS id FROM ${tbl} WHERE ${keys.map((k) => (k === 'name' || k === 'batch_no' ? `lower(trim(${k}))=?` : `${k}=?`)).join(' AND ')}`)
        .get(...keys.map((k) => (k === 'name' || k === 'batch_no' ? norm(vals[k]) : vals[k])));
      if (hit) { m[id] = hit.id; return hit.id; }
    }
    // not here yet: added with an id of this device
    const nid = d.nextId(tbl);
    m[id] = nid;
    if (row) {
      const cols = Object.keys(vals);
      d.prepare(`INSERT INTO ${tbl}(${[t.pk, ...cols].join(',')}) VALUES(${[t.pk, ...cols].map(() => '?').join(',')})`).run(nid, ...cols.map((k) => vals[k]));
    }
    return nid;
  };
  const out = [];
  for (const e of entries) {
    const list = [];
    for (const c of [].concat(e.c || []).filter(Boolean)) {
      const t = info[c.t];
      if (!t || c.t === 'settings' || c.t === 'counters') continue;
      if (!t.intId) { list.push(c); continue; }
      const own = Number(c.k) >= RANGE;
      if (!c.r) { if (own) list.push(c); continue; }   // a starting row deleted there stays here
      const r = { ...c.r };
      for (const f of t.fks) if (r[f.col] != null) r[f.col] = tr(f.ref, r[f.col]);
      // a later row of a matched kind (a new party with a name already here) is that row
      let k = c.k;
      const keys = NATURAL[c.t];
      if (own && keys && !t.uniq.length && keys.every((x) => r[x] != null)) {   // (a UNIQUE kind is folded by apply)
        const hit = d.prepare(`SELECT ${t.pk} AS id FROM ${c.t} WHERE ${keys.map((x) => (x === 'name' || x === 'batch_no' ? `lower(trim(${x}))=?` : `${x}=?`)).join(' AND ')} AND ${t.pk}<>?`)
          .get(...keys.map((x) => (x === 'name' || x === 'batch_no' ? norm(r[x]) : r[x])), c.k);
        if (hit) { (map[c.t] = map[c.t] || {})[c.k] = hit.id; k = hit.id; }
      } else if (!own) k = tr(c.t, c.k);
      if (own && map[c.t] && map[c.t][c.k] != null) k = map[c.t][c.k];
      list.push({ ...c, k, r });
    }
    if (list.length) out.push({ ...e, c: list });
  }
  return out;
}

/** Book changes replayed on company tid: applied, bill numbers used twice settled, and sent out to the other devices. */
function replayInto(tid, d, entries) {
  apply(tid, d, entries);
  db.withCompany(tid, () => d.transaction(() => {
    // a bill whose number the other copy had already used takes the next number (its ledger lines follow)
    for (const [tbl, [col, series]] of Object.entries(NUMBERED)) {
      for (const r of d.prepare(`SELECT id, date, ${col} AS no FROM ${tbl} WHERE ${col} LIKE '%~%'`).all()) {
        const old = String(r.no).split('~')[0];
        const fresh = nextNo(series, r.date);
        const lo = Math.floor(Number(r.id) / RANGE) * RANGE, hi = lo + RANGE;
        d.prepare(`UPDATE ${tbl} SET ${col}=? WHERE id=?`).run(fresh, r.id);
        d.prepare('UPDATE ledger SET ref_no=?, narration=REPLACE(narration, ?, ?) WHERE ref_no=? AND id > ? AND id < ?').run(fresh, old, fresh, old, lo, hi);
        d.prepare("INSERT INTO sync_out(tbl,rid,op) SELECT 'ledger', id, 'u' FROM ledger WHERE ref_no=? AND id > ? AND id < ?").run(fresh, lo, hi);
        d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'u')").run(tbl, r.id);
      }
    }
    // the replayed changes go out to the other devices (a batch's stock as the change it made)
    for (const e of entries) {
      for (const c of [].concat(e.c || []).filter(Boolean)) {
        if (!c.r) d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'d')").run(c.t, c.k);
        else if (c.t === 'batches' && c.q != null) d.prepare("INSERT INTO sync_out(tbl,rid,op,dq) VALUES(?,?,'u',?)").run(c.t, c.k, c.q);
        else d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'i')").run(c.t, c.k);
      }
    }
    for (const k of d.prepare('SELECT key FROM counters').all()) d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES('counters',?,'u')").run(k.key);
  })());
}

/** Company `from` was merged into `to`: it is hidden (kept as a backup) and the apps switch to `to`. */
function moved(from, to) {
  const row = db.companyRow(from);
  if (row) db.registry.prepare('UPDATE companies SET name=? WHERE id=?').run(row.name, to);
  db.registry.prepare('UPDATE companies SET active=0 WHERE id=?').run(from);
  const mm = map(); delete mm[from]; setMap(mm);
  state.moved[from] = to;
  state.companies++;
}

/**
 * This company's book was merged into another one (on another device): this device moves there too. The other book
 * comes here (or is here already), and what this device wrote into the old book after the merge is replayed on it.
 */
async function follow(cid, key, into) {
  const d = db.openCompany(cid);
  const sl = Number(getApp('sync_slot'));
  await push(d, key, sl);
  const at = await rtdb('GET', `books/${key}/info/merged_at`);
  let tid = Number((Object.entries(map()).find(([, v]) => v === into) || [])[0]) || null;
  if (!tid) tid = (await join(into)).company_id;
  else await syncCompany(tid);
  if (at) {
    const mine = await mySlots();
    const page = (await rtdb('GET', `books/${key}/log`, undefined, `&orderBy=${encodeURIComponent('"$key"')}&startAt=${encodeURIComponent(JSON.stringify(at))}`)) || {};
    const late = Object.keys(page).sort().filter((k) => k > at && page[k] && page[k].c && mine.has(Number(page[k].s))).map((k) => page[k]);
    if (late.length) replayInto(tid, db.openCompany(tid), late);
  }
  moved(cid, tid);
  state.version++;
  return 0;
}

/** Bring a synced company onto this device: a new, empty company that fills itself from the other devices' changes. */
async function join(key) {
  if (!key) throw new HttpError(400, 'Choose the company to bring here.');
  if (Object.values(map()).includes(key)) throw new HttpError(400, 'That company is already synced on this device.');
  await slot();
  const info = await rtdb('GET', `books/${key}/info`);
  if (!info) throw new HttpError(404, 'That company is no longer in the sync account.');
  const cid = db.createCompany({ name: info.name || 'Company', fy: info.fy || null });
  const d = db.openCompany(cid);
  // start empty: every row (settings too) comes from the other devices
  for (const t of tables(d)) d.exec(`DELETE FROM ${t.name}`);
  const m = map(); m[cid] = key; setMap(m);
  attach(cid, d);
  d.exec('DELETE FROM sync_out');
  try { await syncCompany(cid); state.lastError = null; } catch (e) { state.lastError = e.message; }
  const nm = d.prepare("SELECT value FROM settings WHERE key='company_name'").get();
  if (nm && nm.value) reg.prepare('UPDATE companies SET name=? WHERE id=?').run(nm.value, cid);
  state.version++;
  return { company_id: cid, ...status(cid) };
}

function status(cid) {
  const m = map();
  const companies = reg.prepare('SELECT id,name,fy FROM companies WHERE active=1 ORDER BY id').all()
    .map((c) => ({ id: c.id, name: c.name, fy: c.fy, synced: !!m[c.id] }));
  let pending = 0;
  if (cid && m[cid]) { try { pending = (db.openCompany(cid).prepare('SELECT COUNT(*) AS n FROM sync_out').get() || {}).n || 0; } catch { pending = 0; } }
  return {
    signed_in: !!getApp('sync_uid'), email: getApp('sync_email') || '', slot: Number(getApp('sync_slot') || 0),
    on: !!(cid && m[cid]), companies, pending, errors: state.errors,
    version: state.version, last_sync: state.lastSync, last_error: state.lastError,
    database: CONFIG.databaseURL,
    rules: '{ "rules": { "users": { "$uid": { ".read": "auth != null && auth.uid === $uid", ".write": "auth != null && auth.uid === $uid" } } } }',
  };
}

for (const [id, d] of db.openHandles()) attach(id, d);

module.exports = { signIn, signOut, status, tick, turnOn, turnOff, remote, join, merge, attach, afterReplace, CONFIG, _state: state, pushTime, pushPrefix };
