/**
 * Parser for text read from a supplier's GST tax invoice (one string per PDF page).
 *
 *   1. selectOriginalPages : only pages of the "Original" / "Original Copy" are read; Duplicate / Triplicate /
 *                            Transporter / Office copies are skipped. Unlabelled continuation pages stay with the copy before them.
 *   2. mergePages          : page 2+ lose the repeated company header, column header, "Page x of y", "Continued", b/f and c/f lines,
 *                            so the item rows continue cleanly from one page to the next.
 *   3. parseItems          : column-aware. The item name is the description column (the second column after the serial number);
 *                            HSN, Qty, Unit, Price (rate) and Amount are taken from their own columns, then renumbered 1..n.
 *   4. parseTotals         : Discount, CGST, SGST, IGST, Round off and Grand total, read from the block around the grand total.
 *   5. parseSupplier       : name, address, GSTIN, state code, tel, phone, mobiles, FSSAI, PAN, email.
 *
 * Everything is a suggestion: the screen shows it for review and nothing is saved by the parser.
 * Pure functions (no DB access); the stock list and supplier list are passed in.
 */
const GSTIN_RE = /\b\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b/g;
const MONTHS = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
const GST_RATES = [0, 3, 5, 12, 18, 28];

const pad = (n) => String(n).padStart(2, '0');
const toNum = (s) => Number(String(s).replace(/[,\s]/g, ''));
const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
const tokensOf = (s) => new Set(norm(s).split(' ').filter((t) => t.length > 1));
const cleanLines = (t) => String(t || '').split(/\r?\n/).map((l) => l.replace(/[\u00a0\t]+/g, ' ').replace(/\s+/g, ' ').replace(/(\d)\s+%/g, '$1%').trim()).filter(Boolean);

// ------------------------------------------------------------------ 1. Original pages only
const KIND_RES = [
  ['original', /\boriginal\b(?!\s+(?:invoice\s+)?(?:no|number|date|ref))/i],
  ['duplicate', /\bduplicate\b/i],
  ['triplicate', /\btriplicate\b/i],
  ['other', /\b(?:extra|office|transporter|customer|driver|accounts?)\s+copy\b/i],
];

/** Which copy label does this page carry? 'original' | 'duplicate' | 'triplicate' | 'other' | 'multi' (several labels listed) | null (no label) */
function copyKind(pageText) {
  const lines = cleanLines(pageText);
  // labels sit in the header or footer; scanning the middle would catch words inside item names
  const zone = [...lines.slice(0, 14), ...lines.slice(-10)].join('\n');
  const found = KIND_RES.filter(([, re]) => re.test(zone)).map(([k]) => k);
  if (found.length === 0) return null;
  if (found.length > 1) return 'multi';
  return found[0];
}

const fingerprint = (pageText) => new Set(cleanLines(pageText).filter((l) => /\d/.test(l)).map(norm));
function jaccard(a, b) {
  if (!a.size || !b.size) return 0;
  let hit = 0; for (const x of a) if (b.has(x)) hit++;
  return hit / (a.size + b.size - hit);
}

function selectOriginalPages(pages) {
  const kinds = pages.map(copyKind);
  const definite = kinds.filter((k) => k && k !== 'multi');
  const skipped = [];
  let keep;
  let note = '';
  if (!definite.length) {
    keep = pages.map((_, i) => i);
    if (pages.length > 1) note = 'No copy labels (Original / Duplicate) found; all pages were read and repeated pages dropped.';
  } else {
    let cur = null; keep = [];
    kinds.forEach((k, i) => {
      if (k && k !== 'multi') cur = k;
      const effective = cur || 'original';           // pages before the first label belong to the first (original) copy
      if (effective === 'original') keep.push(i);
      else skipped.push({ page: i + 1, kind: cur });
    });
    if (!keep.length) {
      keep = pages.map((_, i) => i); skipped.length = 0;
      note = 'No "Original" copy found on any page; all pages were read.';
    }
  }
  // Same content twice (labels missing or ambiguous): keep the first
  const seen = [];
  keep = keep.filter((i) => {
    const fp = fingerprint(pages[i]);
    if (fp.size >= 5 && seen.some((s) => jaccard(s, fp) >= 0.85)) { skipped.push({ page: i + 1, kind: 'repeat' }); return false; }
    seen.push(fp); return true;
  });
  return { used: keep.map((i) => i + 1), skipped, note, pages: keep.map((i) => pages[i]) };
}

// ------------------------------------------------------------------ 2. Merge pages
const TOTAL_MARK = /(^\W*(?:less|add)\s*:|sub\s*-?\s*total|total\s*(amount|taxable|qty|quantity)|grand\s*total|amount\s*(chargeable\s*)?in\s*words|bank\s*details|terms\s*&?\s*conditions|taxable\s*value|total\s*invoice)/i;
const CONT_MARK = /(^|\s)(continued|contd\.?|c\/f|b\/f|c\/o|b\/d|carried\s*forward|brought\s*forward|page\s*total|please\s*turn\s*over)(?=\s|$|\.)/i;
/** Page furniture that carries a running total: "b/d 71.00 BOX 1,30,564.22", "Totals c/o 71.00 BOX 1,30,564.22". Never an item row. */
const CARRY_LINE = /^\W*(?:sub\s*)?(?:totals?\s*)?(?:b\/d|b\/f|c\/o|c\/f|brought\s*forward|carried\s*(?:forward|over)|page\s*total)\b/i;
const PAGE_NO = /^\W*(?:page\s*)?\d+\s*(?:of|\/)\s*\d+\W*$/i;
const COPY_LABEL = /^\W*(?:original|duplicate|triplicate)(?:\s+(?:copy|for\s+[\w\/ ]+))?\W*$/i;

/** One line array per page; later pages have repeated headers and page furniture removed. */
function mergePages(pageTexts) {
  const out = [];
  let headerSet = null;
  pageTexts.forEach((t, p) => {
    let lines = cleanLines(t);
    const hdr = lines.findIndex((l) => detectColumns(l));
    if (p === 0) {
      headerSet = new Set(lines.slice(0, hdr >= 0 ? hdr + 1 : 8).map(norm));
    } else {
      lines = lines.filter((l) => {
        const n = norm(l);
        return !(headerSet.has(n) || CARRY_LINE.test(l) || /^\W*code\W*$/i.test(l) || PAGE_NO.test(l) || COPY_LABEL.test(l) || detectColumns(l) || (CONT_MARK.test(l) && !/\d{3,}/.test(l.replace(CONT_MARK, ''))));
      });
    }
    out.push({ page: p, lines, hdr: p === 0 ? hdr : -1 });
  });
  return out;
}

// ------------------------------------------------------------------ 3. Items
const COLS = [
  ['sno', /(?:^|\s)(?:s\.?\s?no\.?|sl\.?\s?no\.?|sr\.?\s?no\.?|sl|sr|s\.n\.?|no\.?|#)(?=\s|$)/i],
  ['desc', /(?:description(?:\s+of\s+(?:goods|items?))?|particulars|item(?:\s+name)?|product(?:\s+name)?|goods)/i],
  ['hsn', /\b(?:hsn|sac)(?:\s*\/\s*(?:hsn|sac))?(?:\s*code)?\b/i],
  ['qty', /\b(?:qty|quantity|nos)\b\.?/i],
  ['unit', /\b(?:unit|uom|per)\b/i],
  ['mrp', /\bmrp\b/i],
  ['rate', /\b(?:rate|price)\b/i],
  ['disc', /\bdisc(?:ount)?\b/i],
  ['tax', /\b(?:gst|cgst|sgst|igst|tax)\b/i],
  ['amount', /\b(?:amount|amt|value|total)\b/i],
];

/** Column order of an item-table header line (['sno','desc','hsn','qty',...]) or null when the line is not a header. */
function detectColumns(line) {
  const hits = [];
  for (const [k, re] of COLS) { const m = re.exec(line); if (m) hits.push([m.index, k]); }
  const keys = hits.map((h) => h[1]);
  if (!keys.includes('desc') || !keys.includes('qty') || !(keys.includes('amount') || keys.includes('rate'))) return null;
  return hits.sort((a, b) => a[0] - b[0]).map((h) => h[1]);
}

const KIND_OK = {
  hsn: /^\d{4,8}$/, qty: /^\d[\d,]*(\.\d+)?$/, unit: /^[A-Za-z]{1,8}\.?$/, mrp: /^\d[\d,]*(\.\d+)?$/,
  rate: /^\d[\d,]*(\.\d+)?$/, amount: /^\d[\d,]*(\.\d+)?$/, disc: /^-?\d[\d,]*(\.\d+)?%?$/, tax: /^-?\d+(\.\d+)?%?$/, sno: /^\d{1,3}\.?$/,
};
const UNITS = new Set(['PCS', 'PC', 'NOS', 'NO', 'BOX', 'BOXES', 'CASE', 'CS', 'CTN', 'KG', 'KGS', 'GM', 'GMS', 'LTR', 'LT', 'L', 'ML', 'PKT', 'PKTS', 'PACK', 'DOZ', 'SET', 'BAG', 'BTL', 'JAR', 'BDL', 'MTR']);
// floor: how far below qty*rate the printed amount may fall and still be believed (0.4 = up to a 60% line
// discount). Columns already matched by header position (rowFromColumns) get more room — a scheme discount can
// run steeper than that — than numbers merely guessed from an unstructured line (rowByNumbers).
const plausible = (q, r, a, floor = 0.4) => {
  if (!(q > 0 && a > 0)) return false;
  if (!(r > 0)) return true;
  const g = q * r;
  return Math.abs(g - a) <= Math.max(0.6, g * 0.01) || a < g * 0.995 && a >= g * floor || GST_RATES.some((x) => x > 0 && Math.abs(g * (1 + x / 100) - a) <= Math.max(0.6, a * 0.01));
};

function rowFromColumns(line, cols) {
  let toks = line.split(' ');
  const hasUnit = cols.includes('unit');
  // "10PCS" glued: split it so that qty and unit are separate tokens
  if (hasUnit) toks = toks.flatMap((t, ti) => { if (ti < toks.length - (cols.length - cols.indexOf('desc') - 1)) return [t]; const m = /^(\d+(?:\.\d+)?)([A-Za-z]{2,5})\.?$/.exec(t); return m && UNITS.has(m[2].toUpperCase()) ? [m[1], m[2]] : [t]; });
  // "12 PCS": a bare unit word straight after a number, but the header never broke Quantity into its
  // own Unit column. Drop the unit word so the token count still lines up with the declared columns.
  else toks = toks.filter((t, ti) => !(ti > 0 && UNITS.has(t.replace(/\.$/, '').toUpperCase()) && /^\d+(\.\d+)?$/.test(toks[ti - 1])));
  let k = cols.indexOf('desc');
  const left = cols.slice(0, k).filter((c) => c !== 'sno'), hasSno = cols.slice(0, k).includes('sno');
  const right = cols.slice(k + 1);
  if (hasSno && KIND_OK.sno.test(toks[0] || '')) toks = toks.slice(1);
  // Try with all right-hand columns, then without the ones that are often blank
  const variants = [right, right.filter((c) => c !== 'disc'), right.filter((c) => c !== 'disc' && c !== 'tax'), right.filter((c) => !['disc', 'tax', 'mrp'].includes(c))];
  for (const rc of [...new Set(variants.map((v) => v.join('|')))].map((s) => (s ? s.split('|') : []))) {
    const need = left.length + rc.length;
    if (toks.length < need + 1) continue;
    const lt = toks.slice(0, left.length), rt = toks.slice(toks.length - rc.length), name = toks.slice(left.length, toks.length - rc.length);
    const ok = (arr, kinds) => kinds.every((kk, i) => !KIND_OK[kk] || KIND_OK[kk].test(arr[i]));
    if (!ok(lt, left) || !ok(rt, rc)) continue;
    const get = (kind, arr, kinds) => { const i = kinds.indexOf(kind); return i >= 0 ? arr[i] : undefined; };
    const qty = toNum(get('qty', rt, rc) ?? get('qty', lt, left)), rate = toNum(get('rate', rt, rc) ?? 0), amount = toNum(get('amount', rt, rc) ?? 0);
    const unitTok = get('unit', rt, rc) ?? get('unit', lt, left);
    if (!(qty > 0) || !plausible(qty, rate, amount || qty * rate, 0.1)) continue;
    const desc = name.join(' ').replace(/[|:;,]+$/, '').trim();
    if (!/[A-Za-z]{2}/.test(desc)) continue;
    const hsn = get('hsn', rt, rc) ?? get('hsn', lt, left);
    const taxTok = get('tax', rt, rc);
    const mrpTok = get('mrp', rt, rc);
    return { mrp_col: mrpTok ? toNum(mrpTok) : null, description: desc, hsn: hsn || null, qty, unit: unitTok ? unitTok.replace(/\.$/, '').toUpperCase() : null, rate, amount: amount || r2(qty * rate), tax_hint: taxTok ? toNum(String(taxTok).replace('%', '')) : null };
  }
  return null;
}

/** Fallback when the header is missing or unreadable: find qty, rate and amount from the numbers on the line. */
function rowByNumbers(line) {
  const parts = line.split(' ');
  const nums = [];
  parts.forEach((p, idx) => { if (/^-?\d[\d,]*(\.\d+)?%?$/.test(p)) nums.push({ idx, v: toNum(p.replace('%', '')), raw: p }); });
  if (nums.length < 3) return null;
  let first = 0; if (nums[0].idx === 0 && Number.isInteger(nums[0].v) && nums[0].v < 1000) first = 1;
  const hsnTok = nums.find((n, i) => i >= first && /^\d{4,8}$/.test(n.raw));
  const pool = nums.filter((n, i) => i >= first && n !== hsnTok);
  let best = null;
  for (let i = 0; i < pool.length; i++) for (let j = i + 1; j < pool.length; j++) for (let k = j + 1; k < pool.length; k++) {
    const q = pool[i].v, r = pool[j].v, a = pool[k].v;
    if (!(Number.isInteger(q) && q > 0 && q < 100000 && r > 0 && a > 0)) continue;
    const g = q * r;
    const kind = Math.abs(g - a) <= Math.max(0.6, g * 0.005) ? 0 : (a < g * 0.995 && a >= g * 0.5 ? 2 : -1);
    if (kind < 0) continue;
    if (!best || kind < best.kind || (kind === best.kind && k > best.k)) best = { i, j, k, kind, q, r, a };
  }
  if (!best) return null;
  const qt = pool[best.i], rt = pool[best.j];
  const nameEnd = Math.min(qt.idx, hsnTok ? hsnTok.idx : 1e9, rt.idx);
  const desc = parts.slice(first ? 1 : 0, nameEnd).join(' ').replace(/[|:;,]+$/, '').trim();
  if (!/[A-Za-z]{2}/.test(desc)) return null;
  const after = parts[qt.idx + 1];
  const unit = after && /^[A-Za-z]{2,6}\.?$/.test(after) && UNITS.has(after.replace(/\.$/, '').toUpperCase()) ? after.replace(/\.$/, '').toUpperCase() : null;
  return { description: desc, hsn: hsnTok ? hsnTok.raw : null, qty: best.q, unit, rate: best.r, amount: best.a, tax_hint: null };
}

// Words that say nothing about which item or supplier it is
const NOISE = new Set(['pkt', 'pkts', 'pcs', 'pc', 'mrp', 'rs', 'new', 'pvt', 'ltd', 'private', 'limited', 'co', 'the', 'and', 'ms']);
/** Spelling variants read alike: bhujiya / bhujia / bujia, papad / paapad, namkeen / namkin. Words with digits stay as they are. */
const soft = (t) => (/^[a-z]+$/.test(t)
  ? t.replace(/([bdgjkpt])h/g, '$1').replace(/iya$/, 'ia').replace(/ee/g, 'i').replace(/oo/g, 'u').replace(/(.)\1+/g, '$1') : t);
/** Sizes written alike: "200 GM", "200gms", "200 g" -> 200g; kg and ml the same way. */
const sizes = (s) => String(s || '').replace(/(\d+(?:\.\d+)?)\s*(?:grams|gram|gms|grm|gm|g)\b/gi, '$1g')
  .replace(/(\d+(?:\.\d+)?)\s*(?:kgs|kg)\b/gi, '$1kg').replace(/(\d+(?:\.\d+)?)\s*(?:mls|ml)\b/gi, '$1ml');
/** The weight or volume in a name ("200g", "1kg", "500ml"), or null. */
const weightOf = (s) => { const m = /(?:^| )(\d+(?:\.\d+)?(?:g|kg|ml))(?= |$)/.exec(norm(sizes(s))); return m ? m[1] : null; };
const wordsOf = (s) => [...new Set(norm(sizes(s)).split(' ').filter((t) => t.length > 1 && !NOISE.has(t)).map(soft))];
/** At most one letter added, dropped or changed. */
function oneEdit(a, b) {
  if (Math.abs(a.length - b.length) > 1) return false;
  let i = 0, j = 0, d = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) { i++; j++; continue; }
    if (++d > 1) return false;
    if (a.length > b.length) i++; else if (b.length > a.length) j++; else { i++; j++; }
  }
  return d + (a.length - i) + (b.length - j) <= 1;
}
function wordMatch(a, b) {
  if (a === b) return 1;
  const alpha = /^[a-z]+$/.test(a) && /^[a-z]+$/.test(b);
  if (!alpha) return 0;
  if (Math.min(a.length, b.length) >= 4 && (a.startsWith(b) || b.startsWith(a))) return 0.9;   // a shortened word
  if (Math.min(a.length, b.length) >= 5 && oneEdit(a, b)) return 0.85;                          // one letter off
  return 0;
}
/** How alike two names are (0-1): each word of one finds its best match in the other, spelling variants counting nearly as much. */
const similarity = (a, b) => {
  const A = wordsOf(a), B = wordsOf(b);
  if (!A.length || !B.length) return 0;
  let hit = 0;
  for (const t of A) { let m = 0; for (const u of B) { const v = wordMatch(t, u); if (v > m) m = v; } hit += m; }
  return hit / Math.max(A.length, B.length);
};
function bestMatch(text, list, hsn) {
  let best = null, score = 0;
  const want = sizeTokens(text);
  for (const x of list) {
    const have = sizeTokens(x.name);
    if ((want.pack && have.pack && want.pack !== have.pack) || (want.mrp && have.mrp && want.mrp !== have.mrp)) continue; // a different pack of the same brand
    const wa = weightOf(text), wb = weightOf(x.name);
    if (wa && wb && wa !== wb) continue;                                                                                 // 200g is not 400g
    let s = similarity(text, x.name);
    if (hsn && x.hsn && String(x.hsn) === String(hsn)) s += 0.25;
    if (s > score) { score = s; best = x; }
  }
  return score >= 0.5 ? { match: best, score: Math.min(1, score) } : { match: null, score };
}

// ---- facts that can be read from the item name itself ----------------------------------------
/** "(1X144)", "(1X300 PKT)", "(300 PKT)", "(1X432PKT)" -> 144 / 300 / 300 / 432 pieces in one box. */
function packFromName(name) {
  const m = /\(\s*(?:(\d+)\s*[xX*]\s*)?(\d{1,5})\s*(?:PKTS?|PCS?|NOS|PACKS?|UNITS?)?\s*\)/i.exec(name);
  if (!m) { const m2 = /\b\d+\s*[xX]\s*(\d{2,5})\b(?!\s*(?:ml|g|gm|kg|ltr|l)\b)/i.exec(name); return m2 ? Number(m2[1]) : null; }
  return Number(m[2]) >= 1 ? Number(m[2]) : null;
}
/**
 * MRP printed inside an item name. Tried from the most explicit form to the loosest:
 *   "MRP-10/-", "M.R.P. Rs 10", "MRP:10.50"  ->  10 / 10.5
 *   "Rs.10/-", "Rs 10", "₹10"               ->  10
 *   "BIKANO CHIPS 10/-", "NAMKEEN @ 20"      ->  10 / 20
 * Pack sizes ("1X144", "400G") are never read as a price.
 */
function mrpFromName(name) {
  const s = String(name || '');
  const forms = [
    /\bM\.?\s*R\.?\s*P\.?\s*[-:.=]?\s*(?:RS\.?|INR|₹)?\s*(\d+(?:\.\d+)?)/i,
    /(?:\bRS\.?|\bINR|₹)\s*(\d+(?:\.\d+)?)/i,
    /(?:^|[\s(])(\d+(?:\.\d+)?)\s*\/\s*-/,
    /@\s*(\d+(?:\.\d+)?)\b(?!\s*(?:g|gm|kg|ml|l)\b)/i,
  ];
  for (const re of forms) { const m = re.exec(s); if (m && Number(m[1]) > 0 && Number(m[1]) < 100000) return Number(m[1]); }
  return null;
}
/** HSN -> usual GST rate for the goods this distributor deals in. Only used when the bill does not print a single rate. */
const HSN_RATE = [
  ['2106', 12], ['2105', 18], ['1905', 18], ['1704', 18], ['1806', 18], ['1902', 12], ['1904', 18], ['2008', 12], ['2009', 12], ['2202', 28], ['2201', 18],
  ['0902', 5], ['1006', 5], ['1101', 0], ['1512', 5], ['1701', 5], ['0713', 0], ['3401', 18], ['3402', 18], ['3305', 18], ['3306', 18], ['3307', 18], ['2501', 0],
];
const rateFromHsn = (hsn) => { const h = String(hsn || ''); const e = HSN_RATE.find(([p]) => h.startsWith(p)); return e ? e[1] : null; };
function enrichLine(r, billRate) {
  r.pcs_per_box = packFromName(r.description);
  r.mrp = (r.mrp_col > 0 ? r.mrp_col : null) || mrpFromName(r.description);   // the bill's MRP column wins, then "MRP-10/-" in the name
  delete r.mrp_col;
  // GST: the rate printed on the bill wins; else the usual rate for that HSN
  r.gst_rate = billRate !== null && billRate !== undefined ? billRate : rateFromHsn(r.hsn);
  r.gst_source = billRate !== null && billRate !== undefined ? 'bill' : (r.gst_rate !== null ? 'hsn' : null);
  return r;
}
const sizeTokens = (s) => ({ mrp: mrpFromName(s), pack: packFromName(s) });

// A name that wraps onto its own line sometimes carries a "(38%) (4.76% OFF)" discount footnote at the
// same height (so it lands on the same text line as the wrapped words) — strip those fragments, keep the words.
const PCT_FRAG = /\(\s*-?\d+(?:\.\d+)?\s*%[^)]*\)/g;

function parseItems(merged, items, warnings) {
  let cols = null;
  for (const m of merged) { const c = m.hdr >= 0 ? detectColumns(m.lines[m.hdr]) : null; if (c) { cols = c; break; } }
  if (!cols) for (const m of merged) for (const l of m.lines) { const c = detectColumns(l); if (c) { cols = c; break; } if (cols) break; }
  if (!cols) warnings.push('Item table header not recognised; rows were found by their numbers. Please check each row.');
  const rows = [];
  let lastIdx = -1, lastMi = -1;
  merged.forEach((m, mi) => {
    let start = 0;
    if (mi === 0) start = m.hdr >= 0 ? m.hdr + 1 : 0;
    let fold = 0;
    for (let i = start; i < m.lines.length; i++) {
      const line = m.lines[i];
      if (CARRY_LINE.test(line)) continue;
      if (TOTAL_MARK.test(line) || CONT_MARK.test(line)) break;   // totals block or page footer: the next page picks up the rows
      const row = (cols && rowFromColumns(line, cols)) || rowByNumbers(line);
      if (row) { rows.push(row); lastIdx = i; lastMi = mi; fold = 0; continue; }
      // Not a row of its own: a short, number-free tail is most likely the rest of the item name above
      // wrapping onto its own line (a long "Description"/"Items" column cell) — never a tax/total line
      // that just didn't happen to match TOTAL_MARK (a currency sign, a tax name, or "- - -" filler cells).
      if (rows.length && fold < 4 && !/[₹$]|\b(?:gst|cgst|sgst|igst|total|rs\.?)\b|(?:^|\s)-(?:\s+-){1,}/i.test(line)) {
        const tail = line.replace(PCT_FRAG, '').trim();
        if (tail && /[A-Za-z]/.test(tail) && tail.length <= 40 && !/\d[\d,]*\.\d\d\b/.test(tail) && !/\b\d{5,}\b/.test(tail)) {
          rows[rows.length - 1].description = `${rows[rows.length - 1].description} ${tail}`.replace(/\s+/g, ' ').trim();
          fold++;
        }
      }
    }
  });
  const out = rows.map((r, i) => {
    const m = bestMatch(r.description, items, r.hsn);
    const gross = r.qty * r.rate;
    return {
      sno: i + 1, ...r,
      item_id: m.match ? m.match.id : null, item_name: m.match ? m.match.name : null,
      match_confidence: m.match ? Math.round(m.score * 100) / 100 : 0,
      amount_differs: r.rate > 0 && Math.abs(gross - r.amount) > Math.max(0.6, gross * 0.005),
      fractional_qty: !Number.isInteger(r.qty),
    };
  });
  if (!out.length) warnings.push('No item rows could be read. Add them manually or check the PDF.');
  if (out.some((l) => !l.item_id)) warnings.push('Some items were not matched to your stock list. Choose or create them.');
  if (out.some((l) => l.fractional_qty)) warnings.push('Some quantities are fractional; stock is kept in whole pieces. Please correct them.');
  if (out.some((l) => l.amount_differs)) warnings.push('For some rows Qty × Price does not equal the printed Amount (line discount?). The printed Amount was kept.');
  return { rows: out, lastIdx, lastMi };
}

// ------------------------------------------------------------------ 4. Totals
const AMOUNT_RE = /-?\d[\d,]*\.\d{1,2}(?![\d%])|-?\d[\d,]*(?![\d.%,])/g;
/** Last money value on a line, ignoring "@ 2.50 %" rates and the word-like quantities before it: "Add : SGST @ 2.50 % 6,216.10" -> 6216.10 */
function lastAmount(line) {
  const cleaned = line.replace(/@?\s*\d+(?:\.\d+)?\s*%/g, ' ');
  const all = cleaned.match(AMOUNT_RE);
  return all && all.length ? toNum(all[all.length - 1]) : null;
}
const rateOn = (line) => { const m = /(\d+(?:\.\d+)?)\s*%/.exec(line); return m ? Number(m[1]) : null; };

/**
 * Discount, CGST, SGST, IGST, Round off and Grand total, one labelled line each ("Less : Discount @ 3.00 % 7,690.02").
 * Several lines of the same tax (one per rate) are added together. Also returns the GST rate printed beside the tax lines.
 */
function parseTotals(lines) {
  const t = { discount: null, cgst: null, sgst: null, igst: null, round_off: null, grand_total: null };
  const rates = { cgst: [], sgst: [], igst: [] };
  const add = (k, v) => { t[k] = r2((t[k] || 0) + v); };
  for (const line of lines) {
    if (/^\W*(?:rupees|in\s*words)/i.test(line)) continue;
    const v = lastAmount(line);
    if (v === null) continue;
    if (/grand\s*total|invoice\s*total|total\s*invoice\s*value|net\s*(?:payable|amount)|bill\s*amount|amount\s*payable|total\s*payable/i.test(line)) { t.grand_total = Math.abs(v); continue; }
    if (/round(?:ed|ing)?[\s\-]*(?:off|of)\b/i.test(line)) {
      const neg = /\(\s*-\s*\)|\bless\b|-\s*[\d.,]+\s*$/i.test(line);
      t.round_off = r2((neg ? -1 : 1) * Math.abs(v));
      continue;
    }
    if (/\bdiscount\b|\bdisc\b/i.test(line) && !/^\s*\d+\.?\s/.test(line)) { add('discount', Math.abs(v)); continue; }
    if (/\bC\.?G\.?S\.?T\b/i.test(line)) { add('cgst', Math.abs(v)); const r = rateOn(line); if (r !== null) rates.cgst.push(r); continue; }
    if (/\b(?:S\.?G\.?S\.?T|UTGST)\b/i.test(line)) { add('sgst', Math.abs(v)); const r = rateOn(line); if (r !== null) rates.sgst.push(r); continue; }
    if (/\bI\.?G\.?S\.?T\b/i.test(line)) { add('igst', Math.abs(v)); const r = rateOn(line); if (r !== null) rates.igst.push(r); continue; }
  }
  // Last resort: a table-footer summary row the other patterns above don't catch, e.g. "TOTAL 157  27,257.71  40,223.4"
  // (quantity, then money figures) — "total" directly followed by a count, never a word like "Boxes" or "Qty:".
  if (t.grand_total === null) {
    for (const line of lines) {
      if (/^\W*total\s+\d/i.test(line) && !/^\W*sub[\s-]*total/i.test(line)) { const v = lastAmount(line); if (v !== null) { t.grand_total = Math.abs(v); break; } }
    }
  }
  // GST rate of the bill: CGST% + SGST% (or IGST%) when one rate is printed; null when several
  const uniq = (a) => [...new Set(a)];
  let gst = null;
  if (uniq(rates.cgst).length === 1 && uniq(rates.sgst).length <= 1) gst = rates.cgst[0] + (rates.sgst[0] || rates.cgst[0]);
  else if (uniq(rates.igst).length === 1) gst = rates.igst[0];
  t.gst_rate = gst;
  return t;
}

/** Tax-rate summary table: "5%  2,48,644.80  6,216.10  6,216.10  12,432.20" -> [5] */
function summaryRates(lines) {
  const out = [];
  for (const l of lines) { const m = /^\W*(\d{1,2}(?:\.\d+)?)%\s+[\d,]+\.\d\d\b/.exec(l); if (m) out.push(Number(m[1])); }
  return [...new Set(out)];
}

// ------------------------------------------------------------------ 5. Supplier details
const toDigits = (s) => String(s).replace(/\D/g, '');
function numbersIn(s) {
  // phone-like groups separated by comma / slash / "and"; keeps STD codes with hyphen together
  return String(s).split(/[,;\/&]|\band\b/i).map((x) => x.trim()).filter((x) => toDigits(x).length >= 6 && toDigits(x).length <= 14);
}
const mobileOf = (s) => { const d = toDigits(s).replace(/^(91|0)(?=\d{10}$)/, ''); return /^[6-9]\d{9}$/.test(d) ? d : null; };

function parseSupplier(lines, ctx) {
  // The supplier's block ends where the buyer's begins. Some templates print "Invoice No. / Date" between the supplier's
  // address and the supplier's GSTIN / mobile / e-mail, so the invoice row only ends it when no buyer heading is found.
  const buyerAt = lines.findIndex((l, i) => i > 0 && BUYER_HEAD.test(l));
  const stop = buyerAt > 0 ? buyerAt : lines.findIndex((l, i) => i > 0 && /(?:invoice|bill|inv)\s*(?:no|date)/i.test(l));
  const head = lines.slice(0, stop > 0 ? Math.min(stop, 16) : 14);
  const text = head.join('\n');
  const own = String(ctx.companyGstin || '').toUpperCase();
  const gstins = [...new Set(text.match(GSTIN_RE) || [])].filter((g) => g !== own);
  const gstin = gstins[0] || ([...new Set(lines.join('\n').match(GSTIN_RE) || [])].filter((g) => g !== own)[0] || null);
  const sc = /state\s*(?:code)?\s*[:\-]?\s*(\d{2})\b/i.exec(text);
  const pan = /\bPAN\s*(?:no\.?|number|#)?\s*[:\-]?\s*([A-Z]{5}\d{4}[A-Z])\b/i.exec(text);
  const fssai = /FSSAI[^\d\n]{0,30}(\d{14})/i.exec(text) || /\b(\d{14})\b/.exec(text.split('\n').filter((l) => /fssai|lic/i.test(l)).join(' '));
  const email = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/.exec(text);

  const label = (re) => { const m = re.exec(text); return m ? m[1].trim() : null; };
  const telRaw = label(/\b(?:tel(?:ephone)?|landline)\b\.?\s*(?:no\.?)?\s*[:\-]?\s*([\d \t\-+(),\/]{6,50})/i);
  const phoneRaw = label(/\b(?:phone|ph)\b\.?\s*(?:no\.?)?\s*[:\-]?\s*([\d \t\-+(),\/]{6,50})/i);
  const mobRaw = [...text.matchAll(/\b(?:mobile|mob|cell|whatsapp)\b\.?\s*(?:no\.?|nos\.?)?\s*[:\-]?\s*([\d \t\-+(),\/&and]{8,60})/gi)].map((m) => m[1]);
  const mobiles = [];
  for (const raw of mobRaw) for (const n of numbersIn(raw)) { const m = mobileOf(n); if (m && !mobiles.includes(m)) mobiles.push(m); }
  // A number printed after "Tel." or "Phone" that is a 10-digit mobile belongs with the mobiles
  const split = (raw) => { const land = []; for (const n of raw ? numbersIn(raw) : []) { const m = mobileOf(n); if (m) { if (!mobiles.includes(m)) mobiles.push(m); } else land.push(n); } return land.join(', ') || null; };
  const tel = split(telRaw);
  let phone = split(phoneRaw);
  // 10-digit mobile numbers printed without a label
  for (const m of text.matchAll(/(?<![\d-])(?:\+?91[\s-]?)?([6-9]\d{9})(?!\d)/g)) { if (!mobiles.includes(m[1]) && !(phone && toDigits(phone).includes(m[1])) && !(tel && toDigits(tel).includes(m[1]))) mobiles.push(m[1]); }

  const { name, idx: nameIdx } = supplierName(lines, ctx.companyName);
  const addr = [];
  for (let i = nameIdx + 1; i < head.length; i++) {
    const l = head[i];
    if (BILL_ROW.test(l)) break;   // the invoice number row or the items table: the address is over
    if (COPY_LABEL.test(l) || /(tax\s*invoice|invoice)/i.test(l)) { if (addr.length) break; else continue; }
    // the address part of a line that also carries contact details ("NAGLA BYPASS, MORADABAD Tel: 01342-262626")
    const part = withoutContact(l).replace(/^address\s*[:\-]?\s*/i, '').replace(/[,.\s]+$/, '');
    if (/^\d{6}$/.test(part) && addr.length) { addr[addr.length - 1] += ' - ' + part; continue; }   // the PIN code on a line of its own
    if (!/[A-Za-z]{3}/.test(part)) { if (addr.length) break; else continue; }
    addr.push(part);
    if (addr.length >= 4) break;
  }
  return {
    name, address: addr.join(', ') || null, gstin, state_code: sc ? sc[1] : gstin ? gstin.slice(0, 2) : null,
    tel, phone, mobiles, fssai: fssai ? fssai[1] : null, pan: pan ? pan[1].toUpperCase() : gstin ? gstin.slice(2, 12) : null, email: email ? email[0] : null,
  };
}

const SUFFIX = /\b(pvt|private|ltd|limited|traders|enterprises?|distributors?|agenc(?:y|ies)|industries|foods|stores?|corporation|marketing|company|co\.?|brothers|bros|beverages|trading|sales|suppliers?|sons|mart|udyog|impex|exports?|products|pharma|llp|emporium|depot|bhandar|kirana|wholesalers?|mills|provisions|associates|ventures)\b/i;
const GENERIC = /^(tax\s*invoice|proforma(\s*invoice)?|invoice|original|duplicate|triplicate|gstin|bill of supply|page|e-?invoice|irn|ack|cash|credit|\(?see rule)/i;
const INVOCATION = /^\W*(?:shree|shri|sri|jai|om)\s+(?:ganesh\w*|mata\s+di|ram|radhe|krishna|hanuman\w*|balaji|sai\s+ram|shyam|laxmi|lakshmi|durga)(?:\s+(?:ji|namah?a?|ki\s+jai|sahay\w*))*\W*$/i;
const BILL_ROW = /\b(?:invoice|bill|inv)\s*(?:no|number|date)\b|\bdated\b|\bparticulars\b|\bdescription\b|^s\.?\s*no\b|\bhsn\b|\bqty\b/i;
const BUYER_HEAD = /(party\s*details|bill(?:ed)?\s*to|buyer|consignee|ship(?:ped)?\s*to|details\s*of\s*(?:receiver|buyer)|customer\s*name|m\/s)/i;
const EMAIL_RE = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g;
const CONTACT_AT = /\b(?:e-?mail(?:\s*id)?|tel(?:ephone)?|phone|ph|mob(?:ile)?|cell|whatsapp|gstin|gst\s*no|fssai|pan|cin|state\s*code|website|fax|contact)\b/i;
/** A header line with the contact details cut off: "SHREE TRADERS email : st@mail.com" -> "SHREE TRADERS". */
function withoutContact(l) {
  let s = String(l).replace(EMAIL_RE, ' ').replace(/\b(?:https?:\/\/|www\.)\S+/gi, ' ');
  const m = CONTACT_AT.exec(s);
  if (m) s = s.slice(0, m.index);
  s = s.replace(/(?:\+?91[\s-]?)?[6-9]\d{9}(?!\d)/g, ' ');
  return s.replace(/\s+/g, ' ').replace(/^[\s,;:|\-\/.]+/, '').replace(/[\s,;:|\-\/]+$/, '').trim();
}
/** The supplier's name among the first lines, without any e-mail / phone / GSTIN printed on the same line, and the line it is on. */
function supplierName(lines, companyName) {
  const own = norm(companyName);
  const cand = [];
  lines.slice(0, 12).forEach((l, idx) => {
    if (GENERIC.test(l) || INVOCATION.test(l) || /^\W*(bill to|ship to|buyer|consignee)/i.test(l)) return;
    const name = withoutContact(l).replace(/^(?:m\/s\.?|from\s*:)\s*/i, '');
    if (!/[A-Za-z]{3}/.test(name) || GENERIC.test(name)) return;
    if (own && norm(name).includes(own)) return;
    cand.push({ name, idx });
  });
  return cand.find((c) => SUFFIX.test(c.name) && c.name.length < 70) || cand[0] || { name: null, idx: -1 };
}
const guessSupplierName = (lines, companyName) => supplierName(lines, companyName).name;

// ------------------------------------------------------------------ invoice no / date
function findInvoiceNo(text) {
  // The captured run must contain at least one digit, so a label that wraps onto the next word
  // ("Invoice No.\nProforma Date") can't be mistaken for the number itself.
  const m = text.match(/(?:tax\s+)?(?:proforma\s+)?(?:invoice|inv|bill)\s*(?:no|number|num|#)\.?\s*[:\-#]?\s*((?=[A-Z0-9\/\-]{0,24}\d)[A-Z0-9][A-Z0-9\/\-]{2,24})/i);
  if (m) return m[1];
  // Some templates print the label on its own line ("Proforma Invoice No.   Proforma Date   Expiry Date")
  // with the values on a different line further down, mixed in with other fields ("... 5531  09/09/2026 ...").
  const lines = text.split('\n');
  const li = lines.findIndex((l) => /\b(?:invoice|bill)\s*(?:no|number|num|#)\b/i.test(l));
  if (li >= 0) {
    for (let i = li + 1; i < Math.min(li + 3, lines.length); i++) {
      const stripped = lines[i].replace(GSTIN_RE, ' ').replace(/(?:\+?91[\s-]?)?[6-9]\d{9}\b/g, ' ');
      const num = /\b(\d{2,8})\b(?!\s*[\/\-]\d)/.exec(stripped);
      if (num) return num[1];
    }
  }
  return null;
}
function normaliseDate(raw) {
  if (!raw) return null;
  let m = raw.match(/(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})/);
  if (m) {
    let [, d, mo, y] = m; y = y.length === 2 ? '20' + y : y;
    if (+mo >= 1 && +mo <= 12 && +d >= 1 && +d <= 31) return `${y}-${pad(mo)}-${pad(d)}`;
  }
  m = raw.match(/(\d{1,2})[ \-]([A-Za-z]{3})[A-Za-z]*[ \-,.]*(\d{2,4})/);
  if (m && MONTHS[m[2].toLowerCase()]) {
    const y = m[3].length === 2 ? '20' + m[3] : m[3];
    return `${y}-${pad(MONTHS[m[2].toLowerCase()])}-${pad(m[1])}`;
  }
  return null;
}
// The "day Month year" branch only accepts a real month name, not any word — "6 Mobile 7895" is not a date.
const DATE_PAT = '(\\d{1,2}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{2,4}|\\d{1,2}[ \\-](?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[ \\-,.]*\\d{2,4})';
function findDate(text) {
  const near = text.match(new RegExp('(?:(?:invoice|bill|inv|proforma)\\s*date|dated)\\s*[:\\-]?\\s*' + DATE_PAT, 'i'));
  if (near) { const d = normaliseDate(near[1]); if (d) return d; }
  const any = text.match(new RegExp(DATE_PAT, 'i'));
  return any ? normaliseDate(any[1]) : null;
}

// ------------------------------------------------------------------ entry points
/**
 * @param {string[]} pages  text of each PDF page, in order
 * @param {{items?:object[], parties?:object[], companyGstin?:string, companyName?:string}} ctx
 */
function parseInvoicePages(pages, ctx = {}) {
  const { items = [], parties = [], companyGstin = '', companyName = '' } = ctx;
  const warnings = [];
  const sel = selectOriginalPages(pages.length ? pages : ['']);
  if (sel.note) warnings.push(sel.note);
  const merged = mergePages(sel.pages);
  const first = merged[0].lines;
  const firstText = first.join('\n');

  const sup = parseSupplier(first, { companyGstin, companyName });
  let matched = null;
  if (sup.gstin) matched = parties.find((p) => p.gstin && p.gstin.toUpperCase() === sup.gstin) || null;
  if (!matched && sup.name) { const m = bestMatch(sup.name, parties, null); matched = m.match; }
  if (!sup.name) warnings.push('Supplier name not found');

  const invoiceNo = findInvoiceNo(firstText);
  if (!invoiceNo) warnings.push('Invoice number not found');
  const date = findDate(firstText);
  if (!date) warnings.push('Invoice date not found');

  const { rows, lastIdx, lastMi } = parseItems(merged, items, warnings);

  // Totals block: everything after the last item row (it may sit on a later Original page than the last row)
  const tail = lastMi >= 0
    ? [...merged[lastMi].lines.slice(lastIdx + 1), ...merged.slice(lastMi + 1).flatMap((m) => m.lines)]
    : merged.flatMap((m) => m.lines).slice(-40);
  const totals = parseTotals(tail);
  const billRates = summaryRates(tail);
  const fallbackRate = totals.gst_rate !== null ? totals.gst_rate : billRates.length === 1 ? billRates[0] : null;
  for (const r of rows) enrichLine(r, fallbackRate);
  const subtotal = r2(rows.reduce((a, r) => a + r.amount, 0));
  totals.subtotal = subtotal;
  if (totals.grand_total === null) warnings.push('Grand total not found on the bill');
  if (totals.cgst === null && totals.sgst === null && totals.igst === null) warnings.push('CGST / SGST / IGST amounts not found; they will be worked out from your item GST rates unless you type them.');
  if (totals.grand_total !== null && rows.length) {
    const calc = r2(subtotal - (totals.discount || 0) + (totals.cgst || 0) + (totals.sgst || 0) + (totals.igst || 0) + (totals.round_off || 0));
    const haveTax = !(totals.cgst === null && totals.sgst === null && totals.igst === null);
    if (haveTax && Math.abs(calc - totals.grand_total) > 1) warnings.push(`Items − discount + taxes + round off = ${calc}, but the bill's grand total is ${totals.grand_total}. Check the rows and the totals.`);
  }

  return {
    supplier: { ...sup, matched_party_id: matched ? matched.id : null, matched_name: matched ? matched.name : null },
    invoice_no: invoiceNo, date, lines: rows, totals, warnings,
    pages: { total: pages.length, used: sel.used, skipped: sel.skipped },
    // kept for older callers
    stated_total: totals.grand_total,
  };
}

/** Single string input (pages separated by form feed). */
const parseInvoiceText = (text, ctx) => parseInvoicePages(String(text || '').split('\f'), ctx);

module.exports = { rowFromColumns, packFromName, mrpFromName, rateFromHsn, parseInvoicePages, parseInvoiceText, selectOriginalPages, mergePages, copyKind, detectColumns, parseTotals, parseSupplier, normaliseDate, similarity };
