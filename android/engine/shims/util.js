'use strict';
const custom = Symbol.for('nodejs.util.promisify.custom');
function promisify(fn) {
  if (fn[custom]) return fn[custom];
  return (...a) => new Promise((ok, no) => fn(...a, (e, ...r) => (e ? no(e) : ok(r.length > 1 ? r : r[0]))));
}
promisify.custom = custom;
module.exports = { promisify, inspect: (x) => JSON.stringify(x), format: (...a) => a.join(' ') };
