const router = require('express').Router();
const db = require('../db');
const { h, HttpError, blank, today, normDays } = require('../utils/misc');
const { r2 } = require('../utils/gst');

router.get('/salesmen', h((req, res) => {
  res.json(db.prepare('SELECT * FROM salesmen WHERE active=1 ORDER BY name').all());
}));
router.post('/salesmen', h((req, res) => {
  if (!blank(req.body.name)) throw new HttpError(400, 'Name is required');
  const info = db.prepare('INSERT INTO salesmen(name,phone,monthly_target) VALUES(?,?,?)')
    .run(req.body.name.trim(), blank(req.body.phone), Number(req.body.monthly_target) || 0);
  res.status(201).json({ id: Number(info.lastInsertRowid) });
}));
router.put('/salesmen/:id', h((req, res) => {
  const cur = db.prepare('SELECT * FROM salesmen WHERE id=?').get(req.params.id);
  if (!cur) throw new HttpError(404, 'Salesman not found');
  const b = { ...cur, ...req.body };
  db.prepare('UPDATE salesmen SET name=?,phone=?,monthly_target=?,active=? WHERE id=?')
    .run(b.name, blank(b.phone), Number(b.monthly_target) || 0, b.active ? 1 : 0, cur.id);
  res.json({ ok: true });
}));
/** Delete: the salesman leaves the list and their routes are unassigned; bills and receipts keep the name (history). */
router.delete('/salesmen/:id', h((req, res) => {
  const cur = db.prepare('SELECT * FROM salesmen WHERE id=?').get(req.params.id);
  if (!cur) throw new HttpError(404, 'Salesman not found');
  db.transaction(() => {
    db.prepare('UPDATE routes SET salesman_id=NULL WHERE salesman_id=?').run(cur.id);
    db.prepare('UPDATE salesmen SET active=0 WHERE id=?').run(cur.id);
  })();
  res.json({ ok: true });
}));

/** Merge: this salesman's bills, receipts and routes move to `into`, then this salesman leaves the list. */
router.post('/salesmen/:id/merge', h((req, res) => {
  const from = db.prepare('SELECT * FROM salesmen WHERE id=?').get(req.params.id);
  const into = db.prepare('SELECT * FROM salesmen WHERE id=?').get(req.body && req.body.into);
  if (!from || !into) throw new HttpError(404, 'Salesman not found');
  if (from.id === into.id) throw new HttpError(400, 'Choose another salesman to merge into');
  const moved = {};
  db.transaction(() => {
    for (const t of ['invoices', 'receipts', 'routes']) {
      moved[t] = db.prepare(`UPDATE ${t} SET salesman_id=? WHERE salesman_id=?`).run(into.id, from.id).changes;
    }
    if (!into.monthly_target && from.monthly_target) db.prepare('UPDATE salesmen SET monthly_target=? WHERE id=?').run(from.monthly_target, into.id);
    db.prepare('UPDATE salesmen SET active=0 WHERE id=?').run(from.id);
  })();
  res.json({ ok: true, into: into.id, moved });
}));

router.get('/routes', h((req, res) => {
  res.json(db.prepare(
    `SELECT r.*, s.name salesman_name, (SELECT COUNT(*) FROM parties p WHERE p.route_id=r.id AND p.active=1) outlets
     FROM routes r LEFT JOIN salesmen s ON s.id=r.salesman_id ORDER BY r.days, r.name`
  ).all());
}));
router.post('/routes', h((req, res) => {
  const b = req.body;
  if (!blank(b.name)) throw new HttpError(400, 'Route name is required');
  const days = normDays(b.days !== undefined ? b.days : b.day_of_week);
  const info = db.prepare('INSERT INTO routes(name,salesman_id,day_of_week,days) VALUES(?,?,?,?)')
    .run(b.name.trim(), blank(b.salesman_id), days ? parseInt(days) : null, days);
  res.status(201).json({ id: Number(info.lastInsertRowid) });
}));

/** Outlets without a route get the route sharing a word with their name or address: {apply: false} previews, {apply: true, party_ids?} assigns. */
router.post('/routes/auto-assign', h((req, res) => {
  const b = req.body || {};
  res.json(require('../utils/routematch').autoAssignRoutes(db, { apply: !!b.apply, party_ids: b.party_ids, assignments: b.assignments }));
}));

router.put('/routes/:id', h((req, res) => {
  const cur = db.prepare('SELECT * FROM routes WHERE id=?').get(req.params.id);
  if (!cur) throw new HttpError(404, 'Route not found');
  const b = { ...cur, ...req.body };
  const days = normDays(req.body.days !== undefined ? req.body.days : req.body.day_of_week !== undefined ? req.body.day_of_week : cur.days);
  db.prepare('UPDATE routes SET name=?,salesman_id=?,day_of_week=?,days=? WHERE id=?')
    .run(b.name, blank(b.salesman_id), days ? parseInt(days) : null, days, cur.id);
  res.json({ ok: true });
}));
router.delete('/routes/:id', h((req, res) => {
  db.transaction(() => {
    db.prepare('UPDATE parties SET route_id=NULL WHERE route_id=?').run(req.params.id);   // outlets stay, just unassigned
    db.prepare('DELETE FROM routes WHERE id=?').run(req.params.id);
  })();
  res.json({ ok: true });
}));

/** Beat plan: outlets to visit for a salesman on a weekday (default today), with dues to collect. */
router.get('/salesmen/:id/beat', h((req, res) => {
  const day = req.query.day !== undefined ? parseInt(req.query.day) : new Date().getDay();
  const rows = db.prepare(
    `SELECT p.id, p.name, p.phone, p.address, p.credit_limit, r.name route_name,
       COALESCE((SELECT SUM(debit)-SUM(credit) FROM ledger l WHERE l.party_id=p.id AND l.date <= @to),0) outstanding,
       (SELECT MAX(date) FROM invoices i WHERE i.party_id=p.id AND i.date <= @to) last_order
     FROM parties p JOIN routes r ON r.id=p.route_id
     WHERE r.salesman_id=@sm AND (',' || COALESCE(r.days, CAST(r.day_of_week AS TEXT), '') || ',') LIKE '%,' || @day || ',%' AND p.active=1 ORDER BY r.name, p.name`
  ).all({ sm: req.params.id, day: String(day), to: require('../utils/fy').fyRange(req.query.fy).to });   // as text: node:sqlite binds numbers as REAL, so 1 would match as '1.0' and no outlet would ever show
  res.json({ day, outlets: rows, total_outstanding: r2(rows.reduce((a, r) => a + r.outstanding, 0)) });
}));

/** Month target vs achievement + today's van-sales cash-up. */
router.get('/salesmen/:id/performance', h((req, res) => {
  const sm = db.prepare('SELECT * FROM salesmen WHERE id=?').get(req.params.id);
  if (!sm) throw new HttpError(404, 'Salesman not found');
  const fyr = require('../utils/fy').fyRange(req.query.fy);
  const cl = (d) => (d < fyr.from ? fyr.from : d > fyr.to ? fyr.to : d);
  const month = (req.query.month || cl(today()).slice(0, 7)); // YYYY-MM
  const date = req.query.date || cl(today());
  const val = (sql, ...a) => db.prepare(sql).get(...a);

  const sales = val(`SELECT COALESCE(SUM(total),0) v, COUNT(*) n FROM invoices WHERE salesman_id=? AND substr(date,1,7)=?`, sm.id, month);
  const coll = val(`SELECT COALESCE(SUM(amount),0) v FROM receipts WHERE salesman_id=? AND substr(date,1,7)=?`, sm.id, month);
  const dayInv = val(
    `SELECT COUNT(*) n, COALESCE(SUM(total),0) total, COALESCE(SUM(paid),0) paid FROM invoices WHERE salesman_id=? AND date=?`, sm.id, date);
  const byMode = db.prepare(`SELECT mode, COALESCE(SUM(amount),0) amount FROM receipts WHERE salesman_id=? AND date=? GROUP BY mode`).all(sm.id, date);

  res.json({
    salesman: sm, month, target: sm.monthly_target,
    sales: r2(sales.v), invoices: sales.n, collections: r2(coll.v),
    achievement_pct: sm.monthly_target > 0 ? r2((sales.v / sm.monthly_target) * 100) : null,
    day: { date, bills: dayInv.n, sales: r2(dayInv.total), credit_given: r2(dayInv.total - dayInv.paid), collected_by_mode: byMode },
  });
}));

module.exports = router;
