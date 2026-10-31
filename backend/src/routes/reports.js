const router = require('express').Router();
const db = require('../db');
const { h, today } = require('../utils/misc');
const { r2 } = require('../utils/gst');
const R = require('../services/reports');
const { buildXlsx } = require('../utils/xlsx');
const { fyRange, fyList } = require('../utils/fy');

const addDays = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toLocaleDateString('en-CA'); };

const csv = (rows, cols) => [cols.map((c) => c[1]).join(','), ...rows.map((r) => cols.map((c) => JSON.stringify(r[c[0]] ?? '')).join(','))].join('\n');

router.get('/fy', h((req, res) => { const own = require('../utils/fy').booksFy(); res.json({ current: own || fyRange().label, years: fyList(), books_fy: own }); }));
router.get('/reports/dashboard', h((req, res) => res.json(R.dashboard(req.query.fy))));
router.get('/reports/profit', h((req, res) => { const f = fyRange(req.query.fy); res.json(R.profit(req.query.from || f.from, req.query.to || f.to)); }));
router.get('/reports/gst-outward.xlsx', h((req, res) => {
  const d = R.gstOutwardDetail(req.query.month, req.query.fy);
  const co = db.prepare("SELECT value FROM settings WHERE key='company_name'").get();
  const bill = (rows) => ({ total: { invoice_no: 'Total', taxable: r2(rows.reduce((a, r) => a + r.taxable, 0)), cgst: r2(rows.reduce((a, r) => a + r.cgst, 0)), sgst: r2(rows.reduce((a, r) => a + r.sgst, 0)), igst: r2(rows.reduce((a, r) => a + r.igst, 0)), round_off: r2(rows.reduce((a, r) => a + r.round_off, 0)), total: r2(rows.reduce((a, r) => a + r.total, 0)) } });
  const c = (h2, k, w, t) => ({ h: h2, k, w, t });
  const cols = (gst) => [c('Invoice No', 'invoice_no', 16), c('Date', 'date', 12), c('Party Name', 'party', 32), ...(gst ? [c('GSTIN', 'gstin', 20)] : []), c('State', 'state_code', 8),
    c('GST Rates', 'rates', 12), c('Taxable Value', 'taxable', 15, 'num'), c('CGST', 'cgst', 12, 'num'), c('SGST', 'sgst', 12, 'num'), c('IGST (CGST+SGST)', 'igst', 18, 'num'), c('Round Off', 'round_off', 10, 'num'), c('Invoice Value', 'total', 15, 'num')];
  const name = (co && co.value) || 'Company';
  const sheets = [
    { name: 'Summary', title: `GST Outward Supply - ${d.month} - ${name}`, cols: [c('Particulars', 'k', 34), c('Taxable Value', 'taxable', 16, 'num'), c('Tax', 'tax', 16, 'num')],
      rows: [{ k: 'B2B (registered parties)', taxable: d.b2b.taxable, tax: d.b2b.tax }, { k: 'B2C (unregistered / cash)', taxable: d.b2c.taxable, tax: d.b2c.tax }, { k: 'Total outward supplies', taxable: d.totals.taxable, tax: d.totals.tax },
        { k: 'Less: input tax credit (purchases less debit notes)', taxable: null, tax: d.input_credit.total }, { k: 'Net GST payable', taxable: null, tax: d.net_payable }] },
    { name: 'B2B Bills', title: `B2B bills - ${d.month}`, cols: cols(true), rows: d.b2b_bills, ...bill(d.b2b_bills) },
    { name: 'B2C Bills', title: `B2C bills - ${d.month}`, cols: cols(false), rows: d.b2c_bills, ...bill(d.b2c_bills) },
    { name: 'Rate-wise Summary', title: `Tax-rate-wise summary - ${d.month}`, cols: [c('GST Rate %', 'rate', 12, 'num'), c('Invoices', 'invoices', 10, 'int'), c('Taxable Value', 'taxable', 16, 'num'), c('CGST', 'cgst', 14, 'num'), c('SGST', 'sgst', 14, 'num'), c('IGST (CGST+SGST)', 'igst', 18, 'num'), c('Total Tax', 'tax', 14, 'num'), c('Total Value', 'value', 16, 'num')],
      rows: d.rows, total: { rate: 'Total', ...d.totals } },
  ];
  res.set({ 'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'Content-Disposition': `attachment; filename="GST-Outward-${d.month}.xlsx"` });
  res.send(buildXlsx(sheets));
}));
router.get('/reports/gst-outward', h((req, res) => res.json(R.gstOutward(req.query.month, req.query.fy))));
router.get('/reports/book/:type', h((req, res) => res.json(R.book(req.params.type === 'purchase' ? 'purchase' : req.params.type === 'debit' ? 'debit' : 'sales', req.query.from, req.query.to, req.query.fy))));
router.get('/bills', h((req, res) => res.json(R.bills({ type: (req.query.type || 'ALL').toUpperCase(), from: req.query.from, to: req.query.to, q: req.query.q, unpaid: req.query.unpaid === '1', unprinted: req.query.unprinted === '1', fy: req.query.fy }))));

router.get('/reports/expiry', h((req, res) => {
  const days = parseInt(req.query.days) || 90;
  res.json(db.prepare(
    `SELECT b.id, b.batch_no, b.exp_date, b.qty, i.name item_name, i.purchase_price,
       CAST(julianday(b.exp_date) - julianday(?) AS INTEGER) days_left, ROUND(b.qty * i.purchase_price, 2) stock_value
     FROM batches b JOIN items i ON i.id=b.item_id WHERE b.qty>0 AND b.exp_date <= ? AND b.exp_date < '2099-01-01' ORDER BY b.exp_date`).all(today(), addDays(days)));
}));

router.get('/reports/low-stock', h((req, res) => res.json(R.lowStock().rows)));

router.get('/reports/outstanding', h((req, res) => {
  res.json(db.prepare(
    `SELECT p.id, p.name, p.phone, p.type, p.credit_limit, r.name route_name, SUM(l.debit)-SUM(l.credit) balance
     FROM parties p JOIN ledger l ON l.party_id=p.id AND l.date <= ? LEFT JOIN routes r ON r.id=p.route_id
     GROUP BY p.id HAVING ABS(balance) > 0.5 ORDER BY balance DESC`).all(fyRange(req.query.fy).to));
}));

// v1 endpoint kept for compatibility
router.get('/reports/gst-summary', h((req, res) => {
  const from = req.query.from || today().slice(0, 7) + '-01', to = req.query.to || today();
  res.json(db.prepare(
    `SELECT l.gst_rate, ROUND(SUM(l.taxable),2) taxable, ROUND(SUM(l.cgst),2) cgst, ROUND(SUM(l.sgst),2) sgst, ROUND(SUM(l.igst),2) igst
     FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id WHERE i.date BETWEEN ? AND ? GROUP BY l.gst_rate ORDER BY l.gst_rate`).all(from, to));
}));

module.exports = router;
