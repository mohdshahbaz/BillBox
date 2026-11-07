// One device for test/sync.js (a separate process, so it has its own books): runs the steps the test sends it.
const db = require('../src/db');
const S = require('../src/services/sync');
const billing = require('../src/services/billing');
process.on('message', async ({ id, code }) => {
  try {
    const fn = new Function('db', 'S', 'billing', 'require', `return (async () => { ${code} })()`);
    const r = await fn(db, S, billing, require);
    process.send({ id, r: r === undefined ? null : JSON.parse(JSON.stringify(r)) });
  } catch (e) { process.send({ id, err: e.message + '\n' + e.stack }); }
});
process.send({ ready: true });
