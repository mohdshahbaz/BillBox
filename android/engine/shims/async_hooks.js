// AsyncLocalStorage for one request at a time: the Android host runs requests one after another, so the company chosen for
// the request (globalThis.__bbStore, set by the entry) holds until its reply; a synchronous run() inside it (another company
// for a moment, as years and backups do) wins while it lasts.
'use strict';
class AsyncLocalStorage {
  constructor() { this.stack = []; }
  run(store, fn, ...a) {
    this.stack.push(store);
    try { return fn(...a); } finally { this.stack.pop(); }
  }
  getStore() { return this.stack.length ? this.stack[this.stack.length - 1] : globalThis.__bbStore; }
}
module.exports = { AsyncLocalStorage };
