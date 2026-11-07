// Numbering carries on from the last document (bills imported from Marg): node test/numbering.js
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'numbering-'));
const db = require('../src/db');
const { followLast, peekNo, nextNo, numberingEdited, today } = require('../src/utils/misc');
let passed = 0;
const ok = (name, fn) => { db.withCompany(db.firstCompanyId(), fn); passed++; console.log('  ok  ', name); };
const bill = (no, date) => db.prepare("INSERT INTO invoices(invoice_no,date,total) VALUES(?,?,0)").run(no, date);
const party = () => Number(db.prepare("INSERT INTO parties(name,type) VALUES('P'||abs(random()),'CUSTOMER')").run().lastInsertRowid);
const yday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);

ok('without bills BillBox numbering stays', () => {
  assert.deepStrictEqual(followLast(), {});
  assert.match(peekNo('INV').next_no, /^INV\/\d\d-\d\d\/00001$/);
});
ok('after Marg bills (A000421, A000422) the next bill is A000423', () => {
  bill('A000421', '2026-04-02'); bill('A000422', yday);
  assert.deepStrictEqual(followLast(), { INV: 'A000423' });
  assert.strictEqual(nextNo('INV'), 'A000423');
  assert.strictEqual(nextNo('INV'), 'A000424');
  assert.deepStrictEqual(followLast(), {}, 'a BillBox bill made since: nothing changes');
});
ok('receipts numbered only with digits (Marg 000077) go on from 000078', () => {
  db.prepare("INSERT INTO receipts(receipt_no,date,party_id,mode,amount) VALUES('000077',?,?,'CASH',1)").run(yday, party());
  assert.strictEqual(followLast().RCT, '000078');
  assert.strictEqual(nextNo('RCT'), '000078');
});
ok('unpadded numbers keep growing (P99 → P100)', () => {
  db.prepare("INSERT INTO purchases(purchase_no,date,party_id,total,paid) VALUES('P99',?,?,0,0)").run(yday, party());
  followLast();
  assert.strictEqual(nextNo('PUR'), 'P100');
});
ok('numbering set by hand in Settings stops following', () => {
  numberingEdited({ num_INV_prefix: 'INV' });
  db.prepare("UPDATE settings SET value='INV' WHERE key='num_INV_prefix'").run();
  assert.match(peekNo('INV').next_no, /^INV\/\d\d-\d\d\/0+1$/);
});
console.log(`numbering: ${passed} checks passed`);
