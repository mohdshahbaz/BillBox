const db = require('../db');
const { HttpError } = require('../utils/misc');
const { r2 } = require('../utils/gst');
const { settings } = require('./billing');

/**
 * E-way bill for one sale bill, as the JSON file the government portal (ewaybillgst.gov.in › Generate Bulk) takes:
 * NIC's bulk format, version 1.0.0621. BillBox fills Part A from the bill (both parties, items with HSN, values and
 * tax) and Part B from the transport details typed (vehicle or transporter, distance). The portal checks it and
 * returns the 12-digit e-way bill number, which is saved on the bill and printed on it.
 * Plain character work (no regex) so the Swift engine gives exactly the same answers.
 */
const MODES = { 1: 'Road', 2: 'Rail', 3: 'Air', 4: 'Ship' };
const isDigit = (c) => c >= '0' && c <= '9';
const isAlnum = (c) => isDigit(c) || (c >= 'A' && c <= 'Z');
const trim = (v) => (v === undefined || v === null ? '' : String(v).trim());

/** The last 6-digit number in an address that does not start with 0 (the PIN code), or ''. */
function pinFrom(address) {
  const s = trim(address);
  let found = '';
  let i = 0;
  while (i < s.length) {
    if (isDigit(s[i])) {
      let j = i;
      while (j < s.length && isDigit(s[j])) j++;
      if (j - i === 6 && s[i] !== '0') found = s.slice(i, j);
      i = j;
    } else i++;
  }
  return found;
}

/** Address split for the portal: two lines of at most 120 characters, and the place (last part that is not the PIN). */
function addressParts(address) {
  const flat = trim(address).split('\r').join(' ').split('\n').join(', ');
  const parts = flat.split(',').map((x) => x.trim()).filter((x) => x.length);
  let place = '';
  for (let k = parts.length - 1; k >= 0 && !place; k--) {
    let letters = '';
    for (const c of parts[k]) if (!isDigit(c) && c !== '-') letters += c;
    letters = letters.trim();
    if (letters.length >= 2) place = letters;
  }
  const one = parts.join(', ');
  return { addr1: one.slice(0, 120), addr2: one.slice(120, 240), place: place.slice(0, 50) };
}

const dmy = (iso) => (iso && iso.length >= 10 ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : '');
const upperNoSpace = (v) => { let o = ''; for (const c of trim(v).toUpperCase()) if (c !== ' ' && c !== '-' && c !== '.') o += c; return o; };
const isPin = (p) => p.length === 6 && p[0] !== '0' && [...p].every(isDigit);
const isIsoDate = (d) => d.length === 10 && d[4] === '-' && d[7] === '-' && [...(d.slice(0, 4) + d.slice(5, 7) + d.slice(8))].every(isDigit);

function loadBill(id) {
  const inv = db.prepare(`SELECT i.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state
    FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE i.id=?`).get(Number(id));
  if (!inv) throw new HttpError(404, 'Bill not found');
  return inv;
}

/** Saved transport details of the bill, or a first guess (PIN codes read from the two addresses). */
function details(id) {
  const inv = loadBill(id);
  const co = settings();
  let saved = {};
  try { saved = inv.ewb_transport ? JSON.parse(inv.ewb_transport) : {}; } catch (_) { saved = {}; }
  return {
    bill_id: inv.id, invoice_no: inv.invoice_no, date: inv.date, total: inv.total, party: inv.party_name || null,
    needed: inv.total >= 50000,
    from_pincode: saved.from_pincode || trim(co.company_pincode) || pinFrom(co.company_address),
    to_pincode: saved.to_pincode || pinFrom(inv.party_address),
    distance: saved.distance !== undefined ? saved.distance : null,
    mode: Number(saved.mode) || 1, vehicle_no: saved.vehicle_no || '', vehicle_type: saved.vehicle_type || 'R',
    transporter_id: saved.transporter_id || '', transporter_name: saved.transporter_name || '',
    trans_doc_no: saved.trans_doc_no || '', trans_doc_date: saved.trans_doc_date || '',
    ewb_no: inv.ewb_no || null, ewb_date: inv.ewb_date || null, ewb_valid: inv.ewb_valid || null,
  };
}

/** Checks the transport details, saves them on the bill and builds the portal's JSON. */
function build(id, b) {
  b = b || {};
  const inv = loadBill(id);
  const co = settings();
  if (!inv.party_id) throw new HttpError(400, 'Choose the customer on this bill first: an e-way bill needs the buyer’s name and address.');
  const fromGstin = upperNoSpace(co.company_gstin);
  if (fromGstin.length !== 15) throw new HttpError(400, 'Add your GSTIN in Settings › Companies to make an e-way bill.');
  let last = {};
  try { last = inv.ewb_transport ? JSON.parse(inv.ewb_transport) : {}; } catch (_) { last = {}; }
  const fromPin = trim(b.from_pincode) || trim(last.from_pincode) || trim(co.company_pincode) || pinFrom(co.company_address);
  if (!isPin(fromPin)) throw new HttpError(400, 'Your PIN code is needed (6 digits): type it here or add it to your address in Settings › Companies.');
  const toPin = trim(b.to_pincode) || trim(last.to_pincode) || pinFrom(inv.party_address);
  if (!isPin(toPin)) throw new HttpError(400, `The PIN code of ${inv.party_name} is needed (6 digits): type it here or add it to the party’s address.`);
  const dist = trim(b.distance) === '' ? NaN : Number(b.distance);
  if (!Number.isInteger(dist) || dist < 0 || dist > 4000) throw new HttpError(400, 'Distance must be a whole number of km from 0 to 4000 (0 lets the portal work it out from the PIN codes).');
  const modeText = trim(b.mode).toLowerCase();
  const mode = ['1', '2', '3', '4'].includes(modeText) ? Number(modeText) : (['road', 'rail', 'air', 'ship'].indexOf(modeText) + 1 || (modeText ? 0 : 1));
  if (!mode) throw new HttpError(400, 'Mode must be road, rail, air or ship');
  const vehicle = upperNoSpace(b.vehicle_no);
  if (vehicle && (vehicle.length < 6 || vehicle.length > 15 || ![...vehicle].every(isAlnum))) throw new HttpError(400, `Vehicle number "${trim(b.vehicle_no)}" does not look right (e.g. UP20AB1234)`);
  const transId = upperNoSpace(b.transporter_id);
  if (transId && (transId.length !== 15 || ![...transId].every(isAlnum))) throw new HttpError(400, 'Transporter ID is the transporter’s 15-character GSTIN or TRANSIN');
  const docNo = trim(b.trans_doc_no).slice(0, 15), docDate = trim(b.trans_doc_date);
  if (docDate && !isIsoDate(docDate)) throw new HttpError(400, 'Transport document date must be YYYY-MM-DD');
  if (mode === 1 && !vehicle && !transId) throw new HttpError(400, 'Enter the vehicle number, or the transporter ID if the transporter will add the vehicle later.');
  if (mode !== 1 && !docNo) throw new HttpError(400, `For ${MODES[mode].toLowerCase()} transport enter the RR / airway bill / bill of lading number.`);
  const vType = trim(b.vehicle_type).toUpperCase() === 'O' ? 'O' : 'R';

  const lines = db.prepare(`SELECT l.item_id, it.name, it.hsn, l.qty, l.free_qty, l.taxable, l.gst_rate, l.cgst, l.sgst, l.igst
    FROM invoice_lines l JOIN items it ON it.id=l.item_id WHERE l.invoice_id=? ORDER BY l.id`).all(inv.id);
  const noHsn = [];
  const byItem = [];
  for (const l of lines) {
    const hsn = trim(l.hsn);
    if (!hsn || ![...hsn].every(isDigit)) { if (!noHsn.includes(l.name)) noHsn.push(l.name); continue; }
    let g = byItem.find((x) => x.item_id === l.item_id && x.gst_rate === l.gst_rate);
    if (!g) { g = { item_id: l.item_id, name: l.name, hsn, gst_rate: l.gst_rate, qty: 0, taxable: 0 }; byItem.push(g); }
    g.qty += l.qty + l.free_qty;
    g.taxable = r2(g.taxable + l.taxable);
  }
  if (noHsn.length) throw new HttpError(400, `Add the HSN code (Stock › edit item) for: ${noHsn.slice(0, 5).join(', ')}${noHsn.length > 5 ? ` and ${noHsn.length - 5} more` : ''}`);
  const intra = !(inv.igst > 0);
  let main = byItem[0];
  for (const g of byItem) if (g.taxable > main.taxable) main = g;
  const from = addressParts(co.company_address), to = addressParts(inv.party_address);
  const fromState = Number(trim(co.state_code) || fromGstin.slice(0, 2));
  const toGstin = upperNoSpace(inv.party_gstin);
  const toState = Number(trim(inv.party_state) || (toGstin.length === 15 ? toGstin.slice(0, 2) : '') || (intra ? fromState : 0));
  const docNoBill = inv.invoice_no.length > 16 ? inv.invoice_no.slice(inv.invoice_no.length - 16) : inv.invoice_no;
  const bill = {
    userGstin: fromGstin, supplyType: 'O', subSupplyType: 1, subSupplyDesc: '', docType: 'INV', docNo: docNoBill, docDate: dmy(inv.date), transType: 1,
    fromGstin, fromTrdName: trim(co.company_name).slice(0, 100), fromAddr1: from.addr1, fromAddr2: from.addr2, fromPlace: from.place,
    fromPincode: Number(fromPin), fromStateCode: fromState, actualFromStateCode: fromState,
    toGstin: toGstin.length === 15 ? toGstin : 'URP', toTrdName: trim(inv.party_name).slice(0, 100), toAddr1: to.addr1, toAddr2: to.addr2, toPlace: to.place,
    toPincode: Number(toPin), toStateCode: toState, actualToStateCode: toState,
    totalValue: r2(inv.taxable), cgstValue: r2(inv.cgst), sgstValue: r2(inv.sgst), igstValue: r2(inv.igst), cessValue: 0, TotNonAdvolVal: 0,
    OthValue: r2(inv.total - (inv.taxable + inv.cgst + inv.sgst + inv.igst)), totInvValue: r2(inv.total),
    transMode: mode, transDistance: String(dist), transporterName: trim(b.transporter_name).slice(0, 100), transporterId: transId,
    transDocNo: docNo, transDocDate: dmy(docDate), vehicleNo: vehicle, vehicleType: vType,
    mainHsnCode: Number(main ? main.hsn : 0),
    itemList: byItem.map((g, i) => ({
      itemNo: i + 1, productName: g.name.slice(0, 100), productDesc: g.name.slice(0, 100), hsnCode: Number(g.hsn), quantity: g.qty, qtyUnit: 'PCS',
      taxableAmount: g.taxable, sgstRate: intra ? g.gst_rate / 2 : 0, cgstRate: intra ? g.gst_rate / 2 : 0, igstRate: intra ? 0 : g.gst_rate, cessRate: 0, cessNonAdvol: 0,
    })),
  };
  const warnings = [];
  if (inv.total < 50000) warnings.push('This bill is under ₹50,000: an e-way bill is usually not needed (some states ask for one for goods moved within the state).');
  if (byItem.length > 250) warnings.push('The portal takes at most 250 items on one e-way bill.');
  if (!from.place || !to.place) warnings.push(`The portal needs the place of ${!from.place ? 'your business (Settings › Companies › address)' : `${inv.party_name} (the party’s address)`}: add it before uploading.`);
  if (inv.ewb_no) warnings.push(`This bill already has e-way bill ${inv.ewb_no}. Make a new one only if that one was cancelled.`);
  const saved = { from_pincode: fromPin, to_pincode: toPin, distance: dist, mode, vehicle_no: vehicle, vehicle_type: vType,
    transporter_id: transId, transporter_name: trim(b.transporter_name), trans_doc_no: docNo, trans_doc_date: docDate };
  if (!b.preview) db.prepare('UPDATE invoices SET ewb_transport=? WHERE id=?').run(JSON.stringify(saved), inv.id);
  let safe = '';
  for (const c of inv.invoice_no) safe += isAlnum(c.toUpperCase()) ? c : '-';
  return { file_name: `EWB_${safe}.json`, warnings, mode_name: MODES[mode], ewaybill: { version: '1.0.0621', billLists: [bill] } };
}

/** Saves (or clears) the e-way bill number the portal gave. */
function saveNumber(id, b) {
  b = b || {};
  const inv = loadBill(id);
  const no = upperNoSpace(b.ewb_no);
  if (!no) {
    db.prepare('UPDATE invoices SET ewb_no=NULL, ewb_date=NULL, ewb_valid=NULL WHERE id=?').run(inv.id);
    return { ok: true, ewb_no: null };
  }
  if (no.length !== 12 || ![...no].every(isDigit)) throw new HttpError(400, 'The e-way bill number is the 12-digit number the portal gives');
  const d = trim(b.ewb_date), v = trim(b.ewb_valid);
  if ((d && !isIsoDate(d)) || (v && !isIsoDate(v))) throw new HttpError(400, 'Dates must be YYYY-MM-DD');
  if (d && v && v < d) throw new HttpError(400, 'Valid until cannot be before the e-way bill date');
  db.prepare('UPDATE invoices SET ewb_no=?, ewb_date=?, ewb_valid=? WHERE id=?').run(no, d || inv.date, v || null, inv.id);
  return { ok: true, ewb_no: no, ewb_date: d || inv.date, ewb_valid: v || null };
}

module.exports = { details, build, saveNumber, pinFrom };
