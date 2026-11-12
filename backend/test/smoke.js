// Run with: npm test   (needs `npm install` first; uses a throwaway database in a temp folder)
const os = require('os'), fs = require('fs'), path = require('path');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'dist-test-'));
const assert = require('assert');
const db = require('../src/db');
const { buildInvoice, createInvoice, updateInvoice, deleteInvoice, getInvoice } = require('../src/services/billing');
const { createPurchase, updatePurchase, deletePurchase, previewPurchase, getPurchase } = require('../src/services/purchases');
const { recordVoucher, getVoucher, deleteLedgerEntry } = require('../src/services/vouchers');
const { buildXlsx } = require('../src/utils/xlsx');
const { parseInvoicePages, parseInvoiceText, packFromName, mrpFromName } = require('../src/services/pdfParser');
const { createMissing } = require('../src/services/autoCreate');
const R = require('../src/services/reports');
const B = require('../src/services/backup');

let n = 0;
const ok = (name, fn) => { try { fn(); n++; console.log('  ok  ', name); } catch (e) { console.log('  FAIL', name, '\n      ', e.message); process.exitCode = 1; } };
const throws = (fn, code) => { try { fn(); } catch (e) { return e.code === code || e.status === code; } return false; };

const id1 = db.firstCompanyId();
require('child_process').execFileSync(process.execPath, [path.join(__dirname, '../src/seed.js')], { env: process.env });

const NAMES = { BEV001: 'Cola 750ml', BEV003: 'Packaged Water 1L', FOD003: 'Basmati Rice 5kg', HOM001: 'Detergent Powder 1kg' };
db.withCompany(id1, () => {
  const item = (k) => db.prepare('SELECT * FROM items WHERE name=?').get(NAMES[k] || k);
  const party = (name) => db.prepare('SELECT * FROM parties WHERE name=?').get(name);
  const stock = (k) => db.prepare('SELECT COALESCE(SUM(qty),0) n FROM batches WHERE item_id=?').get(item(k).id).n;
  const bal = (id) => db.prepare('SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=?').get(id).b;

  ok('items have no sku / barcode / reorder_level columns', () => {
    const cols = db.prepare('PRAGMA table_info(items)').all().map((c) => c.name);
    for (const c of ['sku', 'barcode', 'reorder_level']) assert.ok(!cols.includes(c), c + ' still present');
    assert.ok(cols.includes('name') && cols.includes('hsn'));
  });
  ok('old items table (with sku etc.) is migrated and data kept', () => {
    const { migrateItems } = require('../src/schema');
    const Database = require('../src/sqlite');
    const t = new Database(':memory:');
    t.exec(`CREATE TABLE categories(id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE items(id INTEGER PRIMARY KEY, sku TEXT UNIQUE NOT NULL, barcode TEXT UNIQUE, name TEXT NOT NULL, category_id INTEGER, hsn TEXT, gst_rate REAL DEFAULT 18, unit TEXT DEFAULT 'PCS',
        mrp REAL DEFAULT 0, retail_price REAL DEFAULT 0, wholesale_price REAL DEFAULT 0, purchase_price REAL DEFAULT 0, reorder_level INTEGER DEFAULT 10, pcs_per_box INTEGER DEFAULT 1, active INTEGER DEFAULT 1);
      INSERT INTO items(sku,barcode,name,hsn,mrp) VALUES('A1','111','Old Item','1905',20);`);
    migrateItems(t);
    assert.ok(!t.prepare('PRAGMA table_info(items)').all().some((c) => c.name === 'sku'));
    assert.strictEqual(t.prepare('SELECT name,mrp FROM items').get().name, 'Old Item');
    t.close();
  });

  ok('dual unit: 2 boxes + 6 pcs of cola (24/box) = 54 pcs', () => {
    const r = buildInvoice({ lines: [{ item_id: item('BEV001').id, boxes: 2, pcs: 6 }] });
    assert.strictEqual(r.display[0].qty, 54);
    assert.deepStrictEqual([r.display[0].boxes, r.display[0].pcs], [2, 6]);
    assert.strictEqual(r.display[0].taxable, Math.round(54 * 29.5 * 0.95 * 100) / 100); // 12+ pcs -> 5% scheme
  });
  ok('dual unit deducts exactly 54 pcs from stock', () => {
    const before = stock('BEV001');
    createInvoice({ pay_mode: 'CASH', lines: [{ item_id: item('BEV001').id, boxes: 2, pcs: 6 }] });
    assert.strictEqual(before - stock('BEV001'), 54);
  });

  // ---- purchases (Item, HSN, Qty, Unit, Price, Amount + bill discount / CGST / SGST / round off) ----
  const sup = party('Hind Beverages Pvt Ltd');
  const line = (o = {}) => ({ item_id: item('BEV003').id, hsn: '2201', qty: 100, unit: 'PCS', rate: 12, ...o });
  ok('purchase preview: items - discount + CGST/SGST + round off = total', () => {
    const p = previewPurchase({ party_id: sup.id, discount: 100, cgst: 99, sgst: 99, round_off: -0.2, lines: [line()] });
    assert.deepStrictEqual([p.subtotal, p.taxable, p.cgst, p.sgst, p.igst, p.round_off, p.total], [1200, 1100, 99, 99, 0, -0.2, 1297.8]);
    assert.deepStrictEqual(p.lines.map((l) => l.sno), [1]);
  });
  ok('blank tax is worked out from item GST (intra-state split, inter-state IGST)', () => {
    const p = previewPurchase({ party_id: sup.id, lines: [line()] });
    assert.strictEqual(p.cgst, 108); assert.strictEqual(p.sgst, 108); assert.strictEqual(p.total, 1416);
    const q = previewPurchase({ party_id: party('Northern FMCG Agencies').id, lines: [line()] });
    assert.strictEqual(q.igst, 216); assert.strictEqual(q.cgst, 0);
  });
  ok('discount larger than items total is rejected', () => {
    assert.ok(throws(() => previewPurchase({ party_id: sup.id, discount: 5000, lines: [line()] }), 400));
  });
  let pid;
  ok('saving a purchase adds stock and credits the supplier ledger', () => {
    const before = stock('BEV003');
    pid = createPurchase({ party_id: sup.id, supplier_invoice_no: 'HB/1001', date: '2026-10-20', lines: [line()], paid_amount: 500, pay_mode: 'UPI' });
    assert.strictEqual(stock('BEV003') - before, 100);
    assert.strictEqual(getPurchase(pid).total, 1416);
    assert.strictEqual(bal(sup.id), -916);
  });
  ok('box unit converts to pieces via pcs per box', () => {
    const before = stock('BEV001');
    createPurchase({ party_id: sup.id, supplier_invoice_no: 'HB/BOX', lines: [{ item_id: item('BEV001').id, qty: 2, unit: 'BOX', rate: 600 }] });
    assert.strictEqual(stock('BEV001') - before, 48);
  });
  ok('same supplier invoice twice is blocked', () => {
    assert.ok(throws(() => createPurchase({ party_id: sup.id, supplier_invoice_no: 'hb/1001', lines: [line()] }), 'DUPLICATE'));
  });
  ok('fractional / zero quantity rejected, nothing saved', () => {
    const before = stock('BEV003');
    assert.ok(throws(() => createPurchase({ party_id: sup.id, lines: [line({ qty: 2.5 })] }), 400));
    assert.ok(throws(() => createPurchase({ party_id: sup.id, lines: [line({ qty: 0 })] }), 400));
    assert.strictEqual(stock('BEV003'), before);
  });
  ok('editing a purchase: stock and ledger are reversed and rewritten under the same number', () => {
    const before = stock('BEV003'), no = getPurchase(pid).purchase_no;
    updatePurchase(pid, { party_id: sup.id, supplier_invoice_no: 'HB/1001', date: '2026-10-20', lines: [line({ qty: 60 })], paid_amount: 0 });
    const p = getPurchase(pid);
    assert.strictEqual(p.purchase_no, no);
    assert.strictEqual(stock('BEV003') - before, -40);
    assert.strictEqual(p.total, 850.0 === p.total ? 850.0 : p.total);
    assert.ok(Math.abs(p.total - Math.round(60 * 12 * 1.18)) <= 1);
    assert.strictEqual(db.prepare("SELECT COUNT(*) n FROM ledger WHERE ref_no=?").get(no).n, 1);
  });
  ok('editing is refused when the received stock was already sold', () => {
    const id = createPurchase({ party_id: sup.id, supplier_invoice_no: 'HB/SOLD', lines: [line({ qty: 5, batch_no: 'SOLD-1' })] });
    db.prepare("UPDATE batches SET qty=0 WHERE batch_no='SOLD-1'").run();
    assert.ok(throws(() => updatePurchase(id, { party_id: sup.id, supplier_invoice_no: 'HB/SOLD', lines: [line({ qty: 1, batch_no: 'SOLD-1' })] }), 'ALREADY_SOLD'));
  });

  ok('editing a sales invoice: stock restored, new lines applied, same invoice number', () => {
    const before = stock('FOD003');
    const inv = createInvoice({ pay_mode: 'CASH', lines: [{ item_id: item('FOD003').id, qty: 4 }] });
    const id = typeof inv === 'object' ? inv.id : inv;
    const no = getInvoice(id).invoice_no;
    assert.strictEqual(before - stock('FOD003'), 4);
    updateInvoice(id, { pay_mode: 'CASH', lines: [{ item_id: item('FOD003').id, qty: 7 }] });
    assert.strictEqual(before - stock('FOD003'), 7);
    assert.strictEqual(getInvoice(id).invoice_no, no);
    updateInvoice(id, { pay_mode: 'CASH', lines: [{ item_id: item('FOD003').id, qty: 2 }] });
    assert.strictEqual(before - stock('FOD003'), 2);
  });

  ok('deleting a sales invoice puts the stock back and removes its ledger and receipt entries', () => {
    const before = stock('FOD003'), p = party('Gupta General Store'), b0 = bal(p.id);
    const inv = createInvoice({ party_id: p.id, pay_mode: 'CASH', lines: [{ item_id: item('FOD003').id, qty: 3 }] });
    const id = typeof inv === 'object' ? inv.id : inv, no = getInvoice(id).invoice_no;
    assert.strictEqual(before - stock('FOD003'), 3);
    deleteInvoice(id);
    assert.strictEqual(stock('FOD003'), before);
    assert.strictEqual(getInvoice(id), null);
    assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM ledger WHERE ref_no=?').get(no).n, 0);
    assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM receipts WHERE invoice_id=?').get(id).n, 0);
    assert.strictEqual(bal(p.id), b0);
  });
  ok('deleting a purchase bill takes its stock out again, and is refused if that stock was already sold', () => {
    const before = stock('BEV003');
    const id = createPurchase({ party_id: sup.id, supplier_invoice_no: 'HB/DEL', lines: [line({ qty: 5, batch_no: 'DEL-1' })] });
    const no = getPurchase(id).purchase_no;
    assert.strictEqual(stock('BEV003') - before, 5);
    deletePurchase(id);
    assert.strictEqual(stock('BEV003'), before);
    assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM ledger WHERE ref_no=?').get(no).n, 0);
    const id2 = createPurchase({ party_id: sup.id, supplier_invoice_no: 'HB/DEL2', lines: [line({ qty: 5, batch_no: 'DEL-2' })] });
    db.prepare("UPDATE batches SET qty=0 WHERE batch_no='DEL-2'").run();
    assert.ok(throws(() => deletePurchase(id2), 'ALREADY_SOLD'));
    assert.ok(getPurchase(id2), 'a refused delete leaves the bill in place');
  });

  ok('payment made to supplier moves the balance toward zero', () => {
    const b0 = bal(sup.id);
    const r = recordVoucher({ party_id: sup.id, direction: 'PAID', amount: 100, mode: 'CASH' });
    assert.ok(r.voucher_no.startsWith('PAY/'));
    assert.strictEqual(r.balance, Math.round((b0 + 100) * 100) / 100);
  });
  ok('a receipt can be deleted from the ledger: balance and receipts table go back', () => {
    const p = party('Gupta General Store');
    const before = bal(p.id), rc = db.prepare('SELECT COUNT(*) n FROM receipts').get().n;
    const r = recordVoucher({ party_id: p.id, direction: 'RECEIVED', amount: 250, mode: 'CASH' });
    assert.strictEqual(Math.round((before - bal(p.id)) * 100) / 100, 250);
    const line = db.prepare("SELECT id FROM ledger WHERE type='RECEIPT' AND ref_no=?").get(r.voucher_no);
    const d = deleteLedgerEntry(line.id);
    assert.strictEqual(d.ok, true);
    assert.strictEqual(Math.round(bal(p.id) * 100) / 100, Math.round(before * 100) / 100);
    assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM receipts').get().n, rc);
  });
  ok('a supplier payment can be deleted from the ledger', () => {
    const sup = db.prepare("SELECT * FROM parties WHERE type='SUPPLIER' LIMIT 1").get();
    const before = bal(sup.id), pc = db.prepare('SELECT COUNT(*) n FROM payments').get().n;
    const r = recordVoucher({ party_id: sup.id, direction: 'PAID', amount: 75, mode: 'CASH' });
    deleteLedgerEntry(db.prepare("SELECT id FROM ledger WHERE type='PAYMENT' AND ref_no=?").get(r.voucher_no).id);
    assert.strictEqual(Math.round(bal(sup.id) * 100) / 100, Math.round(before * 100) / 100);
    assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM payments').get().n, pc);
  });
  ok('a payment taken at billing, deleted from the ledger, lowers the bill\'s paid amount', () => {
    const p = party('Gupta General Store');
    const id = createInvoice({ party_id: p.id, pay_mode: 'CASH', lines: [{ item_id: item('BEV001').id, boxes: 0, pcs: 5 }] });
    const inv = db.prepare('SELECT total, paid FROM invoices WHERE id=?').get(id);
    assert.ok(inv.paid > 0);
    const line = db.prepare("SELECT l.id FROM ledger l JOIN receipts r ON r.receipt_no=l.ref_no WHERE r.invoice_id=? AND l.type='RECEIPT'").get(id);
    deleteLedgerEntry(line.id);
    assert.strictEqual(db.prepare('SELECT paid FROM invoices WHERE id=?').get(id).paid, 0);
  });
  ok('a bill\'s own ledger line cannot be deleted from the ledger', () => {
    const line = db.prepare("SELECT id FROM ledger WHERE type='INVOICE' LIMIT 1").get();
    assert.ok(throws(() => deleteLedgerEntry(line.id), 400));
    assert.ok(throws(() => deleteLedgerEntry(99999999), 404));
  });
  ok('voucher details for printing include amount in words', () => {
    const r = recordVoucher({ party_id: party('Gupta General Store').id, direction: 'RECEIVED', amount: 1000, mode: 'UPI' });
    const v = getVoucher(r.voucher_no);
    assert.strictEqual(v.title, 'Receipt Voucher');
    assert.ok(v.amount_words.startsWith('Rupees One Thousand'));
  });

  ok('GST outward report has all standard slabs and totals reconcile', () => {
    const month = new Date().toLocaleDateString('en-CA').slice(0, 7);
    createInvoice({ party_id: party('Delhi Traders').id, pay_mode: 'CREDIT', lines: [{ item_id: item('FOD003').id, qty: 4 }, { item_id: item('HOM001').id, qty: 2 }] });
    const g = R.gstOutward(month);
    assert.deepStrictEqual([0, 5, 12, 18, 28].filter((r) => !g.rows.some((x) => x.rate === r)), []);
    const inv = db.prepare('SELECT SUM(taxable) t, SUM(cgst+sgst+igst) x FROM invoices WHERE substr(date,1,7)=?').get(month);
    assert.ok(Math.abs(g.totals.taxable - inv.t) < 0.02 && Math.abs(g.totals.tax - inv.x) < 0.02);
  });
  ok('GST workbook data: B2B + B2C bills add up to the month totals', () => {
    const month = new Date().toLocaleDateString('en-CA').slice(0, 7);
    const d = R.gstOutwardDetail(month);
    assert.ok(d.b2b_bills.length >= 1 && d.b2c_bills.length >= 1);
    assert.ok(d.b2b_bills.every((b) => b.gstin) && d.b2c_bills.every((b) => !b.gstin));
    const sum = [...d.b2b_bills, ...d.b2c_bills].reduce((a, b) => a + b.taxable, 0);
    assert.ok(Math.abs(sum - d.totals.taxable) < 0.05);
  });
  ok('GST outward: the IGST column carries CGST + SGST (+ IGST), in the rate table, the totals and every bill row', () => {
    const month = new Date().toLocaleDateString('en-CA').slice(0, 7);
    const g = R.gstOutward(month), d = R.gstOutwardDetail(month);
    for (const r of g.rows) assert.ok(Math.abs(r.igst - (r.cgst + r.sgst)) < 0.02 || r.igst === r.tax, 'rate ' + r.rate);
    assert.ok(g.rows.every((r) => Math.abs(r.tax - (r.cgst + r.sgst + r.igst)) < 0.02), 'IGST is only the integrated tax; the slab tax is CGST + SGST + IGST');
    assert.ok(Math.abs(g.totals.igst - g.totals.tax) < 0.02);
    for (const b of [...d.b2b_bills, ...d.b2c_bills]) assert.ok(Math.abs(b.igst - b.tax) < 0.02);
  });
  ok('xlsx writer produces a valid zip package', () => {
    const buf = buildXlsx([{ name: 'A & B', title: 'T', cols: [{ h: 'x', k: 'x', w: 10 }, { h: 'n', k: 'n', t: 'num' }], rows: [{ x: 'a<b', n: 1.5 }], total: { n: 1.5 } }]);
    assert.strictEqual(buf.slice(0, 2).toString(), 'PK');
    fs.writeFileSync(path.join(process.env.DATA_DIR, 'test.xlsx'), buf);
  });
  ok('sales book + purchase book + all-bills', () => {
    // the same dates for both (on the 1st of a month the books' month-to-date default would leave out yesterday's bills)
    const from = '2000-01-01', to = '2100-12-31';
    const sb = R.book('sales', from, to), pb = R.book('purchase', from, to);
    assert.ok(sb.totals.count >= 2 && pb.totals.count >= 2);
    const all = R.bills({ type: 'ALL', from, to });
    assert.strictEqual(all.rows.length, sb.totals.count + pb.totals.count);
    assert.ok(R.bills({ q: 'HB/1001' }).rows.some((r) => r.type === 'PURCHASE'));
  });
  ok('dashboard fields and company low-stock threshold', () => {
    const d = R.dashboard();
    assert.strictEqual(d.series.length, 14);
    assert.ok(d.month_sales > 0 && d.month_purchases > 0 && d.gst_output > 0 && d.gst_input > 0);
    assert.ok(Array.isArray(d.low_stock) && d.low_stock_qty > 0);
  });
  ok('invoice payload for the print engine', () => {
    const inv = getInvoice(1);
    assert.ok(inv.amount_words.startsWith('Rupees') && inv.gst_summary.length >= 1 && inv.lines[0].pcs_per_box);
  });
});

ok('second company is fully isolated', () => {
  const id2 = db.createCompany({ name: 'Second Traders', state_code: '07' });
  db.withCompany(id2, () => {
    assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM items').get().n, 0);
    db.prepare("INSERT INTO items(name) VALUES('Only here')").run();
  });
  db.withCompany(id1, () => assert.strictEqual(db.prepare("SELECT COUNT(*) n FROM items WHERE name='Only here'").get().n, 0));
});

ok('backup: timestamped folder, verified copies, manifest, all kept', () => {
  const dir = path.join(process.env.DATA_DIR, 'bk');
  B.saveConfig({ dir, keep: 2, enabled: true, time: '00:00' });
  const r = B.backupNow();
  assert.ok(/FMCG_Backup_\d{8}_\d{6}(_\d+)?$/.test(r.folder));
  assert.ok(r.files.length >= 3 && r.files.every((f) => f.sha256.length === 64));
  const Database = require('../src/sqlite');
  const first = r.files.find((f) => f.company_id === id1);
  const copy = new Database(path.join(r.folder, first.file), { readonly: true });
  assert.ok(copy.prepare('SELECT COUNT(*) n FROM invoices').get().n > 0);
  copy.close();
  for (let i = 0; i < 3; i++) { fs.mkdirSync(path.join(dir, `FMCG_Backup_20200101_00000${i}`)); }
  const n0 = B.listBackups().length;
  B.backupNow();
  assert.ok(B.listBackups().length === n0 + 1, 'old backups are never deleted');
});
ok('backup scheduler runs once per day after the set time', () => {
  const first = B.tick(new Date(Date.now() + 1000));
  assert.strictEqual(first, null); // already ran today by the manual backup
});

// ---- PDF text parser: multi-page, Original vs Duplicate copies ----
const HEAD = (label) => `${label}
HIND BEVERAGES PVT LTD
Meerut Road, Meerut, Uttar Pradesh
GSTIN: 09AAACH5555D1Z5 State Code: 09
Tel: 0121-2456789 Mobile: 9810000099, 9810000077
FSSAI Lic No: 11520999000123 PAN: AAACH5555D
Email: sales@hindbev.in
TAX INVOICE
Invoice No: HB/26-27/0457 Invoice Date: 18/10/2026
Bill To: Sharma Distributors GSTIN 09ABCDE1234F1Z5
S.No Description of Goods HSN Qty Unit Rate Amount`;
const PAGE1 = (label) => `${HEAD(label)}
1 Cola 750ml 2202 240 PCS 25.00 6000.00
2 Packaged Water 1L 2201 480 PCS 12.00 5760.00
Continued...
Page 1 of 2`;
const PAGE2 = `HIND BEVERAGES PVT LTD
Meerut Road, Meerut, Uttar Pradesh
S.No Description of Goods HSN Qty Unit Rate Amount
3 Orange Juice 1L 2009 60 PCS 76.00 4560.00
Total Amount 16320.00
Discount 320.00
CGST 9% 1440.00
SGST 9% 1440.00
Rounded Off (-) 0.00
Grand Total 18880.00
Page 2 of 2`;
const PAGE2D = PAGE2.replace('Page 2 of 2', 'Page 2 of 2');
const items = db.withCompany(id1, () => db.prepare('SELECT id,name,hsn,gst_rate FROM items').all());
const parties = db.withCompany(id1, () => db.prepare("SELECT id,name,gstin FROM parties WHERE type='SUPPLIER'").all());
const ctx = { items, parties, companyGstin: '09ABCDE1234F1Z5', companyName: 'Sharma Distributors' };
const parsed = parseInvoicePages([PAGE1('ORIGINAL FOR RECIPIENT'), PAGE2, PAGE1('DUPLICATE FOR TRANSPORTER'), PAGE2D], ctx);
ok('parser: only Original pages are read, Duplicate pages skipped', () => {
  assert.deepStrictEqual(parsed.pages.used, [1, 2]);
  assert.deepStrictEqual(parsed.pages.skipped.map((x) => x.page), [3, 4]);
  assert.strictEqual(parsed.lines.length, 3);
});
ok('parser: rows continue across pages with sequential serials, no repeated headers', () => {
  assert.deepStrictEqual(parsed.lines.map((l) => l.sno), [1, 2, 3]);
  assert.deepStrictEqual(parsed.lines.map((l) => l.description), ['Cola 750ml', 'Packaged Water 1L', 'Orange Juice 1L']);
  const [a, , c] = parsed.lines;
  assert.deepStrictEqual([a.hsn, a.qty, a.unit, a.rate, a.amount], ['2202', 240, 'PCS', 25, 6000]);
  assert.deepStrictEqual([c.qty, c.rate, c.amount], [60, 76, 4560]);
  assert.ok(parsed.lines.every((l) => l.item_id));
});
ok('parser: discount, CGST, SGST, round off, grand total', () => {
  assert.deepStrictEqual([parsed.totals.discount, parsed.totals.cgst, parsed.totals.sgst, parsed.totals.grand_total], [320, 1440, 1440, 18880]);
  assert.strictEqual(parsed.totals.subtotal, 16320);
  assert.ok(!parsed.warnings.some((w) => /grand total is/.test(w)));
});
ok('parser: supplier details (name, address, GSTIN, state, tel, mobiles, FSSAI, PAN, email)', () => {
  const s = parsed.supplier;
  assert.strictEqual(s.name, 'HIND BEVERAGES PVT LTD');
  assert.ok(s.matched_party_id);
  assert.deepStrictEqual([s.gstin, s.state_code, s.tel, s.fssai, s.pan, s.email], ['09AAACH5555D1Z5', '09', '0121-2456789', '11520999000123', 'AAACH5555D', 'sales@hindbev.in']);
  assert.deepStrictEqual(s.mobiles, ['9810000099', '9810000077']);
  assert.ok(/Meerut/.test(s.address));
  assert.strictEqual(parsed.invoice_no, 'HB/26-27/0457');
  assert.strictEqual(parsed.date, '2026-10-18');
});
ok('parser: "Original Copy" label on a single page works; text input with form feeds works', () => {
  const r = parseInvoiceText(PAGE1('ORIGINAL COPY') + '\f' + PAGE2, ctx);
  assert.strictEqual(r.lines.length, 3);
});
ok('parser: parsed totals feed the purchase calculation to the printed grand total', () => {
  const sup = parties[0];
  const p = db.withCompany(id1, () => previewPurchase({
    party_id: sup.id, discount: parsed.totals.discount, cgst: parsed.totals.cgst, sgst: parsed.totals.sgst, round_off: parsed.totals.round_off,
    printed_total: parsed.totals.grand_total, lines: parsed.lines.map((l) => ({ item_id: l.item_id, hsn: l.hsn, qty: l.qty, unit: l.unit, rate: l.rate, amount: l.amount })),
  }));
  assert.strictEqual(p.total, 18880); assert.strictEqual(p.mismatch, 0);
});

// Tests on real supplier bills and the real Marg backup need the private test files (backend/test/fixtures/private,
// kept off GitHub because they hold real business data); without them those tests are skipped.
const PRIV = path.join(__dirname, 'fixtures/private');
const havePriv = fs.existsSync(path.join(PRIV, 'real_bills.js'));
let REAL, real;
if (!havePriv) console.log('  skip real supplier bills, auto-create from them and the Marg backup (private test files not present)');
if (havePriv) ({ REAL, real } = require(path.join(PRIV, 'real_bills.js'))({ ok, assert, parseInvoicePages, packFromName, mrpFromName, fs, path }));

// ---- watermarks: the big faded "SHREE ENTERPRISE" printed across the bill must never land in an item name ----
const { dropWatermarks, pageTextFromItems } = require('../src/services/pdfExtract');
ok('watermark: oversized or slanted text is dropped, normal and 90-degree text kept', () => {
  const run = (str, size, x, y, rot = 0) => { const r = (rot * Math.PI) / 180; return { str, width: str.length * size * 0.5, transform: [size * Math.cos(r), size * Math.sin(r), -size * Math.sin(r), size * Math.cos(r), x, y] }; };
  const items = [run('1 CH. SMOOTH', 8, 20, 500), run('84 PCS', 8, 200, 500), run('ENTERPRISE', 60, 90, 498), run('PAID', 9, 300, 300, 40), run('ORIGINAL', 8, 5, 400, 90), run(' ', 8, 150, 500)];
  assert.deepStrictEqual(dropWatermarks(items).map((i) => i.str), ['1 CH. SMOOTH', '84 PCS', 'ORIGINAL', ' ']);
  assert.ok(!/ENTERPRISE|PAID/.test(pageTextFromItems(items)));
});
const autoCreateTest = () => !havePriv ? Promise.resolve() : db.withCompany(id1, async () => {
  try {
    {
    const r = JSON.parse(JSON.stringify(real));
    await createMissing(r, { online: false });
    assert.ok(r.supplier.matched_party_id && r.created.supplier);
    assert.ok(r.lines.every((l) => l.item_id));
    const it = db.prepare("SELECT i.*, c.name cat FROM items i LEFT JOIN categories c ON c.id=i.category_id WHERE i.name=?").get('BIKANO CHIPS (1X144 PKT) MRP-10/-');
    assert.deepStrictEqual([it.hsn, it.gst_rate, it.pcs_per_box, it.mrp, it.cat], ['2106909', 5, 144, 10, 'Namkeen & Snacks']);
    assert.strictEqual(db.prepare("SELECT COUNT(*) n FROM items WHERE name LIKE 'BIKANO CHIPS (1X144 PKT)%'").get().n, 1); // five identical rows share one item
    const p = previewPurchase({ party_id: r.supplier.matched_party_id, discount: r.totals.discount, cgst: r.totals.cgst, sgst: r.totals.sgst, round_off: r.totals.round_off, printed_total: r.totals.grand_total,
      lines: r.lines.map((l) => ({ item_id: l.item_id, hsn: l.hsn, qty: l.qty, unit: l.unit, rate: l.rate, amount: l.amount })) });
    assert.strictEqual(p.total, 261077); assert.strictEqual(p.mismatch, 0);
    const before = db.prepare('SELECT COALESCE(SUM(qty),0) n FROM batches').get().n;
    createPurchase({ party_id: r.supplier.matched_party_id, supplier_invoice_no: r.invoice_no, date: r.date, discount: r.totals.discount, cgst: r.totals.cgst, sgst: r.totals.sgst, round_off: r.totals.round_off,
      lines: r.lines.map((l) => ({ item_id: l.item_id, hsn: l.hsn, qty: l.qty, unit: l.unit, rate: l.rate, amount: l.amount })) });
    const boxes = r.lines.reduce((a, l) => a + l.qty * l.pcs_per_box, 0);
    assert.strictEqual(db.prepare('SELECT COALESCE(SUM(qty),0) n FROM batches').get().n - before, boxes);   // 2 BOX x 144 pcs etc.
    const again = parseInvoicePages(REAL, { items: db.prepare('SELECT id,name,hsn,gst_rate FROM items').all(), parties: db.prepare("SELECT id,name,gstin FROM parties").all(), companyGstin: '' });
    assert.ok(again.lines.every((l) => l.item_id) && again.supplier.matched_party_id);   // second scan of the same bill matches everything
    }
    n++; console.log('  ok   auto-create: supplier and items made from the bill, category by name, stock in pieces, totals match the printed grand total');
  } catch (e) { console.log('  FAIL auto-create\n      ', e.stack); process.exitCode = 1; }
});

ok('MRP is read from item names in every common form', () => {
  const { mrpFromName } = require('../src/services/pdfParser');
  assert.deepStrictEqual(['BIKANO CHIPS (1X144 PKT) MRP-10/-', 'Tasty M.R.P. Rs 20', 'Mix Rs.5/-', 'Aloo Bhujia 10/-', 'Namkeen @ 25', 'Maggi 70G (1X48)', 'Rice 5 KG'].map(mrpFromName), [10, 20, 5, 10, 25, null, null]);
});

ok('parser: junk text gives warnings, not a crash', () => {
  const r = parseInvoiceText('hello world', { items, parties });
  assert.ok(r.warnings.length >= 2 && r.lines.length === 0);
});


const bulkTest = () => db.withCompany(id1, async () => {
  try {
    const { guessCategory } = require('../src/services/category');
    for (const nm of ['BIKANO ALL TIME MIX 400G', 'All Time Mix (1X24) MRP-10/-', 'Bikano Bhujia 1kg']) assert.strictEqual((await guessCategory(nm, { online: false })).name, 'Namkeen & Snacks');
    // express is not needed to test the handler: load the route file against a tiny recorder
    const Module = require('module'); const recorded = [];
    const fake = () => { const r = {}; for (const m of ['get', 'post', 'put', 'delete', 'use']) r[m] = (pth, ...hs) => { recorded.push({ m, pth, h: hs[hs.length - 1] }); return r; }; return r; };
    const orig = Module._load;
    Module._load = function (rq, ...a) { if (rq === 'express') { const e = () => fake(); e.Router = fake; e.json = () => () => {}; return e; } return orig.call(this, rq, ...a); };
    try { require('../src/routes/items'); } finally { Module._load = orig; }
    const layer = recorded.find((x) => x.m === 'post' && x.pth === '/items/bulk-prices');
    assert.ok(layer, 'route exists');
    const call = (body) => { let out; layer.h({ body }, { json: (o) => { out = o; } }, (e) => { throw e; }); return out; };
    // the items scanned from the real supplier bill; without the private test files, one made here stands in for them
    if (!db.prepare("SELECT 1 FROM items i JOIN categories c ON c.id=i.category_id WHERE c.name='Namkeen & Snacks' AND i.mrp>0").get()) {
      let c = db.prepare("SELECT id FROM categories WHERE name='Namkeen & Snacks'").get();
      if (!c) c = { id: Number(db.prepare("INSERT INTO categories(name) VALUES('Namkeen & Snacks')").run().lastInsertRowid) };
      db.prepare("INSERT INTO items(name,category_id,hsn,gst_rate,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box) VALUES('SAMPLE BHUJIA (1X144 PKT) MRP-10/-',?,'2106909',5,10,8,7.5,7,144)").run(c.id);
    }
    const cat = db.prepare("SELECT id FROM categories WHERE name='Namkeen & Snacks'").get().id;
    const it = db.prepare('SELECT id,mrp,gst_rate FROM items WHERE category_id=? AND mrp>0 LIMIT 1').get(cat);
    const pv = call({ category_id: cat, retail_off: 10, wholesale_off: 15, preview: true });
    assert.ok(pv.would_update >= 1 && pv.updated === 0);
    const r = call({ category_id: cat, retail_off: 10, wholesale_off: 15 });
    assert.ok(r.updated >= 1);
    const row = db.prepare('SELECT retail_price,wholesale_price FROM items WHERE id=?').get(it.id);
    const base = it.mrp / (1 + it.gst_rate / 100);
    assert.ok(Math.abs(row.retail_price - Math.round(base * 0.90 * 100) / 100) < 0.011 && Math.abs(row.wholesale_price - Math.round(base * 0.85 * 100) / 100) < 0.011);
    assert.throws(() => call({ category_id: cat }));
    // auto-mrp: reads "MRP-12/-" from the name, fills missing selling prices, groups the answer by category
    const am = recorded.find((x) => x.m === 'post' && x.pth === '/items/auto-mrp');
    assert.ok(am, 'auto-mrp route exists');
    db.prepare("INSERT INTO items(name,category_id,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box) VALUES('ZZ TEST SNACK (1X24) MRP-12/-',?,5,'PCS',0,0,0,0,24)").run(cat);
    db.prepare("INSERT INTO items(name,category_id,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box) VALUES('ZZ NO PRICE ITEM',?,5,'PCS',0,0,0,0,1)").run(cat);
    let rep; am.h({ body: {} }, { json: (o) => { rep = o; } }, (e) => { throw e; });
    const z = db.prepare("SELECT mrp,retail_price,wholesale_price FROM items WHERE name LIKE 'ZZ TEST SNACK%'").get();
    assert.strictEqual(z.mrp, 12); assert.ok(Math.abs(z.retail_price - 11.43) < 0.011 && Math.abs(z.wholesale_price - 11.43) < 0.011);
    assert.ok(rep.found >= 1 && rep.by_category['Namkeen & Snacks'].missing >= 1 && rep.missing.some((m) => m.name === 'ZZ NO PRICE ITEM'));
    n++; console.log('  ok   Bikano All Time Mix goes to Namkeen & Snacks; bulk MRP-based retail/wholesale update (with preview)');
  } catch (e) { console.log('  FAIL bulk prices\n      ', e.stack); process.exitCode = 1; }
});

const v5Test = () => {
  const FY = require('../src/utils/fy');
  const Module = require('module'); const recorded = [];
  const fake = () => { const r = {}; for (const m of ['get', 'post', 'put', 'delete', 'use']) r[m] = (pth, ...hs) => { recorded.push({ m, pth, h: hs[hs.length - 1] }); return r; }; return r; };
  const orig = Module._load;
  Module._load = function (rq, ...a) { if (rq === 'express') { const e = () => fake(); e.Router = fake; e.json = () => () => {}; return e; } return orig.call(this, rq, ...a); };
  try { for (const r of ['items', 'parties', 'reports', 'backup']) { delete require.cache[require.resolve('../src/routes/' + r)]; require('../src/routes/' + r); } } finally { Module._load = orig; }
  const call = (m, pth, o = {}) => { const l = recorded.filter((x) => x.m === m && x.pth === pth).pop(); assert.ok(l, pth + ' route'); let out; l.h({ body: o.body || {}, query: o.query || {}, params: o.params || {} }, { json: (v) => { out = v; }, status() { return this; } }, (e) => { throw e; }); return out; };

  db.withCompany(id1, () => {
    ok('financial year runs 1 April to 31 March', () => {
      assert.deepStrictEqual([FY.fyRange('2026-27').from, FY.fyRange('2026-27').to], ['2026-04-01', '2027-03-31']);
      assert.strictEqual(FY.fyRange('2025').label, '2025-26');
      assert.strictEqual(FY.startYearOf('2027-03-31'), 2026); assert.strictEqual(FY.startYearOf('2027-04-01'), 2027);
      assert.throws(() => FY.fyRange('2025-28')); assert.throws(() => FY.fyRange('abc'));
    });
    const cola = db.prepare("SELECT * FROM items WHERE name='Cola 750ml'").get();
    ok('bill numbers follow the bill date: 31 Mar and 1 Apr are different years, each starting at 1', () => {
      const a = getInvoice(createInvoice({ date: '2031-03-31', pay_mode: 'CASH', lines: [{ item_id: cola.id, pcs: 1 }] }));
      const b = getInvoice(createInvoice({ date: '2031-04-01', pay_mode: 'CASH', lines: [{ item_id: cola.id, pcs: 1 }] }));
      const c = getInvoice(createInvoice({ date: '2031-04-02', pay_mode: 'CASH', lines: [{ item_id: cola.id, pcs: 1 }] }));
      assert.strictEqual(a.invoice_no, 'INV/30-31/00001'); assert.strictEqual(b.invoice_no, 'INV/31-32/00001'); assert.strictEqual(c.invoice_no, 'INV/31-32/00002');
    });
    ok('financial years with data are listed; each year only sees its own bills', () => {
      const ys = FY.fyList().map((y) => y.label);
      assert.ok(ys.includes('2030-31') && ys.includes('2031-32'));
      const d30 = R.dashboard('2030-31'), d31 = R.dashboard('2031-32');
      assert.strictEqual(d30.fy_bills, 1); assert.strictEqual(d31.fy_bills, 2);
      assert.strictEqual(R.bills({ fy: '2030-31' }).rows.filter((r) => r.type === 'SALE').length, 1);
      assert.strictEqual(R.book('sales', null, null, '2031-32').rows.length, 2);
    });
    ok('profit = sales (ex-GST) minus cost of the pieces sold', () => {
      const id = createInvoice({ date: '2032-06-10', pay_mode: 'CASH', lines: [{ item_id: cola.id, pcs: 10, rate: 40, disc_pct: 0 }] });
      const inv = getInvoice(id);
      const cost = inv.lines.reduce((a, l) => a + (l.qty + l.free_qty) * (db.prepare('SELECT purchase_price p FROM batches WHERE id=?').get(l.batch_id).p || cola.purchase_price), 0);
      const p = R.profit('2032-06-10', '2032-06-10');
      assert.strictEqual(p.revenue, inv.taxable);
      assert.ok(Math.abs(p.profit - (inv.taxable - cost)) < 0.011, `${p.profit} vs ${inv.taxable - cost}`);
      assert.strictEqual(R.dashboard('2032-33').fy_profit, p.profit);
    });
    ok('rate can be changed per line while billing', () => {
      const r = buildInvoice({ date: '2032-06-11', lines: [{ item_id: cola.id, pcs: 10, rate: 12.5 }] });
      assert.strictEqual(r.display[0].rate, 12.5);
    });
    ok('party ledger: earlier years are carried as an opening balance, balances are as at the year end', () => {
      const pt = db.prepare("SELECT * FROM parties WHERE type<>'SUPPLIER' LIMIT 1").get();
      createInvoice({ date: '2033-02-01', party_id: pt.id, pay_mode: 'CREDIT', lines: [{ item_id: cola.id, pcs: 5 }] });
      const dueAtEnd = db.prepare('SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=? AND date<=?').get(pt.id, '2033-03-31').b;
      createInvoice({ date: '2033-05-01', party_id: pt.id, pay_mode: 'CREDIT', lines: [{ item_id: cola.id, pcs: 5 }] });
      const l = call('get', '/parties/:id/ledger', { params: { id: pt.id }, query: { fy: '2033-34' } });
      assert.ok(Math.abs(l.opening_balance - dueAtEnd) < 0.011); assert.strictEqual(l.entries.length, 1);
      const l2 = call('get', '/parties/:id/ledger', { params: { id: pt.id }, query: { fy: '2032-33' } });
      assert.ok(Math.abs(l2.balance - dueAtEnd) < 0.011);
      const list = call('get', '/parties', { query: { fy: '2032-33' } });
      assert.ok(Math.abs(list.find((x) => x.id === pt.id).balance - dueAtEnd) < 0.011);
    });
    ok('pieces per box is read from the name: (1X144), (1X240), (1X300)', () => {
      const ins = db.prepare("INSERT INTO items(name,gst_rate,unit,mrp,pcs_per_box) VALUES(?,12,'BOX',?,1)");
      ins.run('PACK A (1X144) MRP-5/-', 5); ins.run('PACK B (1X240) MRP-10/-', 10); ins.run('PACK C 1X300 MRP-10/-', 10);
      const r = call('post', '/items/auto-pack');
      assert.ok(r.changed >= 3);
      const g = (n) => db.prepare('SELECT pcs_per_box, unit FROM items WHERE name LIKE ?').get(n + '%');
      assert.deepStrictEqual([g('PACK A').pcs_per_box, g('PACK B').pcs_per_box, g('PACK C').pcs_per_box], [144, 240, 300]);
    });
    ok('different prices for different MRPs (MRP 5 and MRP 10) in one go', () => {
      const pv = call('post', '/items/bulk-prices-by-mrp', { body: { preview: true, tiers: [{ mrp: 5, retail: 4.2, wholesale: 4 }, { mrp: 10, retail: 8.5, wholesale: 8 }] } });
      assert.ok(pv.would_update >= 3 && pv.updated === 0);
      const r = call('post', '/items/bulk-prices-by-mrp', { body: { tiers: [{ mrp: 5, retail: 4.2, wholesale: 4 }, { mrp: 10, retail: 8.5 }] } });
      assert.ok(r.updated >= 3);
      const g = (n) => db.prepare('SELECT retail_price r, wholesale_price w FROM items WHERE name LIKE ?').get(n + '%');
      assert.deepStrictEqual([g('PACK A').r, g('PACK A').w, g('PACK B').r], [4.2, 4, 8.5]);
      assert.notStrictEqual(g('PACK B').w, 8);                                   // wholesale left alone when not given
      call('post', '/items/bulk-prices-by-mrp', { body: { include_gst: true, tiers: [{ mrp: 10, retail: 11.2 }] } });
      assert.strictEqual(g('PACK B').r, 10);                                      // 11.2 incl. 12% GST = 10.00 ex-GST
      const groups = call('get', '/items/mrp-groups');
      assert.ok(groups.some((x) => x.mrp === 5) && groups.some((x) => x.mrp === 10));
      assert.throws(() => call('post', '/items/bulk-prices-by-mrp', { body: { tiers: [{ mrp: 5 }] } }));
    });
  });

  // restore replaces the live data with the backup, and keeps a safety copy first
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dist-bk-'));
  B.saveConfig({ dir, keep: 30 });
  const before = db.withCompany(id1, () => db.prepare('SELECT COUNT(*) n FROM items').get().n);
  const snap = B.backupNow({ reason: 'test' });
  db.withCompany(id1, () => { db.prepare("INSERT INTO items(name,gst_rate,unit,mrp,pcs_per_box) VALUES('AFTER BACKUP ITEM',5,'PCS',1,1)").run(); });
  ok('restore from a backup folder brings back the old data (and a safety backup is made first)', () => {
    const nBackupsBefore = B.listBackups().length;
    const r = B.restore({ folder: snap.folder });
    assert.ok(r.restored.length >= 1);
    assert.strictEqual(B.listBackups().length, nBackupsBefore + 1);
    const after = db.withCompany(id1, () => ({ n: db.prepare('SELECT COUNT(*) n FROM items').get().n, gone: db.prepare("SELECT 1 FROM items WHERE name='AFTER BACKUP ITEM'").get() }));
    assert.strictEqual(after.n, before); assert.ok(!after.gone);
  });
  ok('restore goes to the company with the same NAME, and a missing company is created (never overwrites another)', () => {
    const list = B.listBackups()[0];
    assert.ok(list.companies.length >= 1, 'backup list shows company names');
    // a backup whose company is not here: rename the live company, restore -> old name is created again, renamed one untouched
    const row = db.registry.prepare('SELECT * FROM companies WHERE id=?').get(id1);
    const oldName = row.name;
    const snap2 = B.backupNow({ reason: 'test-name' });
    db.registry.prepare('UPDATE companies SET name=? WHERE id=?').run('Renamed Traders', id1);
    const count = db.registry.prepare('SELECT COUNT(*) n FROM companies').get().n;
    const r = B.restore({ folder: snap2.folder });
    assert.ok(r.restored.includes(oldName));
    const rows = db.registry.prepare('SELECT * FROM companies').all();
    assert.ok(rows.some((c) => c.name === 'Renamed Traders' && c.id === id1), 'other company left alone');
    assert.ok(rows.some((c) => c.name === oldName && c.id !== id1), 'restored into its own company');
    assert.ok(rows.length > count);
    db.registry.prepare('UPDATE companies SET name=? WHERE id=?').run(oldName, id1);
  });
  ok('merge adds missing records from a backup, keeps existing ones, reports conflicts', () => {
    const snapM = B.backupNow({ reason: 'test-merge' });
    const cnt = (t) => db.withCompany(id1, () => db.prepare(`SELECT COUNT(*) n FROM ${t}`).get().n);
    // new data made AFTER the backup (a new party and item), and data that exists only in the backup (delete one invoice now)
    db.withCompany(id1, () => {
      db.prepare("INSERT INTO items(name,gst_rate,unit,mrp,pcs_per_box) VALUES('MERGE KEEP ITEM',5,'PCS',1,1)").run();
      const inv = db.prepare('SELECT id FROM invoices ORDER BY id DESC LIMIT 1').get();
      db.prepare('DELETE FROM invoice_lines WHERE invoice_id=?').run(inv.id);
      db.prepare("DELETE FROM receipts WHERE invoice_id=?").run(inv.id);
      db.prepare('DELETE FROM invoices WHERE id=?').run(inv.id);
    });
    const invBefore = cnt('invoices'), itemsBefore = cnt('items');
    const r = B.restore({ folder: snapM.folder, mode: 'merge' });
    assert.strictEqual(r.mode, 'merge');
    assert.strictEqual(cnt('invoices'), invBefore + 1, 'missing invoice came back');
    assert.strictEqual(cnt('items'), itemsBefore, 'no duplicate items');
    assert.ok(db.withCompany(id1, () => db.prepare("SELECT 1 FROM items WHERE name='MERGE KEEP ITEM'").get()), 'newer data kept');
    const again = B.restore({ folder: snapM.folder, mode: 'merge' });
    assert.strictEqual(cnt('invoices'), invBefore + 1, 'merging twice adds nothing');
    assert.ok(Object.keys(again.merged[0].added).length === 0 || Object.values(again.merged[0].added).every((x) => x === 0));
  });
  ok('restore refuses a damaged / foreign folder and changes nothing', () => {
    const bad = fs.mkdtempSync(path.join(os.tmpdir(), 'dist-bad-'));
    assert.throws(() => B.restore({ folder: bad }), /manifest/);
    const f2 = path.join(snap.folder, snap.files[0].file); const saved = fs.readFileSync(f2);
    fs.appendFileSync(f2, 'tamper');
    try { assert.throws(() => B.restore({ folder: snap.folder }), /checksum/); } finally { fs.writeFileSync(f2, saved); }
  });
};
ok('a backup can be deleted on request, and only real backup folders', () => {
  const dir = B.config().dir;
  const f = path.join(dir, 'FMCG_Backup_20190101_000000'); fs.mkdirSync(f);
  assert.deepStrictEqual(B.deleteBackup('FMCG_Backup_20190101_000000'), { deleted: 'FMCG_Backup_20190101_000000' });
  assert.ok(!fs.existsSync(f));
  assert.throws(() => B.deleteBackup('../etc'), /not a backup/);
  B.saveConfig({ on_exit: true }); assert.strictEqual(B.config().on_exit, true); B.saveConfig({ on_exit: false });
});
ok('named parameters: an object with extra keys (a whole item row) can be passed to UPDATE', () => {
  const it = db.withCompany(id1, () => db.prepare('SELECT * FROM items WHERE active=1 LIMIT 1').get());
  db.withCompany(id1, () => db.prepare('UPDATE items SET mrp=@mrp, name=@name WHERE id=@id').run({ ...it, mrp: 99 }));
  assert.strictEqual(db.withCompany(id1, () => db.prepare('SELECT mrp FROM items WHERE id=?').get(it.id).mrp), 99);
});

const boxMathTest = () => {
  const Module = require('module'); const recorded = [];
  const fake = () => { const r = {}; for (const m of ['get', 'post', 'put', 'delete', 'use']) r[m] = (pth, ...hs) => { recorded.push({ m, pth, h: hs[hs.length - 1] }); return r; }; return r; };
  const orig = Module._load;
  Module._load = function (rq, ...a) { if (rq === 'express') { const e = () => fake(); e.Router = fake; e.json = () => () => {}; return e; } return orig.call(this, rq, ...a); };
  try { delete require.cache[require.resolve('../src/routes/items')]; require('../src/routes/items'); } finally { Module._load = orig; }
  const call = (m, pth, body) => { const l = recorded.filter((x) => x.m === m && x.pth === pth).pop(); let out; l.h({ body, query: {}, params: {} }, { json: (v) => { out = v; }, status() { return this; } }, (e) => { throw e; }); return out; };

  db.withCompany(id1, () => {
    const mk = (name, gst) => {
      const itemId = Number(db.prepare("INSERT INTO items(name,gst_rate,unit,mrp,retail_price,wholesale_price,pcs_per_box) VALUES(?,?,'PCS',10,0,0,300)").run(name, gst).lastInsertRowid);
      db.prepare("INSERT INTO batches(item_id,batch_no,exp_date,qty) VALUES(?,?,?,?)").run(itemId, 'B1', '2099-12-31', 3000);
      return itemId;
    };
    const total = (itemId, boxes, pcs, extra = {}) => buildInvoice({ date: '2030-01-10', lines: [{ item_id: itemId, boxes, pcs, ...extra }] });
    const id = mk('Namkeen Test (1X300)', 5);

    ok('a box priced 2500 (ex-GST) bills exactly 2500, not 2499 or 2501', () => {
      call('post', '/items/bulk-prices-by-mrp', { tiers: [{ mrp: 10, retail: 2500 }], per: 'box' });
      const r = total(id, 1, 0);
      assert.strictEqual(r.taxable, 2500);
      assert.strictEqual(total(id, 2, 0).taxable, 5000);
      assert.strictEqual(total(id, 10, 0).taxable, 25000);
      assert.strictEqual(r.total, Math.round(2500 * 1.05));
    });
    ok('a box priced 2500 INCLUDING GST bills a total of exactly 2500', () => {
      call('post', '/items/bulk-prices-by-mrp', { tiers: [{ mrp: 10, retail: 2500 }], per: 'box', include_gst: true });
      assert.strictEqual(total(id, 1, 0).total, 2500);
      assert.strictEqual(total(id, 1, 0).display[0].amount, 2500, 'line amount is 2500.00, not 2501.10');
      assert.strictEqual(total(id, 3, 0).total, 7500);
    });
    ok('per-piece price typed rounded to 2 places no longer drifts: 2500 / 300 = 8.333333 a piece', () => {
      call('post', '/items/bulk-prices-by-mrp', { tiers: [{ mrp: 10, retail: 2500 / 300 }] });
      assert.strictEqual(total(id, 1, 0).taxable, 2500);
      const stored = db.prepare('SELECT retail_price p FROM items WHERE id=?').get(id).p;
      assert.ok(Math.abs(stored - 8.333333) < 1e-5, 'stored ' + stored);
    });
    ok('rate typed on the bill as box rate / pieces per box keeps the box exact', () => {
      assert.strictEqual(total(id, 1, 0, { rate: Number((2500 / 300).toFixed(8)) }).taxable, 2500);
    });
    ok('bill total follows every change of boxes and pieces (what the screen asks for after each keystroke)', () => {
      call('post', '/items/bulk-prices-by-mrp', { tiers: [{ mrp: 10, retail: 2500 }], per: 'box' });
      let prev = null;
      for (const [b, p] of [[1, 0], [1, 1], [1, 12], [2, 0], [2, 150], [3, 0], [0, 5], [0, 300]]) {
        const r = total(id, b, p);
        const qty = b * 300 + p;
        assert.strictEqual(r.display[0].qty, qty);
        assert.strictEqual(r.taxable, Math.round((2500 / 300) * qty * 100) / 100, `${b} box ${p} pcs`);
        assert.notStrictEqual(r.total, prev === null ? NaN : prev, 'total changed');
        prev = r.total;
      }
    });
    ok('% below MRP: 16.67% retail and 21.67% wholesale on MRP 3000 a box bill exactly 2500 and 2350', () => {
      db.prepare("UPDATE items SET gst_rate=5, mrp=10 WHERE id=?").run(id);
      call('post', '/items/bulk-prices', { retail_off: 16.67, wholesale_off: 21.67 });
      const w = Number(db.prepare("INSERT INTO parties(name,type,price_tier,state_code) VALUES('Wholesale Pct','RETAILER','WHOLESALE','09')").run().lastInsertRowid);
      const retail = total(id, 1, 0), whole = buildInvoice({ date: '2030-01-10', party_id: w, lines: [{ item_id: id, boxes: 1, pcs: 0 }] });
      assert.strictEqual(retail.total, 2500); assert.strictEqual(retail.display[0].amount, 2500, 'not 2499.90');
      assert.strictEqual(whole.total, 2350); assert.ok(Math.abs(whole.display[0].amount - 2350) <= 0.011, 'line amount within a paisa of 2350 (GST rounding), bill total exact');
      assert.strictEqual(total(id, 3, 0).total, 7500);
      const pv = call('post', '/items/bulk-prices', { retail_off: 16.67, preview: true });
      assert.ok(pv.sample.length && pv.sample.every((x) => typeof x.retail_box === 'number'), 'the preview shows a box price for each sample item');
    });
    ok('% below MRP leaves a loose-piece item (1 per box) unrounded to whole rupees', () => {
      const lid = Number(db.prepare("INSERT INTO items(name,gst_rate,unit,mrp,retail_price,wholesale_price,pcs_per_box) VALUES('Loose PCT',5,'PCS',10,0,0,1)").run().lastInsertRowid);
      call('post', '/items/bulk-prices', { retail_off: 16.67 });
      const p = db.prepare('SELECT retail_price p FROM items WHERE id=?').get(lid).p;
      assert.ok(Math.abs(p - (10 * (1 - 0.1667)) / 1.05) < 1e-6, String(p));
    });
    ok('MRP price tier is not rounded per piece either', () => {
      db.prepare("UPDATE items SET gst_rate=5 WHERE id=?").run(id);
      const party = db.prepare("INSERT INTO parties(name,type,price_tier,state_code) VALUES('Tier Test','RETAILER','MRP','09')").run();
      const r = buildInvoice({ date: '2030-01-10', party_id: Number(party.lastInsertRowid), lines: [{ item_id: id, boxes: 1, pcs: 0 }] });
      assert.ok(Math.abs(r.taxable - 3000 / 1.05) < 0.006, String(r.taxable));
    });
  });
};


const billMathTest = () => {
  const port = require('./billmath_port');
  db.withCompany(id1, () => {
    const gsts = [0, 5, 12, 18, 28];
    const ppbs = [1, 6, 12, 24, 48, 100, 300];
    const items = ppbs.flatMap((ppb) => gsts.map((g) => {
      const iid = Number(db.prepare("INSERT INTO items(name,gst_rate,unit,mrp,retail_price,wholesale_price,pcs_per_box) VALUES(?,?,'PCS',100,?,?,?)")
        .run(`BM ${ppb}-${g}`, g, Math.round((3 + Math.random() * 200) * 1e8) / 1e8, Math.round((2 + Math.random() * 150) * 1e8) / 1e8, ppb).lastInsertRowid);
      db.prepare("INSERT INTO batches(item_id,batch_no,exp_date,qty) VALUES(?,?,?,?)").run(iid, 'B1', '2099-12-31', 1e7);
      return { iid, ppb, gst: g };
    }));
    const inter = Number(db.prepare("INSERT INTO parties(name,type,price_tier,state_code) VALUES('BM Inter','RETAILER','WHOLESALE','29')").run().lastInsertRowid);
    const intra = Number(db.prepare("INSERT INTO parties(name,type,price_tier,state_code) VALUES('BM Intra','RETAILER','MRP','09')").run().lastInsertRowid);
    ok('Swift bill maths (ported) equals the server engine for 4000 random bills, to the paisa', () => {
      let compared = 0;
      for (let n = 0; n < 4000; n++) {
        const party = [null, inter, intra][n % 3];
        const tier = party === inter ? 'WHOLESALE' : party === intra ? 'MRP' : 'RETAIL';
        const k = 1 + Math.floor(Math.random() * 4);
        const picked = [], payload = [];
        for (let j = 0; j < k; j++) {
          const it = items[Math.floor(Math.random() * items.length)];
          if (picked.includes(it.iid)) continue; picked.push(it.iid);
          const row = db.prepare('SELECT * FROM items WHERE id=?').get(it.iid);
          const boxes = it.ppb > 1 ? Math.floor(Math.random() * 12) : 0, pcs = Math.floor(Math.random() * (it.ppb > 1 ? it.ppb : 50)) + (boxes === 0 ? 1 : 0);
          const typed = Math.random() < 0.2 ? Math.round(Math.random() * 300 * 1e8) / 1e8 : undefined;
          const disc = Math.random() < 0.3 ? Math.floor(Math.random() * 30) : 0;
          const list = tier === 'WHOLESALE' ? row.wholesale_price : tier === 'MRP' ? row.mrp / (1 + row.gst_rate / 100) : row.retail_price;
          payload.push({ srv: { item_id: it.iid, boxes, pcs, disc_pct: disc, ...(typed !== undefined ? { rate: typed } : {}) },
                         loc: { boxes, pcs, ppb: it.ppb, listRate: list, typedRate: typed, discPct: disc, gstRate: it.gst } });
        }
        const srv = buildInvoice({ date: '2030-01-10', party_id: party || undefined, lines: payload.map((p) => p.srv) });
        const loc = port.compute(payload.map((p) => p.loc), srv.intra);
        assert.strictEqual(loc.total, srv.total, `total #${n}`);
        assert.strictEqual(loc.taxable, srv.taxable, `taxable #${n}`);
        assert.strictEqual(loc.subtotal, srv.subtotal, `subtotal #${n}`);
        assert.strictEqual(loc.roundOff, srv.round_off, `round off #${n}`);
        assert.strictEqual(loc.cgst + loc.sgst + loc.igst, srv.cgst + srv.sgst + srv.igst, `gst #${n}`);
        srv.display.forEach((d, x) => assert.strictEqual(loc.lines[x].amount, d.amount, `line ${x} #${n}`));
        compared++;
      }
      assert.strictEqual(compared, 4000);
    });
    ok('changing only the Pcs box changes total pieces x per-piece rate and the bottom-bar total: 1 box + n pcs', () => {
      const it = items.find((x) => x.ppb === 300 && x.gst === 5);
      const row = db.prepare('SELECT * FROM items WHERE id=?').get(it.iid);
      const seen = new Set();
      for (const pcs of [0, 1, 2, 10, 50, 150, 299, 300, 301]) {
        const l = port.compute([{ boxes: 1, pcs, ppb: 300, listRate: row.retail_price, discPct: 0, gstRate: 5 }], true);
        assert.strictEqual(l.pieces, 300 + pcs);
        const srv = buildInvoice({ date: '2030-01-10', lines: [{ item_id: it.iid, boxes: 1, pcs }] });
        assert.strictEqual(l.total, srv.total);
        seen.add(l.total);
      }
      assert.ok(seen.size >= 8, 'every Pcs change moved the total');
    });
  });
};


const debitNoteTest = () => db.withCompany(id1, () => {
  const D = require('../src/services/debitNotes');
  const sup = db.prepare("SELECT * FROM parties WHERE name='Hind Beverages Pvt Ltd'").get();
  const far = db.prepare("SELECT * FROM parties WHERE name='Northern FMCG Agencies'").get();
  db.prepare("INSERT INTO items(name,hsn,gst_rate,mrp,pcs_per_box) VALUES('DN Test Biscuit (1X24)','1905',18,10,24)").run();
  const it = db.prepare("SELECT * FROM items WHERE name='DN Test Biscuit (1X24)'").get();
  const stockOf = () => db.prepare('SELECT COALESCE(SUM(qty),0) q FROM batches WHERE item_id=?').get(it.id).q;
  const bal = (pid) => db.prepare('SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=?').get(pid).b;
  const pur = createPurchase({ party_id: sup.id, supplier_invoice_no: 'DN-SRC-1', date: '2032-05-02',
    lines: [{ item_id: it.id, qty: 5, unit: 'BOX', rate: 200, batch_no: 'A1', exp_date: '2033-01-31' }, { item_id: it.id, qty: 2, unit: 'BOX', rate: 200, batch_no: 'B1', exp_date: '2033-06-30' }] });
  ok('debit note: boxes x rate, bill discount, CGST/SGST at the item rate, rounded', () => {
    const p = D.previewDebitNote({ party_id: sup.id, date: '2032-05-10', discount: 10, lines: [{ item_id: it.id, qty: 2, unit: 'BOX', rate: 200 }] });
    assert.deepStrictEqual([p.subtotal, p.taxable, p.cgst, p.sgst, p.igst, p.round_off, p.total], [400, 390, 35.1, 35.1, 0, -0.2, 460]);
    assert.strictEqual(p.lines[0].pcs_qty, 48);
    const q = D.previewDebitNote({ party_id: far.id, date: '2032-05-10', lines: [{ item_id: it.id, qty: 10, rate: 8 }] });
    assert.deepStrictEqual([q.cgst, q.igst, q.total], [0, 14.4, 94]);
  });
  let dn;
  ok('saving takes the pieces out of the earliest-expiring batches and debits the supplier', () => {
    const s0 = stockOf(), b0 = bal(sup.id);
    dn = D.createDebitNote({ party_id: sup.id, date: '2032-05-10', purchase_id: pur, reason: 'Damaged', lines: [{ item_id: it.id, qty: 6, unit: 'BOX', rate: 200 }] });
    const d = D.getDebitNote(dn);
    assert.ok(/^DN\/32-33\/\d{5}$/.test(d.note_no), d.note_no);
    assert.strictEqual(stockOf(), s0 - 144);
    assert.strictEqual(db.prepare("SELECT qty FROM batches WHERE item_id=? AND batch_no='A1'").get(it.id).qty, 0);
    assert.strictEqual(db.prepare("SELECT qty FROM batches WHERE item_id=? AND batch_no='B1'").get(it.id).qty, 24);
    assert.strictEqual(d.lines[0].batch_no, 'A1, B1');
    assert.strictEqual(d.against_bill, 'DN-SRC-1');
    assert.strictEqual(r2n(bal(sup.id) - b0), d.total);
    assert.strictEqual(d.doc_title, 'DEBIT NOTE'); assert.strictEqual(d.print_lines[0].qty, 144);
  });
  ok('more than the stock is refused and changes nothing', () => {
    const s0 = stockOf();
    assert.ok(throws(() => D.createDebitNote({ party_id: sup.id, date: '2032-05-11', lines: [{ item_id: it.id, qty: 2, unit: 'BOX', rate: 1 }] }), 409));
    assert.strictEqual(stockOf(), s0);
  });
  ok('editing puts the old pieces back first; deleting restores stock and ledger', () => {
    const s0 = stockOf(), b0 = bal(sup.id);
    D.updateDebitNote(dn, { party_id: sup.id, date: '2032-05-10', lines: [{ item_id: it.id, qty: 1, unit: 'BOX', rate: 200 }] });
    assert.strictEqual(stockOf(), s0 + 120);
    const d = D.getDebitNote(dn);
    assert.strictEqual(r2n(bal(sup.id) - b0), r2n(d.total - 6 * 200 * 1.18));
    D.deleteDebitNote(dn);
    assert.strictEqual(stockOf(), s0 + 144);
    assert.strictEqual(db.prepare("SELECT COUNT(*) n FROM ledger WHERE type='DEBIT_NOTE' AND ref_no=?").get(d.note_no).n, 0);
  });
  ok('debit notes reduce the month\'s input tax credit and appear in All Bills', () => {
    const before = R.gstOutward('2032-06').input_credit.total;
    const id = D.createDebitNote({ party_id: sup.id, date: '2032-06-03', lines: [{ item_id: it.id, qty: 10, rate: 8 }] });
    const g = R.gstOutward('2032-06');
    assert.strictEqual(r2n(before - g.input_credit.total), 14.4);
    assert.strictEqual(g.input_credit.debit_notes, 14.4);
    const b = R.bills({ type: 'DEBIT_NOTE', fy: '2032-33' });
    assert.ok(b.rows.some((r) => r.id === id && r.type === 'DEBIT_NOTE' && r.total === r.paid));
    assert.strictEqual(R.book('debit', '2032-06-01', '2032-06-30', '2032-33').rows.length, 1);
  });
});

const margTest = () => {
  if (!havePriv) return;
  const M = require('../src/services/margImport');
  const zip = path.join(PRIV, 'marg_csv_backup_2026-27.zip');
  const made = db.createCompany({ name: 'Marg Import Test' });
  db.withCompany(typeof made === 'object' ? made.id : made, () => {
    ok('Marg backup: every bill total, party closing balance and item closing stock matches Marg', () => {
      const p = M.previewMarg(zip);
      for (const k of ['bills', 'party_balances', 'stock']) assert.deepStrictEqual(p.checks[k].problems, [], k);
      assert.deepStrictEqual([p.found.sales, p.found.purchases, p.found.debit_notes], [415, 14, 2]);
    });
    ok('importing twice adds nothing the second time', () => {
      M.importMarg(zip);
      const again = M.importMarg(zip);
      assert.ok(Object.values(again.added).every((v) => v === 0), JSON.stringify(again.added));
    });
  });
};


const yearsTest = async () => {
  console.log('Financial years as separate books');
  const Y = require('../src/services/years');
  const F = require('../src/utils/fy');
  let made;
  ok('next year starts as its own books with masters and opening balances carried', () => {
    made = Y.addYear(id1, { fy: '2030-31', carry: true });
    assert.strictEqual(made.fy, '2030-31');
    assert.ok(made.carried && made.carried.masters > 0, JSON.stringify(made.carried));
    db.withCompany(made.id, () => {
      assert.strictEqual(F.booksFy(), '2030-31');
      assert.deepStrictEqual(F.fyList().map((y) => y.label), ['2030-31']);
      assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM invoices').get().n, 0);
    });
  });
  ok('the same year twice is refused', () => assert.ok(throws(() => Y.addYear(id1, { fy: '2030-31' }), 'YEAR_EXISTS')));
  ok('an earlier year can start empty', () => {
    const e = Y.addYear(id1, { fy: '2019-20', carry: false });
    assert.strictEqual(e.carried, null);
    db.withCompany(e.id, () => assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM items').get().n, 0));
  });
};

const sheetTest = async () => {
  console.log('Payments from a handwritten list');
  const P = require('../src/services/paymentSheet');
  ok('bills, then the payment after a dash', () => assert.deepStrictEqual(P.parseLine('1. Ram General Store 1200, 850 - 2000'), { name: 'Ram General Store', bills: [1200, 850], payment: 2000, amount: 2000 }));
  ok('no payment written: the bills in full', () => assert.strictEqual(P.parseLine('Shyam Kirana 1200,850').amount, 2050));
  ok('OCR letters inside numbers and Rs /-', () => assert.deepStrictEqual(P.parseLine('Gupta Traders Rs 5OO/-'), { name: 'Gupta Traders', bills: [500], payment: null, amount: 500 }));
  ok('lakh and thousand commas', () => assert.deepStrictEqual(P.parseLine('A 1,20,000, 5,000 - 1,25,000').bills, [120000, 5000]));
  ok('"paid" before the only amount', () => assert.deepStrictEqual(P.parseLine('Sharma ji: paid 700'), { name: 'Sharma ji', bills: [], payment: 700, amount: 700 }));
  ok('close spellings match, common words alone do not', () => {
    assert.ok(P.nameScore('Gupta Genral Store', 'Gupta General Store') >= 0.6);
    assert.ok(P.nameScore('Traders', 'Delhi Traders') < 0.6);
  });
};

const itemToolsTest = async () => {
  console.log('Item names, duplicates and online lists');
  const T = require('../src/services/itemTools');
  ok('pack sizes tidied, capitals kept', () => assert.strictEqual(T.cleanName('BIKANO  BHUJIA 200 GM'), 'BIKANO BHUJIA 200G'));
  ok('Title Case keeps short brand letters', () => assert.strictEqual(T.cleanName('MDH chana masala 100 gms', 'title'), 'MDH Chana Masala 100g'));
  ok('Marg "/-" endings stay', () => assert.strictEqual(T.cleanName('ITC sunfeast (1X12) MRP-10/-'), 'ITC sunfeast (1X12) MRP-10/-'));
  ok('the same item written two ways has one key', () => assert.strictEqual(T.itemKey('Cola 750 ML (1X24)'), T.itemKey('cola 750ml (1x24)')));
  ok('price list table: pack cell joined, MRP column used, repeats merged', () => {
    const lines = T.htmlLines('<table><tr><th>Product</th><th>Pack</th><th>MRP</th></tr><tr><td>Bhujia</td><td>200 gm</td><td>&#8377; 50</td></tr><tr><td>BHUJIA 200GMS</td><td></td><td>50</td></tr></table>');
    assert.deepStrictEqual(lines, ['Product | Pack | MRP', 'Bhujia | 200 gm | ₹ 50', 'BHUJIA 200GMS | 50']);
  });
};

const pricingTest = async () => {
  console.log('Prices from MRP and similar names');
  const P = require('../src/services/pricing');
  const T = require('../src/services/itemTools');
  const { buildInvoice } = require('../src/services/billing');
  ok('16.67% below a 3,000 box: the bill for one box is exactly 2,500', () => db.withCompany(id1, () => {
    const id = Number(db.prepare("INSERT INTO items(name,gst_rate,mrp,pcs_per_box) VALUES('Smoke Box (1X12)',18,250,12)").run().lastInsertRowid);
    db.prepare("INSERT INTO batches(item_id,batch_no,exp_date,qty) VALUES(?,'S1','2099-12-31',24)").run(id);
    const r = P.setPrices({ retail_off: 16.67, item_ids: [id] });
    assert.strictEqual(r.items[0].retail_bill, 2500);
    assert.strictEqual(buildInvoice({ lines: [{ item_id: id, boxes: 1 }] }).total, 2500);
  }));
  ok('a price typed for the box with GST is what the bill shows', () => db.withCompany(id1, () => {
    const id = db.prepare("SELECT id FROM items WHERE name='Smoke Box (1X12)'").get().id;
    P.setPrices({ mode: 'table', per: 'box', include_gst: true, tiers: [{ mrp: 250, retail: 2400 }], item_ids: [id] });
    assert.strictEqual(buildInvoice({ lines: [{ item_id: id, boxes: 1 }] }).total, 2400);
  }));
  ok('similar names group, different packs never', () => db.withCompany(id1, () => {
    for (const n of ['Smoke Bhujia 200g', 'SMOKE BHUJIYA 200 GM', 'Smoke Bhujia 400g']) db.prepare('INSERT INTO items(name,mrp) VALUES(?,50)').run(n);
    const g = T.cleanPreview({}).groups.find((x) => x.keep.name.toLowerCase().includes('smoke bhuj'));
    assert.ok(g && g.merge.length === 1 && !g.merge.concat(g.keep).some((x) => x.name.includes('400')), JSON.stringify(g));
  }));
};

const ewbTest = async () => {
  console.log('E-way bill');
  const E = require('../src/services/ewayBill');
  ok('PIN code read from an address', () => {
    assert.strictEqual(E.pinFrom('Main Bazar, Bijnor 246701 (UP), Ph 9000000001'), '246701');
    assert.strictEqual(E.pinFrom('Shop 12, Main Road'), '');
  });
};

const r2n = (x) => Math.round((x + Number.EPSILON) * 100) / 100;

autoCreateTest().then(bulkTest).then(debitNoteTest).then(margTest).then(v5Test).then(boxMathTest).then(billMathTest).then(yearsTest).then(sheetTest).then(itemToolsTest).then(pricingTest).then(ewbTest).then(() => console.log(`\n${n} checks passed${process.exitCode ? ' (with failures above)' : ''}`));
