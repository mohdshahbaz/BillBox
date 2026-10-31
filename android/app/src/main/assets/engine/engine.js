// BillBox engine for Android, built by android/engine/build.mjs from backend/src. Do not edit by hand.
"use strict";
(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __esm = (fn, res, err) => function __init() {
    if (err) throw err[0];
    try {
      return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
    } catch (e) {
      throw err = [e], e;
    }
  };
  var __commonJS = (cb, mod) => function __require() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));

  // shims/buffer.js
  var require_buffer = __commonJS({
    "shims/buffer.js"(exports, module) {
      "use strict";
      init_globals();
      var te = new TextEncoder();
      var td = new TextDecoder("utf-8");
      function latin1(bytes) {
        let s = "";
        for (let i = 0; i < bytes.length; i += 32768) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
        return s;
      }
      var Buffer3 = class _Buffer extends Uint8Array {
        static from(x, enc) {
          if (typeof x === "string") {
            const e = String(enc || "utf8").toLowerCase();
            if (e === "base64") {
              const b = atob(x.replace(/[^A-Za-z0-9+/=]/g, ""));
              const o2 = new _Buffer(b.length);
              for (let i = 0; i < b.length; i++) o2[i] = b.charCodeAt(i);
              return o2;
            }
            if (e === "latin1" || e === "binary" || e === "ascii") {
              const o2 = new _Buffer(x.length);
              for (let i = 0; i < x.length; i++) o2[i] = x.charCodeAt(i) & 255;
              return o2;
            }
            if (e === "hex") {
              const o2 = new _Buffer(x.length >> 1);
              for (let i = 0; i < o2.length; i++) o2[i] = parseInt(x.substr(i * 2, 2), 16);
              return o2;
            }
            const u = te.encode(x);
            const o = new _Buffer(u.length);
            o.set(u);
            return o;
          }
          if (x instanceof ArrayBuffer) return new _Buffer(x);
          if (ArrayBuffer.isView(x)) {
            const o = new _Buffer(x.byteLength);
            o.set(new Uint8Array(x.buffer, x.byteOffset, x.byteLength));
            return o;
          }
          if (Array.isArray(x)) {
            const o = new _Buffer(x.length);
            for (let i = 0; i < x.length; i++) o[i] = x[i] & 255;
            return o;
          }
          throw new TypeError("Buffer.from: unsupported value");
        }
        static alloc(n, fill) {
          const b = new _Buffer(n);
          if (fill) b.fill(typeof fill === "number" ? fill : 0);
          return b;
        }
        static allocUnsafe(n) {
          return new _Buffer(n);
        }
        static isBuffer(x) {
          return x instanceof _Buffer;
        }
        static byteLength(s, enc) {
          return typeof s === "string" ? _Buffer.from(s, enc).length : s.byteLength;
        }
        static concat(list, total) {
          const n = total !== void 0 ? total : list.reduce((a, b) => a + b.length, 0);
          const o = new _Buffer(n);
          let off = 0;
          for (const b of list) {
            if (off >= n) break;
            o.set(b.subarray(0, n - off), off);
            off += b.length;
          }
          return o;
        }
        toString(enc, start, end) {
          const b = this.subarray(start || 0, end === void 0 ? this.length : end);
          const e = String(enc || "utf8").toLowerCase();
          if (e === "base64") return btoa(latin1(b));
          if (e === "latin1" || e === "binary" || e === "ascii") return latin1(b);
          if (e === "hex") {
            let s = "";
            for (const x of b) s += (x < 16 ? "0" : "") + x.toString(16);
            return s;
          }
          return td.decode(b);
        }
        toJSON() {
          return { type: "Buffer", data: Array.from(this) };
        }
        equals(o) {
          if (o.length !== this.length) return false;
          for (let i = 0; i < o.length; i++) if (o[i] !== this[i]) return false;
          return true;
        }
        slice(a, b) {
          return this.subarray(a, b);
        }
        readUInt8(o) {
          return this[o];
        }
        readUInt16LE(o) {
          return this[o] | this[o + 1] << 8;
        }
        readUInt32LE(o) {
          return (this[o] | this[o + 1] << 8 | this[o + 2] << 16) + this[o + 3] * 16777216;
        }
        readInt32LE(o) {
          return this[o] | this[o + 1] << 8 | this[o + 2] << 16 | this[o + 3] << 24;
        }
        readUInt16BE(o) {
          return this[o] << 8 | this[o + 1];
        }
        readUInt32BE(o) {
          return this[o] * 16777216 + (this[o + 1] << 16 | this[o + 2] << 8 | this[o + 3]);
        }
        writeUInt8(v, o) {
          this[o] = v & 255;
          return o + 1;
        }
        writeUInt16LE(v, o) {
          this[o] = v & 255;
          this[o + 1] = v >>> 8 & 255;
          return o + 2;
        }
        writeUInt32LE(v, o) {
          this[o] = v & 255;
          this[o + 1] = v >>> 8 & 255;
          this[o + 2] = v >>> 16 & 255;
          this[o + 3] = v >>> 24 & 255;
          return o + 4;
        }
        write(s, o = 0) {
          const b = _Buffer.from(s);
          this.set(b.subarray(0, this.length - o), o);
          return Math.min(b.length, this.length - o);
        }
      };
      module.exports = { Buffer: Buffer3 };
    }
  });

  // shims/fetch.js
  var require_fetch = __commonJS({
    "shims/fetch.js"(exports, module) {
      "use strict";
      init_globals();
      function fetchShim2(url, opts = {}) {
        return new Promise((ok, no) => {
          setTimeout(() => {
            try {
              const net = globalThis.AndroidNet;
              if (!net) return no(new TypeError("fetch failed"));
              const b = opts.body == null ? null : Buffer2.isBuffer(opts.body) || opts.body instanceof Uint8Array ? Buffer2.from(opts.body) : Buffer2.from(String(opts.body), "utf8");
              const r = JSON.parse(net.request(String(url), JSON.stringify({
                method: opts.method || "GET",
                headers: opts.headers || {},
                timeoutMs: b ? 12e4 : 2e4,
                ...b ? { b64: b.toString("base64") } : {}
              })));
              if (r.error) return no(new TypeError(r.error));
              const body = Buffer2.from(r.b64 || "", "base64");
              const headers = new Map(Object.entries(r.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
              ok({
                ok: r.status >= 200 && r.status < 300,
                status: r.status,
                headers: { get: (k) => headers.get(String(k).toLowerCase()) || null },
                arrayBuffer: async () => body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength),
                text: async () => body.toString("utf8"),
                json: async () => JSON.parse(body.toString("utf8"))
              });
            } catch (e) {
              no(new TypeError(String(e && e.message || e)));
            }
          }, 0);
        });
      }
      module.exports = { fetchShim: fetchShim2 };
    }
  });

  // shims/globals.js
  var import_buffer, import_fetch, Buffer2, process, __dirname;
  var init_globals = __esm({
    "shims/globals.js"() {
      import_buffer = __toESM(require_buffer());
      import_fetch = __toESM(require_fetch());
      Buffer2 = import_buffer.Buffer;
      process = {
        env: { DATA_DIR: globalThis.AndroidHost.dataDir() },
        pid: 1,
        platform: "android",
        argv: [],
        versions: {},
        cwd: () => "/",
        nextTick: (f, ...a) => Promise.resolve().then(() => f(...a))
      };
      __dirname = "/engine";
      globalThis.fetch = import_fetch.fetchShim;
    }
  });

  // shims/sqlite.js
  var require_sqlite = __commonJS({
    "shims/sqlite.js"(exports, module) {
      "use strict";
      init_globals();
      var ERRSTR = {
        1: "SQL logic error",
        5: "database is locked",
        6: "database table is locked",
        8: "attempt to write a readonly database",
        10: "disk I/O error",
        11: "database disk image is malformed",
        13: "database or disk is full",
        14: "unable to open database file",
        19: "constraint failed",
        20: "datatype mismatch",
        21: "bad parameter or other API misuse",
        26: "file is not a database"
      };
      var bridge = () => globalThis.AndroidSQL;
      function fail(r) {
        const e = new Error(r.error.message);
        e.code = "ERR_SQLITE_ERROR";
        e.errcode = r.error.errcode;
        e.errstr = ERRSTR[r.error.errcode & 255] || "unknown error";
        return e;
      }
      function reply(s) {
        const r = JSON.parse(s);
        if (r && r.error) throw fail(r);
        return r;
      }
      function split(sql) {
        const out = [];
        let cur = "";
        let i = 0;
        while (i < sql.length) {
          const c = sql[i];
          if (c === "'" || c === '"' || c === "`" || c === "[") {
            const end = c === "[" ? "]" : c;
            let j = i + 1;
            while (j < sql.length) {
              if (sql[j] === end) {
                if (end !== "]" && sql[j + 1] === end) {
                  j += 2;
                  continue;
                }
                break;
              }
              j++;
            }
            cur += sql.slice(i, j + 1);
            i = j + 1;
            continue;
          }
          if (c === "-" && sql[i + 1] === "-") {
            const j = sql.indexOf("\n", i);
            i = j < 0 ? sql.length : j + 1;
            cur += " ";
            continue;
          }
          if (c === "/" && sql[i + 1] === "*") {
            const j = sql.indexOf("*/", i + 2);
            i = j < 0 ? sql.length : j + 2;
            cur += " ";
            continue;
          }
          if (c === ";") {
            if (cur.trim()) out.push(cur.trim());
            cur = "";
            i++;
            continue;
          }
          cur += c;
          i++;
        }
        if (cur.trim()) out.push(cur.trim());
        return out;
      }
      function params(sql) {
        const names = /* @__PURE__ */ new Map();
        let next = 0;
        let max = 0;
        const anon = [];
        let out = "";
        let last = 0;
        let i = 0;
        while (i < sql.length) {
          const c = sql[i];
          if (c === "'" || c === '"' || c === "`") {
            let j = i + 1;
            while (j < sql.length && !(sql[j] === c && sql[j + 1] !== c)) j += sql[j] === c ? 2 : 1;
            i = j + 1;
            continue;
          }
          if (c === "-" && sql[i + 1] === "-") {
            const j = sql.indexOf("\n", i);
            i = j < 0 ? sql.length : j + 1;
            continue;
          }
          if (c === "/" && sql[i + 1] === "*") {
            const j = sql.indexOf("*/", i + 2);
            i = j < 0 ? sql.length : j + 2;
            continue;
          }
          if (c === "?") {
            let j = i + 1;
            while (j < sql.length && sql[j] >= "0" && sql[j] <= "9") j++;
            if (j > i + 1) {
              const n = Number(sql.slice(i + 1, j));
              max = Math.max(max, n);
              next = Math.max(next, n);
            } else {
              next = Math.max(next, max) + 1;
              max = next;
              anon.push(next);
            }
            i = j;
            continue;
          }
          if ((c === "@" || c === ":" || c === "$") && /[A-Za-z_]/.test(sql[i + 1] || "")) {
            let j = i + 1;
            while (j < sql.length && /\w/.test(sql[j])) j++;
            const nm = sql.slice(i + 1, j);
            if (!names.has(nm)) {
              next = Math.max(next, max) + 1;
              max = next;
              names.set(nm, next);
            }
            out += sql.slice(last, i) + "?" + names.get(nm);
            last = j;
            i = j;
            continue;
          }
          i++;
        }
        out += sql.slice(last);
        return { count: max, names, anon, sql: out };
      }
      function value(v, i) {
        if (v === null) return null;
        if (typeof v === "number") return Number.isFinite(v) ? v : (() => {
          throw bad(i);
        })();
        if (typeof v === "string") return v;
        if (typeof v === "bigint") return Number(v);
        if (v instanceof Uint8Array) return { $b64: Buffer2.from(v).toString("base64") };
        throw bad(i);
      }
      function bad(i) {
        const e = new TypeError(`Provided value cannot be bound to SQLite parameter ${i}.`);
        e.code = "ERR_INVALID_ARG_TYPE";
        return e;
      }
      function rowsOut(rows) {
        for (const r of rows) for (const k of Object.keys(r)) {
          const v = r[k];
          if (v && typeof v === "object" && v.$b64 !== void 0) r[k] = new Uint8Array(Buffer2.from(v.$b64, "base64"));
        }
        return rows;
      }
      var StatementSync = class {
        constructor(db2, sql) {
          this.db = db2;
          this.sql = sql;
          this.p = params(sql);
        }
        args(a) {
          const slots = new Array(this.p.count).fill(void 0);
          let named = null;
          let pos = a;
          if (a.length && a[0] && typeof a[0] === "object" && !Array.isArray(a[0]) && !(a[0] instanceof Uint8Array)) {
            named = a[0];
            pos = a.slice(1);
          }
          if (named) for (const [k2, v] of Object.entries(named)) {
            const key = k2.replace(/^[@:$]/, "");
            if (this.p.names.has(key)) slots[this.p.names.get(key) - 1] = v;
            else {
              const e = new Error(`Unknown named parameter '${k2}'`);
              e.code = "ERR_INVALID_STATE";
              throw e;
            }
          }
          let k = 0;
          for (let s = 0; s < slots.length && k < pos.length; s++) {
            if (named && [...this.p.names.values()].includes(s + 1)) continue;
            slots[s] = pos[k++];
          }
          return slots.map((v, i) => v === void 0 ? null : value(v, i + 1));
        }
        run(...a) {
          return reply(bridge().query(this.db.h, this.p.sql, JSON.stringify(this.args(a)), "run"));
        }
        get(...a) {
          const r = reply(bridge().query(this.db.h, this.p.sql, JSON.stringify(this.args(a)), "get"));
          return r.rows.length ? rowsOut(r.rows)[0] : void 0;
        }
        all(...a) {
          return rowsOut(reply(bridge().query(this.db.h, this.p.sql, JSON.stringify(this.args(a)), "all")).rows);
        }
      };
      var DatabaseSync = class {
        constructor(file, opts = {}) {
          this.h = reply(bridge().open(String(file), !!opts.readOnly)).handle;
        }
        exec(sql) {
          for (const s of split(sql)) reply(bridge().exec(this.h, s));
        }
        prepare(sql) {
          return new StatementSync(this, sql);
        }
        close() {
          reply(bridge().close(this.h));
        }
      };
      module.exports = { DatabaseSync, split, params };
    }
  });

  // ../../backend/src/sqlite.js
  var require_sqlite2 = __commonJS({
    "../../backend/src/sqlite.js"(exports, module) {
      init_globals();
      var { DatabaseSync } = require_sqlite();
      module.exports = class Database {
        constructor(file, opts = {}) {
          this.d = new DatabaseSync(file, { readOnly: !!opts.readonly });
          this.depth = 0;
        }
        pragma(s) {
          this.d.exec("PRAGMA " + s);
        }
        exec(s) {
          this.d.exec(s);
        }
        close() {
          this.d.close();
        }
        prepare(s) {
          const st = this.d.prepare(s);
          const used = new Set([...s.matchAll(/[@:$]([A-Za-z_]\w*)/g)].map((m) => m[1]));
          const norm = (a) => {
            if (a.length === 1 && a[0] && typeof a[0] === "object" && !Array.isArray(a[0]) && !Buffer2.isBuffer(a[0])) {
              return [Object.fromEntries(Object.entries(a[0]).filter(([k]) => used.has(k)))];
            }
            return a;
          };
          return { run: (...a) => st.run(...norm(a)), get: (...a) => st.get(...norm(a)), all: (...a) => st.all(...norm(a)) };
        }
        transaction(fn) {
          return (...a) => {
            const nested = this.depth > 0, sp = "sp" + this.depth;
            this.d.exec(nested ? `SAVEPOINT ${sp}` : "BEGIN");
            this.depth++;
            try {
              const r = fn(...a);
              this.depth--;
              this.d.exec(nested ? `RELEASE ${sp}` : "COMMIT");
              return r;
            } catch (e) {
              this.depth--;
              this.d.exec(nested ? `ROLLBACK TO ${sp}; RELEASE ${sp}` : "ROLLBACK");
              throw e;
            }
          };
        }
      };
    }
  });

  // shims/async_hooks.js
  var require_async_hooks = __commonJS({
    "shims/async_hooks.js"(exports, module) {
      "use strict";
      init_globals();
      var AsyncLocalStorage = class {
        constructor() {
          this.stack = [];
        }
        run(store, fn, ...a) {
          this.stack.push(store);
          try {
            return fn(...a);
          } finally {
            this.stack.pop();
          }
        }
        getStore() {
          return this.stack.length ? this.stack[this.stack.length - 1] : globalThis.__bbStore;
        }
      };
      module.exports = { AsyncLocalStorage };
    }
  });

  // shims/path.js
  var require_path = __commonJS({
    "shims/path.js"(exports, module) {
      "use strict";
      init_globals();
      function normalize(p) {
        const abs = p.startsWith("/");
        const out = [];
        for (const s of p.split("/")) {
          if (!s || s === ".") continue;
          if (s === "..") {
            if (out.length && out[out.length - 1] !== "..") out.pop();
            else if (!abs) out.push("..");
          } else out.push(s);
        }
        const r = (abs ? "/" : "") + out.join("/");
        return r || (abs ? "/" : ".");
      }
      var join = (...a) => normalize(a.filter((x) => x !== "").join("/"));
      var basename = (p, ext) => {
        const s = String(p).replace(/\/+$/, "");
        let b = s.slice(s.lastIndexOf("/") + 1);
        if (ext && b.endsWith(ext)) b = b.slice(0, -ext.length);
        return b;
      };
      var dirname = (p) => {
        const s = String(p).replace(/\/+$/, "");
        const i = s.lastIndexOf("/");
        return i < 0 ? "." : i === 0 ? "/" : s.slice(0, i);
      };
      var extname = (p) => {
        const b = basename(p);
        const i = b.lastIndexOf(".");
        return i <= 0 ? "" : b.slice(i);
      };
      var isAbsolute = (p) => String(p).startsWith("/");
      var resolve = (...a) => {
        let r = "";
        for (const p of a) r = isAbsolute(p) ? p : r + "/" + p;
        return normalize(isAbsolute(r) ? r : "/" + r);
      };
      module.exports = { join, basename, dirname, extname, isAbsolute, resolve, normalize, sep: "/", delimiter: ":", posix: null };
      module.exports.posix = module.exports;
    }
  });

  // shims/fs.js
  var require_fs = __commonJS({
    "shims/fs.js"(exports, module) {
      "use strict";
      init_globals();
      var host = () => globalThis.AndroidFS;
      function call(name, ...a) {
        const r = JSON.parse(host()[name](...a.map((x) => typeof x === "string" ? x : JSON.stringify(x))));
        if (r && r.error) {
          const e = new Error(`${r.error.code}: ${r.error.message}, ${name} '${a[0]}'`);
          e.code = r.error.code;
          e.path = a[0];
          throw e;
        }
        return r ? r.ok : void 0;
      }
      var stats = (s) => ({ size: s.size, mtimeMs: s.mtime, mtime: new Date(s.mtime), birthtime: new Date(s.mtime), isDirectory: () => s.dir, isFile: () => !s.dir });
      module.exports = {
        existsSync: (p) => !!call("exists", String(p)),
        statSync: (p, o) => {
          try {
            return stats(call("stat", String(p)));
          } catch (e) {
            if (o && o.throwIfNoEntry === false && e.code === "ENOENT") return void 0;
            throw e;
          }
        },
        lstatSync: (p) => stats(call("stat", String(p))),
        readFileSync: (p, o) => {
          const b = Buffer2.from(call("read", String(p)), "base64");
          const enc = typeof o === "string" ? o : o && o.encoding;
          return enc ? b.toString(enc) : b;
        },
        writeFileSync: (p, data) => call("write", String(p), (typeof data === "string" ? Buffer2.from(data) : Buffer2.from(data)).toString("base64")),
        mkdirSync: (p, o) => call("mkdir", String(p), !!(o && o.recursive)),
        readdirSync: (p, o) => {
          const names = call("readdir", String(p));
          if (!(o && o.withFileTypes)) return names;
          return names.map((name) => {
            const s = call("stat", String(p).replace(/\/+$/, "") + "/" + name);
            return { name, isDirectory: () => s.dir, isFile: () => !s.dir };
          });
        },
        rmSync: (p, o) => call("rm", String(p), !!(o && o.recursive), !!(o && o.force)),
        unlinkSync: (p) => call("rm", String(p), false, false),
        renameSync: (a, b) => call("rename", String(a), String(b)),
        copyFileSync: (a, b) => call("copy", String(a), String(b)),
        mkdtempSync: (prefix) => call("mkdtemp", String(prefix))
      };
    }
  });

  // ../../backend/src/schema.js
  var require_schema = __commonJS({
    "../../backend/src/schema.js"(exports, module) {
      init_globals();
      var BASE = `
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS counters (key TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0);

CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS items (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  category_id INTEGER REFERENCES categories(id),
  hsn TEXT,
  gst_rate REAL NOT NULL DEFAULT 18,
  unit TEXT DEFAULT 'PCS',
  mrp REAL NOT NULL DEFAULT 0,              -- GST-inclusive, printed on pack
  retail_price REAL NOT NULL DEFAULT 0,     -- ex-GST selling rate
  wholesale_price REAL NOT NULL DEFAULT 0,  -- ex-GST selling rate
  purchase_price REAL NOT NULL DEFAULT 0,   -- ex-GST landing cost
  pcs_per_box INTEGER NOT NULL DEFAULT 1,   -- dual-unit billing: pieces in one box
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS batches (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_no TEXT NOT NULL,
  mfg_date TEXT,
  exp_date TEXT NOT NULL,
  qty INTEGER NOT NULL DEFAULT 0,
  purchase_price REAL,
  mrp REAL,
  UNIQUE(item_id, batch_no)
);
CREATE INDEX IF NOT EXISTS idx_batches_fefo ON batches(item_id, exp_date);

CREATE TABLE IF NOT EXISTS schemes (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items(id),
  type TEXT NOT NULL CHECK (type IN ('FREE_QTY','PERCENT')),
  buy_qty INTEGER NOT NULL,        -- FREE_QTY: buy X ; PERCENT: minimum qty
  free_qty INTEGER DEFAULT 0,      -- FREE_QTY: get Y free
  percent REAL DEFAULT 0,          -- PERCENT: discount %
  valid_from TEXT, valid_to TEXT,
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS salesmen (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, phone TEXT,
  monthly_target REAL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS routes (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL,
  salesman_id INTEGER REFERENCES salesmen(id),
  day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6)  -- 0 = Sunday
);

CREATE TABLE IF NOT EXISTS parties (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL, gstin TEXT, state_code TEXT, phone TEXT, address TEXT,
  type TEXT NOT NULL DEFAULT 'RETAILER',
  price_tier TEXT NOT NULL DEFAULT 'RETAIL' CHECK (price_tier IN ('WHOLESALE','RETAIL','MRP')),
  credit_limit REAL NOT NULL DEFAULT 0,
  credit_days INTEGER NOT NULL DEFAULT 0,
  route_id INTEGER REFERENCES routes(id),
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS invoices (
  id INTEGER PRIMARY KEY,
  invoice_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER REFERENCES parties(id),
  salesman_id INTEGER REFERENCES salesmen(id),
  sale_type TEXT NOT NULL DEFAULT 'COUNTER',
  pay_mode TEXT NOT NULL DEFAULT 'CASH',
  subtotal REAL, discount REAL, taxable REAL,
  cgst REAL, sgst REAL, igst REAL, round_off REAL,
  total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_inv_date ON invoices(date);
CREATE INDEX IF NOT EXISTS idx_inv_sm ON invoices(salesman_id, date);

CREATE TABLE IF NOT EXISTS invoice_lines (
  id INTEGER PRIMARY KEY,
  invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  qty INTEGER NOT NULL, free_qty INTEGER NOT NULL DEFAULT 0,
  rate REAL NOT NULL, disc_pct REAL NOT NULL DEFAULT 0, disc_amt REAL NOT NULL DEFAULT 0,
  taxable REAL NOT NULL, gst_rate REAL NOT NULL,
  cgst REAL NOT NULL, sgst REAL NOT NULL, igst REAL NOT NULL, amount REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS receipts (
  id INTEGER PRIMARY KEY,
  receipt_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  salesman_id INTEGER REFERENCES salesmen(id),
  invoice_id INTEGER REFERENCES invoices(id),
  mode TEXT NOT NULL DEFAULT 'CASH',
  amount REAL NOT NULL, reference TEXT
);

-- Party ledger: balance = SUM(debit) - SUM(credit)  (positive = party owes us)
CREATE TABLE IF NOT EXISTS ledger (
  id INTEGER PRIMARY KEY,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  date TEXT NOT NULL,
  type TEXT NOT NULL,   -- OPENING | INVOICE | RECEIPT
  ref_no TEXT, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, narration TEXT
);
CREATE INDEX IF NOT EXISTS idx_ledger_party ON ledger(party_id, date);
`;
      var V2 = `
CREATE TABLE IF NOT EXISTS purchases (
  id INTEGER PRIMARY KEY,
  purchase_no TEXT UNIQUE NOT NULL,
  supplier_invoice_no TEXT,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  subtotal REAL, discount REAL, taxable REAL, cgst REAL, sgst REAL, igst REAL, round_off REAL,
  total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0, pay_mode TEXT, notes TEXT,
  source TEXT NOT NULL DEFAULT 'MANUAL',
  created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_pur_date ON purchases(date);
CREATE INDEX IF NOT EXISTS idx_pur_party ON purchases(party_id, supplier_invoice_no);

CREATE TABLE IF NOT EXISTS purchase_lines (
  id INTEGER PRIMARY KEY,
  purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER REFERENCES batches(id),
  batch_no TEXT NOT NULL, mfg_date TEXT, exp_date TEXT NOT NULL,
  qty INTEGER NOT NULL, free_qty INTEGER NOT NULL DEFAULT 0,
  rate REAL NOT NULL, disc_pct REAL NOT NULL DEFAULT 0, disc_amt REAL NOT NULL DEFAULT 0, mrp REAL,
  taxable REAL NOT NULL, gst_rate REAL NOT NULL,
  cgst REAL NOT NULL, sgst REAL NOT NULL, igst REAL NOT NULL, amount REAL NOT NULL
);

-- Money paid OUT to a party (supplier payments). Money received lives in receipts.
CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY,
  voucher_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  purchase_id INTEGER REFERENCES purchases(id),
  mode TEXT NOT NULL DEFAULT 'CASH',
  amount REAL NOT NULL, reference TEXT
);
CREATE INDEX IF NOT EXISTS idx_inv_party ON invoices(party_id);
CREATE INDEX IF NOT EXISTS idx_invl_inv ON invoice_lines(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invl_item ON invoice_lines(item_id);
CREATE INDEX IF NOT EXISTS idx_purl_pur ON purchase_lines(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purl_item ON purchase_lines(item_id);
CREATE INDEX IF NOT EXISTS idx_batches_item ON batches(item_id);
CREATE INDEX IF NOT EXISTS idx_receipts_inv ON receipts(invoice_id);
CREATE INDEX IF NOT EXISTS idx_receipts_date ON receipts(date);
CREATE INDEX IF NOT EXISTS idx_parties_name ON parties(name);
CREATE INDEX IF NOT EXISTS idx_items_name ON items(name);
`;
      function migrateItems(db2) {
        const cols = db2.prepare("PRAGMA table_info(items)").all().map((c) => c.name);
        if (!["sku", "barcode", "reorder_level"].some((c) => cols.includes(c))) return false;
        const ppb = cols.includes("pcs_per_box") ? "pcs_per_box" : "1";
        db2.pragma("foreign_keys = OFF");
        try {
          db2.exec("BEGIN");
          db2.exec(`CREATE TABLE items_new (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, category_id INTEGER REFERENCES categories(id), hsn TEXT,
      gst_rate REAL NOT NULL DEFAULT 18, unit TEXT DEFAULT 'PCS', mrp REAL NOT NULL DEFAULT 0,
      retail_price REAL NOT NULL DEFAULT 0, wholesale_price REAL NOT NULL DEFAULT 0, purchase_price REAL NOT NULL DEFAULT 0,
      pcs_per_box INTEGER NOT NULL DEFAULT 1, active INTEGER NOT NULL DEFAULT 1)`);
          db2.exec(`INSERT INTO items_new(id,name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box,active)
             SELECT id,name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,${ppb},active FROM items`);
          db2.exec("DROP TABLE items");
          db2.exec("ALTER TABLE items_new RENAME TO items");
          const bad = db2.prepare("PRAGMA foreign_key_check").all();
          if (bad.length) throw new Error("Item migration would break references; nothing was changed.");
          db2.exec("COMMIT");
        } catch (e) {
          try {
            db2.exec("ROLLBACK");
          } catch {
          }
          throw e;
        } finally {
          db2.pragma("foreign_keys = ON");
        }
        return true;
      }
      function addColumn(db2, table, col, def) {
        const cols = db2.prepare(`PRAGMA table_info(${table})`).all();
        if (!cols.some((c) => c.name === col)) db2.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${def}`);
      }
      var DEFAULT_SETTINGS = {
        company_name: "My Company",
        company_gstin: "",
        state_code: "09",
        company_address: "",
        company_phone: "",
        invoice_terms: "Goods once sold will not be taken back.",
        print_layout: "halfSheets",
        // halfSheets | a4TwoUp | single | a4Full | a4FullOriginal
        print_printer: "",
        print_auto: "0",
        low_stock_qty: "10"
        // alert when stock of a stocked item is at or below this many pieces
      };
      function applySchema(db2, settings2 = {}) {
        db2.pragma("journal_mode = WAL");
        db2.pragma("foreign_keys = ON");
        db2.pragma("synchronous = NORMAL");
        db2.exec(BASE);
        migrateItems(db2);
        db2.exec(V2);
        addColumn(db2, "routes", "days", "TEXT");
        db2.exec("UPDATE routes SET days=CAST(day_of_week AS TEXT) WHERE days IS NULL AND day_of_week IS NOT NULL");
        addColumn(db2, "items", "pcs_per_box", "INTEGER NOT NULL DEFAULT 1");
        for (const c of ["tel", "mobiles", "fssai", "pan", "email"]) addColumn(db2, "parties", c, "TEXT");
        addColumn(db2, "purchase_lines", "unit", "TEXT DEFAULT 'PCS'");
        addColumn(db2, "purchase_lines", "pcs_qty", "INTEGER");
        addColumn(db2, "invoice_lines", "manual_disc", "REAL NOT NULL DEFAULT 0");
        addColumn(db2, "invoices", "printed", "INTEGER NOT NULL DEFAULT 0");
        for (const c of ["ewb_no", "ewb_date", "ewb_valid", "ewb_transport"]) addColumn(db2, "invoices", c, "TEXT");
        db2.exec(V7);
        const ins = db2.prepare("INSERT OR IGNORE INTO settings(key,value) VALUES(?,?)");
        const up = db2.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value");
        for (const [k, v] of Object.entries(DEFAULT_SETTINGS)) ins.run(k, v);
        for (const [k, v] of Object.entries(settings2)) up.run(k, String(v));
      }
      var V7 = `
CREATE TABLE IF NOT EXISTS debit_notes (
  id INTEGER PRIMARY KEY,
  note_no TEXT UNIQUE NOT NULL,
  date TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  purchase_id INTEGER REFERENCES purchases(id),
  against_bill TEXT, reason TEXT,
  subtotal REAL, discount REAL, taxable REAL, cgst REAL, sgst REAL, igst REAL, round_off REAL,
  total REAL NOT NULL, notes TEXT,
  source TEXT NOT NULL DEFAULT 'MANUAL',
  created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_dn_date ON debit_notes(date);
CREATE INDEX IF NOT EXISTS idx_dn_party ON debit_notes(party_id);
CREATE TABLE IF NOT EXISTS debit_note_lines (
  id INTEGER PRIMARY KEY,
  note_id INTEGER NOT NULL REFERENCES debit_notes(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER REFERENCES batches(id),
  qty INTEGER NOT NULL, unit TEXT NOT NULL DEFAULT 'PCS', pcs_qty INTEGER NOT NULL,
  rate REAL NOT NULL, amount REAL NOT NULL, taxable REAL NOT NULL, gst_rate REAL NOT NULL,
  cgst REAL NOT NULL DEFAULT 0, sgst REAL NOT NULL DEFAULT 0, igst REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_dnl_note ON debit_note_lines(note_id);
CREATE INDEX IF NOT EXISTS idx_dnl_item ON debit_note_lines(item_id);
CREATE TABLE IF NOT EXISTS debit_note_stock (
  id INTEGER PRIMARY KEY,
  line_id INTEGER NOT NULL REFERENCES debit_note_lines(id) ON DELETE CASCADE,
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  qty INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dns_line ON debit_note_stock(line_id);
`;
      module.exports = { applySchema, migrateItems, DEFAULT_SETTINGS };
    }
  });

  // ../../backend/src/services/pdfParser.js
  var require_pdfParser = __commonJS({
    "../../backend/src/services/pdfParser.js"(exports, module) {
      init_globals();
      var GSTIN_RE = /\b\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b/g;
      var MONTHS = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
      var GST_RATES = [0, 3, 5, 12, 18, 28];
      var pad = (n) => String(n).padStart(2, "0");
      var toNum = (s) => Number(String(s).replace(/[,\s]/g, ""));
      var r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
      var norm = (s) => String(s || "").toLowerCase().replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
      var cleanLines = (t) => String(t || "").split(/\r?\n/).map((l) => l.replace(/[\u00a0\t]+/g, " ").replace(/\s+/g, " ").replace(/(\d)\s+%/g, "$1%").trim()).filter(Boolean);
      var KIND_RES = [
        ["original", /\boriginal\b(?!\s+(?:invoice\s+)?(?:no|number|date|ref))/i],
        ["duplicate", /\bduplicate\b/i],
        ["triplicate", /\btriplicate\b/i],
        ["other", /\b(?:extra|office|transporter|customer|driver|accounts?)\s+copy\b/i]
      ];
      function copyKind(pageText) {
        const lines = cleanLines(pageText);
        const zone = [...lines.slice(0, 14), ...lines.slice(-10)].join("\n");
        const found = KIND_RES.filter(([, re]) => re.test(zone)).map(([k]) => k);
        if (found.length === 0) return null;
        if (found.length > 1) return "multi";
        return found[0];
      }
      var fingerprint = (pageText) => new Set(cleanLines(pageText).filter((l) => /\d/.test(l)).map(norm));
      function jaccard(a, b) {
        if (!a.size || !b.size) return 0;
        let hit = 0;
        for (const x of a) if (b.has(x)) hit++;
        return hit / (a.size + b.size - hit);
      }
      function selectOriginalPages(pages) {
        const kinds = pages.map(copyKind);
        const definite = kinds.filter((k) => k && k !== "multi");
        const skipped = [];
        let keep;
        let note = "";
        if (!definite.length) {
          keep = pages.map((_, i) => i);
          if (pages.length > 1) note = "No copy labels (Original / Duplicate) found; all pages were read and repeated pages dropped.";
        } else {
          let cur = null;
          keep = [];
          kinds.forEach((k, i) => {
            if (k && k !== "multi") cur = k;
            const effective = cur || "original";
            if (effective === "original") keep.push(i);
            else skipped.push({ page: i + 1, kind: cur });
          });
          if (!keep.length) {
            keep = pages.map((_, i) => i);
            skipped.length = 0;
            note = 'No "Original" copy found on any page; all pages were read.';
          }
        }
        const seen = [];
        keep = keep.filter((i) => {
          const fp = fingerprint(pages[i]);
          if (fp.size >= 5 && seen.some((s) => jaccard(s, fp) >= 0.85)) {
            skipped.push({ page: i + 1, kind: "repeat" });
            return false;
          }
          seen.push(fp);
          return true;
        });
        return { used: keep.map((i) => i + 1), skipped, note, pages: keep.map((i) => pages[i]) };
      }
      var TOTAL_MARK = /(^\W*(?:less|add)\s*:|sub\s*-?\s*total|total\s*(amount|taxable|qty|quantity)|grand\s*total|amount\s*(chargeable\s*)?in\s*words|bank\s*details|terms\s*&?\s*conditions|taxable\s*value|total\s*invoice)/i;
      var CONT_MARK = /(^|\s)(continued|contd\.?|c\/f|b\/f|c\/o|b\/d|carried\s*forward|brought\s*forward|page\s*total|please\s*turn\s*over)(?=\s|$|\.)/i;
      var CARRY_LINE = /^\W*(?:sub\s*)?(?:totals?\s*)?(?:b\/d|b\/f|c\/o|c\/f|brought\s*forward|carried\s*(?:forward|over)|page\s*total)\b/i;
      var PAGE_NO = /^\W*(?:page\s*)?\d+\s*(?:of|\/)\s*\d+\W*$/i;
      var COPY_LABEL = /^\W*(?:original|duplicate|triplicate)(?:\s+(?:copy|for\s+[\w\/ ]+))?\W*$/i;
      function mergePages(pageTexts) {
        const out = [];
        let headerSet = null;
        pageTexts.forEach((t, p) => {
          let lines = cleanLines(t);
          const hdr = lines.findIndex((l) => detectColumns(l));
          if (p === 0) {
            headerSet = new Set(lines.slice(0, hdr >= 0 ? hdr + 1 : 8).map(norm));
          } else {
            lines = lines.filter((l) => {
              const n = norm(l);
              return !(headerSet.has(n) || CARRY_LINE.test(l) || /^\W*code\W*$/i.test(l) || PAGE_NO.test(l) || COPY_LABEL.test(l) || detectColumns(l) || CONT_MARK.test(l) && !/\d{3,}/.test(l.replace(CONT_MARK, "")));
            });
          }
          out.push({ page: p, lines, hdr: p === 0 ? hdr : -1 });
        });
        return out;
      }
      var COLS = [
        ["sno", /(?:^|\s)(?:s\.?\s?no\.?|sl\.?\s?no\.?|sr\.?\s?no\.?|sl|sr|s\.n\.?|no\.?|#)(?=\s|$)/i],
        ["desc", /(?:description(?:\s+of\s+(?:goods|items?))?|particulars|item(?:\s+name)?|product(?:\s+name)?|goods)/i],
        ["hsn", /\b(?:hsn|sac)(?:\s*\/\s*(?:hsn|sac))?(?:\s*code)?\b/i],
        ["qty", /\b(?:qty|quantity|nos)\b\.?/i],
        ["unit", /\b(?:unit|uom|per)\b/i],
        ["mrp", /\bmrp\b/i],
        ["rate", /\b(?:rate|price)\b/i],
        ["disc", /\bdisc(?:ount)?\b/i],
        ["tax", /\b(?:gst|cgst|sgst|igst|tax)\b/i],
        ["amount", /\b(?:amount|amt|value|total)\b/i]
      ];
      function detectColumns(line) {
        const hits = [];
        for (const [k, re] of COLS) {
          const m = re.exec(line);
          if (m) hits.push([m.index, k]);
        }
        const keys = hits.map((h) => h[1]);
        if (!keys.includes("desc") || !keys.includes("qty") || !(keys.includes("amount") || keys.includes("rate"))) return null;
        return hits.sort((a, b) => a[0] - b[0]).map((h) => h[1]);
      }
      var KIND_OK = {
        hsn: /^\d{4,8}$/,
        qty: /^\d[\d,]*(\.\d+)?$/,
        unit: /^[A-Za-z]{1,8}\.?$/,
        mrp: /^\d[\d,]*(\.\d+)?$/,
        rate: /^\d[\d,]*(\.\d+)?$/,
        amount: /^\d[\d,]*(\.\d+)?$/,
        disc: /^-?\d[\d,]*(\.\d+)?%?$/,
        tax: /^-?\d+(\.\d+)?%?$/,
        sno: /^\d{1,3}\.?$/
      };
      var UNITS = /* @__PURE__ */ new Set(["PCS", "PC", "NOS", "NO", "BOX", "BOXES", "CASE", "CS", "CTN", "KG", "KGS", "GM", "GMS", "LTR", "LT", "L", "ML", "PKT", "PKTS", "PACK", "DOZ", "SET", "BAG", "BTL", "JAR", "BDL", "MTR"]);
      var plausible = (q, r, a, floor = 0.4) => {
        if (!(q > 0 && a > 0)) return false;
        if (!(r > 0)) return true;
        const g = q * r;
        return Math.abs(g - a) <= Math.max(0.6, g * 0.01) || a < g * 0.995 && a >= g * floor || GST_RATES.some((x) => x > 0 && Math.abs(g * (1 + x / 100) - a) <= Math.max(0.6, a * 0.01));
      };
      function rowFromColumns(line, cols) {
        let toks = line.split(" ");
        const hasUnit = cols.includes("unit");
        if (hasUnit) toks = toks.flatMap((t, ti) => {
          if (ti < toks.length - (cols.length - cols.indexOf("desc") - 1)) return [t];
          const m = /^(\d+(?:\.\d+)?)([A-Za-z]{2,5})\.?$/.exec(t);
          return m && UNITS.has(m[2].toUpperCase()) ? [m[1], m[2]] : [t];
        });
        else toks = toks.filter((t, ti) => !(ti > 0 && UNITS.has(t.replace(/\.$/, "").toUpperCase()) && /^\d+(\.\d+)?$/.test(toks[ti - 1])));
        let k = cols.indexOf("desc");
        const left = cols.slice(0, k).filter((c) => c !== "sno"), hasSno = cols.slice(0, k).includes("sno");
        const right = cols.slice(k + 1);
        if (hasSno && KIND_OK.sno.test(toks[0] || "")) toks = toks.slice(1);
        const variants = [right, right.filter((c) => c !== "disc"), right.filter((c) => c !== "disc" && c !== "tax"), right.filter((c) => !["disc", "tax", "mrp"].includes(c))];
        for (const rc of [...new Set(variants.map((v) => v.join("|")))].map((s) => s ? s.split("|") : [])) {
          const need = left.length + rc.length;
          if (toks.length < need + 1) continue;
          const lt = toks.slice(0, left.length), rt = toks.slice(toks.length - rc.length), name = toks.slice(left.length, toks.length - rc.length);
          const ok = (arr, kinds) => kinds.every((kk, i) => !KIND_OK[kk] || KIND_OK[kk].test(arr[i]));
          if (!ok(lt, left) || !ok(rt, rc)) continue;
          const get = (kind, arr, kinds) => {
            const i = kinds.indexOf(kind);
            return i >= 0 ? arr[i] : void 0;
          };
          const qty = toNum(get("qty", rt, rc) ?? get("qty", lt, left)), rate = toNum(get("rate", rt, rc) ?? 0), amount = toNum(get("amount", rt, rc) ?? 0);
          const unitTok = get("unit", rt, rc) ?? get("unit", lt, left);
          if (!(qty > 0) || !plausible(qty, rate, amount || qty * rate, 0.1)) continue;
          const desc = name.join(" ").replace(/[|:;,]+$/, "").trim();
          if (!/[A-Za-z]{2}/.test(desc)) continue;
          const hsn = get("hsn", rt, rc) ?? get("hsn", lt, left);
          const taxTok = get("tax", rt, rc);
          const mrpTok = get("mrp", rt, rc);
          return { mrp_col: mrpTok ? toNum(mrpTok) : null, description: desc, hsn: hsn || null, qty, unit: unitTok ? unitTok.replace(/\.$/, "").toUpperCase() : null, rate, amount: amount || r2(qty * rate), tax_hint: taxTok ? toNum(String(taxTok).replace("%", "")) : null };
        }
        return null;
      }
      function rowByNumbers(line) {
        const parts = line.split(" ");
        const nums = [];
        parts.forEach((p, idx) => {
          if (/^-?\d[\d,]*(\.\d+)?%?$/.test(p)) nums.push({ idx, v: toNum(p.replace("%", "")), raw: p });
        });
        if (nums.length < 3) return null;
        let first = 0;
        if (nums[0].idx === 0 && Number.isInteger(nums[0].v) && nums[0].v < 1e3) first = 1;
        const hsnTok = nums.find((n, i) => i >= first && /^\d{4,8}$/.test(n.raw));
        const pool = nums.filter((n, i) => i >= first && n !== hsnTok);
        let best = null;
        for (let i = 0; i < pool.length; i++) for (let j = i + 1; j < pool.length; j++) for (let k = j + 1; k < pool.length; k++) {
          const q = pool[i].v, r = pool[j].v, a = pool[k].v;
          if (!(Number.isInteger(q) && q > 0 && q < 1e5 && r > 0 && a > 0)) continue;
          const g = q * r;
          const kind = Math.abs(g - a) <= Math.max(0.6, g * 5e-3) ? 0 : a < g * 0.995 && a >= g * 0.5 ? 2 : -1;
          if (kind < 0) continue;
          if (!best || kind < best.kind || kind === best.kind && k > best.k) best = { i, j, k, kind, q, r, a };
        }
        if (!best) return null;
        const qt = pool[best.i], rt = pool[best.j];
        const nameEnd = Math.min(qt.idx, hsnTok ? hsnTok.idx : 1e9, rt.idx);
        const desc = parts.slice(first ? 1 : 0, nameEnd).join(" ").replace(/[|:;,]+$/, "").trim();
        if (!/[A-Za-z]{2}/.test(desc)) return null;
        const after = parts[qt.idx + 1];
        const unit = after && /^[A-Za-z]{2,6}\.?$/.test(after) && UNITS.has(after.replace(/\.$/, "").toUpperCase()) ? after.replace(/\.$/, "").toUpperCase() : null;
        return { description: desc, hsn: hsnTok ? hsnTok.raw : null, qty: best.q, unit, rate: best.r, amount: best.a, tax_hint: null };
      }
      var NOISE = /* @__PURE__ */ new Set(["pkt", "pkts", "pcs", "pc", "mrp", "rs", "new", "pvt", "ltd", "private", "limited", "co", "the", "and", "ms"]);
      var soft = (t) => /^[a-z]+$/.test(t) ? t.replace(/([bdgjkpt])h/g, "$1").replace(/iya$/, "ia").replace(/ee/g, "i").replace(/oo/g, "u").replace(/(.)\1+/g, "$1") : t;
      var sizes = (s) => String(s || "").replace(/(\d+(?:\.\d+)?)\s*(?:grams|gram|gms|grm|gm|g)\b/gi, "$1g").replace(/(\d+(?:\.\d+)?)\s*(?:kgs|kg)\b/gi, "$1kg").replace(/(\d+(?:\.\d+)?)\s*(?:mls|ml)\b/gi, "$1ml");
      var weightOf = (s) => {
        const m = /(?:^| )(\d+(?:\.\d+)?(?:g|kg|ml))(?= |$)/.exec(norm(sizes(s)));
        return m ? m[1] : null;
      };
      var wordsOf = (s) => [...new Set(norm(sizes(s)).split(" ").filter((t) => t.length > 1 && !NOISE.has(t)).map(soft))];
      function oneEdit(a, b) {
        if (Math.abs(a.length - b.length) > 1) return false;
        let i = 0, j = 0, d = 0;
        while (i < a.length && j < b.length) {
          if (a[i] === b[j]) {
            i++;
            j++;
            continue;
          }
          if (++d > 1) return false;
          if (a.length > b.length) i++;
          else if (b.length > a.length) j++;
          else {
            i++;
            j++;
          }
        }
        return d + (a.length - i) + (b.length - j) <= 1;
      }
      function wordMatch(a, b) {
        if (a === b) return 1;
        const alpha = /^[a-z]+$/.test(a) && /^[a-z]+$/.test(b);
        if (!alpha) return 0;
        if (Math.min(a.length, b.length) >= 4 && (a.startsWith(b) || b.startsWith(a))) return 0.9;
        if (Math.min(a.length, b.length) >= 5 && oneEdit(a, b)) return 0.85;
        return 0;
      }
      var similarity = (a, b) => {
        const A = wordsOf(a), B3 = wordsOf(b);
        if (!A.length || !B3.length) return 0;
        let hit = 0;
        for (const t of A) {
          let m = 0;
          for (const u of B3) {
            const v = wordMatch(t, u);
            if (v > m) m = v;
          }
          hit += m;
        }
        return hit / Math.max(A.length, B3.length);
      };
      function bestMatch(text, list, hsn) {
        let best = null, score = 0;
        const want = sizeTokens(text);
        for (const x of list) {
          const have = sizeTokens(x.name);
          if (want.pack && have.pack && want.pack !== have.pack || want.mrp && have.mrp && want.mrp !== have.mrp) continue;
          const wa = weightOf(text), wb = weightOf(x.name);
          if (wa && wb && wa !== wb) continue;
          let s = similarity(text, x.name);
          if (hsn && x.hsn && String(x.hsn) === String(hsn)) s += 0.25;
          if (s > score) {
            score = s;
            best = x;
          }
        }
        return score >= 0.5 ? { match: best, score: Math.min(1, score) } : { match: null, score };
      }
      function packFromName(name) {
        const m = /\(\s*(?:(\d+)\s*[xX*]\s*)?(\d{1,5})\s*(?:PKTS?|PCS?|NOS|PACKS?|UNITS?)?\s*\)/i.exec(name);
        if (!m) {
          const m2 = /\b\d+\s*[xX]\s*(\d{2,5})\b(?!\s*(?:ml|g|gm|kg|ltr|l)\b)/i.exec(name);
          return m2 ? Number(m2[1]) : null;
        }
        return Number(m[2]) >= 1 ? Number(m[2]) : null;
      }
      function mrpFromName(name) {
        const s = String(name || "");
        const forms = [
          /\bM\.?\s*R\.?\s*P\.?\s*[-:.=]?\s*(?:RS\.?|INR|₹)?\s*(\d+(?:\.\d+)?)/i,
          /(?:\bRS\.?|\bINR|₹)\s*(\d+(?:\.\d+)?)/i,
          /(?:^|[\s(])(\d+(?:\.\d+)?)\s*\/\s*-/,
          /@\s*(\d+(?:\.\d+)?)\b(?!\s*(?:g|gm|kg|ml|l)\b)/i
        ];
        for (const re of forms) {
          const m = re.exec(s);
          if (m && Number(m[1]) > 0 && Number(m[1]) < 1e5) return Number(m[1]);
        }
        return null;
      }
      var HSN_RATE = [
        ["2106", 12],
        ["2105", 18],
        ["1905", 18],
        ["1704", 18],
        ["1806", 18],
        ["1902", 12],
        ["1904", 18],
        ["2008", 12],
        ["2009", 12],
        ["2202", 28],
        ["2201", 18],
        ["0902", 5],
        ["1006", 5],
        ["1101", 0],
        ["1512", 5],
        ["1701", 5],
        ["0713", 0],
        ["3401", 18],
        ["3402", 18],
        ["3305", 18],
        ["3306", 18],
        ["3307", 18],
        ["2501", 0]
      ];
      var rateFromHsn = (hsn) => {
        const h = String(hsn || "");
        const e = HSN_RATE.find(([p]) => h.startsWith(p));
        return e ? e[1] : null;
      };
      function enrichLine(r, billRate) {
        r.pcs_per_box = packFromName(r.description);
        r.mrp = (r.mrp_col > 0 ? r.mrp_col : null) || mrpFromName(r.description);
        delete r.mrp_col;
        r.gst_rate = billRate !== null && billRate !== void 0 ? billRate : rateFromHsn(r.hsn);
        r.gst_source = billRate !== null && billRate !== void 0 ? "bill" : r.gst_rate !== null ? "hsn" : null;
        return r;
      }
      var sizeTokens = (s) => ({ mrp: mrpFromName(s), pack: packFromName(s) });
      var PCT_FRAG = /\(\s*-?\d+(?:\.\d+)?\s*%[^)]*\)/g;
      function parseItems(merged, items, warnings) {
        let cols = null;
        for (const m of merged) {
          const c = m.hdr >= 0 ? detectColumns(m.lines[m.hdr]) : null;
          if (c) {
            cols = c;
            break;
          }
        }
        if (!cols) for (const m of merged) for (const l of m.lines) {
          const c = detectColumns(l);
          if (c) {
            cols = c;
            break;
          }
          if (cols) break;
        }
        if (!cols) warnings.push("Item table header not recognised; rows were found by their numbers. Please check each row.");
        const rows = [];
        let lastIdx = -1, lastMi = -1;
        merged.forEach((m, mi) => {
          let start = 0;
          if (mi === 0) start = m.hdr >= 0 ? m.hdr + 1 : 0;
          let fold = 0;
          for (let i = start; i < m.lines.length; i++) {
            const line = m.lines[i];
            if (CARRY_LINE.test(line)) continue;
            if (TOTAL_MARK.test(line) || CONT_MARK.test(line)) break;
            const row = cols && rowFromColumns(line, cols) || rowByNumbers(line);
            if (row) {
              rows.push(row);
              lastIdx = i;
              lastMi = mi;
              fold = 0;
              continue;
            }
            if (rows.length && fold < 4 && !/[₹$]|\b(?:gst|cgst|sgst|igst|total|rs\.?)\b|(?:^|\s)-(?:\s+-){1,}/i.test(line)) {
              const tail = line.replace(PCT_FRAG, "").trim();
              if (tail && /[A-Za-z]/.test(tail) && tail.length <= 40 && !/\d[\d,]*\.\d\d\b/.test(tail) && !/\b\d{5,}\b/.test(tail)) {
                rows[rows.length - 1].description = `${rows[rows.length - 1].description} ${tail}`.replace(/\s+/g, " ").trim();
                fold++;
              }
            }
          }
        });
        const out = rows.map((r, i) => {
          const m = bestMatch(r.description, items, r.hsn);
          const gross = r.qty * r.rate;
          return {
            sno: i + 1,
            ...r,
            item_id: m.match ? m.match.id : null,
            item_name: m.match ? m.match.name : null,
            match_confidence: m.match ? Math.round(m.score * 100) / 100 : 0,
            amount_differs: r.rate > 0 && Math.abs(gross - r.amount) > Math.max(0.6, gross * 5e-3),
            fractional_qty: !Number.isInteger(r.qty)
          };
        });
        if (!out.length) warnings.push("No item rows could be read. Add them manually or check the PDF.");
        if (out.some((l) => !l.item_id)) warnings.push("Some items were not matched to your stock list. Choose or create them.");
        if (out.some((l) => l.fractional_qty)) warnings.push("Some quantities are fractional; stock is kept in whole pieces. Please correct them.");
        if (out.some((l) => l.amount_differs)) warnings.push("For some rows Qty \xD7 Price does not equal the printed Amount (line discount?). The printed Amount was kept.");
        return { rows: out, lastIdx, lastMi };
      }
      var AMOUNT_RE = /-?\d[\d,]*\.\d{1,2}(?![\d%])|-?\d[\d,]*(?![\d.%,])/g;
      function lastAmount(line) {
        const cleaned = line.replace(/@?\s*\d+(?:\.\d+)?\s*%/g, " ");
        const all = cleaned.match(AMOUNT_RE);
        return all && all.length ? toNum(all[all.length - 1]) : null;
      }
      var rateOn = (line) => {
        const m = /(\d+(?:\.\d+)?)\s*%/.exec(line);
        return m ? Number(m[1]) : null;
      };
      function parseTotals(lines) {
        const t = { discount: null, cgst: null, sgst: null, igst: null, round_off: null, grand_total: null };
        const rates = { cgst: [], sgst: [], igst: [] };
        const add = (k, v) => {
          t[k] = r2((t[k] || 0) + v);
        };
        for (const line of lines) {
          if (/^\W*(?:rupees|in\s*words)/i.test(line)) continue;
          const v = lastAmount(line);
          if (v === null) continue;
          if (/grand\s*total|invoice\s*total|total\s*invoice\s*value|net\s*(?:payable|amount)|bill\s*amount|amount\s*payable|total\s*payable/i.test(line)) {
            t.grand_total = Math.abs(v);
            continue;
          }
          if (/round(?:ed|ing)?[\s\-]*(?:off|of)\b/i.test(line)) {
            const neg = /\(\s*-\s*\)|\bless\b|-\s*[\d.,]+\s*$/i.test(line);
            t.round_off = r2((neg ? -1 : 1) * Math.abs(v));
            continue;
          }
          if (/\bdiscount\b|\bdisc\b/i.test(line) && !/^\s*\d+\.?\s/.test(line)) {
            add("discount", Math.abs(v));
            continue;
          }
          if (/\bC\.?G\.?S\.?T\b/i.test(line)) {
            add("cgst", Math.abs(v));
            const r = rateOn(line);
            if (r !== null) rates.cgst.push(r);
            continue;
          }
          if (/\b(?:S\.?G\.?S\.?T|UTGST)\b/i.test(line)) {
            add("sgst", Math.abs(v));
            const r = rateOn(line);
            if (r !== null) rates.sgst.push(r);
            continue;
          }
          if (/\bI\.?G\.?S\.?T\b/i.test(line)) {
            add("igst", Math.abs(v));
            const r = rateOn(line);
            if (r !== null) rates.igst.push(r);
            continue;
          }
        }
        if (t.grand_total === null) {
          for (const line of lines) {
            if (/^\W*total\s+\d/i.test(line) && !/^\W*sub[\s-]*total/i.test(line)) {
              const v = lastAmount(line);
              if (v !== null) {
                t.grand_total = Math.abs(v);
                break;
              }
            }
          }
        }
        const uniq = (a) => [...new Set(a)];
        let gst = null;
        if (uniq(rates.cgst).length === 1 && uniq(rates.sgst).length <= 1) gst = rates.cgst[0] + (rates.sgst[0] || rates.cgst[0]);
        else if (uniq(rates.igst).length === 1) gst = rates.igst[0];
        t.gst_rate = gst;
        return t;
      }
      function summaryRates(lines) {
        const out = [];
        for (const l of lines) {
          const m = /^\W*(\d{1,2}(?:\.\d+)?)%\s+[\d,]+\.\d\d\b/.exec(l);
          if (m) out.push(Number(m[1]));
        }
        return [...new Set(out)];
      }
      var toDigits = (s) => String(s).replace(/\D/g, "");
      function numbersIn(s) {
        return String(s).split(/[,;\/&]|\band\b/i).map((x) => x.trim()).filter((x) => toDigits(x).length >= 6 && toDigits(x).length <= 14);
      }
      var mobileOf = (s) => {
        const d = toDigits(s).replace(/^(91|0)(?=\d{10}$)/, "");
        return /^[6-9]\d{9}$/.test(d) ? d : null;
      };
      function parseSupplier(lines, ctx) {
        const buyerAt = lines.findIndex((l, i) => i > 0 && BUYER_HEAD.test(l));
        const stop = buyerAt > 0 ? buyerAt : lines.findIndex((l, i) => i > 0 && /(?:invoice|bill|inv)\s*(?:no|date)/i.test(l));
        const head = lines.slice(0, stop > 0 ? Math.min(stop, 16) : 14);
        const text = head.join("\n");
        const own = String(ctx.companyGstin || "").toUpperCase();
        const gstins = [...new Set(text.match(GSTIN_RE) || [])].filter((g) => g !== own);
        const gstin = gstins[0] || ([...new Set(lines.join("\n").match(GSTIN_RE) || [])].filter((g) => g !== own)[0] || null);
        const sc = /state\s*(?:code)?\s*[:\-]?\s*(\d{2})\b/i.exec(text);
        const pan = /\bPAN\s*(?:no\.?|number|#)?\s*[:\-]?\s*([A-Z]{5}\d{4}[A-Z])\b/i.exec(text);
        const fssai = /FSSAI[^\d\n]{0,30}(\d{14})/i.exec(text) || /\b(\d{14})\b/.exec(text.split("\n").filter((l) => /fssai|lic/i.test(l)).join(" "));
        const email = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/.exec(text);
        const label = (re) => {
          const m = re.exec(text);
          return m ? m[1].trim() : null;
        };
        const telRaw = label(/\b(?:tel(?:ephone)?|landline)\b\.?\s*(?:no\.?)?\s*[:\-]?\s*([\d \t\-+(),\/]{6,50})/i);
        const phoneRaw = label(/\b(?:phone|ph)\b\.?\s*(?:no\.?)?\s*[:\-]?\s*([\d \t\-+(),\/]{6,50})/i);
        const mobRaw = [...text.matchAll(/\b(?:mobile|mob|cell|whatsapp)\b\.?\s*(?:no\.?|nos\.?)?\s*[:\-]?\s*([\d \t\-+(),\/&and]{8,60})/gi)].map((m) => m[1]);
        const mobiles = [];
        for (const raw of mobRaw) for (const n of numbersIn(raw)) {
          const m = mobileOf(n);
          if (m && !mobiles.includes(m)) mobiles.push(m);
        }
        const split = (raw) => {
          const land = [];
          for (const n of raw ? numbersIn(raw) : []) {
            const m = mobileOf(n);
            if (m) {
              if (!mobiles.includes(m)) mobiles.push(m);
            } else land.push(n);
          }
          return land.join(", ") || null;
        };
        const tel = split(telRaw);
        let phone = split(phoneRaw);
        for (const m of text.matchAll(/(?<![\d-])(?:\+?91[\s-]?)?([6-9]\d{9})(?!\d)/g)) {
          if (!mobiles.includes(m[1]) && !(phone && toDigits(phone).includes(m[1])) && !(tel && toDigits(tel).includes(m[1]))) mobiles.push(m[1]);
        }
        const { name, idx: nameIdx } = supplierName(lines, ctx.companyName);
        const addr = [];
        for (let i = nameIdx + 1; i < head.length; i++) {
          const l = head[i];
          if (BILL_ROW.test(l)) break;
          if (COPY_LABEL.test(l) || /(tax\s*invoice|invoice)/i.test(l)) {
            if (addr.length) break;
            else continue;
          }
          const part = withoutContact(l).replace(/^address\s*[:\-]?\s*/i, "").replace(/[,.\s]+$/, "");
          if (/^\d{6}$/.test(part) && addr.length) {
            addr[addr.length - 1] += " - " + part;
            continue;
          }
          if (!/[A-Za-z]{3}/.test(part)) {
            if (addr.length) break;
            else continue;
          }
          addr.push(part);
          if (addr.length >= 4) break;
        }
        return {
          name,
          address: addr.join(", ") || null,
          gstin,
          state_code: sc ? sc[1] : gstin ? gstin.slice(0, 2) : null,
          tel,
          phone,
          mobiles,
          fssai: fssai ? fssai[1] : null,
          pan: pan ? pan[1].toUpperCase() : gstin ? gstin.slice(2, 12) : null,
          email: email ? email[0] : null
        };
      }
      var SUFFIX = /\b(pvt|private|ltd|limited|traders|enterprises?|distributors?|agenc(?:y|ies)|industries|foods|stores?|corporation|marketing|company|co\.?|brothers|bros|beverages|trading|sales|suppliers?|sons|mart|udyog|impex|exports?|products|pharma|llp|emporium|depot|bhandar|kirana|wholesalers?|mills|provisions|associates|ventures)\b/i;
      var GENERIC = /^(tax\s*invoice|proforma(\s*invoice)?|invoice|original|duplicate|triplicate|gstin|bill of supply|page|e-?invoice|irn|ack|cash|credit|\(?see rule)/i;
      var INVOCATION = /^\W*(?:shree|shri|sri|jai|om)\s+(?:ganesh\w*|mata\s+di|ram|radhe|krishna|hanuman\w*|balaji|sai\s+ram|shyam|laxmi|lakshmi|durga)(?:\s+(?:ji|namah?a?|ki\s+jai|sahay\w*))*\W*$/i;
      var BILL_ROW = /\b(?:invoice|bill|inv)\s*(?:no|number|date)\b|\bdated\b|\bparticulars\b|\bdescription\b|^s\.?\s*no\b|\bhsn\b|\bqty\b/i;
      var BUYER_HEAD = /(party\s*details|bill(?:ed)?\s*to|buyer|consignee|ship(?:ped)?\s*to|details\s*of\s*(?:receiver|buyer)|customer\s*name|m\/s)/i;
      var EMAIL_RE = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g;
      var CONTACT_AT = /\b(?:e-?mail(?:\s*id)?|tel(?:ephone)?|phone|ph|mob(?:ile)?|cell|whatsapp|gstin|gst\s*no|fssai|pan|cin|state\s*code|website|fax|contact)\b/i;
      function withoutContact(l) {
        let s = String(l).replace(EMAIL_RE, " ").replace(/\b(?:https?:\/\/|www\.)\S+/gi, " ");
        const m = CONTACT_AT.exec(s);
        if (m) s = s.slice(0, m.index);
        s = s.replace(/(?:\+?91[\s-]?)?[6-9]\d{9}(?!\d)/g, " ");
        return s.replace(/\s+/g, " ").replace(/^[\s,;:|\-\/.]+/, "").replace(/[\s,;:|\-\/]+$/, "").trim();
      }
      function supplierName(lines, companyName) {
        const own = norm(companyName);
        const cand = [];
        lines.slice(0, 12).forEach((l, idx) => {
          if (GENERIC.test(l) || INVOCATION.test(l) || /^\W*(bill to|ship to|buyer|consignee)/i.test(l)) return;
          const name = withoutContact(l).replace(/^(?:m\/s\.?|from\s*:)\s*/i, "");
          if (!/[A-Za-z]{3}/.test(name) || GENERIC.test(name)) return;
          if (own && norm(name).includes(own)) return;
          cand.push({ name, idx });
        });
        return cand.find((c) => SUFFIX.test(c.name) && c.name.length < 70) || cand[0] || { name: null, idx: -1 };
      }
      function findInvoiceNo(text) {
        const m = text.match(/(?:tax\s+)?(?:proforma\s+)?(?:invoice|inv|bill)\s*(?:no|number|num|#)\.?\s*[:\-#]?\s*((?=[A-Z0-9\/\-]{0,24}\d)[A-Z0-9][A-Z0-9\/\-]{2,24})/i);
        if (m) return m[1];
        const lines = text.split("\n");
        const li = lines.findIndex((l) => /\b(?:invoice|bill)\s*(?:no|number|num|#)\b/i.test(l));
        if (li >= 0) {
          for (let i = li + 1; i < Math.min(li + 3, lines.length); i++) {
            const stripped = lines[i].replace(GSTIN_RE, " ").replace(/(?:\+?91[\s-]?)?[6-9]\d{9}\b/g, " ");
            const num = /\b(\d{2,8})\b(?!\s*[\/\-]\d)/.exec(stripped);
            if (num) return num[1];
          }
        }
        return null;
      }
      function normaliseDate(raw) {
        if (!raw) return null;
        let m = raw.match(/(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})/);
        if (m) {
          let [, d, mo, y] = m;
          y = y.length === 2 ? "20" + y : y;
          if (+mo >= 1 && +mo <= 12 && +d >= 1 && +d <= 31) return `${y}-${pad(mo)}-${pad(d)}`;
        }
        m = raw.match(/(\d{1,2})[ \-]([A-Za-z]{3})[A-Za-z]*[ \-,.]*(\d{2,4})/);
        if (m && MONTHS[m[2].toLowerCase()]) {
          const y = m[3].length === 2 ? "20" + m[3] : m[3];
          return `${y}-${pad(MONTHS[m[2].toLowerCase()])}-${pad(m[1])}`;
        }
        return null;
      }
      var DATE_PAT = "(\\d{1,2}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{2,4}|\\d{1,2}[ \\-](?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[ \\-,.]*\\d{2,4})";
      function findDate(text) {
        const near = text.match(new RegExp("(?:(?:invoice|bill|inv|proforma)\\s*date|dated)\\s*[:\\-]?\\s*" + DATE_PAT, "i"));
        if (near) {
          const d = normaliseDate(near[1]);
          if (d) return d;
        }
        const any = text.match(new RegExp(DATE_PAT, "i"));
        return any ? normaliseDate(any[1]) : null;
      }
      function parseInvoicePages2(pages, ctx = {}) {
        const { items = [], parties = [], companyGstin = "", companyName = "" } = ctx;
        const warnings = [];
        const sel = selectOriginalPages(pages.length ? pages : [""]);
        if (sel.note) warnings.push(sel.note);
        const merged = mergePages(sel.pages);
        const first = merged[0].lines;
        const firstText = first.join("\n");
        const sup = parseSupplier(first, { companyGstin, companyName });
        let matched = null;
        if (sup.gstin) matched = parties.find((p) => p.gstin && p.gstin.toUpperCase() === sup.gstin) || null;
        if (!matched && sup.name) {
          const m = bestMatch(sup.name, parties, null);
          matched = m.match;
        }
        if (!sup.name) warnings.push("Supplier name not found");
        const invoiceNo = findInvoiceNo(firstText);
        if (!invoiceNo) warnings.push("Invoice number not found");
        const date = findDate(firstText);
        if (!date) warnings.push("Invoice date not found");
        const { rows, lastIdx, lastMi } = parseItems(merged, items, warnings);
        const tail = lastMi >= 0 ? [...merged[lastMi].lines.slice(lastIdx + 1), ...merged.slice(lastMi + 1).flatMap((m) => m.lines)] : merged.flatMap((m) => m.lines).slice(-40);
        const totals = parseTotals(tail);
        const billRates = summaryRates(tail);
        const fallbackRate = totals.gst_rate !== null ? totals.gst_rate : billRates.length === 1 ? billRates[0] : null;
        for (const r of rows) enrichLine(r, fallbackRate);
        const subtotal = r2(rows.reduce((a, r) => a + r.amount, 0));
        totals.subtotal = subtotal;
        if (totals.grand_total === null) warnings.push("Grand total not found on the bill");
        if (totals.cgst === null && totals.sgst === null && totals.igst === null) warnings.push("CGST / SGST / IGST amounts not found; they will be worked out from your item GST rates unless you type them.");
        if (totals.grand_total !== null && rows.length) {
          const calc = r2(subtotal - (totals.discount || 0) + (totals.cgst || 0) + (totals.sgst || 0) + (totals.igst || 0) + (totals.round_off || 0));
          const haveTax = !(totals.cgst === null && totals.sgst === null && totals.igst === null);
          if (haveTax && Math.abs(calc - totals.grand_total) > 1) warnings.push(`Items \u2212 discount + taxes + round off = ${calc}, but the bill's grand total is ${totals.grand_total}. Check the rows and the totals.`);
        }
        return {
          supplier: { ...sup, matched_party_id: matched ? matched.id : null, matched_name: matched ? matched.name : null },
          invoice_no: invoiceNo,
          date,
          lines: rows,
          totals,
          warnings,
          pages: { total: pages.length, used: sel.used, skipped: sel.skipped },
          // kept for older callers
          stated_total: totals.grand_total
        };
      }
      var parseInvoiceText = (text, ctx) => parseInvoicePages2(String(text || "").split("\f"), ctx);
      module.exports = { rowFromColumns, packFromName, mrpFromName, rateFromHsn, parseInvoicePages: parseInvoicePages2, parseInvoiceText, selectOriginalPages, mergePages, copyKind, detectColumns, parseTotals, parseSupplier, normaliseDate, similarity };
    }
  });

  // ../../backend/src/db.js
  var require_db = __commonJS({
    "../../backend/src/db.js"(exports, module) {
      init_globals();
      var Database = require_sqlite2();
      var { AsyncLocalStorage } = require_async_hooks();
      var path = require_path();
      var fs = require_fs();
      var { applySchema } = require_schema();
      var dataDir = process.env.DATA_DIR || path.join(__dirname, "..", "data");
      fs.mkdirSync(dataDir, { recursive: true });
      var registry = new Database(path.join(dataDir, "registry.db"));
      registry.pragma("journal_mode = WAL");
      registry.exec(`
CREATE TABLE IF NOT EXISTS companies (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, file TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1, created_at TEXT DEFAULT (datetime('now','localtime'))
);
CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT);
`);
      if (!registry.prepare("PRAGMA table_info(companies)").all().some((c) => c.name === "fy")) registry.exec("ALTER TABLE companies ADD COLUMN fy TEXT");
      var als = new AsyncLocalStorage();
      var open = /* @__PURE__ */ new Map();
      function companyRow(id) {
        return registry.prepare("SELECT * FROM companies WHERE id=? AND active=1").get(id);
      }
      function tidyItems(d) {
        const { packFromName } = require_pdfParser();
        const up = d.prepare("UPDATE items SET pcs_per_box=? WHERE id=?");
        for (const it of d.prepare("SELECT id,name,pcs_per_box FROM items").all()) {
          const pk = packFromName(it.name);
          if (pk && it.pcs_per_box !== pk) up.run(pk, it.id);
        }
        d.exec("UPDATE items SET unit='PCS' WHERE unit IS NOT 'PCS'");
      }
      function openCompany(id) {
        if (open.has(id)) return open.get(id);
        const row = companyRow(id);
        if (!row) return null;
        const d = new Database(path.join(dataDir, row.file));
        applySchema(d);
        tidyItems(d);
        open.set(id, d);
        return d;
      }
      function closeCompany(id) {
        const d = open.get(id);
        if (d) {
          try {
            d.close();
          } catch {
          }
          open.delete(id);
        }
      }
      function firstCompanyId() {
        const r = registry.prepare("SELECT id FROM companies WHERE active=1 ORDER BY id LIMIT 1").get();
        return r ? r.id : null;
      }
      function createCompany({ name, fy = null, ...settings2 }) {
        let file = `company_${Date.now()}.db`;
        for (let n = 2; fs.existsSync(path.join(dataDir, file)); n++) file = `company_${Date.now()}_${n}.db`;
        const id = Number(registry.prepare("INSERT INTO companies(name,file,fy) VALUES(?,?,?)").run(name, file, fy).lastInsertRowid);
        const d = new Database(path.join(dataDir, file));
        applySchema(d, { company_name: name, ...fy ? { books_fy: fy } : {}, ...settings2 });
        open.set(id, d);
        return id;
      }
      function withCompany(id, fn) {
        const d = openCompany(id);
        if (!d) throw new Error(`Company ${id} not found`);
        return als.run(d, fn);
      }
      if (!firstCompanyId()) {
        const legacy = path.join(dataDir, "distributor.db");
        if (fs.existsSync(legacy)) {
          const id = Number(registry.prepare("INSERT INTO companies(name,file) VALUES(?,?)").run("My Company", "distributor.db").lastInsertRowid);
          const d = openCompany(id);
          const nm = d.prepare("SELECT value FROM settings WHERE key='company_name'").get();
          if (nm && nm.value) registry.prepare("UPDATE companies SET name=? WHERE id=?").run(nm.value, id);
        } else {
          createCompany({ name: "My Company" });
        }
      }
      var current = () => {
        const d = als.getStore();
        if (!d) throw new Error("No company selected for this request");
        return d;
      };
      var db2 = {
        prepare: (s) => current().prepare(s),
        exec: (s) => current().exec(s),
        pragma: (s) => current().pragma(s),
        transaction: (fn) => (...a) => current().transaction(fn)(...a),
        // multi-company helpers
        registry,
        dataDir,
        openCompany,
        closeCompany,
        createCompany,
        withCompany,
        firstCompanyId,
        companyRow,
        middleware(req, res, next) {
          const id = Number(req.get("x-company-id")) || firstCompanyId();
          const d = openCompany(id);
          if (!d) return res.status(404).json({ error: "Company not found" });
          als.run(d, next);
        }
      };
      module.exports = db2;
    }
  });

  // shims/os.js
  var require_os = __commonJS({
    "shims/os.js"(exports, module) {
      "use strict";
      init_globals();
      var host = () => globalThis.AndroidHost;
      module.exports = {
        homedir: () => host().home(),
        tmpdir: () => host().tmp(),
        platform: () => "android",
        EOL: "\n"
      };
    }
  });

  // shims/crypto.js
  var require_crypto = __commonJS({
    "shims/crypto.js"(exports, module) {
      "use strict";
      init_globals();
      var K = new Uint32Array([
        1116352408,
        1899447441,
        3049323471,
        3921009573,
        961987163,
        1508970993,
        2453635748,
        2870763221,
        3624381080,
        310598401,
        607225278,
        1426881987,
        1925078388,
        2162078206,
        2614888103,
        3248222580,
        3835390401,
        4022224774,
        264347078,
        604807628,
        770255983,
        1249150122,
        1555081692,
        1996064986,
        2554220882,
        2821834349,
        2952996808,
        3210313671,
        3336571891,
        3584528711,
        113926993,
        338241895,
        666307205,
        773529912,
        1294757372,
        1396182291,
        1695183700,
        1986661051,
        2177026350,
        2456956037,
        2730485921,
        2820302411,
        3259730800,
        3345764771,
        3516065817,
        3600352804,
        4094571909,
        275423344,
        430227734,
        506948616,
        659060556,
        883997877,
        958139571,
        1322822218,
        1537002063,
        1747873779,
        1955562222,
        2024104815,
        2227730452,
        2361852424,
        2428436474,
        2756734187,
        3204031479,
        3329325298
      ]);
      function sha256(bytes) {
        const n = bytes.length, total = n + 9 + 63 >> 6 << 6;
        const m = new Uint8Array(total);
        m.set(bytes);
        m[n] = 128;
        const bits = n * 8;
        const dv = new DataView(m.buffer);
        dv.setUint32(total - 8, Math.floor(bits / 4294967296));
        dv.setUint32(total - 4, bits >>> 0);
        const H = new Uint32Array([1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225]);
        const W = new Uint32Array(64);
        for (let o = 0; o < total; o += 64) {
          for (let i = 0; i < 16; i++) W[i] = dv.getUint32(o + i * 4);
          for (let i = 16; i < 64; i++) {
            const a2 = W[i - 15], b2 = W[i - 2];
            const s0 = (a2 >>> 7 | a2 << 25) ^ (a2 >>> 18 | a2 << 14) ^ a2 >>> 3;
            const s1 = (b2 >>> 17 | b2 << 15) ^ (b2 >>> 19 | b2 << 13) ^ b2 >>> 10;
            W[i] = W[i - 16] + s0 + W[i - 7] + s1 >>> 0;
          }
          let [a, b, c, d, e, f, g, h] = H;
          for (let i = 0; i < 64; i++) {
            const S1 = (e >>> 6 | e << 26) ^ (e >>> 11 | e << 21) ^ (e >>> 25 | e << 7);
            const t1 = h + S1 + (e & f ^ ~e & g) + K[i] + W[i] >>> 0;
            const S0 = (a >>> 2 | a << 30) ^ (a >>> 13 | a << 19) ^ (a >>> 22 | a << 10);
            const t2 = S0 + (a & b ^ a & c ^ b & c) >>> 0;
            h = g;
            g = f;
            f = e;
            e = d + t1 >>> 0;
            d = c;
            c = b;
            b = a;
            a = t1 + t2 >>> 0;
          }
          H[0] += a;
          H[1] += b;
          H[2] += c;
          H[3] += d;
          H[4] += e;
          H[5] += f;
          H[6] += g;
          H[7] += h;
        }
        return Array.from(H, (x) => x.toString(16).padStart(8, "0")).join("");
      }
      function createHash(alg) {
        if (String(alg).toLowerCase() !== "sha256") throw new Error(`Hash ${alg} is not available`);
        const parts = [];
        const h = {
          update(d) {
            parts.push(typeof d === "string" ? new TextEncoder().encode(d) : d);
            return h;
          },
          digest(enc) {
            const n = parts.reduce((a, p) => a + p.length, 0);
            const all = new Uint8Array(n);
            let o = 0;
            for (const p of parts) {
              all.set(p, o);
              o += p.length;
            }
            const hex = sha256(all);
            return enc === "hex" ? hex : Buffer2.from(hex, "hex");
          }
        };
        return h;
      }
      module.exports = { createHash, randomUUID: () => crypto.randomUUID() };
    }
  });

  // ../../backend/src/utils/misc.js
  var require_misc = __commonJS({
    "../../backend/src/utils/misc.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var today = () => (/* @__PURE__ */ new Date()).toLocaleDateString("en-CA");
      function fy(d = /* @__PURE__ */ new Date()) {
        const y = typeof d === "string" ? +d.slice(0, 4) : d.getFullYear();
        const mo = typeof d === "string" ? +d.slice(5, 7) - 1 : d.getMonth();
        const start = mo >= 3 ? y : y - 1;
        return `${String(start).slice(2)}-${String(start + 1).slice(2)}`;
      }
      var SERIES = { INV: ["invoices", "invoice_no"], RCT: ["receipts", "receipt_no"], PUR: ["purchases", "purchase_no"], PAY: ["payments", "voucher_no"], DN: ["debit_notes", "note_no"] };
      function numbering(prefix, date) {
        const get = (k) => {
          const r = db2.prepare("SELECT value FROM settings WHERE key=?").get(k);
          return r && r.value !== null ? String(r.value) : "";
        };
        const label = get(`num_${prefix}_prefix`).trim() || prefix;
        const withFy = get("num_fy") !== "0";
        const own = parseInt(get(`num_${prefix}_digits`), 10);
        const d = parseInt(get("num_digits"), 10);
        const digits = own >= 1 && own <= 9 ? own : d >= 3 && d <= 6 ? d : 5;
        const year = fy(date || /* @__PURE__ */ new Date());
        const sep = /[A-Za-z0-9]$/.test(label) ? "/" : "";
        const head = withFy ? `${label}${sep}${year}/` : label;
        return { prefix, label, withFy, digits, head, key: withFy ? `${prefix}/${year}` : prefix };
      }
      function lastUsed(prefix, head) {
        const t = SERIES[prefix];
        let best = { n: 0, no: "" };
        if (!t) return best;
        for (const r of db2.prepare(`SELECT ${t[1]} AS no FROM ${t[0]} WHERE substr(${t[1]}, 1, ?) = ?`).all(head.length, head)) {
          const rest = String(r.no).slice(head.length);
          if (/^[0-9]+$/.test(rest) && parseInt(rest, 10) > best.n) best = { n: parseInt(rest, 10), no: String(r.no) };
        }
        return best;
      }
      function peekNo(prefix, date) {
        const s = numbering(prefix, date);
        const c = db2.prepare("SELECT value FROM counters WHERE key = ?").get(s.key);
        const v = Math.max(c ? Number(c.value) : 0, lastUsed(prefix, s.head).n) + 1;
        return { ...s, next: v, next_no: s.head + String(v).padStart(s.digits, "0"), last_no: lastUsed(prefix, s.head).no };
      }
      function nextNo(prefix, date) {
        const s = numbering(prefix, date);
        const used = lastUsed(prefix, s.head).n;
        db2.prepare("INSERT INTO counters(key,value) VALUES(?,0) ON CONFLICT(key) DO NOTHING").run(s.key);
        db2.prepare("UPDATE counters SET value = MAX(value, ?) + 1 WHERE key = ?").run(used, s.key);
        const v = db2.prepare("SELECT value FROM counters WHERE key = ?").get(s.key).value;
        return s.head + String(v).padStart(s.digits, "0");
      }
      function setNext(prefix, next, date) {
        if (!SERIES[prefix]) throw new HttpError2(400, "Unknown series");
        const n = parseInt(next, 10);
        if (!(n >= 1) || String(n) !== String(next).trim()) throw new HttpError2(400, "Enter the next number as a whole number, 1 or more");
        const s = numbering(prefix, date);
        const used = lastUsed(prefix, s.head);
        if (n <= used.n) throw new HttpError2(409, `The next number must come after ${used.no}, the last one used`);
        db2.prepare("INSERT INTO counters(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(s.key, n - 1);
        return peekNo(prefix, date);
      }
      var HttpError2 = class extends Error {
        constructor(status, message, code) {
          super(message);
          this.status = status;
          this.code = code;
        }
      };
      var h = (fn) => (req, res, next) => {
        try {
          fn(req, res, next);
        } catch (e) {
          next(e);
        }
      };
      var ha = (fn) => (req, res, next) => {
        Promise.resolve().then(() => fn(req, res, next)).catch(next);
      };
      var blank = (v) => v === void 0 || v === null || String(v).trim() === "" ? null : v;
      function normDays(v) {
        if (v === void 0 || v === null || v === "") return null;
        const a = (Array.isArray(v) ? v : String(v).split(",")).map((x) => parseInt(x)).filter((x) => x >= 0 && x <= 6);
        const u = [...new Set(a)].sort();
        return u.length ? u.join(",") : null;
      }
      module.exports = { normDays, today, fy, nextNo, peekNo, setNext, SERIES, HttpError: HttpError2, h, ha, blank };
    }
  });

  // ../../backend/src/services/drive.js
  var require_drive = __commonJS({
    "../../backend/src/services/drive.js"(exports, module) {
      init_globals();
      var fs = require_fs();
      var path = require_path();
      var db2 = require_db();
      var { HttpError: HttpError2 } = require_misc();
      var B3 = require_backup();
      var reg = db2.registry;
      var get = (k) => {
        const r = reg.prepare("SELECT value FROM app_settings WHERE key=?").get(k);
        return r && r.value ? String(r.value) : "";
      };
      var set = (k, v) => reg.prepare("INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(k, String(v));
      var del = (k) => reg.prepare("DELETE FROM app_settings WHERE key=?").run(k);
      var SCOPE = "https://www.googleapis.com/auth/drive.file";
      var FOLDER = "BillBox Backups";
      var FOLDER_TYPE = "application/vnd.google-apps.folder";
      var offline = () => new HttpError2(503, "Could not reach Google. Check the internet connection and try again.", "OFFLINE");
      var form = (o) => Object.entries(o).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join("&");
      var FORM = { "content-type": "application/x-www-form-urlencoded" };
      async function call(url, opts) {
        let r;
        try {
          r = await fetch(url, opts);
        } catch (_) {
          throw offline();
        }
        const text = await r.text();
        let json = {};
        try {
          json = JSON.parse(text);
        } catch (_) {
        }
        return { status: r.status, json: json && typeof json === "object" ? json : {} };
      }
      function status() {
        return {
          client_id: get("drive_client_id"),
          has_secret: get("drive_client_secret") !== "",
          connected: get("drive_refresh") !== "",
          waiting: get("drive_device") !== "",
          folder: get("drive_folder_id") ? FOLDER : "",
          last_upload: get("drive_last_upload"),
          last_status: get("drive_last_status")
        };
      }
      function keysFromJson(text) {
        let j;
        try {
          j = JSON.parse(String(text));
        } catch (_) {
          throw new HttpError2(400, "That file is not the JSON file downloaded from Google Cloud (client_secret_\u2026.json).");
        }
        if (j && j.web && !j.installed) throw new HttpError2(400, "That file is for a \u201CWeb application\u201D client. In Google Cloud make an OAuth client of type \u201CTVs and Limited Input devices\u201D and download its JSON.");
        const k = j && (j.installed || j.web) || j || {};
        if (!k.client_id || !k.client_secret) throw new HttpError2(400, "That file has no client ID and secret in it. Download the JSON of the OAuth client (Credentials \u203A your client \u203A Download JSON).");
        return { client_id: k.client_id, client_secret: k.client_secret };
      }
      function explain(j, status2) {
        const e = j.error || "";
        if (e === "invalid_client") return "Google does not know this Client ID. Check it was copied in full (or import the downloaded JSON file), that the client is of type \u201CTVs and Limited Input devices\u201D, and if you made it just now wait a few minutes and try again";
        if (e === "unauthorized_client") return "this client cannot use code sign-in: make an OAuth client of type \u201CTVs and Limited Input devices\u201D";
        if (e === "invalid_scope") return "the Google Drive API is not allowed for this client: turn on the Google Drive API in your Google Cloud project";
        if (e === "access_denied" || e === "org_internal") return "Google refused: add your Gmail as a test user on the consent screen (Audience \u203A Test users)";
        return j.error_description || e || String(status2);
      }
      function saveClient(b = {}) {
        if (b.json) b = keysFromJson(b.json);
        const id = String(b.client_id || "").trim(), secret = String(b.client_secret || "").trim();
        if (!/\.apps\.googleusercontent\.com$/.test(id)) throw new HttpError2(400, "Paste the Client ID from Google Cloud (it ends in .apps.googleusercontent.com).");
        if (!secret) throw new HttpError2(400, "Paste the client secret too.");
        if (id !== get("drive_client_id")) for (const k of ["drive_refresh", "drive_folder_id", "drive_device"]) del(k);
        set("drive_client_id", id);
        set("drive_client_secret", secret);
        return status();
      }
      async function connect() {
        const id = get("drive_client_id");
        if (!id) throw new HttpError2(400, "Add the Google Client ID and secret first.");
        const r = await call("https://oauth2.googleapis.com/device/code", { method: "POST", headers: FORM, body: form({ client_id: id, scope: SCOPE }) });
        if (r.status !== 200) throw new HttpError2(r.json.error ? 400 : 502, `Google did not give a code: ${explain(r.json, r.status)}.`);
        set("drive_device", r.json.device_code);
        return {
          user_code: r.json.user_code,
          verification_url: r.json.verification_url || r.json.verification_uri || "https://www.google.com/device",
          interval: r.json.interval || 5,
          expires_in: r.json.expires_in || 1800
        };
      }
      async function poll() {
        const dev = get("drive_device");
        if (!dev) throw new HttpError2(400, "Press Connect first.");
        const r = await call("https://oauth2.googleapis.com/token", {
          method: "POST",
          headers: FORM,
          body: form({ client_id: get("drive_client_id"), client_secret: get("drive_client_secret"), device_code: dev, grant_type: "urn:ietf:params:oauth:grant-type:device_code" })
        });
        if (r.json.error === "authorization_pending" || r.json.error === "slow_down") return { connected: false, waiting: true };
        del("drive_device");
        if (r.status !== 200 || !r.json.refresh_token) {
          throw new HttpError2(400, r.json.error === "access_denied" ? "Google sign-in was declined." : r.json.error === "expired_token" ? "The code ran out. Press Connect again." : `Google did not connect: ${explain(r.json, r.status)}.`);
        }
        set("drive_refresh", r.json.refresh_token);
        await folder(r.json.access_token);
        return { connected: true, waiting: false, folder: FOLDER };
      }
      function disconnect() {
        for (const k of ["drive_refresh", "drive_folder_id", "drive_device", "drive_last_upload", "drive_last_status"]) del(k);
        return status();
      }
      async function token() {
        if (!get("drive_refresh")) throw new HttpError2(400, "Google Drive is not connected.");
        const r = await call("https://oauth2.googleapis.com/token", {
          method: "POST",
          headers: FORM,
          body: form({ client_id: get("drive_client_id"), client_secret: get("drive_client_secret"), refresh_token: get("drive_refresh"), grant_type: "refresh_token" })
        });
        if (r.status !== 200 || !r.json.access_token) {
          if (r.json.error === "invalid_grant") {
            del("drive_refresh");
            del("drive_folder_id");
            throw new HttpError2(401, "Google Drive was disconnected (the permission was removed or ran out). Connect again.");
          }
          throw new HttpError2(502, `Google did not answer (${r.json.error_description || r.json.error || r.status}).`);
        }
        return r.json.access_token;
      }
      async function makeFolder(tok, name, parent) {
        const r = await call("https://www.googleapis.com/drive/v3/files?fields=id", {
          method: "POST",
          headers: { authorization: `Bearer ${tok}`, "content-type": "application/json" },
          body: JSON.stringify(parent ? { name, mimeType: FOLDER_TYPE, parents: [parent] } : { name, mimeType: FOLDER_TYPE })
        });
        if (r.status !== 200 || !r.json.id) throw new HttpError2(502, `Google Drive did not make the folder "${name}" (${r.json.error && r.json.error.message || r.status}).`);
        return r.json.id;
      }
      async function folder(tok) {
        const id = get("drive_folder_id");
        if (id) {
          const r = await call(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(id)}?fields=id,trashed`, { headers: { authorization: `Bearer ${tok}` } });
          if (r.status === 200 && !r.json.trashed) return id;
        }
        const made = await makeFolder(tok, FOLDER, null);
        set("drive_folder_id", made);
        return made;
      }
      async function upload(b = {}) {
        const list = B3.listBackups();
        const name = b.folder ? String(b.folder) : list[0] && list[0].name;
        if (!name) throw new HttpError2(400, "There is no backup to upload yet. Press Back up now first.");
        const dir = path.join(B3.config().dir, path.basename(name));
        if (!fs.existsSync(dir)) throw new HttpError2(404, `Backup ${name} not found.`);
        const tok = await token();
        const parent = await folder(tok);
        const sub = await makeFolder(tok, path.basename(name), parent);
        const files = fs.readdirSync(dir).filter((f) => fs.statSync(path.join(dir, f)).isFile()).sort();
        let bytes = 0;
        for (const f of files) {
          const data = fs.readFileSync(path.join(dir, f));
          const boundary = "billbox" + Date.now().toString(36);
          const meta = JSON.stringify({ name: f, parents: [sub] });
          const body = Buffer2.concat([
            Buffer2.from(`--${boundary}\r
content-type: application/json; charset=UTF-8\r
\r
${meta}\r
--${boundary}\r
content-type: application/octet-stream\r
\r
`),
            data,
            Buffer2.from(`\r
--${boundary}--\r
`)
          ]);
          const r = await call("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id", {
            method: "POST",
            headers: { authorization: `Bearer ${tok}`, "content-type": `multipart/related; boundary=${boundary}` },
            body
          });
          if (r.status !== 200) {
            set("drive_last_status", `failed: ${f}`);
            throw new HttpError2(502, `Google Drive did not take ${f} (${r.json.error && r.json.error.message || r.status}).`);
          }
          bytes += data.length;
        }
        set("drive_last_upload", `${name}`);
        set("drive_last_status", "ok");
        return { folder: name, files: files.length, bytes, drive_folder: FOLDER };
      }
      async function afterBackup(folderName) {
        if (!get("drive_refresh")) return null;
        try {
          return await upload({ folder: folderName });
        } catch (e) {
          set("drive_last_status", `failed: ${e.message}`);
          return null;
        }
      }
      module.exports = { status, saveClient, connect, poll, disconnect, upload, afterBackup };
    }
  });

  // ../../backend/src/services/backup.js
  var require_backup = __commonJS({
    "../../backend/src/services/backup.js"(exports, module) {
      init_globals();
      var fs = require_fs();
      var os = require_os();
      var path = require_path();
      var crypto2 = require_crypto();
      var Database = require_sqlite2();
      var db2 = require_db();
      var { HttpError: HttpError2 } = require_misc();
      var reg = db2.registry;
      var PREFIX = "FMCG_Backup_";
      var FOLDER_RE = /^FMCG_Backup_\d{8}_\d{6}(_\d+)?$/;
      var getSetting = (k, d) => {
        const r = reg.prepare("SELECT value FROM app_settings WHERE key=?").get(k);
        return r ? r.value : d;
      };
      var setSetting = (k, v) => reg.prepare("INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(k, String(v));
      function config() {
        return {
          dir: getSetting("backup_dir", path.join(os.homedir(), "DistributorProBackups")),
          enabled: getSetting("backup_enabled", "0") === "1",
          time: getSetting("backup_time", "21:00"),
          on_exit: getSetting("backup_on_exit", "0") === "1",
          last_run: getSetting("backup_last_run", ""),
          last_status: getSetting("backup_last_status", "")
        };
      }
      function saveConfig(b) {
        if (b.dir !== void 0) {
          if (!path.isAbsolute(b.dir)) throw new HttpError2(400, "Enter the full path of the backup folder, e.g. /Volumes/MyDrive/Backups");
          setSetting("backup_dir", b.dir);
        }
        if (b.enabled !== void 0) setSetting("backup_enabled", b.enabled ? "1" : "0");
        if (b.on_exit !== void 0) setSetting("backup_on_exit", b.on_exit ? "1" : "0");
        if (b.time !== void 0) {
          if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(b.time)) throw new HttpError2(400, "Time must be HH:MM (24 hour)");
          setSetting("backup_time", b.time);
        }
        return config();
      }
      var stamp = (d = /* @__PURE__ */ new Date()) => {
        const p = (n) => String(n).padStart(2, "0");
        return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
      };
      var slug = (s) => String(s).replace(/[^A-Za-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 40) || "Company";
      var sqlPath = (p) => p.replace(/'/g, "''");
      function sha256(file) {
        return crypto2.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
      }
      function copyAndVerify(rawDb, dest) {
        rawDb.exec(`VACUUM INTO '${sqlPath(dest)}'`);
        const chk = new Database(dest, { readonly: true });
        try {
          const r = chk.prepare("PRAGMA integrity_check").get();
          const v = Object.values(r)[0];
          if (v !== "ok") throw new HttpError2(500, `Backup verification failed for ${path.basename(dest)}: ${v}`);
        } finally {
          chk.close();
        }
        return { file: path.basename(dest), bytes: fs.statSync(dest).size, sha256: sha256(dest) };
      }
      function backupNow({ reason = "manual" } = {}) {
        const { dir } = config();
        try {
          fs.mkdirSync(dir, { recursive: true });
          const probe = path.join(dir, `.write-test-${process.pid}`);
          fs.writeFileSync(probe, "ok");
          fs.rmSync(probe);
        } catch (e) {
          const msg = `Cannot write to "${dir}". Is the drive connected and the folder writable?`;
          setSetting("backup_last_status", `FAILED ${(/* @__PURE__ */ new Date()).toISOString()}: ${msg}`);
          throw new HttpError2(500, msg);
        }
        let folder = path.join(dir, PREFIX + stamp());
        for (let n = 2; fs.existsSync(folder); n++) folder = path.join(dir, `${PREFIX}${stamp()}_${n}`);
        fs.mkdirSync(folder);
        try {
          const files = [];
          const companies = reg.prepare("SELECT * FROM companies WHERE active=1 ORDER BY id").all();
          for (const c of companies) {
            const raw = db2.openCompany(c.id);
            files.push({ company_id: c.id, company: c.name, ...c.fy ? { fy: c.fy } : {}, ...copyAndVerify(raw, path.join(folder, `${slug(c.name)}${c.fy ? "_" + c.fy : ""}_${c.id}.db`)) });
          }
          files.push({ company: "(company list)", ...copyAndVerify(reg, path.join(folder, "registry.db")) });
          fs.writeFileSync(path.join(folder, "manifest.json"), JSON.stringify({ created: (/* @__PURE__ */ new Date()).toISOString(), reason, files }, null, 2));
          setSetting("backup_last_run", (/* @__PURE__ */ new Date()).toISOString());
          setSetting("backup_last_status", `OK ${path.basename(folder)}`);
          return { folder, files };
        } catch (e) {
          fs.rmSync(folder, { recursive: true, force: true });
          setSetting("backup_last_status", `FAILED ${(/* @__PURE__ */ new Date()).toISOString()}: ${e.message}`);
          throw e;
        }
      }
      function deleteBackup(name) {
        const { dir } = config();
        const n = path.basename(String(name || ""));
        if (!FOLDER_RE.test(n)) throw new HttpError2(400, "That is not a backup folder made by BillBox.");
        const f = path.join(dir, n);
        if (!fs.existsSync(f)) throw new HttpError2(404, "That backup is already gone.");
        fs.rmSync(f, { recursive: true, force: true });
        return { deleted: n };
      }
      function listBackups() {
        const { dir } = config();
        if (!fs.existsSync(dir)) return [];
        return fs.readdirSync(dir).filter((f) => FOLDER_RE.test(f)).sort().reverse().map((f) => {
          let files = 0, bytes = 0, created = null, companies = [];
          try {
            const m = JSON.parse(fs.readFileSync(path.join(dir, f, "manifest.json"), "utf8"));
            files = m.files.length;
            bytes = m.files.reduce((a, x) => a + x.bytes, 0);
            created = m.created;
            companies = m.files.filter((x) => x.company_id).map((x) => x.company);
          } catch {
          }
          return { name: f, files, bytes, created, companies };
        });
      }
      function tick(now = /* @__PURE__ */ new Date()) {
        const c = config();
        if (!c.enabled) return null;
        const hhmm = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
        const today = now.toLocaleDateString("en-CA");
        const lastDay = c.last_run ? new Date(c.last_run).toLocaleDateString("en-CA") : "";
        if (hhmm >= c.time && lastDay !== today) {
          try {
            const r = backupNow({ reason: "scheduled" });
            require_drive().afterBackup(r.folder);
            return r;
          } catch (e) {
            console.error("Scheduled backup failed:", e.message);
          }
        }
        return null;
      }
      function startScheduler() {
        const t = setInterval(() => tick(), 60 * 1e3);
        t.unref();
        setTimeout(() => tick(), 5e3).unref();
      }
      function checkFile(file) {
        let chk;
        try {
          chk = new Database(file, { readonly: true });
          const v = Object.values(chk.prepare("PRAGMA integrity_check").get())[0];
          if (v !== "ok") throw new HttpError2(400, `${path.basename(file)} is damaged (${v}). Nothing was restored.`);
          if (!chk.prepare("SELECT 1 FROM sqlite_master WHERE name='invoices'").get()) throw new HttpError2(400, `${path.basename(file)} is not a BillBox company file.`);
        } catch (e) {
          if (e instanceof HttpError2) throw e;
          throw new HttpError2(400, `${path.basename(file)} cannot be opened as a database. Nothing was restored.`);
        } finally {
          if (chk) chk.close();
        }
      }
      function swapIn(src, row) {
        const dest = path.join(db2.dataDir, row.file);
        db2.closeCompany(row.id);
        const tmp = dest + ".restoring";
        fs.copyFileSync(src, tmp);
        for (const ext of ["-wal", "-shm"]) fs.rmSync(dest + ext, { force: true });
        fs.renameSync(tmp, dest);
      }
      var norm = (n) => String(n || "").trim().replace(/\s+/g, " ").toLowerCase();
      function rowForCompany(name, { create = true, fy = null } = {}) {
        const wanted = norm(name);
        const hit = reg.prepare("SELECT * FROM companies").all().find((c) => norm(c.name) === wanted && (c.fy || null) === (fy || null));
        if (hit) {
          if (!hit.active) reg.prepare("UPDATE companies SET active=1 WHERE id=?").run(hit.id);
          return hit;
        }
        if (!create) return null;
        const id = db2.createCompany({ name: String(name || "Restored company").trim(), fy: fy || null });
        return reg.prepare("SELECT * FROM companies WHERE id=?").get(id);
      }
      function companyInFile(file) {
        let d;
        try {
          d = new Database(file, { readonly: true });
          const r = d.prepare("SELECT value FROM settings WHERE key='company_name'").get();
          const y = d.prepare("SELECT value FROM settings WHERE key='books_fy'").get();
          return { name: r && r.value ? String(r.value) : null, fy: y && y.value ? String(y.value) : null };
        } catch {
          return { name: null, fy: null };
        } finally {
          if (d) d.close();
        }
      }
      function mergeInto(row, file) {
        const dst = db2.openCompany(row.id);
        const src = new Database(file, { readonly: true });
        const stats = { added: {}, skipped: {}, conflicts: [] };
        const add = (k) => {
          stats.added[k] = (stats.added[k] || 0) + 1;
        };
        const skip = (k) => {
          stats.skipped[k] = (stats.skipped[k] || 0) + 1;
        };
        const all = (t) => {
          try {
            return src.prepare(`SELECT * FROM ${t}`).all();
          } catch {
            return [];
          }
        };
        const cols = (t) => dst.prepare(`PRAGMA table_info(${t})`).all().map((c) => c.name).filter((c) => c !== "id");
        const insert = (t, rec) => {
          const cs = cols(t).filter((c) => rec[c] !== void 0);
          const r = dst.prepare(`INSERT INTO ${t}(${cs.join(",")}) VALUES(${cs.map(() => "?").join(",")})`).run(...cs.map((c) => rec[c]));
          return Number(r.lastInsertRowid);
        };
        const key = (v) => norm(v);
        const idx = (t, f) => new Map(dst.prepare(`SELECT id,${f} v FROM ${t}`).all().map((r) => [key(r.v), r.id]));
        const byName = (table, mapOut) => {
          const have = idx(table, "name");
          for (const r of all(table)) {
            let id = have.get(key(r.name));
            if (id) skip(table);
            else {
              id = insert(table, { ...r, ...mapOut ? mapOut(r) : {} });
              have.set(key(r.name), id);
              add(table);
            }
            maps[table].set(r.id, id);
          }
        };
        const maps = { categories: /* @__PURE__ */ new Map(), salesmen: /* @__PURE__ */ new Map(), routes: /* @__PURE__ */ new Map(), parties: /* @__PURE__ */ new Map(), items: /* @__PURE__ */ new Map(), batches: /* @__PURE__ */ new Map(), invoices: /* @__PURE__ */ new Map(), purchases: /* @__PURE__ */ new Map(), debit_notes: /* @__PURE__ */ new Map() };
        const newParties = /* @__PURE__ */ new Set();
        const m = (name, id) => id == null ? null : maps[name].get(id) ?? null;
        try {
          dst.transaction(() => {
            byName("categories");
            byName("salesmen");
            byName("routes", (r) => ({ salesman_id: m("salesmen", r.salesman_id) }));
            const haveP = new Map(dst.prepare("SELECT id,name,type FROM parties").all().map((r) => [key(r.name) + "|" + (r.type === "SUPPLIER" ? "S" : "C"), r.id]));
            for (const r of all("parties")) {
              const k = key(r.name) + "|" + (r.type === "SUPPLIER" ? "S" : "C");
              let id = haveP.get(k);
              if (id) skip("parties");
              else {
                id = insert("parties", { ...r, route_id: m("routes", r.route_id) });
                haveP.set(k, id);
                newParties.add(id);
                add("parties");
              }
              maps.parties.set(r.id, id);
            }
            const haveI = idx("items", "name");
            for (const r of all("items")) {
              let id = haveI.get(key(r.name));
              if (id) skip("items");
              else {
                id = insert("items", { ...r, category_id: m("categories", r.category_id) });
                haveI.set(key(r.name), id);
                add("items");
              }
              maps.items.set(r.id, id);
            }
            const haveB = new Map(dst.prepare("SELECT id,item_id,batch_no FROM batches").all().map((r) => [r.item_id + "|" + key(r.batch_no), r.id]));
            for (const r of all("batches")) {
              const itemId = m("items", r.item_id);
              if (!itemId) continue;
              const k = itemId + "|" + key(r.batch_no);
              let id = haveB.get(k);
              if (id) skip("batches");
              else {
                id = insert("batches", { ...r, item_id: itemId });
                haveB.set(k, id);
                add("batches");
              }
              maps.batches.set(r.id, id);
            }
            const haveS = new Set(dst.prepare("SELECT item_id,type,buy_qty,free_qty,percent FROM schemes").all().map((r) => [r.item_id, r.type, r.buy_qty, r.free_qty, r.percent].join("|")));
            for (const r of all("schemes")) {
              const itemId = m("items", r.item_id);
              const k = [itemId, r.type, r.buy_qty, r.free_qty, r.percent].join("|");
              if (!itemId || haveS.has(k)) {
                skip("schemes");
                continue;
              }
              insert("schemes", { ...r, item_id: itemId });
              haveS.add(k);
              add("schemes");
            }
            const document = (table, noCol, lineTable, fk, convert, lineConvert, label) => {
              const have = new Map(dst.prepare(`SELECT id,${noCol} no,date,total FROM ${table}`).all().map((r) => [r.no, r]));
              const lines = all(lineTable);
              for (const r of all(table)) {
                const cur = have.get(r[noCol]);
                if (cur) {
                  if (cur.date === r.date && Math.abs(cur.total - r.total) < 5e-3) skip(table);
                  else {
                    stats.conflicts.push(`${label} ${r[noCol]} exists here with different details; left as it is`);
                    skip(table);
                  }
                  maps[table].set(r.id, cur.id);
                  continue;
                }
                const id = insert(table, convert(r));
                maps[table].set(r.id, id);
                add(table);
                for (const l of lines.filter((x) => x[fk] === r.id)) {
                  const itemId = m("items", l.item_id);
                  if (itemId) insert(lineTable, { ...l, [fk]: id, ...lineConvert(l, itemId) });
                }
              }
            };
            document(
              "invoices",
              "invoice_no",
              "invoice_lines",
              "invoice_id",
              (r) => ({ ...r, party_id: m("parties", r.party_id), salesman_id: m("salesmen", r.salesman_id) }),
              (l, itemId) => ({ item_id: itemId, batch_id: m("batches", l.batch_id) }),
              "Bill"
            );
            document(
              "purchases",
              "purchase_no",
              "purchase_lines",
              "purchase_id",
              (r) => ({ ...r, party_id: m("parties", r.party_id) }),
              (l, itemId) => ({ item_id: itemId, batch_id: m("batches", l.batch_id) }),
              "Purchase"
            );
            {
              const have = new Map(dst.prepare("SELECT id,note_no no,date,total FROM debit_notes").all().map((r) => [r.no, r]));
              const lines = all("debit_note_lines"), stock = all("debit_note_stock");
              for (const r of all("debit_notes")) {
                const cur = have.get(r.note_no);
                if (cur) {
                  if (cur.date === r.date && Math.abs(cur.total - r.total) < 5e-3) skip("debit_notes");
                  else {
                    stats.conflicts.push(`Debit note ${r.note_no} exists here with different details; left as it is`);
                    skip("debit_notes");
                  }
                  maps.debit_notes.set(r.id, cur.id);
                  continue;
                }
                const pid = m("parties", r.party_id);
                if (!pid) continue;
                const id = insert("debit_notes", { ...r, party_id: pid, purchase_id: m("purchases", r.purchase_id) });
                maps.debit_notes.set(r.id, id);
                add("debit_notes");
                for (const l of lines.filter((x) => x.note_id === r.id)) {
                  const itemId = m("items", l.item_id);
                  if (!itemId) continue;
                  const lid = insert("debit_note_lines", { ...l, note_id: id, item_id: itemId, batch_id: m("batches", l.batch_id) });
                  for (const st of stock.filter((x) => x.line_id === l.id)) {
                    const b = m("batches", st.batch_id);
                    if (b) insert("debit_note_stock", { ...st, line_id: lid, batch_id: b });
                  }
                }
              }
            }
            dst.exec("DELETE FROM invoice_lines WHERE batch_id IS NULL");
            const voucher = (table, noCol, extra) => {
              const have = new Set(dst.prepare(`SELECT ${noCol} no FROM ${table}`).all().map((r) => r.no));
              for (const r of all(table)) {
                if (have.has(r[noCol])) {
                  skip(table);
                  continue;
                }
                const pid = m("parties", r.party_id);
                if (!pid) continue;
                insert(table, { ...r, party_id: pid, salesman_id: m("salesmen", r.salesman_id), ...extra(r) });
                have.add(r[noCol]);
                add(table);
              }
            };
            voucher("receipts", "receipt_no", (r) => ({ invoice_id: m("invoices", r.invoice_id) }));
            voucher("payments", "voucher_no", (r) => ({ purchase_id: m("purchases", r.purchase_id) }));
            const haveL = new Set(dst.prepare("SELECT party_id,type,IFNULL(ref_no,'') r,date,debit,credit FROM ledger").all().map((r) => [r.party_id, r.type, r.r, r.date, r.debit, r.credit].join("|")));
            for (const r of all("ledger")) {
              const pid = m("parties", r.party_id);
              if (!pid) continue;
              const k = [pid, r.type, r.ref_no || "", r.date, r.debit, r.credit].join("|");
              if (haveL.has(k) || !newParties.has(pid) && r.type === "OPENING") continue;
              insert("ledger", { ...r, party_id: pid });
              haveL.add(k);
              add("ledger");
            }
            for (const c of all("counters")) {
              dst.prepare("INSERT INTO counters(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=MAX(value,excluded.value)").run(c.key, c.value);
            }
          })();
        } finally {
          src.close();
        }
        return stats;
      }
      function restore({ name, folder, file, company_id, mode } = {}) {
        const merge = mode === "merge";
        const merged = [];
        const { dir } = config();
        let restored = [];
        if (file) {
          if (!path.isAbsolute(file) || !fs.existsSync(file) || !fs.statSync(file).isFile()) throw new HttpError2(400, "Choose a company backup file (.db).");
          checkFile(file);
          const inFile = companyInFile(file);
          const own = inFile.name;
          const row = own ? rowForCompany(own, { create: false, fy: inFile.fy }) || null : null;
          const target = row || reg.prepare("SELECT * FROM companies WHERE id=?").get(Number(company_id) || db2.firstCompanyId());
          if (!target) throw new HttpError2(404, "Company not found");
          backupNow({ reason: "before-restore" });
          if (merge) merged.push({ company: target.name, ...mergeInto(target, file) });
          else swapIn(file, target);
          restored.push(target.name);
        } else {
          const f = folder || name && path.join(dir, path.basename(name));
          if (!f || !path.isAbsolute(f) || !fs.existsSync(f) || !fs.statSync(f).isDirectory()) throw new HttpError2(400, "Choose a backup folder (one that contains manifest.json).");
          let manifest;
          try {
            manifest = JSON.parse(fs.readFileSync(path.join(f, "manifest.json"), "utf8"));
          } catch {
            throw new HttpError2(400, "That folder has no readable manifest.json, so it is not a BillBox backup.");
          }
          const items = manifest.files.filter((x) => x.company_id);
          if (!items.length) throw new HttpError2(400, "That backup contains no company data.");
          for (const x of items) {
            const p = path.join(f, x.file);
            if (!fs.existsSync(p)) throw new HttpError2(400, `${x.file} is missing from the backup folder. Nothing was restored.`);
            if (x.sha256 && sha256(p) !== x.sha256) throw new HttpError2(400, `${x.file} does not match its checksum (it was changed or damaged). Nothing was restored.`);
            checkFile(p);
          }
          let bReg = null;
          const regFile = path.join(f, "registry.db");
          if (fs.existsSync(regFile)) bReg = new Database(regFile, { readonly: true });
          try {
            backupNow({ reason: "before-restore" });
            for (const x of items) {
              const row = rowForCompany(
                x.company || bReg && (bReg.prepare("SELECT name FROM companies WHERE id=?").get(x.company_id) || {}).name,
                { fy: x.fy || companyInFile(path.join(f, x.file)).fy }
              );
              if (merge) merged.push({ company: row.name, ...mergeInto(row, path.join(f, x.file)) });
              else swapIn(path.join(f, x.file), row);
              restored.push(row.name);
            }
          } finally {
            if (bReg) bReg.close();
          }
        }
        for (const id of reg.prepare("SELECT id FROM companies").all().map((r) => r.id)) db2.openCompany(id);
        return { restored, mode: merge ? "merge" : "replace", merged };
      }
      module.exports = { deleteBackup, restore, config, saveConfig, backupNow, listBackups, tick, startScheduler };
    }
  });

  // ../../backend/src/utils/gst.js
  var require_gst = __commonJS({
    "../../backend/src/utils/gst.js"(exports, module) {
      init_globals();
      var r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
      function splitTax(taxable, rate, intra) {
        const tax = r2(taxable * rate / 100);
        if (intra) {
          const c = r2(tax / 2);
          return { cgst: c, sgst: r2(tax - c), igst: 0 };
        }
        return { cgst: 0, sgst: 0, igst: tax };
      }
      module.exports = { r2, splitTax };
    }
  });

  // ../../backend/src/services/category.js
  var require_category = __commonJS({
    "../../backend/src/services/category.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var RULES = [
        ["Namkeen & Snacks", /\b(all\s*time\s*mix|bikano|namkeen|bhujia|mixture|mixt|chips|wafer|papad|kurkure|puffs?|chakli|sev|moong\s*dal|peanut|katori|ringz?|cheese\s*ball|munchy|crunchy|nachos|popcorn|chivda|aloo|khatta\s*meetha|lachha|navratan|tadka|chatax|snack)/i],
        ["Biscuits & Cookies", /\b(biscuit|cookie|cracker|rusk|marie|glucose|bourbon|cream\s*roll)/i],
        ["Noodles & Pasta", /\b(noodle|maggi|pasta|macaroni|vermicelli|yippee|chowmein)/i],
        ["Beverages", /\b(cola|pepsi|coke|soda|juice|drink|water|lemonade|energy|squash|sharbat|tea|coffee|frooti|maaza|slice|sprite|fanta|thums)/i],
        ["Dairy", /\b(milk|curd|dahi|paneer|butter|cheese|ghee|cream|lassi|buttermilk)/i],
        ["Chocolates & Confectionery", /\b(chocolate|candy|toffee|lollipop|gum|mint|eclairs?|jelly|cadbury|dairy\s*milk|kitkat)/i],
        ["Staples & Grains", /\b(rice|atta|flour|maida|suji|rava|dal\b|pulses?|poha|besan|sugar|salt|wheat|oats|cornflakes?|muesli)/i],
        ["Oils & Ghee", /\b(oil|refined|mustard\s*oil|sunflower|vanaspati)/i],
        ["Spices & Masala", /\b(masala|spice|turmeric|haldi|chilli|mirch|jeera|coriander|dhaniya|garam)/i],
        ["Sauces & Spreads", /\b(ketchup|sauce|jam|mayonnaise|spread|pickle|achar|vinegar|chutney)/i],
        ["Personal Care", /\b(soap|shampoo|toothpaste|toothbrush|face\s*wash|cream|lotion|deodorant|deo|talc|powder|hair|razor|sanitary|napkin|facewash|oil\s*hair|conditioner|handwash)/i],
        ["Home Care", /\b(detergent|dishwash|cleaner|phenyl|bleach|harpic|vim|surf|ariel|rin\b|wheel|floor|toilet|mop|scrub|freshener|agarbatti|incense|mosquito|coil)/i],
        ["Stationery & General", /\b(pen|pencil|notebook|battery|bulb|candle|match)/i]
      ];
      var PINNED = [
        [/all\s*time\s*mix/i, "Namkeen & Snacks"]
      ];
      function pinned(name) {
        for (const [re, cat] of PINNED) if (re.test(name || "")) return cat;
        return null;
      }
      var cache = /* @__PURE__ */ new Map();
      function cleanQuery(name) {
        return String(name || "").replace(/\(.*?\)/g, " ").replace(/\bMRP\b.*$/i, " ").replace(/\d+\s*[xX*]\s*\d+/g, " ").replace(/\b\d+(\.\d+)?\s*(g|gm|kg|ml|ltr|l|pkt|pcs)\b/gi, " ").replace(/[^A-Za-z ]+/g, " ").replace(/\s+/g, " ").trim().toLowerCase();
      }
      function byRules(text) {
        for (const [cat, re] of RULES) if (re.test(text)) return cat;
        return null;
      }
      async function fromInternet(query) {
        if (!query || typeof fetch !== "function") return null;
        try {
          const url = "https://world.openfoodfacts.org/cgi/search.pl?search_simple=1&action=process&json=1&page_size=6&fields=product_name,categories&search_terms=" + encodeURIComponent(query);
          const r = await fetch(url, { signal: AbortSignal.timeout(4e3), headers: { "User-Agent": "DistributorPro/3 (local desktop app)" } });
          if (!r.ok) return null;
          const j = await r.json();
          const cats = (j.products || []).map((p) => String(p.categories || "")).filter(Boolean);
          if (!cats.length) return null;
          for (const c of cats) {
            const m = byRules(c);
            if (m) return m;
          }
          const first = cats[0].split(",").map((x) => x.trim()).filter(Boolean)[0];
          return first ? first.replace(/^[a-z]{2}:/i, "").slice(0, 40) : null;
        } catch (_) {
          return null;
        }
      }
      async function guessCategory(itemName, { online = true } = {}) {
        const pin = pinned(itemName);
        if (pin) return { name: pin, source: "rules" };
        const q = cleanQuery(itemName);
        const key = q.split(" ").slice(0, 3).join(" ");
        if (cache.has(key)) return cache.get(key);
        let out = { name: byRules(itemName) || byRules(q), source: "rules" };
        if (!out.name && online) {
          const n = await fromInternet(q);
          out = n ? { name: n, source: "internet" } : { name: null };
        }
        if (!out.name) out = { name: null };
        if (out.name) cache.set(key, out);
        return out;
      }
      function ensureCategory(name) {
        if (!name) return null;
        const row = db2.prepare("SELECT id FROM categories WHERE lower(name)=lower(?)").get(name);
        if (row) return row.id;
        return Number(db2.prepare("INSERT INTO categories(name) VALUES(?)").run(name).lastInsertRowid);
      }
      module.exports = { pinned, guessCategory, ensureCategory, cleanQuery, byRules };
    }
  });

  // ../../backend/src/services/autoCreate.js
  var require_autoCreate = __commonJS({
    "../../backend/src/services/autoCreate.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { r2 } = require_gst();
      var { guessCategory, ensureCategory } = require_category();
      var BOX_UNIT = /^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$/i;
      var tidy = (s) => String(s || "").replace(/\s+/g, " ").trim();
      async function createMissing2(parsed, { online = true } = {}) {
        const warnings = parsed.warnings;
        const lines = parsed.lines;
        const missing = /* @__PURE__ */ new Map();
        for (const l of lines) if (!l.item_id) {
          const k = tidy(l.description).toLowerCase();
          if (k && !missing.has(k)) missing.set(k, l);
        }
        const cats = /* @__PURE__ */ new Map();
        const keys = [...missing.keys()];
        for (let i2 = 0; i2 < keys.length; i2 += 5) {
          await Promise.all(keys.slice(i2, i2 + 5).map(async (k) => {
            cats.set(k, await guessCategory(missing.get(k).description, { online }));
          }));
        }
        let createdItems = 0, createdSupplier = false, noBox = 0, noRate = 0, internetCats = 0;
        db2.transaction(() => {
          const sup = parsed.supplier;
          if (sup && sup.name && !sup.matched_party_id) {
            let p = sup.gstin ? db2.prepare("SELECT id,name FROM parties WHERE upper(gstin)=? AND active=1").get(String(sup.gstin).toUpperCase()) : null;
            if (!p) p = db2.prepare("SELECT id,name FROM parties WHERE lower(name)=lower(?) AND active=1").get(tidy(sup.name));
            if (!p) {
              const id = Number(db2.prepare(
                `INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,fssai,pan,email,type,price_tier)
           VALUES(?,?,?,?,?,?,?,?,?,?,'SUPPLIER','WHOLESALE')`
              ).run(
                tidy(sup.name),
                sup.gstin || null,
                sup.state_code || "09",
                sup.phone || null,
                sup.tel || null,
                (sup.mobiles || []).join(", ") || null,
                sup.address || null,
                sup.fssai || null,
                sup.pan || null,
                sup.email || null
              ).lastInsertRowid);
              p = { id, name: tidy(sup.name) };
              createdSupplier = true;
            }
            sup.matched_party_id = p.id;
            sup.matched_name = p.name;
            sup.created = createdSupplier;
          }
          if (sup && sup.matched_party_id && !createdSupplier) {
            const fill = db2.prepare(`UPDATE parties SET gstin=COALESCE(NULLIF(gstin,''),?), phone=COALESCE(NULLIF(phone,''),?), tel=COALESCE(NULLIF(tel,''),?),
        mobiles=COALESCE(NULLIF(mobiles,''),?), address=COALESCE(NULLIF(address,''),?), fssai=COALESCE(NULLIF(fssai,''),?), pan=COALESCE(NULLIF(pan,''),?),
        email=COALESCE(NULLIF(email,''),?) WHERE id=?`);
            fill.run(
              sup.gstin || null,
              sup.phone || null,
              sup.tel || null,
              (sup.mobiles || []).join(", ") || null,
              sup.address || null,
              sup.fssai || null,
              sup.pan || null,
              sup.email || null,
              sup.matched_party_id
            );
          }
          const made = /* @__PURE__ */ new Map();
          for (const l of lines) {
            if (l.item_id) continue;
            const name = tidy(l.description), k = name.toLowerCase();
            if (!name) continue;
            let it = made.get(k) || db2.prepare("SELECT id,name FROM items WHERE active=1 AND lower(name)=lower(?)").get(name);
            if (!it) {
              const ppb = BOX_UNIT.test(l.unit || "") ? l.pcs_per_box || 1 : l.pcs_per_box || 1;
              if (BOX_UNIT.test(l.unit || "") && !l.pcs_per_box) noBox++;
              const gst = l.gst_rate === null || l.gst_rate === void 0 ? 18 : l.gst_rate;
              if (l.gst_rate === null || l.gst_rate === void 0) noRate++;
              const perPiece = BOX_UNIT.test(l.unit || "") ? r2(l.rate / ppb) : l.rate;
              const mrp = l.mrp || 0;
              const sell = mrp ? r2(mrp / (1 + gst / 100)) : 0;
              const c = cats.get(k);
              const catId = c && c.name ? ensureCategory(c.name) : null;
              if (c && c.source === "internet") internetCats++;
              const id = Number(db2.prepare(
                `INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box)
           VALUES(?,?,?,?,'PCS',?,?,?,?,?)`
              ).run(name, catId, l.hsn || null, gst, mrp, sell, sell, perPiece, ppb).lastInsertRowid);
              it = { id, name };
              made.set(k, it);
              createdItems++;
              l.category = c && c.name ? c.name : null;
            }
            l.item_id = it.id;
            l.item_name = it.name;
            l.match_confidence = 1;
            l.created = true;
          }
        })();
        const i = warnings.findIndex((w) => /not matched to your stock list/.test(w));
        if (i >= 0) warnings.splice(i, 1);
        if (createdSupplier) warnings.unshift(`Supplier "${parsed.supplier.name}" was added to Parties.`);
        if (createdItems) warnings.unshift(`${createdItems} new item${createdItems > 1 ? "s" : ""} added to Stock with HSN, GST rate, pieces per box and category taken from the bill${internetCats ? ` (${internetCats} categories found on the internet)` : ""}. Selling prices were set to MRP without GST; adjust them in Stock.`);
        if (noBox) warnings.push(`${noBox} item(s) are bought in boxes but the pieces per box were not in the name; set it in Stock.`);
        if (noRate) warnings.push(`${noRate} item(s) had no GST rate on the bill; 18% was assumed. Check it in Stock.`);
        parsed.created = { items: createdItems, supplier: createdSupplier };
        return parsed;
      }
      module.exports = { createMissing: createMissing2 };
    }
  });

  // ../../backend/src/utils/schemes.js
  var require_schemes = __commonJS({
    "../../backend/src/utils/schemes.js"(exports, module) {
      init_globals();
      function applySchemes(qty, schemes) {
        let freeQty = 0;
        let discPct = 0;
        const applied = [];
        for (const s of schemes) {
          if (s.type === "FREE_QTY" && s.buy_qty > 0 && qty >= s.buy_qty) {
            const f = Math.floor(qty / s.buy_qty) * s.free_qty;
            if (f > freeQty) {
              freeQty = f;
              applied.push(`Buy ${s.buy_qty} get ${s.free_qty} free`);
            }
          } else if (s.type === "PERCENT" && qty >= s.buy_qty && s.percent > discPct) {
            discPct = s.percent;
            applied.push(`${s.percent}% off on ${s.buy_qty}+`);
          }
        }
        return { freeQty, discPct, applied };
      }
      module.exports = { applySchemes };
    }
  });

  // ../../backend/src/utils/words.js
  var require_words = __commonJS({
    "../../backend/src/utils/words.js"(exports, module) {
      init_globals();
      var ones = [
        "",
        "One",
        "Two",
        "Three",
        "Four",
        "Five",
        "Six",
        "Seven",
        "Eight",
        "Nine",
        "Ten",
        "Eleven",
        "Twelve",
        "Thirteen",
        "Fourteen",
        "Fifteen",
        "Sixteen",
        "Seventeen",
        "Eighteen",
        "Nineteen"
      ];
      var tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
      var two = (n) => n < 20 ? ones[n] : tens[Math.floor(n / 10)] + (n % 10 ? " " + ones[n % 10] : "");
      var three = (n) => (n >= 100 ? ones[Math.floor(n / 100)] + " Hundred" + (n % 100 ? " " : "") : "") + (n % 100 ? two(n % 100) : "");
      function words(n) {
        if (n === 0) return "Zero";
        const parts = [];
        const cr = Math.floor(n / 1e7), lk = Math.floor(n / 1e5) % 100, th = Math.floor(n / 1e3) % 100, rest = n % 1e3;
        if (cr) parts.push(three(cr) + " Crore");
        if (lk) parts.push(two(lk) + " Lakh");
        if (th) parts.push(two(th) + " Thousand");
        if (rest) parts.push(three(rest));
        return parts.join(" ");
      }
      var rupeesInWords = (total) => {
        const paise = Math.round(Math.abs(total) * 100) % 100;
        return paise ? `Rupees ${words(Math.floor(total))} and ${words(paise)} Paise Only` : `Rupees ${words(Math.round(total))} Only`;
      };
      module.exports = { words, rupeesInWords };
    }
  });

  // ../../backend/src/services/billing.js
  var require_billing = __commonJS({
    "../../backend/src/services/billing.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { r2, splitTax } = require_gst();
      var { applySchemes } = require_schemes();
      var { today, nextNo, HttpError: HttpError2 } = require_misc();
      var { rupeesInWords } = require_words();
      var settings2 = () => {
        const o = {};
        for (const r of db2.prepare("SELECT key,value FROM settings").all()) o[r.key] = r.value;
        return o;
      };
      var partyBalance = (id) => db2.prepare("SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=?").get(id).b;
      function priceFor(item, tier) {
        if (tier === "WHOLESALE") return item.wholesale_price > 0 ? item.wholesale_price : item.retail_price;
        if (tier === "MRP") return item.mrp / (1 + item.gst_rate / 100);
        return item.retail_price;
      }
      function buildInvoice(input) {
        if (!Array.isArray(input.lines) || !input.lines.length) throw new HttpError2(400, "Add at least one item to the bill");
        const co = settings2();
        const party = input.party_id ? db2.prepare("SELECT * FROM parties WHERE id=?").get(input.party_id) : null;
        if (input.party_id && !party) throw new HttpError2(404, "Party not found");
        const tier = party ? party.price_tier : "RETAIL";
        const intra = !party || !party.state_code || party.state_code === co.state_code;
        const date = input.date || today();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new HttpError2(400, "Bill date must be YYYY-MM-DD");
        const reserved = /* @__PURE__ */ new Map();
        const rows = [];
        const display = [];
        input.lines.forEach((ln, idx) => {
          const item = db2.prepare("SELECT * FROM items WHERE id=? AND active=1").get(ln.item_id);
          if (!item) throw new HttpError2(404, `Item ${ln.item_id} not found`);
          const ppb = Math.max(1, parseInt(item.pcs_per_box, 10) || 1);
          const hasUnits = ln.boxes !== void 0 || ln.pcs !== void 0;
          const qty = hasUnits ? Math.max(0, parseInt(ln.boxes, 10) || 0) * ppb + Math.max(0, parseInt(ln.pcs, 10) || 0) : parseInt(ln.qty, 10);
          if (!(qty > 0)) throw new HttpError2(400, `Enter a quantity for ${item.name}`);
          const rate = ln.rate !== void 0 && ln.rate !== null && ln.rate !== "" ? Number(ln.rate) : priceFor(item, tier);
          const manualPct = Math.min(100, Math.max(0, Number(ln.disc_pct) || 0));
          const schemes = db2.prepare(
            `SELECT * FROM schemes WHERE item_id=? AND active=1
       AND (valid_from IS NULL OR valid_from<=?) AND (valid_to IS NULL OR valid_to>=?)`
          ).all(item.id, date, date);
          const sc = applySchemes(qty, schemes);
          const pct = Math.min(100, manualPct + sc.discPct);
          const need = qty + sc.freeQty;
          const batches = db2.prepare("SELECT * FROM batches WHERE item_id=? AND qty>0 AND exp_date>=? ORDER BY exp_date, id").all(item.id, date);
          let remaining = need;
          let paidLeft = qty;
          for (const b of batches) {
            if (remaining <= 0) break;
            const avail = b.qty - (reserved.get(b.id) || 0);
            if (avail <= 0) continue;
            const take = Math.min(avail, remaining);
            reserved.set(b.id, (reserved.get(b.id) || 0) + take);
            remaining -= take;
            const paid = Math.min(take, paidLeft);
            const free = take - paid;
            paidLeft -= paid;
            const gross = r2(rate * paid);
            const discAmt = r2(gross * pct / 100);
            const taxable2 = r2(gross - discAmt);
            const tax = splitTax(taxable2, item.gst_rate, intra);
            rows.push({
              line_index: idx,
              item_id: item.id,
              item_name: item.name,
              hsn: item.hsn,
              batch_id: b.id,
              batch_no: b.batch_no,
              exp_date: b.exp_date,
              qty: paid,
              free_qty: free,
              rate,
              disc_pct: pct,
              manual_pct: manualPct,
              disc_amt: discAmt,
              gross,
              taxable: taxable2,
              gst_rate: item.gst_rate,
              ...tax,
              amount: r2(taxable2 + tax.cgst + tax.sgst + tax.igst)
            });
          }
          if (remaining > 0) throw new HttpError2(409, `Not enough stock for ${item.name}: short by ${remaining}`, "NO_STOCK");
          const mine = rows.filter((r) => r.line_index === idx);
          const s = (k) => r2(mine.reduce((a, r) => a + r[k], 0));
          display.push({
            line_index: idx,
            item_id: item.id,
            item_name: item.name,
            unit: item.unit,
            qty,
            pcs_per_box: ppb,
            boxes: Math.floor(qty / ppb),
            pcs: qty % ppb,
            free_qty: sc.freeQty,
            rate,
            disc_pct: pct,
            manual_pct: manualPct,
            schemes: sc.applied,
            gst_rate: item.gst_rate,
            disc_amt: s("disc_amt"),
            taxable: s("taxable"),
            tax: r2(s("cgst") + s("sgst") + s("igst")),
            amount: s("amount"),
            batches: mine.map((r) => `${r.batch_no} \xD7${r.qty + r.free_qty}`).join(", ")
          });
        });
        const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
        const taxable = sum("taxable");
        const cgst = sum("cgst"), sgst = sum("sgst"), igst = sum("igst");
        const grand = r2(taxable + cgst + sgst + igst);
        const total = co.bill_round === "0" ? grand : Math.round(grand);
        return {
          date,
          party,
          tier,
          intra,
          rows,
          display,
          subtotal: sum("gross"),
          discount: sum("disc_amt"),
          taxable,
          cgst,
          sgst,
          igst,
          round_off: r2(total - grand),
          total
        };
      }
      function writeInvoice(input, existing) {
        const inv = buildInvoice(input);
        const party = inv.party;
        const mode = String(input.pay_mode || "CASH").toUpperCase();
        let paid = input.paid_amount !== void 0 && input.paid_amount !== null && input.paid_amount !== "" ? Number(input.paid_amount) : mode === "CREDIT" ? 0 : inv.total;
        if (!Number.isFinite(paid)) throw new HttpError2(400, "Paid amount is not a number");
        paid = r2(Math.min(Math.max(paid, 0), inv.total));
        if (!party && paid < inv.total) throw new HttpError2(400, "Walk-in sales must be paid in full");
        if (party && party.credit_limit > 0 && !input.override_credit) {
          const after = r2(partyBalance(party.id) + inv.total - paid);
          if (after > party.credit_limit) {
            throw new HttpError2(409, `Credit limit exceeded: dues would be \u20B9${after} against a limit of \u20B9${party.credit_limit}`, "CREDIT_LIMIT");
          }
        }
        const vals = [
          inv.date,
          party ? party.id : null,
          input.salesman_id || null,
          (input.sale_type || "COUNTER").toUpperCase(),
          mode,
          inv.subtotal,
          inv.discount,
          inv.taxable,
          inv.cgst,
          inv.sgst,
          inv.igst,
          inv.round_off,
          inv.total,
          paid
        ];
        let id, invoice_no;
        if (existing) {
          id = existing.id;
          invoice_no = existing.invoice_no;
          db2.prepare(`UPDATE invoices SET date=?,party_id=?,salesman_id=?,sale_type=?,pay_mode=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,paid=?,printed=0 WHERE id=?`).run(...vals, id);
        } else {
          invoice_no = nextNo("INV", inv.date);
          id = Number(db2.prepare(
            `INSERT INTO invoices(date,party_id,salesman_id,sale_type,pay_mode,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,invoice_no)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
          ).run(...vals, invoice_no).lastInsertRowid);
        }
        const insLine = db2.prepare(
          `INSERT INTO invoice_lines(invoice_id,item_id,batch_id,qty,free_qty,rate,disc_pct,disc_amt,taxable,gst_rate,cgst,sgst,igst,amount,manual_disc)
     VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
        );
        const dec = db2.prepare("UPDATE batches SET qty = qty - ? WHERE id = ? AND qty >= ?");
        for (const r of inv.rows) {
          insLine.run(id, r.item_id, r.batch_id, r.qty, r.free_qty, r.rate, r.disc_pct, r.disc_amt, r.taxable, r.gst_rate, r.cgst, r.sgst, r.igst, r.amount, r.manual_pct);
          const units = r.qty + r.free_qty;
          if (dec.run(units, r.batch_id, units).changes !== 1) throw new HttpError2(409, `Stock changed for ${r.item_name}, please retry`, "NO_STOCK");
        }
        if (party) {
          const lg = db2.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)");
          lg.run(party.id, inv.date, "INVOICE", invoice_no, inv.total, 0, `Sale ${invoice_no}`);
          if (paid > 0) {
            const receipt_no = existing && existing.receipt_no || nextNo("RCT", inv.date);
            db2.prepare("INSERT INTO receipts(receipt_no,date,party_id,salesman_id,invoice_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?,?)").run(receipt_no, inv.date, party.id, input.salesman_id || null, id, mode, paid, `Paid at billing ${invoice_no}`);
            lg.run(party.id, inv.date, "RECEIPT", receipt_no, 0, paid, `Received at billing (${mode})`);
          }
        }
        return id;
      }
      var createInvoice = db2.transaction((input) => writeInvoice(input));
      var updateInvoice = db2.transaction((id, input) => {
        const old = db2.prepare("SELECT * FROM invoices WHERE id=?").get(id);
        if (!old) throw new HttpError2(404, "Invoice not found");
        for (const l of db2.prepare("SELECT batch_id, qty, free_qty FROM invoice_lines WHERE invoice_id=?").all(id))
          db2.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?").run(l.qty + l.free_qty, l.batch_id);
        db2.prepare("DELETE FROM invoice_lines WHERE invoice_id=?").run(id);
        const rc = db2.prepare("SELECT receipt_no FROM receipts WHERE invoice_id=? ORDER BY id").all(id);
        for (const r of rc) db2.prepare("DELETE FROM ledger WHERE type='RECEIPT' AND ref_no=?").run(r.receipt_no);
        db2.prepare("DELETE FROM receipts WHERE invoice_id=?").run(id);
        db2.prepare("DELETE FROM ledger WHERE type='INVOICE' AND ref_no=?").run(old.invoice_no);
        return writeInvoice({ ...input, date: input.date || old.date }, { id, invoice_no: old.invoice_no, receipt_no: rc.length ? rc[0].receipt_no : null });
      });
      var deleteInvoice = db2.transaction((id) => {
        const old = db2.prepare("SELECT * FROM invoices WHERE id=?").get(id);
        if (!old) throw new HttpError2(404, "Invoice not found");
        for (const l of db2.prepare("SELECT batch_id, qty, free_qty FROM invoice_lines WHERE invoice_id=?").all(id))
          db2.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?").run(l.qty + l.free_qty, l.batch_id);
        db2.prepare("DELETE FROM invoice_lines WHERE invoice_id=?").run(id);
        for (const r of db2.prepare("SELECT receipt_no FROM receipts WHERE invoice_id=?").all(id))
          db2.prepare("DELETE FROM ledger WHERE type='RECEIPT' AND ref_no=?").run(r.receipt_no);
        db2.prepare("DELETE FROM receipts WHERE invoice_id=?").run(id);
        db2.prepare("DELETE FROM ledger WHERE type='INVOICE' AND ref_no=?").run(old.invoice_no);
        db2.prepare("DELETE FROM invoices WHERE id=?").run(id);
        return { id, invoice_no: old.invoice_no, total: old.total };
      });
      function getInvoice(id) {
        const inv = db2.prepare(
          `SELECT i.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state, p.phone party_phone, p.mobiles party_mobiles, p.tel party_tel, p.email party_email, p.pan party_pan, p.fssai party_fssai, p.credit_days party_credit_days, s.name salesman_name
     FROM invoices i LEFT JOIN parties p ON p.id=i.party_id LEFT JOIN salesmen s ON s.id=i.salesman_id WHERE i.id=?`
        ).get(id);
        if (!inv) return null;
        inv.lines = db2.prepare(
          `SELECT l.*, it.name item_name, it.hsn, it.unit, it.pcs_per_box, b.batch_no, b.exp_date, b.mfg_date, it.mrp
     FROM invoice_lines l JOIN items it ON it.id=l.item_id JOIN batches b ON b.id=l.batch_id WHERE l.invoice_id=? ORDER BY l.id`
        ).all(id);
        const grouped = /* @__PURE__ */ new Map();
        for (const l of inv.lines) {
          const g2 = grouped.get(l.item_id) || { item_id: l.item_id, item_name: l.item_name, pcs_per_box: l.pcs_per_box, qty: 0, manual_disc: l.manual_disc || 0, rate: l.rate };
          g2.qty += l.qty;
          grouped.set(l.item_id, g2);
        }
        inv.edit_lines = [...grouped.values()];
        inv.supply = inv.igst > 0 ? "INTER" : "INTRA";
        inv.amount_words = rupeesInWords(inv.total);
        const g = {};
        for (const l of inv.lines) {
          const x = g[l.gst_rate] ||= { rate: l.gst_rate, rows: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0 };
          x.rows += 1;
          x.taxable = r2(x.taxable + l.taxable);
          x.cgst = r2(x.cgst + l.cgst);
          x.sgst = r2(x.sgst + l.sgst);
          x.igst = r2(x.igst + l.igst);
        }
        inv.gst_summary = Object.values(g).sort((a, b) => a.rate - b.rate);
        if (inv.party_id) {
          const prev = db2.prepare(`SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=? AND (date < ? OR (date = ? AND id <
      COALESCE((SELECT MIN(id) FROM ledger WHERE type='INVOICE' AND ref_no=?), 1000000000000)))`).get(inv.party_id, inv.date, inv.date, inv.invoice_no).b;
          inv.party_prev_balance = r2(prev);
          inv.party_balance_after = r2(prev + inv.total - inv.paid);
        }
        return inv;
      }
      module.exports = { buildInvoice, createInvoice, updateInvoice, deleteInvoice, getInvoice, settings: settings2, partyBalance };
    }
  });

  // shims/child_process.js
  var require_child_process = __commonJS({
    "shims/child_process.js"(exports, module) {
      "use strict";
      init_globals();
      function execFile(cmd, args, opts, cb) {
        if (typeof opts === "function") {
          cb = opts;
          opts = {};
        }
        const ocr = globalThis.AndroidOCR;
        setTimeout(() => {
          try {
            if (!ocr) {
              const e2 = new Error(`spawn ${cmd} ENOENT`);
              e2.code = "ENOENT";
              return cb(e2);
            }
            if (cmd === "pdftoppm") {
              ocr.render(args[args.length - 2], args[args.length - 1]);
              return cb(null, "", "");
            }
            if (cmd === "tesseract") {
              const out = ocr.recognize(args[0]);
              return cb(null, out, "");
            }
            const e = new Error(`spawn ${cmd} ENOENT`);
            e.code = "ENOENT";
            cb(e);
          } catch (err) {
            cb(err);
          }
        }, 0);
      }
      execFile[/* @__PURE__ */ Symbol.for("nodejs.util.promisify.custom")] = (cmd, args, opts) => new Promise((ok, no) => execFile(cmd, args, opts || {}, (e, stdout, stderr) => e ? no(e) : ok({ stdout, stderr })));
      module.exports = { execFile };
    }
  });

  // shims/util.js
  var require_util = __commonJS({
    "shims/util.js"(exports, module) {
      "use strict";
      init_globals();
      var custom = /* @__PURE__ */ Symbol.for("nodejs.util.promisify.custom");
      function promisify(fn) {
        if (fn[custom]) return fn[custom];
        return (...a) => new Promise((ok, no) => fn(...a, (e, ...r) => e ? no(e) : ok(r.length > 1 ? r : r[0])));
      }
      promisify.custom = custom;
      module.exports = { promisify, inspect: (x) => JSON.stringify(x), format: (...a) => a.join(" ") };
    }
  });

  // shims/pdf-parse.js
  var require_pdf_parse = __commonJS({
    "shims/pdf-parse.js"(exports, module) {
      "use strict";
      init_globals();
      module.exports = async function pdfParse(buf, opts = {}) {
        const P = globalThis.PDFJS;
        if (!P) throw new Error("pdf.js is not loaded");
        P.disableWorker = true;
        const doc = await P.getDocument(new Uint8Array(buf));
        let text = "";
        try {
          for (let i = 1; i <= doc.numPages; i++) {
            try {
              const page = await doc.getPage(i);
              text += "\n\n" + await (opts.pagerender ? opts.pagerender(page) : "");
            } catch (e) {
            }
          }
        } finally {
          doc.destroy();
        }
        return { numpages: doc.numPages, text };
      };
    }
  });

  // ../../backend/src/services/pdfExtract.js
  var require_pdfExtract = __commonJS({
    "../../backend/src/services/pdfExtract.js"(exports, module) {
      init_globals();
      var fs = require_fs();
      var os = require_os();
      var path = require_path();
      var { execFile } = require_child_process();
      var { promisify } = require_util();
      var { HttpError: HttpError2 } = require_misc();
      var run = promisify(execFile);
      var WATERMARK_SCALE = 3;
      function runGeometry(t) {
        const size = Math.hypot(t[2], t[3]) || Math.hypot(t[0], t[1]);
        const angle = Math.abs(Math.atan2(t[1], t[0]) * 180 / Math.PI) % 180;
        return { size, angle: angle > 90 ? 180 - angle : angle };
      }
      function dropWatermarks(items) {
        const runs = items.filter((it) => it && typeof it.str === "string" && Array.isArray(it.transform));
        const sizes = [];
        for (const it of runs) {
          const g = runGeometry(it.transform);
          for (let i = 0; i < it.str.replace(/\s/g, "").length; i++) sizes.push(g.size);
        }
        if (!sizes.length) return runs;
        sizes.sort((a, b) => a - b);
        const median = sizes[Math.floor(sizes.length / 2)];
        return runs.filter((it) => {
          if (!it.str.trim()) return true;
          const g = runGeometry(it.transform);
          if (median > 0 && g.size >= median * WATERMARK_SCALE) return false;
          if (g.angle >= 15 && g.angle <= 75) return false;
          return true;
        });
      }
      function pageTextFromItems2(items) {
        const rows = [];
        for (const it of dropWatermarks(items)) {
          const y = Math.round(it.transform[5]);
          let row = rows.find((r) => Math.abs(r.y - y) <= 2);
          if (!row) {
            row = { y, cells: [] };
            rows.push(row);
          }
          row.cells.push({ x: it.transform[4], w: it.width || 0, s: it.str });
        }
        rows.sort((a, b) => b.y - a.y);
        const joinRow = (cells) => {
          let out = "", prevEnd = null;
          for (const c of cells.sort((a, b) => a.x - b.x)) {
            out += (prevEnd !== null && c.x - prevEnd > 1.2 ? " " : "") + c.s;
            prevEnd = c.x + c.w;
          }
          return out;
        };
        return rows.map((r) => joinRow(r.cells).replace(/\s+/g, " ").trim()).filter(Boolean).join("\n");
      }
      function pageRender(pageData) {
        return pageData.getTextContent({ normalizeWhitespace: true, disableCombineTextItems: false }).then((tc) => pageTextFromItems2(tc.items));
      }
      async function extractText(buf) {
        let pages = [];
        try {
          const pdfParse = require_pdf_parse();
          const out = [];
          await pdfParse(buf, { pagerender: (pd) => pageRender(pd).then((t) => {
            out.push(t);
            return t;
          }) });
          pages = out;
        } catch (e) {
          if (e.code === "MODULE_NOT_FOUND") throw new HttpError2(500, 'PDF support is not installed. Run "npm install" in the backend folder.');
          throw new HttpError2(422, "This file could not be read as a PDF.");
        }
        if (pages.join("").replace(/\s/g, "").length >= 40) return { pages, text: pages.join("\f"), method: "text" };
        const ocrPages = await ocr(buf);
        return { pages: ocrPages, text: ocrPages.join("\f"), method: "ocr" };
      }
      async function ocr(buf) {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bill-"));
        try {
          const pdf = path.join(dir, "bill.pdf");
          fs.writeFileSync(pdf, buf);
          await run("pdftoppm", ["-r", "200", "-png", pdf, path.join(dir, "p")]);
          const pages = fs.readdirSync(dir).filter((f) => f.endsWith(".png")).sort().slice(0, 12);
          const out = [];
          for (const f of pages) out.push((await run("tesseract", [path.join(dir, f), "stdout", "--psm", "6"], { maxBuffer: 2e7 })).stdout);
          if (!out.join("").trim()) throw new HttpError2(422, "No text could be recognised in this scanned PDF.");
          return out;
        } catch (e) {
          if (e instanceof HttpError2) throw e;
          if (e.code === "ENOENT") throw new HttpError2(422, "This PDF is a scan (no text layer). To read scans, install the OCR tools once: brew install poppler tesseract");
          throw new HttpError2(422, "OCR failed on this PDF.");
        } finally {
          fs.rmSync(dir, { recursive: true, force: true });
        }
      }
      module.exports = { extractText, pageTextFromItems: pageTextFromItems2, dropWatermarks };
    }
  });

  // ../../ios/tests/parity/express-shim.js
  var require_express_shim = __commonJS({
    "../../ios/tests/parity/express-shim.js"(exports, module) {
      init_globals();
      function Router() {
        const routes = [];
        const r = { routes };
        for (const m of ["get", "post", "put", "delete"]) r[m] = (p, ...hs) => {
          routes.push({ m: m.toUpperCase(), p, hs });
          return r;
        };
        r.use = () => r;
        return r;
      }
      module.exports = Object.assign(() => ({}), { Router, json: () => (q, s, n) => n() });
    }
  });

  // ../../backend/src/utils/fy.js
  var require_fy = __commonJS({
    "../../backend/src/utils/fy.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { today, HttpError: HttpError2 } = require_misc();
      var startYearOf = (date) => {
        const y = +date.slice(0, 4), m = +date.slice(5, 7);
        return m >= 4 ? y : y - 1;
      };
      var labelOf = (s) => `${s}-${String(s + 1).slice(2)}`;
      var rangeOf = (s) => ({ label: labelOf(s), start_year: s, from: `${s}-04-01`, to: `${s + 1}-03-31` });
      var currentStart = () => startYearOf(today());
      function fyRange(label) {
        if (label === void 0 || label === null || label === "") return { ...rangeOf(currentStart()), current: true };
        const m = /^(\d{4})(?:-(\d{2}|\d{4}))?$/.exec(String(label).trim());
        if (!m) throw new HttpError2(400, "Financial year must look like 2026-27");
        const s = +m[1];
        if (m[2] && +m[2].slice(-2) !== (s + 1) % 100) throw new HttpError2(400, `Financial year ${label} is not consecutive. Use ${labelOf(s)}.`);
        return { ...rangeOf(s), current: s === currentStart() };
      }
      function booksFy() {
        const r = db2.prepare("SELECT value FROM settings WHERE key='books_fy'").get();
        return r && r.value ? String(r.value) : null;
      }
      function fyList() {
        const own = booksFy();
        if (own) {
          const s = +own.slice(0, 4);
          return [{ ...rangeOf(s), current: s === currentStart() }];
        }
        const q = (sql) => db2.prepare(sql).get().d;
        const dates = [
          q("SELECT MIN(date) d FROM invoices"),
          q("SELECT MIN(date) d FROM purchases"),
          q("SELECT MIN(date) d FROM receipts"),
          q("SELECT MIN(date) d FROM payments"),
          q("SELECT MIN(date) d FROM ledger")
        ].filter(Boolean);
        const maxes = [q("SELECT MAX(date) d FROM invoices"), q("SELECT MAX(date) d FROM purchases")].filter(Boolean);
        const cur = currentStart();
        const first = dates.length ? Math.min(...dates.map(startYearOf), cur) : cur;
        const last = maxes.length ? Math.max(...maxes.map(startYearOf), cur) : cur;
        const out = [];
        for (let s = last; s >= first; s--) out.push({ ...rangeOf(s), current: s === cur });
        return out;
      }
      module.exports = { fyRange, fyList, booksFy, startYearOf, labelOf, rangeOf };
    }
  });

  // ../../backend/src/services/years.js
  var require_years = __commonJS({
    "../../backend/src/services/years.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { r2 } = require_gst();
      var { HttpError: HttpError2 } = require_misc();
      var { fyRange } = require_fy();
      var reg = db2.registry;
      var norm = (n) => String(n || "").trim().replace(/\s+/g, " ").toLowerCase();
      var MASTERS = ["categories", "salesmen", "routes", "parties", "items", "schemes"];
      function copyRows(src, dst, table, where = "") {
        const have = new Set(dst.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name));
        const cols = src.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name).filter((c) => have.has(c));
        const ins = dst.prepare(`INSERT INTO ${table}(${cols.join(",")}) VALUES(${cols.map(() => "?").join(",")})`);
        let n = 0;
        for (const r of src.prepare(`SELECT ${cols.join(",")} FROM ${table} ${where} ORDER BY id`).all()) {
          ins.run(...cols.map((c) => r[c]));
          n++;
        }
        return n;
      }
      function addYear(id, b = {}) {
        const src = db2.companyRow(id);
        if (!src) throw new HttpError2(404, "Company not found");
        if (!b.fy) throw new HttpError2(400, "Choose the financial year");
        const fy = fyRange(b.fy);
        const siblings = reg.prepare("SELECT * FROM companies WHERE active=1").all().filter((c) => norm(c.name) === norm(src.name));
        if (siblings.some((c) => c.fy === fy.label)) throw new HttpError2(409, `${src.name} already has books for ${fy.label}.`, "YEAR_EXISTS");
        const carry = !(b.carry === false || b.carry === 0);
        const raw = db2.openCompany(src.id);
        const settings2 = {};
        for (const r of raw.prepare("SELECT key,value FROM settings").all()) if (r.key !== "company_name" && r.key !== "books_fy") settings2[r.key] = r.value;
        const newId = db2.createCompany({ name: src.name, fy: fy.label, ...settings2 });
        const dst = db2.openCompany(newId);
        const carried = { masters: 0, opening_balances: 0, stock_batches: 0 };
        if (carry) {
          dst.transaction(() => {
            for (const t of MASTERS) carried.masters += copyRows(raw, dst, t);
            carried.stock_batches = copyRows(raw, dst, "batches", "WHERE qty <> 0");
            const lg = dst.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,'OPENING','OPENING',?,?,?)");
            const from = src.fy || "the earlier books";
            for (const p of raw.prepare("SELECT party_id, SUM(debit)-SUM(credit) b FROM ledger WHERE date < ? GROUP BY party_id ORDER BY party_id").all(fy.from)) {
              const bal = r2(p.b);
              if (Math.abs(bal) < 5e-3) continue;
              lg.run(p.party_id, fy.from, bal > 0 ? bal : 0, bal < 0 ? -bal : 0, `Opening balance (carried from ${from})`);
              carried.opening_balances++;
            }
          })();
        }
        return { id: newId, name: src.name, fy: fy.label, carried: carry ? carried : null };
      }
      function renameAll(oldName, newName) {
        for (const c of reg.prepare("SELECT * FROM companies").all().filter((x) => norm(x.name) === norm(oldName))) {
          reg.prepare("UPDATE companies SET name=? WHERE id=?").run(newName, c.id);
          const d = db2.openCompany(c.id);
          if (d) d.prepare("INSERT INTO settings(key,value) VALUES('company_name',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(newName);
        }
      }
      module.exports = { addYear, renameAll };
    }
  });

  // ../../backend/src/routes/companies.js
  var require_companies = __commonJS({
    "../../backend/src/routes/companies.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var db2 = require_db();
      var { h, HttpError: HttpError2, blank } = require_misc();
      var Y = require_years();
      var reg = db2.registry;
      var FIELDS = ["company_gstin", "state_code", "company_address", "company_phone", "invoice_terms"];
      var GSTIN = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
      var profile = (c) => db2.withCompany(c.id, () => {
        const o = { id: c.id, name: c.name };
        for (const r of db2.prepare("SELECT key,value FROM settings").all()) o[r.key] = r.value;
        o.fy = c.fy || null;
        return o;
      });
      function validate(b, creating) {
        if (creating && !blank(b.name)) throw new HttpError2(400, "Company name is required");
        if (blank(b.company_gstin) && !GSTIN.test(String(b.company_gstin).toUpperCase())) throw new HttpError2(400, "GSTIN format is not valid");
        if (blank(b.state_code) && !/^\d{2}$/.test(String(b.state_code))) throw new HttpError2(400, "State code must be 2 digits, e.g. 09");
      }
      router.get("/companies", h((req, res) => {
        const rows = reg.prepare("SELECT * FROM companies WHERE active=1 ORDER BY id").all();
        const last = reg.prepare("SELECT value FROM app_settings WHERE key='last_company'").get();
        res.json({ last_used: last ? Number(last.value) : null, companies: rows.map(profile) });
      }));
      router.post("/companies", h((req, res) => {
        const b = req.body;
        validate(b, true);
        const s = {};
        for (const f of FIELDS) if (blank(b[f]) !== null) s[f] = f === "company_gstin" ? String(b[f]).toUpperCase() : b[f];
        const id = db2.createCompany({ name: b.name.trim(), ...s });
        res.status(201).json({ id });
      }));
      router.put("/companies/:id", h((req, res) => {
        const c = db2.companyRow(Number(req.params.id));
        if (!c) throw new HttpError2(404, "Company not found");
        const b = req.body;
        validate(b, false);
        db2.withCompany(c.id, () => {
          const up = db2.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value");
          if (blank(b.name)) up.run("company_name", b.name.trim());
          for (const f of FIELDS) if (b[f] !== void 0) up.run(f, f === "company_gstin" ? String(b[f]).toUpperCase() : String(b[f]));
        });
        if (blank(b.name)) Y.renameAll(c.name, b.name.trim());
        res.json({ ok: true });
      }));
      router.post("/companies/:id/years", h((req, res) => res.status(201).json(Y.addYear(Number(req.params.id), req.body || {}))));
      router.post("/companies/:id/activate", h((req, res) => {
        if (!db2.companyRow(Number(req.params.id))) throw new HttpError2(404, "Company not found");
        reg.prepare("INSERT INTO app_settings(key,value) VALUES('last_company',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(String(req.params.id));
        res.json({ ok: true });
      }));
      router.post("/companies/:id/delete", h((req, res) => {
        const c = db2.companyRow(Number(req.params.id));
        if (!c) throw new HttpError2(404, "Company not found");
        const typed = String((req.body || {}).confirm || "").trim().toLowerCase();
        if (typed !== String(c.name).trim().toLowerCase()) throw new HttpError2(400, `Type the company name "${c.name}" to confirm`);
        const others = reg.prepare("SELECT COUNT(*) AS n FROM companies WHERE active=1 AND id<>?").get(c.id).n;
        if (!others) throw new HttpError2(409, "This is the only company. Make another company first, then delete this one.");
        reg.prepare("UPDATE companies SET active=0 WHERE id=?").run(c.id);
        db2.closeCompany(c.id);
        const last = reg.prepare("SELECT value FROM app_settings WHERE key='last_company'").get();
        let lastUsed = last ? Number(last.value) : null;
        if (lastUsed === c.id || !lastUsed) {
          lastUsed = db2.firstCompanyId();
          reg.prepare("INSERT INTO app_settings(key,value) VALUES('last_company',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(String(lastUsed));
        }
        res.json({ ok: true, last_used: lastUsed });
      }));
      module.exports = router;
    }
  });

  // ../../backend/src/routes/backup.js
  var require_backup2 = __commonJS({
    "../../backend/src/routes/backup.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var { h, ha } = require_misc();
      var B3 = require_backup();
      var D = require_drive();
      router.get("/backup", h((req, res) => res.json({ config: B3.config(), backups: B3.listBackups() })));
      router.put("/backup/config", h((req, res) => res.json(B3.saveConfig(req.body))));
      router.post("/backup/run", h((req, res) => {
        const r = B3.backupNow({ reason: "manual" });
        D.afterBackup(r.folder);
        res.json({ folder: r.folder, files: r.files.length, config: B3.config(), backups: B3.listBackups() });
      }));
      router.get("/backup/drive", h((req, res) => res.json(D.status())));
      router.put("/backup/drive/client", h((req, res) => res.json(D.saveClient(req.body || {}))));
      router.post("/backup/drive/connect", ha(async (req, res) => res.json(await D.connect())));
      router.post("/backup/drive/poll", ha(async (req, res) => res.json(await D.poll())));
      router.post("/backup/drive/disconnect", h((req, res) => res.json(D.disconnect())));
      router.post("/backup/drive/upload", ha(async (req, res) => res.json(await D.upload(req.body || {}))));
      router.delete("/backup/:name", h((req, res) => {
        const r = B3.deleteBackup(req.params.name);
        res.json({ ...r, backups: B3.listBackups() });
      }));
      router.post("/backup/restore", h((req, res) => res.json(B3.restore(req.body || {}))));
      module.exports = router;
    }
  });

  // ../../backend/src/services/itemTools.js
  var require_itemTools = __commonJS({
    "../../backend/src/services/itemTools.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { HttpError: HttpError2, blank } = require_misc();
      var { packFromName } = require_pdfParser();
      var { ensureCategory } = require_category();
      var isDigit = (c) => c >= "0" && c <= "9";
      var isUpperA = (c) => c >= "A" && c <= "Z";
      var isLowerA = (c) => c >= "a" && c <= "z";
      var isLetterA = (c) => isUpperA(c) || isLowerA(c);
      var lowerA = (s) => {
        let o = "";
        for (let i = 0; i < s.length; i++) {
          const c = s[i];
          o += isUpperA(c) ? String.fromCharCode(c.charCodeAt(0) + 32) : c;
        }
        return o;
      };
      var upperA = (s) => {
        let o = "";
        for (let i = 0; i < s.length; i++) {
          const c = s[i];
          o += isLowerA(c) ? String.fromCharCode(c.charCodeAt(0) - 32) : c;
        }
        return o;
      };
      var isWs = (c) => c === " " || c === "	" || c === "\n" || c === "\r" || c === "\xA0";
      var UNITS = {
        g: "g",
        gm: "g",
        gms: "g",
        gram: "g",
        grams: "g",
        gr: "g",
        grm: "g",
        grms: "g",
        kg: "kg",
        kgs: "kg",
        kilo: "kg",
        kilogram: "kg",
        kilograms: "kg",
        ml: "ml",
        mls: "ml",
        millilitre: "ml",
        milliliter: "ml",
        l: "L",
        lt: "L",
        ltr: "L",
        ltrs: "L",
        litre: "L",
        liter: "L",
        litres: "L",
        liters: "L"
      };
      var own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
      var unitOf = (w, upper) => {
        if (!own(UNITS, lowerA(w))) return null;
        const u = UNITS[lowerA(w)];
        return upper ? upperA(u) : u;
      };
      var isNumber = (w) => {
        if (!w.length) return false;
        let dots = 0;
        for (let i = 0; i < w.length; i++) {
          if (w[i] === ".") dots++;
          else if (!isDigit(w[i])) return false;
        }
        return dots <= 1 && w[0] !== "." && w[w.length - 1] !== ".";
      };
      var toInt = (v) => {
        const n = Number(v);
        return Number.isFinite(n) && Math.abs(n) < 1e15 ? Math.trunc(n) : 0;
      };
      var trimEnd = (s, set) => {
        let b = s.length;
        while (b > 0 && set.includes(s[b - 1])) b--;
        return s.slice(0, b);
      };
      function squeeze(s) {
        let o = "", sp = false;
        for (let i = 0; i < s.length; i++) {
          const c = s[i] === "_" ? " " : s[i];
          if (isWs(c)) {
            sp = o.length > 0;
            continue;
          }
          if (sp && c !== ")" && c !== "," && o[o.length - 1] !== "(") o += " ";
          sp = false;
          o += c;
        }
        return o;
      }
      function titleWord(w, mixed) {
        const br = w.indexOf("(");
        if (br > 0) return titleWord(w.slice(0, br), mixed) + w.slice(br);
        let letters = 0, vowels = 0, digit = false, caps = 0;
        for (let i = 0; i < w.length; i++) {
          if (isDigit(w[i])) digit = true;
          if (isLetterA(w[i])) {
            letters++;
            if (isUpperA(w[i])) caps++;
            if ("aeiouyAEIOUY".includes(w[i])) vowels++;
          }
        }
        if (digit || !letters) return w;
        if (mixed && caps === letters && letters <= 4) return w;
        if (letters <= 3 && vowels === 0) return upperA(w);
        let o = "", first = true;
        for (let i = 0; i < w.length; i++) {
          const c = w[i];
          if (isLetterA(c)) {
            o += first ? upperA(c) : lowerA(c);
            first = false;
          } else o += c;
        }
        return o;
      }
      function cleanName(name, mode = "keep") {
        const s = squeeze(String(name ?? ""));
        let up = 0, low = 0;
        for (let i = 0; i < s.length; i++) {
          if (isUpperA(s[i])) up++;
          else if (isLowerA(s[i])) low++;
        }
        const upperUnits = mode === "upper" || mode === "keep" && up > 0 && low === 0;
        const words = s.length ? s.split(" ") : [];
        const out = [];
        for (let i = 0; i < words.length; i++) {
          let w = words[i];
          if (isNumber(w) && i + 1 < words.length) {
            const nx = trimEnd(words[i + 1], ".,");
            const u = unitOf(nx, upperUnits);
            if (u !== null && trimEnd(words[i + 1], ".,").length === nx.length) {
              const tail = words[i + 1].slice(nx.length);
              out.push(w + u + tail);
              i++;
              continue;
            }
          }
          let k = 0, dots = 0;
          while (k < w.length && (isDigit(w[k]) || w[k] === "." && dots === 0 && k > 0)) {
            if (w[k] === ".") dots++;
            k++;
          }
          if (k > 0 && k < w.length && w[k - 1] !== ".") {
            const rest = w.slice(k), core = trimEnd(rest, ".,)");
            const u = core.length ? unitOf(core, upperUnits) : null;
            if (u !== null) w = w.slice(0, k) + u + rest.slice(core.length);
          }
          if (mode === "title") w = titleWord(w, up > 0 && low > 0);
          else if (mode === "upper") w = upperA(w);
          out.push(w);
        }
        return trimEnd(out.join(" "), " ,");
      }
      function itemKey(name) {
        const s = lowerA(cleanName(name, "keep"));
        let o = "";
        for (let i = 0; i < s.length; i++) {
          const c = s[i];
          if (isLowerA(c) || isDigit(c) || c.charCodeAt(0) > 127) o += c;
        }
        return o;
      }
      var GENERIC = ["biscuit", "biscuits", "namkeen", "snacks", "snack", "chips", "noodles", "pouch", "sachet", "bottle", "jar", "box", "refill", "packet"];
      var NOISE = ["mrp", "rs", "pkt", "pkts", "pcs", "pc", "pack", "packet", "x", "new", "the", "and", "of", "n", "no", "nos"];
      function skeleton(w) {
        let o = w[0];
        for (let i = 1; i < w.length; i++) {
          const c = w[i];
          if ("aeiouyh".includes(c)) continue;
          if (o[o.length - 1] !== c) o += c;
        }
        return o;
      }
      var GENERIC_SK = GENERIC.map(skeleton);
      function signature(it) {
        const tidy = lowerA(cleanName(it.name, "keep"));
        const sizes = [], words = [];
        let w = "";
        const flush = () => {
          if (!w) return;
          let k = 0;
          while (k < w.length && (isDigit(w[k]) || w[k] === ".")) k++;
          if (k > 0 && k < w.length && own(UNITS, w.slice(k))) {
            if (!sizes.includes(w)) sizes.push(w);
          } else if (k < w.length && !isDigit(w[w.length - 1]) && w.length >= 2 && !NOISE.includes(w)) {
            const sk = skeleton(w);
            if (!words.includes(sk)) words.push(sk);
          }
          w = "";
        };
        for (let i = 0; i < tidy.length; i++) {
          const c = tidy[i];
          if (isLowerA(c) || isDigit(c) || c === "." && w && isDigit(w[w.length - 1])) w += c;
          else flush();
        }
        flush();
        sizes.sort();
        return { sizes: sizes.join(","), words, mrp: Number(it.mrp) || 0, box: Math.max(1, parseInt(it.pcs_per_box, 10) || 1) };
      }
      function likeness(a, b, match2) {
        if (a.sizes !== b.sizes) return -1;
        if (a.mrp > 0 && b.mrp > 0 && Math.abs(a.mrp - b.mrp) >= 5e-3) return -1;
        if (a.box !== b.box && a.box > 1 && b.box > 1) return -1;
        if (!a.words.length || !b.words.length) return -1;
        let common = 0;
        for (const x of a.words) if (b.words.includes(x)) common++;
        if (!common) return -1;
        const union = a.words.length + b.words.length - common;
        const jac = common / union;
        const ca = a.words.filter((x) => !GENERIC_SK.includes(x)), cb = b.words.filter((x) => !GENERIC_SK.includes(x));
        const sameWords = ca.length > 0 && ca.length === cb.length && ca.every((x) => cb.includes(x));
        const ok = sameWords || match2 === "loose" && a.words[0] === b.words[0] && jac >= 0.5;
        return ok ? Math.round(jac * 100) / 100 : -1;
      }
      function cleanPreview(q) {
        const mode = ["keep", "title", "upper"].includes(q && q.case) ? q.case : "keep";
        const match2 = ["exact", "similar", "loose"].includes(q && q.match) ? q.match : "similar";
        const items = db2.prepare(`SELECT i.id, i.name, i.gst_rate, i.mrp, i.pcs_per_box,
      (SELECT COUNT(*) FROM invoice_lines WHERE item_id=i.id) + (SELECT COUNT(*) FROM purchase_lines WHERE item_id=i.id) + (SELECT COUNT(*) FROM debit_note_lines WHERE item_id=i.id) used,
      (SELECT COALESCE(SUM(qty),0) FROM batches WHERE item_id=i.id) stock
    FROM items i WHERE i.active=1 ORDER BY i.name, i.id`).all();
        const renames = [];
        const parent = items.map((_, i) => i);
        const find = (i) => {
          while (parent[i] !== i) {
            parent[i] = parent[parent[i]];
            i = parent[i];
          }
          return i;
        };
        const keys = items.map((it) => itemKey(it.name));
        const sigs = items.map(signature);
        const group = items.map((_, i) => [i]);
        const fits = (x, y) => !(sigs[x].mrp > 0 && sigs[y].mrp > 0 && Math.abs(sigs[x].mrp - sigs[y].mrp) >= 5e-3) && !(sigs[x].box !== sigs[y].box && sigs[x].box > 1 && sigs[y].box > 1);
        const join = (i, j) => {
          const a = find(i), b = find(j);
          if (a === b) return false;
          if (!group[a].every((x) => group[b].every((y) => fits(x, y)))) return false;
          const lo = Math.min(a, b), hi = Math.max(a, b);
          parent[hi] = lo;
          group[lo] = group[lo].concat(group[hi]);
          return true;
        };
        const best = items.map(() => 1);
        const firstByKey = /* @__PURE__ */ new Map();
        items.forEach((it, i) => {
          const c = cleanName(it.name, mode);
          if (c && c !== it.name) renames.push({ id: it.id, name: it.name, clean: c });
          if (!keys[i]) return;
          if (firstByKey.has(keys[i])) join(firstByKey.get(keys[i]), i);
          else firstByKey.set(keys[i], i);
        });
        if (match2 !== "exact") {
          const bySize = /* @__PURE__ */ new Map();
          items.forEach((_, i) => {
            const k = sigs[i].sizes;
            if (!bySize.has(k)) bySize.set(k, []);
            bySize.get(k).push(i);
          });
          for (const list of bySize.values()) {
            for (let x = 0; x < list.length; x++) {
              for (let y = x + 1; y < list.length; y++) {
                const i = list[x], j = list[y];
                if (keys[i] && keys[i] === keys[j]) continue;
                const l = likeness(sigs[i], sigs[j], match2);
                if (l < 0) continue;
                if (find(i) !== find(j) && !join(i, j)) continue;
                if (l < best[i]) best[i] = l;
                if (l < best[j]) best[j] = l;
              }
            }
          }
        }
        const members = /* @__PURE__ */ new Map();
        items.forEach((_, i) => {
          const r = find(i);
          if (!members.has(r)) members.set(r, []);
          members.get(r).push(i);
        });
        const groups = [];
        for (const list0 of members.values()) {
          if (list0.length < 2) continue;
          const list = list0.map((i) => items[i]);
          const ranked = list.slice().sort((a, b) => b.used - a.used || b.stock - a.stock || a.id - b.id);
          const keep = ranked[0];
          const same = list0.every((i) => keys[i] === keys[list0[0]]);
          const brief = (x) => ({ id: x.id, name: x.name, used: x.used, stock: x.stock, mrp: x.mrp, pcs_per_box: x.pcs_per_box });
          const warnings = [];
          if (list.some((x) => x.gst_rate !== keep.gst_rate)) warnings.push("Different GST rates");
          if (list.some((x) => Math.max(1, x.pcs_per_box || 1) !== Math.max(1, keep.pcs_per_box || 1))) warnings.push("Different pieces per box");
          groups.push({
            key: keys[list0[0]] || String(keep.id),
            match: same ? "same" : "similar",
            score: same ? 1 : Math.min(...list0.map((i) => best[i])),
            keep: brief(keep),
            merge: ranked.slice(1).map(brief),
            warnings
          });
        }
        groups.sort((a, b) => a.keep.name < b.keep.name ? -1 : a.keep.name > b.keep.name ? 1 : a.keep.id - b.keep.id);
        return { mode, match: match2, items: items.length, renames, groups };
      }
      var applyClean = db2.transaction((b) => {
        const mode = ["keep", "title", "upper"].includes(b && b.case) ? b.case : "keep";
        const only = b && Array.isArray(b.ids) ? b.ids.map(toInt) : null;
        const items = db2.prepare("SELECT id,name FROM items WHERE active=1 ORDER BY id").all();
        const taken = db2.prepare("SELECT id FROM items WHERE active=1 AND lower(name)=lower(?) AND id <> ?");
        const upd = db2.prepare("UPDATE items SET name=?, pcs_per_box=? WHERE id=?");
        const cur = db2.prepare("SELECT pcs_per_box FROM items WHERE id=?");
        let renamed = 0;
        const skipped = [];
        for (const it of items) {
          if (only && !only.includes(it.id)) continue;
          const c = cleanName(it.name, mode);
          if (!c || c === it.name) continue;
          if (taken.get(c, it.id)) {
            skipped.push({ id: it.id, name: it.name, clean: c, reason: "Another item already has this name: merge them instead" });
            continue;
          }
          upd.run(c, packFromName(c) || cur.get(it.id).pcs_per_box, it.id);
          renamed++;
        }
        return { renamed, skipped };
      });
      var mergeItems = db2.transaction((b) => {
        const keepId = toInt(b && b.keep_id);
        const ids = (b && Array.isArray(b.merge_ids) ? b.merge_ids : []).map(toInt).filter((x) => x !== keepId);
        const keep = keepId ? db2.prepare("SELECT * FROM items WHERE id=? AND active=1").get(keepId) : null;
        if (!keep) throw new HttpError2(404, "Choose the item to keep");
        if (!ids.length) throw new HttpError2(400, "Choose the items to merge into it");
        const moved = { invoice_lines: 0, purchase_lines: 0, debit_note_lines: 0, batches: 0, schemes: 0 };
        const names = [];
        for (const id of ids) {
          const m = db2.prepare("SELECT * FROM items WHERE id=? AND active=1").get(id);
          if (!m) throw new HttpError2(404, `Item ${id} not found`);
          for (const bt of db2.prepare("SELECT * FROM batches WHERE item_id=? ORDER BY id").all(id)) {
            const same = db2.prepare("SELECT id FROM batches WHERE item_id=? AND batch_no=?").get(keepId, bt.batch_no);
            if (same) {
              db2.prepare("UPDATE batches SET qty=qty+? WHERE id=?").run(bt.qty, same.id);
              for (const t of ["invoice_lines", "purchase_lines", "debit_note_lines", "debit_note_stock"]) db2.prepare(`UPDATE ${t} SET batch_id=? WHERE batch_id=?`).run(same.id, bt.id);
              db2.prepare("DELETE FROM batches WHERE id=?").run(bt.id);
            } else db2.prepare("UPDATE batches SET item_id=? WHERE id=?").run(keepId, bt.id);
            moved.batches++;
          }
          for (const t of ["invoice_lines", "purchase_lines", "debit_note_lines", "schemes"]) {
            moved[t] += db2.prepare(`UPDATE ${t} SET item_id=? WHERE item_id=?`).run(keepId, id).changes;
          }
          for (const k of ["mrp", "retail_price", "wholesale_price", "purchase_price"]) {
            if (!(keep[k] > 0) && m[k] > 0) {
              keep[k] = m[k];
              db2.prepare(`UPDATE items SET ${k}=? WHERE id=?`).run(m[k], keepId);
            }
          }
          for (const k of ["hsn", "category_id"]) {
            if (blank(keep[k]) === null && blank(m[k]) !== null) {
              keep[k] = m[k];
              db2.prepare(`UPDATE items SET ${k}=? WHERE id=?`).run(m[k], keepId);
            }
          }
          db2.prepare("UPDATE items SET active=0 WHERE id=?").run(id);
          names.push(m.name);
        }
        return { kept: keepId, name: keep.name, merged: names, moved };
      });
      var BLOCK = ["br", "p", "div", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6", "table", "tbody", "thead", "ul", "ol", "section", "article", "header", "footer", "dd", "dt", "option", "hr"];
      var ENT = { amp: "&", nbsp: " ", lt: "<", gt: ">", quot: '"', apos: "'", rsquo: "'", lsquo: "'", ndash: "-", mdash: "-", times: "x", rupee: "\u20B9", copy: "\xA9" };
      function htmlLines(html) {
        const s = String(html || "");
        const low = lowerA(s);
        let o = "";
        let i = 0;
        while (i < s.length) {
          const c = s[i];
          if (c === "<") {
            if (low.startsWith("<!--", i)) {
              const e = low.indexOf("-->", i + 4);
              i = e < 0 ? s.length : e + 3;
              continue;
            }
            let j = i + 1;
            if (s[j] === "/") j++;
            let name = "";
            while (j < s.length && (isLetterA(s[j]) || isDigit(s[j]))) name += low[j++];
            const end = s.indexOf(">", j);
            if (!name || end < 0) {
              o += c;
              i++;
              continue;
            }
            if ((name === "script" || name === "style" || name === "noscript" || name === "svg") && s[i + 1] !== "/") {
              const close = low.indexOf("</" + name, end);
              i = close < 0 ? s.length : low.indexOf(">", close) < 0 ? s.length : low.indexOf(">", close) + 1;
              continue;
            }
            if (name === "td" || name === "th") o += " | ";
            else if (BLOCK.includes(name)) o += "\n";
            else o += " ";
            i = end + 1;
            continue;
          }
          if (c === "&") {
            const semi = s.indexOf(";", i);
            if (semi > i && semi - i <= 8) {
              const ent = s.slice(i + 1, semi);
              let rep = null;
              if (ent[0] === "#") {
                const hex = ent[1] === "x" || ent[1] === "X";
                const digits = hex ? ent.slice(2) : ent.slice(1);
                let n = digits.length ? 0 : -1;
                for (let q = 0; q < digits.length && n >= 0; q++) {
                  const d = lowerA(digits[q]);
                  const v = isDigit(d) ? d.charCodeAt(0) - 48 : hex && d >= "a" && d <= "f" ? d.charCodeAt(0) - 87 : -1;
                  n = v < 0 ? -1 : n * (hex ? 16 : 10) + v;
                }
                if (n > 0 && n < 55296) rep = n === 160 ? " " : String.fromCharCode(n);
              } else if (own(ENT, lowerA(ent))) rep = ENT[lowerA(ent)];
              if (rep !== null) {
                o += rep;
                i = semi + 1;
                continue;
              }
            }
          }
          o += c;
          i++;
        }
        const lines = [];
        for (const raw of o.split("\n")) {
          const cells = raw.split("|").map(squeeze).filter((x) => x.length);
          const line = cells.join(" | ");
          if (line.length) lines.push(line);
        }
        return lines;
      }
      var SKIP = ["http", "www.", "copyright", "\xA9", "all rights", "privacy", "cookie", "login", "sign in", "cart", "subscribe", "whatsapp", "call us", "email"];
      var PRICE_WORDS = ["mrp", "rs", "rs.", "inr", "price", "\u20B9", "@"];
      function priceCell(cell) {
        let t = lowerA(cell);
        for (const w of ["mrp", "rs.", "rs", "inr", "\u20B9", "/-", ":", " "]) t = t.split(w).join("");
        t = t.split(",").join("");
        return isNumber(t) ? Number(t) : null;
      }
      function nameAndMrp(text) {
        const low = lowerA(text);
        let best = -1;
        for (const w of PRICE_WORDS) {
          let from = 0;
          for (; ; ) {
            const at = low.indexOf(w, from);
            if (at < 0) break;
            from = at + 1;
            const before = at === 0 ? " " : low[at - 1];
            if (isLetterA(before) || isDigit(before)) continue;
            let k2 = at + w.length;
            const afterW = low[k2];
            if (w !== "\u20B9" && w !== "@" && afterW !== void 0 && isLetterA(afterW)) continue;
            while (k2 < low.length && (low[k2] === " " || low[k2] === "." || low[k2] === ":" || low[k2] === "-" || low[k2] === "=" || low[k2] === "\u20B9")) k2++;
            if (k2 < low.length && isDigit(low[k2]) && (best < 0 || at < best)) best = at;
          }
        }
        if (best < 0) return { name: text, mrp: null };
        let k = best;
        while (k < text.length && !isDigit(text[k])) k++;
        let num = "";
        while (k < text.length && (isDigit(text[k]) || text[k] === "," || text[k] === "." && isDigit(text[k + 1] || ""))) {
          if (text[k] !== ",") num += text[k];
          k++;
        }
        return { name: trimEnd(text.slice(0, best), " -,:|(/"), mrp: isNumber(num) ? Number(num) : null };
      }
      var hasUnit = (name) => {
        const w = cleanName(name, "keep").split(" ");
        for (const x of w) {
          let k = 0;
          while (k < x.length && (isDigit(x[k]) || x[k] === ".")) k++;
          if (k > 0 && k < x.length && own(UNITS, lowerA(trimEnd(x.slice(k), ".,)")))) return true;
        }
        return false;
      };
      function extractList(b) {
        const mode = ["keep", "title", "upper"].includes(b && b.case) ? b.case : "title";
        const company = squeeze(String(b && b.company || ""));
        const lines = b && b.html ? htmlLines(b.html) : String(b && b.text || "").split("\r\n").join("\n").split("\r").join("\n").split("\n").map(squeeze).filter((x) => x.length);
        const existing = /* @__PURE__ */ new Map();
        for (const it of db2.prepare("SELECT id,name FROM items WHERE active=1 ORDER BY id").all()) {
          const k = itemKey(it.name);
          if (k && !existing.has(k)) existing.set(k, it);
        }
        const out = [];
        const seen = /* @__PURE__ */ new Map();
        let merged = 0;
        let mrpCol = -1, headerCells = 0;
        for (const line of lines) {
          const ll = lowerA(line);
          if (SKIP.some((w) => ll.includes(w))) continue;
          const cells = line.split("|").map((x) => squeeze(x)).filter((x) => x.length);
          if (cells.length < 2) {
            mrpCol = -1;
            headerCells = 0;
          } else {
            let h = -1;
            for (let i = 0; i < cells.length; i++) {
              let digit = false;
              for (let q = 0; q < cells[i].length; q++) if (isDigit(cells[i][q])) digit = true;
              if (!digit && lowerA(cells[i]).includes("mrp")) {
                h = i;
                break;
              }
            }
            if (h >= 0) {
              mrpCol = h;
              headerCells = cells.length;
              continue;
            }
          }
          let nameCell = -1;
          for (let i = 0; i < cells.length; i++) {
            let letters = 0;
            for (const ch of cells[i]) if (isLetterA(ch)) letters++;
            if (letters >= 3 && priceCell(cells[i]) === null) {
              nameCell = i;
              break;
            }
          }
          if (nameCell < 0) continue;
          let { name, mrp } = nameAndMrp(cells[nameCell]);
          if (mrp === null && mrpCol >= 0 && mrpCol !== nameCell && cells.length === headerCells) {
            const p = priceCell(cells[mrpCol]);
            if (p !== null && p > 0) mrp = p;
          }
          if (!hasUnit(name)) {
            for (let i = nameCell + 1; i < cells.length; i++) {
              if (i === mrpCol && cells.length === headerCells) continue;
              if (cells[i].length <= 12 && priceCell(cells[i]) === null && hasUnit(cells[i])) {
                name = name + " " + cells[i];
                break;
              }
            }
          }
          if (mrp === null) {
            for (let i = 0; i < cells.length; i++) {
              if (i === nameCell) continue;
              const p = priceCell(cells[i]);
              if (p !== null && p > 0 && (mrp === null || p > mrp)) mrp = p;
            }
          }
          let k = 0;
          while (k < name.length && isDigit(name[k])) k++;
          if (k > 0 && k < name.length && (name[k] === "." || name[k] === ")" || name[k] === " ") && !hasUnit(name.slice(0, k + 3))) name = squeeze(name.slice(k + 1));
          if (name.length < 3 || name.length > 90) continue;
          if (!(mrp > 0) && !hasUnit(name)) continue;
          if (company && !lowerA(name).includes(lowerA(company))) name = company + " " + name;
          const clean = cleanName(name, mode);
          const key = itemKey(clean);
          if (!key) continue;
          if (seen.has(key)) {
            const prev = seen.get(key);
            if (!(prev.mrp > 0) && mrp > 0) prev.mrp = mrp;
            merged++;
            continue;
          }
          const ex = existing.get(key);
          const row = { name: clean, mrp: mrp > 0 ? mrp : null, pack: packFromName(clean) || null, exists_id: ex ? ex.id : null, exists_name: ex ? ex.name : null };
          seen.set(key, row);
          out.push(row);
          if (out.length >= 400) break;
        }
        return { lines: lines.length, items: out, found: out.length, duplicates_merged: merged, new: out.filter((x) => !x.exists_id).length };
      }
      var bulkAdd = db2.transaction((b) => {
        const list = b && Array.isArray(b.items) ? b.items : [];
        if (!list.length) throw new HttpError2(400, "Choose the items to add");
        const catId = blank(b.category) === null ? null : ensureCategory(squeeze(String(b.category)));
        const gst = b.gst_rate === void 0 || b.gst_rate === null || b.gst_rate === "" ? 18 : Number(b.gst_rate);
        if (!Number.isFinite(gst) || gst < 0 || gst > 40) throw new HttpError2(400, "GST rate must be between 0 and 40");
        const added = [], skipped = [];
        const dup = db2.prepare("SELECT id FROM items WHERE active=1 AND lower(name)=lower(?)");
        const ins = db2.prepare("INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,pcs_per_box) VALUES(?,?,?,?,?,?,?)");
        for (const it of list) {
          const name = squeeze(String(it && it.name || ""));
          if (!name) {
            skipped.push({ name, reason: "No name" });
            continue;
          }
          if (name.length > 120) {
            skipped.push({ name, reason: "Name is too long" });
            continue;
          }
          if (dup.get(name)) {
            skipped.push({ name, reason: "Already in your items" });
            continue;
          }
          const mrp = Number(it.mrp || 0);
          const r = ins.run(name, catId, null, gst, "PCS", Number.isFinite(mrp) && mrp > 0 ? mrp : 0, packFromName(name) || 1);
          added.push({ id: Number(r.lastInsertRowid), name });
        }
        return { added, skipped, category_id: catId };
      });
      module.exports = { cleanName, itemKey, cleanPreview, applyClean, mergeItems, htmlLines, extractList, bulkAdd, nameAndMrp };
    }
  });

  // ../../backend/src/services/webList.js
  var require_webList = __commonJS({
    "../../backend/src/services/webList.js"(exports, module) {
      init_globals();
      var { HttpError: HttpError2 } = require_misc();
      var T = require_itemTools();
      var UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
      var OFFLINE = () => new HttpError2(503, "Could not reach the internet. Check the connection and try again.", "OFFLINE");
      async function get(url, ms) {
        if (typeof fetch !== "function") throw OFFLINE();
        let r;
        try {
          r = await fetch(url, { signal: AbortSignal.timeout(ms), redirect: "follow", headers: { "User-Agent": UA, Accept: "text/html,application/pdf,*/*" } });
        } catch (_) {
          throw OFFLINE();
        }
        if (!r.ok) throw new HttpError2(502, `That page answered with an error (${r.status}).`);
        const buf = Buffer2.from(await r.arrayBuffer());
        if (buf.length > 12 * 1024 * 1024) throw new HttpError2(413, "That file is too large to read (12 MB at most).");
        return { buf, type: String(r.headers.get("content-type") || "").toLowerCase() };
      }
      var between = (s, a, b, from = 0) => {
        const i = s.indexOf(a, from);
        if (i < 0) return null;
        const j = s.indexOf(b, i + a.length);
        return j < 0 ? null : s.slice(i + a.length, j);
      };
      async function search(b) {
        const q = String(b && b.q || [b && b.company, b && b.category, "price list MRP"].filter(Boolean).join(" ")).trim();
        if (!q || q === "price list MRP") throw new HttpError2(400, "Type the company (and category) to search for");
        const { buf } = await get("https://html.duckduckgo.com/html/?q=" + encodeURIComponent(q), 12e3);
        const html = buf.toString("utf8");
        const results = [];
        for (const chunk of html.split('class="result__a"').slice(1)) {
          let href = between(chunk, 'href="', '"');
          if (!href) continue;
          href = href.split("&amp;").join("&");
          if (href.includes("uddg=")) {
            try {
              href = decodeURIComponent(href.split("uddg=")[1].split("&")[0]);
            } catch (_) {
              continue;
            }
          }
          if (href.startsWith("//")) href = "https:" + href;
          if (!/^https?:\/\//i.test(href) || href.includes("duckduckgo.com/y.js")) continue;
          const a = chunk.indexOf(">"), z = chunk.indexOf("</a>");
          const title = a >= 0 && z > a ? T.htmlLines(chunk.slice(a + 1, z)).join(" ") : href;
          if (results.some((r) => r.url === href)) continue;
          results.push({ title: title || href, url: href, pdf: /\.pdf($|\?)/i.test(href) });
          if (results.length >= 10) break;
        }
        return { query: q, results };
      }
      async function fetchList(b) {
        const url = String(b && b.url || "").trim();
        if (!/^https?:\/\//i.test(url)) throw new HttpError2(400, "Paste a web address starting with http:// or https://");
        const { buf, type } = await get(url, 2e4);
        const isPdf = type.includes("pdf") || buf.slice(0, 5).toString("latin1") === "%PDF-";
        if (isPdf) {
          const { extractText } = require_pdfExtract();
          const { pages } = await extractText(buf);
          return { url, source: "pdf", ...T.extractList({ text: pages.join("\n"), company: b.company, case: b.case }) };
        }
        return { url, source: "page", ...T.extractList({ html: buf.toString("utf8"), company: b.company, case: b.case }) };
      }
      module.exports = { search, fetchList };
    }
  });

  // ../../backend/src/services/pricing.js
  var require_pricing = __commonJS({
    "../../backend/src/services/pricing.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { HttpError: HttpError2 } = require_misc();
      var { r2, splitTax } = require_gst();
      var r8 = (n) => Math.round((n + Number.EPSILON) * 1e8) / 1e8;
      var boxOf = (it) => Math.max(1, parseInt(it.pcs_per_box, 10) || 1);
      var gstOf = (it) => Number(it.gst_rate) || 0;
      function billForBox(it, rate) {
        const gross = r2(rate * boxOf(it));
        const t = splitTax(gross, gstOf(it), true);
        return Math.round(r2(gross + t.cgst + t.sgst + t.igst));
      }
      function roundTo(v, round) {
        if (round === "none" || round === "auto" && v < 50) return r2(v);
        const step = round === "auto" ? 1 : Number(round);
        return Math.round(v / step + 1e-9) * step;
      }
      function setPrices(b) {
        b = b || {};
        const mode = b.mode === "table" ? "table" : "percent";
        const round = ["auto", "none", "1", "5", "10"].includes(String(b.round)) ? String(b.round) : "auto";
        const pct = (v, label) => {
          if (v === void 0 || v === null || String(v).trim() === "") return null;
          const n = Number(v);
          if (!Number.isFinite(n) || n < 0 || n >= 100) throw new HttpError2(400, `${label} must be a percentage from 0 to 99.99`);
          return n;
        };
        const money = (v, label) => {
          if (v === void 0 || v === null || String(v).trim() === "") return null;
          const n = Number(String(v).split(",").join(""));
          if (!Number.isFinite(n) || n < 0) throw new HttpError2(400, `${label} must be a number (0 or more)`);
          return n;
        };
        let retailOff = null, wholesaleOff = null, tiers = [];
        if (mode === "percent") {
          retailOff = pct(b.retail_off, "Retail % below MRP");
          wholesaleOff = pct(b.wholesale_off, "Wholesale % below MRP");
          if (retailOff === null && wholesaleOff === null) throw new HttpError2(400, "Enter the retail and/or wholesale % below MRP");
        } else {
          tiers = (Array.isArray(b.tiers) ? b.tiers : []).map((t) => {
            const mrp = money(t && t.mrp, "MRP");
            if (!(mrp > 0)) throw new HttpError2(400, "Each row needs an MRP");
            return { mrp, retail: money(t.retail, `Retail price for MRP ${mrp}`), wholesale: money(t.wholesale, `Wholesale price for MRP ${mrp}`) };
          }).filter((t) => t.retail !== null || t.wholesale !== null);
          if (!tiers.length) throw new HttpError2(400, "Enter a retail and/or wholesale price for at least one MRP");
        }
        const perBox = String(b.per || "box").toLowerCase() !== "piece";
        const inclGst = b.include_gst !== false && b.include_gst !== 0 && b.include_gst !== "0" && b.include_gst !== "false";
        const catId = b.category_id ? Number(b.category_id) : null;
        const only = Array.isArray(b.item_ids) && b.item_ids.length ? b.item_ids.map(Number) : null;
        const rows = db2.prepare(`SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items
    WHERE active=1 AND (? IS NULL OR category_id=?) ORDER BY name, id`).all(catId, catId).filter((it) => !only || only.includes(it.id));
        const fromBoxIncl = (it, box) => r8(box / boxOf(it) / (1 + gstOf(it) / 100));
        const fromPercent = (it, off) => {
          const unit = boxOf(it) > 1 ? boxOf(it) : 1;
          const incl = roundTo(it.mrp * unit * (1 - off / 100), round);
          return fromBoxIncl(it, incl);
        };
        const fromTyped = (it, v) => {
          const perPiece = perBox ? v / boxOf(it) : v;
          return r8(inclGst ? perPiece / (1 + gstOf(it) / 100) : perPiece);
        };
        const out = [];
        let skipped = 0;
        for (const it of rows) {
          if (!(it.mrp > 0)) {
            skipped++;
            continue;
          }
          let newRetail = null, newWholesale = null;
          if (mode === "percent") {
            if (retailOff !== null) newRetail = fromPercent(it, retailOff);
            if (wholesaleOff !== null) newWholesale = fromPercent(it, wholesaleOff);
          } else {
            const t = tiers.find((x) => Math.abs(x.mrp - it.mrp) < 5e-3);
            if (!t) continue;
            if (t.retail !== null) newRetail = fromTyped(it, t.retail);
            if (t.wholesale !== null) newWholesale = fromTyped(it, t.wholesale);
          }
          const c = { id: it.id, name: it.name, pcs_per_box: boxOf(it), gst_rate: gstOf(it), mrp: it.mrp, mrp_box: r2(it.mrp * boxOf(it)) };
          if (newRetail !== null) {
            Object.assign(c, {
              retail_old: it.retail_price,
              retail_old_bill: billForBox(it, it.retail_price),
              retail_new: newRetail,
              retail_box: r2(newRetail * boxOf(it) * (1 + gstOf(it) / 100)),
              retail_bill: billForBox(it, newRetail),
              retail_below_pct: r2((1 - billForBox(it, newRetail) / (it.mrp * boxOf(it))) * 100)
            });
          }
          if (newWholesale !== null) {
            Object.assign(c, {
              wholesale_old: it.wholesale_price,
              wholesale_old_bill: billForBox(it, it.wholesale_price),
              wholesale_new: newWholesale,
              wholesale_box: r2(newWholesale * boxOf(it) * (1 + gstOf(it) / 100)),
              wholesale_bill: billForBox(it, newWholesale),
              wholesale_below_pct: r2((1 - billForBox(it, newWholesale) / (it.mrp * boxOf(it))) * 100)
            });
          }
          out.push(c);
        }
        if (!b.preview) {
          const ur = db2.prepare("UPDATE items SET retail_price=? WHERE id=?"), uw = db2.prepare("UPDATE items SET wholesale_price=? WHERE id=?");
          db2.transaction(() => {
            for (const c of out) {
              if (c.retail_new !== void 0) ur.run(c.retail_new, c.id);
              if (c.wholesale_new !== void 0) uw.run(c.wholesale_new, c.id);
            }
          })();
        }
        return { mode, round, updated: b.preview ? 0 : out.length, would_update: out.length, skipped_no_mrp: skipped, items: out.slice(0, 500) };
      }
      function mrpTable(q) {
        const catId = q && q.category_id ? Number(q.category_id) : null;
        const rows = db2.prepare(`SELECT id,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items
    WHERE active=1 AND mrp > 0 AND (? IS NULL OR category_id=?) ORDER BY mrp, id`).all(catId, catId);
        const groups = [];
        for (const it of rows) {
          let g = groups.find((x) => Math.abs(x.mrp - it.mrp) < 5e-3);
          if (!g) {
            g = { mrp: it.mrp, items: 0, boxes: [], retail_box: null, wholesale_box: null, retail_piece: null, wholesale_piece: null };
            groups.push(g);
          }
          g.items++;
          if (!g.boxes.includes(boxOf(it))) g.boxes.push(boxOf(it));
          const rb = r2(it.retail_price * boxOf(it) * (1 + gstOf(it) / 100)), wb = r2(it.wholesale_price * boxOf(it) * (1 + gstOf(it) / 100));
          const rp = r2(it.retail_price * (1 + gstOf(it) / 100)), wp = r2(it.wholesale_price * (1 + gstOf(it) / 100));
          if (g.retail_box === null || rb > g.retail_box) g.retail_box = rb;
          if (g.wholesale_box === null || wb > g.wholesale_box) g.wholesale_box = wb;
          if (g.retail_piece === null || rp > g.retail_piece) g.retail_piece = rp;
          if (g.wholesale_piece === null || wp > g.wholesale_piece) g.wholesale_piece = wp;
        }
        for (const g of groups) {
          g.boxes.sort((a, b) => a - b);
          g.mrp_box = g.boxes.length === 1 ? r2(g.mrp * g.boxes[0]) : null;
        }
        return groups;
      }
      module.exports = { setPrices, mrpTable, billForBox };
    }
  });

  // ../../backend/src/routes/items.js
  var require_items = __commonJS({
    "../../backend/src/routes/items.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var db2 = require_db();
      var { h, ha, HttpError: HttpError2, blank } = require_misc();
      var { mrpFromName, packFromName } = require_pdfParser();
      var { guessCategory, ensureCategory, pinned } = require_category();
      var { r2 } = require_gst();
      var T = require_itemTools();
      var W = require_webList();
      var P = require_pricing();
      router.get("/categories", h((req, res) => {
        res.json(db2.prepare("SELECT * FROM categories ORDER BY name").all());
      }));
      router.post("/categories", h((req, res) => {
        if (!blank(req.body.name)) throw new HttpError2(400, "Category name is required");
        const info = db2.prepare("INSERT INTO categories(name) VALUES(?)").run(req.body.name.trim());
        res.status(201).json({ id: Number(info.lastInsertRowid), name: req.body.name.trim() });
      }));
      var withMargins = (it) => {
        const wholesaleInclGst = it.wholesale_price * (1 + it.gst_rate / 100);
        return {
          ...it,
          dist_margin_pct: it.wholesale_price > 0 ? r2((it.wholesale_price - it.purchase_price) / it.wholesale_price * 100) : 0,
          retailer_margin_pct: it.mrp > 0 ? r2((it.mrp - wholesaleInclGst) / it.mrp * 100) : 0
        };
      };
      function cleanItem(b, partial) {
        const o = {};
        const num = (k, label, min = 0) => {
          if (b[k] === void 0 && partial) return;
          const v = b[k] === void 0 || b[k] === "" || b[k] === null ? 0 : Number(b[k]);
          if (!Number.isFinite(v) || v < min) throw new HttpError2(400, `${label} must be a number${min === 0 ? " (0 or more)" : ""}`);
          o[k] = v;
        };
        if (!partial || b.name !== void 0) {
          const name = String(b.name ?? "").trim().replace(/\s+/g, " ");
          if (!name) throw new HttpError2(400, "Item name is required");
          if (name.length > 120) throw new HttpError2(400, "Item name is too long (120 characters at most)");
          o.name = name;
        }
        num("mrp", "MRP");
        num("retail_price", "Retail price");
        num("wholesale_price", "Wholesale price");
        num("purchase_price", "Purchase price");
        if (b.gst_rate !== void 0 || !partial) {
          const g = b.gst_rate === void 0 || b.gst_rate === "" ? 18 : Number(b.gst_rate);
          if (!Number.isFinite(g) || g < 0 || g > 40) throw new HttpError2(400, "GST rate must be between 0 and 40");
          o.gst_rate = g;
        }
        if (b.pcs_per_box !== void 0 || !partial) {
          const p = Math.floor(Number(b.pcs_per_box || 1));
          if (!Number.isFinite(p) || p < 1 || p > 1e5) throw new HttpError2(400, "Pieces per box must be 1 or more");
          o.pcs_per_box = p;
        }
        o.unit = "PCS";
        if (b.hsn !== void 0 || !partial) {
          const h2 = blank(b.hsn) === null ? null : String(b.hsn).trim();
          if (h2 && !/^\d{2,8}$/.test(h2)) throw new HttpError2(400, "HSN code must be 2 to 8 digits");
          o.hsn = h2;
        }
        if (b.category_id !== void 0 || !partial) o.category_id = blank(b.category_id);
        return o;
      }
      function assertNameFree(name, exceptId) {
        const dup = db2.prepare("SELECT id FROM items WHERE active=1 AND lower(name)=lower(?) AND id <> ?").get(name, exceptId || 0);
        if (dup) throw new HttpError2(409, `An item named "${name}" already exists`, "DUPLICATE");
      }
      router.get("/items", h((req, res) => {
        const q = `%${(req.query.q || "").trim()}%`;
        const cat = req.query.category_id ? Number(req.query.category_id) : null;
        const rows = db2.prepare(
          `SELECT i.*, c.name category,
       COALESCE(s.stock,0) stock, s.next_expiry
     FROM items i LEFT JOIN categories c ON c.id=i.category_id
     LEFT JOIN (SELECT item_id, SUM(qty) stock, MIN(CASE WHEN qty>0 AND exp_date < '2099-01-01' THEN exp_date END) next_expiry
                FROM batches GROUP BY item_id) s ON s.item_id=i.id
     WHERE i.active=1 AND (i.name LIKE ? OR COALESCE(i.hsn,'') LIKE ?) AND (? IS NULL OR i.category_id = ?)
     ORDER BY i.name LIMIT ?`
        ).all(q, q, cat, cat, req.query.all === "1" ? -1 : 1e3);
        res.json(rows.map(withMargins));
      }));
      router.post("/items", ha(async (req, res) => {
        const o = cleanItem(req.body || {}, false);
        assertNameFree(o.name);
        const pk = packFromName(o.name);
        if (pk) o.pcs_per_box = pk;
        if (!o.category_id) {
          const g = await guessCategory(o.name);
          if (g.name) o.category_id = ensureCategory(g.name);
        }
        const info = db2.prepare(
          `INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box)
     VALUES(@name,@category_id,@hsn,@gst_rate,@unit,@mrp,@retail_price,@wholesale_price,@purchase_price,@pcs_per_box)`
        ).run(o);
        res.status(201).json({ id: Number(info.lastInsertRowid) });
      }));
      router.put("/items/:id", h((req, res) => {
        const cur = db2.prepare("SELECT * FROM items WHERE id=?").get(req.params.id);
        if (!cur) throw new HttpError2(404, "Item not found");
        const o = { ...cur, ...cleanItem(req.body || {}, true) };
        assertNameFree(o.name, cur.id);
        const pk = packFromName(o.name);
        if (pk) o.pcs_per_box = pk;
        db2.prepare(
          `UPDATE items SET name=@name,category_id=@category_id,hsn=@hsn,gst_rate=@gst_rate,unit=@unit,mrp=@mrp,retail_price=@retail_price,
       wholesale_price=@wholesale_price,purchase_price=@purchase_price,pcs_per_box=@pcs_per_box WHERE id=@id`
        ).run({ ...o, id: cur.id });
        res.json({ ok: true });
      }));
      router.post("/items/auto-categorize", ha(async (req, res) => {
        let moved = 0;
        for (const it of db2.prepare("SELECT id,name,category_id FROM items WHERE active=1").all()) {
          const pin = pinned(it.name);
          if (!pin) continue;
          const cid = ensureCategory(pin);
          if (it.category_id !== cid) {
            db2.prepare("UPDATE items SET category_id=? WHERE id=?").run(cid, it.id);
            moved++;
          }
        }
        const rows = db2.prepare("SELECT id,name FROM items WHERE active=1 AND category_id IS NULL").all();
        let done = 0, net = 0;
        for (const it of rows) {
          const g = await guessCategory(it.name);
          if (g.name) {
            db2.prepare("UPDATE items SET category_id=? WHERE id=?").run(ensureCategory(g.name), it.id);
            done++;
            if (g.source === "internet") net++;
          }
        }
        res.json({ checked: rows.length, categorised: done + moved, from_internet: net });
      }));
      router.post("/items/auto-mrp", h((req, res) => {
        const r22 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
        const rows = db2.prepare("SELECT i.id,i.name,i.gst_rate,i.retail_price,i.wholesale_price,COALESCE(c.name,'Uncategorised') category FROM items i LEFT JOIN categories c ON c.id=i.category_id WHERE i.active=1 AND COALESCE(i.mrp,0)<=0").all();
        const byCat = {}, missing = [];
        db2.transaction(() => {
          for (const it of rows) {
            const g = byCat[it.category] || (byCat[it.category] = { found: 0, missing: 0 });
            const mrp = mrpFromName(it.name);
            if (!mrp) {
              g.missing++;
              missing.push({ id: it.id, name: it.name, category: it.category });
              continue;
            }
            const ex = Math.round((mrp / (1 + (it.gst_rate || 0) / 100) + Number.EPSILON) * 1e6) / 1e6;
            db2.prepare("UPDATE items SET mrp=?, retail_price=CASE WHEN COALESCE(retail_price,0)<=0 THEN ? ELSE retail_price END, wholesale_price=CASE WHEN COALESCE(wholesale_price,0)<=0 THEN ? ELSE wholesale_price END WHERE id=?").run(mrp, ex, ex, it.id);
            g.found++;
          }
        })();
        const found = Object.values(byCat).reduce((a, g) => a + g.found, 0);
        res.json({ checked: rows.length, found, still_missing: missing.length, by_category: byCat, missing: missing.slice(0, 50) });
      }));
      router.post("/items/bulk-prices", h((req, res) => {
        const b = req.body || {};
        const catId = b.category_id ? Number(b.category_id) : null;
        const parse = (v, label) => {
          if (v === void 0 || v === null || String(v).trim() === "") return null;
          const n = Number(v);
          if (!Number.isFinite(n) || n < 0 || n >= 100) throw new HttpError2(400, `${label} must be a percentage from 0 to 99.99`);
          return n;
        };
        const retailOff = parse(b.retail_off, "Retail below MRP"), wholesaleOff = parse(b.wholesale_off, "Wholesale below MRP");
        if (retailOff === null && wholesaleOff === null) throw new HttpError2(400, "Enter the retail and/or wholesale percentage below MRP");
        const rows = db2.prepare("SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items WHERE active=1 AND (? IS NULL OR category_id=?) ORDER BY name").all(catId, catId);
        const r22 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
        const boxOf = (it) => Math.max(1, parseInt(it.pcs_per_box, 10) || 1);
        const price = (it, off) => {
          const perPieceIncl = it.mrp * (1 - off / 100);
          const ppb = boxOf(it);
          const incl = ppb > 1 ? Math.round(perPieceIncl * ppb + Number.EPSILON) / ppb : perPieceIncl;
          return Math.round((incl / (1 + (it.gst_rate || 0) / 100) + Number.EPSILON) * 1e8) / 1e8;
        };
        const boxIncl = (it, v) => r22(v * boxOf(it) * (1 + (it.gst_rate || 0) / 100));
        const changes = [];
        let skipped = 0;
        for (const it of rows) {
          if (!(it.mrp > 0)) {
            skipped++;
            continue;
          }
          const c = { id: it.id, name: it.name, mrp: it.mrp };
          if (retailOff !== null) {
            c.retail_old = it.retail_price;
            c.retail_new = price(it, retailOff);
            c.retail_box = boxIncl(it, c.retail_new);
          }
          if (wholesaleOff !== null) {
            c.wholesale_old = it.wholesale_price;
            c.wholesale_new = price(it, wholesaleOff);
            c.wholesale_box = boxIncl(it, c.wholesale_new);
          }
          changes.push(c);
        }
        if (!b.preview) {
          db2.transaction(() => {
            for (const c of changes) {
              if (c.retail_new !== void 0) db2.prepare("UPDATE items SET retail_price=? WHERE id=?").run(c.retail_new, c.id);
              if (c.wholesale_new !== void 0) db2.prepare("UPDATE items SET wholesale_price=? WHERE id=?").run(c.wholesale_new, c.id);
            }
          })();
        }
        res.json({ updated: b.preview ? 0 : changes.length, would_update: changes.length, skipped_no_mrp: skipped, sample: changes.slice(0, 5) });
      }));
      function fixPacks() {
        let changed = 0, checked = 0;
        for (const it of db2.prepare("SELECT id,name,pcs_per_box FROM items WHERE active=1").all()) {
          const pk = packFromName(it.name);
          if (!pk) continue;
          checked++;
          if (it.pcs_per_box !== pk) {
            db2.prepare("UPDATE items SET pcs_per_box=? WHERE id=?").run(pk, it.id);
            changed++;
          }
        }
        return { checked, changed };
      }
      router.post("/items/set-prices", h((req, res) => res.json(P.setPrices(req.body || {}))));
      router.get("/items/mrp-table", h((req, res) => res.json(P.mrpTable(req.query))));
      router.get("/items/clean-preview", h((req, res) => res.json(T.cleanPreview(req.query))));
      router.post("/items/clean-names", h((req, res) => res.json(T.applyClean(req.body || {}))));
      router.post("/items/merge", h((req, res) => res.json(T.mergeItems(req.body || {}))));
      router.post("/items/online/search", ha(async (req, res) => res.json(await W.search(req.body || {}))));
      router.post("/items/online/fetch", ha(async (req, res) => res.json(await W.fetchList(req.body || {}))));
      router.post("/items/online/extract", h((req, res) => res.json(T.extractList(req.body || {}))));
      router.post("/items/bulk-add", h((req, res) => res.status(201).json(T.bulkAdd(req.body || {}))));
      router.post("/items/auto-pack", h((req, res) => res.json(fixPacks())));
      router.get("/items/mrp-groups", h((req, res) => {
        const catId = req.query.category_id ? Number(req.query.category_id) : null;
        const rows = db2.prepare(
          `SELECT mrp, COUNT(*) items, MIN(retail_price) retail_min, MAX(retail_price) retail_max, MIN(wholesale_price) wholesale_min, MAX(wholesale_price) wholesale_max,
            MIN(gst_rate) gst_min, MAX(gst_rate) gst_max,
            MAX(retail_price * (1 + COALESCE(gst_rate,0) / 100.0)) retail_incl_max,
            MAX(retail_price * MAX(1, COALESCE(pcs_per_box,1))) retail_box_max,
            MAX(retail_price * MAX(1, COALESCE(pcs_per_box,1)) * (1 + COALESCE(gst_rate,0) / 100.0)) retail_box_incl_max,
            MAX(wholesale_price * (1 + COALESCE(gst_rate,0) / 100.0)) wholesale_incl_max,
            MAX(wholesale_price * MAX(1, COALESCE(pcs_per_box,1))) wholesale_box_max,
            MAX(wholesale_price * MAX(1, COALESCE(pcs_per_box,1)) * (1 + COALESCE(gst_rate,0) / 100.0)) wholesale_box_incl_max
     FROM items WHERE active=1 AND mrp > 0 AND (? IS NULL OR category_id=?) GROUP BY mrp ORDER BY mrp`
        ).all(catId, catId);
        res.json(rows);
      }));
      router.post("/items/bulk-prices-by-mrp", h((req, res) => {
        const b = req.body || {};
        const catId = b.category_id ? Number(b.category_id) : null;
        const tiers = (Array.isArray(b.tiers) ? b.tiers : []).map((t) => {
          const num = (v, label) => {
            if (v === void 0 || v === null || String(v).trim() === "") return null;
            const n = Number(v);
            if (!Number.isFinite(n) || n < 0) throw new HttpError2(400, `${label} must be a number (0 or more)`);
            return n;
          };
          const mrp = num(t.mrp, "MRP");
          if (!(mrp > 0)) throw new HttpError2(400, "Each row needs an MRP");
          return { mrp, retail: num(t.retail, `Retail price for MRP ${mrp}`), wholesale: num(t.wholesale, `Wholesale price for MRP ${mrp}`) };
        }).filter((t) => t.retail !== null || t.wholesale !== null);
        if (!tiers.length) throw new HttpError2(400, "Enter a retail and/or wholesale price for at least one MRP");
        const items = db2.prepare("SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items WHERE active=1 AND mrp>0 AND (? IS NULL OR category_id=?)").all(catId, catId);
        const r22 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
        const r6 = (n) => Math.round((n + Number.EPSILON) * 1e8) / 1e8;
        const perBox = String(b.per || "piece").toLowerCase() === "box";
        const exGst = (it, v) => r6((b.include_gst ? v / (1 + (it.gst_rate || 0) / 100) : v) / (perBox ? Math.max(1, it.pcs_per_box || 1) : 1));
        const changes = [];
        const perTier = tiers.map((t) => ({ mrp: t.mrp, items: 0 }));
        for (const it of items) {
          const ti = tiers.findIndex((t2) => Math.abs(t2.mrp - it.mrp) < 5e-3);
          if (ti < 0) continue;
          const t = tiers[ti];
          perTier[ti].items++;
          changes.push({
            id: it.id,
            name: it.name,
            mrp: it.mrp,
            ...t.retail !== null ? { retail_old: it.retail_price, retail_new: exGst(it, t.retail), retail_box: r22(exGst(it, t.retail) * Math.max(1, it.pcs_per_box || 1) * (1 + (it.gst_rate || 0) / 100)) } : {},
            ...t.wholesale !== null ? { wholesale_old: it.wholesale_price, wholesale_new: exGst(it, t.wholesale), wholesale_box: r22(exGst(it, t.wholesale) * Math.max(1, it.pcs_per_box || 1) * (1 + (it.gst_rate || 0) / 100)) } : {}
          });
        }
        if (!b.preview) {
          db2.transaction(() => {
            for (const c of changes) {
              if (c.retail_new !== void 0) db2.prepare("UPDATE items SET retail_price=? WHERE id=?").run(c.retail_new, c.id);
              if (c.wholesale_new !== void 0) db2.prepare("UPDATE items SET wholesale_price=? WHERE id=?").run(c.wholesale_new, c.id);
            }
          })();
        }
        res.json({ updated: b.preview ? 0 : changes.length, would_update: changes.length, per_mrp: perTier, sample: changes.slice(0, 5) });
      }));
      router.delete("/items/:id", h((req, res) => {
        const it = db2.prepare("SELECT * FROM items WHERE id=?").get(req.params.id);
        if (!it) throw new HttpError2(404, "Item not found");
        const used = db2.prepare("SELECT (SELECT COUNT(*) FROM invoice_lines WHERE item_id=@i) + (SELECT COUNT(*) FROM purchase_lines WHERE item_id=@i) + (SELECT COUNT(*) FROM debit_note_lines WHERE item_id=@i) n").get({ i: it.id }).n;
        const stock = db2.prepare("SELECT COALESCE(SUM(qty),0) n FROM batches WHERE item_id=?").get(it.id).n;
        if (stock > 0 && !req.query.force) throw new HttpError2(409, `${it.name} still has ${stock} units in stock. Sell or adjust the stock first.`, "HAS_STOCK");
        if (used) {
          db2.prepare("UPDATE items SET active=0 WHERE id=?").run(it.id);
          return res.json({ result: "archived" });
        }
        db2.transaction(() => {
          db2.prepare("DELETE FROM schemes WHERE item_id=?").run(it.id);
          db2.prepare("DELETE FROM batches WHERE item_id=?").run(it.id);
          db2.prepare("DELETE FROM items WHERE id=?").run(it.id);
        })();
        res.json({ result: "deleted" });
      }));
      router.get("/items/:id/batches", h((req, res) => {
        res.json(db2.prepare("SELECT * FROM batches WHERE item_id=? ORDER BY exp_date").all(req.params.id));
      }));
      router.post("/batches", h((req, res) => {
        const b = req.body;
        if (!b.item_id) throw new HttpError2(400, "Choose the item");
        b.batch_no = blank(b.batch_no) || "OPENING";
        b.exp_date = blank(b.exp_date) || "2099-12-31";
        const qty = parseInt(b.qty, 10);
        if (!(qty > 0)) throw new HttpError2(400, "Quantity must be greater than zero");
        const isDate = (v) => /^\d{4}-\d{2}-\d{2}$/.test(v);
        if (!isDate(b.exp_date) || blank(b.mfg_date) && !isDate(b.mfg_date)) throw new HttpError2(400, "Dates must be in YYYY-MM-DD format");
        db2.prepare(
          `INSERT INTO batches(item_id,batch_no,mfg_date,exp_date,qty,purchase_price,mrp) VALUES(?,?,?,?,?,?,?)
     ON CONFLICT(item_id,batch_no) DO UPDATE SET qty = qty + excluded.qty,
       exp_date = excluded.exp_date, mfg_date = COALESCE(excluded.mfg_date, mfg_date)`
        ).run(b.item_id, String(b.batch_no).trim(), blank(b.mfg_date), b.exp_date, qty, blank(b.purchase_price), blank(b.mrp));
        res.status(201).json({ ok: true });
      }));
      router.get("/schemes", h((req, res) => {
        res.json(db2.prepare("SELECT s.*, i.name item_name FROM schemes s JOIN items i ON i.id=s.item_id WHERE s.active=1").all());
      }));
      router.post("/schemes", h((req, res) => {
        const b = req.body;
        if (!["FREE_QTY", "PERCENT"].includes(b.type)) throw new HttpError2(400, "Scheme type must be FREE_QTY or PERCENT");
        db2.prepare("INSERT INTO schemes(item_id,type,buy_qty,free_qty,percent,valid_from,valid_to) VALUES(?,?,?,?,?,?,?)").run(b.item_id, b.type, parseInt(b.buy_qty) || 1, parseInt(b.free_qty) || 0, Number(b.percent) || 0, blank(b.valid_from), blank(b.valid_to));
        res.status(201).json({ ok: true });
      }));
      router.delete("/schemes/:id", h((req, res) => {
        db2.prepare("UPDATE schemes SET active=0 WHERE id=?").run(req.params.id);
        res.json({ ok: true });
      }));
      module.exports = router;
      module.exports.fixPacks = fixPacks;
    }
  });

  // ../../backend/src/services/vouchers.js
  var require_vouchers = __commonJS({
    "../../backend/src/services/vouchers.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { today, nextNo, HttpError: HttpError2, blank } = require_misc();
      var { r2 } = require_gst();
      var { partyBalance, settings: settings2 } = require_billing();
      var { rupeesInWords } = require_words();
      var recordVoucher = db2.transaction((b) => {
        const amount = r2(Number(b.amount));
        if (!b.party_id || !(amount > 0)) throw new HttpError2(400, "Party and a positive amount are required");
        if (!db2.prepare("SELECT 1 FROM parties WHERE id=?").get(b.party_id)) throw new HttpError2(404, "Party not found");
        const direction = String(b.direction || "RECEIVED").toUpperCase();
        if (!["RECEIVED", "PAID"].includes(direction)) throw new HttpError2(400, "Direction must be RECEIVED or PAID");
        const date = b.date || today();
        const mode = String(b.mode || "CASH").toUpperCase();
        const lg = db2.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)");
        let no;
        if (direction === "RECEIVED") {
          no = nextNo("RCT", date);
          db2.prepare("INSERT INTO receipts(receipt_no,date,party_id,salesman_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?)").run(no, date, b.party_id, blank(b.salesman_id), mode, amount, blank(b.reference));
          lg.run(b.party_id, date, "RECEIPT", no, 0, amount, `Payment received (${mode})${b.reference ? " " + b.reference : ""}`);
        } else {
          no = nextNo("PAY", date);
          db2.prepare("INSERT INTO payments(voucher_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)").run(no, date, b.party_id, mode, amount, blank(b.reference));
          lg.run(b.party_id, date, "PAYMENT", no, amount, 0, `Payment made (${mode})${b.reference ? " " + b.reference : ""}`);
        }
        return { voucher_no: no, direction, amount, balance: r2(partyBalance(b.party_id)) };
      });
      function getVoucher(voucherNo) {
        const rec = db2.prepare("SELECT receipt_no no, date, party_id, mode, amount, reference FROM receipts WHERE receipt_no=?").get(voucherNo);
        const pay = rec ? null : db2.prepare("SELECT voucher_no no, date, party_id, mode, amount, reference FROM payments WHERE voucher_no=?").get(voucherNo);
        const v = rec || pay;
        if (!v) throw new HttpError2(404, "Voucher not found");
        const party = db2.prepare("SELECT id,name,address,gstin,phone,mobiles FROM parties WHERE id=?").get(v.party_id);
        const co = settings2();
        return {
          ...v,
          direction: rec ? "RECEIVED" : "PAID",
          title: rec ? "Receipt Voucher" : "Payment Voucher",
          party,
          amount_words: rupeesInWords(v.amount),
          balance: r2(partyBalance(v.party_id)),
          company: { name: co.company_name, address: co.company_address, gstin: co.company_gstin, phone: co.company_phone }
        };
      }
      module.exports = { recordVoucher, getVoucher };
    }
  });

  // ../../backend/src/services/paymentSheet.js
  var require_paymentSheet = __commonJS({
    "../../backend/src/services/paymentSheet.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { HttpError: HttpError2, today } = require_misc();
      var { r2 } = require_gst();
      var { partyBalance } = require_billing();
      var { recordVoucher } = require_vouchers();
      var isDigit = (c) => c >= "0" && c <= "9";
      var isAsciiLetter = (c) => c >= "a" && c <= "z" || c >= "A" && c <= "Z";
      var isSpace = (c) => c === " " || c === "	" || c === "\r" || c === "\n";
      var PAY_WORDS = ["paid", "pay", "payment", "rcvd", "recd", "received", "recieved", "rec", "cash", "amt", "jama", "diya"];
      var STOP_WORDS = [
        "m",
        "s",
        "ms",
        "mss",
        "shri",
        "sri",
        "shree",
        "the",
        "and",
        "store",
        "stores",
        "traders",
        "trader",
        "trading",
        "general",
        "genral",
        "gen",
        "kirana",
        "enterprises",
        "enterprise",
        "ent",
        "agency",
        "agencies",
        "mart",
        "shop",
        "co",
        "bros",
        "brothers"
      ];
      function fixDigits(s) {
        const ch = s.split("");
        for (let i = 0; i < ch.length; i++) {
          const c = ch[i];
          const near = i > 0 && isDigit(ch[i - 1]) || i + 1 < ch.length && isDigit(ch[i + 1]);
          if (!near) continue;
          if (c === "O" || c === "o") ch[i] = "0";
          else if (c === "l" || c === "I" || c === "|") ch[i] = "1";
        }
        return ch.join("");
      }
      function trimChars(s, set) {
        let a = 0, b = s.length;
        while (a < b && set.includes(s[a])) a++;
        while (b > a && set.includes(s[b - 1])) b--;
        return s.slice(a, b);
      }
      function words(s) {
        const out = [];
        let w = "";
        for (const c of s.toLowerCase().split("")) {
          if (isAsciiLetter(c) || isDigit(c)) w += c;
          else {
            if (w) out.push(w);
            w = "";
          }
        }
        if (w) out.push(w);
        return out;
      }
      function bigrams(s) {
        const out = [];
        for (let i = 0; i + 1 < s.length; i++) out.push(s.slice(i, i + 2));
        return out;
      }
      function nameScore(a, b) {
        const wa = words(a), wb = words(b);
        const na = wa.join(""), nb = wb.join("");
        if (!na || !nb) return 0;
        if (na === nb) return 1;
        const A = bigrams(na), B3 = bigrams(nb);
        let common = 0;
        const left = B3.slice();
        for (const g of A) {
          const k = left.indexOf(g);
          if (k >= 0) {
            common++;
            left.splice(k, 1);
          }
        }
        let score = A.length + B3.length ? 2 * common / (A.length + B3.length) : 0;
        const ca = wa.filter((w) => !STOP_WORDS.includes(w)).join(""), cb = wb.filter((w) => !STOP_WORDS.includes(w)).join("");
        if (!ca.length) score = Math.min(score, 0.5);
        if (ca.length >= 3 && cb.length >= 3 && (ca === cb || cb.startsWith(ca) || ca.startsWith(cb))) score = Math.max(score, ca === cb ? 0.95 : 0.85);
        return Math.round(score * 100) / 100;
      }
      function parseLine(raw) {
        let s = fixDigits(String(raw).split("\u20B9").join(" "));
        s = s.split("/-").join(" ");
        let i = 0;
        while (i < s.length && isSpace(s[i])) i++;
        let j = i;
        while (j < s.length && isDigit(s[j])) j++;
        if (j > i && j < s.length && (s[j] === "." || s[j] === ")")) s = s.slice(j + 1);
        let first = -1;
        for (let k = 0; k < s.length; k++) if (isDigit(s[k])) {
          first = k;
          break;
        }
        const namePart = first < 0 ? s : s.slice(0, first);
        let name = trimChars(namePart, " 	,.-:=;|/");
        let payWord = false;
        for (; ; ) {
          const sp = name.lastIndexOf(" ");
          const tail = trimChars(name.slice(sp + 1).toLowerCase(), ".:-=");
          if (tail !== "rs" && !PAY_WORDS.includes(tail)) break;
          if (tail !== "rs") payWord = true;
          name = sp < 0 ? "" : trimChars(name.slice(0, sp), " 	,.-:=;|/");
        }
        const nums = [];
        if (first >= 0) {
          let sep = "";
          let k = first;
          while (k < s.length) {
            if (isDigit(s[k])) {
              let t = "";
              while (k < s.length && isDigit(s[k])) t += s[k++];
              let group = t.length, firstGroup = true;
              while (k < s.length && s[k] === "," && (firstGroup && group === 1 || !firstGroup && group === 2)) {
                let e = k + 1;
                while (e < s.length && isDigit(s[e])) e++;
                const run = e - (k + 1);
                if (!(run === 3 || run === 2 && e < s.length && s[e] === ",")) break;
                t += s.slice(k + 1, e);
                k = e;
                group = run;
                firstGroup = false;
              }
              if (k + 1 < s.length && s[k] === "." && isDigit(s[k + 1])) {
                t += s[k++];
                while (k < s.length && isDigit(s[k])) t += s[k++];
              }
              nums.push({ value: Number(t), sep });
              sep = "";
            } else sep += s[k++];
          }
        }
        const sepWords = (sep) => words(sep);
        const isPayment = (n) => n.sep.length > 0 && (!n.sep.includes(",") || sepWords(n.sep).some((w) => PAY_WORDS.includes(w)));
        let bills = nums.map((n) => n.value), payment = null;
        const last = nums[nums.length - 1];
        if (nums.length >= 2 && isPayment(last)) {
          payment = last.value;
          bills = bills.slice(0, -1);
        } else if (nums.length === 1 && (payWord || sepWords(last.sep).some((w) => PAY_WORDS.includes(w)))) {
          payment = last.value;
          bills = [];
        }
        const amount = payment !== null ? r2(payment) : r2(bills.reduce((a, b) => a + b, 0));
        return { name, bills: bills.map(r2), payment: payment === null ? null : r2(payment), amount };
      }
      function parseSheet(b) {
        const text = String(b && b.text || "").split("\r\n").join("\n").split("\r").join("\n");
        const parties = db2.prepare(`SELECT id,name FROM parties WHERE active=1 AND type <> 'SUPPLIER' ORDER BY name, id`).all();
        const billsOf = db2.prepare("SELECT id,invoice_no,date,total,paid FROM invoices WHERE party_id=? ORDER BY date DESC, id DESC");
        const rows = [];
        let lineNo = 0;
        for (const line of text.split("\n")) {
          lineNo++;
          if (!trimChars(line, " 	\r").length) continue;
          const p = parseLine(line);
          if (!p.name && !p.bills.length && p.payment === null) continue;
          const scored = parties.map((x) => ({ id: x.id, name: x.name, score: nameScore(p.name, x.name) })).filter((x) => x.score >= 0.3).sort((x, y) => y.score - x.score || (x.name < y.name ? -1 : x.name > y.name ? 1 : x.id - y.id));
          const best = scored.length && scored[0].score >= 0.6 ? scored[0] : null;
          const problems = [];
          if (!p.name) problems.push("No party name");
          else if (!best) problems.push("Party not found");
          else if (scored.length > 1 && scored[1].score === best.score) problems.push("More than one party matches");
          if (!(p.amount > 0)) problems.push("No amount");
          const used = /* @__PURE__ */ new Set();
          const billRefs = p.bills.map((amt) => {
            if (!best) return { amount: amt, invoice_no: null };
            const hit = billsOf.all(best.id).find((v) => !used.has(v.id) && Math.abs(v.total - amt) < 0.5);
            if (!hit) return { amount: amt, invoice_no: null };
            used.add(hit.id);
            return { amount: amt, invoice_no: hit.invoice_no, invoice_id: hit.id, date: hit.date };
          });
          rows.push({
            line: lineNo,
            text: trimChars(line, " 	\r"),
            name: p.name,
            party_id: best ? best.id : null,
            party_name: best ? best.name : null,
            balance: best ? r2(partyBalance(best.id)) : null,
            score: best ? best.score : 0,
            candidates: scored.slice(0, 3).map((x) => ({ id: x.id, name: x.name, score: x.score })),
            bills: billRefs,
            payment: p.payment,
            amount: p.amount,
            reference: referenceFor(billRefs),
            problems
          });
        }
        const ready = rows.filter((r) => !r.problems.length);
        return { rows, lines: rows.length, ready: ready.length, total: r2(ready.reduce((a, r) => a + r.amount, 0)) };
      }
      function referenceFor(bills) {
        if (!bills.length) return null;
        return "Bills " + bills.map((x) => x.invoice_no || String(x.amount)).join(", ");
      }
      var saveSheet = db2.transaction((b) => {
        const rows = b && Array.isArray(b.rows) ? b.rows : [];
        if (!rows.length) throw new HttpError2(400, "No payments to save");
        const date = b && b.date || today();
        const mode = b && b.mode || "CASH";
        const saved = rows.map((r, i) => {
          try {
            const v = recordVoucher({ party_id: r.party_id, amount: r.amount, date, mode, reference: r.reference || null, direction: "RECEIVED" });
            const p = db2.prepare("SELECT name FROM parties WHERE id=?").get(r.party_id);
            return { voucher_no: v.voucher_no, party_id: r.party_id, party: p.name, amount: v.amount, balance: v.balance };
          } catch (e) {
            throw new HttpError2(e.status || 400, `Row ${i + 1}: ${e.message}`);
          }
        });
        return { saved, count: saved.length, total: r2(saved.reduce((a, x) => a + x.amount, 0)) };
      });
      module.exports = { parseSheet, saveSheet, parseLine, nameScore };
    }
  });

  // ../../backend/src/routes/parties.js
  var require_parties = __commonJS({
    "../../backend/src/routes/parties.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var db2 = require_db();
      var { h, HttpError: HttpError2, blank, today, normDays } = require_misc();
      var { r2 } = require_gst();
      var { recordVoucher, getVoucher } = require_vouchers();
      var Sheet = require_paymentSheet();
      var { fyRange } = require_fy();
      var BAL_AT = `COALESCE((SELECT SUM(debit)-SUM(credit) FROM ledger l WHERE l.party_id=p.id AND l.date <= @to),0)`;
      router.get("/parties", h((req, res) => {
        const q = `%${(req.query.q || "").trim()}%`;
        const kind = req.query.kind === "SUPPLIER" ? `AND p.type = 'SUPPLIER'` : req.query.kind === "CUSTOMER" ? `AND p.type <> 'SUPPLIER'` : "";
        res.json(db2.prepare(
          `SELECT p.*, ${BAL_AT} balance, r.name route_name FROM parties p LEFT JOIN routes r ON r.id=p.route_id
     WHERE p.active=1 ${kind} AND (p.name LIKE @q OR p.phone LIKE @q OR p.gstin LIKE @q OR COALESCE(p.mobiles,'') LIKE @q OR COALESCE(p.tel,'') LIKE @q) ORDER BY p.name`
        ).all({ q, to: fyRange(req.query.fy).to }));
      }));
      function resolveRoute(b) {
        const nr = b.new_route;
        if (nr && blank(nr.name)) {
          const days = normDays(nr.days !== void 0 ? nr.days : nr.day_of_week);
          const info = db2.prepare("INSERT INTO routes(name,salesman_id,day_of_week,days) VALUES(?,?,?,?)").run(String(nr.name).trim(), blank(nr.salesman_id), days ? parseInt(days) : null, days);
          return Number(info.lastInsertRowid);
        }
        return blank(b.route_id);
      }
      var GSTIN_RE = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
      function cleanParty(b, cur) {
        const get = (k) => b[k] !== void 0 ? b[k] : cur ? cur[k] : void 0;
        const txt = (k, max = 200) => {
          const v = get(k);
          return blank(v) === null ? null : String(v).trim().slice(0, max);
        };
        const o = { name: String(get("name") ?? "").trim().replace(/\s+/g, " ") };
        if (!o.name) throw new HttpError2(400, "Party name is required");
        o.address = txt("address", 400);
        o.gstin = txt("gstin", 15) && txt("gstin", 15).toUpperCase().replace(/\s+/g, "");
        if (o.gstin && !GSTIN_RE.test(o.gstin)) throw new HttpError2(400, `GSTIN "${o.gstin}" is not valid (15 characters, e.g. 09ABCDE1234F1Z5)`);
        o.state_code = txt("state_code", 2) || (o.gstin ? o.gstin.slice(0, 2) : null);
        if (o.state_code && !/^\d{2}$/.test(o.state_code)) throw new HttpError2(400, "State code must be 2 digits, e.g. 09");
        o.pan = txt("pan", 10) || (o.gstin ? o.gstin.slice(2, 12) : null) || null;
        if (o.pan) {
          o.pan = o.pan.toUpperCase();
          if (!/^[A-Z]{5}\d{4}[A-Z]$/.test(o.pan)) throw new HttpError2(400, "PAN must look like ABCDE1234F");
        }
        o.fssai = txt("fssai", 14);
        if (o.fssai && !/^\d{14}$/.test(o.fssai)) throw new HttpError2(400, "FSSAI number must be 14 digits");
        o.email = txt("email", 120);
        if (o.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(o.email)) throw new HttpError2(400, "Email address is not valid");
        o.tel = txt("tel", 40);
        o.phone = txt("phone", 40);
        const mob = get("mobiles");
        const list = (Array.isArray(mob) ? mob : String(mob ?? "").split(/[,;\n]+/)).map((x) => String(x).trim()).filter(Boolean);
        o.mobiles = [...new Set(list)].join(", ") || null;
        o.type = ["RETAILER", "WHOLESALER", "SUPPLIER"].includes(get("type")) ? get("type") : "RETAILER";
        o.price_tier = ["RETAIL", "WHOLESALE", "MRP"].includes(get("price_tier")) ? get("price_tier") : "RETAIL";
        const cl = Number(get("credit_limit") || 0), cd = Math.floor(Number(get("credit_days") || 0));
        if (!(cl >= 0) || !(cd >= 0)) throw new HttpError2(400, "Credit limit and credit days cannot be negative");
        o.credit_limit = cl;
        o.credit_days = cd;
        return o;
      }
      router.post("/parties", h((req, res) => {
        const b = req.body || {};
        const o = cleanParty(b, null);
        const id = db2.transaction(() => {
          o.route_id = resolveRoute(b);
          const info = db2.prepare(
            `INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,fssai,pan,email,type,price_tier,credit_limit,credit_days,route_id)
       VALUES(@name,@gstin,@state_code,@phone,@tel,@mobiles,@address,@fssai,@pan,@email,@type,@price_tier,@credit_limit,@credit_days,@route_id)`
          ).run(o);
          const pid = Number(info.lastInsertRowid);
          const opening = Number(b.opening_balance) || 0;
          if (opening !== 0) {
            db2.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)").run(pid, today(), "OPENING", "OPENING", opening > 0 ? opening : 0, opening < 0 ? -opening : 0, "Opening balance");
          }
          return pid;
        })();
        res.status(201).json({ id });
      }));
      router.put("/parties/:id", h((req, res) => {
        const cur = db2.prepare("SELECT * FROM parties WHERE id=?").get(req.params.id);
        if (!cur) throw new HttpError2(404, "Party not found");
        const b = req.body || {};
        const o = cleanParty(b, cur);
        db2.transaction(() => {
          o.route_id = resolveRoute({ ...b, route_id: "route_id" in b ? b.route_id : cur.route_id });
          db2.prepare(
            `UPDATE parties SET name=@name,gstin=@gstin,state_code=@state_code,phone=@phone,tel=@tel,mobiles=@mobiles,address=@address,
         fssai=@fssai,pan=@pan,email=@email,type=@type,price_tier=@price_tier,credit_limit=@credit_limit,credit_days=@credit_days,route_id=@route_id WHERE id=@id`
          ).run({ ...o, id: cur.id });
        })();
        res.json({ ok: true });
      }));
      router.delete("/parties/:id", h((req, res) => {
        const p = db2.prepare("SELECT * FROM parties WHERE id=?").get(req.params.id);
        if (!p) throw new HttpError2(404, "Party not found");
        const used = db2.prepare(
          `SELECT (SELECT COUNT(*) FROM ledger WHERE party_id=@i) + (SELECT COUNT(*) FROM invoices WHERE party_id=@i) + (SELECT COUNT(*) FROM purchases WHERE party_id=@i) + (SELECT COUNT(*) FROM debit_notes WHERE party_id=@i) n`
        ).get({ i: p.id }).n;
        if (used) {
          db2.prepare("UPDATE parties SET active=0 WHERE id=?").run(p.id);
          return res.json({ result: "archived" });
        }
        db2.prepare("DELETE FROM parties WHERE id=?").run(p.id);
        res.json({ result: "deleted" });
      }));
      router.get("/parties/:id/ledger", h((req, res) => {
        const party = db2.prepare("SELECT * FROM parties WHERE id=?").get(req.params.id);
        if (!party) throw new HttpError2(404, "Party not found");
        const fy = fyRange(req.query.fy);
        const open = r2(db2.prepare("SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=? AND date < ?").get(party.id, fy.from).b);
        let run = open;
        const rows = db2.prepare("SELECT * FROM ledger WHERE party_id=? AND date BETWEEN ? AND ? ORDER BY date, id").all(party.id, fy.from, fy.to).map((r) => ({ ...r, balance: run = r2(run + r.debit - r.credit) }));
        res.json({ party, fy: fy.label, opening_balance: open, balance: run, entries: rows });
      }));
      router.get("/vouchers/:no", h((req, res) => res.json(getVoucher(req.params.no))));
      router.post("/vouchers", h((req, res) => res.status(201).json(recordVoucher(req.body))));
      router.post("/receipts/sheet/parse", h((req, res) => res.json(Sheet.parseSheet(req.body))));
      router.post("/receipts/sheet", h((req, res) => res.status(201).json(Sheet.saveSheet(req.body))));
      router.post("/receipts", h((req, res) => res.status(201).json(recordVoucher({ ...req.body, direction: "RECEIVED" }))));
      router.get("/receipts", h((req, res) => {
        res.json(db2.prepare(
          `SELECT r.*, p.name party_name, s.name salesman_name FROM receipts r JOIN parties p ON p.id=r.party_id
     LEFT JOIN salesmen s ON s.id=r.salesman_id WHERE r.date=? ORDER BY r.id DESC`
        ).all(req.query.date || today()));
      }));
      module.exports = router;
    }
  });

  // ../../backend/src/routes/salesmen.js
  var require_salesmen = __commonJS({
    "../../backend/src/routes/salesmen.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var db2 = require_db();
      var { h, HttpError: HttpError2, blank, today, normDays } = require_misc();
      var { r2 } = require_gst();
      router.get("/salesmen", h((req, res) => {
        res.json(db2.prepare("SELECT * FROM salesmen WHERE active=1 ORDER BY name").all());
      }));
      router.post("/salesmen", h((req, res) => {
        if (!blank(req.body.name)) throw new HttpError2(400, "Name is required");
        const info = db2.prepare("INSERT INTO salesmen(name,phone,monthly_target) VALUES(?,?,?)").run(req.body.name.trim(), blank(req.body.phone), Number(req.body.monthly_target) || 0);
        res.status(201).json({ id: Number(info.lastInsertRowid) });
      }));
      router.put("/salesmen/:id", h((req, res) => {
        const cur = db2.prepare("SELECT * FROM salesmen WHERE id=?").get(req.params.id);
        if (!cur) throw new HttpError2(404, "Salesman not found");
        const b = { ...cur, ...req.body };
        db2.prepare("UPDATE salesmen SET name=?,phone=?,monthly_target=?,active=? WHERE id=?").run(b.name, blank(b.phone), Number(b.monthly_target) || 0, b.active ? 1 : 0, cur.id);
        res.json({ ok: true });
      }));
      router.get("/routes", h((req, res) => {
        res.json(db2.prepare(
          `SELECT r.*, s.name salesman_name, (SELECT COUNT(*) FROM parties p WHERE p.route_id=r.id AND p.active=1) outlets
     FROM routes r LEFT JOIN salesmen s ON s.id=r.salesman_id ORDER BY r.days, r.name`
        ).all());
      }));
      router.post("/routes", h((req, res) => {
        const b = req.body;
        if (!blank(b.name)) throw new HttpError2(400, "Route name is required");
        const days = normDays(b.days !== void 0 ? b.days : b.day_of_week);
        const info = db2.prepare("INSERT INTO routes(name,salesman_id,day_of_week,days) VALUES(?,?,?,?)").run(b.name.trim(), blank(b.salesman_id), days ? parseInt(days) : null, days);
        res.status(201).json({ id: Number(info.lastInsertRowid) });
      }));
      router.put("/routes/:id", h((req, res) => {
        const cur = db2.prepare("SELECT * FROM routes WHERE id=?").get(req.params.id);
        if (!cur) throw new HttpError2(404, "Route not found");
        const b = { ...cur, ...req.body };
        const days = normDays(req.body.days !== void 0 ? req.body.days : req.body.day_of_week !== void 0 ? req.body.day_of_week : cur.days);
        db2.prepare("UPDATE routes SET name=?,salesman_id=?,day_of_week=?,days=? WHERE id=?").run(b.name, blank(b.salesman_id), days ? parseInt(days) : null, days, cur.id);
        res.json({ ok: true });
      }));
      router.delete("/routes/:id", h((req, res) => {
        db2.transaction(() => {
          db2.prepare("UPDATE parties SET route_id=NULL WHERE route_id=?").run(req.params.id);
          db2.prepare("DELETE FROM routes WHERE id=?").run(req.params.id);
        })();
        res.json({ ok: true });
      }));
      router.get("/salesmen/:id/beat", h((req, res) => {
        const day = req.query.day !== void 0 ? parseInt(req.query.day) : (/* @__PURE__ */ new Date()).getDay();
        const rows = db2.prepare(
          `SELECT p.id, p.name, p.phone, p.address, p.credit_limit, r.name route_name,
       COALESCE((SELECT SUM(debit)-SUM(credit) FROM ledger l WHERE l.party_id=p.id AND l.date <= @to),0) outstanding,
       (SELECT MAX(date) FROM invoices i WHERE i.party_id=p.id AND i.date <= @to) last_order
     FROM parties p JOIN routes r ON r.id=p.route_id
     WHERE r.salesman_id=@sm AND (',' || COALESCE(r.days, CAST(r.day_of_week AS TEXT), '') || ',') LIKE '%,' || @day || ',%' AND p.active=1 ORDER BY r.name, p.name`
        ).all({ sm: req.params.id, day: String(day), to: require_fy().fyRange(req.query.fy).to });
        res.json({ day, outlets: rows, total_outstanding: r2(rows.reduce((a, r) => a + r.outstanding, 0)) });
      }));
      router.get("/salesmen/:id/performance", h((req, res) => {
        const sm = db2.prepare("SELECT * FROM salesmen WHERE id=?").get(req.params.id);
        if (!sm) throw new HttpError2(404, "Salesman not found");
        const fyr = require_fy().fyRange(req.query.fy);
        const cl = (d) => d < fyr.from ? fyr.from : d > fyr.to ? fyr.to : d;
        const month = req.query.month || cl(today()).slice(0, 7);
        const date = req.query.date || cl(today());
        const val = (sql, ...a) => db2.prepare(sql).get(...a);
        const sales = val(`SELECT COALESCE(SUM(total),0) v, COUNT(*) n FROM invoices WHERE salesman_id=? AND substr(date,1,7)=?`, sm.id, month);
        const coll = val(`SELECT COALESCE(SUM(amount),0) v FROM receipts WHERE salesman_id=? AND substr(date,1,7)=?`, sm.id, month);
        const dayInv = val(
          `SELECT COUNT(*) n, COALESCE(SUM(total),0) total, COALESCE(SUM(paid),0) paid FROM invoices WHERE salesman_id=? AND date=?`,
          sm.id,
          date
        );
        const byMode = db2.prepare(`SELECT mode, COALESCE(SUM(amount),0) amount FROM receipts WHERE salesman_id=? AND date=? GROUP BY mode`).all(sm.id, date);
        res.json({
          salesman: sm,
          month,
          target: sm.monthly_target,
          sales: r2(sales.v),
          invoices: sales.n,
          collections: r2(coll.v),
          achievement_pct: sm.monthly_target > 0 ? r2(sales.v / sm.monthly_target * 100) : null,
          day: { date, bills: dayInv.n, sales: r2(dayInv.total), credit_given: r2(dayInv.total - dayInv.paid), collected_by_mode: byMode }
        });
      }));
      module.exports = router;
    }
  });

  // ../../backend/src/services/ewayBill.js
  var require_ewayBill = __commonJS({
    "../../backend/src/services/ewayBill.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { HttpError: HttpError2 } = require_misc();
      var { r2 } = require_gst();
      var { settings: settings2 } = require_billing();
      var MODES = { 1: "Road", 2: "Rail", 3: "Air", 4: "Ship" };
      var isDigit = (c) => c >= "0" && c <= "9";
      var isAlnum = (c) => isDigit(c) || c >= "A" && c <= "Z";
      var trim = (v) => v === void 0 || v === null ? "" : String(v).trim();
      function pinFrom(address) {
        const s = trim(address);
        let found = "";
        let i = 0;
        while (i < s.length) {
          if (isDigit(s[i])) {
            let j = i;
            while (j < s.length && isDigit(s[j])) j++;
            if (j - i === 6 && s[i] !== "0") found = s.slice(i, j);
            i = j;
          } else i++;
        }
        return found;
      }
      function addressParts(address) {
        const flat = trim(address).split("\r").join(" ").split("\n").join(", ");
        const parts = flat.split(",").map((x) => x.trim()).filter((x) => x.length);
        let place = "";
        for (let k = parts.length - 1; k >= 0 && !place; k--) {
          let letters = "";
          for (const c of parts[k]) if (!isDigit(c) && c !== "-") letters += c;
          letters = letters.trim();
          if (letters.length >= 2) place = letters;
        }
        const one = parts.join(", ");
        return { addr1: one.slice(0, 120), addr2: one.slice(120, 240), place: place.slice(0, 50) };
      }
      var dmy = (iso) => iso && iso.length >= 10 ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : "";
      var upperNoSpace = (v) => {
        let o = "";
        for (const c of trim(v).toUpperCase()) if (c !== " " && c !== "-" && c !== ".") o += c;
        return o;
      };
      var isPin = (p) => p.length === 6 && p[0] !== "0" && [...p].every(isDigit);
      var isIsoDate = (d) => d.length === 10 && d[4] === "-" && d[7] === "-" && [...d.slice(0, 4) + d.slice(5, 7) + d.slice(8)].every(isDigit);
      function loadBill(id) {
        const inv = db2.prepare(`SELECT i.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state
    FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE i.id=?`).get(Number(id));
        if (!inv) throw new HttpError2(404, "Bill not found");
        return inv;
      }
      function details(id) {
        const inv = loadBill(id);
        const co = settings2();
        let saved = {};
        try {
          saved = inv.ewb_transport ? JSON.parse(inv.ewb_transport) : {};
        } catch (_) {
          saved = {};
        }
        return {
          bill_id: inv.id,
          invoice_no: inv.invoice_no,
          date: inv.date,
          total: inv.total,
          party: inv.party_name || null,
          needed: inv.total >= 5e4,
          from_pincode: saved.from_pincode || trim(co.company_pincode) || pinFrom(co.company_address),
          to_pincode: saved.to_pincode || pinFrom(inv.party_address),
          distance: saved.distance !== void 0 ? saved.distance : null,
          mode: Number(saved.mode) || 1,
          vehicle_no: saved.vehicle_no || "",
          vehicle_type: saved.vehicle_type || "R",
          transporter_id: saved.transporter_id || "",
          transporter_name: saved.transporter_name || "",
          trans_doc_no: saved.trans_doc_no || "",
          trans_doc_date: saved.trans_doc_date || "",
          ewb_no: inv.ewb_no || null,
          ewb_date: inv.ewb_date || null,
          ewb_valid: inv.ewb_valid || null
        };
      }
      function build(id, b) {
        b = b || {};
        const inv = loadBill(id);
        const co = settings2();
        if (!inv.party_id) throw new HttpError2(400, "Choose the customer on this bill first: an e-way bill needs the buyer\u2019s name and address.");
        const fromGstin = upperNoSpace(co.company_gstin);
        if (fromGstin.length !== 15) throw new HttpError2(400, "Add your GSTIN in Settings \u203A Companies to make an e-way bill.");
        let last = {};
        try {
          last = inv.ewb_transport ? JSON.parse(inv.ewb_transport) : {};
        } catch (_) {
          last = {};
        }
        const fromPin = trim(b.from_pincode) || trim(last.from_pincode) || trim(co.company_pincode) || pinFrom(co.company_address);
        if (!isPin(fromPin)) throw new HttpError2(400, "Your PIN code is needed (6 digits): type it here or add it to your address in Settings \u203A Companies.");
        const toPin = trim(b.to_pincode) || trim(last.to_pincode) || pinFrom(inv.party_address);
        if (!isPin(toPin)) throw new HttpError2(400, `The PIN code of ${inv.party_name} is needed (6 digits): type it here or add it to the party\u2019s address.`);
        const dist = trim(b.distance) === "" ? NaN : Number(b.distance);
        if (!Number.isInteger(dist) || dist < 0 || dist > 4e3) throw new HttpError2(400, "Distance must be a whole number of km from 0 to 4000 (0 lets the portal work it out from the PIN codes).");
        const modeText = trim(b.mode).toLowerCase();
        const mode = ["1", "2", "3", "4"].includes(modeText) ? Number(modeText) : ["road", "rail", "air", "ship"].indexOf(modeText) + 1 || (modeText ? 0 : 1);
        if (!mode) throw new HttpError2(400, "Mode must be road, rail, air or ship");
        const vehicle = upperNoSpace(b.vehicle_no);
        if (vehicle && (vehicle.length < 6 || vehicle.length > 15 || ![...vehicle].every(isAlnum))) throw new HttpError2(400, `Vehicle number "${trim(b.vehicle_no)}" does not look right (e.g. UP20AB1234)`);
        const transId = upperNoSpace(b.transporter_id);
        if (transId && (transId.length !== 15 || ![...transId].every(isAlnum))) throw new HttpError2(400, "Transporter ID is the transporter\u2019s 15-character GSTIN or TRANSIN");
        const docNo = trim(b.trans_doc_no).slice(0, 15), docDate = trim(b.trans_doc_date);
        if (docDate && !isIsoDate(docDate)) throw new HttpError2(400, "Transport document date must be YYYY-MM-DD");
        if (mode === 1 && !vehicle && !transId) throw new HttpError2(400, "Enter the vehicle number, or the transporter ID if the transporter will add the vehicle later.");
        if (mode !== 1 && !docNo) throw new HttpError2(400, `For ${MODES[mode].toLowerCase()} transport enter the RR / airway bill / bill of lading number.`);
        const vType = trim(b.vehicle_type).toUpperCase() === "O" ? "O" : "R";
        const lines = db2.prepare(`SELECT l.item_id, it.name, it.hsn, l.qty, l.free_qty, l.taxable, l.gst_rate, l.cgst, l.sgst, l.igst
    FROM invoice_lines l JOIN items it ON it.id=l.item_id WHERE l.invoice_id=? ORDER BY l.id`).all(inv.id);
        const noHsn = [];
        const byItem = [];
        for (const l of lines) {
          const hsn = trim(l.hsn);
          if (!hsn || ![...hsn].every(isDigit)) {
            if (!noHsn.includes(l.name)) noHsn.push(l.name);
            continue;
          }
          let g = byItem.find((x) => x.item_id === l.item_id && x.gst_rate === l.gst_rate);
          if (!g) {
            g = { item_id: l.item_id, name: l.name, hsn, gst_rate: l.gst_rate, qty: 0, taxable: 0 };
            byItem.push(g);
          }
          g.qty += l.qty + l.free_qty;
          g.taxable = r2(g.taxable + l.taxable);
        }
        if (noHsn.length) throw new HttpError2(400, `Add the HSN code (Stock \u203A edit item) for: ${noHsn.slice(0, 5).join(", ")}${noHsn.length > 5 ? ` and ${noHsn.length - 5} more` : ""}`);
        const intra = !(inv.igst > 0);
        let main = byItem[0];
        for (const g of byItem) if (g.taxable > main.taxable) main = g;
        const from = addressParts(co.company_address), to = addressParts(inv.party_address);
        const fromState = Number(trim(co.state_code) || fromGstin.slice(0, 2));
        const toGstin = upperNoSpace(inv.party_gstin);
        const toState = Number(trim(inv.party_state) || (toGstin.length === 15 ? toGstin.slice(0, 2) : "") || (intra ? fromState : 0));
        const docNoBill = inv.invoice_no.length > 16 ? inv.invoice_no.slice(inv.invoice_no.length - 16) : inv.invoice_no;
        const bill = {
          userGstin: fromGstin,
          supplyType: "O",
          subSupplyType: 1,
          subSupplyDesc: "",
          docType: "INV",
          docNo: docNoBill,
          docDate: dmy(inv.date),
          transType: 1,
          fromGstin,
          fromTrdName: trim(co.company_name).slice(0, 100),
          fromAddr1: from.addr1,
          fromAddr2: from.addr2,
          fromPlace: from.place,
          fromPincode: Number(fromPin),
          fromStateCode: fromState,
          actualFromStateCode: fromState,
          toGstin: toGstin.length === 15 ? toGstin : "URP",
          toTrdName: trim(inv.party_name).slice(0, 100),
          toAddr1: to.addr1,
          toAddr2: to.addr2,
          toPlace: to.place,
          toPincode: Number(toPin),
          toStateCode: toState,
          actualToStateCode: toState,
          totalValue: r2(inv.taxable),
          cgstValue: r2(inv.cgst),
          sgstValue: r2(inv.sgst),
          igstValue: r2(inv.igst),
          cessValue: 0,
          TotNonAdvolVal: 0,
          OthValue: r2(inv.total - (inv.taxable + inv.cgst + inv.sgst + inv.igst)),
          totInvValue: r2(inv.total),
          transMode: mode,
          transDistance: String(dist),
          transporterName: trim(b.transporter_name).slice(0, 100),
          transporterId: transId,
          transDocNo: docNo,
          transDocDate: dmy(docDate),
          vehicleNo: vehicle,
          vehicleType: vType,
          mainHsnCode: Number(main ? main.hsn : 0),
          itemList: byItem.map((g, i) => ({
            itemNo: i + 1,
            productName: g.name.slice(0, 100),
            productDesc: g.name.slice(0, 100),
            hsnCode: Number(g.hsn),
            quantity: g.qty,
            qtyUnit: "PCS",
            taxableAmount: g.taxable,
            sgstRate: intra ? g.gst_rate / 2 : 0,
            cgstRate: intra ? g.gst_rate / 2 : 0,
            igstRate: intra ? 0 : g.gst_rate,
            cessRate: 0,
            cessNonAdvol: 0
          }))
        };
        const warnings = [];
        if (inv.total < 5e4) warnings.push("This bill is under \u20B950,000: an e-way bill is usually not needed (some states ask for one for goods moved within the state).");
        if (byItem.length > 250) warnings.push("The portal takes at most 250 items on one e-way bill.");
        if (!from.place || !to.place) warnings.push(`The portal needs the place of ${!from.place ? "your business (Settings \u203A Companies \u203A address)" : `${inv.party_name} (the party\u2019s address)`}: add it before uploading.`);
        if (inv.ewb_no) warnings.push(`This bill already has e-way bill ${inv.ewb_no}. Make a new one only if that one was cancelled.`);
        const saved = {
          from_pincode: fromPin,
          to_pincode: toPin,
          distance: dist,
          mode,
          vehicle_no: vehicle,
          vehicle_type: vType,
          transporter_id: transId,
          transporter_name: trim(b.transporter_name),
          trans_doc_no: docNo,
          trans_doc_date: docDate
        };
        if (!b.preview) db2.prepare("UPDATE invoices SET ewb_transport=? WHERE id=?").run(JSON.stringify(saved), inv.id);
        let safe = "";
        for (const c of inv.invoice_no) safe += isAlnum(c.toUpperCase()) ? c : "-";
        return { file_name: `EWB_${safe}.json`, warnings, mode_name: MODES[mode], ewaybill: { version: "1.0.0621", billLists: [bill] } };
      }
      function saveNumber(id, b) {
        b = b || {};
        const inv = loadBill(id);
        const no = upperNoSpace(b.ewb_no);
        if (!no) {
          db2.prepare("UPDATE invoices SET ewb_no=NULL, ewb_date=NULL, ewb_valid=NULL WHERE id=?").run(inv.id);
          return { ok: true, ewb_no: null };
        }
        if (no.length !== 12 || ![...no].every(isDigit)) throw new HttpError2(400, "The e-way bill number is the 12-digit number the portal gives");
        const d = trim(b.ewb_date), v = trim(b.ewb_valid);
        if (d && !isIsoDate(d) || v && !isIsoDate(v)) throw new HttpError2(400, "Dates must be YYYY-MM-DD");
        if (d && v && v < d) throw new HttpError2(400, "Valid until cannot be before the e-way bill date");
        db2.prepare("UPDATE invoices SET ewb_no=?, ewb_date=?, ewb_valid=? WHERE id=?").run(no, d || inv.date, v || null, inv.id);
        return { ok: true, ewb_no: no, ewb_date: d || inv.date, ewb_valid: v || null };
      }
      module.exports = { details, build, saveNumber, pinFrom };
    }
  });

  // ../../backend/src/views/invoiceHtml.js
  var require_invoiceHtml = __commonJS({
    "../../backend/src/views/invoiceHtml.js"(exports, module) {
      init_globals();
      var esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
      var money = (n) => Number(n).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      var { words } = require_words();
      function invoiceHtml(inv, co) {
        const intra = inv.igst === 0;
        const byRate = {};
        for (const l of inv.lines) {
          const g = byRate[l.gst_rate] ||= { taxable: 0, cgst: 0, sgst: 0, igst: 0 };
          g.taxable += l.taxable;
          g.cgst += l.cgst;
          g.sgst += l.sgst;
          g.igst += l.igst;
        }
        const lines = inv.lines.map((l, i) => `
    <tr><td>${i + 1}</td><td>${esc(l.item_name)}<br><small>Batch ${esc(l.batch_no)} \xB7 Exp ${esc(l.exp_date)}</small></td>
    <td>${esc(l.hsn)}</td><td class="r">${l.qty}${l.free_qty ? ` + ${l.free_qty} free` : ""}</td>
    <td class="r">${money(l.mrp)}</td><td class="r">${money(l.rate)}</td><td class="r">${l.disc_pct ? l.disc_pct + "%" : ""}</td>
    <td class="r">${money(l.taxable)}</td><td class="r">${l.gst_rate}%</td><td class="r">${money(l.amount)}</td></tr>`).join("");
        const taxRows = Object.entries(byRate).map(([rate, g]) => `
    <tr><td>${rate}%</td><td class="r">${money(g.taxable)}</td>
    ${intra ? `<td class="r">${money(g.cgst)}</td><td class="r">${money(g.sgst)}</td>` : `<td class="r">${money(g.igst)}</td>`}</tr>`).join("");
        const due = Math.round((inv.total - inv.paid) * 100) / 100;
        return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(inv.invoice_no)}</title>
<style>
  body{font:12px -apple-system,Helvetica,Arial,sans-serif;color:#1b2a2f;margin:24px}
  h1{font-size:18px;margin:0} table{width:100%;border-collapse:collapse;margin-top:10px}
  th,td{border:1px solid #9aa8aa;padding:4px 6px;vertical-align:top} th{background:#eef2f0}
  .r{text-align:right;font-variant-numeric:tabular-nums} .head{display:flex;justify-content:space-between;gap:24px}
  .box{border:1px solid #9aa8aa;padding:8px;flex:1} small{color:#556} .tot td{font-weight:600}
  @media print{body{margin:8mm}.noprint{display:none}}
</style></head><body>
<button class="noprint" onclick="window.print()">Print</button>
<div class="head">
  <div class="box"><h1>${esc(co.company_name)}</h1>${esc(co.company_address)}<br>GSTIN: ${esc(co.company_gstin)} \xB7 State code ${esc(co.state_code)}<br>${esc(co.company_phone)}</div>
  <div class="box"><b>TAX INVOICE</b><br>No: ${esc(inv.invoice_no)}<br>Date: ${esc(inv.date)}<br>Payment: ${esc(inv.pay_mode)}<br>Salesman: ${esc(inv.salesman_name || "-")}</div>
</div>
<div class="box" style="margin-top:10px"><b>Bill to:</b> ${esc(inv.party_name || "Cash customer")}<br>${esc(inv.party_address || "")}<br>
${inv.party_gstin ? "GSTIN: " + esc(inv.party_gstin) + " \xB7 " : ""}${inv.party_state ? "State code " + esc(inv.party_state) : ""}${inv.party_pan ? " \xB7 PAN: " + esc(inv.party_pan) : ""}
${(() => {
          const ph = [...new Set([inv.party_phone, ...String(inv.party_mobiles || "").split(/[,;\/]/)].map((x) => String(x || "").trim()).filter(Boolean))];
          const bits = [ph.length ? "Ph: " + esc(ph.join(", ")) : "", inv.party_tel ? "Tel: " + esc(inv.party_tel) : "", inv.party_email ? "Email: " + esc(inv.party_email) : "", inv.party_fssai ? "FSSAI: " + esc(inv.party_fssai) : ""].filter(Boolean);
          return bits.length ? "<br>" + bits.join(" \xB7 ") : "";
        })()}
${intra ? "<br><small>Intra-state supply: CGST + SGST</small>" : "<br><small>Inter-state supply: IGST</small>"}</div>
<table><tr><th>#</th><th>Item</th><th>HSN</th><th>Qty</th><th>MRP</th><th>Rate</th><th>Disc</th><th>Taxable</th><th>GST</th><th>Amount</th></tr>${lines}</table>
<div class="head"><table style="flex:1"><tr><th>GST rate</th><th>Taxable</th>${intra ? "<th>CGST</th><th>SGST</th>" : "<th>IGST</th>"}</tr>${taxRows}</table>
<table style="flex:1" class="tot"><tr><td>Items total</td><td class="r">${money(inv.subtotal)}</td></tr>
<tr><td>Discount</td><td class="r">- ${money(inv.discount)}</td></tr><tr><td>Taxable value</td><td class="r">${money(inv.taxable)}</td></tr>
${intra ? `<tr><td>CGST</td><td class="r">${money(inv.cgst)}</td></tr><tr><td>SGST</td><td class="r">${money(inv.sgst)}</td></tr>` : `<tr><td>IGST</td><td class="r">${money(inv.igst)}</td></tr>`}
<tr><td>Round off</td><td class="r">${money(inv.round_off)}</td></tr><tr><td>Invoice total</td><td class="r">\u20B9 ${money(inv.total)}</td></tr>
<tr><td>Paid</td><td class="r">${money(inv.paid)}</td></tr><tr><td>Balance due on this bill</td><td class="r">${money(due)}</td></tr></table></div>
<p><b>Amount in words:</b> Rupees ${words(Math.round(inv.total))} Only</p>
<p><small>${esc(co.invoice_terms)}</small></p>
<p style="text-align:right;margin-top:40px">For ${esc(co.company_name)}<br><br>Authorised signatory</p>
<script>if(location.search.includes('autoprint'))window.addEventListener('load',()=>setTimeout(()=>window.print(),200));<\/script>
</body></html>`;
      }
      module.exports = { invoiceHtml };
    }
  });

  // ../../backend/src/routes/invoices.js
  var require_invoices = __commonJS({
    "../../backend/src/routes/invoices.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var EWB = require_ewayBill();
      var db2 = require_db();
      var { h, HttpError: HttpError2, today, peekNo, setNext, SERIES } = require_misc();
      var { buildInvoice, createInvoice, updateInvoice, deleteInvoice, getInvoice, settings: settings2 } = require_billing();
      var { invoiceHtml } = require_invoiceHtml();
      router.post("/invoices/preview", h((req, res) => {
        const inv = buildInvoice(req.body);
        res.json({
          lines: inv.display,
          subtotal: inv.subtotal,
          discount: inv.discount,
          taxable: inv.taxable,
          cgst: inv.cgst,
          sgst: inv.sgst,
          igst: inv.igst,
          round_off: inv.round_off,
          total: inv.total,
          supply: inv.intra ? "INTRA" : "INTER",
          tier: inv.tier
        });
      }));
      router.post("/invoices", h((req, res) => {
        const id = createInvoice(req.body);
        const inv = getInvoice(id);
        res.status(201).json({ id, invoice_no: inv.invoice_no, total: inv.total, paid: inv.paid });
      }));
      router.put("/invoices/:id", h((req, res) => {
        const id = updateInvoice(Number(req.params.id), req.body || {});
        const inv = getInvoice(id);
        res.json({ id, invoice_no: inv.invoice_no, total: inv.total, paid: inv.paid });
      }));
      router.post("/invoices/printed", h((req, res) => {
        const b = req.body || {};
        const ids = (Array.isArray(b.ids) ? b.ids : []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
        if (!ids.length) throw new HttpError2(400, "Choose the bills");
        const flag = b.printed === false || b.printed === 0 ? 0 : 1;
        const st = db2.prepare("UPDATE invoices SET printed=? WHERE id=?");
        let updated = 0;
        db2.transaction(() => {
          for (const id of ids) updated += Number(st.run(flag, id).changes);
        })();
        res.json({ updated, printed: flag });
      }));
      router.delete("/invoices/:id", h((req, res) => res.json(deleteInvoice(Number(req.params.id)))));
      router.get("/invoices", h((req, res) => {
        const date = req.query.date || today();
        res.json(db2.prepare(
          `SELECT i.id,i.invoice_no,i.date,i.total,i.paid,i.pay_mode,i.sale_type, p.name party_name, s.name salesman_name
     FROM invoices i LEFT JOIN parties p ON p.id=i.party_id LEFT JOIN salesmen s ON s.id=i.salesman_id
     WHERE i.date=? ORDER BY i.id DESC`
        ).all(date));
      }));
      router.get("/invoices/:id", h((req, res) => {
        const inv = getInvoice(req.params.id);
        if (!inv) throw new HttpError2(404, "Invoice not found");
        res.json(inv);
      }));
      router.get("/invoices/:id/ewaybill", h((req, res) => res.json(EWB.details(req.params.id))));
      router.post("/invoices/:id/ewaybill", h((req, res) => res.json(EWB.build(req.params.id, req.body || {}))));
      router.put("/invoices/:id/ewaybill", h((req, res) => res.json(EWB.saveNumber(req.params.id, req.body || {}))));
      router.get("/invoices/:id/print", h((req, res) => {
        const inv = getInvoice(req.params.id);
        if (!inv) throw new HttpError2(404, "Invoice not found");
        res.type("html").send(invoiceHtml(inv, settings2()));
      }));
      var numberingRow = (x) => ({ series: x.prefix, label: x.label, digits: x.digits, with_fy: x.withFy, last_no: x.last_no, next_no: x.next_no, next: x.next });
      router.get("/numbering", h((req, res) => res.json({ series: Object.keys(SERIES).map((k) => numberingRow(peekNo(k, req.query.date || void 0))) })));
      router.put("/numbering", h((req, res) => {
        const b = req.body || {};
        res.json(numberingRow(db2.transaction(() => setNext(String(b.series || ""), b.next, b.date || void 0))()));
      }));
      router.get("/settings", h((req, res) => res.json(settings2())));
      router.put("/settings", h((req, res) => {
        const up = db2.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value");
        const b = req.body || {};
        if (b.low_stock_qty !== void 0 && !(Number(b.low_stock_qty) >= 0)) throw new HttpError2(400, "Low-stock level must be 0 or more");
        db2.transaction(() => {
          for (const [k, v] of Object.entries(b)) up.run(k, String(v));
        })();
        res.json(settings2());
      }));
      module.exports = router;
    }
  });

  // ../../backend/src/services/purchases.js
  var require_purchases = __commonJS({
    "../../backend/src/services/purchases.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { r2 } = require_gst();
      var { today, nextNo, HttpError: HttpError2 } = require_misc();
      var { settings: settings2 } = require_billing();
      var isDate = (v) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
      var NO_EXPIRY = "2099-12-31";
      var BOX_UNIT = /^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$/i;
      var blankNum = (v) => v === void 0 || v === null || String(v).trim() === "";
      var num = (v, label, { min = 0 } = {}) => {
        if (blankNum(v)) return 0;
        const n = Number(String(v).replace(/,/g, ""));
        if (!Number.isFinite(n) || n < min) throw new HttpError2(400, `${label} must be a number${min === 0 ? " (0 or more)" : ""}`);
        return n;
      };
      function buildPurchase(input) {
        if (!input.party_id) throw new HttpError2(400, "Select the supplier");
        const party = db2.prepare("SELECT * FROM parties WHERE id=?").get(input.party_id);
        if (!party) throw new HttpError2(404, "Supplier not found");
        if (!Array.isArray(input.lines) || !input.lines.length) throw new HttpError2(400, "Add at least one item");
        const co = settings2();
        const intra = !party.state_code || party.state_code === co.state_code;
        const date = input.date || today();
        if (!isDate(date)) throw new HttpError2(400, "Bill date must be YYYY-MM-DD");
        const rows = input.lines.map((ln, i) => {
          const n = i + 1;
          const item = ln.item_id ? db2.prepare("SELECT * FROM items WHERE id=? AND active=1").get(ln.item_id) : null;
          if (!item) throw new HttpError2(400, `Row ${n}: choose the stock item`);
          const q = num(ln.qty, `Row ${n} (${item.name}) quantity`);
          if (!(q > 0) || !Number.isInteger(q)) throw new HttpError2(400, `Row ${n} (${item.name}): quantity must be a whole number of at least 1`);
          const unit = String(ln.unit || item.unit || "PCS").trim().toUpperCase().slice(0, 8) || "PCS";
          const ppb = Math.max(1, item.pcs_per_box || 1);
          const pcs = BOX_UNIT.test(unit) ? q * ppb : q;
          const rate = num(ln.rate, `Row ${n} (${item.name}) price`);
          const amount = blankNum(ln.amount) ? r2(q * rate) : r2(num(ln.amount, `Row ${n} (${item.name}) amount`));
          const exp = ln.exp_date ? ln.exp_date : NO_EXPIRY;
          if (!isDate(exp)) throw new HttpError2(400, `Row ${n} (${item.name}): expiry must be YYYY-MM-DD`);
          if (ln.mfg_date && !isDate(ln.mfg_date)) throw new HttpError2(400, `Row ${n} (${item.name}): mfg date must be YYYY-MM-DD`);
          return {
            line_index: i,
            sno: n,
            item_id: item.id,
            item_name: item.name,
            hsn: ln.hsn || item.hsn || null,
            gst_rate: item.gst_rate,
            qty: q,
            unit,
            pcs_qty: pcs,
            rate,
            amount,
            batch_no: String(ln.batch_no || "").trim() || `AUTO-${date.replace(/-/g, "")}`,
            mfg_date: ln.mfg_date || null,
            exp_date: exp,
            mrp: ln.mrp ? Number(ln.mrp) : null
          };
        });
        const subtotal = r2(rows.reduce((a, r) => a + r.amount, 0));
        const discount = r2(num(input.discount, "Discount"));
        if (discount > subtotal + 5e-3) throw new HttpError2(400, "Discount cannot be more than the items total");
        const taxable = r2(subtotal - discount);
        const share = subtotal > 0 ? taxable / subtotal : 0;
        let sugTax = 0;
        for (const r of rows) sugTax += r.amount * share * r.gst_rate / 100;
        sugTax = r2(sugTax);
        const suggested = intra ? { cgst: r2(sugTax / 2), sgst: r2(sugTax - r2(sugTax / 2)), igst: 0 } : { cgst: 0, sgst: 0, igst: sugTax };
        const taxGiven = !(blankNum(input.cgst) && blankNum(input.sgst) && blankNum(input.igst));
        let cgst, sgst, igst;
        if (input.auto_tax || !taxGiven) ({ cgst, sgst, igst } = suggested);
        else {
          cgst = r2(num(input.cgst, "CGST"));
          sgst = r2(num(input.sgst, "SGST"));
          igst = r2(num(input.igst, "IGST"));
        }
        const grand = r2(taxable + cgst + sgst + igst);
        let round_off;
        if (blankNum(input.round_off)) round_off = r2(Math.round(grand) - grand);
        else {
          round_off = r2(num(input.round_off, "Round off", { min: -Infinity }));
          if (Math.abs(round_off) > 5) throw new HttpError2(400, "Round off looks too large (more than 5 rupees). Check the figure.");
        }
        const total = r2(grand + round_off);
        const printed = blankNum(input.printed_total) ? null : Number(input.printed_total);
        const mismatch = printed !== null && Number.isFinite(printed) && Math.abs(printed - total) > 1 ? r2(total - printed) : 0;
        return {
          party,
          date,
          intra,
          rows,
          subtotal,
          discount,
          taxable,
          cgst,
          sgst,
          igst,
          round_off,
          total,
          suggested_tax: suggested,
          printed_total: printed,
          mismatch,
          share
          // used to allocate discount to item cost
        };
      }
      var previewPurchase = (input) => {
        const p = buildPurchase(input);
        const { party, rows, share, ...rest } = p;
        return { ...rest, supply: p.intra ? "INTRA" : "INTER", lines: rows };
      };
      function writePurchase(input, existing) {
        const p = buildPurchase(input);
        const supplierNo = String(input.supplier_invoice_no || "").trim();
        if (supplierNo && !input.allow_duplicate) {
          const dup = db2.prepare("SELECT purchase_no FROM purchases WHERE party_id=? AND lower(supplier_invoice_no)=lower(?) AND id <> ?").get(p.party.id, supplierNo, existing ? existing.id : 0);
          if (dup) throw new HttpError2(409, `Bill ${supplierNo} from ${p.party.name} is already entered as ${dup.purchase_no}`, "DUPLICATE");
        }
        const paid = r2(Math.min(Math.max(num(input.paid_amount, "Paid amount"), 0), Math.max(p.total, 0)));
        const mode = String(input.pay_mode || "CASH").toUpperCase();
        const vals = [
          supplierNo || null,
          p.date,
          p.party.id,
          p.subtotal,
          p.discount,
          p.taxable,
          p.cgst,
          p.sgst,
          p.igst,
          p.round_off,
          p.total,
          paid,
          paid > 0 ? mode : null,
          input.notes || null,
          input.source === "PDF" ? "PDF" : "MANUAL"
        ];
        let id, purchase_no;
        if (existing) {
          id = existing.id;
          purchase_no = existing.purchase_no;
          db2.prepare(`UPDATE purchases SET supplier_invoice_no=?,date=?,party_id=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,paid=?,pay_mode=?,notes=?,source=? WHERE id=?`).run(...vals, id);
        } else {
          purchase_no = nextNo("PUR", p.date);
          id = Number(db2.prepare(
            `INSERT INTO purchases(supplier_invoice_no,date,party_id,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,pay_mode,notes,source,purchase_no)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
          ).run(...vals, purchase_no).lastInsertRowid);
        }
        const upsert = db2.prepare(
          `INSERT INTO batches(item_id,batch_no,mfg_date,exp_date,qty,purchase_price,mrp) VALUES(?,?,?,?,?,?,?)
     ON CONFLICT(item_id,batch_no) DO UPDATE SET qty = qty + excluded.qty, exp_date = excluded.exp_date,
       mfg_date = COALESCE(excluded.mfg_date, mfg_date), purchase_price = excluded.purchase_price, mrp = COALESCE(excluded.mrp, mrp)`
        );
        const insLine = db2.prepare(
          `INSERT INTO purchase_lines(purchase_id,item_id,batch_id,batch_no,mfg_date,exp_date,qty,free_qty,rate,disc_pct,disc_amt,mrp,taxable,gst_rate,cgst,sgst,igst,amount,unit,pcs_qty)
     VALUES(?,?,?,?,?,?,?,0,?,0,0,?,?,?,0,0,0,?,?,?)`
        );
        const touched = /* @__PURE__ */ new Set();
        for (const r of p.rows) {
          const lineTaxable = r2(r.amount * p.share);
          const unitCost = r2(lineTaxable / r.pcs_qty);
          upsert.run(r.item_id, r.batch_no, r.mfg_date, r.exp_date, r.pcs_qty, unitCost, r.mrp);
          const batch = db2.prepare("SELECT id FROM batches WHERE item_id=? AND batch_no=?").get(r.item_id, r.batch_no);
          touched.add(batch.id);
          insLine.run(id, r.item_id, batch.id, r.batch_no, r.mfg_date, r.exp_date, r.qty, r.rate, r.mrp, lineTaxable, r.gst_rate, r.amount, r.unit, r.pcs_qty);
          if (input.update_cost !== false && unitCost > 0) db2.prepare("UPDATE items SET purchase_price=? WHERE id=?").run(unitCost, r.item_id);
        }
        return { id, purchase_no, p, paid, mode, supplierNo, touched };
      }
      function postLedger({ id, purchase_no, p, paid, mode, supplierNo }) {
        const lg = db2.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)");
        lg.run(p.party.id, p.date, "PURCHASE", purchase_no, 0, p.total, `Purchase ${purchase_no}${supplierNo ? " / " + supplierNo : ""}`);
        if (paid > 0) {
          const v = nextNo("PAY", p.date);
          db2.prepare("INSERT INTO payments(voucher_no,date,party_id,purchase_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?)").run(v, p.date, p.party.id, id, mode, paid, `Paid at purchase ${purchase_no}`);
          lg.run(p.party.id, p.date, "PAYMENT", v, paid, 0, `Paid at purchase (${mode})`);
        }
      }
      var createPurchase = db2.transaction((input) => {
        const w = writePurchase(input, null);
        postLedger(w);
        return w.id;
      });
      var updatePurchase = db2.transaction((id, input) => {
        const old = db2.prepare("SELECT * FROM purchases WHERE id=?").get(id);
        if (!old) throw new HttpError2(404, "Purchase bill not found");
        const oldTouched = /* @__PURE__ */ new Set();
        for (const l of db2.prepare("SELECT batch_id, qty, free_qty, pcs_qty FROM purchase_lines WHERE purchase_id=?").all(id)) {
          db2.prepare("UPDATE batches SET qty = qty - ? WHERE id = ?").run(l.pcs_qty != null ? l.pcs_qty : l.qty + l.free_qty, l.batch_id);
          oldTouched.add(l.batch_id);
        }
        db2.prepare("DELETE FROM purchase_lines WHERE purchase_id=?").run(id);
        for (const pay of db2.prepare("SELECT voucher_no FROM payments WHERE purchase_id=?").all(id))
          db2.prepare("DELETE FROM ledger WHERE type='PAYMENT' AND ref_no=?").run(pay.voucher_no);
        db2.prepare("DELETE FROM payments WHERE purchase_id=?").run(id);
        db2.prepare("DELETE FROM ledger WHERE type='PURCHASE' AND ref_no=?").run(old.purchase_no);
        const w = writePurchase(input, { id, purchase_no: old.purchase_no });
        postLedger(w);
        for (const b of /* @__PURE__ */ new Set([...oldTouched, ...w.touched])) {
          const row = db2.prepare("SELECT b.qty, i.name FROM batches b JOIN items i ON i.id=b.item_id WHERE b.id=?").get(b);
          if (row && row.qty < 0)
            throw new HttpError2(409, `${row.name}: ${-row.qty} piece(s) from this bill were already sold, so the quantity cannot be reduced that far.`, "ALREADY_SOLD");
        }
        return id;
      });
      var deletePurchase = db2.transaction((id) => {
        const old = db2.prepare("SELECT * FROM purchases WHERE id=?").get(id);
        if (!old) throw new HttpError2(404, "Purchase bill not found");
        const touched = /* @__PURE__ */ new Set();
        for (const l of db2.prepare("SELECT batch_id, qty, free_qty, pcs_qty FROM purchase_lines WHERE purchase_id=?").all(id)) {
          db2.prepare("UPDATE batches SET qty = qty - ? WHERE id = ?").run(l.pcs_qty != null ? l.pcs_qty : l.qty + l.free_qty, l.batch_id);
          touched.add(l.batch_id);
        }
        db2.prepare("DELETE FROM purchase_lines WHERE purchase_id=?").run(id);
        for (const pay of db2.prepare("SELECT voucher_no FROM payments WHERE purchase_id=?").all(id))
          db2.prepare("DELETE FROM ledger WHERE type='PAYMENT' AND ref_no=?").run(pay.voucher_no);
        db2.prepare("DELETE FROM payments WHERE purchase_id=?").run(id);
        db2.prepare("DELETE FROM ledger WHERE type='PURCHASE' AND ref_no=?").run(old.purchase_no);
        db2.prepare("DELETE FROM purchases WHERE id=?").run(id);
        for (const b of touched) {
          const row = db2.prepare("SELECT b.qty, i.name FROM batches b JOIN items i ON i.id=b.item_id WHERE b.id=?").get(b);
          if (row && row.qty < 0)
            throw new HttpError2(409, `${row.name}: ${-row.qty} piece(s) from this bill were already sold, so it cannot be deleted.`, "ALREADY_SOLD");
        }
        return { id, purchase_no: old.purchase_no, total: old.total };
      });
      function getPurchase(id) {
        const p = db2.prepare(
          `SELECT pu.*, pa.name party_name, pa.gstin party_gstin, pa.state_code party_state FROM purchases pu JOIN parties pa ON pa.id=pu.party_id WHERE pu.id=?`
        ).get(id);
        if (!p) return null;
        p.lines = db2.prepare(
          `SELECT l.*, it.name item_name, COALESCE(it.hsn,'') hsn FROM purchase_lines l JOIN items it ON it.id=l.item_id WHERE l.purchase_id=? ORDER BY l.id`
        ).all(id);
        p.lines.forEach((l, i) => {
          l.sno = i + 1;
          if (l.exp_date >= "2099-01-01") l.exp_date = null;
          if (!l.unit) l.unit = "PCS";
        });
        return p;
      }
      module.exports = { buildPurchase, previewPurchase, createPurchase, updatePurchase, deletePurchase, getPurchase, NO_EXPIRY };
    }
  });

  // ../../backend/src/routes/purchases.js
  var require_purchases2 = __commonJS({
    "../../backend/src/routes/purchases.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var db2 = require_db();
      var { h, HttpError: HttpError2 } = require_misc();
      var { previewPurchase, createPurchase, updatePurchase, deletePurchase, getPurchase } = require_purchases();
      var { extractText } = require_pdfExtract();
      var { parseInvoicePages: parseInvoicePages2 } = require_pdfParser();
      var { settings: settings2 } = require_billing();
      var { createMissing: createMissing2 } = require_autoCreate();
      router.post("/purchases/preview", h((req, res) => res.json(previewPurchase(req.body))));
      router.post("/purchases", h((req, res) => {
        const id = createPurchase(req.body);
        const p = getPurchase(id);
        res.status(201).json({ id, purchase_no: p.purchase_no, total: p.total });
      }));
      router.put("/purchases/:id", h((req, res) => {
        const id = updatePurchase(Number(req.params.id), req.body || {});
        const p = getPurchase(id);
        res.json({ id, purchase_no: p.purchase_no, total: p.total });
      }));
      router.delete("/purchases/:id", h((req, res) => res.json(deletePurchase(Number(req.params.id)))));
      router.get("/purchases/:id", h((req, res) => {
        const p = getPurchase(req.params.id);
        if (!p) throw new HttpError2(404, "Purchase bill not found");
        res.json(p);
      }));
      router.post("/purchases/parse-pdf", async (req, res, next) => {
        try {
          const b64 = req.body && req.body.pdf_base64;
          if (!b64) throw new HttpError2(400, "No PDF received");
          const buf = Buffer2.from(b64, "base64");
          if (buf.length < 100 || buf.slice(0, 4).toString() !== "%PDF") throw new HttpError2(422, "That file is not a PDF");
          const { pages, text, method } = await extractText(buf);
          const co = settings2();
          const result = parseInvoicePages2(pages, {
            items: db2.prepare("SELECT id,name,hsn,gst_rate FROM items WHERE active=1").all(),
            parties: db2.prepare(`SELECT id,name,gstin FROM parties WHERE active=1 AND type='SUPPLIER'`).all(),
            companyGstin: co.company_gstin,
            companyName: co.company_name
          });
          if (req.body.create_missing) await createMissing2(result, { online: req.body.online !== false });
          res.json({ ...result, method, raw_text: text.replace(/\f/g, "\n---- page ----\n").slice(0, 8e3) });
        } catch (e) {
          next(e);
        }
      });
      module.exports = router;
    }
  });

  // ../../backend/src/services/debitNotes.js
  var require_debitNotes = __commonJS({
    "../../backend/src/services/debitNotes.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { r2 } = require_gst();
      var { today, nextNo, HttpError: HttpError2 } = require_misc();
      var { settings: settings2 } = require_billing();
      var { rupeesInWords } = require_words();
      var { fyRange } = require_fy();
      var isDate = (v) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
      var BOX_UNIT = /^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$/i;
      var blankNum = (v) => v === void 0 || v === null || String(v).trim() === "";
      var num = (v, label, { min = 0 } = {}) => {
        if (blankNum(v)) return 0;
        const n = Number(String(v).replace(/,/g, ""));
        if (!Number.isFinite(n) || n < min) throw new HttpError2(400, `${label} must be a number${min === 0 ? " (0 or more)" : ""}`);
        return n;
      };
      var text = (v, max = 200) => {
        const s = String(v ?? "").trim().replace(/\s+/g, " ").slice(0, max);
        return s || null;
      };
      function buildDebitNote(input) {
        if (!input.party_id) throw new HttpError2(400, "Select the supplier");
        const party = db2.prepare("SELECT * FROM parties WHERE id=?").get(input.party_id);
        if (!party) throw new HttpError2(404, "Party not found");
        if (!Array.isArray(input.lines) || !input.lines.length) throw new HttpError2(400, "Add at least one item");
        const co = settings2();
        const intra = !party.state_code || party.state_code === co.state_code;
        const date = input.date || today();
        if (!isDate(date)) throw new HttpError2(400, "Date must be YYYY-MM-DD");
        const rows = input.lines.map((ln, i) => {
          const n = i + 1;
          const item = ln.item_id ? db2.prepare("SELECT * FROM items WHERE id=?").get(ln.item_id) : null;
          if (!item) throw new HttpError2(400, `Row ${n}: choose the stock item`);
          const q = num(ln.qty, `Row ${n} (${item.name}) quantity`);
          if (!(q > 0) || !Number.isInteger(q)) throw new HttpError2(400, `Row ${n} (${item.name}): quantity must be a whole number of at least 1`);
          const unit = BOX_UNIT.test(String(ln.unit || "").trim()) ? "BOX" : "PCS";
          const ppb = Math.max(1, item.pcs_per_box || 1);
          const pcs = unit === "BOX" ? q * ppb : q;
          const rate = num(ln.rate, `Row ${n} (${item.name}) rate`);
          const amount = blankNum(ln.amount) ? r2(q * rate) : r2(num(ln.amount, `Row ${n} (${item.name}) amount`));
          const gst = blankNum(ln.gst_rate) ? item.gst_rate : num(ln.gst_rate, `Row ${n} (${item.name}) GST rate`);
          if (gst > 40) throw new HttpError2(400, `Row ${n} (${item.name}): GST rate must be between 0 and 40`);
          const batchId = ln.batch_id ? Number(ln.batch_id) : null;
          return {
            sno: n,
            item_id: item.id,
            item_name: item.name,
            hsn: item.hsn || null,
            pcs_per_box: ppb,
            mrp: item.mrp,
            qty: q,
            unit,
            pcs_qty: pcs,
            rate,
            amount,
            gst_rate: gst,
            batch_id: batchId
          };
        });
        const subtotal = r2(rows.reduce((a, r) => a + r.amount, 0));
        const discount = r2(num(input.discount, "Discount"));
        if (discount > subtotal + 5e-3) throw new HttpError2(400, "Discount cannot be more than the items total");
        const taxable = r2(subtotal - discount);
        const share = subtotal > 0 ? taxable / subtotal : 0;
        for (const r of rows) {
          r.taxable = r2(r.amount * share);
          const tax = r2(r.taxable * r.gst_rate / 100);
          if (intra) {
            r.cgst = r2(tax / 2);
            r.sgst = r2(tax - r.cgst);
            r.igst = 0;
          } else {
            r.cgst = 0;
            r.sgst = 0;
            r.igst = tax;
          }
        }
        const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
        const cgst = sum("cgst"), sgst = sum("sgst"), igst = sum("igst");
        const grand = r2(taxable + cgst + sgst + igst);
        const round_off = r2(Math.round(grand) - grand);
        const total = r2(grand + round_off);
        return { party, date, intra, rows, subtotal, discount, taxable, cgst, sgst, igst, round_off, total };
      }
      var previewDebitNote = (input) => {
        const p = buildDebitNote(input);
        const { party, rows, ...rest } = p;
        return { ...rest, supply: p.intra ? "INTRA" : "INTER", lines: rows };
      };
      function allocate(r) {
        if (r.batch_id) {
          const b = db2.prepare("SELECT id, batch_no, qty FROM batches WHERE id=? AND item_id=?").get(r.batch_id, r.item_id);
          if (!b) throw new HttpError2(400, `Row ${r.sno} (${r.item_name}): that batch is not one of this item's batches`);
          if (b.qty < r.pcs_qty) throw new HttpError2(409, `Row ${r.sno} (${r.item_name}): batch ${b.batch_no} has only ${b.qty} piece(s) in stock`, "NO_STOCK");
          return [{ batch_id: b.id, qty: r.pcs_qty }];
        }
        const out = [];
        let left = r.pcs_qty;
        for (const b of db2.prepare("SELECT id, qty FROM batches WHERE item_id=? AND qty>0 ORDER BY exp_date, id").all(r.item_id)) {
          if (left <= 0) break;
          const take = Math.min(b.qty, left);
          out.push({ batch_id: b.id, qty: take });
          left -= take;
        }
        if (left > 0) throw new HttpError2(409, `${r.item_name}: only ${r.pcs_qty - left} piece(s) in stock, ${r.pcs_qty} to return`, "NO_STOCK");
        return out;
      }
      function writeDebitNote(input, existing) {
        const p = buildDebitNote(input);
        let purchase = null;
        if (input.purchase_id) {
          purchase = db2.prepare("SELECT id, purchase_no, supplier_invoice_no FROM purchases WHERE id=?").get(input.purchase_id);
          if (!purchase) throw new HttpError2(404, "Purchase bill not found");
        }
        const against = text(input.against_bill, 60) || (purchase ? purchase.supplier_invoice_no || purchase.purchase_no : null);
        const vals = [
          p.date,
          p.party.id,
          purchase ? purchase.id : null,
          against,
          text(input.reason),
          p.subtotal,
          p.discount,
          p.taxable,
          p.cgst,
          p.sgst,
          p.igst,
          p.round_off,
          p.total,
          text(input.notes, 500)
        ];
        let id, note_no;
        if (existing) {
          id = existing.id;
          note_no = existing.note_no;
          db2.prepare(`UPDATE debit_notes SET date=?,party_id=?,purchase_id=?,against_bill=?,reason=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,notes=? WHERE id=?`).run(...vals, id);
        } else {
          note_no = nextNo("DN", p.date);
          id = Number(db2.prepare(
            `INSERT INTO debit_notes(date,party_id,purchase_id,against_bill,reason,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,notes,note_no)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
          ).run(...vals, note_no).lastInsertRowid);
        }
        const insLine = db2.prepare(
          `INSERT INTO debit_note_lines(note_id,item_id,batch_id,qty,unit,pcs_qty,rate,amount,taxable,gst_rate,cgst,sgst,igst) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)`
        );
        const insStock = db2.prepare("INSERT INTO debit_note_stock(line_id,batch_id,qty) VALUES(?,?,?)");
        for (const r of p.rows) {
          const parts = allocate(r);
          const lineId = Number(insLine.run(
            id,
            r.item_id,
            parts.length === 1 ? parts[0].batch_id : null,
            r.qty,
            r.unit,
            r.pcs_qty,
            r.rate,
            r.amount,
            r.taxable,
            r.gst_rate,
            r.cgst,
            r.sgst,
            r.igst
          ).lastInsertRowid);
          for (const s of parts) {
            db2.prepare("UPDATE batches SET qty = qty - ? WHERE id = ?").run(s.qty, s.batch_id);
            insStock.run(lineId, s.batch_id, s.qty);
          }
        }
        const why = [against ? `against ${against}` : "", text(input.reason) ? `(${text(input.reason)})` : ""].filter(Boolean).join(" ");
        db2.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)").run(p.party.id, p.date, "DEBIT_NOTE", note_no, p.total, 0, `Debit note ${note_no}${why ? " " + why : ""}`);
        return id;
      }
      function reverse(old) {
        for (const s of db2.prepare("SELECT s.batch_id, s.qty FROM debit_note_stock s JOIN debit_note_lines l ON l.id=s.line_id WHERE l.note_id=?").all(old.id))
          db2.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?").run(s.qty, s.batch_id);
        db2.prepare("DELETE FROM debit_note_stock WHERE line_id IN (SELECT id FROM debit_note_lines WHERE note_id=?)").run(old.id);
        db2.prepare("DELETE FROM debit_note_lines WHERE note_id=?").run(old.id);
        db2.prepare("DELETE FROM ledger WHERE type='DEBIT_NOTE' AND ref_no=?").run(old.note_no);
      }
      var createDebitNote = db2.transaction((input) => writeDebitNote(input, null));
      var updateDebitNote = db2.transaction((id, input) => {
        const old = db2.prepare("SELECT * FROM debit_notes WHERE id=?").get(id);
        if (!old) throw new HttpError2(404, "Debit note not found");
        reverse(old);
        return writeDebitNote(input, { id, note_no: old.note_no });
      });
      var deleteDebitNote = db2.transaction((id) => {
        const old = db2.prepare("SELECT * FROM debit_notes WHERE id=?").get(id);
        if (!old) throw new HttpError2(404, "Debit note not found");
        reverse(old);
        db2.prepare("DELETE FROM debit_notes WHERE id=?").run(id);
        return { id, note_no: old.note_no, total: old.total };
      });
      function getDebitNote(id) {
        const d = db2.prepare(
          `SELECT d.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state, p.phone party_phone, p.mobiles party_mobiles,
            p.tel party_tel, p.email party_email, p.pan party_pan, p.fssai party_fssai, u.purchase_no
     FROM debit_notes d JOIN parties p ON p.id=d.party_id LEFT JOIN purchases u ON u.id=d.purchase_id WHERE d.id=?`
        ).get(id);
        if (!d) return null;
        d.lines = db2.prepare(
          `SELECT l.*, it.name item_name, COALESCE(it.hsn,'') hsn, it.pcs_per_box, it.mrp,
            (SELECT GROUP_CONCAT(b.batch_no, ', ') FROM debit_note_stock s JOIN batches b ON b.id=s.batch_id WHERE s.line_id=l.id) batch_no
     FROM debit_note_lines l JOIN items it ON it.id=l.item_id WHERE l.note_id=? ORDER BY l.id`
        ).all(id);
        d.lines.forEach((l, i) => {
          l.sno = i + 1;
          if (!l.batch_no) l.batch_no = "";
        });
        d.supply = d.igst > 0 ? "INTER" : "INTRA";
        d.amount_words = rupeesInWords(d.total);
        const g = {};
        for (const l of d.lines) {
          const x = g[l.gst_rate] ||= { rate: l.gst_rate, rows: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0 };
          x.rows += 1;
          x.taxable = r2(x.taxable + l.taxable);
          x.cgst = r2(x.cgst + l.cgst);
          x.sgst = r2(x.sgst + l.sgst);
          x.igst = r2(x.igst + l.igst);
        }
        d.gst_summary = Object.values(g).sort((a, b) => a.rate - b.rate);
        d.invoice_no = d.note_no;
        d.doc_title = "DEBIT NOTE";
        d.doc_no_label = "Debit note no";
        d.doc_line = [d.against_bill ? `Against bill ${d.against_bill}` : "", d.reason || ""].filter(Boolean).join("  \xB7  ");
        d.print_lines = d.lines.map((l) => ({
          item_name: l.item_name,
          hsn: l.hsn,
          qty: l.pcs_qty,
          free_qty: 0,
          pcs_per_box: l.pcs_per_box,
          mrp: l.mrp,
          rate: l.pcs_qty > 0 ? r2(l.amount / l.pcs_qty) : 0,
          disc_pct: 0,
          taxable: l.taxable,
          gst_rate: l.gst_rate,
          amount: r2(l.taxable + l.cgst + l.sgst + l.igst)
        }));
        return d;
      }
      function listDebitNotes({ fy: fyLabel, from, to, q, party_id } = {}) {
        const fy = fyRange(fyLabel);
        const f = from && from > fy.from ? from : fy.from, t = to && to < fy.to ? to : fy.to;
        const rows = db2.prepare(
          `SELECT d.id, d.note_no, d.date, COALESCE(d.against_bill,'') against_bill, COALESCE(d.reason,'') reason, d.party_id, p.name party, COALESCE(p.gstin,'') gstin,
            d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total
     FROM debit_notes d JOIN parties p ON p.id=d.party_id
     WHERE d.date BETWEEN @f AND @t AND (@pid IS NULL OR d.party_id=@pid)
       AND (d.note_no LIKE @q OR p.name LIKE @q OR COALESCE(d.against_bill,'') LIKE @q)
     ORDER BY d.date DESC, d.id DESC`
        ).all({ f, t, q: `%${String(q || "").trim()}%`, pid: party_id ? Number(party_id) : null });
        const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
        return { from: f, to: t, rows, totals: { count: rows.length, taxable: sum("taxable"), cgst: sum("cgst"), sgst: sum("sgst"), igst: sum("igst"), total: sum("total") } };
      }
      module.exports = { buildDebitNote, previewDebitNote, createDebitNote, updateDebitNote, deleteDebitNote, getDebitNote, listDebitNotes };
    }
  });

  // ../../backend/src/routes/debitNotes.js
  var require_debitNotes2 = __commonJS({
    "../../backend/src/routes/debitNotes.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var { h, HttpError: HttpError2 } = require_misc();
      var D = require_debitNotes();
      router.get("/debit-notes", h((req, res) => res.json(D.listDebitNotes({ fy: req.query.fy, from: req.query.from, to: req.query.to, q: req.query.q, party_id: req.query.party_id }))));
      router.post("/debit-notes/preview", h((req, res) => res.json(D.previewDebitNote(req.body || {}))));
      router.post("/debit-notes", h((req, res) => {
        const id = D.createDebitNote(req.body || {});
        const d = D.getDebitNote(id);
        res.status(201).json({ id, note_no: d.note_no, total: d.total });
      }));
      router.put("/debit-notes/:id", h((req, res) => {
        const id = D.updateDebitNote(Number(req.params.id), req.body || {});
        const d = D.getDebitNote(id);
        res.json({ id, note_no: d.note_no, total: d.total });
      }));
      router.delete("/debit-notes/:id", h((req, res) => res.json(D.deleteDebitNote(Number(req.params.id)))));
      router.get("/debit-notes/:id", h((req, res) => {
        const d = D.getDebitNote(req.params.id);
        if (!d) throw new HttpError2(404, "Debit note not found");
        res.json(d);
      }));
      module.exports = router;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/utils/common.js
  var require_common = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/utils/common.js"(exports) {
      "use strict";
      init_globals();
      var TYPED_OK = typeof Uint8Array !== "undefined" && typeof Uint16Array !== "undefined" && typeof Int32Array !== "undefined";
      function _has(obj, key) {
        return Object.prototype.hasOwnProperty.call(obj, key);
      }
      exports.assign = function(obj) {
        var sources = Array.prototype.slice.call(arguments, 1);
        while (sources.length) {
          var source = sources.shift();
          if (!source) {
            continue;
          }
          if (typeof source !== "object") {
            throw new TypeError(source + "must be non-object");
          }
          for (var p in source) {
            if (_has(source, p)) {
              obj[p] = source[p];
            }
          }
        }
        return obj;
      };
      exports.shrinkBuf = function(buf, size) {
        if (buf.length === size) {
          return buf;
        }
        if (buf.subarray) {
          return buf.subarray(0, size);
        }
        buf.length = size;
        return buf;
      };
      var fnTyped = {
        arraySet: function(dest, src, src_offs, len, dest_offs) {
          if (src.subarray && dest.subarray) {
            dest.set(src.subarray(src_offs, src_offs + len), dest_offs);
            return;
          }
          for (var i = 0; i < len; i++) {
            dest[dest_offs + i] = src[src_offs + i];
          }
        },
        // Join array of chunks to single array.
        flattenChunks: function(chunks) {
          var i, l, len, pos, chunk, result;
          len = 0;
          for (i = 0, l = chunks.length; i < l; i++) {
            len += chunks[i].length;
          }
          result = new Uint8Array(len);
          pos = 0;
          for (i = 0, l = chunks.length; i < l; i++) {
            chunk = chunks[i];
            result.set(chunk, pos);
            pos += chunk.length;
          }
          return result;
        }
      };
      var fnUntyped = {
        arraySet: function(dest, src, src_offs, len, dest_offs) {
          for (var i = 0; i < len; i++) {
            dest[dest_offs + i] = src[src_offs + i];
          }
        },
        // Join array of chunks to single array.
        flattenChunks: function(chunks) {
          return [].concat.apply([], chunks);
        }
      };
      exports.setTyped = function(on) {
        if (on) {
          exports.Buf8 = Uint8Array;
          exports.Buf16 = Uint16Array;
          exports.Buf32 = Int32Array;
          exports.assign(exports, fnTyped);
        } else {
          exports.Buf8 = Array;
          exports.Buf16 = Array;
          exports.Buf32 = Array;
          exports.assign(exports, fnUntyped);
        }
      };
      exports.setTyped(TYPED_OK);
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/trees.js
  var require_trees = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/trees.js"(exports) {
      "use strict";
      init_globals();
      var utils = require_common();
      var Z_FIXED = 4;
      var Z_BINARY = 0;
      var Z_TEXT = 1;
      var Z_UNKNOWN = 2;
      function zero(buf) {
        var len = buf.length;
        while (--len >= 0) {
          buf[len] = 0;
        }
      }
      var STORED_BLOCK = 0;
      var STATIC_TREES = 1;
      var DYN_TREES = 2;
      var MIN_MATCH = 3;
      var MAX_MATCH = 258;
      var LENGTH_CODES = 29;
      var LITERALS = 256;
      var L_CODES = LITERALS + 1 + LENGTH_CODES;
      var D_CODES = 30;
      var BL_CODES = 19;
      var HEAP_SIZE = 2 * L_CODES + 1;
      var MAX_BITS = 15;
      var Buf_size = 16;
      var MAX_BL_BITS = 7;
      var END_BLOCK = 256;
      var REP_3_6 = 16;
      var REPZ_3_10 = 17;
      var REPZ_11_138 = 18;
      var extra_lbits = (
        /* extra bits for each length code */
        [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
      );
      var extra_dbits = (
        /* extra bits for each distance code */
        [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
      );
      var extra_blbits = (
        /* extra bits for each bit length code */
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 7]
      );
      var bl_order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
      var DIST_CODE_LEN = 512;
      var static_ltree = new Array((L_CODES + 2) * 2);
      zero(static_ltree);
      var static_dtree = new Array(D_CODES * 2);
      zero(static_dtree);
      var _dist_code = new Array(DIST_CODE_LEN);
      zero(_dist_code);
      var _length_code = new Array(MAX_MATCH - MIN_MATCH + 1);
      zero(_length_code);
      var base_length = new Array(LENGTH_CODES);
      zero(base_length);
      var base_dist = new Array(D_CODES);
      zero(base_dist);
      function StaticTreeDesc(static_tree, extra_bits, extra_base, elems, max_length) {
        this.static_tree = static_tree;
        this.extra_bits = extra_bits;
        this.extra_base = extra_base;
        this.elems = elems;
        this.max_length = max_length;
        this.has_stree = static_tree && static_tree.length;
      }
      var static_l_desc;
      var static_d_desc;
      var static_bl_desc;
      function TreeDesc(dyn_tree, stat_desc) {
        this.dyn_tree = dyn_tree;
        this.max_code = 0;
        this.stat_desc = stat_desc;
      }
      function d_code(dist) {
        return dist < 256 ? _dist_code[dist] : _dist_code[256 + (dist >>> 7)];
      }
      function put_short(s, w) {
        s.pending_buf[s.pending++] = w & 255;
        s.pending_buf[s.pending++] = w >>> 8 & 255;
      }
      function send_bits(s, value, length) {
        if (s.bi_valid > Buf_size - length) {
          s.bi_buf |= value << s.bi_valid & 65535;
          put_short(s, s.bi_buf);
          s.bi_buf = value >> Buf_size - s.bi_valid;
          s.bi_valid += length - Buf_size;
        } else {
          s.bi_buf |= value << s.bi_valid & 65535;
          s.bi_valid += length;
        }
      }
      function send_code(s, c, tree) {
        send_bits(
          s,
          tree[c * 2],
          tree[c * 2 + 1]
          /*.Len*/
        );
      }
      function bi_reverse(code, len) {
        var res = 0;
        do {
          res |= code & 1;
          code >>>= 1;
          res <<= 1;
        } while (--len > 0);
        return res >>> 1;
      }
      function bi_flush(s) {
        if (s.bi_valid === 16) {
          put_short(s, s.bi_buf);
          s.bi_buf = 0;
          s.bi_valid = 0;
        } else if (s.bi_valid >= 8) {
          s.pending_buf[s.pending++] = s.bi_buf & 255;
          s.bi_buf >>= 8;
          s.bi_valid -= 8;
        }
      }
      function gen_bitlen(s, desc) {
        var tree = desc.dyn_tree;
        var max_code = desc.max_code;
        var stree = desc.stat_desc.static_tree;
        var has_stree = desc.stat_desc.has_stree;
        var extra = desc.stat_desc.extra_bits;
        var base = desc.stat_desc.extra_base;
        var max_length = desc.stat_desc.max_length;
        var h;
        var n, m;
        var bits;
        var xbits;
        var f;
        var overflow = 0;
        for (bits = 0; bits <= MAX_BITS; bits++) {
          s.bl_count[bits] = 0;
        }
        tree[s.heap[s.heap_max] * 2 + 1] = 0;
        for (h = s.heap_max + 1; h < HEAP_SIZE; h++) {
          n = s.heap[h];
          bits = tree[tree[n * 2 + 1] * 2 + 1] + 1;
          if (bits > max_length) {
            bits = max_length;
            overflow++;
          }
          tree[n * 2 + 1] = bits;
          if (n > max_code) {
            continue;
          }
          s.bl_count[bits]++;
          xbits = 0;
          if (n >= base) {
            xbits = extra[n - base];
          }
          f = tree[n * 2];
          s.opt_len += f * (bits + xbits);
          if (has_stree) {
            s.static_len += f * (stree[n * 2 + 1] + xbits);
          }
        }
        if (overflow === 0) {
          return;
        }
        do {
          bits = max_length - 1;
          while (s.bl_count[bits] === 0) {
            bits--;
          }
          s.bl_count[bits]--;
          s.bl_count[bits + 1] += 2;
          s.bl_count[max_length]--;
          overflow -= 2;
        } while (overflow > 0);
        for (bits = max_length; bits !== 0; bits--) {
          n = s.bl_count[bits];
          while (n !== 0) {
            m = s.heap[--h];
            if (m > max_code) {
              continue;
            }
            if (tree[m * 2 + 1] !== bits) {
              s.opt_len += (bits - tree[m * 2 + 1]) * tree[m * 2];
              tree[m * 2 + 1] = bits;
            }
            n--;
          }
        }
      }
      function gen_codes(tree, max_code, bl_count) {
        var next_code = new Array(MAX_BITS + 1);
        var code = 0;
        var bits;
        var n;
        for (bits = 1; bits <= MAX_BITS; bits++) {
          next_code[bits] = code = code + bl_count[bits - 1] << 1;
        }
        for (n = 0; n <= max_code; n++) {
          var len = tree[n * 2 + 1];
          if (len === 0) {
            continue;
          }
          tree[n * 2] = bi_reverse(next_code[len]++, len);
        }
      }
      function tr_static_init() {
        var n;
        var bits;
        var length;
        var code;
        var dist;
        var bl_count = new Array(MAX_BITS + 1);
        length = 0;
        for (code = 0; code < LENGTH_CODES - 1; code++) {
          base_length[code] = length;
          for (n = 0; n < 1 << extra_lbits[code]; n++) {
            _length_code[length++] = code;
          }
        }
        _length_code[length - 1] = code;
        dist = 0;
        for (code = 0; code < 16; code++) {
          base_dist[code] = dist;
          for (n = 0; n < 1 << extra_dbits[code]; n++) {
            _dist_code[dist++] = code;
          }
        }
        dist >>= 7;
        for (; code < D_CODES; code++) {
          base_dist[code] = dist << 7;
          for (n = 0; n < 1 << extra_dbits[code] - 7; n++) {
            _dist_code[256 + dist++] = code;
          }
        }
        for (bits = 0; bits <= MAX_BITS; bits++) {
          bl_count[bits] = 0;
        }
        n = 0;
        while (n <= 143) {
          static_ltree[n * 2 + 1] = 8;
          n++;
          bl_count[8]++;
        }
        while (n <= 255) {
          static_ltree[n * 2 + 1] = 9;
          n++;
          bl_count[9]++;
        }
        while (n <= 279) {
          static_ltree[n * 2 + 1] = 7;
          n++;
          bl_count[7]++;
        }
        while (n <= 287) {
          static_ltree[n * 2 + 1] = 8;
          n++;
          bl_count[8]++;
        }
        gen_codes(static_ltree, L_CODES + 1, bl_count);
        for (n = 0; n < D_CODES; n++) {
          static_dtree[n * 2 + 1] = 5;
          static_dtree[n * 2] = bi_reverse(n, 5);
        }
        static_l_desc = new StaticTreeDesc(static_ltree, extra_lbits, LITERALS + 1, L_CODES, MAX_BITS);
        static_d_desc = new StaticTreeDesc(static_dtree, extra_dbits, 0, D_CODES, MAX_BITS);
        static_bl_desc = new StaticTreeDesc(new Array(0), extra_blbits, 0, BL_CODES, MAX_BL_BITS);
      }
      function init_block(s) {
        var n;
        for (n = 0; n < L_CODES; n++) {
          s.dyn_ltree[n * 2] = 0;
        }
        for (n = 0; n < D_CODES; n++) {
          s.dyn_dtree[n * 2] = 0;
        }
        for (n = 0; n < BL_CODES; n++) {
          s.bl_tree[n * 2] = 0;
        }
        s.dyn_ltree[END_BLOCK * 2] = 1;
        s.opt_len = s.static_len = 0;
        s.last_lit = s.matches = 0;
      }
      function bi_windup(s) {
        if (s.bi_valid > 8) {
          put_short(s, s.bi_buf);
        } else if (s.bi_valid > 0) {
          s.pending_buf[s.pending++] = s.bi_buf;
        }
        s.bi_buf = 0;
        s.bi_valid = 0;
      }
      function copy_block(s, buf, len, header) {
        bi_windup(s);
        if (header) {
          put_short(s, len);
          put_short(s, ~len);
        }
        utils.arraySet(s.pending_buf, s.window, buf, len, s.pending);
        s.pending += len;
      }
      function smaller(tree, n, m, depth) {
        var _n2 = n * 2;
        var _m2 = m * 2;
        return tree[_n2] < tree[_m2] || tree[_n2] === tree[_m2] && depth[n] <= depth[m];
      }
      function pqdownheap(s, tree, k) {
        var v = s.heap[k];
        var j = k << 1;
        while (j <= s.heap_len) {
          if (j < s.heap_len && smaller(tree, s.heap[j + 1], s.heap[j], s.depth)) {
            j++;
          }
          if (smaller(tree, v, s.heap[j], s.depth)) {
            break;
          }
          s.heap[k] = s.heap[j];
          k = j;
          j <<= 1;
        }
        s.heap[k] = v;
      }
      function compress_block(s, ltree, dtree) {
        var dist;
        var lc;
        var lx = 0;
        var code;
        var extra;
        if (s.last_lit !== 0) {
          do {
            dist = s.pending_buf[s.d_buf + lx * 2] << 8 | s.pending_buf[s.d_buf + lx * 2 + 1];
            lc = s.pending_buf[s.l_buf + lx];
            lx++;
            if (dist === 0) {
              send_code(s, lc, ltree);
            } else {
              code = _length_code[lc];
              send_code(s, code + LITERALS + 1, ltree);
              extra = extra_lbits[code];
              if (extra !== 0) {
                lc -= base_length[code];
                send_bits(s, lc, extra);
              }
              dist--;
              code = d_code(dist);
              send_code(s, code, dtree);
              extra = extra_dbits[code];
              if (extra !== 0) {
                dist -= base_dist[code];
                send_bits(s, dist, extra);
              }
            }
          } while (lx < s.last_lit);
        }
        send_code(s, END_BLOCK, ltree);
      }
      function build_tree(s, desc) {
        var tree = desc.dyn_tree;
        var stree = desc.stat_desc.static_tree;
        var has_stree = desc.stat_desc.has_stree;
        var elems = desc.stat_desc.elems;
        var n, m;
        var max_code = -1;
        var node;
        s.heap_len = 0;
        s.heap_max = HEAP_SIZE;
        for (n = 0; n < elems; n++) {
          if (tree[n * 2] !== 0) {
            s.heap[++s.heap_len] = max_code = n;
            s.depth[n] = 0;
          } else {
            tree[n * 2 + 1] = 0;
          }
        }
        while (s.heap_len < 2) {
          node = s.heap[++s.heap_len] = max_code < 2 ? ++max_code : 0;
          tree[node * 2] = 1;
          s.depth[node] = 0;
          s.opt_len--;
          if (has_stree) {
            s.static_len -= stree[node * 2 + 1];
          }
        }
        desc.max_code = max_code;
        for (n = s.heap_len >> 1; n >= 1; n--) {
          pqdownheap(s, tree, n);
        }
        node = elems;
        do {
          n = s.heap[
            1
            /*SMALLEST*/
          ];
          s.heap[
            1
            /*SMALLEST*/
          ] = s.heap[s.heap_len--];
          pqdownheap(
            s,
            tree,
            1
            /*SMALLEST*/
          );
          m = s.heap[
            1
            /*SMALLEST*/
          ];
          s.heap[--s.heap_max] = n;
          s.heap[--s.heap_max] = m;
          tree[node * 2] = tree[n * 2] + tree[m * 2];
          s.depth[node] = (s.depth[n] >= s.depth[m] ? s.depth[n] : s.depth[m]) + 1;
          tree[n * 2 + 1] = tree[m * 2 + 1] = node;
          s.heap[
            1
            /*SMALLEST*/
          ] = node++;
          pqdownheap(
            s,
            tree,
            1
            /*SMALLEST*/
          );
        } while (s.heap_len >= 2);
        s.heap[--s.heap_max] = s.heap[
          1
          /*SMALLEST*/
        ];
        gen_bitlen(s, desc);
        gen_codes(tree, max_code, s.bl_count);
      }
      function scan_tree(s, tree, max_code) {
        var n;
        var prevlen = -1;
        var curlen;
        var nextlen = tree[0 * 2 + 1];
        var count = 0;
        var max_count = 7;
        var min_count = 4;
        if (nextlen === 0) {
          max_count = 138;
          min_count = 3;
        }
        tree[(max_code + 1) * 2 + 1] = 65535;
        for (n = 0; n <= max_code; n++) {
          curlen = nextlen;
          nextlen = tree[(n + 1) * 2 + 1];
          if (++count < max_count && curlen === nextlen) {
            continue;
          } else if (count < min_count) {
            s.bl_tree[curlen * 2] += count;
          } else if (curlen !== 0) {
            if (curlen !== prevlen) {
              s.bl_tree[curlen * 2]++;
            }
            s.bl_tree[REP_3_6 * 2]++;
          } else if (count <= 10) {
            s.bl_tree[REPZ_3_10 * 2]++;
          } else {
            s.bl_tree[REPZ_11_138 * 2]++;
          }
          count = 0;
          prevlen = curlen;
          if (nextlen === 0) {
            max_count = 138;
            min_count = 3;
          } else if (curlen === nextlen) {
            max_count = 6;
            min_count = 3;
          } else {
            max_count = 7;
            min_count = 4;
          }
        }
      }
      function send_tree(s, tree, max_code) {
        var n;
        var prevlen = -1;
        var curlen;
        var nextlen = tree[0 * 2 + 1];
        var count = 0;
        var max_count = 7;
        var min_count = 4;
        if (nextlen === 0) {
          max_count = 138;
          min_count = 3;
        }
        for (n = 0; n <= max_code; n++) {
          curlen = nextlen;
          nextlen = tree[(n + 1) * 2 + 1];
          if (++count < max_count && curlen === nextlen) {
            continue;
          } else if (count < min_count) {
            do {
              send_code(s, curlen, s.bl_tree);
            } while (--count !== 0);
          } else if (curlen !== 0) {
            if (curlen !== prevlen) {
              send_code(s, curlen, s.bl_tree);
              count--;
            }
            send_code(s, REP_3_6, s.bl_tree);
            send_bits(s, count - 3, 2);
          } else if (count <= 10) {
            send_code(s, REPZ_3_10, s.bl_tree);
            send_bits(s, count - 3, 3);
          } else {
            send_code(s, REPZ_11_138, s.bl_tree);
            send_bits(s, count - 11, 7);
          }
          count = 0;
          prevlen = curlen;
          if (nextlen === 0) {
            max_count = 138;
            min_count = 3;
          } else if (curlen === nextlen) {
            max_count = 6;
            min_count = 3;
          } else {
            max_count = 7;
            min_count = 4;
          }
        }
      }
      function build_bl_tree(s) {
        var max_blindex;
        scan_tree(s, s.dyn_ltree, s.l_desc.max_code);
        scan_tree(s, s.dyn_dtree, s.d_desc.max_code);
        build_tree(s, s.bl_desc);
        for (max_blindex = BL_CODES - 1; max_blindex >= 3; max_blindex--) {
          if (s.bl_tree[bl_order[max_blindex] * 2 + 1] !== 0) {
            break;
          }
        }
        s.opt_len += 3 * (max_blindex + 1) + 5 + 5 + 4;
        return max_blindex;
      }
      function send_all_trees(s, lcodes, dcodes, blcodes) {
        var rank;
        send_bits(s, lcodes - 257, 5);
        send_bits(s, dcodes - 1, 5);
        send_bits(s, blcodes - 4, 4);
        for (rank = 0; rank < blcodes; rank++) {
          send_bits(s, s.bl_tree[bl_order[rank] * 2 + 1], 3);
        }
        send_tree(s, s.dyn_ltree, lcodes - 1);
        send_tree(s, s.dyn_dtree, dcodes - 1);
      }
      function detect_data_type(s) {
        var black_mask = 4093624447;
        var n;
        for (n = 0; n <= 31; n++, black_mask >>>= 1) {
          if (black_mask & 1 && s.dyn_ltree[n * 2] !== 0) {
            return Z_BINARY;
          }
        }
        if (s.dyn_ltree[9 * 2] !== 0 || s.dyn_ltree[10 * 2] !== 0 || s.dyn_ltree[13 * 2] !== 0) {
          return Z_TEXT;
        }
        for (n = 32; n < LITERALS; n++) {
          if (s.dyn_ltree[n * 2] !== 0) {
            return Z_TEXT;
          }
        }
        return Z_BINARY;
      }
      var static_init_done = false;
      function _tr_init(s) {
        if (!static_init_done) {
          tr_static_init();
          static_init_done = true;
        }
        s.l_desc = new TreeDesc(s.dyn_ltree, static_l_desc);
        s.d_desc = new TreeDesc(s.dyn_dtree, static_d_desc);
        s.bl_desc = new TreeDesc(s.bl_tree, static_bl_desc);
        s.bi_buf = 0;
        s.bi_valid = 0;
        init_block(s);
      }
      function _tr_stored_block(s, buf, stored_len, last) {
        send_bits(s, (STORED_BLOCK << 1) + (last ? 1 : 0), 3);
        copy_block(s, buf, stored_len, true);
      }
      function _tr_align(s) {
        send_bits(s, STATIC_TREES << 1, 3);
        send_code(s, END_BLOCK, static_ltree);
        bi_flush(s);
      }
      function _tr_flush_block(s, buf, stored_len, last) {
        var opt_lenb, static_lenb;
        var max_blindex = 0;
        if (s.level > 0) {
          if (s.strm.data_type === Z_UNKNOWN) {
            s.strm.data_type = detect_data_type(s);
          }
          build_tree(s, s.l_desc);
          build_tree(s, s.d_desc);
          max_blindex = build_bl_tree(s);
          opt_lenb = s.opt_len + 3 + 7 >>> 3;
          static_lenb = s.static_len + 3 + 7 >>> 3;
          if (static_lenb <= opt_lenb) {
            opt_lenb = static_lenb;
          }
        } else {
          opt_lenb = static_lenb = stored_len + 5;
        }
        if (stored_len + 4 <= opt_lenb && buf !== -1) {
          _tr_stored_block(s, buf, stored_len, last);
        } else if (s.strategy === Z_FIXED || static_lenb === opt_lenb) {
          send_bits(s, (STATIC_TREES << 1) + (last ? 1 : 0), 3);
          compress_block(s, static_ltree, static_dtree);
        } else {
          send_bits(s, (DYN_TREES << 1) + (last ? 1 : 0), 3);
          send_all_trees(s, s.l_desc.max_code + 1, s.d_desc.max_code + 1, max_blindex + 1);
          compress_block(s, s.dyn_ltree, s.dyn_dtree);
        }
        init_block(s);
        if (last) {
          bi_windup(s);
        }
      }
      function _tr_tally(s, dist, lc) {
        s.pending_buf[s.d_buf + s.last_lit * 2] = dist >>> 8 & 255;
        s.pending_buf[s.d_buf + s.last_lit * 2 + 1] = dist & 255;
        s.pending_buf[s.l_buf + s.last_lit] = lc & 255;
        s.last_lit++;
        if (dist === 0) {
          s.dyn_ltree[lc * 2]++;
        } else {
          s.matches++;
          dist--;
          s.dyn_ltree[(_length_code[lc] + LITERALS + 1) * 2]++;
          s.dyn_dtree[d_code(dist) * 2]++;
        }
        return s.last_lit === s.lit_bufsize - 1;
      }
      exports._tr_init = _tr_init;
      exports._tr_stored_block = _tr_stored_block;
      exports._tr_flush_block = _tr_flush_block;
      exports._tr_tally = _tr_tally;
      exports._tr_align = _tr_align;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/adler32.js
  var require_adler32 = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/adler32.js"(exports, module) {
      "use strict";
      init_globals();
      function adler32(adler, buf, len, pos) {
        var s1 = adler & 65535 | 0, s2 = adler >>> 16 & 65535 | 0, n = 0;
        while (len !== 0) {
          n = len > 2e3 ? 2e3 : len;
          len -= n;
          do {
            s1 = s1 + buf[pos++] | 0;
            s2 = s2 + s1 | 0;
          } while (--n);
          s1 %= 65521;
          s2 %= 65521;
        }
        return s1 | s2 << 16 | 0;
      }
      module.exports = adler32;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/crc32.js
  var require_crc32 = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/crc32.js"(exports, module) {
      "use strict";
      init_globals();
      function makeTable() {
        var c, table = [];
        for (var n = 0; n < 256; n++) {
          c = n;
          for (var k = 0; k < 8; k++) {
            c = c & 1 ? 3988292384 ^ c >>> 1 : c >>> 1;
          }
          table[n] = c;
        }
        return table;
      }
      var crcTable = makeTable();
      function crc32(crc, buf, len, pos) {
        var t = crcTable, end = pos + len;
        crc ^= -1;
        for (var i = pos; i < end; i++) {
          crc = crc >>> 8 ^ t[(crc ^ buf[i]) & 255];
        }
        return crc ^ -1;
      }
      module.exports = crc32;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/messages.js
  var require_messages = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/messages.js"(exports, module) {
      "use strict";
      init_globals();
      module.exports = {
        2: "need dictionary",
        /* Z_NEED_DICT       2  */
        1: "stream end",
        /* Z_STREAM_END      1  */
        0: "",
        /* Z_OK              0  */
        "-1": "file error",
        /* Z_ERRNO         (-1) */
        "-2": "stream error",
        /* Z_STREAM_ERROR  (-2) */
        "-3": "data error",
        /* Z_DATA_ERROR    (-3) */
        "-4": "insufficient memory",
        /* Z_MEM_ERROR     (-4) */
        "-5": "buffer error",
        /* Z_BUF_ERROR     (-5) */
        "-6": "incompatible version"
        /* Z_VERSION_ERROR (-6) */
      };
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/deflate.js
  var require_deflate = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/deflate.js"(exports) {
      "use strict";
      init_globals();
      var utils = require_common();
      var trees = require_trees();
      var adler32 = require_adler32();
      var crc32 = require_crc32();
      var msg = require_messages();
      var Z_NO_FLUSH = 0;
      var Z_PARTIAL_FLUSH = 1;
      var Z_FULL_FLUSH = 3;
      var Z_FINISH = 4;
      var Z_BLOCK = 5;
      var Z_OK = 0;
      var Z_STREAM_END = 1;
      var Z_STREAM_ERROR = -2;
      var Z_DATA_ERROR = -3;
      var Z_BUF_ERROR = -5;
      var Z_DEFAULT_COMPRESSION = -1;
      var Z_FILTERED = 1;
      var Z_HUFFMAN_ONLY = 2;
      var Z_RLE = 3;
      var Z_FIXED = 4;
      var Z_DEFAULT_STRATEGY = 0;
      var Z_UNKNOWN = 2;
      var Z_DEFLATED = 8;
      var MAX_MEM_LEVEL = 9;
      var MAX_WBITS = 15;
      var DEF_MEM_LEVEL = 8;
      var LENGTH_CODES = 29;
      var LITERALS = 256;
      var L_CODES = LITERALS + 1 + LENGTH_CODES;
      var D_CODES = 30;
      var BL_CODES = 19;
      var HEAP_SIZE = 2 * L_CODES + 1;
      var MAX_BITS = 15;
      var MIN_MATCH = 3;
      var MAX_MATCH = 258;
      var MIN_LOOKAHEAD = MAX_MATCH + MIN_MATCH + 1;
      var PRESET_DICT = 32;
      var INIT_STATE = 42;
      var EXTRA_STATE = 69;
      var NAME_STATE = 73;
      var COMMENT_STATE = 91;
      var HCRC_STATE = 103;
      var BUSY_STATE = 113;
      var FINISH_STATE = 666;
      var BS_NEED_MORE = 1;
      var BS_BLOCK_DONE = 2;
      var BS_FINISH_STARTED = 3;
      var BS_FINISH_DONE = 4;
      var OS_CODE = 3;
      function err(strm, errorCode) {
        strm.msg = msg[errorCode];
        return errorCode;
      }
      function rank(f) {
        return (f << 1) - (f > 4 ? 9 : 0);
      }
      function zero(buf) {
        var len = buf.length;
        while (--len >= 0) {
          buf[len] = 0;
        }
      }
      function flush_pending(strm) {
        var s = strm.state;
        var len = s.pending;
        if (len > strm.avail_out) {
          len = strm.avail_out;
        }
        if (len === 0) {
          return;
        }
        utils.arraySet(strm.output, s.pending_buf, s.pending_out, len, strm.next_out);
        strm.next_out += len;
        s.pending_out += len;
        strm.total_out += len;
        strm.avail_out -= len;
        s.pending -= len;
        if (s.pending === 0) {
          s.pending_out = 0;
        }
      }
      function flush_block_only(s, last) {
        trees._tr_flush_block(s, s.block_start >= 0 ? s.block_start : -1, s.strstart - s.block_start, last);
        s.block_start = s.strstart;
        flush_pending(s.strm);
      }
      function put_byte(s, b) {
        s.pending_buf[s.pending++] = b;
      }
      function putShortMSB(s, b) {
        s.pending_buf[s.pending++] = b >>> 8 & 255;
        s.pending_buf[s.pending++] = b & 255;
      }
      function read_buf(strm, buf, start, size) {
        var len = strm.avail_in;
        if (len > size) {
          len = size;
        }
        if (len === 0) {
          return 0;
        }
        strm.avail_in -= len;
        utils.arraySet(buf, strm.input, strm.next_in, len, start);
        if (strm.state.wrap === 1) {
          strm.adler = adler32(strm.adler, buf, len, start);
        } else if (strm.state.wrap === 2) {
          strm.adler = crc32(strm.adler, buf, len, start);
        }
        strm.next_in += len;
        strm.total_in += len;
        return len;
      }
      function longest_match(s, cur_match) {
        var chain_length = s.max_chain_length;
        var scan = s.strstart;
        var match2;
        var len;
        var best_len = s.prev_length;
        var nice_match = s.nice_match;
        var limit = s.strstart > s.w_size - MIN_LOOKAHEAD ? s.strstart - (s.w_size - MIN_LOOKAHEAD) : 0;
        var _win = s.window;
        var wmask = s.w_mask;
        var prev = s.prev;
        var strend = s.strstart + MAX_MATCH;
        var scan_end1 = _win[scan + best_len - 1];
        var scan_end = _win[scan + best_len];
        if (s.prev_length >= s.good_match) {
          chain_length >>= 2;
        }
        if (nice_match > s.lookahead) {
          nice_match = s.lookahead;
        }
        do {
          match2 = cur_match;
          if (_win[match2 + best_len] !== scan_end || _win[match2 + best_len - 1] !== scan_end1 || _win[match2] !== _win[scan] || _win[++match2] !== _win[scan + 1]) {
            continue;
          }
          scan += 2;
          match2++;
          do {
          } while (_win[++scan] === _win[++match2] && _win[++scan] === _win[++match2] && _win[++scan] === _win[++match2] && _win[++scan] === _win[++match2] && _win[++scan] === _win[++match2] && _win[++scan] === _win[++match2] && _win[++scan] === _win[++match2] && _win[++scan] === _win[++match2] && scan < strend);
          len = MAX_MATCH - (strend - scan);
          scan = strend - MAX_MATCH;
          if (len > best_len) {
            s.match_start = cur_match;
            best_len = len;
            if (len >= nice_match) {
              break;
            }
            scan_end1 = _win[scan + best_len - 1];
            scan_end = _win[scan + best_len];
          }
        } while ((cur_match = prev[cur_match & wmask]) > limit && --chain_length !== 0);
        if (best_len <= s.lookahead) {
          return best_len;
        }
        return s.lookahead;
      }
      function fill_window(s) {
        var _w_size = s.w_size;
        var p, n, m, more, str;
        do {
          more = s.window_size - s.lookahead - s.strstart;
          if (s.strstart >= _w_size + (_w_size - MIN_LOOKAHEAD)) {
            utils.arraySet(s.window, s.window, _w_size, _w_size, 0);
            s.match_start -= _w_size;
            s.strstart -= _w_size;
            s.block_start -= _w_size;
            n = s.hash_size;
            p = n;
            do {
              m = s.head[--p];
              s.head[p] = m >= _w_size ? m - _w_size : 0;
            } while (--n);
            n = _w_size;
            p = n;
            do {
              m = s.prev[--p];
              s.prev[p] = m >= _w_size ? m - _w_size : 0;
            } while (--n);
            more += _w_size;
          }
          if (s.strm.avail_in === 0) {
            break;
          }
          n = read_buf(s.strm, s.window, s.strstart + s.lookahead, more);
          s.lookahead += n;
          if (s.lookahead + s.insert >= MIN_MATCH) {
            str = s.strstart - s.insert;
            s.ins_h = s.window[str];
            s.ins_h = (s.ins_h << s.hash_shift ^ s.window[str + 1]) & s.hash_mask;
            while (s.insert) {
              s.ins_h = (s.ins_h << s.hash_shift ^ s.window[str + MIN_MATCH - 1]) & s.hash_mask;
              s.prev[str & s.w_mask] = s.head[s.ins_h];
              s.head[s.ins_h] = str;
              str++;
              s.insert--;
              if (s.lookahead + s.insert < MIN_MATCH) {
                break;
              }
            }
          }
        } while (s.lookahead < MIN_LOOKAHEAD && s.strm.avail_in !== 0);
      }
      function deflate_stored(s, flush) {
        var max_block_size = 65535;
        if (max_block_size > s.pending_buf_size - 5) {
          max_block_size = s.pending_buf_size - 5;
        }
        for (; ; ) {
          if (s.lookahead <= 1) {
            fill_window(s);
            if (s.lookahead === 0 && flush === Z_NO_FLUSH) {
              return BS_NEED_MORE;
            }
            if (s.lookahead === 0) {
              break;
            }
          }
          s.strstart += s.lookahead;
          s.lookahead = 0;
          var max_start = s.block_start + max_block_size;
          if (s.strstart === 0 || s.strstart >= max_start) {
            s.lookahead = s.strstart - max_start;
            s.strstart = max_start;
            flush_block_only(s, false);
            if (s.strm.avail_out === 0) {
              return BS_NEED_MORE;
            }
          }
          if (s.strstart - s.block_start >= s.w_size - MIN_LOOKAHEAD) {
            flush_block_only(s, false);
            if (s.strm.avail_out === 0) {
              return BS_NEED_MORE;
            }
          }
        }
        s.insert = 0;
        if (flush === Z_FINISH) {
          flush_block_only(s, true);
          if (s.strm.avail_out === 0) {
            return BS_FINISH_STARTED;
          }
          return BS_FINISH_DONE;
        }
        if (s.strstart > s.block_start) {
          flush_block_only(s, false);
          if (s.strm.avail_out === 0) {
            return BS_NEED_MORE;
          }
        }
        return BS_NEED_MORE;
      }
      function deflate_fast(s, flush) {
        var hash_head;
        var bflush;
        for (; ; ) {
          if (s.lookahead < MIN_LOOKAHEAD) {
            fill_window(s);
            if (s.lookahead < MIN_LOOKAHEAD && flush === Z_NO_FLUSH) {
              return BS_NEED_MORE;
            }
            if (s.lookahead === 0) {
              break;
            }
          }
          hash_head = 0;
          if (s.lookahead >= MIN_MATCH) {
            s.ins_h = (s.ins_h << s.hash_shift ^ s.window[s.strstart + MIN_MATCH - 1]) & s.hash_mask;
            hash_head = s.prev[s.strstart & s.w_mask] = s.head[s.ins_h];
            s.head[s.ins_h] = s.strstart;
          }
          if (hash_head !== 0 && s.strstart - hash_head <= s.w_size - MIN_LOOKAHEAD) {
            s.match_length = longest_match(s, hash_head);
          }
          if (s.match_length >= MIN_MATCH) {
            bflush = trees._tr_tally(s, s.strstart - s.match_start, s.match_length - MIN_MATCH);
            s.lookahead -= s.match_length;
            if (s.match_length <= s.max_lazy_match && s.lookahead >= MIN_MATCH) {
              s.match_length--;
              do {
                s.strstart++;
                s.ins_h = (s.ins_h << s.hash_shift ^ s.window[s.strstart + MIN_MATCH - 1]) & s.hash_mask;
                hash_head = s.prev[s.strstart & s.w_mask] = s.head[s.ins_h];
                s.head[s.ins_h] = s.strstart;
              } while (--s.match_length !== 0);
              s.strstart++;
            } else {
              s.strstart += s.match_length;
              s.match_length = 0;
              s.ins_h = s.window[s.strstart];
              s.ins_h = (s.ins_h << s.hash_shift ^ s.window[s.strstart + 1]) & s.hash_mask;
            }
          } else {
            bflush = trees._tr_tally(s, 0, s.window[s.strstart]);
            s.lookahead--;
            s.strstart++;
          }
          if (bflush) {
            flush_block_only(s, false);
            if (s.strm.avail_out === 0) {
              return BS_NEED_MORE;
            }
          }
        }
        s.insert = s.strstart < MIN_MATCH - 1 ? s.strstart : MIN_MATCH - 1;
        if (flush === Z_FINISH) {
          flush_block_only(s, true);
          if (s.strm.avail_out === 0) {
            return BS_FINISH_STARTED;
          }
          return BS_FINISH_DONE;
        }
        if (s.last_lit) {
          flush_block_only(s, false);
          if (s.strm.avail_out === 0) {
            return BS_NEED_MORE;
          }
        }
        return BS_BLOCK_DONE;
      }
      function deflate_slow(s, flush) {
        var hash_head;
        var bflush;
        var max_insert;
        for (; ; ) {
          if (s.lookahead < MIN_LOOKAHEAD) {
            fill_window(s);
            if (s.lookahead < MIN_LOOKAHEAD && flush === Z_NO_FLUSH) {
              return BS_NEED_MORE;
            }
            if (s.lookahead === 0) {
              break;
            }
          }
          hash_head = 0;
          if (s.lookahead >= MIN_MATCH) {
            s.ins_h = (s.ins_h << s.hash_shift ^ s.window[s.strstart + MIN_MATCH - 1]) & s.hash_mask;
            hash_head = s.prev[s.strstart & s.w_mask] = s.head[s.ins_h];
            s.head[s.ins_h] = s.strstart;
          }
          s.prev_length = s.match_length;
          s.prev_match = s.match_start;
          s.match_length = MIN_MATCH - 1;
          if (hash_head !== 0 && s.prev_length < s.max_lazy_match && s.strstart - hash_head <= s.w_size - MIN_LOOKAHEAD) {
            s.match_length = longest_match(s, hash_head);
            if (s.match_length <= 5 && (s.strategy === Z_FILTERED || s.match_length === MIN_MATCH && s.strstart - s.match_start > 4096)) {
              s.match_length = MIN_MATCH - 1;
            }
          }
          if (s.prev_length >= MIN_MATCH && s.match_length <= s.prev_length) {
            max_insert = s.strstart + s.lookahead - MIN_MATCH;
            bflush = trees._tr_tally(s, s.strstart - 1 - s.prev_match, s.prev_length - MIN_MATCH);
            s.lookahead -= s.prev_length - 1;
            s.prev_length -= 2;
            do {
              if (++s.strstart <= max_insert) {
                s.ins_h = (s.ins_h << s.hash_shift ^ s.window[s.strstart + MIN_MATCH - 1]) & s.hash_mask;
                hash_head = s.prev[s.strstart & s.w_mask] = s.head[s.ins_h];
                s.head[s.ins_h] = s.strstart;
              }
            } while (--s.prev_length !== 0);
            s.match_available = 0;
            s.match_length = MIN_MATCH - 1;
            s.strstart++;
            if (bflush) {
              flush_block_only(s, false);
              if (s.strm.avail_out === 0) {
                return BS_NEED_MORE;
              }
            }
          } else if (s.match_available) {
            bflush = trees._tr_tally(s, 0, s.window[s.strstart - 1]);
            if (bflush) {
              flush_block_only(s, false);
            }
            s.strstart++;
            s.lookahead--;
            if (s.strm.avail_out === 0) {
              return BS_NEED_MORE;
            }
          } else {
            s.match_available = 1;
            s.strstart++;
            s.lookahead--;
          }
        }
        if (s.match_available) {
          bflush = trees._tr_tally(s, 0, s.window[s.strstart - 1]);
          s.match_available = 0;
        }
        s.insert = s.strstart < MIN_MATCH - 1 ? s.strstart : MIN_MATCH - 1;
        if (flush === Z_FINISH) {
          flush_block_only(s, true);
          if (s.strm.avail_out === 0) {
            return BS_FINISH_STARTED;
          }
          return BS_FINISH_DONE;
        }
        if (s.last_lit) {
          flush_block_only(s, false);
          if (s.strm.avail_out === 0) {
            return BS_NEED_MORE;
          }
        }
        return BS_BLOCK_DONE;
      }
      function deflate_rle(s, flush) {
        var bflush;
        var prev;
        var scan, strend;
        var _win = s.window;
        for (; ; ) {
          if (s.lookahead <= MAX_MATCH) {
            fill_window(s);
            if (s.lookahead <= MAX_MATCH && flush === Z_NO_FLUSH) {
              return BS_NEED_MORE;
            }
            if (s.lookahead === 0) {
              break;
            }
          }
          s.match_length = 0;
          if (s.lookahead >= MIN_MATCH && s.strstart > 0) {
            scan = s.strstart - 1;
            prev = _win[scan];
            if (prev === _win[++scan] && prev === _win[++scan] && prev === _win[++scan]) {
              strend = s.strstart + MAX_MATCH;
              do {
              } while (prev === _win[++scan] && prev === _win[++scan] && prev === _win[++scan] && prev === _win[++scan] && prev === _win[++scan] && prev === _win[++scan] && prev === _win[++scan] && prev === _win[++scan] && scan < strend);
              s.match_length = MAX_MATCH - (strend - scan);
              if (s.match_length > s.lookahead) {
                s.match_length = s.lookahead;
              }
            }
          }
          if (s.match_length >= MIN_MATCH) {
            bflush = trees._tr_tally(s, 1, s.match_length - MIN_MATCH);
            s.lookahead -= s.match_length;
            s.strstart += s.match_length;
            s.match_length = 0;
          } else {
            bflush = trees._tr_tally(s, 0, s.window[s.strstart]);
            s.lookahead--;
            s.strstart++;
          }
          if (bflush) {
            flush_block_only(s, false);
            if (s.strm.avail_out === 0) {
              return BS_NEED_MORE;
            }
          }
        }
        s.insert = 0;
        if (flush === Z_FINISH) {
          flush_block_only(s, true);
          if (s.strm.avail_out === 0) {
            return BS_FINISH_STARTED;
          }
          return BS_FINISH_DONE;
        }
        if (s.last_lit) {
          flush_block_only(s, false);
          if (s.strm.avail_out === 0) {
            return BS_NEED_MORE;
          }
        }
        return BS_BLOCK_DONE;
      }
      function deflate_huff(s, flush) {
        var bflush;
        for (; ; ) {
          if (s.lookahead === 0) {
            fill_window(s);
            if (s.lookahead === 0) {
              if (flush === Z_NO_FLUSH) {
                return BS_NEED_MORE;
              }
              break;
            }
          }
          s.match_length = 0;
          bflush = trees._tr_tally(s, 0, s.window[s.strstart]);
          s.lookahead--;
          s.strstart++;
          if (bflush) {
            flush_block_only(s, false);
            if (s.strm.avail_out === 0) {
              return BS_NEED_MORE;
            }
          }
        }
        s.insert = 0;
        if (flush === Z_FINISH) {
          flush_block_only(s, true);
          if (s.strm.avail_out === 0) {
            return BS_FINISH_STARTED;
          }
          return BS_FINISH_DONE;
        }
        if (s.last_lit) {
          flush_block_only(s, false);
          if (s.strm.avail_out === 0) {
            return BS_NEED_MORE;
          }
        }
        return BS_BLOCK_DONE;
      }
      function Config(good_length, max_lazy, nice_length, max_chain, func) {
        this.good_length = good_length;
        this.max_lazy = max_lazy;
        this.nice_length = nice_length;
        this.max_chain = max_chain;
        this.func = func;
      }
      var configuration_table;
      configuration_table = [
        /*      good lazy nice chain */
        new Config(0, 0, 0, 0, deflate_stored),
        /* 0 store only */
        new Config(4, 4, 8, 4, deflate_fast),
        /* 1 max speed, no lazy matches */
        new Config(4, 5, 16, 8, deflate_fast),
        /* 2 */
        new Config(4, 6, 32, 32, deflate_fast),
        /* 3 */
        new Config(4, 4, 16, 16, deflate_slow),
        /* 4 lazy matches */
        new Config(8, 16, 32, 32, deflate_slow),
        /* 5 */
        new Config(8, 16, 128, 128, deflate_slow),
        /* 6 */
        new Config(8, 32, 128, 256, deflate_slow),
        /* 7 */
        new Config(32, 128, 258, 1024, deflate_slow),
        /* 8 */
        new Config(32, 258, 258, 4096, deflate_slow)
        /* 9 max compression */
      ];
      function lm_init(s) {
        s.window_size = 2 * s.w_size;
        zero(s.head);
        s.max_lazy_match = configuration_table[s.level].max_lazy;
        s.good_match = configuration_table[s.level].good_length;
        s.nice_match = configuration_table[s.level].nice_length;
        s.max_chain_length = configuration_table[s.level].max_chain;
        s.strstart = 0;
        s.block_start = 0;
        s.lookahead = 0;
        s.insert = 0;
        s.match_length = s.prev_length = MIN_MATCH - 1;
        s.match_available = 0;
        s.ins_h = 0;
      }
      function DeflateState() {
        this.strm = null;
        this.status = 0;
        this.pending_buf = null;
        this.pending_buf_size = 0;
        this.pending_out = 0;
        this.pending = 0;
        this.wrap = 0;
        this.gzhead = null;
        this.gzindex = 0;
        this.method = Z_DEFLATED;
        this.last_flush = -1;
        this.w_size = 0;
        this.w_bits = 0;
        this.w_mask = 0;
        this.window = null;
        this.window_size = 0;
        this.prev = null;
        this.head = null;
        this.ins_h = 0;
        this.hash_size = 0;
        this.hash_bits = 0;
        this.hash_mask = 0;
        this.hash_shift = 0;
        this.block_start = 0;
        this.match_length = 0;
        this.prev_match = 0;
        this.match_available = 0;
        this.strstart = 0;
        this.match_start = 0;
        this.lookahead = 0;
        this.prev_length = 0;
        this.max_chain_length = 0;
        this.max_lazy_match = 0;
        this.level = 0;
        this.strategy = 0;
        this.good_match = 0;
        this.nice_match = 0;
        this.dyn_ltree = new utils.Buf16(HEAP_SIZE * 2);
        this.dyn_dtree = new utils.Buf16((2 * D_CODES + 1) * 2);
        this.bl_tree = new utils.Buf16((2 * BL_CODES + 1) * 2);
        zero(this.dyn_ltree);
        zero(this.dyn_dtree);
        zero(this.bl_tree);
        this.l_desc = null;
        this.d_desc = null;
        this.bl_desc = null;
        this.bl_count = new utils.Buf16(MAX_BITS + 1);
        this.heap = new utils.Buf16(2 * L_CODES + 1);
        zero(this.heap);
        this.heap_len = 0;
        this.heap_max = 0;
        this.depth = new utils.Buf16(2 * L_CODES + 1);
        zero(this.depth);
        this.l_buf = 0;
        this.lit_bufsize = 0;
        this.last_lit = 0;
        this.d_buf = 0;
        this.opt_len = 0;
        this.static_len = 0;
        this.matches = 0;
        this.insert = 0;
        this.bi_buf = 0;
        this.bi_valid = 0;
      }
      function deflateResetKeep(strm) {
        var s;
        if (!strm || !strm.state) {
          return err(strm, Z_STREAM_ERROR);
        }
        strm.total_in = strm.total_out = 0;
        strm.data_type = Z_UNKNOWN;
        s = strm.state;
        s.pending = 0;
        s.pending_out = 0;
        if (s.wrap < 0) {
          s.wrap = -s.wrap;
        }
        s.status = s.wrap ? INIT_STATE : BUSY_STATE;
        strm.adler = s.wrap === 2 ? 0 : 1;
        s.last_flush = Z_NO_FLUSH;
        trees._tr_init(s);
        return Z_OK;
      }
      function deflateReset(strm) {
        var ret = deflateResetKeep(strm);
        if (ret === Z_OK) {
          lm_init(strm.state);
        }
        return ret;
      }
      function deflateSetHeader(strm, head) {
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        if (strm.state.wrap !== 2) {
          return Z_STREAM_ERROR;
        }
        strm.state.gzhead = head;
        return Z_OK;
      }
      function deflateInit2(strm, level, method, windowBits, memLevel, strategy) {
        if (!strm) {
          return Z_STREAM_ERROR;
        }
        var wrap = 1;
        if (level === Z_DEFAULT_COMPRESSION) {
          level = 6;
        }
        if (windowBits < 0) {
          wrap = 0;
          windowBits = -windowBits;
        } else if (windowBits > 15) {
          wrap = 2;
          windowBits -= 16;
        }
        if (memLevel < 1 || memLevel > MAX_MEM_LEVEL || method !== Z_DEFLATED || windowBits < 8 || windowBits > 15 || level < 0 || level > 9 || strategy < 0 || strategy > Z_FIXED) {
          return err(strm, Z_STREAM_ERROR);
        }
        if (windowBits === 8) {
          windowBits = 9;
        }
        var s = new DeflateState();
        strm.state = s;
        s.strm = strm;
        s.wrap = wrap;
        s.gzhead = null;
        s.w_bits = windowBits;
        s.w_size = 1 << s.w_bits;
        s.w_mask = s.w_size - 1;
        s.hash_bits = memLevel + 7;
        s.hash_size = 1 << s.hash_bits;
        s.hash_mask = s.hash_size - 1;
        s.hash_shift = ~~((s.hash_bits + MIN_MATCH - 1) / MIN_MATCH);
        s.window = new utils.Buf8(s.w_size * 2);
        s.head = new utils.Buf16(s.hash_size);
        s.prev = new utils.Buf16(s.w_size);
        s.lit_bufsize = 1 << memLevel + 6;
        s.pending_buf_size = s.lit_bufsize * 4;
        s.pending_buf = new utils.Buf8(s.pending_buf_size);
        s.d_buf = 1 * s.lit_bufsize;
        s.l_buf = (1 + 2) * s.lit_bufsize;
        s.level = level;
        s.strategy = strategy;
        s.method = method;
        return deflateReset(strm);
      }
      function deflateInit(strm, level) {
        return deflateInit2(strm, level, Z_DEFLATED, MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY);
      }
      function deflate(strm, flush) {
        var old_flush, s;
        var beg, val;
        if (!strm || !strm.state || flush > Z_BLOCK || flush < 0) {
          return strm ? err(strm, Z_STREAM_ERROR) : Z_STREAM_ERROR;
        }
        s = strm.state;
        if (!strm.output || !strm.input && strm.avail_in !== 0 || s.status === FINISH_STATE && flush !== Z_FINISH) {
          return err(strm, strm.avail_out === 0 ? Z_BUF_ERROR : Z_STREAM_ERROR);
        }
        s.strm = strm;
        old_flush = s.last_flush;
        s.last_flush = flush;
        if (s.status === INIT_STATE) {
          if (s.wrap === 2) {
            strm.adler = 0;
            put_byte(s, 31);
            put_byte(s, 139);
            put_byte(s, 8);
            if (!s.gzhead) {
              put_byte(s, 0);
              put_byte(s, 0);
              put_byte(s, 0);
              put_byte(s, 0);
              put_byte(s, 0);
              put_byte(s, s.level === 9 ? 2 : s.strategy >= Z_HUFFMAN_ONLY || s.level < 2 ? 4 : 0);
              put_byte(s, OS_CODE);
              s.status = BUSY_STATE;
            } else {
              put_byte(
                s,
                (s.gzhead.text ? 1 : 0) + (s.gzhead.hcrc ? 2 : 0) + (!s.gzhead.extra ? 0 : 4) + (!s.gzhead.name ? 0 : 8) + (!s.gzhead.comment ? 0 : 16)
              );
              put_byte(s, s.gzhead.time & 255);
              put_byte(s, s.gzhead.time >> 8 & 255);
              put_byte(s, s.gzhead.time >> 16 & 255);
              put_byte(s, s.gzhead.time >> 24 & 255);
              put_byte(s, s.level === 9 ? 2 : s.strategy >= Z_HUFFMAN_ONLY || s.level < 2 ? 4 : 0);
              put_byte(s, s.gzhead.os & 255);
              if (s.gzhead.extra && s.gzhead.extra.length) {
                put_byte(s, s.gzhead.extra.length & 255);
                put_byte(s, s.gzhead.extra.length >> 8 & 255);
              }
              if (s.gzhead.hcrc) {
                strm.adler = crc32(strm.adler, s.pending_buf, s.pending, 0);
              }
              s.gzindex = 0;
              s.status = EXTRA_STATE;
            }
          } else {
            var header = Z_DEFLATED + (s.w_bits - 8 << 4) << 8;
            var level_flags = -1;
            if (s.strategy >= Z_HUFFMAN_ONLY || s.level < 2) {
              level_flags = 0;
            } else if (s.level < 6) {
              level_flags = 1;
            } else if (s.level === 6) {
              level_flags = 2;
            } else {
              level_flags = 3;
            }
            header |= level_flags << 6;
            if (s.strstart !== 0) {
              header |= PRESET_DICT;
            }
            header += 31 - header % 31;
            s.status = BUSY_STATE;
            putShortMSB(s, header);
            if (s.strstart !== 0) {
              putShortMSB(s, strm.adler >>> 16);
              putShortMSB(s, strm.adler & 65535);
            }
            strm.adler = 1;
          }
        }
        if (s.status === EXTRA_STATE) {
          if (s.gzhead.extra) {
            beg = s.pending;
            while (s.gzindex < (s.gzhead.extra.length & 65535)) {
              if (s.pending === s.pending_buf_size) {
                if (s.gzhead.hcrc && s.pending > beg) {
                  strm.adler = crc32(strm.adler, s.pending_buf, s.pending - beg, beg);
                }
                flush_pending(strm);
                beg = s.pending;
                if (s.pending === s.pending_buf_size) {
                  break;
                }
              }
              put_byte(s, s.gzhead.extra[s.gzindex] & 255);
              s.gzindex++;
            }
            if (s.gzhead.hcrc && s.pending > beg) {
              strm.adler = crc32(strm.adler, s.pending_buf, s.pending - beg, beg);
            }
            if (s.gzindex === s.gzhead.extra.length) {
              s.gzindex = 0;
              s.status = NAME_STATE;
            }
          } else {
            s.status = NAME_STATE;
          }
        }
        if (s.status === NAME_STATE) {
          if (s.gzhead.name) {
            beg = s.pending;
            do {
              if (s.pending === s.pending_buf_size) {
                if (s.gzhead.hcrc && s.pending > beg) {
                  strm.adler = crc32(strm.adler, s.pending_buf, s.pending - beg, beg);
                }
                flush_pending(strm);
                beg = s.pending;
                if (s.pending === s.pending_buf_size) {
                  val = 1;
                  break;
                }
              }
              if (s.gzindex < s.gzhead.name.length) {
                val = s.gzhead.name.charCodeAt(s.gzindex++) & 255;
              } else {
                val = 0;
              }
              put_byte(s, val);
            } while (val !== 0);
            if (s.gzhead.hcrc && s.pending > beg) {
              strm.adler = crc32(strm.adler, s.pending_buf, s.pending - beg, beg);
            }
            if (val === 0) {
              s.gzindex = 0;
              s.status = COMMENT_STATE;
            }
          } else {
            s.status = COMMENT_STATE;
          }
        }
        if (s.status === COMMENT_STATE) {
          if (s.gzhead.comment) {
            beg = s.pending;
            do {
              if (s.pending === s.pending_buf_size) {
                if (s.gzhead.hcrc && s.pending > beg) {
                  strm.adler = crc32(strm.adler, s.pending_buf, s.pending - beg, beg);
                }
                flush_pending(strm);
                beg = s.pending;
                if (s.pending === s.pending_buf_size) {
                  val = 1;
                  break;
                }
              }
              if (s.gzindex < s.gzhead.comment.length) {
                val = s.gzhead.comment.charCodeAt(s.gzindex++) & 255;
              } else {
                val = 0;
              }
              put_byte(s, val);
            } while (val !== 0);
            if (s.gzhead.hcrc && s.pending > beg) {
              strm.adler = crc32(strm.adler, s.pending_buf, s.pending - beg, beg);
            }
            if (val === 0) {
              s.status = HCRC_STATE;
            }
          } else {
            s.status = HCRC_STATE;
          }
        }
        if (s.status === HCRC_STATE) {
          if (s.gzhead.hcrc) {
            if (s.pending + 2 > s.pending_buf_size) {
              flush_pending(strm);
            }
            if (s.pending + 2 <= s.pending_buf_size) {
              put_byte(s, strm.adler & 255);
              put_byte(s, strm.adler >> 8 & 255);
              strm.adler = 0;
              s.status = BUSY_STATE;
            }
          } else {
            s.status = BUSY_STATE;
          }
        }
        if (s.pending !== 0) {
          flush_pending(strm);
          if (strm.avail_out === 0) {
            s.last_flush = -1;
            return Z_OK;
          }
        } else if (strm.avail_in === 0 && rank(flush) <= rank(old_flush) && flush !== Z_FINISH) {
          return err(strm, Z_BUF_ERROR);
        }
        if (s.status === FINISH_STATE && strm.avail_in !== 0) {
          return err(strm, Z_BUF_ERROR);
        }
        if (strm.avail_in !== 0 || s.lookahead !== 0 || flush !== Z_NO_FLUSH && s.status !== FINISH_STATE) {
          var bstate = s.strategy === Z_HUFFMAN_ONLY ? deflate_huff(s, flush) : s.strategy === Z_RLE ? deflate_rle(s, flush) : configuration_table[s.level].func(s, flush);
          if (bstate === BS_FINISH_STARTED || bstate === BS_FINISH_DONE) {
            s.status = FINISH_STATE;
          }
          if (bstate === BS_NEED_MORE || bstate === BS_FINISH_STARTED) {
            if (strm.avail_out === 0) {
              s.last_flush = -1;
            }
            return Z_OK;
          }
          if (bstate === BS_BLOCK_DONE) {
            if (flush === Z_PARTIAL_FLUSH) {
              trees._tr_align(s);
            } else if (flush !== Z_BLOCK) {
              trees._tr_stored_block(s, 0, 0, false);
              if (flush === Z_FULL_FLUSH) {
                zero(s.head);
                if (s.lookahead === 0) {
                  s.strstart = 0;
                  s.block_start = 0;
                  s.insert = 0;
                }
              }
            }
            flush_pending(strm);
            if (strm.avail_out === 0) {
              s.last_flush = -1;
              return Z_OK;
            }
          }
        }
        if (flush !== Z_FINISH) {
          return Z_OK;
        }
        if (s.wrap <= 0) {
          return Z_STREAM_END;
        }
        if (s.wrap === 2) {
          put_byte(s, strm.adler & 255);
          put_byte(s, strm.adler >> 8 & 255);
          put_byte(s, strm.adler >> 16 & 255);
          put_byte(s, strm.adler >> 24 & 255);
          put_byte(s, strm.total_in & 255);
          put_byte(s, strm.total_in >> 8 & 255);
          put_byte(s, strm.total_in >> 16 & 255);
          put_byte(s, strm.total_in >> 24 & 255);
        } else {
          putShortMSB(s, strm.adler >>> 16);
          putShortMSB(s, strm.adler & 65535);
        }
        flush_pending(strm);
        if (s.wrap > 0) {
          s.wrap = -s.wrap;
        }
        return s.pending !== 0 ? Z_OK : Z_STREAM_END;
      }
      function deflateEnd(strm) {
        var status;
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        status = strm.state.status;
        if (status !== INIT_STATE && status !== EXTRA_STATE && status !== NAME_STATE && status !== COMMENT_STATE && status !== HCRC_STATE && status !== BUSY_STATE && status !== FINISH_STATE) {
          return err(strm, Z_STREAM_ERROR);
        }
        strm.state = null;
        return status === BUSY_STATE ? err(strm, Z_DATA_ERROR) : Z_OK;
      }
      function deflateSetDictionary(strm, dictionary) {
        var dictLength = dictionary.length;
        var s;
        var str, n;
        var wrap;
        var avail;
        var next;
        var input;
        var tmpDict;
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        s = strm.state;
        wrap = s.wrap;
        if (wrap === 2 || wrap === 1 && s.status !== INIT_STATE || s.lookahead) {
          return Z_STREAM_ERROR;
        }
        if (wrap === 1) {
          strm.adler = adler32(strm.adler, dictionary, dictLength, 0);
        }
        s.wrap = 0;
        if (dictLength >= s.w_size) {
          if (wrap === 0) {
            zero(s.head);
            s.strstart = 0;
            s.block_start = 0;
            s.insert = 0;
          }
          tmpDict = new utils.Buf8(s.w_size);
          utils.arraySet(tmpDict, dictionary, dictLength - s.w_size, s.w_size, 0);
          dictionary = tmpDict;
          dictLength = s.w_size;
        }
        avail = strm.avail_in;
        next = strm.next_in;
        input = strm.input;
        strm.avail_in = dictLength;
        strm.next_in = 0;
        strm.input = dictionary;
        fill_window(s);
        while (s.lookahead >= MIN_MATCH) {
          str = s.strstart;
          n = s.lookahead - (MIN_MATCH - 1);
          do {
            s.ins_h = (s.ins_h << s.hash_shift ^ s.window[str + MIN_MATCH - 1]) & s.hash_mask;
            s.prev[str & s.w_mask] = s.head[s.ins_h];
            s.head[s.ins_h] = str;
            str++;
          } while (--n);
          s.strstart = str;
          s.lookahead = MIN_MATCH - 1;
          fill_window(s);
        }
        s.strstart += s.lookahead;
        s.block_start = s.strstart;
        s.insert = s.lookahead;
        s.lookahead = 0;
        s.match_length = s.prev_length = MIN_MATCH - 1;
        s.match_available = 0;
        strm.next_in = next;
        strm.input = input;
        strm.avail_in = avail;
        s.wrap = wrap;
        return Z_OK;
      }
      exports.deflateInit = deflateInit;
      exports.deflateInit2 = deflateInit2;
      exports.deflateReset = deflateReset;
      exports.deflateResetKeep = deflateResetKeep;
      exports.deflateSetHeader = deflateSetHeader;
      exports.deflate = deflate;
      exports.deflateEnd = deflateEnd;
      exports.deflateSetDictionary = deflateSetDictionary;
      exports.deflateInfo = "pako deflate (from Nodeca project)";
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/utils/strings.js
  var require_strings = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/utils/strings.js"(exports) {
      "use strict";
      init_globals();
      var utils = require_common();
      var STR_APPLY_OK = true;
      var STR_APPLY_UIA_OK = true;
      try {
        String.fromCharCode.apply(null, [0]);
      } catch (__) {
        STR_APPLY_OK = false;
      }
      try {
        String.fromCharCode.apply(null, new Uint8Array(1));
      } catch (__) {
        STR_APPLY_UIA_OK = false;
      }
      var _utf8len = new utils.Buf8(256);
      for (q = 0; q < 256; q++) {
        _utf8len[q] = q >= 252 ? 6 : q >= 248 ? 5 : q >= 240 ? 4 : q >= 224 ? 3 : q >= 192 ? 2 : 1;
      }
      var q;
      _utf8len[254] = _utf8len[254] = 1;
      exports.string2buf = function(str) {
        var buf, c, c2, m_pos, i, str_len = str.length, buf_len = 0;
        for (m_pos = 0; m_pos < str_len; m_pos++) {
          c = str.charCodeAt(m_pos);
          if ((c & 64512) === 55296 && m_pos + 1 < str_len) {
            c2 = str.charCodeAt(m_pos + 1);
            if ((c2 & 64512) === 56320) {
              c = 65536 + (c - 55296 << 10) + (c2 - 56320);
              m_pos++;
            }
          }
          buf_len += c < 128 ? 1 : c < 2048 ? 2 : c < 65536 ? 3 : 4;
        }
        buf = new utils.Buf8(buf_len);
        for (i = 0, m_pos = 0; i < buf_len; m_pos++) {
          c = str.charCodeAt(m_pos);
          if ((c & 64512) === 55296 && m_pos + 1 < str_len) {
            c2 = str.charCodeAt(m_pos + 1);
            if ((c2 & 64512) === 56320) {
              c = 65536 + (c - 55296 << 10) + (c2 - 56320);
              m_pos++;
            }
          }
          if (c < 128) {
            buf[i++] = c;
          } else if (c < 2048) {
            buf[i++] = 192 | c >>> 6;
            buf[i++] = 128 | c & 63;
          } else if (c < 65536) {
            buf[i++] = 224 | c >>> 12;
            buf[i++] = 128 | c >>> 6 & 63;
            buf[i++] = 128 | c & 63;
          } else {
            buf[i++] = 240 | c >>> 18;
            buf[i++] = 128 | c >>> 12 & 63;
            buf[i++] = 128 | c >>> 6 & 63;
            buf[i++] = 128 | c & 63;
          }
        }
        return buf;
      };
      function buf2binstring(buf, len) {
        if (len < 65534) {
          if (buf.subarray && STR_APPLY_UIA_OK || !buf.subarray && STR_APPLY_OK) {
            return String.fromCharCode.apply(null, utils.shrinkBuf(buf, len));
          }
        }
        var result = "";
        for (var i = 0; i < len; i++) {
          result += String.fromCharCode(buf[i]);
        }
        return result;
      }
      exports.buf2binstring = function(buf) {
        return buf2binstring(buf, buf.length);
      };
      exports.binstring2buf = function(str) {
        var buf = new utils.Buf8(str.length);
        for (var i = 0, len = buf.length; i < len; i++) {
          buf[i] = str.charCodeAt(i);
        }
        return buf;
      };
      exports.buf2string = function(buf, max) {
        var i, out, c, c_len;
        var len = max || buf.length;
        var utf16buf = new Array(len * 2);
        for (out = 0, i = 0; i < len; ) {
          c = buf[i++];
          if (c < 128) {
            utf16buf[out++] = c;
            continue;
          }
          c_len = _utf8len[c];
          if (c_len > 4) {
            utf16buf[out++] = 65533;
            i += c_len - 1;
            continue;
          }
          c &= c_len === 2 ? 31 : c_len === 3 ? 15 : 7;
          while (c_len > 1 && i < len) {
            c = c << 6 | buf[i++] & 63;
            c_len--;
          }
          if (c_len > 1) {
            utf16buf[out++] = 65533;
            continue;
          }
          if (c < 65536) {
            utf16buf[out++] = c;
          } else {
            c -= 65536;
            utf16buf[out++] = 55296 | c >> 10 & 1023;
            utf16buf[out++] = 56320 | c & 1023;
          }
        }
        return buf2binstring(utf16buf, out);
      };
      exports.utf8border = function(buf, max) {
        var pos;
        max = max || buf.length;
        if (max > buf.length) {
          max = buf.length;
        }
        pos = max - 1;
        while (pos >= 0 && (buf[pos] & 192) === 128) {
          pos--;
        }
        if (pos < 0) {
          return max;
        }
        if (pos === 0) {
          return max;
        }
        return pos + _utf8len[buf[pos]] > max ? pos : max;
      };
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/zstream.js
  var require_zstream = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/zstream.js"(exports, module) {
      "use strict";
      init_globals();
      function ZStream() {
        this.input = null;
        this.next_in = 0;
        this.avail_in = 0;
        this.total_in = 0;
        this.output = null;
        this.next_out = 0;
        this.avail_out = 0;
        this.total_out = 0;
        this.msg = "";
        this.state = null;
        this.data_type = 2;
        this.adler = 0;
      }
      module.exports = ZStream;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/deflate.js
  var require_deflate2 = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/deflate.js"(exports) {
      "use strict";
      init_globals();
      var zlib_deflate = require_deflate();
      var utils = require_common();
      var strings = require_strings();
      var msg = require_messages();
      var ZStream = require_zstream();
      var toString = Object.prototype.toString;
      var Z_NO_FLUSH = 0;
      var Z_FINISH = 4;
      var Z_OK = 0;
      var Z_STREAM_END = 1;
      var Z_SYNC_FLUSH = 2;
      var Z_DEFAULT_COMPRESSION = -1;
      var Z_DEFAULT_STRATEGY = 0;
      var Z_DEFLATED = 8;
      function Deflate(options) {
        if (!(this instanceof Deflate)) return new Deflate(options);
        this.options = utils.assign({
          level: Z_DEFAULT_COMPRESSION,
          method: Z_DEFLATED,
          chunkSize: 16384,
          windowBits: 15,
          memLevel: 8,
          strategy: Z_DEFAULT_STRATEGY,
          to: ""
        }, options || {});
        var opt = this.options;
        if (opt.raw && opt.windowBits > 0) {
          opt.windowBits = -opt.windowBits;
        } else if (opt.gzip && opt.windowBits > 0 && opt.windowBits < 16) {
          opt.windowBits += 16;
        }
        this.err = 0;
        this.msg = "";
        this.ended = false;
        this.chunks = [];
        this.strm = new ZStream();
        this.strm.avail_out = 0;
        var status = zlib_deflate.deflateInit2(
          this.strm,
          opt.level,
          opt.method,
          opt.windowBits,
          opt.memLevel,
          opt.strategy
        );
        if (status !== Z_OK) {
          throw new Error(msg[status]);
        }
        if (opt.header) {
          zlib_deflate.deflateSetHeader(this.strm, opt.header);
        }
        if (opt.dictionary) {
          var dict;
          if (typeof opt.dictionary === "string") {
            dict = strings.string2buf(opt.dictionary);
          } else if (toString.call(opt.dictionary) === "[object ArrayBuffer]") {
            dict = new Uint8Array(opt.dictionary);
          } else {
            dict = opt.dictionary;
          }
          status = zlib_deflate.deflateSetDictionary(this.strm, dict);
          if (status !== Z_OK) {
            throw new Error(msg[status]);
          }
          this._dict_set = true;
        }
      }
      Deflate.prototype.push = function(data, mode) {
        var strm = this.strm;
        var chunkSize = this.options.chunkSize;
        var status, _mode;
        if (this.ended) {
          return false;
        }
        _mode = mode === ~~mode ? mode : mode === true ? Z_FINISH : Z_NO_FLUSH;
        if (typeof data === "string") {
          strm.input = strings.string2buf(data);
        } else if (toString.call(data) === "[object ArrayBuffer]") {
          strm.input = new Uint8Array(data);
        } else {
          strm.input = data;
        }
        strm.next_in = 0;
        strm.avail_in = strm.input.length;
        do {
          if (strm.avail_out === 0) {
            strm.output = new utils.Buf8(chunkSize);
            strm.next_out = 0;
            strm.avail_out = chunkSize;
          }
          status = zlib_deflate.deflate(strm, _mode);
          if (status !== Z_STREAM_END && status !== Z_OK) {
            this.onEnd(status);
            this.ended = true;
            return false;
          }
          if (strm.avail_out === 0 || strm.avail_in === 0 && (_mode === Z_FINISH || _mode === Z_SYNC_FLUSH)) {
            if (this.options.to === "string") {
              this.onData(strings.buf2binstring(utils.shrinkBuf(strm.output, strm.next_out)));
            } else {
              this.onData(utils.shrinkBuf(strm.output, strm.next_out));
            }
          }
        } while ((strm.avail_in > 0 || strm.avail_out === 0) && status !== Z_STREAM_END);
        if (_mode === Z_FINISH) {
          status = zlib_deflate.deflateEnd(this.strm);
          this.onEnd(status);
          this.ended = true;
          return status === Z_OK;
        }
        if (_mode === Z_SYNC_FLUSH) {
          this.onEnd(Z_OK);
          strm.avail_out = 0;
          return true;
        }
        return true;
      };
      Deflate.prototype.onData = function(chunk) {
        this.chunks.push(chunk);
      };
      Deflate.prototype.onEnd = function(status) {
        if (status === Z_OK) {
          if (this.options.to === "string") {
            this.result = this.chunks.join("");
          } else {
            this.result = utils.flattenChunks(this.chunks);
          }
        }
        this.chunks = [];
        this.err = status;
        this.msg = this.strm.msg;
      };
      function deflate(input, options) {
        var deflator = new Deflate(options);
        deflator.push(input, true);
        if (deflator.err) {
          throw deflator.msg || msg[deflator.err];
        }
        return deflator.result;
      }
      function deflateRaw(input, options) {
        options = options || {};
        options.raw = true;
        return deflate(input, options);
      }
      function gzip(input, options) {
        options = options || {};
        options.gzip = true;
        return deflate(input, options);
      }
      exports.Deflate = Deflate;
      exports.deflate = deflate;
      exports.deflateRaw = deflateRaw;
      exports.gzip = gzip;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/inffast.js
  var require_inffast = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/inffast.js"(exports, module) {
      "use strict";
      init_globals();
      var BAD = 30;
      var TYPE = 12;
      module.exports = function inflate_fast(strm, start) {
        var state;
        var _in;
        var last;
        var _out;
        var beg;
        var end;
        var dmax;
        var wsize;
        var whave;
        var wnext;
        var s_window;
        var hold;
        var bits;
        var lcode;
        var dcode;
        var lmask;
        var dmask;
        var here;
        var op;
        var len;
        var dist;
        var from;
        var from_source;
        var input, output;
        state = strm.state;
        _in = strm.next_in;
        input = strm.input;
        last = _in + (strm.avail_in - 5);
        _out = strm.next_out;
        output = strm.output;
        beg = _out - (start - strm.avail_out);
        end = _out + (strm.avail_out - 257);
        dmax = state.dmax;
        wsize = state.wsize;
        whave = state.whave;
        wnext = state.wnext;
        s_window = state.window;
        hold = state.hold;
        bits = state.bits;
        lcode = state.lencode;
        dcode = state.distcode;
        lmask = (1 << state.lenbits) - 1;
        dmask = (1 << state.distbits) - 1;
        top:
          do {
            if (bits < 15) {
              hold += input[_in++] << bits;
              bits += 8;
              hold += input[_in++] << bits;
              bits += 8;
            }
            here = lcode[hold & lmask];
            dolen:
              for (; ; ) {
                op = here >>> 24;
                hold >>>= op;
                bits -= op;
                op = here >>> 16 & 255;
                if (op === 0) {
                  output[_out++] = here & 65535;
                } else if (op & 16) {
                  len = here & 65535;
                  op &= 15;
                  if (op) {
                    if (bits < op) {
                      hold += input[_in++] << bits;
                      bits += 8;
                    }
                    len += hold & (1 << op) - 1;
                    hold >>>= op;
                    bits -= op;
                  }
                  if (bits < 15) {
                    hold += input[_in++] << bits;
                    bits += 8;
                    hold += input[_in++] << bits;
                    bits += 8;
                  }
                  here = dcode[hold & dmask];
                  dodist:
                    for (; ; ) {
                      op = here >>> 24;
                      hold >>>= op;
                      bits -= op;
                      op = here >>> 16 & 255;
                      if (op & 16) {
                        dist = here & 65535;
                        op &= 15;
                        if (bits < op) {
                          hold += input[_in++] << bits;
                          bits += 8;
                          if (bits < op) {
                            hold += input[_in++] << bits;
                            bits += 8;
                          }
                        }
                        dist += hold & (1 << op) - 1;
                        if (dist > dmax) {
                          strm.msg = "invalid distance too far back";
                          state.mode = BAD;
                          break top;
                        }
                        hold >>>= op;
                        bits -= op;
                        op = _out - beg;
                        if (dist > op) {
                          op = dist - op;
                          if (op > whave) {
                            if (state.sane) {
                              strm.msg = "invalid distance too far back";
                              state.mode = BAD;
                              break top;
                            }
                          }
                          from = 0;
                          from_source = s_window;
                          if (wnext === 0) {
                            from += wsize - op;
                            if (op < len) {
                              len -= op;
                              do {
                                output[_out++] = s_window[from++];
                              } while (--op);
                              from = _out - dist;
                              from_source = output;
                            }
                          } else if (wnext < op) {
                            from += wsize + wnext - op;
                            op -= wnext;
                            if (op < len) {
                              len -= op;
                              do {
                                output[_out++] = s_window[from++];
                              } while (--op);
                              from = 0;
                              if (wnext < len) {
                                op = wnext;
                                len -= op;
                                do {
                                  output[_out++] = s_window[from++];
                                } while (--op);
                                from = _out - dist;
                                from_source = output;
                              }
                            }
                          } else {
                            from += wnext - op;
                            if (op < len) {
                              len -= op;
                              do {
                                output[_out++] = s_window[from++];
                              } while (--op);
                              from = _out - dist;
                              from_source = output;
                            }
                          }
                          while (len > 2) {
                            output[_out++] = from_source[from++];
                            output[_out++] = from_source[from++];
                            output[_out++] = from_source[from++];
                            len -= 3;
                          }
                          if (len) {
                            output[_out++] = from_source[from++];
                            if (len > 1) {
                              output[_out++] = from_source[from++];
                            }
                          }
                        } else {
                          from = _out - dist;
                          do {
                            output[_out++] = output[from++];
                            output[_out++] = output[from++];
                            output[_out++] = output[from++];
                            len -= 3;
                          } while (len > 2);
                          if (len) {
                            output[_out++] = output[from++];
                            if (len > 1) {
                              output[_out++] = output[from++];
                            }
                          }
                        }
                      } else if ((op & 64) === 0) {
                        here = dcode[(here & 65535) + (hold & (1 << op) - 1)];
                        continue dodist;
                      } else {
                        strm.msg = "invalid distance code";
                        state.mode = BAD;
                        break top;
                      }
                      break;
                    }
                } else if ((op & 64) === 0) {
                  here = lcode[(here & 65535) + (hold & (1 << op) - 1)];
                  continue dolen;
                } else if (op & 32) {
                  state.mode = TYPE;
                  break top;
                } else {
                  strm.msg = "invalid literal/length code";
                  state.mode = BAD;
                  break top;
                }
                break;
              }
          } while (_in < last && _out < end);
        len = bits >> 3;
        _in -= len;
        bits -= len << 3;
        hold &= (1 << bits) - 1;
        strm.next_in = _in;
        strm.next_out = _out;
        strm.avail_in = _in < last ? 5 + (last - _in) : 5 - (_in - last);
        strm.avail_out = _out < end ? 257 + (end - _out) : 257 - (_out - end);
        state.hold = hold;
        state.bits = bits;
        return;
      };
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/inftrees.js
  var require_inftrees = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/inftrees.js"(exports, module) {
      "use strict";
      init_globals();
      var utils = require_common();
      var MAXBITS = 15;
      var ENOUGH_LENS = 852;
      var ENOUGH_DISTS = 592;
      var CODES = 0;
      var LENS = 1;
      var DISTS = 2;
      var lbase = [
        /* Length codes 257..285 base */
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        13,
        15,
        17,
        19,
        23,
        27,
        31,
        35,
        43,
        51,
        59,
        67,
        83,
        99,
        115,
        131,
        163,
        195,
        227,
        258,
        0,
        0
      ];
      var lext = [
        /* Length codes 257..285 extra */
        16,
        16,
        16,
        16,
        16,
        16,
        16,
        16,
        17,
        17,
        17,
        17,
        18,
        18,
        18,
        18,
        19,
        19,
        19,
        19,
        20,
        20,
        20,
        20,
        21,
        21,
        21,
        21,
        16,
        72,
        78
      ];
      var dbase = [
        /* Distance codes 0..29 base */
        1,
        2,
        3,
        4,
        5,
        7,
        9,
        13,
        17,
        25,
        33,
        49,
        65,
        97,
        129,
        193,
        257,
        385,
        513,
        769,
        1025,
        1537,
        2049,
        3073,
        4097,
        6145,
        8193,
        12289,
        16385,
        24577,
        0,
        0
      ];
      var dext = [
        /* Distance codes 0..29 extra */
        16,
        16,
        16,
        16,
        17,
        17,
        18,
        18,
        19,
        19,
        20,
        20,
        21,
        21,
        22,
        22,
        23,
        23,
        24,
        24,
        25,
        25,
        26,
        26,
        27,
        27,
        28,
        28,
        29,
        29,
        64,
        64
      ];
      module.exports = function inflate_table(type, lens, lens_index, codes, table, table_index, work, opts) {
        var bits = opts.bits;
        var len = 0;
        var sym = 0;
        var min = 0, max = 0;
        var root = 0;
        var curr = 0;
        var drop = 0;
        var left = 0;
        var used = 0;
        var huff = 0;
        var incr;
        var fill;
        var low;
        var mask;
        var next;
        var base = null;
        var base_index = 0;
        var end;
        var count = new utils.Buf16(MAXBITS + 1);
        var offs = new utils.Buf16(MAXBITS + 1);
        var extra = null;
        var extra_index = 0;
        var here_bits, here_op, here_val;
        for (len = 0; len <= MAXBITS; len++) {
          count[len] = 0;
        }
        for (sym = 0; sym < codes; sym++) {
          count[lens[lens_index + sym]]++;
        }
        root = bits;
        for (max = MAXBITS; max >= 1; max--) {
          if (count[max] !== 0) {
            break;
          }
        }
        if (root > max) {
          root = max;
        }
        if (max === 0) {
          table[table_index++] = 1 << 24 | 64 << 16 | 0;
          table[table_index++] = 1 << 24 | 64 << 16 | 0;
          opts.bits = 1;
          return 0;
        }
        for (min = 1; min < max; min++) {
          if (count[min] !== 0) {
            break;
          }
        }
        if (root < min) {
          root = min;
        }
        left = 1;
        for (len = 1; len <= MAXBITS; len++) {
          left <<= 1;
          left -= count[len];
          if (left < 0) {
            return -1;
          }
        }
        if (left > 0 && (type === CODES || max !== 1)) {
          return -1;
        }
        offs[1] = 0;
        for (len = 1; len < MAXBITS; len++) {
          offs[len + 1] = offs[len] + count[len];
        }
        for (sym = 0; sym < codes; sym++) {
          if (lens[lens_index + sym] !== 0) {
            work[offs[lens[lens_index + sym]]++] = sym;
          }
        }
        if (type === CODES) {
          base = extra = work;
          end = 19;
        } else if (type === LENS) {
          base = lbase;
          base_index -= 257;
          extra = lext;
          extra_index -= 257;
          end = 256;
        } else {
          base = dbase;
          extra = dext;
          end = -1;
        }
        huff = 0;
        sym = 0;
        len = min;
        next = table_index;
        curr = root;
        drop = 0;
        low = -1;
        used = 1 << root;
        mask = used - 1;
        if (type === LENS && used > ENOUGH_LENS || type === DISTS && used > ENOUGH_DISTS) {
          return 1;
        }
        for (; ; ) {
          here_bits = len - drop;
          if (work[sym] < end) {
            here_op = 0;
            here_val = work[sym];
          } else if (work[sym] > end) {
            here_op = extra[extra_index + work[sym]];
            here_val = base[base_index + work[sym]];
          } else {
            here_op = 32 + 64;
            here_val = 0;
          }
          incr = 1 << len - drop;
          fill = 1 << curr;
          min = fill;
          do {
            fill -= incr;
            table[next + (huff >> drop) + fill] = here_bits << 24 | here_op << 16 | here_val | 0;
          } while (fill !== 0);
          incr = 1 << len - 1;
          while (huff & incr) {
            incr >>= 1;
          }
          if (incr !== 0) {
            huff &= incr - 1;
            huff += incr;
          } else {
            huff = 0;
          }
          sym++;
          if (--count[len] === 0) {
            if (len === max) {
              break;
            }
            len = lens[lens_index + work[sym]];
          }
          if (len > root && (huff & mask) !== low) {
            if (drop === 0) {
              drop = root;
            }
            next += min;
            curr = len - drop;
            left = 1 << curr;
            while (curr + drop < max) {
              left -= count[curr + drop];
              if (left <= 0) {
                break;
              }
              curr++;
              left <<= 1;
            }
            used += 1 << curr;
            if (type === LENS && used > ENOUGH_LENS || type === DISTS && used > ENOUGH_DISTS) {
              return 1;
            }
            low = huff & mask;
            table[low] = root << 24 | curr << 16 | next - table_index | 0;
          }
        }
        if (huff !== 0) {
          table[next + huff] = len - drop << 24 | 64 << 16 | 0;
        }
        opts.bits = root;
        return 0;
      };
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/inflate.js
  var require_inflate = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/inflate.js"(exports) {
      "use strict";
      init_globals();
      var utils = require_common();
      var adler32 = require_adler32();
      var crc32 = require_crc32();
      var inflate_fast = require_inffast();
      var inflate_table = require_inftrees();
      var CODES = 0;
      var LENS = 1;
      var DISTS = 2;
      var Z_FINISH = 4;
      var Z_BLOCK = 5;
      var Z_TREES = 6;
      var Z_OK = 0;
      var Z_STREAM_END = 1;
      var Z_NEED_DICT = 2;
      var Z_STREAM_ERROR = -2;
      var Z_DATA_ERROR = -3;
      var Z_MEM_ERROR = -4;
      var Z_BUF_ERROR = -5;
      var Z_DEFLATED = 8;
      var HEAD = 1;
      var FLAGS = 2;
      var TIME = 3;
      var OS = 4;
      var EXLEN = 5;
      var EXTRA = 6;
      var NAME = 7;
      var COMMENT = 8;
      var HCRC = 9;
      var DICTID = 10;
      var DICT = 11;
      var TYPE = 12;
      var TYPEDO = 13;
      var STORED = 14;
      var COPY_ = 15;
      var COPY = 16;
      var TABLE = 17;
      var LENLENS = 18;
      var CODELENS = 19;
      var LEN_ = 20;
      var LEN = 21;
      var LENEXT = 22;
      var DIST = 23;
      var DISTEXT = 24;
      var MATCH = 25;
      var LIT = 26;
      var CHECK = 27;
      var LENGTH = 28;
      var DONE = 29;
      var BAD = 30;
      var MEM = 31;
      var SYNC = 32;
      var ENOUGH_LENS = 852;
      var ENOUGH_DISTS = 592;
      var MAX_WBITS = 15;
      var DEF_WBITS = MAX_WBITS;
      function zswap32(q) {
        return (q >>> 24 & 255) + (q >>> 8 & 65280) + ((q & 65280) << 8) + ((q & 255) << 24);
      }
      function InflateState() {
        this.mode = 0;
        this.last = false;
        this.wrap = 0;
        this.havedict = false;
        this.flags = 0;
        this.dmax = 0;
        this.check = 0;
        this.total = 0;
        this.head = null;
        this.wbits = 0;
        this.wsize = 0;
        this.whave = 0;
        this.wnext = 0;
        this.window = null;
        this.hold = 0;
        this.bits = 0;
        this.length = 0;
        this.offset = 0;
        this.extra = 0;
        this.lencode = null;
        this.distcode = null;
        this.lenbits = 0;
        this.distbits = 0;
        this.ncode = 0;
        this.nlen = 0;
        this.ndist = 0;
        this.have = 0;
        this.next = null;
        this.lens = new utils.Buf16(320);
        this.work = new utils.Buf16(288);
        this.lendyn = null;
        this.distdyn = null;
        this.sane = 0;
        this.back = 0;
        this.was = 0;
      }
      function inflateResetKeep(strm) {
        var state;
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        state = strm.state;
        strm.total_in = strm.total_out = state.total = 0;
        strm.msg = "";
        if (state.wrap) {
          strm.adler = state.wrap & 1;
        }
        state.mode = HEAD;
        state.last = 0;
        state.havedict = 0;
        state.dmax = 32768;
        state.head = null;
        state.hold = 0;
        state.bits = 0;
        state.lencode = state.lendyn = new utils.Buf32(ENOUGH_LENS);
        state.distcode = state.distdyn = new utils.Buf32(ENOUGH_DISTS);
        state.sane = 1;
        state.back = -1;
        return Z_OK;
      }
      function inflateReset(strm) {
        var state;
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        state = strm.state;
        state.wsize = 0;
        state.whave = 0;
        state.wnext = 0;
        return inflateResetKeep(strm);
      }
      function inflateReset2(strm, windowBits) {
        var wrap;
        var state;
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        state = strm.state;
        if (windowBits < 0) {
          wrap = 0;
          windowBits = -windowBits;
        } else {
          wrap = (windowBits >> 4) + 1;
          if (windowBits < 48) {
            windowBits &= 15;
          }
        }
        if (windowBits && (windowBits < 8 || windowBits > 15)) {
          return Z_STREAM_ERROR;
        }
        if (state.window !== null && state.wbits !== windowBits) {
          state.window = null;
        }
        state.wrap = wrap;
        state.wbits = windowBits;
        return inflateReset(strm);
      }
      function inflateInit2(strm, windowBits) {
        var ret;
        var state;
        if (!strm) {
          return Z_STREAM_ERROR;
        }
        state = new InflateState();
        strm.state = state;
        state.window = null;
        ret = inflateReset2(strm, windowBits);
        if (ret !== Z_OK) {
          strm.state = null;
        }
        return ret;
      }
      function inflateInit(strm) {
        return inflateInit2(strm, DEF_WBITS);
      }
      var virgin = true;
      var lenfix;
      var distfix;
      function fixedtables(state) {
        if (virgin) {
          var sym;
          lenfix = new utils.Buf32(512);
          distfix = new utils.Buf32(32);
          sym = 0;
          while (sym < 144) {
            state.lens[sym++] = 8;
          }
          while (sym < 256) {
            state.lens[sym++] = 9;
          }
          while (sym < 280) {
            state.lens[sym++] = 7;
          }
          while (sym < 288) {
            state.lens[sym++] = 8;
          }
          inflate_table(LENS, state.lens, 0, 288, lenfix, 0, state.work, { bits: 9 });
          sym = 0;
          while (sym < 32) {
            state.lens[sym++] = 5;
          }
          inflate_table(DISTS, state.lens, 0, 32, distfix, 0, state.work, { bits: 5 });
          virgin = false;
        }
        state.lencode = lenfix;
        state.lenbits = 9;
        state.distcode = distfix;
        state.distbits = 5;
      }
      function updatewindow(strm, src, end, copy) {
        var dist;
        var state = strm.state;
        if (state.window === null) {
          state.wsize = 1 << state.wbits;
          state.wnext = 0;
          state.whave = 0;
          state.window = new utils.Buf8(state.wsize);
        }
        if (copy >= state.wsize) {
          utils.arraySet(state.window, src, end - state.wsize, state.wsize, 0);
          state.wnext = 0;
          state.whave = state.wsize;
        } else {
          dist = state.wsize - state.wnext;
          if (dist > copy) {
            dist = copy;
          }
          utils.arraySet(state.window, src, end - copy, dist, state.wnext);
          copy -= dist;
          if (copy) {
            utils.arraySet(state.window, src, end - copy, copy, 0);
            state.wnext = copy;
            state.whave = state.wsize;
          } else {
            state.wnext += dist;
            if (state.wnext === state.wsize) {
              state.wnext = 0;
            }
            if (state.whave < state.wsize) {
              state.whave += dist;
            }
          }
        }
        return 0;
      }
      function inflate(strm, flush) {
        var state;
        var input, output;
        var next;
        var put;
        var have, left;
        var hold;
        var bits;
        var _in, _out;
        var copy;
        var from;
        var from_source;
        var here = 0;
        var here_bits, here_op, here_val;
        var last_bits, last_op, last_val;
        var len;
        var ret;
        var hbuf = new utils.Buf8(4);
        var opts;
        var n;
        var order = (
          /* permutation of code lengths */
          [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        );
        if (!strm || !strm.state || !strm.output || !strm.input && strm.avail_in !== 0) {
          return Z_STREAM_ERROR;
        }
        state = strm.state;
        if (state.mode === TYPE) {
          state.mode = TYPEDO;
        }
        put = strm.next_out;
        output = strm.output;
        left = strm.avail_out;
        next = strm.next_in;
        input = strm.input;
        have = strm.avail_in;
        hold = state.hold;
        bits = state.bits;
        _in = have;
        _out = left;
        ret = Z_OK;
        inf_leave:
          for (; ; ) {
            switch (state.mode) {
              case HEAD:
                if (state.wrap === 0) {
                  state.mode = TYPEDO;
                  break;
                }
                while (bits < 16) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                if (state.wrap & 2 && hold === 35615) {
                  state.check = 0;
                  hbuf[0] = hold & 255;
                  hbuf[1] = hold >>> 8 & 255;
                  state.check = crc32(state.check, hbuf, 2, 0);
                  hold = 0;
                  bits = 0;
                  state.mode = FLAGS;
                  break;
                }
                state.flags = 0;
                if (state.head) {
                  state.head.done = false;
                }
                if (!(state.wrap & 1) || /* check if zlib header allowed */
                (((hold & 255) << 8) + (hold >> 8)) % 31) {
                  strm.msg = "incorrect header check";
                  state.mode = BAD;
                  break;
                }
                if ((hold & 15) !== Z_DEFLATED) {
                  strm.msg = "unknown compression method";
                  state.mode = BAD;
                  break;
                }
                hold >>>= 4;
                bits -= 4;
                len = (hold & 15) + 8;
                if (state.wbits === 0) {
                  state.wbits = len;
                } else if (len > state.wbits) {
                  strm.msg = "invalid window size";
                  state.mode = BAD;
                  break;
                }
                state.dmax = 1 << len;
                strm.adler = state.check = 1;
                state.mode = hold & 512 ? DICTID : TYPE;
                hold = 0;
                bits = 0;
                break;
              case FLAGS:
                while (bits < 16) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                state.flags = hold;
                if ((state.flags & 255) !== Z_DEFLATED) {
                  strm.msg = "unknown compression method";
                  state.mode = BAD;
                  break;
                }
                if (state.flags & 57344) {
                  strm.msg = "unknown header flags set";
                  state.mode = BAD;
                  break;
                }
                if (state.head) {
                  state.head.text = hold >> 8 & 1;
                }
                if (state.flags & 512) {
                  hbuf[0] = hold & 255;
                  hbuf[1] = hold >>> 8 & 255;
                  state.check = crc32(state.check, hbuf, 2, 0);
                }
                hold = 0;
                bits = 0;
                state.mode = TIME;
              /* falls through */
              case TIME:
                while (bits < 32) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                if (state.head) {
                  state.head.time = hold;
                }
                if (state.flags & 512) {
                  hbuf[0] = hold & 255;
                  hbuf[1] = hold >>> 8 & 255;
                  hbuf[2] = hold >>> 16 & 255;
                  hbuf[3] = hold >>> 24 & 255;
                  state.check = crc32(state.check, hbuf, 4, 0);
                }
                hold = 0;
                bits = 0;
                state.mode = OS;
              /* falls through */
              case OS:
                while (bits < 16) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                if (state.head) {
                  state.head.xflags = hold & 255;
                  state.head.os = hold >> 8;
                }
                if (state.flags & 512) {
                  hbuf[0] = hold & 255;
                  hbuf[1] = hold >>> 8 & 255;
                  state.check = crc32(state.check, hbuf, 2, 0);
                }
                hold = 0;
                bits = 0;
                state.mode = EXLEN;
              /* falls through */
              case EXLEN:
                if (state.flags & 1024) {
                  while (bits < 16) {
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  state.length = hold;
                  if (state.head) {
                    state.head.extra_len = hold;
                  }
                  if (state.flags & 512) {
                    hbuf[0] = hold & 255;
                    hbuf[1] = hold >>> 8 & 255;
                    state.check = crc32(state.check, hbuf, 2, 0);
                  }
                  hold = 0;
                  bits = 0;
                } else if (state.head) {
                  state.head.extra = null;
                }
                state.mode = EXTRA;
              /* falls through */
              case EXTRA:
                if (state.flags & 1024) {
                  copy = state.length;
                  if (copy > have) {
                    copy = have;
                  }
                  if (copy) {
                    if (state.head) {
                      len = state.head.extra_len - state.length;
                      if (!state.head.extra) {
                        state.head.extra = new Array(state.head.extra_len);
                      }
                      utils.arraySet(
                        state.head.extra,
                        input,
                        next,
                        // extra field is limited to 65536 bytes
                        // - no need for additional size check
                        copy,
                        /*len + copy > state.head.extra_max - len ? state.head.extra_max : copy,*/
                        len
                      );
                    }
                    if (state.flags & 512) {
                      state.check = crc32(state.check, input, copy, next);
                    }
                    have -= copy;
                    next += copy;
                    state.length -= copy;
                  }
                  if (state.length) {
                    break inf_leave;
                  }
                }
                state.length = 0;
                state.mode = NAME;
              /* falls through */
              case NAME:
                if (state.flags & 2048) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  copy = 0;
                  do {
                    len = input[next + copy++];
                    if (state.head && len && state.length < 65536) {
                      state.head.name += String.fromCharCode(len);
                    }
                  } while (len && copy < have);
                  if (state.flags & 512) {
                    state.check = crc32(state.check, input, copy, next);
                  }
                  have -= copy;
                  next += copy;
                  if (len) {
                    break inf_leave;
                  }
                } else if (state.head) {
                  state.head.name = null;
                }
                state.length = 0;
                state.mode = COMMENT;
              /* falls through */
              case COMMENT:
                if (state.flags & 4096) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  copy = 0;
                  do {
                    len = input[next + copy++];
                    if (state.head && len && state.length < 65536) {
                      state.head.comment += String.fromCharCode(len);
                    }
                  } while (len && copy < have);
                  if (state.flags & 512) {
                    state.check = crc32(state.check, input, copy, next);
                  }
                  have -= copy;
                  next += copy;
                  if (len) {
                    break inf_leave;
                  }
                } else if (state.head) {
                  state.head.comment = null;
                }
                state.mode = HCRC;
              /* falls through */
              case HCRC:
                if (state.flags & 512) {
                  while (bits < 16) {
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  if (hold !== (state.check & 65535)) {
                    strm.msg = "header crc mismatch";
                    state.mode = BAD;
                    break;
                  }
                  hold = 0;
                  bits = 0;
                }
                if (state.head) {
                  state.head.hcrc = state.flags >> 9 & 1;
                  state.head.done = true;
                }
                strm.adler = state.check = 0;
                state.mode = TYPE;
                break;
              case DICTID:
                while (bits < 32) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                strm.adler = state.check = zswap32(hold);
                hold = 0;
                bits = 0;
                state.mode = DICT;
              /* falls through */
              case DICT:
                if (state.havedict === 0) {
                  strm.next_out = put;
                  strm.avail_out = left;
                  strm.next_in = next;
                  strm.avail_in = have;
                  state.hold = hold;
                  state.bits = bits;
                  return Z_NEED_DICT;
                }
                strm.adler = state.check = 1;
                state.mode = TYPE;
              /* falls through */
              case TYPE:
                if (flush === Z_BLOCK || flush === Z_TREES) {
                  break inf_leave;
                }
              /* falls through */
              case TYPEDO:
                if (state.last) {
                  hold >>>= bits & 7;
                  bits -= bits & 7;
                  state.mode = CHECK;
                  break;
                }
                while (bits < 3) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                state.last = hold & 1;
                hold >>>= 1;
                bits -= 1;
                switch (hold & 3) {
                  case 0:
                    state.mode = STORED;
                    break;
                  case 1:
                    fixedtables(state);
                    state.mode = LEN_;
                    if (flush === Z_TREES) {
                      hold >>>= 2;
                      bits -= 2;
                      break inf_leave;
                    }
                    break;
                  case 2:
                    state.mode = TABLE;
                    break;
                  case 3:
                    strm.msg = "invalid block type";
                    state.mode = BAD;
                }
                hold >>>= 2;
                bits -= 2;
                break;
              case STORED:
                hold >>>= bits & 7;
                bits -= bits & 7;
                while (bits < 32) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                if ((hold & 65535) !== (hold >>> 16 ^ 65535)) {
                  strm.msg = "invalid stored block lengths";
                  state.mode = BAD;
                  break;
                }
                state.length = hold & 65535;
                hold = 0;
                bits = 0;
                state.mode = COPY_;
                if (flush === Z_TREES) {
                  break inf_leave;
                }
              /* falls through */
              case COPY_:
                state.mode = COPY;
              /* falls through */
              case COPY:
                copy = state.length;
                if (copy) {
                  if (copy > have) {
                    copy = have;
                  }
                  if (copy > left) {
                    copy = left;
                  }
                  if (copy === 0) {
                    break inf_leave;
                  }
                  utils.arraySet(output, input, next, copy, put);
                  have -= copy;
                  next += copy;
                  left -= copy;
                  put += copy;
                  state.length -= copy;
                  break;
                }
                state.mode = TYPE;
                break;
              case TABLE:
                while (bits < 14) {
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                state.nlen = (hold & 31) + 257;
                hold >>>= 5;
                bits -= 5;
                state.ndist = (hold & 31) + 1;
                hold >>>= 5;
                bits -= 5;
                state.ncode = (hold & 15) + 4;
                hold >>>= 4;
                bits -= 4;
                if (state.nlen > 286 || state.ndist > 30) {
                  strm.msg = "too many length or distance symbols";
                  state.mode = BAD;
                  break;
                }
                state.have = 0;
                state.mode = LENLENS;
              /* falls through */
              case LENLENS:
                while (state.have < state.ncode) {
                  while (bits < 3) {
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  state.lens[order[state.have++]] = hold & 7;
                  hold >>>= 3;
                  bits -= 3;
                }
                while (state.have < 19) {
                  state.lens[order[state.have++]] = 0;
                }
                state.lencode = state.lendyn;
                state.lenbits = 7;
                opts = { bits: state.lenbits };
                ret = inflate_table(CODES, state.lens, 0, 19, state.lencode, 0, state.work, opts);
                state.lenbits = opts.bits;
                if (ret) {
                  strm.msg = "invalid code lengths set";
                  state.mode = BAD;
                  break;
                }
                state.have = 0;
                state.mode = CODELENS;
              /* falls through */
              case CODELENS:
                while (state.have < state.nlen + state.ndist) {
                  for (; ; ) {
                    here = state.lencode[hold & (1 << state.lenbits) - 1];
                    here_bits = here >>> 24;
                    here_op = here >>> 16 & 255;
                    here_val = here & 65535;
                    if (here_bits <= bits) {
                      break;
                    }
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  if (here_val < 16) {
                    hold >>>= here_bits;
                    bits -= here_bits;
                    state.lens[state.have++] = here_val;
                  } else {
                    if (here_val === 16) {
                      n = here_bits + 2;
                      while (bits < n) {
                        if (have === 0) {
                          break inf_leave;
                        }
                        have--;
                        hold += input[next++] << bits;
                        bits += 8;
                      }
                      hold >>>= here_bits;
                      bits -= here_bits;
                      if (state.have === 0) {
                        strm.msg = "invalid bit length repeat";
                        state.mode = BAD;
                        break;
                      }
                      len = state.lens[state.have - 1];
                      copy = 3 + (hold & 3);
                      hold >>>= 2;
                      bits -= 2;
                    } else if (here_val === 17) {
                      n = here_bits + 3;
                      while (bits < n) {
                        if (have === 0) {
                          break inf_leave;
                        }
                        have--;
                        hold += input[next++] << bits;
                        bits += 8;
                      }
                      hold >>>= here_bits;
                      bits -= here_bits;
                      len = 0;
                      copy = 3 + (hold & 7);
                      hold >>>= 3;
                      bits -= 3;
                    } else {
                      n = here_bits + 7;
                      while (bits < n) {
                        if (have === 0) {
                          break inf_leave;
                        }
                        have--;
                        hold += input[next++] << bits;
                        bits += 8;
                      }
                      hold >>>= here_bits;
                      bits -= here_bits;
                      len = 0;
                      copy = 11 + (hold & 127);
                      hold >>>= 7;
                      bits -= 7;
                    }
                    if (state.have + copy > state.nlen + state.ndist) {
                      strm.msg = "invalid bit length repeat";
                      state.mode = BAD;
                      break;
                    }
                    while (copy--) {
                      state.lens[state.have++] = len;
                    }
                  }
                }
                if (state.mode === BAD) {
                  break;
                }
                if (state.lens[256] === 0) {
                  strm.msg = "invalid code -- missing end-of-block";
                  state.mode = BAD;
                  break;
                }
                state.lenbits = 9;
                opts = { bits: state.lenbits };
                ret = inflate_table(LENS, state.lens, 0, state.nlen, state.lencode, 0, state.work, opts);
                state.lenbits = opts.bits;
                if (ret) {
                  strm.msg = "invalid literal/lengths set";
                  state.mode = BAD;
                  break;
                }
                state.distbits = 6;
                state.distcode = state.distdyn;
                opts = { bits: state.distbits };
                ret = inflate_table(DISTS, state.lens, state.nlen, state.ndist, state.distcode, 0, state.work, opts);
                state.distbits = opts.bits;
                if (ret) {
                  strm.msg = "invalid distances set";
                  state.mode = BAD;
                  break;
                }
                state.mode = LEN_;
                if (flush === Z_TREES) {
                  break inf_leave;
                }
              /* falls through */
              case LEN_:
                state.mode = LEN;
              /* falls through */
              case LEN:
                if (have >= 6 && left >= 258) {
                  strm.next_out = put;
                  strm.avail_out = left;
                  strm.next_in = next;
                  strm.avail_in = have;
                  state.hold = hold;
                  state.bits = bits;
                  inflate_fast(strm, _out);
                  put = strm.next_out;
                  output = strm.output;
                  left = strm.avail_out;
                  next = strm.next_in;
                  input = strm.input;
                  have = strm.avail_in;
                  hold = state.hold;
                  bits = state.bits;
                  if (state.mode === TYPE) {
                    state.back = -1;
                  }
                  break;
                }
                state.back = 0;
                for (; ; ) {
                  here = state.lencode[hold & (1 << state.lenbits) - 1];
                  here_bits = here >>> 24;
                  here_op = here >>> 16 & 255;
                  here_val = here & 65535;
                  if (here_bits <= bits) {
                    break;
                  }
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                if (here_op && (here_op & 240) === 0) {
                  last_bits = here_bits;
                  last_op = here_op;
                  last_val = here_val;
                  for (; ; ) {
                    here = state.lencode[last_val + ((hold & (1 << last_bits + last_op) - 1) >> last_bits)];
                    here_bits = here >>> 24;
                    here_op = here >>> 16 & 255;
                    here_val = here & 65535;
                    if (last_bits + here_bits <= bits) {
                      break;
                    }
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  hold >>>= last_bits;
                  bits -= last_bits;
                  state.back += last_bits;
                }
                hold >>>= here_bits;
                bits -= here_bits;
                state.back += here_bits;
                state.length = here_val;
                if (here_op === 0) {
                  state.mode = LIT;
                  break;
                }
                if (here_op & 32) {
                  state.back = -1;
                  state.mode = TYPE;
                  break;
                }
                if (here_op & 64) {
                  strm.msg = "invalid literal/length code";
                  state.mode = BAD;
                  break;
                }
                state.extra = here_op & 15;
                state.mode = LENEXT;
              /* falls through */
              case LENEXT:
                if (state.extra) {
                  n = state.extra;
                  while (bits < n) {
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  state.length += hold & (1 << state.extra) - 1;
                  hold >>>= state.extra;
                  bits -= state.extra;
                  state.back += state.extra;
                }
                state.was = state.length;
                state.mode = DIST;
              /* falls through */
              case DIST:
                for (; ; ) {
                  here = state.distcode[hold & (1 << state.distbits) - 1];
                  here_bits = here >>> 24;
                  here_op = here >>> 16 & 255;
                  here_val = here & 65535;
                  if (here_bits <= bits) {
                    break;
                  }
                  if (have === 0) {
                    break inf_leave;
                  }
                  have--;
                  hold += input[next++] << bits;
                  bits += 8;
                }
                if ((here_op & 240) === 0) {
                  last_bits = here_bits;
                  last_op = here_op;
                  last_val = here_val;
                  for (; ; ) {
                    here = state.distcode[last_val + ((hold & (1 << last_bits + last_op) - 1) >> last_bits)];
                    here_bits = here >>> 24;
                    here_op = here >>> 16 & 255;
                    here_val = here & 65535;
                    if (last_bits + here_bits <= bits) {
                      break;
                    }
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  hold >>>= last_bits;
                  bits -= last_bits;
                  state.back += last_bits;
                }
                hold >>>= here_bits;
                bits -= here_bits;
                state.back += here_bits;
                if (here_op & 64) {
                  strm.msg = "invalid distance code";
                  state.mode = BAD;
                  break;
                }
                state.offset = here_val;
                state.extra = here_op & 15;
                state.mode = DISTEXT;
              /* falls through */
              case DISTEXT:
                if (state.extra) {
                  n = state.extra;
                  while (bits < n) {
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  state.offset += hold & (1 << state.extra) - 1;
                  hold >>>= state.extra;
                  bits -= state.extra;
                  state.back += state.extra;
                }
                if (state.offset > state.dmax) {
                  strm.msg = "invalid distance too far back";
                  state.mode = BAD;
                  break;
                }
                state.mode = MATCH;
              /* falls through */
              case MATCH:
                if (left === 0) {
                  break inf_leave;
                }
                copy = _out - left;
                if (state.offset > copy) {
                  copy = state.offset - copy;
                  if (copy > state.whave) {
                    if (state.sane) {
                      strm.msg = "invalid distance too far back";
                      state.mode = BAD;
                      break;
                    }
                  }
                  if (copy > state.wnext) {
                    copy -= state.wnext;
                    from = state.wsize - copy;
                  } else {
                    from = state.wnext - copy;
                  }
                  if (copy > state.length) {
                    copy = state.length;
                  }
                  from_source = state.window;
                } else {
                  from_source = output;
                  from = put - state.offset;
                  copy = state.length;
                }
                if (copy > left) {
                  copy = left;
                }
                left -= copy;
                state.length -= copy;
                do {
                  output[put++] = from_source[from++];
                } while (--copy);
                if (state.length === 0) {
                  state.mode = LEN;
                }
                break;
              case LIT:
                if (left === 0) {
                  break inf_leave;
                }
                output[put++] = state.length;
                left--;
                state.mode = LEN;
                break;
              case CHECK:
                if (state.wrap) {
                  while (bits < 32) {
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold |= input[next++] << bits;
                    bits += 8;
                  }
                  _out -= left;
                  strm.total_out += _out;
                  state.total += _out;
                  if (_out) {
                    strm.adler = state.check = /*UPDATE(state.check, put - _out, _out);*/
                    state.flags ? crc32(state.check, output, _out, put - _out) : adler32(state.check, output, _out, put - _out);
                  }
                  _out = left;
                  if ((state.flags ? hold : zswap32(hold)) !== state.check) {
                    strm.msg = "incorrect data check";
                    state.mode = BAD;
                    break;
                  }
                  hold = 0;
                  bits = 0;
                }
                state.mode = LENGTH;
              /* falls through */
              case LENGTH:
                if (state.wrap && state.flags) {
                  while (bits < 32) {
                    if (have === 0) {
                      break inf_leave;
                    }
                    have--;
                    hold += input[next++] << bits;
                    bits += 8;
                  }
                  if (hold !== (state.total & 4294967295)) {
                    strm.msg = "incorrect length check";
                    state.mode = BAD;
                    break;
                  }
                  hold = 0;
                  bits = 0;
                }
                state.mode = DONE;
              /* falls through */
              case DONE:
                ret = Z_STREAM_END;
                break inf_leave;
              case BAD:
                ret = Z_DATA_ERROR;
                break inf_leave;
              case MEM:
                return Z_MEM_ERROR;
              case SYNC:
              /* falls through */
              default:
                return Z_STREAM_ERROR;
            }
          }
        strm.next_out = put;
        strm.avail_out = left;
        strm.next_in = next;
        strm.avail_in = have;
        state.hold = hold;
        state.bits = bits;
        if (state.wsize || _out !== strm.avail_out && state.mode < BAD && (state.mode < CHECK || flush !== Z_FINISH)) {
          if (updatewindow(strm, strm.output, strm.next_out, _out - strm.avail_out)) {
            state.mode = MEM;
            return Z_MEM_ERROR;
          }
        }
        _in -= strm.avail_in;
        _out -= strm.avail_out;
        strm.total_in += _in;
        strm.total_out += _out;
        state.total += _out;
        if (state.wrap && _out) {
          strm.adler = state.check = /*UPDATE(state.check, strm.next_out - _out, _out);*/
          state.flags ? crc32(state.check, output, _out, strm.next_out - _out) : adler32(state.check, output, _out, strm.next_out - _out);
        }
        strm.data_type = state.bits + (state.last ? 64 : 0) + (state.mode === TYPE ? 128 : 0) + (state.mode === LEN_ || state.mode === COPY_ ? 256 : 0);
        if ((_in === 0 && _out === 0 || flush === Z_FINISH) && ret === Z_OK) {
          ret = Z_BUF_ERROR;
        }
        return ret;
      }
      function inflateEnd(strm) {
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        var state = strm.state;
        if (state.window) {
          state.window = null;
        }
        strm.state = null;
        return Z_OK;
      }
      function inflateGetHeader(strm, head) {
        var state;
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        state = strm.state;
        if ((state.wrap & 2) === 0) {
          return Z_STREAM_ERROR;
        }
        state.head = head;
        head.done = false;
        return Z_OK;
      }
      function inflateSetDictionary(strm, dictionary) {
        var dictLength = dictionary.length;
        var state;
        var dictid;
        var ret;
        if (!strm || !strm.state) {
          return Z_STREAM_ERROR;
        }
        state = strm.state;
        if (state.wrap !== 0 && state.mode !== DICT) {
          return Z_STREAM_ERROR;
        }
        if (state.mode === DICT) {
          dictid = 1;
          dictid = adler32(dictid, dictionary, dictLength, 0);
          if (dictid !== state.check) {
            return Z_DATA_ERROR;
          }
        }
        ret = updatewindow(strm, dictionary, dictLength, dictLength);
        if (ret) {
          state.mode = MEM;
          return Z_MEM_ERROR;
        }
        state.havedict = 1;
        return Z_OK;
      }
      exports.inflateReset = inflateReset;
      exports.inflateReset2 = inflateReset2;
      exports.inflateResetKeep = inflateResetKeep;
      exports.inflateInit = inflateInit;
      exports.inflateInit2 = inflateInit2;
      exports.inflate = inflate;
      exports.inflateEnd = inflateEnd;
      exports.inflateGetHeader = inflateGetHeader;
      exports.inflateSetDictionary = inflateSetDictionary;
      exports.inflateInfo = "pako inflate (from Nodeca project)";
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/constants.js
  var require_constants = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/constants.js"(exports, module) {
      "use strict";
      init_globals();
      module.exports = {
        /* Allowed flush values; see deflate() and inflate() below for details */
        Z_NO_FLUSH: 0,
        Z_PARTIAL_FLUSH: 1,
        Z_SYNC_FLUSH: 2,
        Z_FULL_FLUSH: 3,
        Z_FINISH: 4,
        Z_BLOCK: 5,
        Z_TREES: 6,
        /* Return codes for the compression/decompression functions. Negative values
        * are errors, positive values are used for special but normal events.
        */
        Z_OK: 0,
        Z_STREAM_END: 1,
        Z_NEED_DICT: 2,
        Z_ERRNO: -1,
        Z_STREAM_ERROR: -2,
        Z_DATA_ERROR: -3,
        //Z_MEM_ERROR:     -4,
        Z_BUF_ERROR: -5,
        //Z_VERSION_ERROR: -6,
        /* compression levels */
        Z_NO_COMPRESSION: 0,
        Z_BEST_SPEED: 1,
        Z_BEST_COMPRESSION: 9,
        Z_DEFAULT_COMPRESSION: -1,
        Z_FILTERED: 1,
        Z_HUFFMAN_ONLY: 2,
        Z_RLE: 3,
        Z_FIXED: 4,
        Z_DEFAULT_STRATEGY: 0,
        /* Possible values of the data_type field (though see inflate()) */
        Z_BINARY: 0,
        Z_TEXT: 1,
        //Z_ASCII:                1, // = Z_TEXT (deprecated)
        Z_UNKNOWN: 2,
        /* The deflate compression method */
        Z_DEFLATED: 8
        //Z_NULL:                 null // Use -1 or null inline, depending on var type
      };
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/zlib/gzheader.js
  var require_gzheader = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/zlib/gzheader.js"(exports, module) {
      "use strict";
      init_globals();
      function GZheader() {
        this.text = 0;
        this.time = 0;
        this.xflags = 0;
        this.os = 0;
        this.extra = null;
        this.extra_len = 0;
        this.name = "";
        this.comment = "";
        this.hcrc = 0;
        this.done = false;
      }
      module.exports = GZheader;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/lib/inflate.js
  var require_inflate2 = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/lib/inflate.js"(exports) {
      "use strict";
      init_globals();
      var zlib_inflate = require_inflate();
      var utils = require_common();
      var strings = require_strings();
      var c = require_constants();
      var msg = require_messages();
      var ZStream = require_zstream();
      var GZheader = require_gzheader();
      var toString = Object.prototype.toString;
      function Inflate(options) {
        if (!(this instanceof Inflate)) return new Inflate(options);
        this.options = utils.assign({
          chunkSize: 16384,
          windowBits: 0,
          to: ""
        }, options || {});
        var opt = this.options;
        if (opt.raw && opt.windowBits >= 0 && opt.windowBits < 16) {
          opt.windowBits = -opt.windowBits;
          if (opt.windowBits === 0) {
            opt.windowBits = -15;
          }
        }
        if (opt.windowBits >= 0 && opt.windowBits < 16 && !(options && options.windowBits)) {
          opt.windowBits += 32;
        }
        if (opt.windowBits > 15 && opt.windowBits < 48) {
          if ((opt.windowBits & 15) === 0) {
            opt.windowBits |= 15;
          }
        }
        this.err = 0;
        this.msg = "";
        this.ended = false;
        this.chunks = [];
        this.strm = new ZStream();
        this.strm.avail_out = 0;
        var status = zlib_inflate.inflateInit2(
          this.strm,
          opt.windowBits
        );
        if (status !== c.Z_OK) {
          throw new Error(msg[status]);
        }
        this.header = new GZheader();
        zlib_inflate.inflateGetHeader(this.strm, this.header);
        if (opt.dictionary) {
          if (typeof opt.dictionary === "string") {
            opt.dictionary = strings.string2buf(opt.dictionary);
          } else if (toString.call(opt.dictionary) === "[object ArrayBuffer]") {
            opt.dictionary = new Uint8Array(opt.dictionary);
          }
          if (opt.raw) {
            status = zlib_inflate.inflateSetDictionary(this.strm, opt.dictionary);
            if (status !== c.Z_OK) {
              throw new Error(msg[status]);
            }
          }
        }
      }
      Inflate.prototype.push = function(data, mode) {
        var strm = this.strm;
        var chunkSize = this.options.chunkSize;
        var dictionary = this.options.dictionary;
        var status, _mode;
        var next_out_utf8, tail, utf8str;
        var allowBufError = false;
        if (this.ended) {
          return false;
        }
        _mode = mode === ~~mode ? mode : mode === true ? c.Z_FINISH : c.Z_NO_FLUSH;
        if (typeof data === "string") {
          strm.input = strings.binstring2buf(data);
        } else if (toString.call(data) === "[object ArrayBuffer]") {
          strm.input = new Uint8Array(data);
        } else {
          strm.input = data;
        }
        strm.next_in = 0;
        strm.avail_in = strm.input.length;
        do {
          if (strm.avail_out === 0) {
            strm.output = new utils.Buf8(chunkSize);
            strm.next_out = 0;
            strm.avail_out = chunkSize;
          }
          status = zlib_inflate.inflate(strm, c.Z_NO_FLUSH);
          if (status === c.Z_NEED_DICT && dictionary) {
            status = zlib_inflate.inflateSetDictionary(this.strm, dictionary);
          }
          if (status === c.Z_BUF_ERROR && allowBufError === true) {
            status = c.Z_OK;
            allowBufError = false;
          }
          if (status !== c.Z_STREAM_END && status !== c.Z_OK) {
            this.onEnd(status);
            this.ended = true;
            return false;
          }
          if (strm.next_out) {
            if (strm.avail_out === 0 || status === c.Z_STREAM_END || strm.avail_in === 0 && (_mode === c.Z_FINISH || _mode === c.Z_SYNC_FLUSH)) {
              if (this.options.to === "string") {
                next_out_utf8 = strings.utf8border(strm.output, strm.next_out);
                tail = strm.next_out - next_out_utf8;
                utf8str = strings.buf2string(strm.output, next_out_utf8);
                strm.next_out = tail;
                strm.avail_out = chunkSize - tail;
                if (tail) {
                  utils.arraySet(strm.output, strm.output, next_out_utf8, tail, 0);
                }
                this.onData(utf8str);
              } else {
                this.onData(utils.shrinkBuf(strm.output, strm.next_out));
              }
            }
          }
          if (strm.avail_in === 0 && strm.avail_out === 0) {
            allowBufError = true;
          }
        } while ((strm.avail_in > 0 || strm.avail_out === 0) && status !== c.Z_STREAM_END);
        if (status === c.Z_STREAM_END) {
          _mode = c.Z_FINISH;
        }
        if (_mode === c.Z_FINISH) {
          status = zlib_inflate.inflateEnd(this.strm);
          this.onEnd(status);
          this.ended = true;
          return status === c.Z_OK;
        }
        if (_mode === c.Z_SYNC_FLUSH) {
          this.onEnd(c.Z_OK);
          strm.avail_out = 0;
          return true;
        }
        return true;
      };
      Inflate.prototype.onData = function(chunk) {
        this.chunks.push(chunk);
      };
      Inflate.prototype.onEnd = function(status) {
        if (status === c.Z_OK) {
          if (this.options.to === "string") {
            this.result = this.chunks.join("");
          } else {
            this.result = utils.flattenChunks(this.chunks);
          }
        }
        this.chunks = [];
        this.err = status;
        this.msg = this.strm.msg;
      };
      function inflate(input, options) {
        var inflator = new Inflate(options);
        inflator.push(input, true);
        if (inflator.err) {
          throw inflator.msg || msg[inflator.err];
        }
        return inflator.result;
      }
      function inflateRaw(input, options) {
        options = options || {};
        options.raw = true;
        return inflate(input, options);
      }
      exports.Inflate = Inflate;
      exports.inflate = inflate;
      exports.inflateRaw = inflateRaw;
      exports.ungzip = inflate;
    }
  });

  // ../../../../../opt/npm-tools/node_modules/pako/index.js
  var require_pako = __commonJS({
    "../../../../../opt/npm-tools/node_modules/pako/index.js"(exports, module) {
      "use strict";
      init_globals();
      var assign = require_common().assign;
      var deflate = require_deflate2();
      var inflate = require_inflate2();
      var constants = require_constants();
      var pako = {};
      assign(pako, deflate, inflate, constants);
      module.exports = pako;
    }
  });

  // shims/zlib.js
  var require_zlib = __commonJS({
    "shims/zlib.js"(exports, module) {
      "use strict";
      init_globals();
      var pako = require_pako();
      module.exports = {
        inflateRawSync: (b) => Buffer2.from(pako.inflateRaw(b)),
        deflateRawSync: (b) => Buffer2.from(pako.deflateRaw(b)),
        inflateSync: (b) => Buffer2.from(pako.inflate(b)),
        deflateSync: (b) => Buffer2.from(pako.deflate(b))
      };
    }
  });

  // ../../backend/src/services/margImport.js
  var require_margImport = __commonJS({
    "../../backend/src/services/margImport.js"(exports, module) {
      init_globals();
      var fs = require_fs();
      var path = require_path();
      var zlib = require_zlib();
      var db2 = require_db();
      var { r2 } = require_gst();
      var { HttpError: HttpError2, peekNo } = require_misc();
      var { fyRange } = require_fy();
      var { mrpFromName, packFromName } = require_pdfParser();
      var { pinned, byRules, cleanQuery } = require_category();
      var GSTIN_RE = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
      var PAN_RE = /^[A-Z]{5}\d{4}[A-Z]$/;
      var NO_EXPIRY = "2099-12-31";
      var r8 = (n) => Math.round((n + Number.EPSILON) * 1e8) / 1e8;
      var num = (s) => {
        const n = Number(String(s ?? "").trim());
        return Number.isFinite(n) ? n : 0;
      };
      var int = (s) => Math.round(num(s));
      var clean = (s) => String(s ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
      var key = (s) => clean(s).toLowerCase();
      var day = (s) => {
        const m = /^(\d{1,2})-(\d{1,2})-(\d{4})/.exec(String(s ?? "").trim());
        return m ? `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}` : null;
      };
      function readZip(buf) {
        let eocd = -1;
        for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) if (buf.readUInt32LE(i) === 101010256) {
          eocd = i;
          break;
        }
        if (eocd < 0) throw new HttpError2(400, "This is not a zip file.");
        const out = {};
        let p = buf.readUInt32LE(eocd + 16);
        for (let k = 0, n = buf.readUInt16LE(eocd + 10); k < n; k++) {
          if (buf.readUInt32LE(p) !== 33639248) throw new HttpError2(400, "The zip file is damaged.");
          const method = buf.readUInt16LE(p + 10), csize = buf.readUInt32LE(p + 20);
          const nlen = buf.readUInt16LE(p + 28), xlen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32), local = buf.readUInt32LE(p + 42);
          const name = buf.slice(p + 46, p + 46 + nlen).toString("utf8");
          p += 46 + nlen + xlen + clen;
          if (name.endsWith("/") || name.startsWith("__MACOSX/")) continue;
          const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
          const raw = buf.slice(start, start + csize);
          out[name] = method === 0 ? raw : method === 8 ? zlib.inflateRawSync(raw) : null;
        }
        return out;
      }
      function readSource(p) {
        if (!p || !path.isAbsolute(String(p)) || !fs.existsSync(p)) throw new HttpError2(400, "Choose the Marg backup folder or .zip file.");
        const files = {};
        const take = (name, buf) => {
          const b = path.basename(name).toLowerCase();
          if (b.endsWith(".csv") && buf && !(b in files)) files[b] = buf.toString("latin1");
        };
        if (fs.statSync(p).isDirectory()) {
          const walk = (d, depth) => {
            for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
              const f = path.join(d, e.name);
              if (e.isDirectory()) {
                if (depth < 3 && e.name !== "__MACOSX") walk(f, depth + 1);
              } else take(e.name, fs.readFileSync(f));
            }
          };
          walk(p, 0);
        } else {
          const entries = readZip(fs.readFileSync(p));
          for (const n of Object.keys(entries).sort()) take(n, entries[n]);
        }
        for (const need of ["pro.csv", "order.csv", "mdis.csv", "dis.csv"])
          if (!files[need]) throw new HttpError2(400, `This is not a Marg CSV backup: ${need} is missing.`);
        return files;
      }
      function parseCsv(text) {
        const rows = [];
        let row = [], f = "", q = false;
        for (let i = 0; i < text.length; i++) {
          const c = text[i];
          if (q) {
            if (c === '"') {
              if (text[i + 1] === '"') {
                f += '"';
                i++;
              } else q = false;
            } else f += c;
          } else if (c === '"' && f === "") q = true;
          else if (c === ",") {
            row.push(f);
            f = "";
          } else if (c === "\n" || c === "\r") {
            if (c === "\r" && text[i + 1] === "\n") i++;
            row.push(f);
            f = "";
            if (row.length > 1 || row[0] !== "") rows.push(row);
            row = [];
          } else f += c;
        }
        if (f !== "" || row.length) {
          row.push(f);
          if (row.length > 1 || row[0] !== "") rows.push(row);
        }
        if (!rows.length) return [];
        const head = rows[0].map((h) => h.trim().toUpperCase());
        return rows.slice(1).map((r) => {
          const o = {};
          head.forEach((h, i) => {
            if (!(h in o)) o[h] = r[i] === void 0 ? "" : r[i];
          });
          return o;
        });
      }
      var mobileOf = (d) => {
        const x = d.replace(/^(91|0)(?=\d{10}$)/, "");
        return /^[6-9]\d{9}$/.test(x) ? x : null;
      };
      function model(files) {
        const T = (n) => files[n] ? parseCsv(files[n]) : [];
        const pro = T("pro.csv"), order = T("order.csv"), mdis = T("mdis.csv"), dis = T("dis.csv"), gl = T("gledger.csv"), st = T("saletype.csv");
        const cleaning = [], warnings = [];
        const note = (arr, s) => {
          if (!arr.includes(s)) arr.push(s);
        };
        const commodity = {}, company = {};
        for (const r of st) {
          const code = clean(r.SCODE);
          if (!code) continue;
          if (clean(r.SGCODE) === "COMMCD" && !(code in commodity)) {
            const h = clean(r.PARNAM);
            commodity[code] = { hsn: /^\d{4,8}$/.test(h) ? h : null, gst: num(r.IGST) };
          } else if (clean(r.SGCODE) === "ZZZZZZ" && !(code in company)) company[code] = clean(r.SNAME) || clean(r.PARNAM) || null;
        }
        function rateUnit(rate, packs, lp, inner) {
          const marg = Math.max(1, packs[0] || 1);
          if (!(lp > 0) || !(rate > 0)) return marg;
          const cands = [.../* @__PURE__ */ new Set([1, ...packs.filter((p) => p > 0), ...inner.filter((q) => q > 1).map((q) => marg * q)])];
          const off = (d) => Math.abs(Math.log(rate / d / (lp * 1.15)));
          const best = cands.reduce((b, d) => off(d) < off(b) - 1e-9 ? d : b, marg);
          return off(best) <= Math.log(3) ? best : marg;
        }
        function purchaseRate(lp, sale, packs) {
          if (!(lp > 0) || !(sale > 0) || lp <= sale * 3) return r8(lp);
          const off = (d) => Math.abs(Math.log(lp / d / (sale * 0.87)));
          const best = packs.filter((p) => p > 1).reduce((b, d) => b === null || off(d) < off(b) - 1e-9 ? d : b, null);
          return best !== null && off(best) <= Math.log(2) ? r8(lp / best) : r8(lp);
        }
        function byNameMrp(it, packs) {
          const nm = mrpFromName(it.name);
          const incl = it.retail_price * (1 + (it.gst_rate || 0) / 100);
          if (!(nm > 0) || !(incl > nm * 1.02)) return;
          for (const d of [...new Set(packs.filter((p) => p > 1))]) {
            const v = incl / d;
            if (v >= nm * 0.5 && v <= nm * 1.02) {
              it.retail_price = it.wholesale_price = r8(it.retail_price / d);
              if (it.purchase_price > nm) it.purchase_price = r8(it.purchase_price / d);
              return;
            }
          }
        }
        const linePacks = {};
        for (const l of dis) {
          const p = int(l.PACK);
          if (p > 1) (linePacks[clean(l.CODE)] = linePacks[clean(l.CODE)] || /* @__PURE__ */ new Set()).add(p);
        }
        const packCount = {};
        for (const l of dis) if (clean(l.FLG) === "G" && num(l.SFRATE) > 0) {
          const c = clean(l.CODE), p = Math.max(1, int(l.PACK) || 1);
          (packCount[c] = packCount[c] || {})[p] = (packCount[c][p] || 0) + 1;
        }
        const usualPack = (c) => Object.entries(packCount[c] || {}).reduce((b, [p, n]) => !b || n > b[1] || n === b[1] && +p < +b[0] ? [p, n] : b, null);
        const saleRate = {};
        for (const l of dis) if (clean(l.FLG) === "G" && num(l.SFRATE) > 0) {
          const d = day(l.DATE) || "", c = clean(l.CODE), p = Math.max(1, int(l.PACK) || 1);
          if (String(p) !== usualPack(c)[0]) continue;
          const cur = saleRate[c];
          if (!cur || d >= cur.date) saleRate[c] = { date: d, rate: r8(num(l.SFRATE) / p) };
        }
        const batchMrp = {};
        for (const l of dis) {
          const f = clean(l.FLG), b = num(l.BATCH);
          if (f !== "G" && f !== "P" || !(b > 0)) continue;
          if (packCount[clean(l.CODE)] && String(Math.max(1, int(l.PACK) || 1)) !== usualPack(clean(l.CODE))[0]) continue;
          const d = day(l.DATE) || "";
          const cur = batchMrp[clean(l.CODE)];
          if (!cur || d >= cur.date) batchMrp[clean(l.CODE)] = { date: d, mrp: r2(b / Math.max(1, int(l.PACK) || 1)) };
        }
        const items = [], itemByCode = {}, itemByKey = {};
        let skippedItems = 0, mergedItems = 0;
        for (const r of pro) {
          const code = clean(r.CODE);
          let name = clean(r.PRODUCT) || clean(r.BILLNAME);
          if (!code || !name || clean(r.NAME).startsWith("#") || /^product name\b/i.test(name)) {
            skippedItems++;
            continue;
          }
          const pack = packFromName(name) || Math.max(1, int(r.PACK) || 1);
          let k = key(name);
          if (itemByKey[k] && itemByKey[k].pcs_per_box !== pack && clean(r.PACKING)) {
            name = `${name} ${clean(r.PACKING)}`;
            k = key(name);
          }
          if (itemByKey[k]) {
            const ex = itemByKey[k];
            if (ex.rateFromList && saleRate[code]) {
              ex.retail_price = ex.wholesale_price = saleRate[code].rate;
              ex.rateFromList = false;
            }
            itemByCode[code] = ex;
            mergedItems++;
            continue;
          }
          const com = commodity[clean(r.GCODE6)] || {};
          const gst = clean(r.TAXL) === "E" ? 0 : com.gst || num(r.IGST) || 0;
          const sr = saleRate[code];
          const rateA = num(r.RATEA) > 0 ? r8(num(r.RATEA) / (1 + gst / 100) / rateUnit(num(r.RATEA) / (1 + gst / 100), [int(r.PACK), pack], num(r.LPRATE), [...linePacks[code] || []].sort((a, b) => a - b))) : 0;
          const it = {
            code,
            name,
            pcs_per_box: pack,
            gst_rate: gst,
            hsn: com.hsn || null,
            mrp: mrpFromName(name) || (batchMrp[code] ? batchMrp[code].mrp : 0),
            category: pinned(name) || byRules(name) || byRules(cleanQuery(name)) || company[clean(r.GCODE)] || null,
            purchase_price: purchaseRate(num(r.LPRATE), sr ? sr.rate : rateA, [packCount[code] ? +usualPack(code)[0] : 0, int(r.PACK)]),
            retail_price: sr ? sr.rate : rateA,
            wholesale_price: sr ? sr.rate : rateA,
            opening: int(r.OPENING),
            closing: int(r.BALANCE),
            moved: 0,
            rateFromList: !sr
          };
          byNameMrp(it, [pack, packCount[code] ? +usualPack(code)[0] : 0, int(r.PACK)]);
          items.push(it);
          itemByCode[code] = it;
          itemByKey[k] = it;
        }
        if (skippedItems) cleaning.push(`${skippedItems} placeholder item rows skipped (###\u2026, "PRODUCT NAME").`);
        if (mergedItems) cleaning.push(`${mergedItems} duplicate item names merged into one item each.`);
        const noMrp = items.filter((i) => !i.mrp).length;
        if (noMrp) cleaning.push(`${noMrp} items have no MRP in their name or on their bill rows; set it later with Stock \u203A Auto-fill missing MRPs or by editing the item.`);
        const parties = [], partyByCode = {}, partyByKey = {};
        let badGstin = 0, mergedParties = 0, cityCut = 0;
        for (const r of order) {
          const group = clean(r.SCODE);
          const kind = group.startsWith("C6") ? "CUSTOMER" : group.startsWith("D3") ? "SUPPLIER" : null;
          if (!kind) continue;
          const parts = String(r.PARNAM || "").split(/\s{3,}/).map(clean).filter(Boolean);
          let name = parts[0] || "";
          if (!name) continue;
          const town = clean(r.CITY);
          if (parts.length > 1) cityCut++;
          else if (town && name.length > town.length + 3 && name.toLowerCase().endsWith(" " + town.toLowerCase())) {
            name = clean(name.slice(0, name.length - town.length));
            cityCut++;
          }
          const k = kind + "|" + key(name);
          const code = clean(r.ORDNO);
          if (partyByKey[k]) {
            partyByCode[code] = partyByKey[k];
            mergedParties++;
            continue;
          }
          let gstin = clean(r.GSTNO).toUpperCase().replace(/\s/g, "");
          if (gstin && !GSTIN_RE.test(gstin)) {
            badGstin++;
            gstin = "";
          }
          const pan = clean(r.ITNO).toUpperCase();
          const city = clean(r.CITY);
          const addr = [r.PARADD, r.PARADD1, r.PARADD2].map(clean).filter((x) => x && !/aadhaa?r/i.test(x));
          if (city && !addr.some((a) => a.toLowerCase().includes(city.toLowerCase()))) addr.push(city);
          const pin = clean(r.DSM);
          if (/^\d{6}$/.test(pin) && !addr.some((a) => a.includes(pin))) addr.push(pin);
          const mobiles = [], land = [];
          for (const f of ["PHONE1", "PHONE2", "PHONE3", "PHONE4"]) {
            for (const piece of String(r[f] || "").split(/[,;\/]/)) {
              const d = piece.replace(/\D/g, "");
              if (d.length < 6) continue;
              const m = mobileOf(d);
              if (m) {
                if (!mobiles.includes(m)) mobiles.push(m);
              } else if (!land.includes(clean(piece))) land.push(clean(piece));
            }
          }
          const p = {
            code,
            kind,
            name,
            gstin: gstin || null,
            state_code: gstin ? gstin.slice(0, 2) : null,
            pan: PAN_RE.test(pan) ? pan : gstin ? gstin.slice(2, 12) : null,
            address: addr.join(", ") || null,
            phone: mobiles[0] || land[0] || null,
            mobiles: mobiles.slice(1).join(", ") || null,
            tel: land.join(", ") || null,
            opening: r2(num(r.OPNING)),
            closing: r2(num(r.BALANCE)),
            moved: 0
          };
          parties.push(p);
          partyByCode[code] = p;
          partyByKey[k] = p;
        }
        if (cityCut) cleaning.push(`${cityCut} party names had the town padded onto the name; the town was moved to the address.`);
        if (badGstin) cleaning.push(`${badGstin} invalid GSTINs dropped.`);
        if (mergedParties) cleaning.push(`${mergedParties} duplicate party names merged.`);
        const lines = {};
        for (const l of dis) (lines[clean(l.VOUCHER) + "|" + clean(l.CODEP)] ||= []).push(l);
        const docs = [];
        const bad = [];
        const skip = { other: 0, noParty: 0 };
        for (const h of mdis) {
          const type = clean(h.TYPE);
          const kind = type === "S" ? "SALE" : type === "P" ? "PURCHASE" : type === "Q" ? "DEBIT_NOTE" : null;
          if (!kind) {
            skip.other++;
            continue;
          }
          const no = clean(h.VCN), date = day(h.DATE);
          const party = partyByCode[clean(h.CODEP)];
          if (!no || !date) {
            skip.other++;
            continue;
          }
          if (!party || kind === "SALE" !== (party.kind === "CUSTOMER")) {
            skip.noParty++;
            note(warnings, `${no}: its party (Marg code ${clean(h.CODEP)}) is not a ${kind === "SALE" ? "customer" : "supplier"}; bill skipped.`);
            continue;
          }
          const flag = type === "S" ? "G" : type;
          const rows = [];
          for (const l of lines[clean(h.VOUCHER) + "|" + clean(h.CODEP)] || []) {
            if (clean(l.FLG) !== flag) continue;
            const it = itemByCode[clean(l.CODE)];
            if (!it) {
              note(warnings, `${no}: item code ${clean(l.CODE)} is not in the item list; that row is left out.`);
              continue;
            }
            const pcs = int(l.QTY), free = int(l.FREE), pack = Math.max(1, int(l.PACK) || it.pcs_per_box);
            const taxable = r2(num(l.AMMMOUNT)), disc = r2(num(l.SDISCOUNT)), tax = r2(num(l.SSTAAMO)), cg2 = r2(num(l.CGSTAMO));
            rows.push({
              item: it,
              qty: pcs,
              free,
              taxable,
              disc_amt: disc,
              disc_pct: num(l.DISC1),
              gross: r2(taxable + disc),
              rate: pcs > 0 ? r8(num(l.SFRATE) / pack) : 0,
              gst_rate: num(l.CGST) > 0 ? num(l.CGST) * 2 : tax > 0 ? it.gst_rate : 0,
              cgst: cg2 > 0 ? cg2 : 0,
              sgst: cg2 > 0 ? r2(tax - cg2) : 0,
              igst: cg2 > 0 ? 0 : tax,
              amount: r2(taxable + tax),
              stock: kind !== "DEBIT_NOTE" && clean(l.GODWON) !== "Y",
              challan: clean(l.CHALLAN)
            });
          }
          const taxAmt = r2(num(h.TAXAMO)), cg = r2(num(h.CGSTAMO));
          const d = {
            kind,
            no,
            date,
            party,
            rows,
            ref: kind === "PURCHASE" ? clean(h.PM) || null : kind === "DEBIT_NOTE" ? (rows.find((x) => x.challan) || {}).challan || null : null,
            subtotal: r2(rows.reduce((a, x) => a + x.gross, 0)),
            discount: r2(rows.reduce((a, x) => a + x.disc_amt, 0)),
            taxable: r2(num(h.AMOUNTT)),
            cgst: cg > 0 ? cg : 0,
            sgst: cg > 0 ? r2(taxAmt - cg) : 0,
            igst: cg > 0 ? 0 : taxAmt,
            round_off: r2(num(h.ROUND)),
            total: r2(num(h.FINAL))
          };
          if (Math.abs(r2(d.taxable + taxAmt + d.round_off) - d.total) > 0.05) bad.push(`${no}: taxable + GST + round off = ${r2(d.taxable + taxAmt + d.round_off)}, Marg total ${d.total}`);
          else if (Math.abs(r2(rows.reduce((a, x) => a + x.taxable, 0)) - d.taxable) > 0.5) bad.push(`${no}: rows add up to ${r2(rows.reduce((a, x) => a + x.taxable, 0))}, Marg taxable ${d.taxable}`);
          if (!rows.length) {
            note(warnings, `${no}: no item rows; skipped.`);
            continue;
          }
          docs.push(d);
        }
        if (skip.other) cleaning.push(`${skip.other} other Marg vouchers (not sales, purchases or debit notes) left out.`);
        const money = [];
        for (const r of gl) {
          const book = clean(r.BOOK);
          if (book !== "R" && book !== "P") continue;
          const p = partyByCode[clean(r.CODE)];
          if (!p) continue;
          const amt = r2(book === "R" ? num(r.CREDIT) - num(r.DEBIT) : num(r.DEBIT) - num(r.CREDIT));
          const date = day(r.DATE);
          if (!(amt > 0) || !date) continue;
          const ref = clean(r.REMARK1);
          const mode = /neft|rtgs|imps|bank|transfer/i.test(ref) ? "BANK" : /upi|gpay|phonepe|paytm/i.test(ref) ? "UPI" : /che?q/i.test(ref) ? "CHEQUE" : "CASH";
          money.push({ kind: book === "R" ? "RECEIPT" : "PAYMENT", no: `${book === "R" ? "MR" : "MP"}/${clean(r.VOUCHER)}`, date, party: p, amount: amt, mode, ref: ref || null });
        }
        const used = /* @__PURE__ */ new Set([...docs.map((d) => d.party), ...money.map((v) => v.party)]);
        const builtIn = parties.filter((p) => p.code.startsWith("STA") && p.opening === 0 && p.closing === 0 && !used.has(p));
        if (builtIn.length) {
          cleaning.push(`${builtIn.length} empty Marg system accounts left out (${builtIn.slice(0, 3).map((p) => p.name).join(", ")}${builtIn.length > 3 ? ", \u2026" : ""}).`);
          for (const p of builtIn) parties.splice(parties.indexOf(p), 1);
        }
        for (const d of docs) {
          d.party.moved += d.kind === "PURCHASE" ? -d.total : d.total;
          for (const x of d.rows) if (x.stock) x.item.moved += (d.kind === "SALE" ? -1 : 1) * (x.qty + x.free);
        }
        for (const m of money) m.party.moved += m.kind === "RECEIPT" ? -m.amount : m.amount;
        const partyOff = parties.filter((p) => Math.abs(r2(p.opening + p.moved) - p.closing) > 0.05).map((p) => `${p.name}: opening ${p.opening} + bills and payments = ${r2(p.opening + p.moved)}, Marg closing ${p.closing}`);
        const stockOff = items.filter((i) => i.opening + i.moved !== i.closing).map((i) => `${i.name}: opening ${i.opening} + purchases \u2212 sales = ${i.opening + i.moved}, Marg closing ${i.closing}`);
        const negative = items.filter((i) => i.opening + i.moved < 0).length;
        if (negative) note(warnings, `${negative} items have negative stock in Marg (sold more than was entered as bought); they come in negative so the totals still match.`);
        const dates = docs.map((d) => d.date).sort();
        const sum = (k) => r2(docs.filter((d) => d.kind === k).reduce((a, d) => a + d.total, 0));
        const msum = (k) => r2(money.filter((m) => m.kind === k).reduce((a, m) => a + m.amount, 0));
        const count = (k) => docs.filter((d) => d.kind === k).length;
        const summary = {
          period: dates.length ? { from: dates[0], to: dates[dates.length - 1] } : null,
          found: {
            items: items.length,
            customers: parties.filter((p) => p.kind === "CUSTOMER").length,
            suppliers: parties.filter((p) => p.kind === "SUPPLIER").length,
            sales: count("SALE"),
            purchases: count("PURCHASE"),
            debit_notes: count("DEBIT_NOTE"),
            receipts: money.filter((m) => m.kind === "RECEIPT").length,
            payments: money.filter((m) => m.kind === "PAYMENT").length
          },
          totals: {
            sales: sum("SALE"),
            purchases: sum("PURCHASE"),
            debit_notes: sum("DEBIT_NOTE"),
            receipts: msum("RECEIPT"),
            payments: msum("PAYMENT"),
            opening_receivable: r2(parties.reduce((a, p) => a + (p.opening > 0 ? p.opening : 0), 0)),
            opening_payable: r2(parties.reduce((a, p) => a + (p.opening < 0 ? -p.opening : 0), 0))
          },
          checks: {
            bills: { checked: docs.length, ok: docs.length - bad.length, problems: bad },
            party_balances: { checked: parties.length, ok: parties.length - partyOff.length, problems: partyOff },
            stock: { checked: items.length, ok: items.length - stockOff.length, problems: stockOff }
          },
          cleaning,
          warnings
        };
        return { items, parties, docs, money, summary };
      }
      function write(m) {
        const added = { items: 0, categories: 0, customers: 0, suppliers: 0, sales: 0, purchases: 0, debit_notes: 0, receipts: 0, payments: 0 };
        const existing = { items: 0, parties: 0, bills: 0, vouchers: 0 };
        const catId = (name) => {
          if (!name) return null;
          const row = db2.prepare("SELECT id FROM categories WHERE lower(name)=lower(?)").get(name);
          if (row) return row.id;
          added.categories++;
          return Number(db2.prepare("INSERT INTO categories(name) VALUES(?)").run(name).lastInsertRowid);
        };
        const opening = m.summary.period ? m.summary.period.from : null;
        for (const it of m.items) {
          const have = db2.prepare("SELECT id FROM items WHERE lower(name)=lower(?)").get(it.name);
          if (have) {
            it.id = have.id;
            it.isNew = false;
            existing.items++;
          } else {
            it.id = Number(db2.prepare(`INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box) VALUES(?,?,?,?,?,?,?,?,?,?)`).run(it.name, catId(it.category), it.hsn, it.gst_rate, "PCS", it.mrp, it.retail_price, it.wholesale_price, it.purchase_price, it.pcs_per_box).lastInsertRowid);
            it.isNew = true;
            added.items++;
          }
          let b = db2.prepare("SELECT id FROM batches WHERE item_id=? AND batch_no='MARG'").get(it.id);
          if (!b) b = { id: Number(db2.prepare("INSERT INTO batches(item_id,batch_no,exp_date,qty,purchase_price,mrp) VALUES(?,'MARG',?,?,?,?)").run(it.id, NO_EXPIRY, it.isNew ? it.opening : 0, it.purchase_price, it.mrp || null).lastInsertRowid) };
          it.batch = b.id;
        }
        const lg = db2.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)");
        for (const p of m.parties) {
          const have = db2.prepare(`SELECT id FROM parties WHERE lower(name)=lower(?) AND ${p.kind === "SUPPLIER" ? "type='SUPPLIER'" : "type<>'SUPPLIER'"}`).get(p.name);
          if (have) {
            p.id = have.id;
            existing.parties++;
            continue;
          }
          p.id = Number(db2.prepare(`INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,pan,type,price_tier) VALUES(?,?,?,?,?,?,?,?,?,?)`).run(p.name, p.gstin, p.state_code, p.phone, p.tel, p.mobiles, p.address, p.pan, p.kind === "SUPPLIER" ? "SUPPLIER" : "RETAILER", "RETAIL").lastInsertRowid);
          added[p.kind === "SUPPLIER" ? "suppliers" : "customers"]++;
          if (p.opening !== 0 && opening) lg.run(p.id, opening, "OPENING", "OPENING", p.opening > 0 ? p.opening : 0, p.opening < 0 ? -p.opening : 0, "Opening balance (Marg)");
        }
        const move = db2.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?");
        for (const d of m.docs) {
          if (d.kind === "SALE") {
            if (db2.prepare("SELECT 1 FROM invoices WHERE invoice_no=?").get(d.no)) {
              existing.bills++;
              continue;
            }
            const id = Number(db2.prepare(`INSERT INTO invoices(invoice_no,date,party_id,sale_type,pay_mode,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,0)`).run(d.no, d.date, d.party.id, "COUNTER", "CREDIT", d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total).lastInsertRowid);
            for (const x of d.rows) {
              db2.prepare(`INSERT INTO invoice_lines(invoice_id,item_id,batch_id,qty,free_qty,rate,disc_pct,disc_amt,taxable,gst_rate,cgst,sgst,igst,amount,manual_disc) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(id, x.item.id, x.item.batch, x.qty, x.free, x.rate, x.disc_pct, x.disc_amt, x.taxable, x.gst_rate, x.cgst, x.sgst, x.igst, x.amount, x.disc_pct);
              if (x.stock) move.run(-(x.qty + x.free), x.item.batch);
            }
            lg.run(d.party.id, d.date, "INVOICE", d.no, d.total, 0, `Sale ${d.no}`);
            added.sales++;
          } else if (d.kind === "PURCHASE") {
            if (db2.prepare("SELECT 1 FROM purchases WHERE purchase_no=?").get(d.no)) {
              existing.bills++;
              continue;
            }
            const id = Number(db2.prepare(`INSERT INTO purchases(purchase_no,supplier_invoice_no,date,party_id,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,source) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,0,'MARG')`).run(d.no, d.ref, d.date, d.party.id, d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total).lastInsertRowid);
            for (const x of d.rows) {
              db2.prepare(`INSERT INTO purchase_lines(purchase_id,item_id,batch_id,batch_no,exp_date,qty,free_qty,rate,disc_pct,disc_amt,mrp,taxable,gst_rate,cgst,sgst,igst,amount,unit,pcs_qty) VALUES(?,?,?,'MARG',?,?,?,?,?,?,?,?,?,?,?,?,?,'PCS',?)`).run(id, x.item.id, x.item.batch, NO_EXPIRY, x.qty, x.free, x.qty > 0 ? r8(x.gross / x.qty) : 0, x.disc_pct, x.disc_amt, x.item.mrp || null, x.taxable, x.gst_rate, x.cgst, x.sgst, x.igst, x.gross, x.qty + x.free);
              if (x.stock) move.run(x.qty + x.free, x.item.batch);
            }
            lg.run(d.party.id, d.date, "PURCHASE", d.no, 0, d.total, `Purchase ${d.no}${d.ref ? " / " + d.ref : ""}`);
            added.purchases++;
          } else {
            if (db2.prepare("SELECT 1 FROM debit_notes WHERE note_no=?").get(d.no)) {
              existing.bills++;
              continue;
            }
            const id = Number(db2.prepare(`INSERT INTO debit_notes(note_no,date,party_id,against_bill,reason,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,source) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'MARG')`).run(d.no, d.date, d.party.id, d.ref, "From Marg", d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total).lastInsertRowid);
            for (const x of d.rows) {
              db2.prepare(`INSERT INTO debit_note_lines(note_id,item_id,batch_id,qty,unit,pcs_qty,rate,amount,taxable,gst_rate,cgst,sgst,igst) VALUES(?,?,NULL,?,'PCS',?,?,?,?,?,?,?,?)`).run(id, x.item.id, x.qty, x.qty, x.qty > 0 ? r8(x.gross / x.qty) : 0, x.gross, x.taxable, x.gst_rate, x.cgst, x.sgst, x.igst);
            }
            lg.run(d.party.id, d.date, "DEBIT_NOTE", d.no, d.total, 0, `Debit note ${d.no}${d.ref ? " against " + d.ref : ""}`);
            added.debit_notes++;
          }
        }
        for (const v of m.money) {
          if (v.kind === "RECEIPT") {
            if (db2.prepare("SELECT 1 FROM receipts WHERE receipt_no=?").get(v.no)) {
              existing.vouchers++;
              continue;
            }
            db2.prepare("INSERT INTO receipts(receipt_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)").run(v.no, v.date, v.party.id, v.mode, v.amount, v.ref);
            lg.run(v.party.id, v.date, "RECEIPT", v.no, 0, v.amount, `Payment received (${v.mode})${v.ref ? " " + v.ref : ""}`);
            added.receipts++;
          } else {
            if (db2.prepare("SELECT 1 FROM payments WHERE voucher_no=?").get(v.no)) {
              existing.vouchers++;
              continue;
            }
            db2.prepare("INSERT INTO payments(voucher_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)").run(v.no, v.date, v.party.id, v.mode, v.amount, v.ref);
            lg.run(v.party.id, v.date, "PAYMENT", v.no, v.amount, 0, `Payment made (${v.mode})${v.ref ? " " + v.ref : ""}`);
            added.payments++;
          }
        }
        return { added, existing };
      }
      var Preview = class extends Error {
      };
      function checkYear(m) {
        const own = require_fy().booksFy();
        const per = m.summary.period;
        if (!own || !per) return;
        const fy = fyRange(own);
        if (per.from < fy.from || per.to > fy.to) {
          const theirs = fyRange(String(Number(per.from.slice(0, 4)) - (Number(per.from.slice(5, 7)) < 4 ? 1 : 0))).label;
          throw new HttpError2(400, `This Marg data is for ${theirs} (${per.from} to ${per.to}), but these are the ${own} books. Open or add the ${theirs} books first (Settings \u203A Companies).`, "WRONG_YEAR");
        }
      }
      function previewMarg(p) {
        const m = model(readSource(p));
        checkYear(m);
        let out;
        try {
          db2.transaction(() => {
            out = write(m);
            throw new Preview();
          })();
        } catch (e) {
          if (!(e instanceof Preview)) throw e;
        }
        return { ...m.summary, would_add: out.added, already_here: out.existing };
      }
      function followMarg(m) {
        const get = (k) => {
          const r = db2.prepare("SELECT value FROM settings WHERE key=?").get(k);
          return r && r.value !== null ? String(r.value) : "";
        };
        const set = db2.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value");
        const out = {};
        if (get("num_fy") !== "") return out;
        for (const [kind, s] of [["SALE", "INV"], ["PURCHASE", "PUR"], ["DEBIT_NOTE", "DN"]]) {
          if (get(`num_${s}_prefix`) !== "") continue;
          let best = null;
          for (const d of m.docs) {
            if (d.kind !== kind) continue;
            const x = /^(.*?[^0-9])([0-9]+)$/.exec(d.no);
            if (x && (!best || parseInt(x[2], 10) > parseInt(best[2], 10))) best = x;
          }
          if (!best || !best[1].trim()) continue;
          set.run(`num_${s}_prefix`, best[1]);
          set.run(`num_${s}_digits`, String(Math.min(9, best[2].length)));
          out[s] = best[1];
        }
        if (Object.keys(out).length) set.run("num_fy", "0");
        for (const s of Object.keys(out)) out[s] = peekNo(s).next_no;
        return out;
      }
      function importMarg(p) {
        const m = model(readSource(p));
        checkYear(m);
        let numbering = {};
        const out = db2.transaction(() => {
          const w = write(m);
          numbering = followMarg(m);
          return w;
        })();
        return { ...m.summary, added: out.added, already_here: out.existing, numbering };
      }
      function correctPrices(p, apply) {
        const m = model(readSource(p));
        const far = (have, want) => want > 0 ? !(have > 0) || have / want >= 1.9 || want / have >= 1.9 : false;
        const items = [];
        let checked = 0;
        const run = () => {
          for (const it of m.items) {
            const h = db2.prepare("SELECT id,name,retail_price,wholesale_price,purchase_price,mrp FROM items WHERE lower(name)=lower(?)").get(it.name);
            if (!h) continue;
            checked++;
            const want = { retail_price: r8(it.retail_price), wholesale_price: r8(it.wholesale_price), purchase_price: r8(it.purchase_price), mrp: r2(it.mrp || 0) };
            const next = {};
            for (const k of Object.keys(want)) next[k] = far(Number(h[k]) || 0, want[k]) ? want[k] : Number(h[k]) || 0;
            if (Object.keys(want).every((k) => next[k] === (Number(h[k]) || 0))) continue;
            items.push({
              name: h.name,
              retail_old: Number(h.retail_price) || 0,
              retail_new: next.retail_price,
              wholesale_old: Number(h.wholesale_price) || 0,
              wholesale_new: next.wholesale_price,
              purchase_old: Number(h.purchase_price) || 0,
              purchase_new: next.purchase_price,
              mrp_old: Number(h.mrp) || 0,
              mrp_new: next.mrp
            });
            if (apply) db2.prepare("UPDATE items SET retail_price=?,wholesale_price=?,purchase_price=?,mrp=? WHERE id=?").run(next.retail_price, next.wholesale_price, next.purchase_price, next.mrp, h.id);
          }
        };
        if (apply) db2.transaction(run)();
        else run();
        return { checked, changed: items.length, applied: !!apply, items };
      }
      function cleanTables(p) {
        const m = model(readSource(p));
        return {
          summary: m.summary,
          items: m.items.map((i) => ({
            marg_code: i.code,
            name: i.name,
            category: i.category || "",
            hsn: i.hsn || "",
            gst_rate: i.gst_rate,
            pcs_per_box: i.pcs_per_box,
            mrp: i.mrp || "",
            purchase_price: i.purchase_price,
            sale_price: i.retail_price,
            opening_stock_pcs: i.opening,
            closing_stock_pcs: i.closing
          })),
          parties: m.parties.map((x) => ({
            marg_code: x.code,
            type: x.kind,
            name: x.name,
            address: x.address || "",
            gstin: x.gstin || "",
            state_code: x.state_code || "",
            pan: x.pan || "",
            phone: x.phone || "",
            mobiles: x.mobiles || "",
            tel: x.tel || "",
            opening_balance: x.opening,
            closing_balance: x.closing
          })),
          bills: m.docs.map((d) => ({
            type: d.kind,
            no: d.no,
            date: d.date,
            party: d.party.name,
            ref: d.ref || "",
            rows: d.rows.length,
            subtotal: d.subtotal,
            discount: d.discount,
            taxable: d.taxable,
            cgst: d.cgst,
            sgst: d.sgst,
            igst: d.igst,
            round_off: d.round_off,
            total: d.total
          })),
          bill_rows: m.docs.flatMap((d) => d.rows.map((x) => ({
            type: d.kind,
            no: d.no,
            date: d.date,
            item: x.item.name,
            qty_pcs: x.qty,
            free_pcs: x.free,
            rate_per_pc: x.rate,
            disc_pct: x.disc_pct,
            disc_amt: x.disc_amt,
            taxable: x.taxable,
            gst_rate: x.gst_rate,
            cgst: x.cgst,
            sgst: x.sgst,
            igst: x.igst,
            amount: x.amount
          }))),
          money: m.money.map((v) => ({ type: v.kind, no: v.no, date: v.date, party: v.party.name, mode: v.mode, amount: v.amount, reference: v.ref || "" }))
        };
      }
      module.exports = { previewMarg, importMarg, cleanTables, parseCsv, readZip, correctPrices };
    }
  });

  // ../../backend/src/routes/import.js
  var require_import = __commonJS({
    "../../backend/src/routes/import.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var { h } = require_misc();
      var { previewMarg, importMarg, correctPrices } = require_margImport();
      router.post("/import/marg/preview", h((req, res) => res.json(previewMarg((req.body || {}).path))));
      router.post("/import/marg", h((req, res) => res.json(importMarg((req.body || {}).path))));
      router.post("/import/marg/prices", h((req, res) => res.json(correctPrices((req.body || {}).path, !!(req.body || {}).apply))));
      module.exports = router;
    }
  });

  // ../../backend/src/services/reports.js
  var require_reports = __commonJS({
    "../../backend/src/services/reports.js"(exports, module) {
      init_globals();
      var db2 = require_db();
      var { r2 } = require_gst();
      var { today } = require_misc();
      var addDays = (n, base = /* @__PURE__ */ new Date()) => {
        const d = new Date(base);
        d.setDate(d.getDate() + n);
        return d.toLocaleDateString("en-CA");
      };
      var one = (sql, ...a) => db2.prepare(sql).get(...a);
      var monthOf = (d) => d.slice(0, 7);
      var { fyRange } = require_fy();
      var clamp = (d, r) => d < r.from ? r.from : d > r.to ? r.to : d;
      function profit(from, to) {
        const r = one(
          `SELECT COALESCE(SUM(l.taxable),0) revenue,
            COALESCE(SUM((l.qty+l.free_qty) * COALESCE(NULLIF(b.purchase_price,0), NULLIF(it.purchase_price,0), 0)),0) cost,
            COALESCE(SUM(CASE WHEN COALESCE(NULLIF(b.purchase_price,0), NULLIF(it.purchase_price,0), 0)=0 THEN 1 ELSE 0 END),0) unknown_cost_lines
     FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id JOIN items it ON it.id=l.item_id LEFT JOIN batches b ON b.id=l.batch_id
     WHERE i.date BETWEEN ? AND ?`,
          from,
          to
        );
        const p = r2(r.revenue - r.cost);
        return { revenue: r2(r.revenue), cost: r2(r.cost), profit: p, margin_pct: r.revenue > 0 ? r2(p / r.revenue * 100) : 0, unknown_cost_lines: r.unknown_cost_lines };
      }
      var sumBetween = (table, col, from, to) => r2(one(`SELECT COALESCE(SUM(${col}),0) v FROM ${table} WHERE date BETWEEN ? AND ?`, from, to).v);
      function expiryDays() {
        const r = db2.prepare("SELECT value FROM settings WHERE key='expiry_days'").get();
        const n = parseInt(r ? r.value : "", 10);
        return n >= 1 && n <= 365 ? n : 30;
      }
      function dashboard(fyLabel) {
        const fy = fyRange(fyLabel);
        const t = clamp(today(), fy);
        const m = monthOf(t), mFrom = m + "-01";
        const taxOut = (f, to) => one(`SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM invoices WHERE date BETWEEN ? AND ?`, f, to).v;
        const taxIn = (f, to) => one(`SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM purchases WHERE date BETWEEN ? AND ?`, f, to).v - one(`SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM debit_notes WHERE date BETWEEN ? AND ?`, f, to).v;
        const bal = one(`SELECT COALESCE(SUM(CASE WHEN b>0 THEN b ELSE 0 END),0) rec, COALESCE(-SUM(CASE WHEN b<0 THEN b ELSE 0 END),0) pay
                   FROM (SELECT SUM(debit)-SUM(credit) b FROM ledger WHERE date <= ? GROUP BY party_id)`, fy.to);
        const series = [];
        for (let i = 13; i >= 0; i--) {
          const d = addDays(-i, /* @__PURE__ */ new Date(t + "T12:00:00"));
          if (d < fy.from) continue;
          series.push({ date: d, sales: sumBetween("invoices", "total", d, d), purchases: sumBetween("purchases", "total", d, d) });
        }
        const monthly = [];
        for (let k = 0; k < 12; k++) {
          const y = fy.start_year + (k + 3 >= 12 ? 1 : 0), mo = (k + 3) % 12 + 1;
          const from = `${y}-${String(mo).padStart(2, "0")}-01`, to = `${y}-${String(mo).padStart(2, "0")}-31`;
          monthly.push({ month: from.slice(0, 7), sales: sumBetween("invoices", "total", from, to), purchases: sumBetween("purchases", "total", from, to), profit: profit(from, to).profit });
        }
        const low = lowStock(8);
        const fyProfit = profit(fy.from, fy.to), monthProfit = profit(mFrom, t), dayProfit = profit(t, t);
        return {
          fy: fy.label,
          fy_from: fy.from,
          fy_to: fy.to,
          is_current: fy.current,
          as_of: t,
          month: m,
          today_sales: sumBetween("invoices", "total", t, t),
          today_bills: one("SELECT COUNT(*) v FROM invoices WHERE date=?", t).v,
          today_profit: dayProfit.profit,
          month_sales: sumBetween("invoices", "total", mFrom, t),
          month_bills: one("SELECT COUNT(*) v FROM invoices WHERE date BETWEEN ? AND ?", mFrom, t).v,
          month_profit: monthProfit.profit,
          month_purchases: sumBetween("purchases", "total", mFrom, t),
          month_purchase_bills: one("SELECT COUNT(*) v FROM purchases WHERE date BETWEEN ? AND ?", mFrom, t).v,
          fy_sales: sumBetween("invoices", "total", fy.from, fy.to),
          fy_bills: one("SELECT COUNT(*) v FROM invoices WHERE date BETWEEN ? AND ?", fy.from, fy.to).v,
          fy_purchases: sumBetween("purchases", "total", fy.from, fy.to),
          fy_collections: sumBetween("receipts", "amount", fy.from, fy.to),
          fy_profit: fyProfit.profit,
          fy_margin_pct: fyProfit.margin_pct,
          fy_cost: fyProfit.cost,
          fy_revenue: fyProfit.revenue,
          profit_unknown_cost_lines: fyProfit.unknown_cost_lines,
          today_collections: sumBetween("receipts", "amount", t, t),
          receivable: r2(bal.rec),
          payable: r2(bal.pay),
          gst_output: r2(taxOut(mFrom, t)),
          gst_input: r2(taxIn(mFrom, t)),
          gst_liability: r2(taxOut(mFrom, t) - taxIn(mFrom, t)),
          fy_gst_liability: r2(taxOut(fy.from, fy.to) - taxIn(fy.from, fy.to)),
          low_stock_count: low.total,
          low_stock: low.rows,
          low_stock_qty: low.threshold,
          // Settings › Stock › expiry warning (days); the key keeps its old name
          expiring_30d: one("SELECT COUNT(*) v FROM batches WHERE qty>0 AND exp_date BETWEEN ? AND ?", today(), addDays(expiryDays())).v,
          expiry_days: expiryDays(),
          expired_stock: one("SELECT COUNT(*) v FROM batches WHERE qty>0 AND exp_date<?", today()).v,
          top_dues: db2.prepare(
            `SELECT p.id, p.name, SUM(l.debit)-SUM(l.credit) balance FROM parties p JOIN ledger l ON l.party_id=p.id AND l.date <= ?
       GROUP BY p.id HAVING balance > 0.5 ORDER BY balance DESC LIMIT 5`
          ).all(fy.to),
          series,
          monthly,
          month_collections: sumBetween("receipts", "amount", mFrom, t),
          unprinted_bills: one("SELECT COUNT(*) v FROM invoices WHERE printed=0 AND date BETWEEN ? AND ?", fy.from, fy.to).v,
          top_items: db2.prepare(
            `SELECT i.id, i.name, i.pcs_per_box, SUM(l.qty + l.free_qty) qty, ROUND(SUM(l.amount),2) amount FROM invoice_lines l
       JOIN invoices v ON v.id=l.invoice_id JOIN items i ON i.id=l.item_id WHERE v.date BETWEEN ? AND ?
       GROUP BY i.id ORDER BY amount DESC, i.name LIMIT 6`
          ).all(mFrom, t),
          recent_bills: db2.prepare(
            `SELECT v.id, v.invoice_no, v.date, COALESCE(p.name, 'Cash sale') party, v.total, v.printed FROM invoices v LEFT JOIN parties p ON p.id=v.party_id
       WHERE v.date BETWEEN ? AND ? ORDER BY v.date DESC, v.id DESC LIMIT 6`
          ).all(fy.from, fy.to)
        };
      }
      function lowStock(limit = 1e3) {
        const row = db2.prepare("SELECT value FROM settings WHERE key='low_stock_qty'").get();
        const threshold = Math.max(0, parseInt(row ? row.value : "10", 10) || 0);
        const all = db2.prepare(
          `SELECT i.id, i.name, i.pcs_per_box, COALESCE(SUM(b.qty),0) stock FROM items i JOIN batches b ON b.item_id=i.id
     WHERE i.active=1 GROUP BY i.id HAVING stock <= ? ORDER BY stock, i.name`
        ).all(threshold);
        return { threshold, total: all.length, rows: all.slice(0, limit) };
      }
      var STD_RATES = [0, 5, 12, 18, 28];
      function gstOutward(month, fyLabel) {
        const m = month || monthOf(clamp(today(), fyRange(fyLabel)));
        if (!/^\d{4}-\d{2}$/.test(m)) throw Object.assign(new Error("Month must be YYYY-MM"), { status: 400 });
        const rows = db2.prepare(
          `SELECT l.gst_rate rate, SUM(l.taxable) taxable, SUM(l.cgst) cgst, SUM(l.sgst) sgst, SUM(l.igst) igst, COUNT(DISTINCT l.invoice_id) invoices
     FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id WHERE substr(i.date,1,7)=? GROUP BY l.gst_rate`
        ).all(m);
        const byRate = new Map(rows.map((r) => [r.rate, r]));
        const rates = [.../* @__PURE__ */ new Set([...STD_RATES, ...rows.map((r) => r.rate)])].sort((a, b) => a - b);
        const out = rates.map((rate) => {
          const r = byRate.get(rate) || { taxable: 0, cgst: 0, sgst: 0, igst: 0, invoices: 0 };
          const tax = r2(r.cgst + r.sgst + r.igst);
          return { rate, taxable: r2(r.taxable), cgst: r2(r.cgst), sgst: r2(r.sgst), igst: tax, tax, value: r2(r.taxable + tax), invoices: r.invoices };
        });
        const tot = (k) => r2(out.reduce((a, r) => a + r[k], 0));
        const split = (cond) => one(
          `SELECT COALESCE(SUM(l.taxable),0) taxable, COALESCE(SUM(l.cgst+l.sgst+l.igst),0) tax FROM invoice_lines l
     JOIN invoices i ON i.id=l.invoice_id LEFT JOIN parties p ON p.id=i.party_id WHERE substr(i.date,1,7)=? AND ${cond}`,
          m
        );
        const b2b = split(`COALESCE(p.gstin,'') <> ''`), b2c = split(`COALESCE(p.gstin,'') = ''`);
        const inv = one("SELECT COUNT(*) n, COALESCE(SUM(round_off),0) ro FROM invoices WHERE substr(date,1,7)=?", m);
        const bought = one(`SELECT COALESCE(SUM(cgst),0) c, COALESCE(SUM(sgst),0) s, COALESCE(SUM(igst),0) i FROM purchases WHERE substr(date,1,7)=?`, m);
        const returned = one(`SELECT COALESCE(SUM(cgst),0) c, COALESCE(SUM(sgst),0) s, COALESCE(SUM(igst),0) i FROM debit_notes WHERE substr(date,1,7)=?`, m);
        const input = { c: bought.c - returned.c, s: bought.s - returned.s, i: bought.i - returned.i };
        return {
          month: m,
          rows: out,
          totals: { taxable: tot("taxable"), cgst: tot("cgst"), sgst: tot("sgst"), igst: tot("igst"), tax: tot("tax"), value: tot("value") },
          invoices: inv.n,
          round_off: r2(inv.ro),
          b2b: { taxable: r2(b2b.taxable), tax: r2(b2b.tax) },
          b2c: { taxable: r2(b2c.taxable), tax: r2(b2c.tax) },
          input_credit: { cgst: r2(input.c), sgst: r2(input.s), igst: r2(input.i), total: r2(input.c + input.s + input.i), debit_notes: r2(returned.c + returned.s + returned.i) },
          net_payable: r2(tot("tax") - (input.c + input.s + input.i))
        };
      }
      function gstOutwardDetail(month, fyLabel) {
        const base = gstOutward(month, fyLabel);
        const bills2 = db2.prepare(
          `SELECT i.id, i.invoice_no, i.date, COALESCE(p.name,'Cash customer') party, COALESCE(p.gstin,'') gstin, COALESCE(p.state_code,'') state_code,
            i.taxable, i.cgst, i.sgst, i.igst, i.round_off, i.total
     FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE substr(i.date,1,7)=? ORDER BY i.date, i.id`
        ).all(base.month);
        const rates = db2.prepare(
          `SELECT l.invoice_id, GROUP_CONCAT(DISTINCT l.gst_rate) rates FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id
     WHERE substr(i.date,1,7)=? GROUP BY l.invoice_id`
        ).all(base.month);
        const rm = new Map(rates.map((r) => [r.invoice_id, r.rates]));
        const rows = bills2.map((b) => ({ ...b, rates: (rm.get(b.id) || "").split(",").filter(Boolean).map((x) => x + "%").join(", "), tax: r2(b.cgst + b.sgst + b.igst), igst: r2(b.cgst + b.sgst + b.igst) }));
        return { ...base, b2b_bills: rows.filter((b) => b.gstin), b2c_bills: rows.filter((b) => !b.gstin) };
      }
      function book(type, from, to, fyLabel) {
        const fy = fyRange(fyLabel);
        const f = clamp(from || (fy.current ? monthOf(today()) + "-01" : fy.from), fy), t = clamp(to || (fy.current ? today() : fy.to), fy);
        const isSales = type === "sales";
        const rows = type === "debit" ? db2.prepare(`SELECT d.id, d.date, d.note_no no, COALESCE(d.against_bill,'') ref, p.name party, COALESCE(p.gstin,'') gstin,
                  d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total FROM debit_notes d JOIN parties p ON p.id=d.party_id
                  WHERE d.date BETWEEN ? AND ? ORDER BY d.date, d.id`).all(f, t) : isSales ? db2.prepare(`SELECT i.id, i.date, i.invoice_no no, '' ref, COALESCE(p.name,'Cash customer') party, COALESCE(p.gstin,'') gstin,
                  i.taxable, i.cgst, i.sgst, i.igst, i.round_off, i.total FROM invoices i LEFT JOIN parties p ON p.id=i.party_id
                  WHERE i.date BETWEEN ? AND ? ORDER BY i.date, i.id`).all(f, t) : db2.prepare(`SELECT u.id, u.date, u.purchase_no no, COALESCE(u.supplier_invoice_no,'') ref, p.name party, COALESCE(p.gstin,'') gstin,
                  u.taxable, u.cgst, u.sgst, u.igst, u.round_off, u.total FROM purchases u JOIN parties p ON p.id=u.party_id
                  WHERE u.date BETWEEN ? AND ? ORDER BY u.date, u.id`).all(f, t);
        const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
        return {
          type: type === "debit" ? "debit" : isSales ? "sales" : "purchase",
          from: f,
          to: t,
          rows,
          totals: { count: rows.length, taxable: sum("taxable"), cgst: sum("cgst"), sgst: sum("sgst"), igst: sum("igst"), round_off: sum("round_off"), total: sum("total") }
        };
      }
      function bills({ type = "ALL", from, to, q, unpaid, unprinted, fy: fyLabel } = {}) {
        const fy = fyRange(fyLabel);
        const f = clamp(from || fy.from, fy), t = clamp(to || fy.to, fy);
        const like = `%${(q || "").trim()}%`;
        const parts = [];
        if (type !== "PURCHASE" && type !== "DEBIT_NOTE")
          parts.push(`SELECT 'SALE' type, i.id, i.date, i.invoice_no no, '' ref, COALESCE(p.name,'Cash customer') party, i.total, i.paid, i.printed
                FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE i.date BETWEEN @f AND @t
                AND (i.invoice_no LIKE @q OR COALESCE(p.name,'Cash customer') LIKE @q)`);
        if (type !== "SALE" && type !== "DEBIT_NOTE")
          parts.push(`SELECT 'PURCHASE' type, u.id, u.date, u.purchase_no no, COALESCE(u.supplier_invoice_no,'') ref, p.name party, u.total, u.paid, 1 printed
                FROM purchases u JOIN parties p ON p.id=u.party_id WHERE u.date BETWEEN @f AND @t
                AND (u.purchase_no LIKE @q OR COALESCE(u.supplier_invoice_no,'') LIKE @q OR p.name LIKE @q)`);
        if (type === "ALL" || type === "DEBIT_NOTE")
          parts.push(`SELECT 'DEBIT_NOTE' type, d.id, d.date, d.note_no no, COALESCE(d.against_bill,'') ref, p.name party, d.total, d.total paid, 1 printed
                FROM debit_notes d JOIN parties p ON p.id=d.party_id WHERE d.date BETWEEN @f AND @t
                AND (d.note_no LIKE @q OR COALESCE(d.against_bill,'') LIKE @q OR p.name LIKE @q)`);
        let sql = `SELECT * FROM (${parts.join(" UNION ALL ")})`;
        const where = [];
        if (unpaid) where.push("total - paid > 0.5");
        if (unprinted) where.push("printed = 0");
        if (where.length) sql += " WHERE " + where.join(" AND ");
        sql += " ORDER BY date DESC, id DESC LIMIT 1000";
        const rows = db2.prepare(sql).all({ f, t, q: like });
        const total = (ty) => r2(rows.filter((r) => r.type === ty).reduce((a, r) => a + r.total, 0));
        return { rows, totals: { sales: total("SALE"), purchases: total("PURCHASE"), debit_notes: total("DEBIT_NOTE"), due: r2(rows.reduce((a, r) => a + (r.total - r.paid), 0)) } };
      }
      module.exports = { profit, lowStock, dashboard, gstOutward, gstOutwardDetail, book, bills };
    }
  });

  // ../../backend/src/utils/xlsx.js
  var require_xlsx = __commonJS({
    "../../backend/src/utils/xlsx.js"(exports, module) {
      init_globals();
      var zlib = require_zlib();
      var CRC = (() => {
        const t = new Int32Array(256);
        for (let n = 0; n < 256; n++) {
          let c = n;
          for (let k = 0; k < 8; k++) c = c & 1 ? 3988292384 ^ c >>> 1 : c >>> 1;
          t[n] = c;
        }
        return t;
      })();
      var crc32 = (buf) => {
        let c = -1;
        for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 255] ^ c >>> 8;
        return (c ^ -1) >>> 0;
      };
      var esc = (s) => String(s).replace(/[<>&"]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;" })[c]).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "");
      var colName = (i) => {
        let s = "";
        for (i++; i > 0; i = Math.floor((i - 1) / 26)) s = String.fromCharCode(65 + (i - 1) % 26) + s;
        return s;
      };
      function zip(files) {
        const parts = [], central = [];
        let off = 0;
        for (const [name, content] of files) {
          const raw = Buffer2.from(content), def = zlib.deflateRawSync(raw), nm = Buffer2.from(name), crc = crc32(raw);
          const lh = Buffer2.alloc(30);
          lh.writeUInt32LE(67324752, 0);
          lh.writeUInt16LE(20, 4);
          lh.writeUInt16LE(2048, 6);
          lh.writeUInt16LE(8, 8);
          lh.writeUInt32LE(crc, 14);
          lh.writeUInt32LE(def.length, 18);
          lh.writeUInt32LE(raw.length, 22);
          lh.writeUInt16LE(nm.length, 26);
          parts.push(lh, nm, def);
          const ch = Buffer2.alloc(46);
          ch.writeUInt32LE(33639248, 0);
          ch.writeUInt16LE(20, 4);
          ch.writeUInt16LE(20, 6);
          ch.writeUInt16LE(2048, 8);
          ch.writeUInt16LE(8, 10);
          ch.writeUInt32LE(crc, 16);
          ch.writeUInt32LE(def.length, 20);
          ch.writeUInt32LE(raw.length, 24);
          ch.writeUInt16LE(nm.length, 28);
          ch.writeUInt32LE(off, 42);
          central.push(ch, nm);
          off += 30 + nm.length + def.length;
        }
        const cd = Buffer2.concat(central), end = Buffer2.alloc(22);
        end.writeUInt32LE(101010256, 0);
        end.writeUInt16LE(files.length, 8);
        end.writeUInt16LE(files.length, 10);
        end.writeUInt32LE(cd.length, 12);
        end.writeUInt32LE(off, 16);
        return Buffer2.concat([...parts, cd, end]);
      }
      var STYLES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE3EAF3"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FF8A99AD"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="7">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="4" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
      function sheetXml(sh) {
        const rows = [];
        let r = 0;
        const cell = (c, v, s) => v === null || v === void 0 || v === "" ? `<c r="${c}" s="${s}"/>` : typeof v === "number" && Number.isFinite(v) ? `<c r="${c}" s="${s}"><v>${v}</v></c>` : `<c r="${c}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${esc(v)}</t></is></c>`;
        if (sh.title) {
          r++;
          rows.push(`<row r="${r}" ht="22" customHeight="1">${cell("A" + r, sh.title, 4)}</row>`);
          r++;
        }
        const headerRow = r + 1;
        r++;
        rows.push(`<row r="${r}" ht="30" customHeight="1">${sh.cols.map((c, i) => cell(colName(i) + r, c.h, 1)).join("")}</row>`);
        for (const row of sh.rows) {
          r++;
          rows.push(`<row r="${r}">${sh.cols.map((c, i) => cell(colName(i) + r, row[c.k], c.t === "num" ? 2 : c.t === "int" ? 3 : 0)).join("")}</row>`);
        }
        if (sh.total) {
          r++;
          rows.push(`<row r="${r}">${sh.cols.map((c, i) => cell(colName(i) + r, i === 0 && sh.total[c.k] === void 0 ? "Total" : sh.total[c.k], c.t === "num" || c.t === "int" ? 5 : 6)).join("")}</row>`);
        }
        const widths = sh.cols.map((c, i) => `<col min="${i + 1}" max="${i + 1}" width="${c.w || 14}" customWidth="1"/>`).join("");
        return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="${headerRow}" topLeftCell="A${headerRow + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols>${widths}</cols><sheetData>${rows.join("")}</sheetData></worksheet>`;
      }
      function buildXlsx(sheets) {
        const names = sheets.map((s) => esc(s.name.replace(/[\\\/?*\[\]:]/g, " ").slice(0, 31)));
        const files = [
          ["[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("")}</Types>`],
          ["_rels/.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
          ["xl/workbook.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${names.map((n, i) => `<sheet name="${n}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets></workbook>`],
          ["xl/_rels/workbook.xml.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("")}<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`],
          ["xl/styles.xml", STYLES],
          ...sheets.map((s, i) => [`xl/worksheets/sheet${i + 1}.xml`, sheetXml(s)])
        ];
        return zip(files);
      }
      module.exports = { buildXlsx };
    }
  });

  // ../../backend/src/routes/reports.js
  var require_reports2 = __commonJS({
    "../../backend/src/routes/reports.js"(exports, module) {
      init_globals();
      var router = require_express_shim().Router();
      var db2 = require_db();
      var { h, today } = require_misc();
      var { r2 } = require_gst();
      var R = require_reports();
      var { buildXlsx } = require_xlsx();
      var { fyRange, fyList } = require_fy();
      var addDays = (n) => {
        const d = /* @__PURE__ */ new Date();
        d.setDate(d.getDate() + n);
        return d.toLocaleDateString("en-CA");
      };
      router.get("/fy", h((req, res) => {
        const own = require_fy().booksFy();
        res.json({ current: own || fyRange().label, years: fyList(), books_fy: own });
      }));
      router.get("/reports/dashboard", h((req, res) => res.json(R.dashboard(req.query.fy))));
      router.get("/reports/profit", h((req, res) => {
        const f = fyRange(req.query.fy);
        res.json(R.profit(req.query.from || f.from, req.query.to || f.to));
      }));
      router.get("/reports/gst-outward.xlsx", h((req, res) => {
        const d = R.gstOutwardDetail(req.query.month, req.query.fy);
        const co = db2.prepare("SELECT value FROM settings WHERE key='company_name'").get();
        const bill = (rows) => ({ total: { invoice_no: "Total", taxable: r2(rows.reduce((a, r) => a + r.taxable, 0)), cgst: r2(rows.reduce((a, r) => a + r.cgst, 0)), sgst: r2(rows.reduce((a, r) => a + r.sgst, 0)), igst: r2(rows.reduce((a, r) => a + r.igst, 0)), round_off: r2(rows.reduce((a, r) => a + r.round_off, 0)), total: r2(rows.reduce((a, r) => a + r.total, 0)) } });
        const c = (h2, k, w, t) => ({ h: h2, k, w, t });
        const cols = (gst) => [
          c("Invoice No", "invoice_no", 16),
          c("Date", "date", 12),
          c("Party Name", "party", 32),
          ...gst ? [c("GSTIN", "gstin", 20)] : [],
          c("State", "state_code", 8),
          c("GST Rates", "rates", 12),
          c("Taxable Value", "taxable", 15, "num"),
          c("CGST", "cgst", 12, "num"),
          c("SGST", "sgst", 12, "num"),
          c("IGST (CGST+SGST)", "igst", 18, "num"),
          c("Round Off", "round_off", 10, "num"),
          c("Invoice Value", "total", 15, "num")
        ];
        const name = co && co.value || "Company";
        const sheets = [
          {
            name: "Summary",
            title: `GST Outward Supply - ${d.month} - ${name}`,
            cols: [c("Particulars", "k", 34), c("Taxable Value", "taxable", 16, "num"), c("Tax", "tax", 16, "num")],
            rows: [
              { k: "B2B (registered parties)", taxable: d.b2b.taxable, tax: d.b2b.tax },
              { k: "B2C (unregistered / cash)", taxable: d.b2c.taxable, tax: d.b2c.tax },
              { k: "Total outward supplies", taxable: d.totals.taxable, tax: d.totals.tax },
              { k: "Less: input tax credit (purchases less debit notes)", taxable: null, tax: d.input_credit.total },
              { k: "Net GST payable", taxable: null, tax: d.net_payable }
            ]
          },
          { name: "B2B Bills", title: `B2B bills - ${d.month}`, cols: cols(true), rows: d.b2b_bills, ...bill(d.b2b_bills) },
          { name: "B2C Bills", title: `B2C bills - ${d.month}`, cols: cols(false), rows: d.b2c_bills, ...bill(d.b2c_bills) },
          {
            name: "Rate-wise Summary",
            title: `Tax-rate-wise summary - ${d.month}`,
            cols: [c("GST Rate %", "rate", 12, "num"), c("Invoices", "invoices", 10, "int"), c("Taxable Value", "taxable", 16, "num"), c("CGST", "cgst", 14, "num"), c("SGST", "sgst", 14, "num"), c("IGST (CGST+SGST)", "igst", 18, "num"), c("Total Tax", "tax", 14, "num"), c("Total Value", "value", 16, "num")],
            rows: d.rows,
            total: { rate: "Total", ...d.totals }
          }
        ];
        res.set({ "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "Content-Disposition": `attachment; filename="GST-Outward-${d.month}.xlsx"` });
        res.send(buildXlsx(sheets));
      }));
      router.get("/reports/gst-outward", h((req, res) => res.json(R.gstOutward(req.query.month, req.query.fy))));
      router.get("/reports/book/:type", h((req, res) => res.json(R.book(req.params.type === "purchase" ? "purchase" : req.params.type === "debit" ? "debit" : "sales", req.query.from, req.query.to, req.query.fy))));
      router.get("/bills", h((req, res) => res.json(R.bills({ type: (req.query.type || "ALL").toUpperCase(), from: req.query.from, to: req.query.to, q: req.query.q, unpaid: req.query.unpaid === "1", unprinted: req.query.unprinted === "1", fy: req.query.fy }))));
      router.get("/reports/expiry", h((req, res) => {
        const days = parseInt(req.query.days) || 90;
        res.json(db2.prepare(
          `SELECT b.id, b.batch_no, b.exp_date, b.qty, i.name item_name, i.purchase_price,
       CAST(julianday(b.exp_date) - julianday(?) AS INTEGER) days_left, ROUND(b.qty * i.purchase_price, 2) stock_value
     FROM batches b JOIN items i ON i.id=b.item_id WHERE b.qty>0 AND b.exp_date <= ? AND b.exp_date < '2099-01-01' ORDER BY b.exp_date`
        ).all(today(), addDays(days)));
      }));
      router.get("/reports/low-stock", h((req, res) => res.json(R.lowStock().rows)));
      router.get("/reports/outstanding", h((req, res) => {
        res.json(db2.prepare(
          `SELECT p.id, p.name, p.phone, p.type, p.credit_limit, r.name route_name, SUM(l.debit)-SUM(l.credit) balance
     FROM parties p JOIN ledger l ON l.party_id=p.id AND l.date <= ? LEFT JOIN routes r ON r.id=p.route_id
     GROUP BY p.id HAVING ABS(balance) > 0.5 ORDER BY balance DESC`
        ).all(fyRange(req.query.fy).to));
      }));
      router.get("/reports/gst-summary", h((req, res) => {
        const from = req.query.from || today().slice(0, 7) + "-01", to = req.query.to || today();
        res.json(db2.prepare(
          `SELECT l.gst_rate, ROUND(SUM(l.taxable),2) taxable, ROUND(SUM(l.cgst),2) cgst, ROUND(SUM(l.sgst),2) sgst, ROUND(SUM(l.igst),2) igst
     FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id WHERE i.date BETWEEN ? AND ? GROUP BY l.gst_rate ORDER BY l.gst_rate`
        ).all(from, to));
      }));
      module.exports = router;
    }
  });

  // entry.js
  init_globals();
  var db = require_db();
  var B2 = require_backup();
  var { HttpError } = require_misc();
  var { parseInvoicePages } = require_pdfParser();
  var { createMissing } = require_autoCreate();
  var { settings } = require_billing();
  var { pageTextFromItems } = require_pdfExtract();
  var pre = [require_companies(), require_backup2()];
  var post = ["items", "parties", "salesmen", "invoices", "purchases", "debitNotes", "import", "reports"].map((n) => ({
    items: require_items(),
    parties: require_parties(),
    salesmen: require_salesmen(),
    invoices: require_invoices(),
    purchases: require_purchases2(),
    debitNotes: require_debitNotes2(),
    import: require_import(),
    reports: require_reports2()
  })[n]);
  function match(router, method, segs) {
    for (const rt of router.routes) {
      if (rt.m !== method) continue;
      const ps = rt.p.split("/").filter(Boolean);
      if (ps.length !== segs.length) continue;
      const params = {};
      let ok = true;
      ps.forEach((p, i) => {
        if (p.startsWith(":")) params[p.slice(1)] = decodeURIComponent(segs[i]);
        else if (p !== segs[i]) ok = false;
      });
      if (ok) return { rt, params };
    }
    return null;
  }
  function request(step) {
    return new Promise((resolve) => {
      const method = (step.method || "GET").toUpperCase();
      const segs = (step.path || "/").split("?")[0].split("/").filter(Boolean);
      const query = {};
      for (const [k, v] of Object.entries(step.query || {})) if (v !== null && v !== void 0) query[k] = String(v);
      const headers = { "x-company-id": step.company !== void 0 && step.company !== null ? String(step.company) : void 0 };
      const req = { params: {}, query, body: step.body || {}, get: (h) => headers[h.toLowerCase()] };
      let status = 200, sent = false, kind = "json";
      const hdr = {};
      const done = (r) => {
        if (!sent) {
          sent = true;
          globalThis.__bbStore = void 0;
          resolve(r);
        }
      };
      const res = {
        status(c) {
          status = c;
          return res;
        },
        json(v) {
          done({ status, body: JSON.parse(JSON.stringify(v === void 0 ? null : v)) });
          return res;
        },
        type(t) {
          kind = t;
          return res;
        },
        set(h) {
          Object.assign(hdr, h || {});
          return res;
        },
        send(v) {
          if (typeof v === "string" && kind === "html") return done({ status, html: v }), res;
          const bytes = v instanceof Uint8Array ? Buffer2.from(v) : Buffer2.from(String(v));
          done({ status, file: (/filename="([^"]+)"/.exec(hdr["Content-Disposition"] || "") || [])[1], type: hdr["Content-Type"] || "", b64: bytes.toString("base64") });
          return res;
        }
      };
      const onError = (err) => {
        if (err && (String(err.code || "").startsWith("SQLITE_CONSTRAINT") || err.code === "ERR_SQLITE_ERROR" && (Number(err.errcode) & 255) === 19)) {
          const msg = /UNIQUE/.test(err.message) ? "That value already exists (for example a duplicate batch number)." : "Invalid reference or missing value.";
          return res.status(409).json({ error: msg });
        }
        const st = err.status || 500;
        if (st === 500) console.error(err && err.stack || err);
        res.status(st).json({ error: st === 500 ? "Server error" : err.message, code: err.code, detail: st === 500 && err instanceof HttpError ? err.message : void 0 });
      };
      const run = (m) => {
        req.params = m.params;
        try {
          m.rt.hs[m.rt.hs.length - 1](req, res, (e) => e ? onError(e) : res.status(404).json({ error: "Not found" }));
        } catch (e) {
          onError(e);
        }
      };
      try {
        for (const r of pre) {
          const m = match(r, method, segs);
          if (m) return run(m);
        }
        const id = Number(req.get("x-company-id")) || db.firstCompanyId();
        const d = db.openCompany(id);
        if (!d) return res.status(404).json({ error: "Company not found" });
        globalThis.__bbStore = d;
        db.withCompany(id, () => {
          for (const r of post) {
            const m = match(r, method, segs);
            if (m) return run(m);
          }
          res.status(404).json({ error: "Not found" });
        });
      } catch (e) {
        onError(e);
      }
    });
  }
  function dump() {
    const out = {};
    out.registry = db.registry.prepare("SELECT id,name,file,active,fy FROM companies ORDER BY id").all().map((r) => {
      const x = { ...r };
      delete x.file;
      return x;
    });
    out.app_settings = db.registry.prepare("SELECT key,value FROM app_settings WHERE key NOT LIKE 'backup_last%' ORDER BY key").all();
    out.companies = {};
    for (const { id } of db.registry.prepare("SELECT id FROM companies ORDER BY id").all()) {
      const d = db.openCompany(id);
      if (!d) continue;
      const t = {};
      for (const { name } of d.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all())
        t[name] = d.prepare(`SELECT * FROM ${name} ORDER BY 1`).all().map((r) => {
          const x = { ...r };
          delete x.created_at;
          return x;
        });
      out.companies[String(id)] = t;
    }
    return out;
  }
  async function special(st) {
    if (st.op === "dump") return { dump: dump() };
    if (st.op === "parse") {
      const c = st.ctx || {};
      return { parse: parseInvoicePages(st.pages || [], c) };
    }
    if (st.op === "autocreate") {
      const id = st.company || db.firstCompanyId();
      globalThis.__bbStore = db.openCompany(id);
      try {
        const r = await db.withCompany(id, async () => {
          const co = settings();
          const parsed = parseInvoicePages(st.pages, {
            items: db.prepare("SELECT id,name,hsn,gst_rate FROM items WHERE active=1").all(),
            parties: db.prepare("SELECT id,name,gstin FROM parties WHERE active=1 AND type='SUPPLIER'").all(),
            companyGstin: co.company_gstin,
            companyName: co.company_name
          });
          return createMissing(parsed, { online: false });
        });
        return { parse: JSON.parse(JSON.stringify(r)) };
      } finally {
        globalThis.__bbStore = void 0;
      }
    }
    if (st.op === "pagetext") return { text: st.pages.map(pageTextFromItems) };
    if (st.op === "backup") {
      const r = B2.backupNow({ reason: st.reason || "manual" });
      return { folder: r.folder, files: r.files };
    }
    if (st.op === "tick") {
      const r = B2.tick();
      return { ok: true, folder: r ? r.folder : null };
    }
    return null;
  }
  var queue = Promise.resolve();
  var BillBox = {
    /** For the app: runs one request (in order) and hands the reply to AndroidHost.reply(id, json). */
    handle(id, json) {
      queue = queue.then(async () => {
        let out;
        try {
          const st = JSON.parse(json);
          out = (st.op ? await special(st) : null) || await request(st);
        } catch (e) {
          out = { status: 500, body: { error: "Server error", detail: String(e && e.message || e) } };
        }
        globalThis.AndroidHost.reply(id, JSON.stringify(out));
      });
    },
    /** For tests in Node: the same, returning the reply. */
    async call(st) {
      return (st.op ? await special(st) : null) || request(st);
    },
    version: "15.0"
  };
  globalThis.BillBox = BillBox;
  if (globalThis.AndroidHost && globalThis.AndroidHost.ready) globalThis.AndroidHost.ready();
})();
