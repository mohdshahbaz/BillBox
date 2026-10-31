// Indian financial year: 1 April to 31 March. Label "2026-27" = 1 Apr 2026 .. 31 Mar 2027.
const db = require('../db');
const { today, HttpError } = require('./misc');

const startYearOf = (date) => { const y = +date.slice(0, 4), m = +date.slice(5, 7); return m >= 4 ? y : y - 1; };
const labelOf = (s) => `${s}-${String(s + 1).slice(2)}`;
const rangeOf = (s) => ({ label: labelOf(s), start_year: s, from: `${s}-04-01`, to: `${s + 1}-03-31` });
const currentStart = () => startYearOf(today());

/** Accepts "2026-27", "2026-2027", "2026" or nothing (= the year that contains today). */
function fyRange(label) {
  if (label === undefined || label === null || label === '') return { ...rangeOf(currentStart()), current: true };
  const m = /^(\d{4})(?:-(\d{2}|\d{4}))?$/.exec(String(label).trim());
  if (!m) throw new HttpError(400, 'Financial year must look like 2026-27');
  const s = +m[1];
  if (m[2] && (+m[2].slice(-2) !== (s + 1) % 100)) throw new HttpError(400, `Financial year ${label} is not consecutive. Use ${labelOf(s)}.`);
  return { ...rangeOf(s), current: s === currentStart() };
}

/** Every financial year that has data, plus the current one, newest first. */
/** The year a company's books are for, when they are one year's books (Marg style); else null (books for every year). */
function booksFy() {
  const r = db.prepare("SELECT value FROM settings WHERE key='books_fy'").get();
  return r && r.value ? String(r.value) : null;
}

function fyList() {
  const own = booksFy();
  if (own) { const s = +own.slice(0, 4); return [{ ...rangeOf(s), current: s === currentStart() }]; }
  const q = (sql) => db.prepare(sql).get().d;
  const dates = [q('SELECT MIN(date) d FROM invoices'), q('SELECT MIN(date) d FROM purchases'), q('SELECT MIN(date) d FROM receipts'),
    q('SELECT MIN(date) d FROM payments'), q("SELECT MIN(date) d FROM ledger")].filter(Boolean);
  const maxes = [q('SELECT MAX(date) d FROM invoices'), q('SELECT MAX(date) d FROM purchases')].filter(Boolean);
  const cur = currentStart();
  const first = dates.length ? Math.min(...dates.map(startYearOf), cur) : cur;
  const last = maxes.length ? Math.max(...maxes.map(startYearOf), cur) : cur;   // a bill dated in a later year still gets its year listed
  const out = [];
  for (let s = last; s >= first; s--) out.push({ ...rangeOf(s), current: s === cur });
  return out;
}

module.exports = { fyRange, fyList, booksFy, startYearOf, labelOf, rangeOf };
