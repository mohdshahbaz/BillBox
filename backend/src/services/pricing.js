const db = require('../db');
const { HttpError } = require('../utils/misc');
const { r2, splitTax } = require('../utils/gst');

/**
 * Set retail / wholesale prices from the MRP, for many items at once.
 *
 * The books keep selling prices per piece WITHOUT GST (billing adds the item's GST). The MRP is per piece WITH GST.
 * So a price meant to include GST is divided by (1 + GST%) before it is stored; 8 decimals are kept, so a whole box
 * always comes back to exactly the price that was set (2,500 a box stays 2,500, not 2,499.99 or 2,950).
 *
 * body:
 *   mode: 'percent'   retail_off / wholesale_off = % below MRP (either or both)
 *         'table'     tiers: [{ mrp, retail?, wholesale? }] = the price for every item with that piece MRP
 *   per: 'box' | 'piece'     (table) the typed price is for a whole box or one piece
 *   include_gst: true|false  (table) the typed price includes GST (default true)
 *   round: 'auto' | 'none' | '1' | '5' | '10'
 *          (percent) the price of a box (or of one piece for loose items), GST included, is rounded to this many rupees;
 *          auto = nearest rupee when that price is 50 or more, otherwise to the paisa
 *   category_id?, item_ids?: [..]   which items (default every item with an MRP)
 *   preview: true            change nothing, only report
 * Reply: every item with its MRP (piece and box), the new box price with GST and what one box totals on a bill.
 */
const r8 = (n) => Math.round((n + Number.EPSILON) * 1e8) / 1e8;
const boxOf = (it) => Math.max(1, parseInt(it.pcs_per_box, 10) || 1);
const gstOf = (it) => Number(it.gst_rate) || 0;

/** What one box comes to on a bill at this ex-GST piece rate: billing's own arithmetic (same state, no discount). */
function billForBox(it, rate) {
  const gross = r2(rate * boxOf(it));
  const t = splitTax(gross, gstOf(it), true);
  return Math.round(r2(gross + t.cgst + t.sgst + t.igst));
}

function roundTo(v, round) {
  if (round === 'none' || (round === 'auto' && v < 50)) return r2(v);
  const step = round === 'auto' ? 1 : Number(round);
  return Math.round(v / step + 1e-9) * step;
}

function setPrices(b) {
  b = b || {};
  const mode = b.mode === 'table' ? 'table' : 'percent';
  const round = ['auto', 'none', '1', '5', '10'].includes(String(b.round)) ? String(b.round) : 'auto';
  const pct = (v, label) => {
    if (v === undefined || v === null || String(v).trim() === '') return null;
    const n = Number(v);
    if (!Number.isFinite(n) || n < 0 || n >= 100) throw new HttpError(400, `${label} must be a percentage from 0 to 99.99`);
    return n;
  };
  const money = (v, label) => {
    if (v === undefined || v === null || String(v).trim() === '') return null;
    const n = Number(String(v).split(',').join(''));
    if (!Number.isFinite(n) || n < 0) throw new HttpError(400, `${label} must be a number (0 or more)`);
    return n;
  };
  let retailOff = null, wholesaleOff = null, tiers = [];
  if (mode === 'percent') {
    retailOff = pct(b.retail_off, 'Retail % below MRP');
    wholesaleOff = pct(b.wholesale_off, 'Wholesale % below MRP');
    if (retailOff === null && wholesaleOff === null) throw new HttpError(400, 'Enter the retail and/or wholesale % below MRP');
  } else {
    tiers = (Array.isArray(b.tiers) ? b.tiers : []).map((t) => {
      const mrp = money(t && t.mrp, 'MRP');
      if (!(mrp > 0)) throw new HttpError(400, 'Each row needs an MRP');
      return { mrp, retail: money(t.retail, `Retail price for MRP ${mrp}`), wholesale: money(t.wholesale, `Wholesale price for MRP ${mrp}`) };
    }).filter((t) => t.retail !== null || t.wholesale !== null);
    if (!tiers.length) throw new HttpError(400, 'Enter a retail and/or wholesale price for at least one MRP');
  }
  const perBox = String(b.per || 'box').toLowerCase() !== 'piece';
  const inclGst = b.include_gst !== false && b.include_gst !== 0 && b.include_gst !== '0' && b.include_gst !== 'false';
  const catId = b.category_id ? Number(b.category_id) : null;
  const only = Array.isArray(b.item_ids) && b.item_ids.length ? b.item_ids.map(Number) : null;

  const rows = db.prepare(`SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items
    WHERE active=1 AND (? IS NULL OR category_id=?) ORDER BY name, id`).all(catId, catId).filter((it) => !only || only.includes(it.id));

  /** ex-GST piece rate for a box price that includes GST */
  const fromBoxIncl = (it, box) => r8(box / boxOf(it) / (1 + gstOf(it) / 100));
  const fromPercent = (it, off) => {
    const unit = boxOf(it) > 1 ? boxOf(it) : 1;
    const incl = roundTo(it.mrp * unit * (1 - off / 100), round);
    return fromBoxIncl(it, incl);
  };
  const fromTyped = (it, v) => {
    const perPiece = perBox ? v / boxOf(it) : v;
    return r8(inclGst ? perPiece / (1 + gstOf(it) / 100) : perPiece);
  };

  const out = [];
  let skipped = 0;
  for (const it of rows) {
    if (!(it.mrp > 0)) { skipped++; continue; }
    let newRetail = null, newWholesale = null;
    if (mode === 'percent') {
      if (retailOff !== null) newRetail = fromPercent(it, retailOff);
      if (wholesaleOff !== null) newWholesale = fromPercent(it, wholesaleOff);
    } else {
      const t = tiers.find((x) => Math.abs(x.mrp - it.mrp) < 0.005);
      if (!t) continue;
      if (t.retail !== null) newRetail = fromTyped(it, t.retail);
      if (t.wholesale !== null) newWholesale = fromTyped(it, t.wholesale);
    }
    const c = { id: it.id, name: it.name, pcs_per_box: boxOf(it), gst_rate: gstOf(it), mrp: it.mrp, mrp_box: r2(it.mrp * boxOf(it)) };
    if (newRetail !== null) {
      Object.assign(c, { retail_old: it.retail_price, retail_old_bill: billForBox(it, it.retail_price), retail_new: newRetail,
        retail_box: r2(newRetail * boxOf(it) * (1 + gstOf(it) / 100)), retail_bill: billForBox(it, newRetail),
        retail_below_pct: r2((1 - billForBox(it, newRetail) / (it.mrp * boxOf(it))) * 100) });
    }
    if (newWholesale !== null) {
      Object.assign(c, { wholesale_old: it.wholesale_price, wholesale_old_bill: billForBox(it, it.wholesale_price), wholesale_new: newWholesale,
        wholesale_box: r2(newWholesale * boxOf(it) * (1 + gstOf(it) / 100)), wholesale_bill: billForBox(it, newWholesale),
        wholesale_below_pct: r2((1 - billForBox(it, newWholesale) / (it.mrp * boxOf(it))) * 100) });
    }
    out.push(c);
  }
  if (!b.preview) {
    const ur = db.prepare('UPDATE items SET retail_price=? WHERE id=?'), uw = db.prepare('UPDATE items SET wholesale_price=? WHERE id=?');
    db.transaction(() => {
      for (const c of out) {
        if (c.retail_new !== undefined) ur.run(c.retail_new, c.id);
        if (c.wholesale_new !== undefined) uw.run(c.wholesale_new, c.id);
      }
    })();
  }
  return { mode, round, updated: b.preview ? 0 : out.length, would_update: out.length, skipped_no_mrp: skipped, items: out.slice(0, 500) };
}

/** MRP groups for the price table: piece MRP, how many items, their box sizes and today's prices (box, GST included). */
function mrpTable(q) {
  const catId = q && q.category_id ? Number(q.category_id) : null;
  const rows = db.prepare(`SELECT id,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items
    WHERE active=1 AND mrp > 0 AND (? IS NULL OR category_id=?) ORDER BY mrp, id`).all(catId, catId);
  const groups = [];
  for (const it of rows) {
    let g = groups.find((x) => Math.abs(x.mrp - it.mrp) < 0.005);
    if (!g) { g = { mrp: it.mrp, items: 0, boxes: [], retail_box: null, wholesale_box: null, retail_piece: null, wholesale_piece: null }; groups.push(g); }
    g.items++;
    if (!g.boxes.includes(boxOf(it))) g.boxes.push(boxOf(it));
    const rb = r2(it.retail_price * boxOf(it) * (1 + gstOf(it) / 100)), wb = r2(it.wholesale_price * boxOf(it) * (1 + gstOf(it) / 100));
    const rp = r2(it.retail_price * (1 + gstOf(it) / 100)), wp = r2(it.wholesale_price * (1 + gstOf(it) / 100));
    if (g.retail_box === null || rb > g.retail_box) g.retail_box = rb;
    if (g.wholesale_box === null || wb > g.wholesale_box) g.wholesale_box = wb;
    if (g.retail_piece === null || rp > g.retail_piece) g.retail_piece = rp;
    if (g.wholesale_piece === null || wp > g.wholesale_piece) g.wholesale_piece = wp;
  }
  for (const g of groups) { g.boxes.sort((a, b) => a - b); g.mrp_box = g.boxes.length === 1 ? r2(g.mrp * g.boxes[0]) : null; }
  return groups;
}

module.exports = { setPrices, mrpTable, billForBox };
