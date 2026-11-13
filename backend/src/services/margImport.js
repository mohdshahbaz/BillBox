const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const db = require('../db');
const { r2 } = require('../utils/gst');
const { HttpError, peekNo, followLast } = require('../utils/misc');
const { fyRange } = require('../utils/fy');
const { mrpFromName, packFromName } = require('./pdfParser');
const { pinned, byRules, cleanQuery } = require('./category');

/**
 * Import from a Marg ERP backup exported as CSV files (Marg: Reports > Management Report > Data Transfer Utility > Export All Data > CSV — a folder or .zip of pro.csv,
 * order.csv, mdis.csv, dis.csv, gledger.csv, saletype.csv ...).
 *
 *   pro.csv       items: name, pack, MRP, purchase rate, opening and closing stock (pieces)
 *   saletype.csv  HSN codes and GST rates (rows COMMCD), manufacturer names (rows ZZZZZZ)
 *   order.csv     accounts: sundry debtors (group C6..) = customers, sundry creditors (D3..) = suppliers, with opening balance
 *   mdis.csv      bill headers: S = sale, P = purchase, Q = debit note (goods returned to a supplier)
 *   dis.csv       bill rows (quantities in pieces, rates per box, amounts after discount, GST)
 *   gledger.csv   ledger postings: book R = money received from a customer, book P = money paid to a supplier
 *
 * Cleaning: names trimmed and single-spaced (Marg pads names and puts the city after a run of spaces), invalid GSTIN / PAN
 * dropped, phone numbers split into mobiles and landlines, Marg's placeholder rows (###..., "PRODUCT NAME") skipped,
 * duplicate names merged. Stock: one batch "MARG" per item = opening + purchases - sales (Marg's debit notes here come from the
 * breakage godown and do not move stock, so neither do the imported ones). Sales are credit bills; Marg's receipts are imported
 * as receipts. Everything is checked against Marg's own figures: every bill's total, every party's closing balance and every
 * item's closing stock.
 *
 * Importing twice adds nothing twice: items and parties are matched by name, bills and vouchers by their Marg number.
 */

const GSTIN_RE = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const PAN_RE = /^[A-Z]{5}\d{4}[A-Z]$/;
const NO_EXPIRY = '2099-12-31';
const r8 = (n) => Math.round((n + Number.EPSILON) * 1e8) / 1e8;
const num = (s) => { const n = Number(String(s ?? '').trim()); return Number.isFinite(n) ? n : 0; };
const int = (s) => Math.round(num(s));
const clean = (s) => String(s ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
const key = (s) => clean(s).toLowerCase();
const day = (s) => { const m = /^(\d{1,2})-(\d{1,2})-(\d{4})/.exec(String(s ?? '').trim()); return m ? `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}` : null; };

// ------------------------------------------------------------------ reading the backup
/** Entries of a .zip file (stored or deflated), as { name: Buffer }. */
function readZip(buf) {
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) throw new HttpError(400, 'This is not a zip file.');
  const out = {};
  let p = buf.readUInt32LE(eocd + 16);
  for (let k = 0, n = buf.readUInt16LE(eocd + 10); k < n; k++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new HttpError(400, 'The zip file is damaged.');
    const method = buf.readUInt16LE(p + 10), csize = buf.readUInt32LE(p + 20);
    const nlen = buf.readUInt16LE(p + 28), xlen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32), local = buf.readUInt32LE(p + 42);
    const name = buf.slice(p + 46, p + 46 + nlen).toString('utf8');
    p += 46 + nlen + xlen + clen;
    if (name.endsWith('/') || name.startsWith('__MACOSX/')) continue;
    const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    const raw = buf.slice(start, start + csize);
    out[name] = method === 0 ? raw : method === 8 ? zlib.inflateRawSync(raw) : null;
  }
  return out;
}

/** { 'pro.csv': text, ... } from a folder (searched a few levels down) or a .zip. Marg writes Windows-1252 / Latin-1 text. */
function readSource(p) {
  if (!p || !path.isAbsolute(String(p)) || !fs.existsSync(p)) throw new HttpError(400, 'Choose the Marg backup folder or .zip file.');
  const files = {};
  const take = (name, buf) => { const b = path.basename(name).toLowerCase(); if (b.endsWith('.csv') && buf && !(b in files)) files[b] = buf.toString('latin1'); };
  if (fs.statSync(p).isDirectory()) {
    const walk = (d, depth) => {
      let list;
      try { list = fs.readdirSync(d, { withFileTypes: true }); } catch { return; } // a folder that cannot be opened is skipped
      for (const e of list.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
        const f = path.join(d, e.name);
        if (e.isDirectory()) { if (depth < 3 && e.name !== '__MACOSX') walk(f, depth + 1); continue; }
        // only regular .csv files are read: a folder such as Downloads may hold large files, sockets or devices
        if (!e.isFile() || !e.name.toLowerCase().endsWith('.csv') || e.name.toLowerCase() in files) continue;
        try { take(e.name, fs.readFileSync(f)); } catch { /* unreadable: treated as missing */ }
      }
    };
    walk(p, 0);
  } else {
    const entries = readZip(fs.readFileSync(p));
    for (const n of Object.keys(entries).sort()) take(n, entries[n]);
  }
  for (const need of ['pro.csv', 'order.csv', 'mdis.csv', 'dis.csv'])
    if (!files[need]) throw new HttpError(400, `This is not a Marg CSV backup: ${need} is missing.`);
  return files;
}

/** RFC 4180 CSV (Marg does not quote, but a quoted field still reads right). First row = column names. */
function parseCsv(text) {
  const rows = [];
  let row = [], f = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c;
    } else if (c === '"' && f === '') q = true;
    else if (c === ',') { row.push(f); f = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(f); f = '';
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    } else f += c;
  }
  if (f !== '' || row.length) { row.push(f); if (row.length > 1 || row[0] !== '') rows.push(row); }
  if (!rows.length) return [];
  const head = rows[0].map((h) => h.trim().toUpperCase());
  return rows.slice(1).map((r) => { const o = {}; head.forEach((h, i) => { if (!(h in o)) o[h] = r[i] === undefined ? '' : r[i]; }); return o; });
}

// ------------------------------------------------------------------ building the books from the CSV tables
const mobileOf = (d) => { const x = d.replace(/^(91|0)(?=\d{10}$)/, ''); return /^[6-9]\d{9}$/.test(x) ? x : null; };

function model(files) {
  const T = (n) => (files[n] ? parseCsv(files[n]) : []);
  const pro = T('pro.csv'), order = T('order.csv'), mdis = T('mdis.csv'), dis = T('dis.csv'), gl = T('gledger.csv'), st = T('saletype.csv');
  const cleaning = [], warnings = [];
  const note = (arr, s) => { if (!arr.includes(s)) arr.push(s); };

  // HSN / GST by commodity code, manufacturer by company code
  const commodity = {}, company = {};
  for (const r of st) {
    const code = clean(r.SCODE);
    if (!code) continue;
    if (clean(r.SGCODE) === 'COMMCD' && !(code in commodity)) {
      const h = clean(r.PARNAM);
      commodity[code] = { hsn: /^\d{4,8}$/.test(h) ? h : null, gst: num(r.IGST) };
    } else if (clean(r.SGCODE) === 'ZZZZZZ' && !(code in company)) company[code] = clean(r.SNAME) || clean(r.PARNAM) || null;
  }

  /**
   * How many pieces Marg's Rate A is for. Marg keeps it per its own pack (10 for "Boondi 38g (250 PKT)", where 250 is the
   * case), per the case, or per piece, item by item. The last purchase rate (LPRATE) is per piece, so the pack that puts
   * the per-piece sale rate just above it wins; without one, Marg's own pack (never the case size read from the name).
   */
  function rateUnit(rate, packs, lp, inner) {
    const marg = Math.max(1, packs[0] || 1);
    if (!(lp > 0) || !(rate > 0)) return marg;
    // one piece, Marg's pack, the case in the name, or Marg's pack of the packs its bills are written in (36 x 12)
    const cands = [...new Set([1, ...packs.filter((p) => p > 0), ...inner.filter((q) => q > 1).map((q) => marg * q)])];
    const off = (d) => Math.abs(Math.log(rate / d / (lp * 1.15)));
    const best = cands.reduce((b, d) => (off(d) < off(b) - 1e-9 ? d : b), marg);
    return off(best) <= Math.log(3) ? best : marg;   // nothing near the purchase rate: the purchase rate is off, keep Marg's pack
  }
  /** Marg's last purchase rate is per piece for most items and per box for some: when it is far above the per-piece sale
   *  rate, the box it is for (the usual billing pack, or Marg's pack) brings it back to just under the sale rate. */
  function purchaseRate(lp, sale, packs) {
    if (!(lp > 0) || !(sale > 0) || lp <= sale * 3) return r8(lp);
    const off = (d) => Math.abs(Math.log(lp / d / (sale * 0.87)));
    const best = packs.filter((p) => p > 1).reduce((b, d) => (b === null || off(d) < off(b) - 1e-9 ? d : b), null);
    return best !== null && off(best) <= Math.log(2) ? r8(lp / best) : r8(lp);
  }
  /** A name with the piece's MRP ("Fatax Noodles 5/-") whose rate is above it: the rate is for a box, so the box it is for
   *  (the box in the name, the usual billing pack or Marg's pack) that lands it under the MRP brings it to one piece. */
  function byNameMrp(it, packs) {
    const nm = mrpFromName(it.name);
    const incl = it.retail_price * (1 + (it.gst_rate || 0) / 100);
    if (!(nm > 0) || !(incl > nm * 1.02)) return;
    for (const d of [...new Set(packs.filter((p) => p > 1))]) {
      const v = incl / d;
      if (v >= nm * 0.5 && v <= nm * 1.02) {
        it.retail_price = it.wholesale_price = r8(it.retail_price / d);
        if (it.purchase_price > nm) it.purchase_price = r8(it.purchase_price / d);
        return;
      }
    }
  }
  // the packs each item's bill rows are written in (12 for a box of 12 packets)
  const linePacks = {};
  for (const l of dis) { const p = int(l.PACK); if (p > 1) (linePacks[clean(l.CODE)] = linePacks[clean(l.CODE)] || new Set()).add(p); }

  // latest sale rate of each item (ex-GST, per piece): what the item is actually sold at.
  // The pack each item is usually billed in (rows in another pack, like a later change of pack in Marg, are left out)
  const packCount = {};
  for (const l of dis) if (clean(l.FLG) === 'G' && num(l.SFRATE) > 0) {
    const c = clean(l.CODE), p = Math.max(1, int(l.PACK) || 1);
    (packCount[c] = packCount[c] || {})[p] = (packCount[c][p] || 0) + 1;
  }
  const usualPack = (c) => Object.entries(packCount[c] || {}).reduce((b, [p, n]) => (!b || n > b[1] || (n === b[1] && +p < +b[0]) ? [p, n] : b), null);
  const saleRate = {};
  for (const l of dis) if (clean(l.FLG) === 'G' && num(l.SFRATE) > 0) {
    const d = day(l.DATE) || '', c = clean(l.CODE), p = Math.max(1, int(l.PACK) || 1);
    if (String(p) !== usualPack(c)[0]) continue;
    const cur = saleRate[c];
    if (!cur || d >= cur.date) saleRate[c] = { date: d, rate: r8(num(l.SFRATE) / p) };
  }

  // the MRP Marg keeps as the batch label on bill rows ("120.00" = a box of 12 at Rs 10), per piece, latest row first
  const batchMrp = {};
  for (const l of dis) {
    const f = clean(l.FLG), b = num(l.BATCH);
    if ((f !== 'G' && f !== 'P') || !(b > 0)) continue;
    if (packCount[clean(l.CODE)] && String(Math.max(1, int(l.PACK) || 1)) !== usualPack(clean(l.CODE))[0]) continue;   // the usual pack only
    const d = day(l.DATE) || '';
    const cur = batchMrp[clean(l.CODE)];
    if (!cur || d >= cur.date) batchMrp[clean(l.CODE)] = { date: d, mrp: r2(b / Math.max(1, int(l.PACK) || 1)) };
  }

  // ---- items
  const items = [], itemByCode = {}, itemByKey = {};
  let skippedItems = 0, mergedItems = 0;
  for (const r of pro) {
    const code = clean(r.CODE);
    let name = clean(r.PRODUCT) || clean(r.BILLNAME);
    if (!code || !name || clean(r.NAME).startsWith('#') || /^product name\b/i.test(name)) { skippedItems++; continue; }
    const pack = packFromName(name) || Math.max(1, int(r.PACK) || 1);
    let k = key(name);
    if (itemByKey[k] && itemByKey[k].pcs_per_box !== pack && clean(r.PACKING)) { name = `${name} ${clean(r.PACKING)}`; k = key(name); }
    if (itemByKey[k]) {
      const ex = itemByKey[k];
      // the same item under a second Marg code: its real sale rate beats the first code's list rate
      if (ex.rateFromList && saleRate[code]) { ex.retail_price = ex.wholesale_price = saleRate[code].rate; ex.rateFromList = false; }
      itemByCode[code] = ex; mergedItems++; continue;
    }
    const com = commodity[clean(r.GCODE6)] || {};
    const gst = clean(r.TAXL) === 'E' ? 0 : (com.gst || num(r.IGST) || 0);
    const sr = saleRate[code];
    const rateA = num(r.RATEA) > 0 ? r8(num(r.RATEA) / (1 + gst / 100) / rateUnit(num(r.RATEA) / (1 + gst / 100), [int(r.PACK), pack], num(r.LPRATE), [...(linePacks[code] || [])].sort((a, b) => a - b))) : 0;
    const it = {
      code, name, pcs_per_box: pack, gst_rate: gst, hsn: com.hsn || null, mrp: mrpFromName(name) || (batchMrp[code] ? batchMrp[code].mrp : 0),
      category: pinned(name) || byRules(name) || byRules(cleanQuery(name)) || company[clean(r.GCODE)] || null,
      purchase_price: purchaseRate(num(r.LPRATE), sr ? sr.rate : rateA, [packCount[code] ? +usualPack(code)[0] : 0, int(r.PACK)]), retail_price: sr ? sr.rate : rateA, wholesale_price: sr ? sr.rate : rateA,
      opening: int(r.OPENING), closing: int(r.BALANCE), moved: 0, rateFromList: !sr,
    };
    byNameMrp(it, [pack, packCount[code] ? +usualPack(code)[0] : 0, int(r.PACK)]);
    items.push(it); itemByCode[code] = it; itemByKey[k] = it;
  }
  if (skippedItems) cleaning.push(`${skippedItems} placeholder item rows skipped (###…, "PRODUCT NAME").`);
  if (mergedItems) cleaning.push(`${mergedItems} duplicate item names merged into one item each.`);
  const noMrp = items.filter((i) => !i.mrp).length;
  if (noMrp) cleaning.push(`${noMrp} items have no MRP in their name or on their bill rows; set it later with Stock › Auto-fill missing MRPs or by editing the item.`);

  // ---- parties (customers = sundry debtors, suppliers = sundry creditors)
  const parties = [], partyByCode = {}, partyByKey = {};
  let badGstin = 0, mergedParties = 0, cityCut = 0;
  for (const r of order) {
    const group = clean(r.SCODE);
    const kind = group.startsWith('C6') ? 'CUSTOMER' : group.startsWith('D3') ? 'SUPPLIER' : null;
    if (!kind) continue;
    const parts = String(r.PARNAM || '').split(/\s{3,}/).map(clean).filter(Boolean);
    let name = parts[0] || '';
    if (!name) continue;
    const town = clean(r.CITY);
    if (parts.length > 1) cityCut++;
    else if (town && name.length > town.length + 3 && name.toLowerCase().endsWith(' ' + town.toLowerCase())) { name = clean(name.slice(0, name.length - town.length)); cityCut++; }
    const k = kind + '|' + key(name);
    const code = clean(r.ORDNO);
    if (partyByKey[k]) { partyByCode[code] = partyByKey[k]; mergedParties++; continue; }
    let gstin = clean(r.GSTNO).toUpperCase().replace(/\s/g, '');
    if (gstin && !GSTIN_RE.test(gstin)) { badGstin++; gstin = ''; }
    const pan = clean(r.ITNO).toUpperCase();
    const city = clean(r.CITY);
    const addr = [r.PARADD, r.PARADD1, r.PARADD2].map(clean).filter((x) => x && !/aadhaa?r/i.test(x));
    if (city && !addr.some((a) => a.toLowerCase().includes(city.toLowerCase()))) addr.push(city);
    const pin = clean(r.DSM);
    if (/^\d{6}$/.test(pin) && !addr.some((a) => a.includes(pin))) addr.push(pin);
    const mobiles = [], land = [];
    for (const f of ['PHONE1', 'PHONE2', 'PHONE3', 'PHONE4']) {
      for (const piece of String(r[f] || '').split(/[,;\/]/)) {
        const d = piece.replace(/\D/g, '');
        if (d.length < 6) continue;
        const m = mobileOf(d);
        if (m) { if (!mobiles.includes(m)) mobiles.push(m); } else if (!land.includes(clean(piece))) land.push(clean(piece));
      }
    }
    const p = {
      code, kind, name, gstin: gstin || null, state_code: gstin ? gstin.slice(0, 2) : null, pan: PAN_RE.test(pan) ? pan : (gstin ? gstin.slice(2, 12) : null),
      address: addr.join(', ') || null, phone: mobiles[0] || land[0] || null, mobiles: mobiles.slice(1).join(', ') || null, tel: land.join(', ') || null,
      opening: r2(num(r.OPNING)), closing: r2(num(r.BALANCE)), moved: 0,
    };
    parties.push(p); partyByCode[code] = p; partyByKey[k] = p;
  }
  if (cityCut) cleaning.push(`${cityCut} party names had the town padded onto the name; the town was moved to the address.`);
  if (badGstin) cleaning.push(`${badGstin} invalid GSTINs dropped.`);
  if (mergedParties) cleaning.push(`${mergedParties} duplicate party names merged.`);

  // ---- bills
  const lines = {};
  // rows belong to their bill by Marg's voucher serial (a purchase row's VCN holds the supplier's bill number instead)
  for (const l of dis) (lines[clean(l.VOUCHER) + '|' + clean(l.CODEP)] ||= []).push(l);
  const docs = [];
  const bad = [];
  const skip = { other: 0, noParty: 0 };
  for (const h of mdis) {
    const type = clean(h.TYPE);
    const kind = type === 'S' ? 'SALE' : type === 'P' ? 'PURCHASE' : type === 'Q' ? 'DEBIT_NOTE' : null;
    if (!kind) { skip.other++; continue; }
    const no = clean(h.VCN), date = day(h.DATE);
    const party = partyByCode[clean(h.CODEP)];
    if (!no || !date) { skip.other++; continue; }
    if (!party || (kind === 'SALE') !== (party.kind === 'CUSTOMER')) { skip.noParty++; note(warnings, `${no}: its party (Marg code ${clean(h.CODEP)}) is not a ${kind === 'SALE' ? 'customer' : 'supplier'}; bill skipped.`); continue; }
    const flag = type === 'S' ? 'G' : type;
    const rows = [];
    for (const l of lines[clean(h.VOUCHER) + '|' + clean(h.CODEP)] || []) {
      if (clean(l.FLG) !== flag) continue;
      const it = itemByCode[clean(l.CODE)];
      if (!it) { note(warnings, `${no}: item code ${clean(l.CODE)} is not in the item list; that row is left out.`); continue; }
      const pcs = int(l.QTY), free = int(l.FREE), pack = Math.max(1, int(l.PACK) || it.pcs_per_box);
      const taxable = r2(num(l.AMMMOUNT)), disc = r2(num(l.SDISCOUNT)), tax = r2(num(l.SSTAAMO)), cg = r2(num(l.CGSTAMO));
      rows.push({
        item: it, qty: pcs, free, taxable, disc_amt: disc, disc_pct: num(l.DISC1), gross: r2(taxable + disc),
        rate: pcs > 0 ? r8(num(l.SFRATE) / pack) : 0, gst_rate: num(l.CGST) > 0 ? num(l.CGST) * 2 : (tax > 0 ? it.gst_rate : 0),
        cgst: cg > 0 ? cg : 0, sgst: cg > 0 ? r2(tax - cg) : 0, igst: cg > 0 ? 0 : tax, amount: r2(taxable + tax),
        stock: kind !== 'DEBIT_NOTE' && clean(l.GODWON) !== 'Y', challan: clean(l.CHALLAN),
      });
    }
    const taxAmt = r2(num(h.TAXAMO)), cg = r2(num(h.CGSTAMO));
    const d = {
      kind, no, date, party, rows, ref: kind === 'PURCHASE' ? clean(h.PM) || null : kind === 'DEBIT_NOTE' ? (rows.find((x) => x.challan) || {}).challan || null : null,
      subtotal: r2(rows.reduce((a, x) => a + x.gross, 0)), discount: r2(rows.reduce((a, x) => a + x.disc_amt, 0)), taxable: r2(num(h.AMOUNTT)),
      cgst: cg > 0 ? cg : 0, sgst: cg > 0 ? r2(taxAmt - cg) : 0, igst: cg > 0 ? 0 : taxAmt, round_off: r2(num(h.ROUND)), total: r2(num(h.FINAL)),
    };
    if (Math.abs(r2(d.taxable + taxAmt + d.round_off) - d.total) > 0.05) bad.push(`${no}: taxable + GST + round off = ${r2(d.taxable + taxAmt + d.round_off)}, Marg total ${d.total}`);
    else if (Math.abs(r2(rows.reduce((a, x) => a + x.taxable, 0)) - d.taxable) > 0.5) bad.push(`${no}: rows add up to ${r2(rows.reduce((a, x) => a + x.taxable, 0))}, Marg taxable ${d.taxable}`);
    if (!rows.length) { note(warnings, `${no}: no item rows; skipped.`); continue; }
    docs.push(d);
  }
  if (skip.other) cleaning.push(`${skip.other} other Marg vouchers (not sales, purchases or debit notes) left out.`);

  // ---- money received / paid
  const money = [];
  for (const r of gl) {
    const book = clean(r.BOOK);
    if (book !== 'R' && book !== 'P') continue;
    const p = partyByCode[clean(r.CODE)];
    if (!p) continue;
    const amt = r2(book === 'R' ? num(r.CREDIT) - num(r.DEBIT) : num(r.DEBIT) - num(r.CREDIT));
    const date = day(r.DATE);
    if (!(amt > 0) || !date) continue;
    const ref = clean(r.REMARK1);
    const mode = /neft|rtgs|imps|bank|transfer/i.test(ref) ? 'BANK' : /upi|gpay|phonepe|paytm/i.test(ref) ? 'UPI' : /che?q/i.test(ref) ? 'CHEQUE' : 'CASH';
    money.push({ kind: book === 'R' ? 'RECEIPT' : 'PAYMENT', no: `${book === 'R' ? 'MR' : 'MP'}/${clean(r.VOUCHER)}`, date, party: p, amount: amt, mode, ref: ref || null });
  }

  // Marg's own built-in accounts (codes STA…, e.g. GENERAL LEDGER) sit in the debtors group; unused and empty ones are left out
  const used = new Set([...docs.map((d) => d.party), ...money.map((v) => v.party)]);
  const builtIn = parties.filter((p) => p.code.startsWith('STA') && p.opening === 0 && p.closing === 0 && !used.has(p));
  if (builtIn.length) {
    cleaning.push(`${builtIn.length} empty Marg system accounts left out (${builtIn.slice(0, 3).map((p) => p.name).join(', ')}${builtIn.length > 3 ? ', …' : ''}).`);
    for (const p of builtIn) parties.splice(parties.indexOf(p), 1);
  }

  // ---- checks against Marg's own closing figures
  for (const d of docs) {
    d.party.moved += d.kind === 'PURCHASE' ? -d.total : d.total;
    for (const x of d.rows) if (x.stock) x.item.moved += (d.kind === 'SALE' ? -1 : 1) * (x.qty + x.free);
  }
  for (const m of money) m.party.moved += m.kind === 'RECEIPT' ? -m.amount : m.amount;
  const partyOff = parties.filter((p) => Math.abs(r2(p.opening + p.moved) - p.closing) > 0.05)
    .map((p) => `${p.name}: opening ${p.opening} + bills and payments = ${r2(p.opening + p.moved)}, Marg closing ${p.closing}`);
  const stockOff = items.filter((i) => i.opening + i.moved !== i.closing)
    .map((i) => `${i.name}: opening ${i.opening} + purchases − sales = ${i.opening + i.moved}, Marg closing ${i.closing}`);
  const negative = items.filter((i) => i.opening + i.moved < 0).length;
  if (negative) note(warnings, `${negative} items have negative stock in Marg (sold more than was entered as bought); they come in negative so the totals still match.`);

  const dates = docs.map((d) => d.date).sort();
  const sum = (k) => r2(docs.filter((d) => d.kind === k).reduce((a, d) => a + d.total, 0));
  const msum = (k) => r2(money.filter((m) => m.kind === k).reduce((a, m) => a + m.amount, 0));
  const count = (k) => docs.filter((d) => d.kind === k).length;
  const summary = {
    period: dates.length ? { from: dates[0], to: dates[dates.length - 1] } : null,
    found: { items: items.length, customers: parties.filter((p) => p.kind === 'CUSTOMER').length, suppliers: parties.filter((p) => p.kind === 'SUPPLIER').length,
      sales: count('SALE'), purchases: count('PURCHASE'), debit_notes: count('DEBIT_NOTE'), receipts: money.filter((m) => m.kind === 'RECEIPT').length, payments: money.filter((m) => m.kind === 'PAYMENT').length },
    totals: { sales: sum('SALE'), purchases: sum('PURCHASE'), debit_notes: sum('DEBIT_NOTE'), receipts: msum('RECEIPT'), payments: msum('PAYMENT'),
      opening_receivable: r2(parties.reduce((a, p) => a + (p.opening > 0 ? p.opening : 0), 0)), opening_payable: r2(parties.reduce((a, p) => a + (p.opening < 0 ? -p.opening : 0), 0)) },
    checks: {
      bills: { checked: docs.length, ok: docs.length - bad.length, problems: bad },
      party_balances: { checked: parties.length, ok: parties.length - partyOff.length, problems: partyOff },
      stock: { checked: items.length, ok: items.length - stockOff.length, problems: stockOff },
    },
    cleaning, warnings,
  };
  return { items, parties, docs, money, summary };
}

// ------------------------------------------------------------------ writing into the open company
function write(m) {
  const added = { items: 0, categories: 0, customers: 0, suppliers: 0, sales: 0, purchases: 0, debit_notes: 0, receipts: 0, payments: 0 };
  const existing = { items: 0, parties: 0, bills: 0, vouchers: 0 };
  const catId = (name) => {
    if (!name) return null;
    const row = db.prepare('SELECT id FROM categories WHERE lower(name)=lower(?)').get(name);
    if (row) return row.id;
    added.categories++;
    return Number(db.prepare('INSERT INTO categories(name) VALUES(?)').run(name).lastInsertRowid);
  };
  const opening = m.summary.period ? m.summary.period.from : null;
  // items and their MARG batch
  for (const it of m.items) {
    const have = db.prepare('SELECT id FROM items WHERE lower(name)=lower(?)').get(it.name);
    if (have) { it.id = have.id; it.isNew = false; existing.items++; } else {
      it.id = Number(db.prepare(`INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box) VALUES(?,?,?,?,?,?,?,?,?,?)`)
        .run(it.name, catId(it.category), it.hsn, it.gst_rate, 'PCS', it.mrp, it.retail_price, it.wholesale_price, it.purchase_price, it.pcs_per_box).lastInsertRowid);
      it.isNew = true; added.items++;
    }
    let b = db.prepare("SELECT id FROM batches WHERE item_id=? AND batch_no='MARG'").get(it.id);
    if (!b) b = { id: Number(db.prepare("INSERT INTO batches(item_id,batch_no,exp_date,qty,purchase_price,mrp) VALUES(?,'MARG',?,?,?,?)")
      .run(it.id, NO_EXPIRY, it.isNew ? it.opening : 0, it.purchase_price, it.mrp || null).lastInsertRowid) };
    it.batch = b.id;
  }
  // parties with their opening balance
  const lg = db.prepare('INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)');
  for (const p of m.parties) {
    const have = db.prepare(`SELECT id FROM parties WHERE lower(name)=lower(?) AND ${p.kind === 'SUPPLIER' ? "type='SUPPLIER'" : "type<>'SUPPLIER'"}`).get(p.name);
    if (have) { p.id = have.id; existing.parties++; continue; }
    p.id = Number(db.prepare(`INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,pan,type,price_tier) VALUES(?,?,?,?,?,?,?,?,?,?)`)
      .run(p.name, p.gstin, p.state_code, p.phone, p.tel, p.mobiles, p.address, p.pan, p.kind === 'SUPPLIER' ? 'SUPPLIER' : 'RETAILER', 'RETAIL').lastInsertRowid);
    added[p.kind === 'SUPPLIER' ? 'suppliers' : 'customers']++;
    if (p.opening !== 0 && opening) lg.run(p.id, opening, 'OPENING', 'OPENING', p.opening > 0 ? p.opening : 0, p.opening < 0 ? -p.opening : 0, 'Opening balance (Marg)');
  }
  const move = db.prepare('UPDATE batches SET qty = qty + ? WHERE id = ?');
  for (const d of m.docs) {
    if (d.kind === 'SALE') {
      if (db.prepare('SELECT 1 FROM invoices WHERE invoice_no=?').get(d.no)) { existing.bills++; continue; }
      const id = Number(db.prepare(`INSERT INTO invoices(invoice_no,date,party_id,sale_type,pay_mode,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,0)`)
        .run(d.no, d.date, d.party.id, 'COUNTER', 'CREDIT', d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total).lastInsertRowid);
      for (const x of d.rows) {
        db.prepare(`INSERT INTO invoice_lines(invoice_id,item_id,batch_id,qty,free_qty,rate,disc_pct,disc_amt,taxable,gst_rate,cgst,sgst,igst,amount,manual_disc) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
          .run(id, x.item.id, x.item.batch, x.qty, x.free, x.rate, x.disc_pct, x.disc_amt, x.taxable, x.gst_rate, x.cgst, x.sgst, x.igst, x.amount, x.disc_pct);
        if (x.stock) move.run(-(x.qty + x.free), x.item.batch);
      }
      lg.run(d.party.id, d.date, 'INVOICE', d.no, d.total, 0, `Sale ${d.no}`);
      added.sales++;
    } else if (d.kind === 'PURCHASE') {
      if (db.prepare('SELECT 1 FROM purchases WHERE purchase_no=?').get(d.no)) { existing.bills++; continue; }
      const id = Number(db.prepare(`INSERT INTO purchases(purchase_no,supplier_invoice_no,date,party_id,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,source) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,0,'MARG')`)
        .run(d.no, d.ref, d.date, d.party.id, d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total).lastInsertRowid);
      for (const x of d.rows) {
        db.prepare(`INSERT INTO purchase_lines(purchase_id,item_id,batch_id,batch_no,exp_date,qty,free_qty,rate,disc_pct,disc_amt,mrp,taxable,gst_rate,cgst,sgst,igst,amount,unit,pcs_qty) VALUES(?,?,?,'MARG',?,?,?,?,?,?,?,?,?,?,?,?,?,'PCS',?)`)
          .run(id, x.item.id, x.item.batch, NO_EXPIRY, x.qty, x.free, x.qty > 0 ? r8(x.gross / x.qty) : 0, x.disc_pct, x.disc_amt, x.item.mrp || null, x.taxable, x.gst_rate, x.cgst, x.sgst, x.igst, x.gross, x.qty + x.free);
        if (x.stock) move.run(x.qty + x.free, x.item.batch);
      }
      lg.run(d.party.id, d.date, 'PURCHASE', d.no, 0, d.total, `Purchase ${d.no}${d.ref ? ' / ' + d.ref : ''}`);
      added.purchases++;
    } else {
      if (db.prepare('SELECT 1 FROM debit_notes WHERE note_no=?').get(d.no)) { existing.bills++; continue; }
      const id = Number(db.prepare(`INSERT INTO debit_notes(note_no,date,party_id,against_bill,reason,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,source) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'MARG')`)
        .run(d.no, d.date, d.party.id, d.ref, 'From Marg', d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total).lastInsertRowid);
      for (const x of d.rows) {
        db.prepare(`INSERT INTO debit_note_lines(note_id,item_id,batch_id,qty,unit,pcs_qty,rate,amount,taxable,gst_rate,cgst,sgst,igst) VALUES(?,?,NULL,?,'PCS',?,?,?,?,?,?,?,?)`)
          .run(id, x.item.id, x.qty, x.qty, x.qty > 0 ? r8(x.gross / x.qty) : 0, x.gross, x.taxable, x.gst_rate, x.cgst, x.sgst, x.igst);
      }
      lg.run(d.party.id, d.date, 'DEBIT_NOTE', d.no, d.total, 0, `Debit note ${d.no}${d.ref ? ' against ' + d.ref : ''}`);
      added.debit_notes++;
    }
  }
  for (const v of m.money) {
    if (v.kind === 'RECEIPT') {
      if (db.prepare('SELECT 1 FROM receipts WHERE receipt_no=?').get(v.no)) { existing.vouchers++; continue; }
      db.prepare('INSERT INTO receipts(receipt_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)').run(v.no, v.date, v.party.id, v.mode, v.amount, v.ref);
      lg.run(v.party.id, v.date, 'RECEIPT', v.no, 0, v.amount, `Payment received (${v.mode})${v.ref ? ' ' + v.ref : ''}`);
      added.receipts++;
    } else {
      if (db.prepare('SELECT 1 FROM payments WHERE voucher_no=?').get(v.no)) { existing.vouchers++; continue; }
      db.prepare('INSERT INTO payments(voucher_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)').run(v.no, v.date, v.party.id, v.mode, v.amount, v.ref);
      lg.run(v.party.id, v.date, 'PAYMENT', v.no, v.amount, 0, `Payment made (${v.mode})${v.ref ? ' ' + v.ref : ''}`);
      added.payments++;
    }
  }
  return { added, existing };
}

class Preview extends Error {}

/** What the backup holds, the checks, and what importing would add, without changing anything. */
/** One year's books take only that year's Marg data. */
function checkYear(m) {
  const own = require('../utils/fy').booksFy();
  const per = m.summary.period;
  if (!own || !per) return;
  const fy = fyRange(own);
  if (per.from < fy.from || per.to > fy.to) {
    const theirs = fyRange(String(Number(per.from.slice(0, 4)) - (Number(per.from.slice(5, 7)) < 4 ? 1 : 0))).label;
    throw new HttpError(400, `This Marg data is for ${theirs} (${per.from} to ${per.to}), but these are the ${own} books. Open or add the ${theirs} books first (Settings › Companies).`, 'WRONG_YEAR');
  }
}

function previewMarg(p) {
  const m = model(readSource(p));
  checkYear(m);
  let out;
  try { db.transaction(() => { out = write(m); throw new Preview(); })(); } catch (e) { if (!(e instanceof Preview)) throw e; }
  return { ...m.summary, would_add: out.added, already_here: out.existing };
}

/**
 * (Older versions; imports now use followLast in utils/misc.js, which every series follows.)
 * After a Marg import, new bills carry on Marg's own numbering — A000423 after A000422, P000015, DNB00003 — unless the
 * numbering was already chosen in Settings (then that is kept). The prefix and digit count are read from the last bill.
 */
function followMarg(m) {
  const get = (k) => { const r = db.prepare('SELECT value FROM settings WHERE key=?').get(k); return r && r.value !== null ? String(r.value) : ''; };
  const set = db.prepare('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value');
  const out = {};
  if (get('num_fy') !== '') return out;
  for (const [kind, s] of [['SALE', 'INV'], ['PURCHASE', 'PUR'], ['DEBIT_NOTE', 'DN']]) {
    if (get(`num_${s}_prefix`) !== '') continue;
    let best = null;
    for (const d of m.docs) {
      if (d.kind !== kind) continue;
      const x = /^(.*?[^0-9])([0-9]+)$/.exec(d.no);
      if (x && (!best || parseInt(x[2], 10) > parseInt(best[2], 10))) best = x;
    }
    if (!best || !best[1].trim()) continue;
    set.run(`num_${s}_prefix`, best[1]);
    set.run(`num_${s}_digits`, String(Math.min(9, best[2].length)));
    out[s] = best[1];
  }
  if (Object.keys(out).length) set.run('num_fy', '0');
  for (const s of Object.keys(out)) out[s] = peekNo(s).next_no;
  return out;
}

function importMarg(p) {
  const m = model(readSource(p));
  checkYear(m);
  let numbering = {};
  const out = db.transaction(() => { const w = write(m); numbering = followLast(); return w; })();
  return { ...m.summary, added: out.added, already_here: out.existing, numbering };
}

/**
 * Settings › Import from Marg › Correct item prices: reads the Marg backup again and puts right the sale, wholesale and
 * purchase price (and MRP) of items already here whose price is far off what Marg says (twice as much or less: a price
 * worked out per box instead of per piece by an earlier BillBox). Prices changed by hand by a little are left alone.
 * body { path, apply }: without apply it only lists what would change.
 */
function correctPrices(p, apply) {
  const m = model(readSource(p));
  const far = (have, want) => (want > 0 ? !(have > 0) || have / want >= 1.9 || want / have >= 1.9 : false);
  const items = [];
  let checked = 0;
  const run = () => {
    for (const it of m.items) {
      const h = db.prepare('SELECT id,name,retail_price,wholesale_price,purchase_price,mrp FROM items WHERE lower(name)=lower(?)').get(it.name);
      if (!h) continue;
      checked++;
      const want = { retail_price: r8(it.retail_price), wholesale_price: r8(it.wholesale_price), purchase_price: r8(it.purchase_price), mrp: r2(it.mrp || 0) };
      const next = {};
      for (const k of Object.keys(want)) next[k] = far(Number(h[k]) || 0, want[k]) ? want[k] : Number(h[k]) || 0;
      if (Object.keys(want).every((k) => next[k] === (Number(h[k]) || 0))) continue;
      items.push({ name: h.name, retail_old: Number(h.retail_price) || 0, retail_new: next.retail_price, wholesale_old: Number(h.wholesale_price) || 0,
        wholesale_new: next.wholesale_price, purchase_old: Number(h.purchase_price) || 0, purchase_new: next.purchase_price, mrp_old: Number(h.mrp) || 0, mrp_new: next.mrp });
      if (apply) db.prepare('UPDATE items SET retail_price=?,wholesale_price=?,purchase_price=?,mrp=? WHERE id=?').run(next.retail_price, next.wholesale_price, next.purchase_price, next.mrp, h.id);
    }
  };
  if (apply) db.transaction(run)(); else run();
  return { checked, changed: items.length, applied: !!apply, items };
}

/** The cleaned books as plain tables (for checking in a spreadsheet, or keeping): items, parties, bills, bill rows, money. */
function cleanTables(p) {
  const m = model(readSource(p));
  return {
    summary: m.summary,
    items: m.items.map((i) => ({ marg_code: i.code, name: i.name, category: i.category || '', hsn: i.hsn || '', gst_rate: i.gst_rate, pcs_per_box: i.pcs_per_box, mrp: i.mrp || '',
      purchase_price: i.purchase_price, sale_price: i.retail_price, opening_stock_pcs: i.opening, closing_stock_pcs: i.closing })),
    parties: m.parties.map((x) => ({ marg_code: x.code, type: x.kind, name: x.name, address: x.address || '', gstin: x.gstin || '', state_code: x.state_code || '', pan: x.pan || '',
      phone: x.phone || '', mobiles: x.mobiles || '', tel: x.tel || '', opening_balance: x.opening, closing_balance: x.closing })),
    bills: m.docs.map((d) => ({ type: d.kind, no: d.no, date: d.date, party: d.party.name, ref: d.ref || '', rows: d.rows.length, subtotal: d.subtotal, discount: d.discount,
      taxable: d.taxable, cgst: d.cgst, sgst: d.sgst, igst: d.igst, round_off: d.round_off, total: d.total })),
    bill_rows: m.docs.flatMap((d) => d.rows.map((x) => ({ type: d.kind, no: d.no, date: d.date, item: x.item.name, qty_pcs: x.qty, free_pcs: x.free, rate_per_pc: x.rate,
      disc_pct: x.disc_pct, disc_amt: x.disc_amt, taxable: x.taxable, gst_rate: x.gst_rate, cgst: x.cgst, sgst: x.sgst, igst: x.igst, amount: x.amount }))),
    money: m.money.map((v) => ({ type: v.kind, no: v.no, date: v.date, party: v.party.name, mode: v.mode, amount: v.amount, reference: v.ref || '' })),
  };
}

module.exports = { previewMarg, importMarg, cleanTables, parseCsv, readZip, correctPrices };
