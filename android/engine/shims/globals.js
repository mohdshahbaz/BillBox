// Node globals the engine relies on: Buffer, process (data folder from the app), __dirname, fetch through the app.
import { Buffer as B } from './buffer.js';
import { fetchShim } from './fetch.js';
export const Buffer = B;
export const process = {
  env: { DATA_DIR: globalThis.AndroidHost.dataDir() }, pid: 1, platform: 'android', argv: [], versions: {},
  cwd: () => '/', nextTick: (f, ...a) => Promise.resolve().then(() => f(...a)),
};
export const __dirname = '/engine';
globalThis.fetch = fetchShim;
