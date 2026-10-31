// Raw deflate / inflate (zip files: Marg backups in, Excel files out) through pako.
'use strict';
const pako = require('pako');
module.exports = {
  inflateRawSync: (b) => Buffer.from(pako.inflateRaw(b)),
  deflateRawSync: (b) => Buffer.from(pako.deflateRaw(b)),
  inflateSync: (b) => Buffer.from(pako.inflate(b)),
  deflateSync: (b) => Buffer.from(pako.deflate(b)),
};
