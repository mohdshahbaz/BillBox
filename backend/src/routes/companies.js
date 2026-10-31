const router = require('express').Router();
const db = require('../db');
const { h, HttpError, blank } = require('../utils/misc');
const Y = require('../services/years');

const reg = db.registry;
const FIELDS = ['company_gstin', 'state_code', 'company_address', 'company_phone', 'invoice_terms'];
const GSTIN = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;

const profile = (c) => db.withCompany(c.id, () => {
  const o = { id: c.id, name: c.name };
  for (const r of db.prepare('SELECT key,value FROM settings').all()) o[r.key] = r.value;
  o.fy = c.fy || null;
  return o;
});

function validate(b, creating) {
  if (creating && !blank(b.name)) throw new HttpError(400, 'Company name is required');
  if (blank(b.company_gstin) && !GSTIN.test(String(b.company_gstin).toUpperCase())) throw new HttpError(400, 'GSTIN format is not valid');
  if (blank(b.state_code) && !/^\d{2}$/.test(String(b.state_code))) throw new HttpError(400, 'State code must be 2 digits, e.g. 09');
}

router.get('/companies', h((req, res) => {
  const rows = reg.prepare('SELECT * FROM companies WHERE active=1 ORDER BY id').all();
  const last = reg.prepare("SELECT value FROM app_settings WHERE key='last_company'").get();
  res.json({ last_used: last ? Number(last.value) : null, companies: rows.map(profile) });
}));

router.post('/companies', h((req, res) => {
  const b = req.body;
  validate(b, true);
  const s = {};
  for (const f of FIELDS) if (blank(b[f]) !== null) s[f] = f === 'company_gstin' ? String(b[f]).toUpperCase() : b[f];
  const id = db.createCompany({ name: b.name.trim(), ...s });
  res.status(201).json({ id });
}));

router.put('/companies/:id', h((req, res) => {
  const c = db.companyRow(Number(req.params.id));
  if (!c) throw new HttpError(404, 'Company not found');
  const b = req.body;
  validate(b, false);
  db.withCompany(c.id, () => {
    const up = db.prepare('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value');
    if (blank(b.name)) up.run('company_name', b.name.trim());
    for (const f of FIELDS) if (b[f] !== undefined) up.run(f, f === 'company_gstin' ? String(b[f]).toUpperCase() : String(b[f]));
  });
  if (blank(b.name)) Y.renameAll(c.name, b.name.trim());   // every year's books keep the same name
  res.json({ ok: true });
}));

// a new financial year's books for this company: body { fy: "2027-28", carry: true | false }
router.post('/companies/:id/years', h((req, res) => res.status(201).json(Y.addYear(Number(req.params.id), req.body || {}))));

router.post('/companies/:id/activate', h((req, res) => {
  if (!db.companyRow(Number(req.params.id))) throw new HttpError(404, 'Company not found');
  reg.prepare("INSERT INTO app_settings(key,value) VALUES('last_company',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(String(req.params.id));
  res.json({ ok: true });
}));

module.exports = router;
