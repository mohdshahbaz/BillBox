const db = require('../db');
const { today, nextNo, HttpError, blank } = require('../utils/misc');
const { r2 } = require('../utils/gst');
const { partyBalance, settings } = require('./billing');
const { rupeesInWords } = require('../utils/words');

/**
 * Cash/bank voucher against a party.
 *   RECEIVED -> money in  (receipts table, ledger credit)  e.g. customer pays us
 *   PAID     -> money out (payments table, ledger debit)   e.g. we pay a supplier
 * Ledger balance = debit - credit: positive = party owes us, negative = we owe the party.
 */
const recordVoucher = db.transaction((b) => {
  const amount = r2(Number(b.amount));
  if (!b.party_id || !(amount > 0)) throw new HttpError(400, 'Party and a positive amount are required');
  if (!db.prepare('SELECT 1 FROM parties WHERE id=?').get(b.party_id)) throw new HttpError(404, 'Party not found');
  const direction = String(b.direction || 'RECEIVED').toUpperCase();
  if (!['RECEIVED', 'PAID'].includes(direction)) throw new HttpError(400, 'Direction must be RECEIVED or PAID');
  const date = b.date || today();
  const mode = String(b.mode || 'CASH').toUpperCase();
  const lg = db.prepare('INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)');
  let no;
  if (direction === 'RECEIVED') {
    no = nextNo('RCT', date);
    db.prepare('INSERT INTO receipts(receipt_no,date,party_id,salesman_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?)')
      .run(no, date, b.party_id, blank(b.salesman_id), mode, amount, blank(b.reference));
    lg.run(b.party_id, date, 'RECEIPT', no, 0, amount, `Payment received (${mode})${b.reference ? ' ' + b.reference : ''}`);
  } else {
    no = nextNo('PAY', date);
    db.prepare('INSERT INTO payments(voucher_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)')
      .run(no, date, b.party_id, mode, amount, blank(b.reference));
    lg.run(b.party_id, date, 'PAYMENT', no, amount, 0, `Payment made (${mode})${b.reference ? ' ' + b.reference : ''}`);
  }
  return { voucher_no: no, direction, amount, balance: r2(partyBalance(b.party_id)) };
});

/** Everything the print engine needs for a receipt / payment voucher. */
function getVoucher(voucherNo) {
  const rec = db.prepare('SELECT receipt_no no, date, party_id, mode, amount, reference FROM receipts WHERE receipt_no=?').get(voucherNo);
  const pay = rec ? null : db.prepare('SELECT voucher_no no, date, party_id, mode, amount, reference FROM payments WHERE voucher_no=?').get(voucherNo);
  const v = rec || pay;
  if (!v) throw new HttpError(404, 'Voucher not found');
  const party = db.prepare('SELECT id,name,address,gstin,phone,mobiles FROM parties WHERE id=?').get(v.party_id);
  const co = settings();
  return {
    ...v, direction: rec ? 'RECEIVED' : 'PAID', title: rec ? 'Receipt Voucher' : 'Payment Voucher', party,
    amount_words: rupeesInWords(v.amount), balance: r2(partyBalance(v.party_id)),
    company: { name: co.company_name, address: co.company_address, gstin: co.company_gstin, phone: co.company_phone },
  };
}

/**
 * Delete one line of a party's ledger.
 *   RECEIPT / PAYMENT  -> the voucher behind it goes too (and a bill's "paid" amount comes down by it)
 *   OPENING            -> the opening balance line is removed
 *   INVOICE / PURCHASE / DEBIT_NOTE -> refused: those lines belong to a bill, so the bill is deleted or edited instead
 * One transaction: the ledger, the voucher and the bill's paid amount change together or not at all.
 */
const deleteLedgerEntry = db.transaction((id) => {
  const e = db.prepare('SELECT * FROM ledger WHERE id=?').get(id);
  if (!e) throw new HttpError(404, 'Ledger entry not found');
  if (e.type === 'RECEIPT') {
    const r = db.prepare('SELECT id, invoice_id, amount FROM receipts WHERE receipt_no=?').get(e.ref_no);
    if (r) {
      if (r.invoice_id) db.prepare('UPDATE invoices SET paid = MAX(0, ROUND(paid - ?, 2)) WHERE id=?').run(r.amount, r.invoice_id);
      db.prepare('DELETE FROM receipts WHERE id=?').run(r.id);
    }
  } else if (e.type === 'PAYMENT') {
    const p = db.prepare('SELECT id, purchase_id, amount FROM payments WHERE voucher_no=?').get(e.ref_no);
    if (p) {
      if (p.purchase_id) db.prepare('UPDATE purchases SET paid = MAX(0, ROUND(paid - ?, 2)) WHERE id=?').run(p.amount, p.purchase_id);
      db.prepare('DELETE FROM payments WHERE id=?').run(p.id);
    }
  } else if (e.type !== 'OPENING') {
    throw new HttpError(400, 'This line belongs to a bill. Delete or edit the bill itself to remove it.');
  }
  db.prepare('DELETE FROM ledger WHERE id=?').run(e.id);
  return { ok: true, deleted: { type: e.type, ref_no: e.ref_no }, balance: r2(partyBalance(e.party_id)) };
});

module.exports = { recordVoucher, getVoucher, deleteLedgerEntry };
