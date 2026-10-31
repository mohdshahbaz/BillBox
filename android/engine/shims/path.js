// POSIX path: what the engine uses (join, basename, dirname, extname, isAbsolute, resolve, sep).
'use strict';
function normalize(p) {
  const abs = p.startsWith('/');
  const out = [];
  for (const s of p.split('/')) {
    if (!s || s === '.') continue;
    if (s === '..') { if (out.length && out[out.length - 1] !== '..') out.pop(); else if (!abs) out.push('..'); } else out.push(s);
  }
  const r = (abs ? '/' : '') + out.join('/');
  return r || (abs ? '/' : '.');
}
const join = (...a) => normalize(a.filter((x) => x !== '').join('/'));
const basename = (p, ext) => { const s = String(p).replace(/\/+$/, ''); let b = s.slice(s.lastIndexOf('/') + 1); if (ext && b.endsWith(ext)) b = b.slice(0, -ext.length); return b; };
const dirname = (p) => { const s = String(p).replace(/\/+$/, ''); const i = s.lastIndexOf('/'); return i < 0 ? '.' : i === 0 ? '/' : s.slice(0, i); };
const extname = (p) => { const b = basename(p); const i = b.lastIndexOf('.'); return i <= 0 ? '' : b.slice(i); };
const isAbsolute = (p) => String(p).startsWith('/');
const resolve = (...a) => { let r = ''; for (const p of a) r = isAbsolute(p) ? p : r + '/' + p; return normalize(isAbsolute(r) ? r : '/' + r); };
module.exports = { join, basename, dirname, extname, isAbsolute, resolve, normalize, sep: '/', delimiter: ':', posix: null };
module.exports.posix = module.exports;
