/**
 * Route validation, report-only (docs/API_ERRORS.md): the main write routes check what the apps send and log anything
 * unexpected (a number sent as text, a missing name, a date in another format). Nothing is rejected yet, so no app can
 * break; once the logs stay quiet across app versions, REJECT can be switched on and the same checks answer 400 INVALID.
 */
const REJECT = false;

const isDate = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);
const TYPES = {
  id: (v) => (Number.isInteger(v) && v > 0 ? null : typeof v === 'string' && /^\d+$/.test(v) ? 'is a number sent as text' : 'is not an id'),
  num: (v) => (typeof v === 'number' && Number.isFinite(v) ? null : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? 'is a number sent as text' : 'is not a number'),
  str: (v) => (typeof v === 'string' ? null : 'is not text'),
  date: (v) => (isDate(v) ? null : 'is not a date (yyyy-mm-dd)'),
  bool: (v) => (typeof v === 'boolean' || v === 0 || v === 1 ? null : 'is not true/false'),
  lines: (v) => (Array.isArray(v) ? (v.length ? null : 'is empty') : 'is not a list'),
};

// field: [type, required]; `lines` items are checked with `line`
const S = (fields, line) => ({ fields, line });
const SCHEMAS = [
  [/^\/invoices(\/\d+)?$/, S({ party_id: ['id'], date: ['date'], lines: ['lines', true], discount: ['num'], paid_amount: ['num'] },
    { item_id: ['id', true], batch_id: ['id'], qty: ['num'], rate: ['num'], disc_pct: ['num'], boxes: ['num'], pcs: ['num'] })],
  [/^\/purchases(\/\d+)?$/, S({ party_id: ['id'], date: ['date'], supplier_invoice_no: ['str'], lines: ['lines', true], discount: ['num'], cgst: ['num'], sgst: ['num'], igst: ['num'], round_off: ['num'] },
    { item_id: ['id'], qty: ['num', true], rate: ['num'], mrp: ['num'], batch_no: ['str'] })],
  [/^\/parties(\/\d+)?$/, S({ name: ['str', true], opening_balance: ['num'], gstin: ['str'], phone: ['str'], credit_limit: ['num'] })],
  [/^\/items(\/\d+)?$/, S({ name: ['str', true], gst_rate: ['num'], mrp: ['num'], retail_price: ['num'], wholesale_price: ['num'], purchase_price: ['num'], hsn: ['str'] })],
];

function checkFields(fields, obj, prefix, out, partial) {
  for (const [k, [t, req]] of Object.entries(fields)) {
    const v = obj[k];
    if (v === undefined || v === null || v === '') { if (req && !partial) out.push(`${prefix}${k} is missing`); continue; }
    const p = TYPES[t](v);
    if (p) out.push(`${prefix}${k} ${p}`);
  }
}

/** Problems with one request body (empty = fine). PUT may send only the fields it changes. */
function check(method, path, body) {
  if (method !== 'POST' && method !== 'PUT') return [];
  const hit = SCHEMAS.find(([re]) => re.test(path));
  if (!hit || !body || typeof body !== 'object') return [];
  const { fields, line } = hit[1];
  const out = [];
  const partial = method === 'PUT';
  checkFields(fields, body, '', out, partial);
  if (line && Array.isArray(body.lines)) body.lines.forEach((l, i) => { if (l && typeof l === 'object') checkFields(line, l, `lines[${i}].`, out, false); else out.push(`lines[${i}] is not an object`); });
  return out;
}

// each kind of problem is logged once per run, so a busy screen does not flood the log
const seen = new Set();
function report(method, path, problems, log = console.warn) {
  const route = path.replace(/\/\d+/g, '/:id');
  for (const p of problems) {
    const k = `${method} ${route} ${p.replace(/\[\d+\]/g, '[]')}`;
    if (seen.has(k)) continue;
    seen.add(k);
    log(`[validate] ${k}`);
  }
}

/** Express middleware for /api. */
function middleware(req, res, next) {
  const problems = check(req.method, req.path, req.body);
  if (problems.length) {
    report(req.method, req.path, problems);
    if (REJECT) { const { HttpError } = require('./misc'); return next(new HttpError(422, `Please check: ${problems.join('; ')}`)); }
  }
  next();
}

module.exports = { check, report, middleware, REJECT };
