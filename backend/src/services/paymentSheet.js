const db = require('../db');
const { HttpError, today } = require('../utils/misc');
const { r2 } = require('../utils/gst');
const { partyBalance } = require('./billing');
const { recordVoucher } = require('./vouchers');

/**
 * Payments from a photo of a handwritten sheet (text read on the device by OCR).
 * One row per line:   party name, bill amount, bill amount, ...  [separator] payment
 *   "Ram General Store 1200, 850 - 2000"  -> bills 1200 and 850, payment 2000
 *   "Ram General Store 1200, 850"         -> bills 1200 and 850, payment = 2050 (both in full)
 * The payment is the last number when it is not joined to the bills by a comma, or follows
 * "paid", "rcvd", "cash" and similar words. Everything here is plain character work (no regex)
 * so the Swift engine gives the same answer.
 */

const isDigit = (c) => c >= '0' && c <= '9';
const isAsciiLetter = (c) => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
const isSpace = (c) => c === ' ' || c === '\t' || c === '\r' || c === '\n';
const PAY_WORDS = ['paid', 'pay', 'payment', 'rcvd', 'recd', 'received', 'recieved', 'rec', 'cash', 'amt', 'jama', 'diya'];
const STOP_WORDS = ['m', 's', 'ms', 'mss', 'shri', 'sri', 'shree', 'the', 'and', 'store', 'stores', 'traders', 'trader', 'trading',
  'general', 'genral', 'gen', 'kirana', 'enterprises', 'enterprise', 'ent', 'agency', 'agencies', 'mart', 'shop', 'co', 'bros', 'brothers'];

/** OCR often reads 0 as O and 1 as l / I / | when they sit inside a number. */
function fixDigits(s) {
  const ch = s.split('');
  for (let i = 0; i < ch.length; i++) {
    const c = ch[i];
    const near = (i > 0 && isDigit(ch[i - 1])) || (i + 1 < ch.length && isDigit(ch[i + 1]));
    if (!near) continue;
    if (c === 'O' || c === 'o') ch[i] = '0';
    else if (c === 'l' || c === 'I' || c === '|') ch[i] = '1';
  }
  return ch.join('');
}

function trimChars(s, set) {
  let a = 0, b = s.length;
  while (a < b && set.includes(s[a])) a++;
  while (b > a && set.includes(s[b - 1])) b--;
  return s.slice(a, b);
}

/** Lower-case words of a name (ASCII letters and digits; anything else splits words). */
function words(s) {
  const out = [];
  let w = '';
  for (const c of s.toLowerCase().split('')) {
    if (isAsciiLetter(c) || isDigit(c)) w += c;
    else { if (w) out.push(w); w = ''; }
  }
  if (w) out.push(w);
  return out;
}

function bigrams(s) {
  const out = [];
  for (let i = 0; i + 1 < s.length; i++) out.push(s.slice(i, i + 2));
  return out;
}

/** How alike two party names are, 0 to 1. */
function nameScore(a, b) {
  const wa = words(a), wb = words(b);
  const na = wa.join(''), nb = wb.join('');
  if (!na || !nb) return 0;
  if (na === nb) return 1;
  const A = bigrams(na), B = bigrams(nb);
  let common = 0;
  const left = B.slice();
  for (const g of A) { const k = left.indexOf(g); if (k >= 0) { common++; left.splice(k, 1); } }
  let score = A.length + B.length ? (2 * common) / (A.length + B.length) : 0;
  const ca = wa.filter((w) => !STOP_WORDS.includes(w)).join(''), cb = wb.filter((w) => !STOP_WORDS.includes(w)).join('');
  if (!ca.length) score = Math.min(score, 0.5);   // only words like "Traders" or "Store": not enough to tell parties apart
  if (ca.length >= 3 && cb.length >= 3 && (ca === cb || cb.startsWith(ca) || ca.startsWith(cb))) score = Math.max(score, ca === cb ? 0.95 : 0.85);
  return Math.round(score * 100) / 100;
}

/** Splits one written line into the party name, the bill amounts and the payment. */
function parseLine(raw) {
  let s = fixDigits(String(raw).split('₹').join(' '));
  s = s.split('/-').join(' ');
  // a serial number in front: "1. Ram Store ..." or "1) Ram Store ..."
  let i = 0;
  while (i < s.length && isSpace(s[i])) i++;
  let j = i;
  while (j < s.length && isDigit(s[j])) j++;
  if (j > i && j < s.length && (s[j] === '.' || s[j] === ')')) s = s.slice(j + 1);
  let first = -1;
  for (let k = 0; k < s.length; k++) if (isDigit(s[k])) { first = k; break; }
  const namePart = first < 0 ? s : s.slice(0, first);
  let name = trimChars(namePart, ' \t,.-:=;|/');
  // "Rs", "paid", "cash" written before the first amount belong to the amount, not the name
  let payWord = false;
  for (;;) {
    const sp = name.lastIndexOf(' ');
    const tail = trimChars(name.slice(sp + 1).toLowerCase(), '.:-=');
    if (tail !== 'rs' && !PAY_WORDS.includes(tail)) break;
    if (tail !== 'rs') payWord = true;
    name = sp < 0 ? '' : trimChars(name.slice(0, sp), ' \t,.-:=;|/');
  }
  const nums = [];
  if (first >= 0) {
    let sep = '';
    let k = first;
    while (k < s.length) {
      if (isDigit(s[k])) {
        let t = '';
        while (k < s.length && isDigit(s[k])) t += s[k++];
        // Indian grouping inside one amount: 1,200 or 1,20,000 (commas between bills follow 3 or more digits)
        let group = t.length, firstGroup = true;
        while (k < s.length && s[k] === ',' && ((firstGroup && group === 1) || (!firstGroup && group === 2))) {
          let e = k + 1;
          while (e < s.length && isDigit(s[e])) e++;
          const run = e - (k + 1);
          if (!(run === 3 || (run === 2 && e < s.length && s[e] === ','))) break;
          t += s.slice(k + 1, e);
          k = e; group = run; firstGroup = false;
        }
        if (k + 1 < s.length && s[k] === '.' && isDigit(s[k + 1])) {
          t += s[k++];
          while (k < s.length && isDigit(s[k])) t += s[k++];
        }
        nums.push({ value: Number(t), sep });
        sep = '';
      } else sep += s[k++];
    }
  }
  const sepWords = (sep) => words(sep);
  const isPayment = (n) => n.sep.length > 0 && (!n.sep.includes(',') || sepWords(n.sep).some((w) => PAY_WORDS.includes(w)));
  let bills = nums.map((n) => n.value), payment = null;
  const last = nums[nums.length - 1];
  if (nums.length >= 2 && isPayment(last)) { payment = last.value; bills = bills.slice(0, -1); }
  else if (nums.length === 1 && (payWord || sepWords(last.sep).some((w) => PAY_WORDS.includes(w)))) { payment = last.value; bills = []; }
  const amount = payment !== null ? r2(payment) : r2(bills.reduce((a, b) => a + b, 0));
  return { name, bills: bills.map(r2), payment: payment === null ? null : r2(payment), amount };
}

/** Reads every line and finds the party and bills each one means. */
function parseSheet(b) {
  const text = String((b && b.text) || '').split('\r\n').join('\n').split('\r').join('\n');
  const parties = db.prepare(`SELECT id,name FROM parties WHERE active=1 AND type <> 'SUPPLIER' ORDER BY name, id`).all();
  const billsOf = db.prepare('SELECT id,invoice_no,date,total,paid FROM invoices WHERE party_id=? ORDER BY date DESC, id DESC');
  const rows = [];
  let lineNo = 0;
  for (const line of text.split('\n')) {
    lineNo++;
    if (!trimChars(line, ' \t\r').length) continue;
    const p = parseLine(line);
    if (!p.name && !p.bills.length && p.payment === null) continue;
    const scored = parties.map((x) => ({ id: x.id, name: x.name, score: nameScore(p.name, x.name) }))
      .filter((x) => x.score >= 0.3)
      .sort((x, y) => y.score - x.score || (x.name < y.name ? -1 : x.name > y.name ? 1 : x.id - y.id));
    const best = scored.length && scored[0].score >= 0.6 ? scored[0] : null;
    const problems = [];
    if (!p.name) problems.push('No party name');
    else if (!best) problems.push('Party not found');
    else if (scored.length > 1 && scored[1].score === best.score) problems.push('More than one party matches');
    if (!(p.amount > 0)) problems.push('No amount');
    const used = new Set();
    const billRefs = p.bills.map((amt) => {
      if (!best) return { amount: amt, invoice_no: null };
      const hit = billsOf.all(best.id).find((v) => !used.has(v.id) && Math.abs(v.total - amt) < 0.5);
      if (!hit) return { amount: amt, invoice_no: null };
      used.add(hit.id);
      return { amount: amt, invoice_no: hit.invoice_no, invoice_id: hit.id, date: hit.date };
    });
    rows.push({
      line: lineNo, text: trimChars(line, ' \t\r'), name: p.name,
      party_id: best ? best.id : null, party_name: best ? best.name : null,
      balance: best ? r2(partyBalance(best.id)) : null, score: best ? best.score : 0,
      candidates: scored.slice(0, 3).map((x) => ({ id: x.id, name: x.name, score: x.score })),
      bills: billRefs, payment: p.payment, amount: p.amount,
      reference: referenceFor(billRefs), problems,
    });
  }
  const ready = rows.filter((r) => !r.problems.length);
  return { rows, lines: rows.length, ready: ready.length, total: r2(ready.reduce((a, r) => a + r.amount, 0)) };
}

/** "Bills A000412, A000418, 950" for the receipt's reference. */
function referenceFor(bills) {
  if (!bills.length) return null;
  return 'Bills ' + bills.map((x) => x.invoice_no || String(x.amount)).join(', ');
}

/** Saves the checked rows as receipts, all or nothing. */
const saveSheet = db.transaction((b) => {
  const rows = (b && Array.isArray(b.rows)) ? b.rows : [];
  if (!rows.length) throw new HttpError(400, 'No payments to save');
  const date = (b && b.date) || today();
  const mode = (b && b.mode) || 'CASH';
  const saved = rows.map((r, i) => {
    try {
      const v = recordVoucher({ party_id: r.party_id, amount: r.amount, date, mode, reference: r.reference || null, direction: 'RECEIVED' });
      const p = db.prepare('SELECT name FROM parties WHERE id=?').get(r.party_id);
      return { voucher_no: v.voucher_no, party_id: r.party_id, party: p.name, amount: v.amount, balance: v.balance };
    } catch (e) {
      throw new HttpError(e.status || 400, `Row ${i + 1}: ${e.message}`);
    }
  });
  return { saved, count: saved.length, total: r2(saved.reduce((a, x) => a + x.amount, 0)) };
});

module.exports = { parseSheet, saveSheet, parseLine, nameScore };
