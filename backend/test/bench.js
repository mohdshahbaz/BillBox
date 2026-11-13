// Timings of the slow paths on a large synthetic company (docs/BACKEND_PERF.md).
// Run with: node test/bench.js [invoices=20000]   (throwaway database in a temp folder; prints a table and a checksum of
// every answer, so a speed change can be checked for "no figure changed": the checksum must stay the same).
const os = require('os'), fs = require('fs'), path = require('path'), crypto = require('crypto');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'bb-bench-'));
const db = require('../src/db');
const R = require('../src/services/reports');
const { buildXlsx } = require('../src/utils/xlsx');

const { parseInvoiceText } = require('../src/services/pdfParser');
const B = require('../src/services/backup');

const N = Number(process.argv[2]) || 20000;
const PDF_TEXT = `ORIGINAL FOR RECIPIENT
SUPPLIER 3 TRADERS
GSTIN: 27ABCDE0003F1Z5 State Code: 27
TAX INVOICE
Invoice No: ST/26-27/0457 Invoice Date: 18/10/2026
S.No Description of Goods HSN Qty Unit Rate Amount
${Array.from({ length: 40 }, (_, i) => `${i + 1} Item ${i * 7} 3401 ${12 + i} PCS ${(40 + i).toFixed(2)} ${((12 + i) * (40 + i)).toFixed(2)}`).join('\n')}
CGST 9% 100.00
SGST 9% 100.00
Grand Total 99999.00`;
const pdfCtx = () => ({ items: db.prepare('SELECT id,name,hsn,gst_rate FROM items').all(), parties: db.prepare("SELECT id,name,gstin FROM parties WHERE type='SUPPLIER'").all(), companyGstin: '', companyName: '' });
const id = db.firstCompanyId();
const { fyRange } = require('../src/utils/fy');
const fy = fyRange();

// deterministic pseudo-random numbers, so every run builds the same books
let seed = 42;
const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const pick = (n) => Math.floor(rnd() * n);
const r2 = (x) => Math.round(x * 100) / 100;
const dayOf = (k) => { const d = new Date(fy.from + 'T12:00:00'); d.setDate(d.getDate() + k); return d.toLocaleDateString('en-CA'); };
const days = Math.max(1, Math.round((new Date(fy.to) - new Date(fy.from)) / 864e5));

db.withCompany(id, () => {
  const run = (sql, ...a) => Number(db.prepare(sql).run(...a).lastInsertRowid);
  db.transaction(() => {
    const items = [], parties = [], batches = [];
    for (let i = 0; i < 400; i++) {
      const it = run('INSERT INTO items(name,hsn,gst_rate,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box) VALUES(?,?,?,?,?,?,?,?)',
        `Item ${i}`, '3401', [5, 12, 18, 28][i % 4], 50 + i, 40 + i, 38 + i, 30 + i, 12);
      items.push(it);
      for (let b = 0; b < 3; b++) batches.push([it, run('INSERT INTO batches(item_id,batch_no,exp_date,qty,purchase_price) VALUES(?,?,?,?,?)', it, `B${i}-${b}`, dayOf(200 + b * 90), 5 + pick(400), 30 + i)]);
    }
    for (let p = 0; p < 300; p++) parties.push(run("INSERT INTO parties(name,gstin,state_code,type) VALUES(?,?,?,?)", `Party ${p}`, p % 3 ? '' : `27ABCDE${String(p).padStart(4, '0')}F1Z5`, '27', p < 20 ? 'SUPPLIER' : 'RETAILER'));
    for (let n = 0; n < N; n++) {
      const date = dayOf(pick(days)), party = parties[20 + pick(280)];
      const lines = [];
      for (let l = 0; l < 4; l++) {
        const [it, bt] = batches[pick(batches.length)], qty = 1 + pick(24), rate = 40 + pick(300), g = [5, 12, 18, 28][pick(4)];
        const taxable = r2(qty * rate), half = r2(taxable * g / 200);
        lines.push([it, bt, qty, rate, taxable, g, half, half, 0, r2(taxable + 2 * half)]);
      }
      const taxable = r2(lines.reduce((a, l) => a + l[4], 0)), c = r2(lines.reduce((a, l) => a + l[6], 0));
      const raw = taxable + 2 * c, total = Math.round(raw), ro = r2(total - raw);
      const inv = run(`INSERT INTO invoices(invoice_no,date,party_id,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,printed)
                       VALUES(?,?,?,?,0,?,?,?,0,?,?,?,?)`, `INV${n}`, date, party, taxable, taxable, c, c, ro, total, pick(3) ? total : 0, pick(5) ? 1 : 0);
      for (const l of lines) run(`INSERT INTO invoice_lines(invoice_id,item_id,batch_id,qty,rate,taxable,gst_rate,cgst,sgst,igst,amount) VALUES(?,?,?,?,?,?,?,?,?,?,?)`, inv, ...l);
      run("INSERT INTO ledger(party_id,date,type,ref_no,debit) VALUES(?,?,'INVOICE',?,?)", party, date, `INV${n}`, total);
      if (n % 3 === 0) run("INSERT INTO ledger(party_id,date,type,ref_no,credit) VALUES(?,?,'RECEIPT',?,?)", party, date, `R${n}`, total);
    }
    for (let n = 0; n < N / 10; n++) {
      const date = dayOf(pick(days)), t = 1000 + pick(90000), c = r2(t * 0.09);
      run(`INSERT INTO purchases(purchase_no,supplier_invoice_no,date,party_id,taxable,cgst,sgst,igst,round_off,total,paid) VALUES(?,?,?,?,?,?,?,0,0,?,?)`,
        `P${n}`, `S${n}`, date, parties[pick(20)], t, c, c, r2(t + 2 * c), 0);
    }
  })();

  const month = (fy.current ? new Date().toLocaleDateString('en-CA') : fy.to).slice(0, 7);
  const cases = [
    ['dashboard', () => R.dashboard()],
    ['all bills (whole year)', () => R.bills({})],
    ['all bills, search "Party 1"', () => R.bills({ q: 'Party 1' })],
    ['all bills, unpaid only', () => R.bills({ unpaid: true })],
    ['sales book (year)', () => R.book('sales', fy.from, fy.to)],
    ['GST outward (month)', () => R.gstOutward(month)],
    ['GST workbook (month, xlsx)', () => { const d = R.gstOutwardDetail(month); return { d, bytes: buildXlsx ? 1 : 0 }; }],
    ['low stock', () => R.lowStock()],
    ['profit (year)', () => R.profit(fy.from, fy.to)],
    // Excel export: the whole year's sales book as one sheet (the biggest workbook the apps write)
    ['Excel: sales book (year, xlsx)', () => {
      const rows = R.book('sales', fy.from, fy.to);
      const list = Array.isArray(rows) ? rows : rows.rows || [];
      const keys = list.length ? Object.keys(list[0]) : [];
      const buf = buildXlsx([{ name: 'Sales', title: 'Sales book', cols: keys.map((k) => ({ h: k, k, t: typeof list[0][k] === 'number' ? 'num' : 'text' })), rows: list }]);
      return { bytes: buf.length, crc: crypto.createHash('sha256').update(buf).digest('hex').slice(0, 16) };
    }],
    // PDF import: a 40-line supplier bill matched against the 400 items and 20 suppliers
    ['PDF import: parse 40-line bill', () => parseInvoiceText(PDF_TEXT, pdfCtx())],
  ];
  const rows = [];
  const hash = crypto.createHash('sha256');
  for (const [name, fn] of cases) {
    fn(); // warm up
    const times = [];
    let out;
    for (let k = 0; k < 7; k++) { const t0 = process.hrtime.bigint(); out = fn(); times.push(Number(process.hrtime.bigint() - t0) / 1e6); }
    times.sort((a, b) => a - b);
    const json = JSON.stringify(out, (k, v) => (k === 'as_of' ? undefined : v));
    hash.update(name + json);
    if (process.env.BENCH_DUMP) fs.appendFileSync(process.env.BENCH_DUMP, name + '\n' + JSON.stringify(JSON.parse(json), null, 1) + '\n');
    rows.push([name, times[3].toFixed(1)]);
  }
  // backup and restore: timed once each (they write files); not part of the checksum
  const once = (name, fn) => { const t0 = process.hrtime.bigint(); const out = fn(); rows.push([name, (Number(process.hrtime.bigint() - t0) / 1e6).toFixed(1)]); return out; };
  B.saveConfig({ dir: path.join(process.env.DATA_DIR, 'backups') });
  const made = once('backup now (all companies)', () => B.backupNow());
  // the copy is renamed so the restore finds the new, empty company by name (restores match companies by name)
  const copy = path.join(process.env.DATA_DIR, 'bench-copy.db');
  fs.copyFileSync(path.join(made.folder, made.files.find((f) => f.company_id).file), copy);
  { const { DatabaseSync } = require('node:sqlite'); const d = new DatabaseSync(copy); d.prepare("UPDATE settings SET value='Bench restore target' WHERE key='company_name'").run(); d.close(); }
  const blank = db.createCompany({ name: 'Bench restore target' });
  const res = once('restore: merge into empty books', () => B.restore({ file: copy, company_id: blank, mode: 'merge' }));
  const added = res.merged[0] ? res.merged[0].added : {};
  console.log('merged', JSON.stringify(added));
  // what the merge wrote, row by row (must not change when the merge gets faster)
  const mh = crypto.createHash('sha256');
  db.withCompany(blank, () => {
    for (const t of ['parties', 'items', 'batches', 'invoices', 'invoice_lines', 'purchases', 'purchase_lines', 'ledger', 'counters']) {
      for (const r of db.prepare(`SELECT * FROM ${t} ORDER BY rowid`).all()) mh.update(t + JSON.stringify(r, (k, v) => (k === 'created_at' || k === 'updated_at' ? undefined : v)));
    }
  });
  console.log('merge checksum', mh.digest('hex').slice(0, 16));
  console.log(`${N} sale bills, ${N / 10} purchases, 400 items, 300 parties (node ${process.version})`);
  for (const [n, t] of rows) console.log(`  ${n.padEnd(32)} ${t.padStart(8)} ms`);
  console.log('answers checksum', hash.digest('hex').slice(0, 16));
});
