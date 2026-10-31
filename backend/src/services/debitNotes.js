const db = require('../db');
const { r2 } = require('../utils/gst');
const { today, nextNo, HttpError } = require('../utils/misc');
const { settings } = require('./billing');
const { rupeesInWords } = require('../utils/words');
const { fyRange } = require('../utils/fy');

/**
 * Debit note (purchase return): goods sent back to a supplier. The pieces go out of stock (from the batch chosen, or the
 * earliest-expiring batches), the supplier's ledger is debited by the note's total (we owe them that much less), and the GST
 * on it is taken off the input tax credit of its month. Numbered DN/<year>/00001 like every other voucher.
 *
 * Amounts work like a purchase bill: qty x rate per row (rate per box when the row is in boxes), less a bill discount spread
 * over the rows, plus GST at each item's rate (CGST + SGST inside the state, IGST outside), rounded to the rupee.
 */
const isDate = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);
const BOX_UNIT = /^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$/i;
const blankNum = (v) => v === undefined || v === null || String(v).trim() === '';
const num = (v, label, { min = 0 } = {}) => {
  if (blankNum(v)) return 0;
  const n = Number(String(v).replace(/,/g, ''));
  if (!Number.isFinite(n) || n < min) throw new HttpError(400, `${label} must be a number${min === 0 ? ' (0 or more)' : ''}`);
  return n;
};
const text = (v, max = 200) => { const s = String(v ?? '').trim().replace(/\s+/g, ' ').slice(0, max); return s || null; };

/** Pure calculation, no writes. */
function buildDebitNote(input) {
  if (!input.party_id) throw new HttpError(400, 'Select the supplier');
  const party = db.prepare('SELECT * FROM parties WHERE id=?').get(input.party_id);
  if (!party) throw new HttpError(404, 'Party not found');
  if (!Array.isArray(input.lines) || !input.lines.length) throw new HttpError(400, 'Add at least one item');
  const co = settings();
  const intra = !party.state_code || party.state_code === co.state_code;
  const date = input.date || today();
  if (!isDate(date)) throw new HttpError(400, 'Date must be YYYY-MM-DD');

  const rows = input.lines.map((ln, i) => {
    const n = i + 1;
    const item = ln.item_id ? db.prepare('SELECT * FROM items WHERE id=?').get(ln.item_id) : null;
    if (!item) throw new HttpError(400, `Row ${n}: choose the stock item`);
    const q = num(ln.qty, `Row ${n} (${item.name}) quantity`);
    if (!(q > 0) || !Number.isInteger(q)) throw new HttpError(400, `Row ${n} (${item.name}): quantity must be a whole number of at least 1`);
    const unit = BOX_UNIT.test(String(ln.unit || '').trim()) ? 'BOX' : 'PCS';
    const ppb = Math.max(1, item.pcs_per_box || 1);
    const pcs = unit === 'BOX' ? q * ppb : q;
    const rate = num(ln.rate, `Row ${n} (${item.name}) rate`);
    const amount = blankNum(ln.amount) ? r2(q * rate) : r2(num(ln.amount, `Row ${n} (${item.name}) amount`));
    const gst = blankNum(ln.gst_rate) ? item.gst_rate : num(ln.gst_rate, `Row ${n} (${item.name}) GST rate`);
    if (gst > 40) throw new HttpError(400, `Row ${n} (${item.name}): GST rate must be between 0 and 40`);
    const batchId = ln.batch_id ? Number(ln.batch_id) : null;
    return { sno: n, item_id: item.id, item_name: item.name, hsn: item.hsn || null, pcs_per_box: ppb, mrp: item.mrp,
      qty: q, unit, pcs_qty: pcs, rate, amount, gst_rate: gst, batch_id: batchId };
  });

  const subtotal = r2(rows.reduce((a, r) => a + r.amount, 0));
  const discount = r2(num(input.discount, 'Discount'));
  if (discount > subtotal + 0.005) throw new HttpError(400, 'Discount cannot be more than the items total');
  const taxable = r2(subtotal - discount);
  const share = subtotal > 0 ? taxable / subtotal : 0;
  for (const r of rows) {
    r.taxable = r2(r.amount * share);
    const tax = r2((r.taxable * r.gst_rate) / 100);
    if (intra) { r.cgst = r2(tax / 2); r.sgst = r2(tax - r.cgst); r.igst = 0; } else { r.cgst = 0; r.sgst = 0; r.igst = tax; }
  }
  const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
  const cgst = sum('cgst'), sgst = sum('sgst'), igst = sum('igst');
  const grand = r2(taxable + cgst + sgst + igst);
  const round_off = r2(Math.round(grand) - grand);
  const total = r2(grand + round_off);
  return { party, date, intra, rows, subtotal, discount, taxable, cgst, sgst, igst, round_off, total };
}

const previewDebitNote = (input) => {
  const p = buildDebitNote(input);
  const { party, rows, ...rest } = p;
  return { ...rest, supply: p.intra ? 'INTRA' : 'INTER', lines: rows };
};

/** Which batches the pieces of one row come out of: the chosen batch, or the earliest-expiring batches that have stock. */
function allocate(r) {
  if (r.batch_id) {
    const b = db.prepare('SELECT id, batch_no, qty FROM batches WHERE id=? AND item_id=?').get(r.batch_id, r.item_id);
    if (!b) throw new HttpError(400, `Row ${r.sno} (${r.item_name}): that batch is not one of this item's batches`);
    if (b.qty < r.pcs_qty) throw new HttpError(409, `Row ${r.sno} (${r.item_name}): batch ${b.batch_no} has only ${b.qty} piece(s) in stock`, 'NO_STOCK');
    return [{ batch_id: b.id, qty: r.pcs_qty }];
  }
  const out = [];
  let left = r.pcs_qty;
  for (const b of db.prepare('SELECT id, qty FROM batches WHERE item_id=? AND qty>0 ORDER BY exp_date, id').all(r.item_id)) {
    if (left <= 0) break;
    const take = Math.min(b.qty, left);
    out.push({ batch_id: b.id, qty: take });
    left -= take;
  }
  if (left > 0) throw new HttpError(409, `${r.item_name}: only ${r.pcs_qty - left} piece(s) in stock, ${r.pcs_qty} to return`, 'NO_STOCK');
  return out;
}

/** Shared by create and edit. `existing` = { id, note_no } when an edited note is rewritten under its own number. */
function writeDebitNote(input, existing) {
  const p = buildDebitNote(input);
  let purchase = null;
  if (input.purchase_id) {
    purchase = db.prepare('SELECT id, purchase_no, supplier_invoice_no FROM purchases WHERE id=?').get(input.purchase_id);
    if (!purchase) throw new HttpError(404, 'Purchase bill not found');
  }
  const against = text(input.against_bill, 60) || (purchase ? purchase.supplier_invoice_no || purchase.purchase_no : null);
  const vals = [p.date, p.party.id, purchase ? purchase.id : null, against, text(input.reason), p.subtotal, p.discount, p.taxable,
    p.cgst, p.sgst, p.igst, p.round_off, p.total, text(input.notes, 500)];
  let id, note_no;
  if (existing) {
    id = existing.id; note_no = existing.note_no;
    db.prepare(`UPDATE debit_notes SET date=?,party_id=?,purchase_id=?,against_bill=?,reason=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,notes=? WHERE id=?`)
      .run(...vals, id);
  } else {
    note_no = nextNo('DN', p.date);
    id = Number(db.prepare(
      `INSERT INTO debit_notes(date,party_id,purchase_id,against_bill,reason,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,notes,note_no)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(...vals, note_no).lastInsertRowid);
  }
  const insLine = db.prepare(
    `INSERT INTO debit_note_lines(note_id,item_id,batch_id,qty,unit,pcs_qty,rate,amount,taxable,gst_rate,cgst,sgst,igst) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)`);
  const insStock = db.prepare('INSERT INTO debit_note_stock(line_id,batch_id,qty) VALUES(?,?,?)');
  for (const r of p.rows) {
    const parts = allocate(r);
    const lineId = Number(insLine.run(id, r.item_id, parts.length === 1 ? parts[0].batch_id : null, r.qty, r.unit, r.pcs_qty, r.rate, r.amount,
      r.taxable, r.gst_rate, r.cgst, r.sgst, r.igst).lastInsertRowid);
    for (const s of parts) {
      db.prepare('UPDATE batches SET qty = qty - ? WHERE id = ?').run(s.qty, s.batch_id);
      insStock.run(lineId, s.batch_id, s.qty);
    }
  }
  const why = [against ? `against ${against}` : '', text(input.reason) ? `(${text(input.reason)})` : ''].filter(Boolean).join(' ');
  db.prepare('INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)')
    .run(p.party.id, p.date, 'DEBIT_NOTE', note_no, p.total, 0, `Debit note ${note_no}${why ? ' ' + why : ''}`);
  return id;
}

/** Puts the returned pieces back into their batches and removes the note's lines and ledger entry. */
function reverse(old) {
  for (const s of db.prepare('SELECT s.batch_id, s.qty FROM debit_note_stock s JOIN debit_note_lines l ON l.id=s.line_id WHERE l.note_id=?').all(old.id))
    db.prepare('UPDATE batches SET qty = qty + ? WHERE id = ?').run(s.qty, s.batch_id);
  db.prepare('DELETE FROM debit_note_stock WHERE line_id IN (SELECT id FROM debit_note_lines WHERE note_id=?)').run(old.id);
  db.prepare('DELETE FROM debit_note_lines WHERE note_id=?').run(old.id);
  db.prepare("DELETE FROM ledger WHERE type='DEBIT_NOTE' AND ref_no=?").run(old.note_no);
}

const createDebitNote = db.transaction((input) => writeDebitNote(input, null));

const updateDebitNote = db.transaction((id, input) => {
  const old = db.prepare('SELECT * FROM debit_notes WHERE id=?').get(id);
  if (!old) throw new HttpError(404, 'Debit note not found');
  reverse(old);
  return writeDebitNote(input, { id, note_no: old.note_no });
});

const deleteDebitNote = db.transaction((id) => {
  const old = db.prepare('SELECT * FROM debit_notes WHERE id=?').get(id);
  if (!old) throw new HttpError(404, 'Debit note not found');
  reverse(old);
  db.prepare('DELETE FROM debit_notes WHERE id=?').run(id);
  return { id, note_no: old.note_no, total: old.total };
});

/** The note with its lines, and the same fields a printed bill uses (so it prints on the bill layouts as a DEBIT NOTE). */
function getDebitNote(id) {
  const d = db.prepare(
    `SELECT d.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state, p.phone party_phone, p.mobiles party_mobiles,
            p.tel party_tel, p.email party_email, p.pan party_pan, p.fssai party_fssai, u.purchase_no
     FROM debit_notes d JOIN parties p ON p.id=d.party_id LEFT JOIN purchases u ON u.id=d.purchase_id WHERE d.id=?`).get(id);
  if (!d) return null;
  d.lines = db.prepare(
    `SELECT l.*, it.name item_name, COALESCE(it.hsn,'') hsn, it.pcs_per_box, it.mrp,
            (SELECT GROUP_CONCAT(b.batch_no, ', ') FROM debit_note_stock s JOIN batches b ON b.id=s.batch_id WHERE s.line_id=l.id) batch_no
     FROM debit_note_lines l JOIN items it ON it.id=l.item_id WHERE l.note_id=? ORDER BY l.id`).all(id);
  d.lines.forEach((l, i) => { l.sno = i + 1; if (!l.batch_no) l.batch_no = ''; });
  d.supply = d.igst > 0 ? 'INTER' : 'INTRA';
  d.amount_words = rupeesInWords(d.total);
  const g = {};
  for (const l of d.lines) {
    const x = (g[l.gst_rate] ||= { rate: l.gst_rate, rows: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0 });
    x.rows += 1; x.taxable = r2(x.taxable + l.taxable); x.cgst = r2(x.cgst + l.cgst); x.sgst = r2(x.sgst + l.sgst); x.igst = r2(x.igst + l.igst);
  }
  d.gst_summary = Object.values(g).sort((a, b) => a.rate - b.rate);
  // for the print layouts: the number, the heading and one line per row in pieces, like a sale bill
  d.invoice_no = d.note_no;
  d.doc_title = 'DEBIT NOTE';
  d.doc_no_label = 'Debit note no';
  d.doc_line = [d.against_bill ? `Against bill ${d.against_bill}` : '', d.reason || ''].filter(Boolean).join('  ·  ');
  d.print_lines = d.lines.map((l) => ({ item_name: l.item_name, hsn: l.hsn, qty: l.pcs_qty, free_qty: 0, pcs_per_box: l.pcs_per_box, mrp: l.mrp,
    rate: l.pcs_qty > 0 ? r2(l.amount / l.pcs_qty) : 0, disc_pct: 0, taxable: l.taxable, gst_rate: l.gst_rate, amount: r2(l.taxable + l.cgst + l.sgst + l.igst) }));
  return d;
}

/** Debit notes of the selected year (optionally a date range, a supplier, or a search), newest first, with totals. */
function listDebitNotes({ fy: fyLabel, from, to, q, party_id } = {}) {
  const fy = fyRange(fyLabel);
  const f = from && from > fy.from ? from : fy.from, t = to && to < fy.to ? to : fy.to;
  const rows = db.prepare(
    `SELECT d.id, d.note_no, d.date, COALESCE(d.against_bill,'') against_bill, COALESCE(d.reason,'') reason, d.party_id, p.name party, COALESCE(p.gstin,'') gstin,
            d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total
     FROM debit_notes d JOIN parties p ON p.id=d.party_id
     WHERE d.date BETWEEN @f AND @t AND (@pid IS NULL OR d.party_id=@pid)
       AND (d.note_no LIKE @q OR p.name LIKE @q OR COALESCE(d.against_bill,'') LIKE @q)
     ORDER BY d.date DESC, d.id DESC`).all({ f, t, q: `%${String(q || '').trim()}%`, pid: party_id ? Number(party_id) : null });
  const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
  return { from: f, to: t, rows, totals: { count: rows.length, taxable: sum('taxable'), cgst: sum('cgst'), sgst: sum('sgst'), igst: sum('igst'), total: sum('total') } };
}

module.exports = { buildDebitNote, previewDebitNote, createDebitNote, updateDebitNote, deleteDebitNote, getDebitNote, listDebitNotes };
