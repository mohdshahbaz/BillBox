// Node's Buffer, as much as the engine uses: from / alloc / concat / isBuffer, toString (utf8, latin1, base64, hex),
// slice, little-endian reads and writes. A Uint8Array underneath, so it passes straight to pdf.js and the SQLite bridge.
'use strict';
const te = new TextEncoder();
const td = new TextDecoder('utf-8');

function latin1(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return s;
}

class Buffer extends Uint8Array {
  static from(x, enc) {
    if (typeof x === 'string') {
      const e = String(enc || 'utf8').toLowerCase();
      if (e === 'base64') { const b = atob(x.replace(/[^A-Za-z0-9+/=]/g, '')); const o = new Buffer(b.length); for (let i = 0; i < b.length; i++) o[i] = b.charCodeAt(i); return o; }
      if (e === 'latin1' || e === 'binary' || e === 'ascii') { const o = new Buffer(x.length); for (let i = 0; i < x.length; i++) o[i] = x.charCodeAt(i) & 255; return o; }
      if (e === 'hex') { const o = new Buffer(x.length >> 1); for (let i = 0; i < o.length; i++) o[i] = parseInt(x.substr(i * 2, 2), 16); return o; }
      const u = te.encode(x); const o = new Buffer(u.length); o.set(u); return o;
    }
    if (x instanceof ArrayBuffer) return new Buffer(x);
    if (ArrayBuffer.isView(x)) { const o = new Buffer(x.byteLength); o.set(new Uint8Array(x.buffer, x.byteOffset, x.byteLength)); return o; }
    if (Array.isArray(x)) { const o = new Buffer(x.length); for (let i = 0; i < x.length; i++) o[i] = x[i] & 255; return o; }
    throw new TypeError('Buffer.from: unsupported value');
  }
  static alloc(n, fill) { const b = new Buffer(n); if (fill) b.fill(typeof fill === 'number' ? fill : 0); return b; }
  static allocUnsafe(n) { return new Buffer(n); }
  static isBuffer(x) { return x instanceof Buffer; }
  static byteLength(s, enc) { return typeof s === 'string' ? Buffer.from(s, enc).length : s.byteLength; }
  static concat(list, total) {
    const n = total !== undefined ? total : list.reduce((a, b) => a + b.length, 0);
    const o = new Buffer(n); let off = 0;
    for (const b of list) { if (off >= n) break; o.set(b.subarray(0, n - off), off); off += b.length; }
    return o;
  }
  toString(enc, start, end) {
    const b = this.subarray(start || 0, end === undefined ? this.length : end);
    const e = String(enc || 'utf8').toLowerCase();
    if (e === 'base64') return btoa(latin1(b));
    if (e === 'latin1' || e === 'binary' || e === 'ascii') return latin1(b);
    if (e === 'hex') { let s = ''; for (const x of b) s += (x < 16 ? '0' : '') + x.toString(16); return s; }
    return td.decode(b);
  }
  toJSON() { return { type: 'Buffer', data: Array.from(this) }; }
  equals(o) { if (o.length !== this.length) return false; for (let i = 0; i < o.length; i++) if (o[i] !== this[i]) return false; return true; }
  slice(a, b) { return this.subarray(a, b); }
  readUInt8(o) { return this[o]; }
  readUInt16LE(o) { return this[o] | (this[o + 1] << 8); }
  readUInt32LE(o) { return (this[o] | (this[o + 1] << 8) | (this[o + 2] << 16)) + this[o + 3] * 0x1000000; }
  readInt32LE(o) { return this[o] | (this[o + 1] << 8) | (this[o + 2] << 16) | (this[o + 3] << 24); }
  readUInt16BE(o) { return (this[o] << 8) | this[o + 1]; }
  readUInt32BE(o) { return this[o] * 0x1000000 + ((this[o + 1] << 16) | (this[o + 2] << 8) | this[o + 3]); }
  writeUInt8(v, o) { this[o] = v & 255; return o + 1; }
  writeUInt16LE(v, o) { this[o] = v & 255; this[o + 1] = (v >>> 8) & 255; return o + 2; }
  writeUInt32LE(v, o) { this[o] = v & 255; this[o + 1] = (v >>> 8) & 255; this[o + 2] = (v >>> 16) & 255; this[o + 3] = (v >>> 24) & 255; return o + 4; }
  write(s, o = 0) { const b = Buffer.from(s); this.set(b.subarray(0, this.length - o), o); return Math.min(b.length, this.length - o); }
}
module.exports = { Buffer };
