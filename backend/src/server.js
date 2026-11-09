const express = require('express');
const { HttpError } = require('./utils/misc');
const cors = require('cors');
const db = require('./db');
const backup = require('./services/backup');

const app = express();
app.use(cors());
app.use(express.json({ limit: '40mb' })); // scanned purchase-bill PDFs arrive base64-encoded
// every answer is live data: never kept in a cache (the Mac app's web cache otherwise showed old prices and parties)
app.set('etag', false);
app.use('/api', (req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });

app.get('/api/health', (req, res) => res.json({ ok: true }));

// Licence: after the trial, without a licence, the books are read-only (services/license.js)
const license = require('./services/license');
app.use('/api', (req, res, next) => (license.allows(req.method, req.path) ? next() : next(license.blocked())));

// Company-independent routes first, then everything else runs inside the selected company's database.
app.use('/api', require('./routes/license'));
app.use('/api', require('./routes/companies'));
app.use('/api', require('./routes/backup'));
app.use('/api', require('./routes/sync'));
app.use('/api', require('./routes/update'));
app.use('/api', db.middleware);
for (const r of ['items', 'parties', 'salesmen', 'invoices', 'purchases', 'debitNotes', 'import', 'reports']) app.use('/api', require(`./routes/${r}`));

app.use((req, res) => res.status(404).json({ error: 'Not found' }));
app.use((err, req, res, next) => {
  // a constraint failure (a name or batch that already exists): node:sqlite reports it as ERR_SQLITE_ERROR with errcode 19
  // (or an extended code whose low byte is 19), better-sqlite3 as SQLITE_CONSTRAINT_*
  if (err && (String(err.code || '').startsWith('SQLITE_CONSTRAINT') || (err.code === 'ERR_SQLITE_ERROR' && (Number(err.errcode) & 255) === 19))) {
    const msg = /UNIQUE/.test(err.message) ? 'That value already exists (for example a duplicate batch number).' : 'Invalid reference or missing value.';
    return res.status(409).json({ error: msg });
  }
  const status = err.status || 500;
  if (status === 500) console.error(err);
  // a failure the app itself reports (HttpError, e.g. "Cannot write to the backup folder") keeps its reason in `detail`;
  // any other failure says what went wrong too, so "Server error" on a screen can be traced
  const detail = status === 500 ? String((err && err.message) || err) : undefined;
  res.status(status).json({ error: status === 500 ? 'Server error' : err.message, code: err.code, detail });
});

const PORT = process.env.PORT || 3000;
// Bind to localhost only: this is a single-machine desktop deployment.
const server = app.listen(PORT, '127.0.0.1', () => {
  console.log(`Distributor API on http://127.0.0.1:${PORT}`);
  backup.startScheduler();
});
// Keep idle connections open longer than the apps do: with Node's 5-second default, an app reusing a connection the server
// had just closed got "Cannot reach the server" at random.
server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;

// The Linux and Windows apps start this server themselves and pass their process id: when the app has gone (closed,
// crashed or killed), the server stops too, so it never keeps the books open in the background.
const parent = Number(process.env.BILLBOX_PARENT_PID || 0);
if (parent > 0) {
  setInterval(() => {
    try { process.kill(parent, 0); } catch (e) { if (e.code !== 'EPERM') { console.log('BillBox closed: stopping.'); process.exit(0); } }
  }, 2000).unref();
}
