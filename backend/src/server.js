const express = require('express');
const { HttpError } = require('./utils/misc');
const cors = require('cors');
const db = require('./db');
const backup = require('./services/backup');

const app = express();
app.use(cors());
app.use(express.json({ limit: '40mb' })); // scanned purchase-bill PDFs arrive base64-encoded

app.get('/api/health', (req, res) => res.json({ ok: true }));

// Company-independent routes first, then everything else runs inside the selected company's database.
app.use('/api', require('./routes/companies'));
app.use('/api', require('./routes/backup'));
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
  // a failure the app itself reports (HttpError, e.g. "Cannot write to the backup folder") keeps its reason in `detail`
  const detail = status === 500 && err instanceof HttpError ? err.message : undefined;
  res.status(status).json({ error: status === 500 ? 'Server error' : err.message, code: err.code, detail });
});

const PORT = process.env.PORT || 3000;
// Bind to localhost only: this is a single-machine desktop deployment.
app.listen(PORT, '127.0.0.1', () => {
  console.log(`Distributor API on http://127.0.0.1:${PORT}`);
  backup.startScheduler();
});
