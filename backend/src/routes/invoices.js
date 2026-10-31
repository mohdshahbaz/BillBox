const router = require('express').Router();
const EWB = require('../services/ewayBill');
const db = require('../db');
const { h, HttpError, today, peekNo, setNext, SERIES } = require('../utils/misc');
const { buildInvoice, createInvoice, updateInvoice, deleteInvoice, getInvoice, settings } = require('../services/billing');
const { invoiceHtml } = require('../views/invoiceHtml');

// Live totals while the operator is typing: same engine as save, but nothing is written.
router.post('/invoices/preview', h((req, res) => {
  const inv = buildInvoice(req.body);
  res.json({
    lines: inv.display, subtotal: inv.subtotal, discount: inv.discount, taxable: inv.taxable,
    cgst: inv.cgst, sgst: inv.sgst, igst: inv.igst, round_off: inv.round_off, total: inv.total,
    supply: inv.intra ? 'INTRA' : 'INTER', tier: inv.tier,
  });
}));

router.post('/invoices', h((req, res) => {
  const id = createInvoice(req.body);
  const inv = getInvoice(id);
  res.status(201).json({ id, invoice_no: inv.invoice_no, total: inv.total, paid: inv.paid });
}));

router.put('/invoices/:id', h((req, res) => {
  const id = updateInvoice(Number(req.params.id), req.body || {});
  const inv = getInvoice(id);
  res.json({ id, invoice_no: inv.invoice_no, total: inv.total, paid: inv.paid });
}));

/** Marks bills as printed (or not): body { ids: [..], printed?: true }. Bills kept to print later have printed = 0. */
router.post('/invoices/printed', h((req, res) => {
  const b = req.body || {};
  const ids = (Array.isArray(b.ids) ? b.ids : []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (!ids.length) throw new HttpError(400, 'Choose the bills');
  const flag = b.printed === false || b.printed === 0 ? 0 : 1;
  const st = db.prepare('UPDATE invoices SET printed=? WHERE id=?');
  let updated = 0;
  db.transaction(() => { for (const id of ids) updated += Number(st.run(flag, id).changes); })();
  res.json({ updated, printed: flag });
}));

router.delete('/invoices/:id', h((req, res) => res.json(deleteInvoice(Number(req.params.id)))));

router.get('/invoices', h((req, res) => {
  const date = req.query.date || today();
  res.json(db.prepare(
    `SELECT i.id,i.invoice_no,i.date,i.total,i.paid,i.pay_mode,i.sale_type, p.name party_name, s.name salesman_name
     FROM invoices i LEFT JOIN parties p ON p.id=i.party_id LEFT JOIN salesmen s ON s.id=i.salesman_id
     WHERE i.date=? ORDER BY i.id DESC`
  ).all(date));
}));

router.get('/invoices/:id', h((req, res) => {
  const inv = getInvoice(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  res.json(inv);
}));

// e-way bill: transport details (saved or guessed), the portal's JSON file, and the number the portal gives
router.get('/invoices/:id/ewaybill', h((req, res) => res.json(EWB.details(req.params.id))));
router.post('/invoices/:id/ewaybill', h((req, res) => res.json(EWB.build(req.params.id, req.body || {}))));
router.put('/invoices/:id/ewaybill', h((req, res) => res.json(EWB.saveNumber(req.params.id, req.body || {}))));

router.get('/invoices/:id/print', h((req, res) => {
  const inv = getInvoice(req.params.id);
  if (!inv) throw new HttpError(404, 'Invoice not found');
  res.type('html').send(invoiceHtml(inv, settings()));
}));

/** Settings › Numbering: each series' next number and the last one used, and setting where the count carries on. */
const numberingRow = (x) => ({ series: x.prefix, label: x.label, digits: x.digits, with_fy: x.withFy, last_no: x.last_no, next_no: x.next_no, next: x.next });
router.get('/numbering', h((req, res) => res.json({ series: Object.keys(SERIES).map((k) => numberingRow(peekNo(k, req.query.date || undefined))) })));
router.put('/numbering', h((req, res) => {
  const b = req.body || {};
  res.json(numberingRow(db.transaction(() => setNext(String(b.series || ''), b.next, b.date || undefined))()));
}));

router.get('/settings', h((req, res) => res.json(settings())));
router.put('/settings', h((req, res) => {
  const up = db.prepare('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value');
  const b = req.body || {};
  if (b.low_stock_qty !== undefined && !(Number(b.low_stock_qty) >= 0)) throw new HttpError(400, 'Low-stock level must be 0 or more');
  db.transaction(() => { for (const [k, v] of Object.entries(b)) up.run(k, String(v)); })();
  res.json(settings());
}));

module.exports = router;
