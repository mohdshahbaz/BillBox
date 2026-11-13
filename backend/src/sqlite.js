/**
 * SQLite through Node's built-in node:sqlite (Node 22.5+), wrapped to the small better-sqlite3 style API the app uses:
 * prepare().run/get/all, exec, pragma, transaction (nested = savepoints), close, { readonly }.
 * No native module has to be installed or compiled, which is what lets the backend ship inside the app.
 */
const { DatabaseSync } = require('node:sqlite');

const ID_RANGE = 10000000; // ids per device: slot × 10 000 000 stays below 2^31 for the Android app's Int ids (slots ≤ 210)
const INSERT = /^(\s*INSERT\s+(?:OR\s+\w+\s+)?INTO\s+)(\w+)(\s*\()([^)]*)(\)\s*VALUES\s*\()/i;

class Database {
  constructor(file, opts = {}) {
    this.d = new DatabaseSync(file, { readOnly: !!opts.readonly });
    this.depth = 0;
    // Live sync (services/sync.js): rows this device adds get ids from its own range (idBase + 1 …), so two devices
    // never hand out the same id. 0 = sync off, ids as SQLite picks them.
    this.idBase = 0;
    this.idTables = new Set();
    this.idNext = {};
    // prepared statements, compiled once per SQL text (and per id range, which changes the INSERT rewrite)
    this.cache = new Map();
  }
  /** Next free id of this device's range in table t. */
  nextId(t) {
    let n = this.idNext[t];
    if (n == null) {
      // ids folded into another row (sync_alias) are never handed out again
      const r = this.d.prepare(`SELECT MAX(m) AS m FROM (SELECT MAX(id) AS m FROM ${t} WHERE id > ?1 AND id < ?2
        UNION ALL SELECT MAX(from_id) FROM sync_alias WHERE tbl='${t}' AND from_id > ?1 AND from_id < ?2)`).get(this.idBase, this.idBase + ID_RANGE);
      n = r && r.m != null ? Number(r.m) + 1 : this.idBase + 1;
    }
    this.idNext[t] = n + 1;
    return n;
  }
  pragma(s) { this.d.exec('PRAGMA ' + s); }
  exec(s) { this.cache.clear(); this.d.exec(s); } // DDL may change what a cached statement means
  close() { this.cache.clear(); this.d.close(); }
  prepare(sql) {
    const key = this.idBase + '|' + sql;
    let p = this.cache.get(key);
    if (!p) {
      p = this._prepare(sql);
      if (this.cache.size >= 500) this.cache.delete(this.cache.keys().next().value); // oldest first
      this.cache.set(key, p);
    }
    return p;
  }
  _prepare(s) {
    // sync on: "INSERT INTO t(a,b) VALUES(…)" without an id gets this device's next id as its first value
    let idTable = null, named = false;
    if (this.idBase) {
      const m = INSERT.exec(s);
      if (m && this.idTables.has(m[2]) && !m[4].split(',').some((c) => c.trim().toLowerCase() === 'id')) {
        idTable = m[2];
        named = !s.includes('?');
        s = m[1] + m[2] + m[3] + 'id,' + m[4] + m[5] + (named ? '@__bbid,' : '?,') + s.slice(m[0].length);
      }
    }
    const st = this.d.prepare(s);
    // better-sqlite3 ignores object keys the SQL does not use; node:sqlite throws on them, so keep only the names the statement mentions
    const used = new Set([...s.matchAll(/[@:$]([A-Za-z_]\w*)/g)].map((m) => m[1]));
    const norm = (a) => {
      if (a.length === 1 && a[0] && typeof a[0] === 'object' && !Array.isArray(a[0]) && !Buffer.isBuffer(a[0])) {
        return [Object.fromEntries(Object.entries(a[0]).filter(([k]) => used.has(k)))];
      }
      return a;
    };
    if (idTable) {
      const withId = (a) => {
        const id = this.nextId(idTable);
        if (!named) return [id, ...a];
        const o = a.length === 1 && a[0] && typeof a[0] === 'object' ? a[0] : {};
        return [{ ...o, __bbid: id }];
      };
      return { run: (...a) => st.run(...norm(withId(a))), get: (...a) => st.get(...norm(withId(a))), all: (...a) => st.all(...norm(withId(a))) };
    }
    return { run: (...a) => st.run(...norm(a)), get: (...a) => st.get(...norm(a)), all: (...a) => st.all(...norm(a)) };
  }
  transaction(fn) {
    return (...a) => {
      const nested = this.depth > 0, sp = 'sp' + this.depth;
      this.d.exec(nested ? `SAVEPOINT ${sp}` : 'BEGIN');
      this.depth++;
      try {
        const r = fn(...a);
        this.depth--;
        this.d.exec(nested ? `RELEASE ${sp}` : 'COMMIT');
        return r;
      } catch (e) {
        this.depth--;
        this.d.exec(nested ? `ROLLBACK TO ${sp}; RELEASE ${sp}` : 'ROLLBACK');
        throw e;
      }
    };
  }
};
Database.ID_RANGE = ID_RANGE;
module.exports = Database;
