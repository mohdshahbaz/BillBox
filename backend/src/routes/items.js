const router = require('express').Router();
const db = require('../db');
const { h, ha, HttpError, blank } = require('../utils/misc');
const { mrpFromName, packFromName } = require('../services/pdfParser');
const { guessCategory, ensureCategory, pinned } = require('../services/category');
const { r2 } = require('../utils/gst');
const T = require('../services/itemTools');
const W = require('../services/webList');
const P = require('../services/pricing');

// ---------- categories ----------
router.get('/categories', h((req, res) => {
  res.json(db.prepare('SELECT * FROM categories ORDER BY name').all());
}));
router.post('/categories', h((req, res) => {
  if (!blank(req.body.name)) throw new HttpError(400, 'Category name is required');
  const info = db.prepare('INSERT INTO categories(name) VALUES(?)').run(req.body.name.trim());
  res.status(201).json({ id: Number(info.lastInsertRowid), name: req.body.name.trim() });
}));

// ---------- items ----------
const withMargins = (it) => {
  // Distributor margin on selling price; retailer margin when buying at wholesale and selling at MRP (MRP includes GST).
  const wholesaleInclGst = it.wholesale_price * (1 + it.gst_rate / 100);
  return {
    ...it,
    dist_margin_pct: it.wholesale_price > 0 ? r2(((it.wholesale_price - it.purchase_price) / it.wholesale_price) * 100) : 0,
    retailer_margin_pct: it.mrp > 0 ? r2(((it.mrp - wholesaleInclGst) / it.mrp) * 100) : 0,
  };
};

/** Validates and normalises the editable item fields. Items are identified by name (no SKU or barcode). */
function cleanItem(b, partial) {
  const o = {};
  const num = (k, label, min = 0) => {
    if (b[k] === undefined && partial) return;
    const v = b[k] === undefined || b[k] === '' || b[k] === null ? 0 : Number(b[k]);
    if (!Number.isFinite(v) || v < min) throw new HttpError(400, `${label} must be a number${min === 0 ? ' (0 or more)' : ''}`);
    o[k] = v;
  };
  if (!partial || b.name !== undefined) {
    const name = String(b.name ?? '').trim().replace(/\s+/g, ' ');
    if (!name) throw new HttpError(400, 'Item name is required');
    if (name.length > 120) throw new HttpError(400, 'Item name is too long (120 characters at most)');
    o.name = name;
  }
  num('mrp', 'MRP'); num('retail_price', 'Retail price'); num('wholesale_price', 'Wholesale price'); num('purchase_price', 'Purchase price');
  if (b.gst_rate !== undefined || !partial) {
    const g = b.gst_rate === undefined || b.gst_rate === '' ? 18 : Number(b.gst_rate);
    if (!Number.isFinite(g) || g < 0 || g > 40) throw new HttpError(400, 'GST rate must be between 0 and 40');
    o.gst_rate = g;
  }
  if (b.pcs_per_box !== undefined || !partial) {
    const p = Math.floor(Number(b.pcs_per_box || 1));
    if (!Number.isFinite(p) || p < 1 || p > 100000) throw new HttpError(400, 'Pieces per box must be 1 or more');
    o.pcs_per_box = p;
  }
  o.unit = 'PCS';   // everything is stored in pieces; boxes are worked out from pieces-per-box
  if (b.hsn !== undefined || !partial) {
    const h2 = blank(b.hsn) === null ? null : String(b.hsn).trim();
    if (h2 && !/^\d{2,8}$/.test(h2)) throw new HttpError(400, 'HSN code must be 2 to 8 digits');
    o.hsn = h2;
  }
  if (b.category_id !== undefined || !partial) o.category_id = blank(b.category_id);
  return o;
}

function assertNameFree(name, exceptId) {
  const dup = db.prepare('SELECT id FROM items WHERE active=1 AND lower(name)=lower(?) AND id <> ?').get(name, exceptId || 0);
  if (dup) throw new HttpError(409, `An item named "${name}" already exists`, 'DUPLICATE');
}

router.get('/items', h((req, res) => {
  const q = `%${(req.query.q || '').trim()}%`;
  const cat = req.query.category_id ? Number(req.query.category_id) : null;
  const rows = db.prepare(
    `SELECT i.*, c.name category,
       COALESCE(s.stock,0) stock, s.next_expiry
     FROM items i LEFT JOIN categories c ON c.id=i.category_id
     LEFT JOIN (SELECT item_id, SUM(qty) stock, MIN(CASE WHEN qty>0 AND exp_date < '2099-01-01' THEN exp_date END) next_expiry
                FROM batches GROUP BY item_id) s ON s.item_id=i.id
     WHERE i.active=1 AND (i.name LIKE ? OR COALESCE(i.hsn,'') LIKE ?) AND (? IS NULL OR i.category_id = ?)
     ORDER BY i.name LIMIT ?`
  ).all(q, q, cat, cat, req.query.all === '1' ? -1 : 1000);   // the billing screen asks for every item (all=1)
  res.json(rows.map(withMargins));
}));

router.post('/items', ha(async (req, res) => {
  const o = cleanItem(req.body || {}, false);
  assertNameFree(o.name);
  const pk = packFromName(o.name);
  if (pk) o.pcs_per_box = pk;   // "(1X144)" in the name = 144 pieces per box
  // no category chosen: work it out from the name (rules, then the internet)
  if (!o.category_id) { const g = await guessCategory(o.name); if (g.name) o.category_id = ensureCategory(g.name); }
  const info = db.prepare(
    `INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box)
     VALUES(@name,@category_id,@hsn,@gst_rate,@unit,@mrp,@retail_price,@wholesale_price,@purchase_price,@pcs_per_box)`
  ).run(o);
  res.status(201).json({ id: Number(info.lastInsertRowid) });
}));

router.put('/items/:id', h((req, res) => {
  const cur = db.prepare('SELECT * FROM items WHERE id=?').get(req.params.id);
  if (!cur) throw new HttpError(404, 'Item not found');
  const o = { ...cur, ...cleanItem(req.body || {}, true) };
  assertNameFree(o.name, cur.id);
  const pk = packFromName(o.name);
  if (pk) o.pcs_per_box = pk;
  db.prepare(
    `UPDATE items SET name=@name,category_id=@category_id,hsn=@hsn,gst_rate=@gst_rate,unit=@unit,mrp=@mrp,retail_price=@retail_price,
       wholesale_price=@wholesale_price,purchase_price=@purchase_price,pcs_per_box=@pcs_per_box WHERE id=@id`
  ).run({ ...o, id: cur.id });
  res.json({ ok: true });
}));

/** Fills the category of every uncategorised item from its name. */
router.post('/items/auto-categorize', ha(async (req, res) => {
  // pinned names (e.g. Bikano All Time Mix) are moved even when another category was chosen earlier
  let moved = 0;
  for (const it of db.prepare('SELECT id,name,category_id FROM items WHERE active=1').all()) {
    const pin = pinned(it.name);
    if (!pin) continue;
    const cid = ensureCategory(pin);
    if (it.category_id !== cid) { db.prepare('UPDATE items SET category_id=? WHERE id=?').run(cid, it.id); moved++; }
  }
  const rows = db.prepare('SELECT id,name FROM items WHERE active=1 AND category_id IS NULL').all();
  let done = 0, net = 0;
  for (const it of rows) {
    const g = await guessCategory(it.name);
    if (g.name) { db.prepare('UPDATE items SET category_id=? WHERE id=?').run(ensureCategory(g.name), it.id); done++; if (g.source === 'internet') net++; }
  }
  res.json({ checked: rows.length, categorised: done + moved, from_internet: net });
}));

/**
 * Reads the MRP printed in the item name ("MRP-10/-", "Rs.10/-", "10/-") for every item that has none,
 * and gives items with no selling prices the MRP (without GST) as retail and wholesale price.
 * The reply groups what was found by category so you can see which categories are still missing MRPs.
 */
router.post('/items/auto-mrp', h((req, res) => {
  const r2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
  const rows = db.prepare('SELECT i.id,i.name,i.gst_rate,i.retail_price,i.wholesale_price,COALESCE(c.name,\'Uncategorised\') category FROM items i LEFT JOIN categories c ON c.id=i.category_id WHERE i.active=1 AND COALESCE(i.mrp,0)<=0').all();
  const byCat = {}, missing = [];
  db.transaction(() => {
    for (const it of rows) {
      const g = byCat[it.category] || (byCat[it.category] = { found: 0, missing: 0 });
      const mrp = mrpFromName(it.name);
      if (!mrp) { g.missing++; missing.push({ id: it.id, name: it.name, category: it.category }); continue; }
      const ex = Math.round((mrp / (1 + (it.gst_rate || 0) / 100) + Number.EPSILON) * 1e6) / 1e6;
      db.prepare('UPDATE items SET mrp=?, retail_price=CASE WHEN COALESCE(retail_price,0)<=0 THEN ? ELSE retail_price END, wholesale_price=CASE WHEN COALESCE(wholesale_price,0)<=0 THEN ? ELSE wholesale_price END WHERE id=?').run(mrp, ex, ex, it.id);
      g.found++;
    }
  })();
  const found = Object.values(byCat).reduce((a, g) => a + g.found, 0);
  res.json({ checked: rows.length, found, still_missing: missing.length, by_category: byCat, missing: missing.slice(0, 50) });
}));

/**
 * Sets selling prices for every item of a category from its MRP (MRP includes GST, prices are stored without it):
 *   price = MRP / (1 + GST%) x (1 - off%)      off% = how far below MRP you sell (the retailer's margin)
 * retail_off / wholesale_off are optional, give one or both. preview:true changes nothing and returns what would happen.
 */
router.post('/items/bulk-prices', h((req, res) => {
  const b = req.body || {};
  const catId = b.category_id ? Number(b.category_id) : null;   // empty = every item
  const parse = (v, label) => {
    if (v === undefined || v === null || String(v).trim() === '') return null;
    const n = Number(v);
    if (!Number.isFinite(n) || n < 0 || n >= 100) throw new HttpError(400, `${label} must be a percentage from 0 to 99.99`);
    return n;
  };
  const retailOff = parse(b.retail_off, 'Retail below MRP'), wholesaleOff = parse(b.wholesale_off, 'Wholesale below MRP');
  if (retailOff === null && wholesaleOff === null) throw new HttpError(400, 'Enter the retail and/or wholesale percentage below MRP');
  const rows = db.prepare('SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items WHERE active=1 AND (? IS NULL OR category_id=?) ORDER BY name').all(catId, catId);
  const r2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
  // price per piece without GST. The percentage is usually typed rounded (16.67 for 16.666...), so for items packed in boxes the whole
  // box (GST included) is rounded to the nearest rupee first, and the piece price is that box price divided out: 2499.90 becomes exactly 2500.
  const boxOf = (it) => Math.max(1, parseInt(it.pcs_per_box, 10) || 1);
  const price = (it, off) => {
    const perPieceIncl = it.mrp * (1 - off / 100);
    const ppb = boxOf(it);
    const incl = ppb > 1 ? Math.round(perPieceIncl * ppb + Number.EPSILON) / ppb : perPieceIncl;
    return Math.round((incl / (1 + (it.gst_rate || 0) / 100) + Number.EPSILON) * 1e8) / 1e8;
  };
  const boxIncl = (it, v) => r2(v * boxOf(it) * (1 + (it.gst_rate || 0) / 100));
  const changes = [];
  let skipped = 0;
  for (const it of rows) {
    if (!(it.mrp > 0)) { skipped++; continue; }
    const c = { id: it.id, name: it.name, mrp: it.mrp };
    if (retailOff !== null) { c.retail_old = it.retail_price; c.retail_new = price(it, retailOff); c.retail_box = boxIncl(it, c.retail_new); }
    if (wholesaleOff !== null) { c.wholesale_old = it.wholesale_price; c.wholesale_new = price(it, wholesaleOff); c.wholesale_box = boxIncl(it, c.wholesale_new); }
    changes.push(c);
  }
  if (!b.preview) {
    db.transaction(() => {
      for (const c of changes) {
        if (c.retail_new !== undefined) db.prepare('UPDATE items SET retail_price=? WHERE id=?').run(c.retail_new, c.id);
        if (c.wholesale_new !== undefined) db.prepare('UPDATE items SET wholesale_price=? WHERE id=?').run(c.wholesale_new, c.id);
      }
    })();
  }
  res.json({ updated: b.preview ? 0 : changes.length, would_update: changes.length, skipped_no_mrp: skipped, sample: changes.slice(0, 5) });
}));

/** Re-reads the pieces-per-box of every item from its name: "(1X144)", "(1X240)", "(1X300)" -> 144 / 240 / 300. */
function fixPacks() {
  let changed = 0, checked = 0;
  for (const it of db.prepare('SELECT id,name,pcs_per_box FROM items WHERE active=1').all()) {
    const pk = packFromName(it.name);
    if (!pk) continue;
    checked++;
    if (it.pcs_per_box !== pk) { db.prepare('UPDATE items SET pcs_per_box=? WHERE id=?').run(pk, it.id); changed++; }
  }
  return { checked, changed };
}
router.post('/items/set-prices', h((req, res) => res.json(P.setPrices(req.body || {}))));
router.get('/items/mrp-table', h((req, res) => res.json(P.mrpTable(req.query))));
router.get('/items/clean-preview', h((req, res) => res.json(T.cleanPreview(req.query))));
router.post('/items/clean-names', h((req, res) => res.json(T.applyClean(req.body || {}))));
router.post('/items/merge', h((req, res) => res.json(T.mergeItems(req.body || {}))));
router.post('/items/online/search', ha(async (req, res) => res.json(await W.search(req.body || {}))));
router.post('/items/online/fetch', ha(async (req, res) => res.json(await W.fetchList(req.body || {}))));
router.post('/items/online/extract', h((req, res) => res.json(T.extractList(req.body || {}))));
router.post('/items/bulk-add', h((req, res) => res.status(201).json(T.bulkAdd(req.body || {}))));
router.post('/items/auto-pack', h((req, res) => res.json(fixPacks())));

/** The distinct MRPs among the items (optionally one category) with how many items each has and the prices they carry now. */
router.get('/items/mrp-groups', h((req, res) => {
  const catId = req.query.category_id ? Number(req.query.category_id) : null;
  const rows = db.prepare(
    `SELECT mrp, COUNT(*) items, MIN(retail_price) retail_min, MAX(retail_price) retail_max, MIN(wholesale_price) wholesale_min, MAX(wholesale_price) wholesale_max,
            MIN(gst_rate) gst_min, MAX(gst_rate) gst_max,
            MAX(retail_price * (1 + COALESCE(gst_rate,0) / 100.0)) retail_incl_max,
            MAX(retail_price * MAX(1, COALESCE(pcs_per_box,1))) retail_box_max,
            MAX(retail_price * MAX(1, COALESCE(pcs_per_box,1)) * (1 + COALESCE(gst_rate,0) / 100.0)) retail_box_incl_max,
            MAX(wholesale_price * (1 + COALESCE(gst_rate,0) / 100.0)) wholesale_incl_max,
            MAX(wholesale_price * MAX(1, COALESCE(pcs_per_box,1))) wholesale_box_max,
            MAX(wholesale_price * MAX(1, COALESCE(pcs_per_box,1)) * (1 + COALESCE(gst_rate,0) / 100.0)) wholesale_box_incl_max
     FROM items WHERE active=1 AND mrp > 0 AND (? IS NULL OR category_id=?) GROUP BY mrp ORDER BY mrp`).all(catId, catId);
  res.json(rows);
}));

/**
 * Price list by MRP: for each MRP value (e.g. 5, 10, 20) the retail and wholesale price per piece that every item with that MRP gets.
 * body: { category_id?, include_gst?: bool, tiers: [{ mrp, retail?, wholesale? }], preview? }
 * Prices are stored ex-GST. With include_gst the typed price is GST-inclusive and the tax is backed out per item.
 */
router.post('/items/bulk-prices-by-mrp', h((req, res) => {
  const b = req.body || {};
  const catId = b.category_id ? Number(b.category_id) : null;
  const tiers = (Array.isArray(b.tiers) ? b.tiers : []).map((t) => {
    const num = (v, label) => {
      if (v === undefined || v === null || String(v).trim() === '') return null;
      const n = Number(v);
      if (!Number.isFinite(n) || n < 0) throw new HttpError(400, `${label} must be a number (0 or more)`);
      return n;
    };
    const mrp = num(t.mrp, 'MRP');
    if (!(mrp > 0)) throw new HttpError(400, 'Each row needs an MRP');
    return { mrp, retail: num(t.retail, `Retail price for MRP ${mrp}`), wholesale: num(t.wholesale, `Wholesale price for MRP ${mrp}`) };
  }).filter((t) => t.retail !== null || t.wholesale !== null);
  if (!tiers.length) throw new HttpError(400, 'Enter a retail and/or wholesale price for at least one MRP');
  const items = db.prepare('SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items WHERE active=1 AND mrp>0 AND (? IS NULL OR category_id=?)').all(catId, catId);
  // prices are kept to 6 decimals: 2500 per box of 300 is 8.333333 a piece, so a whole box always comes back to exactly 2500
  const r2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
  const r6 = (n) => Math.round((n + Number.EPSILON) * 1e8) / 1e8;
  const perBox = String(b.per || 'piece').toLowerCase() === 'box';
  const exGst = (it, v) => r6((b.include_gst ? v / (1 + (it.gst_rate || 0) / 100) : v) / (perBox ? Math.max(1, it.pcs_per_box || 1) : 1));
  const changes = [];
  const perTier = tiers.map((t) => ({ mrp: t.mrp, items: 0 }));
  for (const it of items) {
    const ti = tiers.findIndex((t) => Math.abs(t.mrp - it.mrp) < 0.005);
    if (ti < 0) continue;
    const t = tiers[ti];
    perTier[ti].items++;
    changes.push({ id: it.id, name: it.name, mrp: it.mrp,
      ...(t.retail !== null ? { retail_old: it.retail_price, retail_new: exGst(it, t.retail), retail_box: r2(exGst(it, t.retail) * Math.max(1, it.pcs_per_box || 1) * (1 + (it.gst_rate || 0) / 100)) } : {}),
      ...(t.wholesale !== null ? { wholesale_old: it.wholesale_price, wholesale_new: exGst(it, t.wholesale), wholesale_box: r2(exGst(it, t.wholesale) * Math.max(1, it.pcs_per_box || 1) * (1 + (it.gst_rate || 0) / 100)) } : {}) });
  }
  if (!b.preview) {
    db.transaction(() => {
      for (const c of changes) {
        if (c.retail_new !== undefined) db.prepare('UPDATE items SET retail_price=? WHERE id=?').run(c.retail_new, c.id);
        if (c.wholesale_new !== undefined) db.prepare('UPDATE items SET wholesale_price=? WHERE id=?').run(c.wholesale_new, c.id);
      }
    })();
  }
  res.json({ updated: b.preview ? 0 : changes.length, would_update: changes.length, per_mrp: perTier, sample: changes.slice(0, 5) });
}));

/** Items that were ever sold or bought are archived (history stays intact); unused items are removed. */
router.delete('/items/:id', h((req, res) => {
  const it = db.prepare('SELECT * FROM items WHERE id=?').get(req.params.id);
  if (!it) throw new HttpError(404, 'Item not found');
  const used = db.prepare('SELECT (SELECT COUNT(*) FROM invoice_lines WHERE item_id=@i) + (SELECT COUNT(*) FROM purchase_lines WHERE item_id=@i) + (SELECT COUNT(*) FROM debit_note_lines WHERE item_id=@i) n').get({ i: it.id }).n;
  const stock = db.prepare('SELECT COALESCE(SUM(qty),0) n FROM batches WHERE item_id=?').get(it.id).n;
  if (stock > 0 && !req.query.force) throw new HttpError(409, `${it.name} still has ${stock} units in stock. Sell or adjust the stock first.`, 'HAS_STOCK');
  if (used) { db.prepare('UPDATE items SET active=0 WHERE id=?').run(it.id); return res.json({ result: 'archived' }); }
  db.transaction(() => { db.prepare('DELETE FROM schemes WHERE item_id=?').run(it.id); db.prepare('DELETE FROM batches WHERE item_id=?').run(it.id); db.prepare('DELETE FROM items WHERE id=?').run(it.id); })();
  res.json({ result: 'deleted' });
}));

router.get('/items/:id/batches', h((req, res) => {
  res.json(db.prepare('SELECT * FROM batches WHERE item_id=? ORDER BY exp_date').all(req.params.id));
}));

// ---------- stock in (purchase / opening stock) ----------
router.post('/batches', h((req, res) => {
  const b = req.body;
  if (!b.item_id) throw new HttpError(400, 'Choose the item');
  b.batch_no = blank(b.batch_no) || 'OPENING';
  b.exp_date = blank(b.exp_date) || '2099-12-31';
  const qty = parseInt(b.qty, 10);
  if (!(qty > 0)) throw new HttpError(400, 'Quantity must be greater than zero');
  const isDate = (v) => /^\d{4}-\d{2}-\d{2}$/.test(v);
  if (!isDate(b.exp_date) || (blank(b.mfg_date) && !isDate(b.mfg_date))) throw new HttpError(400, 'Dates must be in YYYY-MM-DD format');
  db.prepare(
    `INSERT INTO batches(item_id,batch_no,mfg_date,exp_date,qty,purchase_price,mrp) VALUES(?,?,?,?,?,?,?)
     ON CONFLICT(item_id,batch_no) DO UPDATE SET qty = qty + excluded.qty,
       exp_date = excluded.exp_date, mfg_date = COALESCE(excluded.mfg_date, mfg_date)`
  ).run(b.item_id, String(b.batch_no).trim(), blank(b.mfg_date), b.exp_date, qty, blank(b.purchase_price), blank(b.mrp));
  res.status(201).json({ ok: true });
}));

// ---------- set stock (stocktake correction: total pieces, may be zero or negative) ----------
router.post('/items/:id/set-stock', h((req, res) => {
  const it = db.prepare('SELECT id FROM items WHERE id=?').get(req.params.id);
  if (!it) throw new HttpError(404, 'Item not found');
  const target = Number(req.body && req.body.qty);
  if (!Number.isInteger(target)) throw new HttpError(400, 'Enter the stock as a whole number of pieces');
  const cur = db.prepare('SELECT COALESCE(SUM(qty),0) n FROM batches WHERE item_id=?').get(it.id).n;
  const diff = target - cur;
  if (diff !== 0) db.prepare(
    `INSERT INTO batches(item_id,batch_no,exp_date,qty) VALUES(?,?,?,?)
     ON CONFLICT(item_id,batch_no) DO UPDATE SET qty = qty + excluded.qty`
  ).run(it.id, 'ADJUST', '2099-12-31', diff);
  res.json({ ok: true, previous: cur, stock: target });
}));

// ---------- schemes ----------
router.get('/schemes', h((req, res) => {
  res.json(db.prepare('SELECT s.*, i.name item_name FROM schemes s JOIN items i ON i.id=s.item_id WHERE s.active=1').all());
}));
router.post('/schemes', h((req, res) => {
  const b = req.body;
  if (!['FREE_QTY', 'PERCENT'].includes(b.type)) throw new HttpError(400, 'Scheme type must be FREE_QTY or PERCENT');
  db.prepare('INSERT INTO schemes(item_id,type,buy_qty,free_qty,percent,valid_from,valid_to) VALUES(?,?,?,?,?,?,?)')
    .run(b.item_id, b.type, parseInt(b.buy_qty) || 1, parseInt(b.free_qty) || 0, Number(b.percent) || 0, blank(b.valid_from), blank(b.valid_to));
  res.status(201).json({ ok: true });
}));
router.delete('/schemes/:id', h((req, res) => {
  db.prepare('UPDATE schemes SET active=0 WHERE id=?').run(req.params.id);
  res.json({ ok: true });
}));

// ---- Mix boxes: a box of N pieces made of `each` pieces of every matching item in stock (bill screen › Mix box) ----

/** The boxes offered until the owner changes them (Settings key mix_boxes, a JSON list). `match` is words the item name
 *  must contain (any of them; none = every item), "-WORD" words it must not; `category` (optional) the category name, or
 *  part of it; `mrp` 0 = any MRP; `box` 0 = one lot of each. */
const MIX_DEFAULTS = [
  { name: '₹10 Namkeen mix box', match: '-CHIPS -PAPAD', mrp: 10, box: 300, each: 12 },
  { name: '₹5 Namkeen mix box', match: '-CHIPS -PAPAD', mrp: 5, box: 432, each: 12 },
  { name: '₹5 Chips mix box', match: 'CHIPS', mrp: 5, box: 192, each: 12 },
  { name: 'Chatpat papad mix box', match: 'CHATPAT', mrp: 0, box: 300, each: 12 },
  { name: '₹20 Namkeen mix box', match: '-CHIPS -PAPAD', mrp: 20, box: 120, each: 10 },
  { name: 'All namkeen in stock (12 pc each)', match: '-CHIPS -PAPAD', mrp: 0, box: 0, each: 12 },
  { name: 'Makhana mix box', match: 'MAKHANA MAKANNA', mrp: 0, box: 120, each: 10 },
];

function mixPresets() {
  const r = db.prepare("SELECT value FROM settings WHERE key='mix_boxes'").get();
  try { const v = r && JSON.parse(r.value); if (Array.isArray(v) && v.length) return v; } catch (_) { /* bad setting: defaults */ }
  return MIX_DEFAULTS;
}

/** Does the item name pass the preset's words? */
function mixMatch(name, match) {
  const n = String(name || '').toUpperCase();
  const words = String(match || '').toUpperCase().split(/[\s,]+/).filter(Boolean);
  const want = words.filter((w) => !w.startsWith('-')), not = words.filter((w) => w.startsWith('-')).map((w) => w.slice(1)).filter(Boolean);
  return (!want.length || want.some((w) => n.includes(w))) && !not.some((w) => n.includes(w));
}

/** Is the item in the preset's category? Empty = any category; otherwise the category name contains it (any case). */
function catMatch(cat, want) {
  const w = String(want || '').trim().toUpperCase();
  return !w || String(cat || '').toUpperCase().includes(w);
}

/** The lines of one box: `each` pieces of every matching item in stock (by name), then more lots of the same items, round
 *  after round, until the box is full or the stock runs out (`short` then says how many pieces are missing). */
function planMix(p) {
  const each = Math.max(1, Math.floor(Number(p.each) || 12));
  const box = Math.max(0, Math.floor(Number(p.box) || 0));
  const mrp = Number(p.mrp) || 0;
  const rows = db.prepare(
    `SELECT i.*, c.name category, COALESCE(s.stock,0) stock, s.next_expiry
     FROM items i LEFT JOIN categories c ON c.id=i.category_id
     LEFT JOIN (SELECT item_id, SUM(qty) stock, MIN(CASE WHEN qty>0 AND exp_date < '2099-01-01' THEN exp_date END) next_expiry
                FROM batches GROUP BY item_id) s ON s.item_id=i.id
     WHERE i.active=1 AND COALESCE(s.stock,0) > 0 ORDER BY i.name`
  ).all().filter((it) => mixMatch(it.name, p.match) && catMatch(it.category, p.category) && (!mrp || Math.abs((Number(it.mrp) || mrpFromName(it.name) || 0) - mrp) < 0.01));
  const pcs = new Map();
  let left = box || rows.length * each;
  for (let more = true; left > 0 && more;) {
    more = false;
    for (const it of rows) {
      if (left <= 0) break;
      const have = pcs.get(it.id) || 0;
      const take = Math.min(each, left, Math.floor(it.stock) - have);
      if (take <= 0) continue;
      pcs.set(it.id, have + take); left -= take; more = true;
    }
    if (!box) break;   // "one lot of each": a single round
  }
  const lines = rows.filter((it) => pcs.has(it.id)).map((it) => ({ ...withMargins(it), pcs: pcs.get(it.id) }));
  const filled = lines.reduce((a, l) => a + l.pcs, 0);
  return { name: p.name || '', box, each, filled, short: box ? Math.max(0, box - filled) : 0, items: lines.length, lines };
}

router.get('/mixboxes', h((req, res) => res.json(mixPresets())));
router.post('/mixboxes/plan', h((req, res) => {
  const b = req.body || {};
  const p = b.index !== undefined ? mixPresets()[Number(b.index)] : b;
  if (!p) throw new HttpError(404, 'Mix box not found');
  res.json(planMix(p));
}));

module.exports = router;
module.exports.fixPacks = fixPacks;
module.exports.planMix = planMix;
module.exports.mixMatch = mixMatch;
