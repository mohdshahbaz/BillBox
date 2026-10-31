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

module.exports = { recordVoucher, getVoucher };
