// The file calls the engine makes, carried out by the Android app (AndroidFS, synchronous). Errors look like Node's
// (code ENOENT, EEXIST …) so the engine's own error handling works unchanged.
'use strict';
const host = () => globalThis.AndroidFS;
function call(name, ...a) {
  const r = JSON.parse(host()[name](...a.map((x) => (typeof x === 'string' ? x : JSON.stringify(x)))));
  if (r && r.error) { const e = new Error(`${r.error.code}: ${r.error.message}, ${name} '${a[0]}'`); e.code = r.error.code; e.path = a[0]; throw e; }
  return r ? r.ok : undefined;
}
const stats = (s) => ({ size: s.size, mtimeMs: s.mtime, mtime: new Date(s.mtime), birthtime: new Date(s.mtime), isDirectory: () => s.dir, isFile: () => !s.dir });
module.exports = {
  existsSync: (p) => !!call('exists', String(p)),
  statSync: (p, o) => { try { return stats(call('stat', String(p))); } catch (e) { if (o && o.throwIfNoEntry === false && e.code === 'ENOENT') return undefined; throw e; } },
  lstatSync: (p) => stats(call('stat', String(p))),
  readFileSync: (p, o) => {
    const b = Buffer.from(call('read', String(p)), 'base64');
    const enc = typeof o === 'string' ? o : o && o.encoding;
    return enc ? b.toString(enc) : b;
  },
  writeFileSync: (p, data) => call('write', String(p), (typeof data === 'string' ? Buffer.from(data) : Buffer.from(data)).toString('base64')),
  mkdirSync: (p, o) => call('mkdir', String(p), !!(o && o.recursive)),
  readdirSync: (p, o) => {
    const names = call('readdir', String(p));
    if (!(o && o.withFileTypes)) return names;
    return names.map((name) => { const s = call('stat', String(p).replace(/\/+$/, '') + '/' + name); return { name, isDirectory: () => s.dir, isFile: () => !s.dir }; });
  },
  rmSync: (p, o) => call('rm', String(p), !!(o && o.recursive), !!(o && o.force)),
  unlinkSync: (p) => call('rm', String(p), false, false),
  renameSync: (a, b) => call('rename', String(a), String(b)),
  copyFileSync: (a, b) => call('copy', String(a), String(b)),
  mkdtempSync: (prefix) => call('mkdtemp', String(prefix)),
};
