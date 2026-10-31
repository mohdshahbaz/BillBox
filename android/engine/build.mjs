// Bundles backend/src (the Mac engine) for the Android app: android/app/src/main/assets/engine/engine.js
// Node modules the engine uses are swapped for the shims in ./shims (Android's SQLite, files and network through the app).
import { build } from 'esbuild';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
import { createRequire } from 'module';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const out = process.argv[2] || path.join(here, '../app/src/main/assets/engine/engine.js');
const shim = (n) => path.join(here, 'shims', n);
const map = {
  'fs': shim('fs.js'), 'path': shim('path.js'), 'os': shim('os.js'), 'crypto': shim('crypto.js'), 'zlib': shim('zlib.js'),
  'util': shim('util.js'), 'child_process': shim('child_process.js'), 'node:sqlite': shim('sqlite.js'),
  'node:async_hooks': shim('async_hooks.js'), 'async_hooks': shim('async_hooks.js'),
  'express': path.join(here, '../../ios/tests/parity/express-shim.js'), 'pdf-parse/lib/pdf-parse.js': shim('pdf-parse.js'),
};
let pako;
try { pako = require.resolve('pako'); } catch { pako = '/opt/npm-tools/node_modules/pako/index.js'; }
map.pako = pako;

const plugin = {
  name: 'node-shims',
  setup(b) {
    b.onResolve({ filter: /.*/ }, (a) => (map[a.path] ? { path: map[a.path] } : undefined));
  },
};
fs.mkdirSync(path.dirname(out), { recursive: true });
await build({
  absWorkingDir: here, entryPoints: [path.join(here, 'entry.js')], bundle: true, outfile: out, format: 'iife', platform: 'browser', target: 'chrome100',
  plugins: [plugin], inject: [shim('globals.js')], logLevel: 'warning', legalComments: 'none',
  banner: { js: '// BillBox engine for Android, built by android/engine/build.mjs from backend/src. Do not edit by hand.' },
});
console.log('engine bundle:', out, fs.statSync(out).size, 'bytes');
