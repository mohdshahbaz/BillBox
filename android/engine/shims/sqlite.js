// node:sqlite (DatabaseSync) on Android's SQLite, through the app's AndroidSQL bridge, behaving like Node's:
//   numbers bind as REAL (as node:sqlite does), text as TEXT, null as NULL, bytes as BLOB; booleans / undefined are refused;
//   ?, ?NNN, @name, :name and $name parameters are numbered exactly as SQLite numbers them;
//   exec() runs several statements one by one (Android runs only the first statement of a string);
//   errors carry code ERR_SQLITE_ERROR, errcode and errstr.
'use strict';
const ERRSTR = { 1: 'SQL logic error', 5: 'database is locked', 6: 'database table is locked', 8: 'attempt to write a readonly database',
  10: 'disk I/O error', 11: 'database disk image is malformed', 13: 'database or disk is full', 14: 'unable to open database file',
  19: 'constraint failed', 20: 'datatype mismatch', 21: 'bad parameter or other API misuse', 26: 'file is not a database' };
const bridge = () => globalThis.AndroidSQL;

function fail(r) {
  const e = new Error(r.error.message);
  e.code = 'ERR_SQLITE_ERROR';
  e.errcode = r.error.errcode;
  e.errstr = ERRSTR[r.error.errcode & 255] || 'unknown error';
  return e;
}
function reply(s) { const r = JSON.parse(s); if (r && r.error) throw fail(r); return r; }

/** Splits SQL into statements at semicolons outside quotes and comments. */
function split(sql) {
  const out = []; let cur = ''; let i = 0;
  while (i < sql.length) {
    const c = sql[i];
    if (c === "'" || c === '"' || c === '`' || c === '[') {
      const end = c === '[' ? ']' : c; let j = i + 1;
      while (j < sql.length) { if (sql[j] === end) { if (end !== ']' && sql[j + 1] === end) { j += 2; continue; } break; } j++; }
      cur += sql.slice(i, j + 1); i = j + 1; continue;
    }
    if (c === '-' && sql[i + 1] === '-') { const j = sql.indexOf('\n', i); i = j < 0 ? sql.length : j + 1; cur += ' '; continue; }
    if (c === '/' && sql[i + 1] === '*') { const j = sql.indexOf('*/', i + 2); i = j < 0 ? sql.length : j + 2; cur += ' '; continue; }
    if (c === ';') { if (cur.trim()) out.push(cur.trim()); cur = ''; i++; continue; }
    cur += c; i++;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

/** Parameters in SQLite's order: [{ name } | { index }] → number of slots and the slot of each name. */
function params(sql) {
  const names = new Map(); let next = 0; let max = 0; const anon = []; let out = ''; let last = 0;
  let i = 0;
  while (i < sql.length) {
    const c = sql[i];
    if (c === "'" || c === '"' || c === '`') { let j = i + 1; while (j < sql.length && !(sql[j] === c && sql[j + 1] !== c)) j += sql[j] === c ? 2 : 1; i = j + 1; continue; }
    if (c === '-' && sql[i + 1] === '-') { const j = sql.indexOf('\n', i); i = j < 0 ? sql.length : j + 1; continue; }
    if (c === '/' && sql[i + 1] === '*') { const j = sql.indexOf('*/', i + 2); i = j < 0 ? sql.length : j + 2; continue; }
    if (c === '?') {
      let j = i + 1; while (j < sql.length && sql[j] >= '0' && sql[j] <= '9') j++;
      if (j > i + 1) { const n = Number(sql.slice(i + 1, j)); max = Math.max(max, n); next = Math.max(next, n); }
      else { next = Math.max(next, max) + 1; max = next; anon.push(next); }
      i = j; continue;
    }
    if ((c === '@' || c === ':' || c === '$') && /[A-Za-z_]/.test(sql[i + 1] || '')) {
      let j = i + 1; while (j < sql.length && /\w/.test(sql[j])) j++;
      const nm = sql.slice(i + 1, j);
      if (!names.has(nm)) { next = Math.max(next, max) + 1; max = next; names.set(nm, next); }
      out += sql.slice(last, i) + '?' + names.get(nm); last = j;   // the bridge binds by number only
      i = j; continue;
    }
    i++;
  }
  out += sql.slice(last);
  return { count: max, names, anon, sql: out };
}

function value(v, i) {
  if (v === null) return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : (() => { throw bad(i); })();
  if (typeof v === 'string') return v;
  if (typeof v === 'bigint') return Number(v);
  if (v instanceof Uint8Array) return { $b64: Buffer.from(v).toString('base64') };
  throw bad(i);
}
function bad(i) { const e = new TypeError(`Provided value cannot be bound to SQLite parameter ${i}.`); e.code = 'ERR_INVALID_ARG_TYPE'; return e; }

function rowsOut(rows) {
  for (const r of rows) for (const k of Object.keys(r)) { const v = r[k]; if (v && typeof v === 'object' && v.$b64 !== undefined) r[k] = new Uint8Array(Buffer.from(v.$b64, 'base64')); }
  return rows;
}

class StatementSync {
  constructor(db, sql) { this.db = db; this.sql = sql; this.p = params(sql); }
  args(a) {
    const slots = new Array(this.p.count).fill(undefined);
    let named = null; let pos = a;
    if (a.length && a[0] && typeof a[0] === 'object' && !Array.isArray(a[0]) && !(a[0] instanceof Uint8Array)) { named = a[0]; pos = a.slice(1); }
    if (named) for (const [k, v] of Object.entries(named)) { const key = k.replace(/^[@:$]/, ''); if (this.p.names.has(key)) slots[this.p.names.get(key) - 1] = v; else { const e = new Error(`Unknown named parameter '${k}'`); e.code = 'ERR_INVALID_STATE'; throw e; } }
    // positional values fill the slots that are not named, in order
    let k = 0;
    for (let s = 0; s < slots.length && k < pos.length; s++) { if (named && [...this.p.names.values()].includes(s + 1)) continue; slots[s] = pos[k++]; }
    return slots.map((v, i) => (v === undefined ? null : value(v, i + 1)));
  }
  run(...a) { return reply(bridge().query(this.db.h, this.p.sql, JSON.stringify(this.args(a)), 'run')); }
  get(...a) { const r = reply(bridge().query(this.db.h, this.p.sql, JSON.stringify(this.args(a)), 'get')); return r.rows.length ? rowsOut(r.rows)[0] : undefined; }
  all(...a) { return rowsOut(reply(bridge().query(this.db.h, this.p.sql, JSON.stringify(this.args(a)), 'all')).rows); }
}

class DatabaseSync {
  constructor(file, opts = {}) { this.h = reply(bridge().open(String(file), !!opts.readOnly)).handle; }
  exec(sql) { for (const s of split(sql)) reply(bridge().exec(this.h, s)); }
  prepare(sql) { return new StatementSync(this, sql); }
  close() { reply(bridge().close(this.h)); }
}
module.exports = { DatabaseSync, split, params };
