const db = require('../db');
const { r2, splitTax } = require('../utils/gst');
const { applySchemes } = require('../utils/schemes');
const { today, nextNo, HttpError } = require('../utils/misc');
const { rupeesInWords } = require('../utils/words');

const settings = () => {
  const o = {};
  for (const r of db.prepare('SELECT key,value FROM settings').all()) o[r.key] = r.value;
  return o;
};

const partyBalance = (id) =>
  db.prepare('SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=?').get(id).b;

// Selling rates are ex-GST. MRP is GST-inclusive, so back the tax out for the MRP tier.
function priceFor(item, tier) {
  // no wholesale price set for this item (0): bill it at the retail price rather than at nothing
  if (tier === 'WHOLESALE') return item.wholesale_price > 0 ? item.wholesale_price : item.retail_price;
  if (tier === 'MRP') return item.mrp / (1 + item.gst_rate / 100);   // not rounded: a whole box must add up exactly
  return item.retail_price;
}

/**
 * Pure calculation (no writes): price tier -> schemes -> FEFO batch allocation -> GST.
 * Used by both /invoices/preview and the real save, so the screen total always matches.
 */
function buildInvoice(input) {
  if (!Array.isArray(input.lines) || !input.lines.length) throw new HttpError(400, 'Add at least one item to the bill');
  const co = settings();
  const party = input.party_id ? db.prepare('SELECT * FROM parties WHERE id=?').get(input.party_id) : null;
  if (input.party_id && !party) throw new HttpError(404, 'Party not found');

  const tier = party ? party.price_tier : 'RETAIL';
  const intra = !party || !party.state_code || party.state_code === co.state_code;
  const date = input.date || today();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new HttpError(400, 'Bill date must be YYYY-MM-DD');

  const reserved = new Map(); // batch_id -> qty already taken by earlier lines of this bill
  const rows = [];
  const display = [];

  input.lines.forEach((ln, idx) => {
    const item = db.prepare('SELECT * FROM items WHERE id=? AND active=1').get(ln.item_id);
    if (!item) throw new HttpError(404, `Item ${ln.item_id} not found`);
    // Dual unit: the operator may enter Boxes and loose Pieces. Everything below works in pieces.
    const ppb = Math.max(1, parseInt(item.pcs_per_box, 10) || 1);
    const hasUnits = ln.boxes !== undefined || ln.pcs !== undefined;
    const qty = hasUnits
      ? Math.max(0, parseInt(ln.boxes, 10) || 0) * ppb + Math.max(0, parseInt(ln.pcs, 10) || 0)
      : parseInt(ln.qty, 10);
    if (!(qty > 0)) throw new HttpError(400, `Enter a quantity for ${item.name}`);

    const rate = ln.rate !== undefined && ln.rate !== null && ln.rate !== '' ? Number(ln.rate) : priceFor(item, tier);
    const manualPct = Math.min(100, Math.max(0, Number(ln.disc_pct) || 0));

    const schemes = db.prepare(
      `SELECT * FROM schemes WHERE item_id=? AND active=1
       AND (valid_from IS NULL OR valid_from<=?) AND (valid_to IS NULL OR valid_to>=?)`
    ).all(item.id, date, date);
    const sc = applySchemes(qty, schemes);
    const pct = Math.min(100, manualPct + sc.discPct);

    // FEFO: first-expiry-first-out, skipping expired batches
    const need = qty + sc.freeQty;
    const batches = db.prepare('SELECT * FROM batches WHERE item_id=? AND qty>0 AND exp_date>=? ORDER BY exp_date, id').all(item.id, date);
    let remaining = need;
    let paidLeft = qty;
    for (const b of batches) {
      if (remaining <= 0) break;
      const avail = b.qty - (reserved.get(b.id) || 0);
      if (avail <= 0) continue;
      const take = Math.min(avail, remaining);
      reserved.set(b.id, (reserved.get(b.id) || 0) + take);
      remaining -= take;

      const paid = Math.min(take, paidLeft);
      const free = take - paid;
      paidLeft -= paid;

      const gross = r2(rate * paid);
      const discAmt = r2((gross * pct) / 100);
      const taxable = r2(gross - discAmt);
      const tax = splitTax(taxable, item.gst_rate, intra);
      rows.push({
        line_index: idx, item_id: item.id, item_name: item.name, hsn: item.hsn,
        batch_id: b.id, batch_no: b.batch_no, exp_date: b.exp_date,
        qty: paid, free_qty: free, rate, disc_pct: pct, manual_pct: manualPct, disc_amt: discAmt, gross, taxable,
        gst_rate: item.gst_rate, ...tax, amount: r2(taxable + tax.cgst + tax.sgst + tax.igst),
      });
    }
    if (remaining > 0) throw new HttpError(409, `Not enough stock for ${item.name}: short by ${remaining}`, 'NO_STOCK');

    const mine = rows.filter((r) => r.line_index === idx);
    const s = (k) => r2(mine.reduce((a, r) => a + r[k], 0));
    display.push({
      line_index: idx, item_id: item.id, item_name: item.name, unit: item.unit, qty,
      pcs_per_box: ppb, boxes: Math.floor(qty / ppb), pcs: qty % ppb,
      free_qty: sc.freeQty, rate, disc_pct: pct, manual_pct: manualPct, schemes: sc.applied, gst_rate: item.gst_rate,
      disc_amt: s('disc_amt'), taxable: s('taxable'),
      tax: r2(s('cgst') + s('sgst') + s('igst')), amount: s('amount'),
      batches: mine.map((r) => `${r.batch_no} ×${r.qty + r.free_qty}`).join(', '),
    });
  });

  const sum = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
  const taxable = sum('taxable');
  const cgst = sum('cgst'), sgst = sum('sgst'), igst = sum('igst');
  const grand = r2(taxable + cgst + sgst + igst);
  // Settings › Billing & Dashboard › round the total to the rupee (on unless switched off)
  const total = co.bill_round === '0' ? grand : Math.round(grand);

  return {
    date, party, tier, intra, rows, display,
    subtotal: sum('gross'), discount: sum('disc_amt'), taxable, cgst, sgst, igst,
    round_off: r2(total - grand), total,
  };
}

/** Shared by create and edit. `existing` = { id, invoice_no, receipt_no } when an edited bill is being rewritten in place. */
function writeInvoice(input, existing) {
  const inv = buildInvoice(input);
  const party = inv.party;
  const mode = String(input.pay_mode || 'CASH').toUpperCase();

  let paid = input.paid_amount !== undefined && input.paid_amount !== null && input.paid_amount !== ''
    ? Number(input.paid_amount) : mode === 'CREDIT' ? 0 : inv.total;
  if (!Number.isFinite(paid)) throw new HttpError(400, 'Paid amount is not a number');
  paid = r2(Math.min(Math.max(paid, 0), inv.total));

  if (!party && paid < inv.total) throw new HttpError(400, 'Walk-in sales must be paid in full');
  if (party && party.credit_limit > 0 && !input.override_credit) {
    const after = r2(partyBalance(party.id) + inv.total - paid);
    if (after > party.credit_limit) {
      throw new HttpError(409, `Credit limit exceeded: dues would be ₹${after} against a limit of ₹${party.credit_limit}`, 'CREDIT_LIMIT');
    }
  }

  const vals = [inv.date, party ? party.id : null, input.salesman_id || null, (input.sale_type || 'COUNTER').toUpperCase(), mode,
    inv.subtotal, inv.discount, inv.taxable, inv.cgst, inv.sgst, inv.igst, inv.round_off, inv.total, paid];
  let id, invoice_no;
  if (existing) {
    id = existing.id; invoice_no = existing.invoice_no;
    db.prepare(`UPDATE invoices SET date=?,party_id=?,salesman_id=?,sale_type=?,pay_mode=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,paid=?,printed=0 WHERE id=?`)
      .run(...vals, id);
  } else {
    invoice_no = nextNo('INV', inv.date);
    id = Number(db.prepare(
      `INSERT INTO invoices(date,party_id,salesman_id,sale_type,pay_mode,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,invoice_no)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(...vals, invoice_no).lastInsertRowid);
  }

  const insLine = db.prepare(
    `INSERT INTO invoice_lines(invoice_id,item_id,batch_id,qty,free_qty,rate,disc_pct,disc_amt,taxable,gst_rate,cgst,sgst,igst,amount,manual_disc)
     VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
  );
  const dec = db.prepare('UPDATE batches SET qty = qty - ? WHERE id = ? AND qty >= ?');
  for (const r of inv.rows) {
    insLine.run(id, r.item_id, r.batch_id, r.qty, r.free_qty, r.rate, r.disc_pct, r.disc_amt, r.taxable, r.gst_rate, r.cgst, r.sgst, r.igst, r.amount, r.manual_pct);
    const units = r.qty + r.free_qty;
    if (dec.run(units, r.batch_id, units).changes !== 1) throw new HttpError(409, `Stock changed for ${r.item_name}, please retry`, 'NO_STOCK');
  }

  if (party) {
    const lg = db.prepare('INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)');
    lg.run(party.id, inv.date, 'INVOICE', invoice_no, inv.total, 0, `Sale ${invoice_no}`);
    if (paid > 0) {
      const receipt_no = (existing && existing.receipt_no) || nextNo('RCT', inv.date);
      db.prepare('INSERT INTO receipts(receipt_no,date,party_id,salesman_id,invoice_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?,?)')
        .run(receipt_no, inv.date, party.id, input.salesman_id || null, id, mode, paid, `Paid at billing ${invoice_no}`);
      lg.run(party.id, inv.date, 'RECEIPT', receipt_no, 0, paid, `Received at billing (${mode})`);
    }
  }
  return id;
}

const createInvoice = db.transaction((input) => writeInvoice(input));

/**
 * Edit a saved sale: put the old stock back, remove its lines and its ledger/receipt postings,
 * then write the new version under the same id and invoice number. All in one transaction, so a failure changes nothing.
 * Payments recorded later through vouchers are left alone.
 */
const updateInvoice = db.transaction((id, input) => {
  const old = db.prepare('SELECT * FROM invoices WHERE id=?').get(id);
  if (!old) throw new HttpError(404, 'Invoice not found');
  for (const l of db.prepare('SELECT batch_id, qty, free_qty FROM invoice_lines WHERE invoice_id=?').all(id))
    db.prepare('UPDATE batches SET qty = qty + ? WHERE id = ?').run(l.qty + l.free_qty, l.batch_id);
  db.prepare('DELETE FROM invoice_lines WHERE invoice_id=?').run(id);
  const rc = db.prepare('SELECT receipt_no FROM receipts WHERE invoice_id=? ORDER BY id').all(id);
  for (const r of rc) db.prepare("DELETE FROM ledger WHERE type='RECEIPT' AND ref_no=?").run(r.receipt_no);
  db.prepare('DELETE FROM receipts WHERE invoice_id=?').run(id);
  db.prepare("DELETE FROM ledger WHERE type='INVOICE' AND ref_no=?").run(old.invoice_no);
  return writeInvoice({ ...input, date: input.date || old.date }, { id, invoice_no: old.invoice_no, receipt_no: rc.length ? rc[0].receipt_no : null });
});

/** Delete a saved sale: the stock goes back on the shelf and its ledger entries, receipts and lines are removed. All or nothing. */
const deleteInvoice = db.transaction((id) => {
  const old = db.prepare('SELECT * FROM invoices WHERE id=?').get(id);
  if (!old) throw new HttpError(404, 'Invoice not found');
  for (const l of db.prepare('SELECT batch_id, qty, free_qty FROM invoice_lines WHERE invoice_id=?').all(id))
    db.prepare('UPDATE batches SET qty = qty + ? WHERE id = ?').run(l.qty + l.free_qty, l.batch_id);
  db.prepare('DELETE FROM invoice_lines WHERE invoice_id=?').run(id);
  for (const r of db.prepare('SELECT receipt_no FROM receipts WHERE invoice_id=?').all(id))
    db.prepare("DELETE FROM ledger WHERE type='RECEIPT' AND ref_no=?").run(r.receipt_no);
  db.prepare('DELETE FROM receipts WHERE invoice_id=?').run(id);
  db.prepare("DELETE FROM ledger WHERE type='INVOICE' AND ref_no=?").run(old.invoice_no);
  db.prepare('DELETE FROM invoices WHERE id=?').run(id);
  return { id, invoice_no: old.invoice_no, total: old.total };
});

function getInvoice(id) {
  const inv = db.prepare(
    `SELECT i.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state, p.phone party_phone, p.mobiles party_mobiles, p.tel party_tel, p.email party_email, p.pan party_pan, p.fssai party_fssai, s.name salesman_name
     FROM invoices i LEFT JOIN parties p ON p.id=i.party_id LEFT JOIN salesmen s ON s.id=i.salesman_id WHERE i.id=?`
  ).get(id);
  if (!inv) return null;
  inv.lines = db.prepare(
    `SELECT l.*, it.name item_name, it.hsn, it.unit, it.pcs_per_box, b.batch_no, b.exp_date, b.mfg_date, it.mrp
     FROM invoice_lines l JOIN items it ON it.id=l.item_id JOIN batches b ON b.id=l.batch_id WHERE l.invoice_id=? ORDER BY l.id`
  ).all(id);
  // Extras used by the print engine
  // One row per item (a bill line can be split over several batches): what the billing screen needs to reopen the bill
  const grouped = new Map();
  for (const l of inv.lines) {
    const g = grouped.get(l.item_id) || { item_id: l.item_id, item_name: l.item_name, pcs_per_box: l.pcs_per_box, qty: 0, manual_disc: l.manual_disc || 0, rate: l.rate };
    g.qty += l.qty; grouped.set(l.item_id, g);
  }
  inv.edit_lines = [...grouped.values()];
  inv.supply = inv.igst > 0 ? 'INTER' : 'INTRA';
  inv.amount_words = rupeesInWords(inv.total);
  const g = {};
  for (const l of inv.lines) {
    const x = (g[l.gst_rate] ||= { rate: l.gst_rate, rows: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0 });
    x.rows += 1; x.taxable = r2(x.taxable + l.taxable); x.cgst = r2(x.cgst + l.cgst); x.sgst = r2(x.sgst + l.sgst); x.igst = r2(x.igst + l.igst);
  }
  inv.gst_summary = Object.values(g).sort((a, b) => a.rate - b.rate);
  // for the printed bill (Settings › Printing › outstanding): the party's balance before this bill and after it
  if (inv.party_id) {
    const prev = db.prepare(`SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=? AND (date < ? OR (date = ? AND id <
      COALESCE((SELECT MIN(id) FROM ledger WHERE type='INVOICE' AND ref_no=?), 1000000000000)))`).get(inv.party_id, inv.date, inv.date, inv.invoice_no).b;
    inv.party_prev_balance = r2(prev);
    inv.party_balance_after = r2(prev + inv.total - inv.paid);
  }
  return inv;
}

module.exports = { buildInvoice, createInvoice, updateInvoice, deleteInvoice, getInvoice, settings, partyBalance };
