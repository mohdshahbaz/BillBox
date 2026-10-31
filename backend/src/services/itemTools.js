const db = require('../db');
const { HttpError, blank } = require('../utils/misc');
const { packFromName } = require('./pdfParser');
const { ensureCategory } = require('./category');

/**
 * Item names: tidy them, find the same item entered twice, merge duplicates, and read item lists
 * (company price lists found online) into new items. Plain character work on UTF-16 units (no regex),
 * so the Swift engine gives exactly the same answers.
 */

const isDigit = (c) => c >= '0' && c <= '9';
const isUpperA = (c) => c >= 'A' && c <= 'Z';
const isLowerA = (c) => c >= 'a' && c <= 'z';
const isLetterA = (c) => isUpperA(c) || isLowerA(c);
const lowerA = (s) => { let o = ''; for (let i = 0; i < s.length; i++) { const c = s[i]; o += isUpperA(c) ? String.fromCharCode(c.charCodeAt(0) + 32) : c; } return o; };
const upperA = (s) => { let o = ''; for (let i = 0; i < s.length; i++) { const c = s[i]; o += isLowerA(c) ? String.fromCharCode(c.charCodeAt(0) - 32) : c; } return o; };
const isWs = (c) => c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === ' ';

const UNITS = {
  g: 'g', gm: 'g', gms: 'g', gram: 'g', grams: 'g', gr: 'g', grm: 'g', grms: 'g',
  kg: 'kg', kgs: 'kg', kilo: 'kg', kilogram: 'kg', kilograms: 'kg',
  ml: 'ml', mls: 'ml', millilitre: 'ml', milliliter: 'ml',
  l: 'L', lt: 'L', ltr: 'L', ltrs: 'L', litre: 'L', liter: 'L', litres: 'L', liters: 'L',
};
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const unitOf = (w, upper) => {
  if (!own(UNITS, lowerA(w))) return null;
  const u = UNITS[lowerA(w)];
  return upper ? upperA(u) : u;
};

/** "250", "1.5" (a number written as one word) */
const isNumber = (w) => {
  if (!w.length) return false;
  let dots = 0;
  for (let i = 0; i < w.length; i++) { if (w[i] === '.') dots++; else if (!isDigit(w[i])) return false; }
  return dots <= 1 && w[0] !== '.' && w[w.length - 1] !== '.';
};

/** Number(x) as a whole id; anything else becomes 0 (no item has id 0). */
const toInt = (v) => { const n = Number(v); return Number.isFinite(n) && Math.abs(n) < 1e15 ? Math.trunc(n) : 0; };
const trimEnd = (s, set) => { let b = s.length; while (b > 0 && set.includes(s[b - 1])) b--; return s.slice(0, b); };

/** One space between words, none inside brackets' edges. */
function squeeze(s) {
  let o = '', sp = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i] === '_' ? ' ' : s[i];
    if (isWs(c)) { sp = o.length > 0; continue; }
    if (sp && c !== ')' && c !== ',' && o[o.length - 1] !== '(') o += ' ';
    sp = false;
    o += c;
  }
  return o;
}

function titleWord(w, mixed) {
  const br = w.indexOf('(');
  if (br > 0) return titleWord(w.slice(0, br), mixed) + w.slice(br);   // BHUJIA(1X300PKT) -> Bhujia(1X300PKT)
  let letters = 0, vowels = 0, digit = false, caps = 0;
  for (let i = 0; i < w.length; i++) {
    if (isDigit(w[i])) digit = true;
    if (isLetterA(w[i])) { letters++; if (isUpperA(w[i])) caps++; if ('aeiouyAEIOUY'.includes(w[i])) vowels++; }
  }
  if (digit || !letters) return w;
  if (mixed && caps === letters && letters <= 4) return w;          // ITC, AMUL written in capitals on purpose
  if (letters <= 3 && vowels === 0) return upperA(w);           // MDH, ITC-style short brand letters
  let o = '', first = true;
  for (let i = 0; i < w.length; i++) {
    const c = w[i];
    if (isLetterA(c)) { o += first ? upperA(c) : lowerA(c); first = false; } else o += c;
  }
  return o;
}

/**
 * Tidy an item name.
 *   mode 'keep'  : spacing and pack sizes only (20 GM -> 20GM in capitals, 20 gm -> 20g otherwise)
 *   mode 'title' : Title Case words too ("BIKANO BHUJIA 200 GM" -> "Bikano Bhujia 200g")
 *   mode 'upper' : CAPITALS throughout ("Bikano bhujia 200 gm" -> "BIKANO BHUJIA 200G")
 */
function cleanName(name, mode = 'keep') {
  const s = squeeze(String(name ?? ''));
  let up = 0, low = 0;
  for (let i = 0; i < s.length; i++) { if (isUpperA(s[i])) up++; else if (isLowerA(s[i])) low++; }
  const upperUnits = mode === 'upper' || (mode === 'keep' && up > 0 && low === 0);
  const words = s.length ? s.split(' ') : [];
  const out = [];
  for (let i = 0; i < words.length; i++) {
    let w = words[i];
    // "200 gm" -> "200g"
    if (isNumber(w) && i + 1 < words.length) {
      const nx = trimEnd(words[i + 1], '.,');
      const u = unitOf(nx, upperUnits);
      if (u !== null && trimEnd(words[i + 1], '.,').length === nx.length) {
        const tail = words[i + 1].slice(nx.length);
        out.push(w + u + tail); i++; continue;
      }
    }
    // "200gm" / "200GMS." -> "200g"
    let k = 0, dots = 0;
    while (k < w.length && (isDigit(w[k]) || (w[k] === '.' && dots === 0 && k > 0))) { if (w[k] === '.') dots++; k++; }
    if (k > 0 && k < w.length && w[k - 1] !== '.') {
      const rest = w.slice(k), core = trimEnd(rest, '.,)');
      const u = core.length ? unitOf(core, upperUnits) : null;
      if (u !== null) w = w.slice(0, k) + u + rest.slice(core.length);
    }
    if (mode === 'title') w = titleWord(w, up > 0 && low > 0);
    else if (mode === 'upper') w = upperA(w);
    out.push(w);
  }
  return trimEnd(out.join(' '), ' ,');
}

/** What makes two names the same item: tidied, lower case, letters and digits only. */
function itemKey(name) {
  const s = lowerA(cleanName(name, 'keep'));
  let o = '';
  for (let i = 0; i < s.length; i++) { const c = s[i]; if (isLowerA(c) || isDigit(c) || c.charCodeAt(0) > 127) o += c; }
  return o;
}

const GENERIC = ['biscuit', 'biscuits', 'namkeen', 'snacks', 'snack', 'chips', 'noodles', 'pouch', 'sachet', 'bottle', 'jar', 'box', 'refill', 'packet'];
const NOISE = ['mrp', 'rs', 'pkt', 'pkts', 'pcs', 'pc', 'pack', 'packet', 'x', 'new', 'the', 'and', 'of', 'n', 'no', 'nos'];

/** A word reduced to its consonants (h and y count as vowels, doubles collapse): Bhujia, Bhujiya and Bujia all give "bj". */
function skeleton(w) {
  let o = w[0];
  for (let i = 1; i < w.length; i++) {
    const c = w[i];
    if ('aeiouyh'.includes(c)) continue;
    if (o[o.length - 1] !== c) o += c;
  }
  return o;
}

const GENERIC_SK = GENERIC.map(skeleton);

/** What two items are compared on: pack sizes (200g, 1kg), the words (as skeletons), MRP and pieces per box. */
function signature(it) {
  const tidy = lowerA(cleanName(it.name, 'keep'));
  const sizes = [], words = [];
  let w = '';
  const flush = () => {
    if (!w) return;
    let k = 0;
    while (k < w.length && (isDigit(w[k]) || w[k] === '.')) k++;
    if (k > 0 && k < w.length && own(UNITS, w.slice(k))) { if (!sizes.includes(w)) sizes.push(w); }
    else if (k < w.length && !isDigit(w[w.length - 1]) && w.length >= 2 && !NOISE.includes(w)) { const sk = skeleton(w); if (!words.includes(sk)) words.push(sk); }
    w = '';
  };
  for (let i = 0; i < tidy.length; i++) {
    const c = tidy[i];
    if (isLowerA(c) || isDigit(c) || (c === '.' && w && isDigit(w[w.length - 1]))) w += c; else flush();
  }
  flush();
  sizes.sort();
  return { sizes: sizes.join(','), words, mrp: Number(it.mrp) || 0, box: Math.max(1, parseInt(it.pcs_per_box, 10) || 1) };
}

/** 0..1 when the two may be the same item, -1 when they cannot be (different pack size, MRP or box). */
function likeness(a, b, match) {
  if (a.sizes !== b.sizes) return -1;
  if (a.mrp > 0 && b.mrp > 0 && Math.abs(a.mrp - b.mrp) >= 0.005) return -1;
  if (a.box !== b.box && a.box > 1 && b.box > 1) return -1;
  if (!a.words.length || !b.words.length) return -1;
  let common = 0;
  for (const x of a.words) if (b.words.includes(x)) common++;
  if (!common) return -1;
  const union = a.words.length + b.words.length - common;
  const jac = common / union;
  // the same words once generic ones (biscuit, chips, pouch …) are left out: spelling, order, capitals and pack writing may differ
  const ca = a.words.filter((x) => !GENERIC_SK.includes(x)), cb = b.words.filter((x) => !GENERIC_SK.includes(x));
  const sameWords = ca.length > 0 && ca.length === cb.length && ca.every((x) => cb.includes(x));
  const ok = sameWords || (match === 'loose' && a.words[0] === b.words[0] && jac >= 0.5);
  return ok ? Math.round(jac * 100) / 100 : -1;
}

/**
 * Proposed tidy names, and items that may be the same item entered more than once.
 *   match=exact   names that are the same once tidied
 *   match=similar also spelling variants, word order and an extra word (default)
 *   match=loose   fewer words in common (same first word); check these carefully
 * Different pack sizes (200g / 400g), different MRPs and different box sizes are never put together.
 */
function cleanPreview(q) {
  const mode = ['keep', 'title', 'upper'].includes(q && q.case) ? q.case : 'keep';
  const match = ['exact', 'similar', 'loose'].includes(q && q.match) ? q.match : 'similar';
  const items = db.prepare(`SELECT i.id, i.name, i.gst_rate, i.mrp, i.pcs_per_box,
      (SELECT COUNT(*) FROM invoice_lines WHERE item_id=i.id) + (SELECT COUNT(*) FROM purchase_lines WHERE item_id=i.id) + (SELECT COUNT(*) FROM debit_note_lines WHERE item_id=i.id) used,
      (SELECT COALESCE(SUM(qty),0) FROM batches WHERE item_id=i.id) stock
    FROM items i WHERE i.active=1 ORDER BY i.name, i.id`).all();
  const renames = [];
  const parent = items.map((_, i) => i);
  const find = (i) => { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; };
  const keys = items.map((it) => itemKey(it.name));
  const sigs = items.map(signature);
  const group = items.map((_, i) => [i]);
  // two items can only end up together when their MRPs and boxes agree (checked against every member, so no chains)
  const fits = (x, y) => !(sigs[x].mrp > 0 && sigs[y].mrp > 0 && Math.abs(sigs[x].mrp - sigs[y].mrp) >= 0.005) && !(sigs[x].box !== sigs[y].box && sigs[x].box > 1 && sigs[y].box > 1);
  const join = (i, j) => {
    const a = find(i), b = find(j);
    if (a === b) return false;
    if (!group[a].every((x) => group[b].every((y) => fits(x, y)))) return false;
    const lo = Math.min(a, b), hi = Math.max(a, b);
    parent[hi] = lo;
    group[lo] = group[lo].concat(group[hi]);
    return true;
  };
  const best = items.map(() => 1);
  const firstByKey = new Map();
  items.forEach((it, i) => {
    const c = cleanName(it.name, mode);
    if (c && c !== it.name) renames.push({ id: it.id, name: it.name, clean: c });
    if (!keys[i]) return;
    if (firstByKey.has(keys[i])) join(firstByKey.get(keys[i]), i); else firstByKey.set(keys[i], i);
  });
  if (match !== 'exact') {
    const bySize = new Map();
    items.forEach((_, i) => { const k = sigs[i].sizes; if (!bySize.has(k)) bySize.set(k, []); bySize.get(k).push(i); });
    for (const list of bySize.values()) {
      for (let x = 0; x < list.length; x++) {
        for (let y = x + 1; y < list.length; y++) {
          const i = list[x], j = list[y];
          if (keys[i] && keys[i] === keys[j]) continue;
          const l = likeness(sigs[i], sigs[j], match);
          if (l < 0) continue;
          if (find(i) !== find(j) && !join(i, j)) continue;
          if (l < best[i]) best[i] = l;
          if (l < best[j]) best[j] = l;
        }
      }
    }
  }
  const members = new Map();
  items.forEach((_, i) => { const r = find(i); if (!members.has(r)) members.set(r, []); members.get(r).push(i); });
  const groups = [];
  for (const list0 of members.values()) {
    if (list0.length < 2) continue;
    const list = list0.map((i) => items[i]);
    const ranked = list.slice().sort((a, b) => b.used - a.used || b.stock - a.stock || a.id - b.id);
    const keep = ranked[0];
    const same = list0.every((i) => keys[i] === keys[list0[0]]);
    const brief = (x) => ({ id: x.id, name: x.name, used: x.used, stock: x.stock, mrp: x.mrp, pcs_per_box: x.pcs_per_box });
    const warnings = [];
    if (list.some((x) => x.gst_rate !== keep.gst_rate)) warnings.push('Different GST rates');
    if (list.some((x) => Math.max(1, x.pcs_per_box || 1) !== Math.max(1, keep.pcs_per_box || 1))) warnings.push('Different pieces per box');
    groups.push({
      key: keys[list0[0]] || String(keep.id), match: same ? 'same' : 'similar',
      score: same ? 1 : Math.min(...list0.map((i) => best[i])),
      keep: brief(keep), merge: ranked.slice(1).map(brief), warnings,
    });
  }
  groups.sort((a, b) => (a.keep.name < b.keep.name ? -1 : a.keep.name > b.keep.name ? 1 : a.keep.id - b.keep.id));
  return { mode, match, items: items.length, renames, groups };
}

/** Renames items to their tidy names. A name already taken by another item is left alone (merge those instead). */
const applyClean = db.transaction((b) => {
  const mode = ['keep', 'title', 'upper'].includes(b && b.case) ? b.case : 'keep';
  const only = b && Array.isArray(b.ids) ? b.ids.map(toInt) : null;
  const items = db.prepare('SELECT id,name FROM items WHERE active=1 ORDER BY id').all();
  const taken = db.prepare('SELECT id FROM items WHERE active=1 AND lower(name)=lower(?) AND id <> ?');
  const upd = db.prepare('UPDATE items SET name=?, pcs_per_box=? WHERE id=?');
  const cur = db.prepare('SELECT pcs_per_box FROM items WHERE id=?');
  let renamed = 0;
  const skipped = [];
  for (const it of items) {
    if (only && !only.includes(it.id)) continue;
    const c = cleanName(it.name, mode);
    if (!c || c === it.name) continue;
    if (taken.get(c, it.id)) { skipped.push({ id: it.id, name: it.name, clean: c, reason: 'Another item already has this name: merge them instead' }); continue; }
    upd.run(c, packFromName(c) || cur.get(it.id).pcs_per_box, it.id);
    renamed++;
  }
  return { renamed, skipped };
});

/** Moves every bill line, batch and scheme of the duplicates onto the item kept, then archives the duplicates. */
const mergeItems = db.transaction((b) => {
  const keepId = toInt(b && b.keep_id);
  const ids = (b && Array.isArray(b.merge_ids) ? b.merge_ids : []).map(toInt).filter((x) => x !== keepId);
  const keep = keepId ? db.prepare('SELECT * FROM items WHERE id=? AND active=1').get(keepId) : null;
  if (!keep) throw new HttpError(404, 'Choose the item to keep');
  if (!ids.length) throw new HttpError(400, 'Choose the items to merge into it');
  const moved = { invoice_lines: 0, purchase_lines: 0, debit_note_lines: 0, batches: 0, schemes: 0 };
  const names = [];
  for (const id of ids) {
    const m = db.prepare('SELECT * FROM items WHERE id=? AND active=1').get(id);
    if (!m) throw new HttpError(404, `Item ${id} not found`);
    for (const bt of db.prepare('SELECT * FROM batches WHERE item_id=? ORDER BY id').all(id)) {
      const same = db.prepare('SELECT id FROM batches WHERE item_id=? AND batch_no=?').get(keepId, bt.batch_no);
      if (same) {
        db.prepare('UPDATE batches SET qty=qty+? WHERE id=?').run(bt.qty, same.id);
        for (const t of ['invoice_lines', 'purchase_lines', 'debit_note_lines', 'debit_note_stock']) db.prepare(`UPDATE ${t} SET batch_id=? WHERE batch_id=?`).run(same.id, bt.id);
        db.prepare('DELETE FROM batches WHERE id=?').run(bt.id);
      } else db.prepare('UPDATE batches SET item_id=? WHERE id=?').run(keepId, bt.id);
      moved.batches++;
    }
    for (const t of ['invoice_lines', 'purchase_lines', 'debit_note_lines', 'schemes']) {
      moved[t] += db.prepare(`UPDATE ${t} SET item_id=? WHERE item_id=?`).run(keepId, id).changes;
    }
    // prices and codes the kept item lacks come from the duplicate
    for (const k of ['mrp', 'retail_price', 'wholesale_price', 'purchase_price']) {
      if (!(keep[k] > 0) && m[k] > 0) { keep[k] = m[k]; db.prepare(`UPDATE items SET ${k}=? WHERE id=?`).run(m[k], keepId); }
    }
    for (const k of ['hsn', 'category_id']) {
      if (blank(keep[k]) === null && blank(m[k]) !== null) { keep[k] = m[k]; db.prepare(`UPDATE items SET ${k}=? WHERE id=?`).run(m[k], keepId); }
    }
    db.prepare('UPDATE items SET active=0 WHERE id=?').run(id);
    names.push(m.name);
  }
  return { kept: keepId, name: keep.name, merged: names, moved };
});

// ---------- item lists from the internet (a company's price list page or PDF) ----------

const BLOCK = ['br', 'p', 'div', 'tr', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table', 'tbody', 'thead', 'ul', 'ol', 'section', 'article', 'header', 'footer', 'dd', 'dt', 'option', 'hr'];
const ENT = { amp: '&', nbsp: ' ', lt: '<', gt: '>', quot: '"', apos: "'", rsquo: "'", lsquo: "'", ndash: '-', mdash: '-', times: 'x', rupee: '₹', copy: '©' };

/** A web page as lines of text: table cells joined by " | ", scripts and styles dropped. */
function htmlLines(html) {
  const s = String(html || '');
  const low = lowerA(s);
  let o = '';
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === '<') {
      if (low.startsWith('<!--', i)) { const e = low.indexOf('-->', i + 4); i = e < 0 ? s.length : e + 3; continue; }
      let j = i + 1;
      if (s[j] === '/') j++;
      let name = '';
      while (j < s.length && (isLetterA(s[j]) || isDigit(s[j]))) name += low[j++];
      const end = s.indexOf('>', j);
      if (!name || end < 0) { o += c; i++; continue; }
      if ((name === 'script' || name === 'style' || name === 'noscript' || name === 'svg') && s[i + 1] !== '/') {
        const close = low.indexOf('</' + name, end);
        i = close < 0 ? s.length : (low.indexOf('>', close) < 0 ? s.length : low.indexOf('>', close) + 1);
        continue;
      }
      if (name === 'td' || name === 'th') o += ' | ';
      else if (BLOCK.includes(name)) o += '\n';
      else o += ' ';
      i = end + 1;
      continue;
    }
    if (c === '&') {
      const semi = s.indexOf(';', i);
      if (semi > i && semi - i <= 8) {
        const ent = s.slice(i + 1, semi);
        let rep = null;
        if (ent[0] === '#') {
          const hex = ent[1] === 'x' || ent[1] === 'X';
          const digits = hex ? ent.slice(2) : ent.slice(1);
          let n = digits.length ? 0 : -1;
          for (let q = 0; q < digits.length && n >= 0; q++) {
            const d = lowerA(digits[q]);
            const v = isDigit(d) ? d.charCodeAt(0) - 48 : (hex && d >= 'a' && d <= 'f' ? d.charCodeAt(0) - 87 : -1);
            n = v < 0 ? -1 : n * (hex ? 16 : 10) + v;
          }
          if (n > 0 && n < 0xd800) rep = n === 160 ? ' ' : String.fromCharCode(n);
        } else if (own(ENT, lowerA(ent))) rep = ENT[lowerA(ent)];
        if (rep !== null) { o += rep; i = semi + 1; continue; }
      }
    }
    o += c;
    i++;
  }
  const lines = [];
  for (const raw of o.split('\n')) {
    const cells = raw.split('|').map(squeeze).filter((x) => x.length);
    const line = cells.join(' | ');
    if (line.length) lines.push(line);
  }
  return lines;
}

const SKIP = ['http', 'www.', 'copyright', '©', 'all rights', 'privacy', 'cookie', 'login', 'sign in', 'cart', 'subscribe', 'whatsapp', 'call us', 'email'];
const PRICE_WORDS = ['mrp', 'rs', 'rs.', 'inr', 'price', '₹', '@'];

/** A number written in a price cell: "₹ 1,250.00", "Rs.50/-", "50" (null when the cell is not just a price). */
function priceCell(cell) {
  let t = lowerA(cell);
  for (const w of ['mrp', 'rs.', 'rs', 'inr', '₹', '/-', ':', ' ']) t = t.split(w).join('');
  t = t.split(',').join('');
  return isNumber(t) ? Number(t) : null;
}

/** Splits "Bhujia 200 gm MRP 50" into the name and the MRP written after it. */
function nameAndMrp(text) {
  const low = lowerA(text);
  let best = -1;
  for (const w of PRICE_WORDS) {
    let from = 0;
    for (;;) {
      const at = low.indexOf(w, from);
      if (at < 0) break;
      from = at + 1;
      const before = at === 0 ? ' ' : low[at - 1];
      if (isLetterA(before) || isDigit(before)) continue;           // inside a word ("Crisps")
      let k = at + w.length;
      const afterW = low[k];
      if (w !== '₹' && w !== '@' && afterW !== undefined && isLetterA(afterW)) continue;
      while (k < low.length && (low[k] === ' ' || low[k] === '.' || low[k] === ':' || low[k] === '-' || low[k] === '=' || low[k] === '₹')) k++;
      if (k < low.length && isDigit(low[k]) && (best < 0 || at < best)) best = at;
    }
  }
  if (best < 0) return { name: text, mrp: null };
  let k = best;
  while (k < text.length && !isDigit(text[k])) k++;
  let num = '';
  while (k < text.length && (isDigit(text[k]) || text[k] === ',' || (text[k] === '.' && isDigit(text[k + 1] || '')))) { if (text[k] !== ',') num += text[k]; k++; }
  return { name: trimEnd(text.slice(0, best), ' -,:|(/'), mrp: isNumber(num) ? Number(num) : null };
}

const hasUnit = (name) => {
  const w = cleanName(name, 'keep').split(' ');
  for (const x of w) {
    let k = 0;
    while (k < x.length && (isDigit(x[k]) || x[k] === '.')) k++;
    if (k > 0 && k < x.length && own(UNITS, lowerA(trimEnd(x.slice(k), '.,)')))) return true;
  }
  return false;
};

/**
 * Items read from a price list: { html } of a web page or { text } (a PDF's text, or pasted). Names are tidied
 * (mode, default Title Case), the company's name is put in front when missing, the same item listed twice is kept
 * once, and items already in the books are marked.
 */
function extractList(b) {
  const mode = ['keep', 'title', 'upper'].includes(b && b.case) ? b.case : 'title';
  const company = squeeze(String((b && b.company) || ''));
  const lines = b && b.html ? htmlLines(b.html) : String((b && b.text) || '').split('\r\n').join('\n').split('\r').join('\n').split('\n').map(squeeze).filter((x) => x.length);
  const existing = new Map();
  for (const it of db.prepare('SELECT id,name FROM items WHERE active=1 ORDER BY id').all()) { const k = itemKey(it.name); if (k && !existing.has(k)) existing.set(k, it); }
  const out = [];
  const seen = new Map();
  let merged = 0;
  let mrpCol = -1, headerCells = 0;   // a table heading with an "MRP" column says which cell is the MRP
  for (const line of lines) {
    const ll = lowerA(line);
    if (SKIP.some((w) => ll.includes(w))) continue;
    const cells = line.split('|').map((x) => squeeze(x)).filter((x) => x.length);
    if (cells.length < 2) { mrpCol = -1; headerCells = 0; } else {
      let h = -1;
      for (let i = 0; i < cells.length; i++) {
        let digit = false;
        for (let q = 0; q < cells[i].length; q++) if (isDigit(cells[i][q])) digit = true;
        if (!digit && lowerA(cells[i]).includes('mrp')) { h = i; break; }
      }
      if (h >= 0) { mrpCol = h; headerCells = cells.length; continue; }
    }
    let nameCell = -1;
    for (let i = 0; i < cells.length; i++) {
      let letters = 0;
      for (const ch of cells[i]) if (isLetterA(ch)) letters++;
      if (letters >= 3 && priceCell(cells[i]) === null) { nameCell = i; break; }
    }
    if (nameCell < 0) continue;
    let { name, mrp } = nameAndMrp(cells[nameCell]);
    if (mrp === null && mrpCol >= 0 && mrpCol !== nameCell && cells.length === headerCells) {
      const p = priceCell(cells[mrpCol]);
      if (p !== null && p > 0) mrp = p;
    }
    // the pack size in a cell of its own: "Bhujia | 200 gm"
    if (!hasUnit(name)) {
      for (let i = nameCell + 1; i < cells.length; i++) {
        if (i === mrpCol && cells.length === headerCells) continue;
        if (cells[i].length <= 12 && priceCell(cells[i]) === null && hasUnit(cells[i])) { name = name + ' ' + cells[i]; break; }
      }
    }
    if (mrp === null) {
      for (let i = 0; i < cells.length; i++) {
        if (i === nameCell) continue;
        const p = priceCell(cells[i]);
        if (p !== null && p > 0 && (mrp === null || p > mrp)) mrp = p;
      }
    }
    // leading serial number: "12. Bhujia" / "12 Bhujia"
    let k = 0;
    while (k < name.length && isDigit(name[k])) k++;
    if (k > 0 && k < name.length && (name[k] === '.' || name[k] === ')' || name[k] === ' ') && !hasUnit(name.slice(0, k + 3))) name = squeeze(name.slice(k + 1));
    if (name.length < 3 || name.length > 90) continue;
    if (!(mrp > 0) && !hasUnit(name)) continue;
    if (company && !lowerA(name).includes(lowerA(company))) name = company + ' ' + name;
    const clean = cleanName(name, mode);
    const key = itemKey(clean);
    if (!key) continue;
    if (seen.has(key)) { const prev = seen.get(key); if (!(prev.mrp > 0) && mrp > 0) prev.mrp = mrp; merged++; continue; }
    const ex = existing.get(key);
    const row = { name: clean, mrp: mrp > 0 ? mrp : null, pack: packFromName(clean) || null, exists_id: ex ? ex.id : null, exists_name: ex ? ex.name : null };
    seen.set(key, row);
    out.push(row);
    if (out.length >= 400) break;
  }
  return { lines: lines.length, items: out, found: out.length, duplicates_merged: merged, new: out.filter((x) => !x.exists_id).length };
}

/** Adds the chosen items in one go (names already in the books are skipped). */
const bulkAdd = db.transaction((b) => {
  const list = b && Array.isArray(b.items) ? b.items : [];
  if (!list.length) throw new HttpError(400, 'Choose the items to add');
  const catId = blank(b.category) === null ? null : ensureCategory(squeeze(String(b.category)));
  const gst = b.gst_rate === undefined || b.gst_rate === null || b.gst_rate === '' ? 18 : Number(b.gst_rate);
  if (!Number.isFinite(gst) || gst < 0 || gst > 40) throw new HttpError(400, 'GST rate must be between 0 and 40');
  const added = [], skipped = [];
  const dup = db.prepare('SELECT id FROM items WHERE active=1 AND lower(name)=lower(?)');
  const ins = db.prepare('INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,pcs_per_box) VALUES(?,?,?,?,?,?,?)');
  for (const it of list) {
    const name = squeeze(String((it && it.name) || ''));
    if (!name) { skipped.push({ name, reason: 'No name' }); continue; }
    if (name.length > 120) { skipped.push({ name, reason: 'Name is too long' }); continue; }
    if (dup.get(name)) { skipped.push({ name, reason: 'Already in your items' }); continue; }
    const mrp = Number(it.mrp || 0);
    const r = ins.run(name, catId, null, gst, 'PCS', Number.isFinite(mrp) && mrp > 0 ? mrp : 0, packFromName(name) || 1);
    added.push({ id: Number(r.lastInsertRowid), name });
  }
  return { added, skipped, category_id: catId };
});

module.exports = { cleanName, itemKey, cleanPreview, applyClean, mergeItems, htmlLines, extractList, bulkAdd, nameAndMrp };
