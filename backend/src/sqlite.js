/**
 * SQLite through Node's built-in node:sqlite (Node 22.5+), wrapped to the small better-sqlite3 style API the app uses:
 * prepare().run/get/all, exec, pragma, transaction (nested = savepoints), close, { readonly }.
 * No native module has to be installed or compiled, which is what lets the backend ship inside the app.
 */
const { DatabaseSync } = require('node:sqlite');

module.exports = class Database {
  constructor(file, opts = {}) {
    this.d = new DatabaseSync(file, { readOnly: !!opts.readonly });
    this.depth = 0;
  }
  pragma(s) { this.d.exec('PRAGMA ' + s); }
  exec(s) { this.d.exec(s); }
  close() { this.d.close(); }
  prepare(s) {
    const st = this.d.prepare(s);
    // better-sqlite3 ignores object keys the SQL does not use; node:sqlite throws on them, so keep only the names the statement mentions
    const used = new Set([...s.matchAll(/[@:$]([A-Za-z_]\w*)/g)].map((m) => m[1]));
    const norm = (a) => {
      if (a.length === 1 && a[0] && typeof a[0] === 'object' && !Array.isArray(a[0]) && !Buffer.isBuffer(a[0])) {
        return [Object.fromEntries(Object.entries(a[0]).filter(([k]) => used.has(k)))];
      }
      return a;
    };
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
