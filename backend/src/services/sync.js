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
const LOCAL = new Set(['sync_out', 'sync_state', 'sync_seen']);
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
const state = { version: 0, lastSync: null, lastError: null, running: null, errors: 0, token: null, tokenExp: 0 };

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

/** This device's slot: its place among the account's devices (each install adds itself once). */
async function slot() {
  const have = Number(getApp('sync_slot') || 0);
  if (have) return have;
  let mine = getApp('sync_device');
  if (!mine) {
    const r = await rtdb('POST', 'devices', { at: { '.sv': 'timestamp' }, name: String((typeof process !== 'undefined' && process.platform) || 'device') });
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
    out.push({ name, pk: pk[0].name, intId: pk[0].name === 'id' && /INT/i.test(pk[0].type), cols: cols.map((c) => c.name) });
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
CREATE TABLE IF NOT EXISTS sync_seen (k TEXT PRIMARY KEY, at INTEGER)`);
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
  d.exec('DROP TABLE IF EXISTS sync_out; DROP TABLE IF EXISTS sync_seen; DROP TABLE IF EXISTS sync_state');
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
        for (const c of [].concat(e.c || []).filter(Boolean)) {
          const t = info[c.t];
          if (!t || (c.t === 'settings' && /^sync_/.test(String(c.k)))) continue;
          try {
            d.transaction(() => applyOne(d, t, c, ctx))();
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
  return applied;
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

function applyOne(d, t, c, ctx) {
  if (!c.r) { d.prepare(`DELETE FROM ${t.name} WHERE ${t.pk}=?`).run(c.k); return; }
  const vals = {};
  for (const [k, v] of Object.entries(c.r)) if (t.cols.includes(k) && k !== t.pk) vals[k] = typeof v === 'object' && v !== null ? JSON.stringify(v) : (typeof v === 'boolean' ? (v ? 1 : 0) : v);
  for (const k of String(c.z || '').split(',').filter(Boolean)) if (t.cols.includes(k) && k !== t.pk) vals[k] = null;
  if (NUMBERED[t.name]) settleNumber(d, t, c, vals, ctx);
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
  let sent = 0;
  for (let round = 0; round < 20; round++) {
    const { changes, upTo } = outgoing(d);
    if (!changes.length) { if (upTo) d.prepare('DELETE FROM sync_out WHERE seq <= ?').run(upTo); break; }
    for (let i = 0; i < changes.length; i += CHUNK) {
      const r = await rtdb('POST', `books/${key}/log`, { s: sl, c: changes.slice(i, i + CHUNK) });
      if (r && r.name) d.prepare('INSERT OR IGNORE INTO sync_seen(k,at) VALUES(?,?)').run(r.name, pushTime(r.name));
    }
    d.prepare('DELETE FROM sync_out WHERE seq <= ?').run(upTo);
    sent += changes.length;
  }
  return sent;
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
    const fresh = keys.filter((k) => !seen.has(k));
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
  if (!d.idBase) attach(cid, d);
  const sl = Number(getApp('sync_slot'));
  await push(d, key, sl);
  const got = await pull(cid, d, key, sl);
  if (got) state.version++;
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
const brief = () => ({ on: !!getApp('sync_uid') && Object.keys(map()).length > 0, version: state.version, last_sync: state.lastSync, last_error: state.lastError });

/** Sync this company: the first device sends all of its books, other devices then join them. */
async function turnOn(cid) {
  const row = db.companyRow(cid);
  if (!row) throw new HttpError(404, 'Company not found');
  await slot();
  const m = map();
  if (m[cid]) return status(cid);
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
    await push(d, key, Number(getApp('sync_slot')));
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
async function remote() {
  const books = (await rtdb('GET', 'books', undefined, '&shallow=true')) || {};
  const here = new Set(Object.values(map()));
  const out = [];
  for (const key of Object.keys(books)) {
    const info = (await rtdb('GET', `books/${key}/info`)) || {};
    out.push({ key, name: info.name || 'Company', fy: info.fy || null, on_this_device: here.has(key) });
  }
  return { books: out };
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

module.exports = { signIn, signOut, status, tick, turnOn, turnOff, remote, join, attach, CONFIG, _state: state, pushTime, pushPrefix };
