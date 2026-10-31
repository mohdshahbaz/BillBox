/**
 * After a supplier PDF is read: create the supplier and any stock items the bill mentions that are not in the books yet,
 * so the purchase screen opens with every row already linked. Item facts come from the bill:
 *   name        as printed (so the same bill reads back as a match next time)
 *   HSN         the HSN column
 *   GST rate    printed on the bill (CGST% + SGST%), else the usual rate for that HSN, else 18 (flagged)
 *   pieces/box  from the name: (1X144) -> 144
 *   MRP         from the name: MRP-10/- -> 10
 *   category    keyword rules, then an internet lookup (services/category.js)
 */
const db = require('../db');
const { r2 } = require('../utils/gst');
const { guessCategory, ensureCategory } = require('./category');

const BOX_UNIT = /^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$/i;
const tidy = (s) => String(s || '').replace(/\s+/g, ' ').trim();

async function createMissing(parsed, { online = true } = {}) {
  const warnings = parsed.warnings;
  const lines = parsed.lines;
  const missing = new Map();                       // lower-case name -> first line
  for (const l of lines) if (!l.item_id) { const k = tidy(l.description).toLowerCase(); if (k && !missing.has(k)) missing.set(k, l); }

  // categories need the network, so settle them before the database transaction
  const cats = new Map();
  const keys = [...missing.keys()];
  for (let i = 0; i < keys.length; i += 5) {
    await Promise.all(keys.slice(i, i + 5).map(async (k) => { cats.set(k, await guessCategory(missing.get(k).description, { online })); }));
  }

  let createdItems = 0, createdSupplier = false, noBox = 0, noRate = 0, internetCats = 0;
  db.transaction(() => {
    // supplier
    const sup = parsed.supplier;
    if (sup && sup.name && !sup.matched_party_id) {
      let p = sup.gstin ? db.prepare("SELECT id,name FROM parties WHERE upper(gstin)=? AND active=1").get(String(sup.gstin).toUpperCase()) : null;
      if (!p) p = db.prepare('SELECT id,name FROM parties WHERE lower(name)=lower(?) AND active=1').get(tidy(sup.name));
      if (!p) {
        const id = Number(db.prepare(
          `INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,fssai,pan,email,type,price_tier)
           VALUES(?,?,?,?,?,?,?,?,?,?,'SUPPLIER','WHOLESALE')`
        ).run(tidy(sup.name), sup.gstin || null, sup.state_code || '09', sup.phone || null, sup.tel || null, (sup.mobiles || []).join(', ') || null,
          sup.address || null, sup.fssai || null, sup.pan || null, sup.email || null).lastInsertRowid);
        p = { id, name: tidy(sup.name) };
        createdSupplier = true;
      }
      sup.matched_party_id = p.id; sup.matched_name = p.name; sup.created = createdSupplier;
    }
    // a supplier already in Parties (matched by GSTIN or a similar name): details missing there are filled in from the bill
    if (sup && sup.matched_party_id && !createdSupplier) {
      const fill = db.prepare(`UPDATE parties SET gstin=COALESCE(NULLIF(gstin,''),?), phone=COALESCE(NULLIF(phone,''),?), tel=COALESCE(NULLIF(tel,''),?),
        mobiles=COALESCE(NULLIF(mobiles,''),?), address=COALESCE(NULLIF(address,''),?), fssai=COALESCE(NULLIF(fssai,''),?), pan=COALESCE(NULLIF(pan,''),?),
        email=COALESCE(NULLIF(email,''),?) WHERE id=?`);
      fill.run(sup.gstin || null, sup.phone || null, sup.tel || null, (sup.mobiles || []).join(', ') || null, sup.address || null,
        sup.fssai || null, sup.pan || null, sup.email || null, sup.matched_party_id);
    }

    // items
    const made = new Map();
    for (const l of lines) {
      if (l.item_id) continue;
      const name = tidy(l.description), k = name.toLowerCase();
      if (!name) continue;
      let it = made.get(k) || db.prepare('SELECT id,name FROM items WHERE active=1 AND lower(name)=lower(?)').get(name);
      if (!it) {
        const ppb = BOX_UNIT.test(l.unit || '') ? (l.pcs_per_box || 1) : (l.pcs_per_box || 1);
        if (BOX_UNIT.test(l.unit || '') && !l.pcs_per_box) noBox++;
        const gst = l.gst_rate === null || l.gst_rate === undefined ? 18 : l.gst_rate;
        if (l.gst_rate === null || l.gst_rate === undefined) noRate++;
        const perPiece = BOX_UNIT.test(l.unit || '') ? r2(l.rate / ppb) : l.rate;          // cost of one piece
        const mrp = l.mrp || 0;
        const sell = mrp ? r2(mrp / (1 + gst / 100)) : 0;                                    // MRP without GST: the highest sensible price
        const c = cats.get(k);
        const catId = c && c.name ? ensureCategory(c.name) : null;
        if (c && c.source === 'internet') internetCats++;
        const id = Number(db.prepare(
          `INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box)
           VALUES(?,?,?,?,'PCS',?,?,?,?,?)`
        ).run(name, catId, l.hsn || null, gst, mrp, sell, sell, perPiece, ppb).lastInsertRowid);
        it = { id, name }; made.set(k, it); createdItems++;
        l.category = c && c.name ? c.name : null;
      }
      l.item_id = it.id; l.item_name = it.name; l.match_confidence = 1; l.created = true;
    }
  })();

  // the "not matched" warning no longer applies; say what was done instead
  const i = warnings.findIndex((w) => /not matched to your stock list/.test(w));
  if (i >= 0) warnings.splice(i, 1);
  if (createdSupplier) warnings.unshift(`Supplier "${parsed.supplier.name}" was added to Parties.`);
  if (createdItems) warnings.unshift(`${createdItems} new item${createdItems > 1 ? 's' : ''} added to Stock with HSN, GST rate, pieces per box and category taken from the bill${internetCats ? ` (${internetCats} categories found on the internet)` : ''}. Selling prices were set to MRP without GST; adjust them in Stock.`);
  if (noBox) warnings.push(`${noBox} item(s) are bought in boxes but the pieces per box were not in the name; set it in Stock.`);
  if (noRate) warnings.push(`${noRate} item(s) had no GST rate on the bill; 18% was assumed. Check it in Stock.`);
  parsed.created = { items: createdItems, supplier: createdSupplier };
  return parsed;
}

module.exports = { createMissing };
