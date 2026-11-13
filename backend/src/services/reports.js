const db = require('../db');
const { r2 } = require('../utils/gst');
const { today } = require('../utils/misc');

const addDays = (n, base = new Date()) => { const d = new Date(base); d.setDate(d.getDate() + n); return d.toLocaleDateString('en-CA'); };
const one = (sql, ...a) => db.prepare(sql).get(...a);
const monthOf = (d) => d.slice(0, 7);
/** A YYYY-MM month as a date range, so queries use the date index (substr(date,1,7)=? scanned every row). */
const monthSpan = (m) => [m + '-01', m + '-31'];

const { fyRange } = require('../utils/fy');
const clamp = (d, r) => (d < r.from ? r.from : d > r.to ? r.to : d);

/**
 * Profit = selling value (ex-GST, after discounts) minus what the sold pieces cost (batch purchase price, else the item's
 * purchase price). Free pieces count as cost. Lines whose cost is unknown are counted and reported, not guessed.
 */
const PROFIT_COLS = `COALESCE(SUM(l.taxable),0) revenue,
            COALESCE(SUM((l.qty+l.free_qty) * COALESCE(NULLIF(b.purchase_price,0), NULLIF(it.purchase_price,0), 0)),0) cost,
            COALESCE(SUM(CASE WHEN COALESCE(NULLIF(b.purchase_price,0), NULLIF(it.purchase_price,0), 0)=0 THEN 1 ELSE 0 END),0) unknown_cost_lines
     FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id JOIN items it ON it.id=l.item_id LEFT JOIN batches b ON b.id=l.batch_id
     WHERE i.date BETWEEN ? AND ?`;
const profitOf = (r) => {
  const p = r2(r.revenue - r.cost);
  return { revenue: r2(r.revenue), cost: r2(r.cost), profit: p, margin_pct: r.revenue > 0 ? r2((p / r.revenue) * 100) : 0, unknown_cost_lines: r.unknown_cost_lines };
};
function profit(from, to) {
  return profitOf(one(`SELECT ${PROFIT_COLS}`, from, to));
}
/** SUM(col) per key (date or month) between two dates, one query instead of one per day / month. */
const sumsBy = (table, col, key, from, to) =>
  new Map(db.prepare(`SELECT ${key} k, COALESCE(SUM(${col}),0) v FROM ${table} WHERE date BETWEEN ? AND ? GROUP BY k`).all(from, to).map((r) => [r.k, r2(r.v)]));

const sumBetween = (table, col, from, to) => r2(one(`SELECT COALESCE(SUM(${col}),0) v FROM ${table} WHERE date BETWEEN ? AND ?`, from, to).v);

/** Settings › Stock: how many days ahead the dashboard warns about expiry (1 to 365, default 30). */
function expiryDays() {
  const r = db.prepare("SELECT value FROM settings WHERE key='expiry_days'").get();
  const n = parseInt(r ? r.value : '', 10);
  return n >= 1 && n <= 365 ? n : 30;
}

function dashboard(fyLabel) {
  const fy = fyRange(fyLabel);
  const t = clamp(today(), fy);                 // "today" = the last day of a finished year
  const m = monthOf(t), mFrom = m + '-01';
  const taxOut = (f, to) => one(`SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM invoices WHERE date BETWEEN ? AND ?`, f, to).v;
  // input tax credit: GST paid on purchases less the GST on goods sent back (debit notes)
  const taxIn = (f, to) => one(`SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM purchases WHERE date BETWEEN ? AND ?`, f, to).v
    - one(`SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM debit_notes WHERE date BETWEEN ? AND ?`, f, to).v;
  const bal = one(`SELECT COALESCE(SUM(CASE WHEN b>0 THEN b ELSE 0 END),0) rec, COALESCE(-SUM(CASE WHEN b<0 THEN b ELSE 0 END),0) pay
                   FROM (SELECT SUM(debit)-SUM(credit) b FROM ledger WHERE date <= ? GROUP BY party_id)`, fy.to);
  // last 14 days and the 12 months of the year: grouped queries (the same sums as one query per day / month)
  const s0 = addDays(-13, new Date(t + 'T12:00:00'));
  const daySales = sumsBy('invoices', 'total', 'date', s0, t), dayBuys = sumsBy('purchases', 'total', 'date', s0, t);
  const series = [];
  for (let i = 13; i >= 0; i--) {
    const d = addDays(-i, new Date(t + 'T12:00:00'));
    if (d < fy.from) continue;
    series.push({ date: d, sales: daySales.get(d) || 0, purchases: dayBuys.get(d) || 0 });
  }
  const ym = (k) => `${fy.start_year + (k + 3 >= 12 ? 1 : 0)}-${String(((k + 3) % 12) + 1).padStart(2, '0')}`;
  const mFirst = ym(0) + '-01', mLast = ym(11) + '-31';
  const mSales = sumsBy('invoices', 'total', 'substr(date,1,7)', mFirst, mLast), mBuys = sumsBy('purchases', 'total', 'substr(date,1,7)', mFirst, mLast);
  const monthly = [];
  for (let k = 0; k < 12; k++) {
    const m = ym(k);
    monthly.push({ month: m, sales: mSales.get(m) || 0, purchases: mBuys.get(m) || 0, profit: profit(m + '-01', m + '-31').profit });
  }
  const low = lowStock(8);
  const fyProfit = profit(fy.from, fy.to), monthProfit = profit(mFrom, t), dayProfit = profit(t, t);
  return {
    fy: fy.label, fy_from: fy.from, fy_to: fy.to, is_current: fy.current, as_of: t, month: m,
    today_sales: sumBetween('invoices', 'total', t, t),
    today_bills: one('SELECT COUNT(*) v FROM invoices WHERE date=?', t).v,
    today_profit: dayProfit.profit,
    month_sales: sumBetween('invoices', 'total', mFrom, t),
    month_bills: one('SELECT COUNT(*) v FROM invoices WHERE date BETWEEN ? AND ?', mFrom, t).v,
    month_profit: monthProfit.profit,
    month_purchases: sumBetween('purchases', 'total', mFrom, t),
    month_purchase_bills: one('SELECT COUNT(*) v FROM purchases WHERE date BETWEEN ? AND ?', mFrom, t).v,
    fy_sales: sumBetween('invoices', 'total', fy.from, fy.to),
    fy_bills: one('SELECT COUNT(*) v FROM invoices WHERE date BETWEEN ? AND ?', fy.from, fy.to).v,
    fy_purchases: sumBetween('purchases', 'total', fy.from, fy.to),
    fy_collections: sumBetween('receipts', 'amount', fy.from, fy.to),
    fy_profit: fyProfit.profit, fy_margin_pct: fyProfit.margin_pct, fy_cost: fyProfit.cost, fy_revenue: fyProfit.revenue,
    profit_unknown_cost_lines: fyProfit.unknown_cost_lines,
    today_collections: sumBetween('receipts', 'amount', t, t),
    receivable: r2(bal.rec), payable: r2(bal.pay),
    gst_output: r2(taxOut(mFrom, t)), gst_input: r2(taxIn(mFrom, t)), gst_liability: r2(taxOut(mFrom, t) - taxIn(mFrom, t)),
    fy_gst_liability: r2(taxOut(fy.from, fy.to) - taxIn(fy.from, fy.to)),
    low_stock_count: low.total, low_stock: low.rows, low_stock_qty: low.threshold,
    // Settings › Stock › expiry warning (days); the key keeps its old name
    expiring_30d: one('SELECT COUNT(*) v FROM batches WHERE qty>0 AND exp_date BETWEEN ? AND ?', today(), addDays(expiryDays())).v,
    expiry_days: expiryDays(),
    expired_stock: one('SELECT COUNT(*) v FROM batches WHERE qty>0 AND exp_date<?', today()).v,
    top_dues: db.prepare(
      `SELECT p.id, p.name, SUM(l.debit)-SUM(l.credit) balance FROM parties p JOIN ledger l ON l.party_id=p.id AND l.date <= ?
       GROUP BY p.id HAVING balance > 0.5 ORDER BY balance DESC LIMIT 5`).all(fy.to),
    series, monthly,
    month_collections: sumBetween('receipts', 'amount', mFrom, t),
    unprinted_bills: one('SELECT COUNT(*) v FROM invoices WHERE printed=0 AND date BETWEEN ? AND ?', fy.from, fy.to).v,
    top_items: db.prepare(
      `SELECT i.id, i.name, i.pcs_per_box, SUM(l.qty + l.free_qty) qty, ROUND(SUM(l.amount),2) amount FROM invoice_lines l
       JOIN invoices v ON v.id=l.invoice_id JOIN items i ON i.id=l.item_id WHERE v.date BETWEEN ? AND ?
       GROUP BY i.id ORDER BY amount DESC, i.name LIMIT 6`).all(mFrom, t),
    recent_bills: db.prepare(
      `SELECT v.id, v.invoice_no, v.date, COALESCE(p.name, 'Cash sale') party, v.total, v.printed FROM invoices v LEFT JOIN parties p ON p.id=v.party_id
       WHERE v.date BETWEEN ? AND ? ORDER BY v.date DESC, v.id DESC LIMIT 6`).all(fy.from, fy.to),
  };
}

/** Items that have been stocked before and are now at or below the company's low-stock level (pieces). */
function lowStock(limit = 1000) {
  const row = db.prepare("SELECT value FROM settings WHERE key='low_stock_qty'").get();
  const threshold = Math.max(0, parseInt(row ? row.value : '10', 10) || 0);
  const all = db.prepare(
    `SELECT i.id, i.name, i.pcs_per_box, COALESCE(SUM(b.qty),0) stock FROM items i JOIN batches b ON b.item_id=i.id
     WHERE i.active=1 GROUP BY i.id HAVING stock <= ? ORDER BY stock, i.name`).all(threshold);
  return { threshold, total: all.length, rows: all.slice(0, limit) };
}

const STD_RATES = [0, 5, 12, 18, 28];

/** Monthly outward supplies (GSTR-1 style summary): taxable value and CGST/SGST/IGST per rate slab. */
function gstOutward(month, fyLabel) {
  const m = month || monthOf(clamp(today(), fyRange(fyLabel)));
  if (!/^\d{4}-\d{2}$/.test(m)) throw Object.assign(new Error('Month must be YYYY-MM'), { status: 400 });
  const rows = db.prepare(
    `SELECT l.gst_rate rate, SUM(l.taxable) taxable, SUM(l.cgst) cgst, SUM(l.sgst) sgst, SUM(l.igst) igst, COUNT(DISTINCT l.invoice_id) invoices
     FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id WHERE i.date BETWEEN ? AND ? GROUP BY l.gst_rate`).all(...monthSpan(m));
  const byRate = new Map(rows.map((r) => [r.rate, r]));
  const rates = [...new Set([...STD_RATES, ...rows.map((r) => r.rate)])].sort((a, b) => a - b);
  const out = rates.map((rate) => {
    const r = byRate.get(rate) || { taxable: 0, cgst: 0, sgst: 0, igst: 0, invoices: 0 };
    const tax = r2(r.cgst + r.sgst + r.igst);
    // IGST is only the integrated tax of inter-state bills; the whole tax of the slab is in "tax"
    return { rate, taxable: r2(r.taxable), cgst: r2(r.cgst), sgst: r2(r.sgst), igst: r2(r.igst), tax, value: r2(r.taxable + tax), invoices: r.invoices };
  });
  const tot = (k) => r2(out.reduce((a, r) => a + r[k], 0));
  const split = (cond) => one(
    `SELECT COALESCE(SUM(l.taxable),0) taxable, COALESCE(SUM(l.cgst+l.sgst+l.igst),0) tax FROM invoice_lines l
     JOIN invoices i ON i.id=l.invoice_id LEFT JOIN parties p ON p.id=i.party_id WHERE i.date BETWEEN ? AND ? AND ${cond}`, ...monthSpan(m));
  const b2b = split(`COALESCE(p.gstin,'') <> ''`), b2c = split(`COALESCE(p.gstin,'') = ''`);
  const inv = one('SELECT COUNT(*) n, COALESCE(SUM(round_off),0) ro FROM invoices WHERE date BETWEEN ? AND ?', ...monthSpan(m));
  const bought = one(`SELECT COALESCE(SUM(cgst),0) c, COALESCE(SUM(sgst),0) s, COALESCE(SUM(igst),0) i FROM purchases WHERE date BETWEEN ? AND ?`, ...monthSpan(m));
  const returned = one(`SELECT COALESCE(SUM(cgst),0) c, COALESCE(SUM(sgst),0) s, COALESCE(SUM(igst),0) i FROM debit_notes WHERE date BETWEEN ? AND ?`, ...monthSpan(m));
  const input = { c: bought.c - returned.c, s: bought.s - returned.s, i: bought.i - returned.i };
  return {
    month: m, rows: out,
    totals: { taxable: tot('taxable'), cgst: tot('cgst'), sgst: tot('sgst'), igst: tot('igst'), tax: tot('tax'), value: tot('value') },
    invoices: inv.n, round_off: r2(inv.ro),
    b2b: { taxable: r2(b2b.taxable), tax: r2(b2b.tax) }, b2c: { taxable: r2(b2c.taxable), tax: r2(b2c.tax) },
    input_credit: { cgst: r2(input.c), sgst: r2(input.s), igst: r2(input.i), total: r2(input.c + input.s + input.i), debit_notes: r2(returned.c + returned.s + returned.i) },
    net_payable: r2(tot('tax') - (input.c + input.s + input.i)),
  };
}


/** Bill-wise detail for the monthly GST workbook: B2B (party has GSTIN), B2C (no GSTIN) and the rate-wise summary. */
function gstOutwardDetail(month, fyLabel) {
  const base = gstOutward(month, fyLabel);
  const bills = db.prepare(
    `SELECT i.id, i.invoice_no, i.date, COALESCE(p.name,'Cash customer') party, COALESCE(p.gstin,'') gstin, COALESCE(p.state_code,'') state_code,
            i.taxable, i.cgst, i.sgst, i.igst, i.round_off, i.total
     FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE i.date BETWEEN ? AND ? ORDER BY i.date, i.id`).all(...monthSpan(base.month));
  const rates = db.prepare(
    // INDEXED BY: rates listed in line order (as the iPhone engine does), not in the order of the covering index
    `SELECT l.invoice_id, GROUP_CONCAT(DISTINCT l.gst_rate) rates FROM invoice_lines l INDEXED BY idx_invl_inv JOIN invoices i ON i.id=l.invoice_id
     WHERE i.date BETWEEN ? AND ? GROUP BY l.invoice_id`).all(...monthSpan(base.month));
  const rm = new Map(rates.map((r) => [r.invoice_id, r.rates]));
  const rows = bills.map((b) => ({ ...b, rates: (rm.get(b.id) || '').split(',').filter(Boolean).map((x) => x + '%').join(', '), tax: r2(b.cgst + b.sgst + b.igst) }));
  return { ...base, b2b_bills: rows.filter((b) => b.gstin), b2c_bills: rows.filter((b) => !b.gstin) };
}

/** Sales or purchase book: chronological register with period totals. */
function book(type, from, to, fyLabel) {
  const fy = fyRange(fyLabel);
  const f = clamp(from || (fy.current ? monthOf(today()) + '-01' : fy.from), fy), t = clamp(to || (fy.current ? today() : fy.to), fy);
  const isSales = type === 'sales';
  const rows = type === 'debit'
    ? db.prepare(`SELECT d.id, d.date, d.note_no no, COALESCE(d.against_bill,'') ref, p.name party, COALESCE(p.gstin,'') gstin,
                  d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total FROM debit_notes d JOIN parties p ON p.id=d.party_id
                  WHERE d.date BETWEEN ? AND ? ORDER BY d.date, d.id`).all(f, t)
    : isSales
    ? db.prepare(`SELECT i.id, i.date, i.invoice_no no, '' ref, COALESCE(p.name,'Cash customer') party, COALESCE(p.gstin,'') gstin,
                  i.taxable, i.cgst, i.sgst, i.igst, i.round_off, i.total FROM invoices i LEFT JOIN parties p ON p.id=i.party_id
                  WHERE i.date BETWEEN ? AND ? ORDER BY i.date, i.id`).all(f, t)
    : db.prepare(`SELECT u.id, u.date, u.purchase_no no, COALESCE(u.supplier_invoice_no,'') ref, p.name party, COALESCE(p.gstin,'') gstin,
                  u.taxable, u.cgst, u.sgst, u.igst, u.round_off, u.total FROM purchases u JOIN parties p ON p.id=u.party_id
                  WHERE u.date BETWEEN ? AND ? ORDER BY u.date, u.id`).all(f, t);
  const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
  return { type: type === 'debit' ? 'debit' : isSales ? 'sales' : 'purchase', from: f, to: t, rows,
    totals: { count: rows.length, taxable: sum('taxable'), cgst: sum('cgst'), sgst: sum('sgst'), igst: sum('igst'), round_off: sum('round_off'), total: sum('total') } };
}

/** All bills: sales and purchases together, filterable. */
function bills({ type = 'ALL', from, to, q, unpaid, unprinted, fy: fyLabel } = {}) {
  const fy = fyRange(fyLabel);
  const f = clamp(from || fy.from, fy), t = clamp(to || fy.to, fy);
  const like = `%${(q || '').trim()}%`;
  const parts = [];
  if (type !== 'PURCHASE' && type !== 'DEBIT_NOTE')
    parts.push(`SELECT 'SALE' type, i.id, i.date, i.invoice_no no, '' ref, COALESCE(p.name,'Cash customer') party, i.total, i.paid, i.printed
                FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE i.date BETWEEN @f AND @t
                AND (i.invoice_no LIKE @q OR COALESCE(p.name,'Cash customer') LIKE @q)`);
  if (type !== 'SALE' && type !== 'DEBIT_NOTE')
    parts.push(`SELECT 'PURCHASE' type, u.id, u.date, u.purchase_no no, COALESCE(u.supplier_invoice_no,'') ref, p.name party, u.total, u.paid, 1 printed
                FROM purchases u JOIN parties p ON p.id=u.party_id WHERE u.date BETWEEN @f AND @t
                AND (u.purchase_no LIKE @q OR COALESCE(u.supplier_invoice_no,'') LIKE @q OR p.name LIKE @q)`);
  // goods returned to suppliers: nothing is due on a debit note, so paid = total
  if (type === 'ALL' || type === 'DEBIT_NOTE')
    parts.push(`SELECT 'DEBIT_NOTE' type, d.id, d.date, d.note_no no, COALESCE(d.against_bill,'') ref, p.name party, d.total, d.total paid, 1 printed
                FROM debit_notes d JOIN parties p ON p.id=d.party_id WHERE d.date BETWEEN @f AND @t
                AND (d.note_no LIKE @q OR COALESCE(d.against_bill,'') LIKE @q OR p.name LIKE @q)`);
  let sql = `SELECT * FROM (${parts.join(' UNION ALL ')})`;
  const where = [];
  if (unpaid) where.push('total - paid > 0.5');
  if (unprinted) where.push('printed = 0');
  if (where.length) sql += ' WHERE ' + where.join(' AND ');
  sql += ' ORDER BY date DESC, id DESC LIMIT 1000';
  const rows = db.prepare(sql).all({ f, t, q: like });
  const total = (ty) => r2(rows.filter((r) => r.type === ty).reduce((a, r) => a + r.total, 0));
  return { rows, totals: { sales: total('SALE'), purchases: total('PURCHASE'), debit_notes: total('DEBIT_NOTE'), due: r2(rows.reduce((a, r) => a + (r.total - r.paid), 0)) } };
}

module.exports = { profit, lowStock, dashboard, gstOutward, gstOutwardDetail, book, bills };
