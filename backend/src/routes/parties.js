const router = require('express').Router();
const db = require('../db');
const { h, HttpError, blank, today, normDays } = require('../utils/misc');
const { r2 } = require('../utils/gst');
const { recordVoucher, getVoucher, deleteLedgerEntry } = require('../services/vouchers');
const Sheet = require('../services/paymentSheet');

const { fyRange } = require('../utils/fy');
const BAL = `COALESCE((SELECT SUM(debit)-SUM(credit) FROM ledger l WHERE l.party_id=p.id),0)`;
// balance as it stood at the end of the selected financial year
const BAL_AT = `COALESCE((SELECT SUM(debit)-SUM(credit) FROM ledger l WHERE l.party_id=p.id AND l.date <= @to),0)`;

// ?kind=CUSTOMER | SUPPLIER (default: all).  balance > 0 = they owe us, balance < 0 = we owe them.
router.get('/parties', h((req, res) => {
  const q = `%${(req.query.q || '').trim()}%`;
  const kind = req.query.kind === 'SUPPLIER' ? `AND p.type = 'SUPPLIER'` : req.query.kind === 'CUSTOMER' ? `AND p.type <> 'SUPPLIER'` : '';
  res.json(db.prepare(
    `SELECT p.*, ${BAL_AT} balance, r.name route_name FROM parties p LEFT JOIN routes r ON r.id=p.route_id
     WHERE p.active=1 ${kind} AND (p.name LIKE @q OR p.phone LIKE @q OR p.gstin LIKE @q OR COALESCE(p.mobiles,'') LIKE @q OR COALESCE(p.tel,'') LIKE @q) ORDER BY p.name`
  ).all({ q, to: fyRange(req.query.fy).to }));
}));

/** Accepts route_id OR new_route {name, salesman_id, day_of_week}: the route is created and assigned in the same transaction. */
function resolveRoute(b) {
  const nr = b.new_route;
  if (nr && blank(nr.name)) {
    const days = normDays(nr.days !== undefined ? nr.days : nr.day_of_week);
    const info = db.prepare('INSERT INTO routes(name,salesman_id,day_of_week,days) VALUES(?,?,?,?)')
      .run(String(nr.name).trim(), blank(nr.salesman_id), days ? parseInt(days) : null, days);
    return Number(info.lastInsertRowid);
  }
  return blank(b.route_id);
}

const GSTIN_RE = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;

/** Cleans and validates the party fields (shared by add and edit). Supplier details: tel, phone, several mobiles, FSSAI, PAN, email. */
function cleanParty(b, cur) {
  const get = (k) => (b[k] !== undefined ? b[k] : cur ? cur[k] : undefined);
  const txt = (k, max = 200) => { const v = get(k); return blank(v) === null ? null : String(v).trim().slice(0, max); };
  const o = { name: String(get('name') ?? '').trim().replace(/\s+/g, ' ') };
  if (!o.name) throw new HttpError(400, 'Party name is required');
  o.address = txt('address', 400);
  o.gstin = txt('gstin', 15) && txt('gstin', 15).toUpperCase().replace(/\s+/g, '');
  if (o.gstin && !GSTIN_RE.test(o.gstin)) throw new HttpError(400, `GSTIN "${o.gstin}" is not valid (15 characters, e.g. 09ABCDE1234F1Z5)`);
  o.state_code = txt('state_code', 2) || (o.gstin ? o.gstin.slice(0, 2) : null);
  if (o.state_code && !/^\d{2}$/.test(o.state_code)) throw new HttpError(400, 'State code must be 2 digits, e.g. 09');
  o.pan = (txt('pan', 10) || (o.gstin ? o.gstin.slice(2, 12) : null) || null);
  if (o.pan) { o.pan = o.pan.toUpperCase(); if (!/^[A-Z]{5}\d{4}[A-Z]$/.test(o.pan)) throw new HttpError(400, 'PAN must look like ABCDE1234F'); }
  o.fssai = txt('fssai', 14);
  if (o.fssai && !/^\d{14}$/.test(o.fssai)) throw new HttpError(400, 'FSSAI number must be 14 digits');
  o.email = txt('email', 120);
  if (o.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(o.email)) throw new HttpError(400, 'Email address is not valid');
  o.tel = txt('tel', 40);
  o.phone = txt('phone', 40);
  const mob = get('mobiles');
  const list = (Array.isArray(mob) ? mob : String(mob ?? '').split(/[,;\n]+/)).map((x) => String(x).trim()).filter(Boolean);
  o.mobiles = [...new Set(list)].join(', ') || null;
  o.type = ['RETAILER', 'WHOLESALER', 'SUPPLIER'].includes(get('type')) ? get('type') : 'RETAILER';
  o.price_tier = ['RETAIL', 'WHOLESALE', 'MRP'].includes(get('price_tier')) ? get('price_tier') : 'RETAIL';
  const cl = Number(get('credit_limit') || 0), cd = Math.floor(Number(get('credit_days') || 0));
  if (!(cl >= 0) || !(cd >= 0)) throw new HttpError(400, 'Credit limit and credit days cannot be negative');
  o.credit_limit = cl; o.credit_days = cd;
  return o;
}

router.post('/parties', h((req, res) => {
  const b = req.body || {};
  const o = cleanParty(b, null);
  const id = db.transaction(() => {
    o.route_id = resolveRoute(b);
    const info = db.prepare(
      `INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,fssai,pan,email,type,price_tier,credit_limit,credit_days,route_id)
       VALUES(@name,@gstin,@state_code,@phone,@tel,@mobiles,@address,@fssai,@pan,@email,@type,@price_tier,@credit_limit,@credit_days,@route_id)`
    ).run(o);
    const pid = Number(info.lastInsertRowid);
    const opening = Number(b.opening_balance) || 0;   // positive = they owe us, negative = we owe them
    if (opening !== 0) {
      db.prepare('INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)')
        .run(pid, today(), 'OPENING', 'OPENING', opening > 0 ? opening : 0, opening < 0 ? -opening : 0, 'Opening balance');
    }
    return pid;
  })();
  res.status(201).json({ id });
}));

router.put('/parties/:id', h((req, res) => {
  const cur = db.prepare('SELECT * FROM parties WHERE id=?').get(req.params.id);
  if (!cur) throw new HttpError(404, 'Party not found');
  const b = req.body || {};
  const o = cleanParty(b, cur);
  db.transaction(() => {
    o.route_id = resolveRoute({ ...b, route_id: 'route_id' in b ? b.route_id : cur.route_id });
    db.prepare(
      `UPDATE parties SET name=@name,gstin=@gstin,state_code=@state_code,phone=@phone,tel=@tel,mobiles=@mobiles,address=@address,
         fssai=@fssai,pan=@pan,email=@email,type=@type,price_tier=@price_tier,credit_limit=@credit_limit,credit_days=@credit_days,route_id=@route_id WHERE id=@id`
    ).run({ ...o, id: cur.id });
  })();
  res.json({ ok: true });
}));

/** A party with any history is archived (hidden, books stay correct); an unused one is removed. */
router.delete('/parties/:id', h((req, res) => {
  const p = db.prepare('SELECT * FROM parties WHERE id=?').get(req.params.id);
  if (!p) throw new HttpError(404, 'Party not found');
  const used = db.prepare(
    `SELECT (SELECT COUNT(*) FROM ledger WHERE party_id=@i) + (SELECT COUNT(*) FROM invoices WHERE party_id=@i) + (SELECT COUNT(*) FROM purchases WHERE party_id=@i) + (SELECT COUNT(*) FROM debit_notes WHERE party_id=@i) n`
  ).get({ i: p.id }).n;
  if (used) { db.prepare('UPDATE parties SET active=0 WHERE id=?').run(p.id); return res.json({ result: 'archived' }); }
  db.prepare('DELETE FROM parties WHERE id=?').run(p.id);
  res.json({ result: 'deleted' });
}));

router.get('/parties/:id/ledger', h((req, res) => {
  const party = db.prepare('SELECT * FROM parties WHERE id=?').get(req.params.id);
  if (!party) throw new HttpError(404, 'Party not found');
  // Selected financial year only; everything before it is carried in as one opening-balance line.
  const fy = fyRange(req.query.fy);
  const open = r2(db.prepare('SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=? AND date < ?').get(party.id, fy.from).b);
  let run = open;
  const rows = db.prepare('SELECT * FROM ledger WHERE party_id=? AND date BETWEEN ? AND ? ORDER BY date, id').all(party.id, fy.from, fy.to)
    .map((r) => ({ ...r, balance: (run = r2(run + r.debit - r.credit)) }));
  res.json({ party, fy: fy.label, opening_balance: open, balance: run, entries: rows });
}));

// ---------- vouchers: money received from / paid to a party ----------
router.get('/vouchers/:no', h((req, res) => res.json(getVoucher(req.params.no))));
router.post('/vouchers', h((req, res) => res.status(201).json(recordVoucher(req.body))));
router.delete('/ledger/:id', h((req, res) => res.json(deleteLedgerEntry(Number(req.params.id)))));
router.post('/receipts/sheet/parse', h((req, res) => res.json(Sheet.parseSheet(req.body))));
router.post('/receipts/sheet', h((req, res) => res.status(201).json(Sheet.saveSheet(req.body))));
router.post('/receipts', h((req, res) => res.status(201).json(recordVoucher({ ...req.body, direction: 'RECEIVED' }))));  // v1 compatibility

router.get('/receipts', h((req, res) => {
  res.json(db.prepare(
    `SELECT r.*, p.name party_name, s.name salesman_name FROM receipts r JOIN parties p ON p.id=r.party_id
     LEFT JOIN salesmen s ON s.id=r.salesman_id WHERE r.date=? ORDER BY r.id DESC`).all(req.query.date || today()));
}));

module.exports = router;
