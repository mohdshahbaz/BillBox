const db = require('../db');

const today = () => new Date().toLocaleDateString('en-CA'); // YYYY-MM-DD, local time

/** Short financial-year label for numbering. Accepts a Date or a YYYY-MM-DD string (the bill's own date decides the year). */
function fy(d = new Date()) {
  const y = typeof d === 'string' ? +d.slice(0, 4) : d.getFullYear();
  const mo = typeof d === 'string' ? +d.slice(5, 7) - 1 : d.getMonth();
  const start = mo >= 3 ? y : y - 1; // Indian FY: 1 Apr - 31 Mar
  return `${String(start).slice(2)}-${String(start + 1).slice(2)}`;
}

/**
 * Numbering of a series (INV, RCT, PUR, PAY, DN), as Settings › Billing & Dashboard › Numbering says:
 *   num_<SERIES>_prefix  text shown instead of the series name ("A", "AKE/S")      default: the series name
 *   num_<SERIES>_digits  1 to 9 digits for that series (Marg: A000001 = 6, DNB00001 = 5)
 *   num_fy               '0' leaves the year out (one running count)                default: INV/26-27/00001
 *   num_digits           3 to 6 digits for every series without its own            default: 5
 * A new number always follows the highest one already used with the same beginning (bills imported from Marg,
 * or made before the numbering was changed), so numbers carry on from the last bill and never clash.
 */
const SERIES = { INV: ['invoices', 'invoice_no'], RCT: ['receipts', 'receipt_no'], PUR: ['purchases', 'purchase_no'], PAY: ['payments', 'voucher_no'], DN: ['debit_notes', 'note_no'] };

function numbering(prefix, date) {
  const get = (k) => { const r = db.prepare('SELECT value FROM settings WHERE key=?').get(k); return r && r.value !== null ? String(r.value) : ''; };
  const label = get(`num_${prefix}_prefix`).trim() || prefix;
  const withFy = get('num_fy') !== '0';
  const own = parseInt(get(`num_${prefix}_digits`), 10);
  const d = parseInt(get('num_digits'), 10);
  const digits = own >= 1 && own <= 9 ? own : d >= 3 && d <= 6 ? d : 5;
  const year = fy(date || new Date());
  const sep = /[A-Za-z0-9]$/.test(label) ? '/' : '';
  const head = withFy ? `${label}${sep}${year}/` : label;
  return { prefix, label, withFy, digits, head, key: withFy ? `${prefix}/${year}` : prefix };
}

/** The highest number already used after this beginning ({ n, no }), e.g. A000422 for "A". */
function lastUsed(prefix, head) {
  const t = SERIES[prefix];
  let best = { n: 0, no: '' };
  if (!t) return best;
  for (const r of db.prepare(`SELECT ${t[1]} AS no FROM ${t[0]} WHERE substr(${t[1]}, 1, ?) = ?`).all(head.length, head)) {
    const rest = String(r.no).slice(head.length);
    if (/^[0-9]+$/.test(rest) && parseInt(rest, 10) > best.n) best = { n: parseInt(rest, 10), no: String(r.no) };
  }
  return best;
}

/** The number the next document of the series will get, without using it up. */
function peekNo(prefix, date) {
  const s = numbering(prefix, date);
  const c = db.prepare('SELECT value FROM counters WHERE key = ?').get(s.key);
  const v = Math.max(c ? Number(c.value) : 0, lastUsed(prefix, s.head).n) + 1;
  return { ...s, next: v, next_no: s.head + String(v).padStart(s.digits, '0'), last_no: lastUsed(prefix, s.head).no };
}

function nextNo(prefix, date) {
  const s = numbering(prefix, date);
  const used = lastUsed(prefix, s.head).n;
  db.prepare('INSERT INTO counters(key,value) VALUES(?,0) ON CONFLICT(key) DO NOTHING').run(s.key);
  db.prepare('UPDATE counters SET value = MAX(value, ?) + 1 WHERE key = ?').run(used, s.key);
  const v = db.prepare('SELECT value FROM counters WHERE key = ?').get(s.key).value;
  return s.head + String(v).padStart(s.digits, '0');
}

/** Settings › Numbering › Next number: the next document of the series gets `next` (it must come after the last one used). */
function setNext(prefix, next, date) {
  if (!SERIES[prefix]) throw new HttpError(400, 'Unknown series');
  const n = parseInt(next, 10);
  if (!(n >= 1) || String(n) !== String(next).trim()) throw new HttpError(400, 'Enter the next number as a whole number, 1 or more');
  const s = numbering(prefix, date);
  const used = lastUsed(prefix, s.head);
  if (n <= used.n) throw new HttpError(409, `The next number must come after ${used.no}, the last one used`);
  db.prepare('INSERT INTO counters(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run(s.key, n - 1);
  return peekNo(prefix, date);
}

class HttpError extends Error {
  constructor(status, message, code) { super(message); this.status = status; this.code = code; }
}

const h = (fn) => (req, res, next) => { try { fn(req, res, next); } catch (e) { next(e); } };

/** Same as h() for async handlers. */
const ha = (fn) => (req, res, next) => { Promise.resolve().then(() => fn(req, res, next)).catch(next); };

const blank = (v) => (v === undefined || v === null || String(v).trim() === '' ? null : v);

/** Weekday list for a route: accepts [1,3], "1,3" or a single number; returns sorted unique 0-6 as "1,3" (or null). */
function normDays(v) {
  if (v === undefined || v === null || v === '') return null;
  const a = (Array.isArray(v) ? v : String(v).split(',')).map((x) => parseInt(x)).filter((x) => x >= 0 && x <= 6);
  const u = [...new Set(a)].sort();
  return u.length ? u.join(',') : null;
}

module.exports = { normDays, today, fy, nextNo, peekNo, setNext, SERIES, HttpError, h, ha, blank };
