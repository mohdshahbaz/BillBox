const db = require('../db');
const { r2 } = require('../utils/gst');
const { today, nextNo, HttpError } = require('../utils/misc');
const { settings } = require('./billing');

const isDate = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);
const NO_EXPIRY = '2099-12-31';                                   // batches bought without an expiry date sort last in FEFO
const BOX_UNIT = /^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$/i;
const blankNum = (v) => v === undefined || v === null || String(v).trim() === '';
const num = (v, label, { min = 0 } = {}) => {
  if (blankNum(v)) return 0;
  const n = Number(String(v).replace(/,/g, ''));
  if (!Number.isFinite(n) || n < min) throw new HttpError(400, `${label} must be a number${min === 0 ? ' (0 or more)' : ''}`);
  return n;
};

/**
 * Pure calculation for a supplier bill, no writes:
 *   items -> subtotal; minus bill discount -> taxable; plus CGST/SGST (or IGST); plus round off -> grand total.
 * Tax amounts come from the bill (typed or read from the PDF). If they are left blank, or auto_tax is set,
 * they are worked out from each item's GST rate.
 */
function buildPurchase(input) {
  if (!input.party_id) throw new HttpError(400, 'Select the supplier');
  const party = db.prepare('SELECT * FROM parties WHERE id=?').get(input.party_id);
  if (!party) throw new HttpError(404, 'Supplier not found');
  if (!Array.isArray(input.lines) || !input.lines.length) throw new HttpError(400, 'Add at least one item');
  const co = settings();
  const intra = !party.state_code || party.state_code === co.state_code;
  const date = input.date || today();
  if (!isDate(date)) throw new HttpError(400, 'Bill date must be YYYY-MM-DD');

  const rows = input.lines.map((ln, i) => {
    const n = i + 1;
    const item = ln.item_id ? db.prepare('SELECT * FROM items WHERE id=? AND active=1').get(ln.item_id) : null;
    if (!item) throw new HttpError(400, `Row ${n}: choose the stock item`);
    const q = num(ln.qty, `Row ${n} (${item.name}) quantity`);
    if (!(q > 0) || !Number.isInteger(q)) throw new HttpError(400, `Row ${n} (${item.name}): quantity must be a whole number of at least 1`);
    const unit = String(ln.unit || item.unit || 'PCS').trim().toUpperCase().slice(0, 8) || 'PCS';
    const ppb = Math.max(1, item.pcs_per_box || 1);
    const pcs = BOX_UNIT.test(unit) ? q * ppb : q;                 // stock is always kept in pieces
    const rate = num(ln.rate, `Row ${n} (${item.name}) price`);
    const amount = blankNum(ln.amount) ? r2(q * rate) : r2(num(ln.amount, `Row ${n} (${item.name}) amount`));
    const exp = ln.exp_date ? ln.exp_date : NO_EXPIRY;
    if (!isDate(exp)) throw new HttpError(400, `Row ${n} (${item.name}): expiry must be YYYY-MM-DD`);
    if (ln.mfg_date && !isDate(ln.mfg_date)) throw new HttpError(400, `Row ${n} (${item.name}): mfg date must be YYYY-MM-DD`);
    return {
      line_index: i, sno: n, item_id: item.id, item_name: item.name, hsn: ln.hsn || item.hsn || null, gst_rate: item.gst_rate,
      qty: q, unit, pcs_qty: pcs, rate, amount,
      batch_no: String(ln.batch_no || '').trim() || `AUTO-${date.replace(/-/g, '')}`,
      mfg_date: ln.mfg_date || null, exp_date: exp, mrp: ln.mrp ? Number(ln.mrp) : null,
    };
  });

  const subtotal = r2(rows.reduce((a, r) => a + r.amount, 0));
  const discount = r2(num(input.discount, 'Discount'));
  if (discount > subtotal + 0.005) throw new HttpError(400, 'Discount cannot be more than the items total');
  const taxable = r2(subtotal - discount);
  const share = subtotal > 0 ? taxable / subtotal : 0;

  // Tax worked out from item GST rates (also offered to the user as "recalculate")
  let sugTax = 0;
  for (const r of rows) sugTax += (r.amount * share * r.gst_rate) / 100;
  sugTax = r2(sugTax);
  const suggested = intra ? { cgst: r2(sugTax / 2), sgst: r2(sugTax - r2(sugTax / 2)), igst: 0 } : { cgst: 0, sgst: 0, igst: sugTax };

  const taxGiven = !(blankNum(input.cgst) && blankNum(input.sgst) && blankNum(input.igst));
  let cgst, sgst, igst;
  if (input.auto_tax || !taxGiven) ({ cgst, sgst, igst } = suggested);
  else { cgst = r2(num(input.cgst, 'CGST')); sgst = r2(num(input.sgst, 'SGST')); igst = r2(num(input.igst, 'IGST')); }

  const grand = r2(taxable + cgst + sgst + igst);
  let round_off;
  if (blankNum(input.round_off)) round_off = r2(Math.round(grand) - grand);
  else {
    round_off = r2(num(input.round_off, 'Round off', { min: -Infinity }));
    if (Math.abs(round_off) > 5) throw new HttpError(400, 'Round off looks too large (more than 5 rupees). Check the figure.');
  }
  const total = r2(grand + round_off);
  const printed = blankNum(input.printed_total) ? null : Number(input.printed_total);
  const mismatch = printed !== null && Number.isFinite(printed) && Math.abs(printed - total) > 1 ? r2(total - printed) : 0;

  return {
    party, date, intra, rows, subtotal, discount, taxable, cgst, sgst, igst, round_off, total,
    suggested_tax: suggested, printed_total: printed, mismatch,
    share, // used to allocate discount to item cost
  };
}

const previewPurchase = (input) => {
  const p = buildPurchase(input);
  const { party, rows, share, ...rest } = p;
  return { ...rest, supply: p.intra ? 'INTRA' : 'INTER', lines: rows };
};

/** Shared by create and edit. `existing` = { id, purchase_no } when an edited bill is rewritten in place. */
function writePurchase(input, existing) {
  const p = buildPurchase(input);
  const supplierNo = String(input.supplier_invoice_no || '').trim();
  if (supplierNo && !input.allow_duplicate) {
    const dup = db.prepare('SELECT purchase_no FROM purchases WHERE party_id=? AND lower(supplier_invoice_no)=lower(?) AND id <> ?')
      .get(p.party.id, supplierNo, existing ? existing.id : 0);
    if (dup) throw new HttpError(409, `Bill ${supplierNo} from ${p.party.name} is already entered as ${dup.purchase_no}`, 'DUPLICATE');
  }
  const paid = r2(Math.min(Math.max(num(input.paid_amount, 'Paid amount'), 0), Math.max(p.total, 0)));
  const mode = String(input.pay_mode || 'CASH').toUpperCase();
  const vals = [supplierNo || null, p.date, p.party.id, p.subtotal, p.discount, p.taxable, p.cgst, p.sgst, p.igst, p.round_off, p.total, paid,
    paid > 0 ? mode : null, input.notes || null, input.source === 'PDF' ? 'PDF' : 'MANUAL'];
  let id, purchase_no;
  if (existing) {
    id = existing.id; purchase_no = existing.purchase_no;
    db.prepare(`UPDATE purchases SET supplier_invoice_no=?,date=?,party_id=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,paid=?,pay_mode=?,notes=?,source=? WHERE id=?`)
      .run(...vals, id);
  } else {
    purchase_no = nextNo('PUR', p.date);
    id = Number(db.prepare(
      `INSERT INTO purchases(supplier_invoice_no,date,party_id,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,pay_mode,notes,source,purchase_no)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(...vals, purchase_no).lastInsertRowid);
  }

  const upsert = db.prepare(
    `INSERT INTO batches(item_id,batch_no,mfg_date,exp_date,qty,purchase_price,mrp) VALUES(?,?,?,?,?,?,?)
     ON CONFLICT(item_id,batch_no) DO UPDATE SET qty = qty + excluded.qty, exp_date = excluded.exp_date,
       mfg_date = COALESCE(excluded.mfg_date, mfg_date), purchase_price = excluded.purchase_price, mrp = COALESCE(excluded.mrp, mrp)`);
  const insLine = db.prepare(
    `INSERT INTO purchase_lines(purchase_id,item_id,batch_id,batch_no,mfg_date,exp_date,qty,free_qty,rate,disc_pct,disc_amt,mrp,taxable,gst_rate,cgst,sgst,igst,amount,unit,pcs_qty)
     VALUES(?,?,?,?,?,?,?,0,?,0,0,?,?,?,0,0,0,?,?,?)`);
  const touched = new Set();
  for (const r of p.rows) {
    const lineTaxable = r2(r.amount * p.share);
    const unitCost = r2(lineTaxable / r.pcs_qty);                  // landed cost per piece after bill discount
    upsert.run(r.item_id, r.batch_no, r.mfg_date, r.exp_date, r.pcs_qty, unitCost, r.mrp);
    const batch = db.prepare('SELECT id FROM batches WHERE item_id=? AND batch_no=?').get(r.item_id, r.batch_no);
    touched.add(batch.id);
    insLine.run(id, r.item_id, batch.id, r.batch_no, r.mfg_date, r.exp_date, r.qty, r.rate, r.mrp, lineTaxable, r.gst_rate, r.amount, r.unit, r.pcs_qty);
    if (input.update_cost !== false && unitCost > 0) db.prepare('UPDATE items SET purchase_price=? WHERE id=?').run(unitCost, r.item_id);
  }
  return { id, purchase_no, p, paid, mode, supplierNo, touched };
}

function postLedger({ id, purchase_no, p, paid, mode, supplierNo }) {
  const lg = db.prepare('INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)');
  lg.run(p.party.id, p.date, 'PURCHASE', purchase_no, 0, p.total, `Purchase ${purchase_no}${supplierNo ? ' / ' + supplierNo : ''}`);
  if (paid > 0) {
    const v = nextNo('PAY', p.date);
    db.prepare('INSERT INTO payments(voucher_no,date,party_id,purchase_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?)')
      .run(v, p.date, p.party.id, id, mode, paid, `Paid at purchase ${purchase_no}`);
    lg.run(p.party.id, p.date, 'PAYMENT', v, paid, 0, `Paid at purchase (${mode})`);
  }
}

/** Saves the bill AND adds the received pieces to batch stock, posts to the supplier ledger, all in one transaction. */
const createPurchase = db.transaction((input) => {
  const w = writePurchase(input, null);
  postLedger(w);
  return w.id;
});

/**
 * Edit a saved (manual or scanned) purchase: take the old pieces back out of stock, drop its ledger postings,
 * write the new version under the same bill number, and refuse (changing nothing) if that would leave a batch
 * with fewer pieces than were already sold from it.
 */
const updatePurchase = db.transaction((id, input) => {
  const old = db.prepare('SELECT * FROM purchases WHERE id=?').get(id);
  if (!old) throw new HttpError(404, 'Purchase bill not found');
  const oldTouched = new Set();
  for (const l of db.prepare('SELECT batch_id, qty, free_qty, pcs_qty FROM purchase_lines WHERE purchase_id=?').all(id)) {
    db.prepare('UPDATE batches SET qty = qty - ? WHERE id = ?').run(l.pcs_qty != null ? l.pcs_qty : l.qty + l.free_qty, l.batch_id);
    oldTouched.add(l.batch_id);
  }
  db.prepare('DELETE FROM purchase_lines WHERE purchase_id=?').run(id);
  for (const pay of db.prepare('SELECT voucher_no FROM payments WHERE purchase_id=?').all(id))
    db.prepare("DELETE FROM ledger WHERE type='PAYMENT' AND ref_no=?").run(pay.voucher_no);
  db.prepare('DELETE FROM payments WHERE purchase_id=?').run(id);
  db.prepare("DELETE FROM ledger WHERE type='PURCHASE' AND ref_no=?").run(old.purchase_no);

  const w = writePurchase(input, { id, purchase_no: old.purchase_no });
  postLedger(w);
  for (const b of new Set([...oldTouched, ...w.touched])) {
    const row = db.prepare('SELECT b.qty, i.name FROM batches b JOIN items i ON i.id=b.item_id WHERE b.id=?').get(b);
    if (row && row.qty < 0)
      throw new HttpError(409, `${row.name}: ${-row.qty} piece(s) from this bill were already sold, so the quantity cannot be reduced that far.`, 'ALREADY_SOLD');
  }
  return id;
});

/** Delete a purchase bill: its stock comes back out of the batches (refused if some of it was already sold) and its ledger entries go. */
const deletePurchase = db.transaction((id) => {
  const old = db.prepare('SELECT * FROM purchases WHERE id=?').get(id);
  if (!old) throw new HttpError(404, 'Purchase bill not found');
  const touched = new Set();
  for (const l of db.prepare('SELECT batch_id, qty, free_qty, pcs_qty FROM purchase_lines WHERE purchase_id=?').all(id)) {
    db.prepare('UPDATE batches SET qty = qty - ? WHERE id = ?').run(l.pcs_qty != null ? l.pcs_qty : l.qty + l.free_qty, l.batch_id);
    touched.add(l.batch_id);
  }
  db.prepare('DELETE FROM purchase_lines WHERE purchase_id=?').run(id);
  for (const pay of db.prepare('SELECT voucher_no FROM payments WHERE purchase_id=?').all(id))
    db.prepare("DELETE FROM ledger WHERE type='PAYMENT' AND ref_no=?").run(pay.voucher_no);
  db.prepare('DELETE FROM payments WHERE purchase_id=?').run(id);
  db.prepare("DELETE FROM ledger WHERE type='PURCHASE' AND ref_no=?").run(old.purchase_no);
  db.prepare('DELETE FROM purchases WHERE id=?').run(id);
  for (const b of touched) {
    const row = db.prepare('SELECT b.qty, i.name FROM batches b JOIN items i ON i.id=b.item_id WHERE b.id=?').get(b);
    if (row && row.qty < 0)
      throw new HttpError(409, `${row.name}: ${-row.qty} piece(s) from this bill were already sold, so it cannot be deleted.`, 'ALREADY_SOLD');
  }
  return { id, purchase_no: old.purchase_no, total: old.total };
});

function getPurchase(id) {
  const p = db.prepare(
    `SELECT pu.*, pa.name party_name, pa.gstin party_gstin, pa.state_code party_state FROM purchases pu JOIN parties pa ON pa.id=pu.party_id WHERE pu.id=?`
  ).get(id);
  if (!p) return null;
  p.lines = db.prepare(
    `SELECT l.*, it.name item_name, COALESCE(it.hsn,'') hsn, MAX(1, COALESCE(it.pcs_per_box,1)) pcs_per_box FROM purchase_lines l JOIN items it ON it.id=l.item_id WHERE l.purchase_id=? ORDER BY l.id`).all(id);
  p.lines.forEach((l, i) => {
    l.sno = i + 1; if (l.exp_date >= '2099-01-01') l.exp_date = null; if (!l.unit) l.unit = 'PCS';
    // pieces into stock (older lines have none saved): a BOX line's qty is boxes, so screens can show boxes and pieces
    if (l.pcs_qty == null) l.pcs_qty = BOX_UNIT.test(l.unit) ? l.qty * l.pcs_per_box : l.qty;
  });
  return p;
}

module.exports = { buildPurchase, previewPurchase, createPurchase, updatePurchase, deletePurchase, getPurchase, NO_EXPIRY };
