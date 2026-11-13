// Checks, against the running desktop app's engine, every engine route the Windows/Linux screens added for parity with
// the Mac use, and that the replies have the fields those screens read. Run by desktop/ci/linux-ui-test.sh after the
// demo books are seeded; it leaves a debit note and a few payments in the books, so the screenshots show them.
// usage: node desktop/ci/api-check.mjs [http://127.0.0.1:37420]
const root = (process.argv[2] || 'http://127.0.0.1:37420') + '/api';
let failed = 0, passed = 0;

async function call(method, path, body) {
  const r = await fetch(root + path, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  return { status: r.status, json };
}
function has(obj, keys, where) {
  const missing = keys.filter((k) => !(obj && Object.prototype.hasOwnProperty.call(obj, k)));
  if (missing.length) throw new Error(`${where}: missing ${missing.join(', ')}`);
}
async function check(name, fn) {
  try { await fn(); passed++; console.log(`  ok   ${name}`); }
  catch (e) { failed++; console.log(`  FAIL ${name}: ${e.message}`); console.log(`::error title=Desktop API check::${name}: ${e.message}`); }
}
const ok = (r, where, want = [200, 201]) => { if (!want.includes(r.status)) throw new Error(`${where}: HTTP ${r.status} ${JSON.stringify(r.json).slice(0, 200)}`); return r.json; };

const suppliers = ok(await call('GET', '/parties?kind=SUPPLIER'), 'suppliers');
const customers = ok(await call('GET', '/parties?kind=CUSTOMER'), 'customers');
const items = ok(await call('GET', '/items'), 'items');
const stocked = items.find((i) => Number(i.stock) >= 5);
let noteId = null;

console.log('Debit notes');
await check('preview has the totals the editor shows', async () => {
  const p = ok(await call('POST', '/debit-notes/preview', { party_id: suppliers[0].id, reason: 'Damaged', lines: [{ item_id: stocked.id, qty: '2', unit: 'PCS', rate: '10' }] }), 'preview');
  has(p, ['subtotal', 'taxable', 'cgst', 'sgst', 'igst', 'round_off', 'total', 'supply', 'lines'], 'preview');
});
await check('save, list, open, print fields', async () => {
  const s = ok(await call('POST', '/debit-notes', { party_id: suppliers[0].id, reason: 'Damaged', against_bill: 'CI-1', lines: [{ item_id: stocked.id, qty: '2', unit: 'PCS', rate: '10' }] }), 'save');
  has(s, ['id', 'note_no', 'total'], 'save');
  noteId = s.id;
  const l = ok(await call('GET', '/debit-notes?q='), 'list');
  has(l, ['rows', 'totals'], 'list');
  has(l.rows[0], ['id', 'note_no', 'date', 'party', 'against_bill', 'reason', 'taxable', 'cgst', 'sgst', 'igst', 'total'], 'list row');
  has(l.totals, ['count', 'taxable', 'total'], 'list totals');
  const n = ok(await call('GET', `/debit-notes/${noteId}`), 'open');
  has(n, ['note_no', 'party_id', 'lines', 'print_lines', 'doc_title', 'amount_words', 'gst_summary', 'invoice_no'], 'open');
  has(n.lines[0], ['item_id', 'unit', 'qty', 'pcs_qty', 'rate', 'batch_no', 'item_name', 'pcs_per_box'], 'open line');
  const b = ok(await call('GET', '/reports/book/debit'), 'debit book');
  has(b, ['rows', 'totals'], 'debit book');
});
await check('items/:id/batches is a list of batches', async () => {
  const b = ok(await call('GET', `/items/${stocked.id}/batches`), 'batches');
  if (!Array.isArray(b)) throw new Error('not a list');
});

console.log('E-way bill and WhatsApp');
// the demo books have no sale bill: one is made (it also shows in the All bills screenshot)
await check('a sale bill can be made', async () => {
  const c = customers.find((x) => String(x.phone || x.mobiles || '').replace(/\D/g, '').length >= 10) || customers[0];
  has(ok(await call('POST', '/invoices', { party_id: c.id, lines: [{ item_id: stocked.id, qty: 2 }] }), 'invoice'), ['id'], 'invoice');
});
const bills = ok(await call('GET', '/bills?type=SALE&from=2000-01-01&to=2100-12-31'), 'bills');
const sale = bills.rows.find((r) => r.type === 'SALE');
await check('e-way bill details for a sale', async () => {
  if (!sale) throw new Error('the demo books have no sale bill');
  const e = ok(await call('GET', `/invoices/${sale.id}/ewaybill`), 'ewaybill');
  has(e, ['invoice_no', 'party', 'total', 'needed', 'from_pincode', 'to_pincode', 'distance', 'mode', 'vehicle_no', 'ewb_no'], 'ewaybill');
  const r = await call('POST', `/invoices/${sale.id}/ewaybill`, { distance: '12', mode: 1, vehicle_no: 'UP15AB1234', preview: true });
  // the demo company may lack a GSTIN or HSN codes: then a readable 400, which the dialog shows
  if (r.status === 200) has(r.json, ['file_name', 'warnings', 'ewaybill'], 'ewaybill file');
  else if (r.status !== 400 || !r.json?.error) throw new Error(`HTTP ${r.status}`);
});
await check('a bill has the party phone fields WhatsApp reads', async () => {
  const inv = ok(await call('GET', `/invoices/${sale.id}`), 'invoice');
  has(inv, ['invoice_no', 'total', 'party_name', 'party_phone', 'party_mobiles'], 'invoice');
});

console.log('Salesmen');
await check('edit keeps the salesman, merge and delete answer', async () => {
  const sms = ok(await call('GET', '/salesmen'), 'salesmen');
  const a = ok(await call('POST', '/salesmen', { name: 'CI Merge From', phone: '', monthly_target: 0 }), 'add');
  const b = ok(await call('POST', '/salesmen', { name: 'CI Merge Into', phone: '', monthly_target: 0 }), 'add');
  ok(await call('PUT', `/salesmen/${a.id}`, { name: 'CI Merge From', phone: '9000000000', monthly_target: '5000', active: true }), 'edit');
  const m = ok(await call('POST', `/salesmen/${a.id}/merge`, { into: b.id }), 'merge');
  has(m, ['moved'], 'merge');
  ok(await call('DELETE', `/salesmen/${b.id}`), 'delete');
  if (!Array.isArray(sms)) throw new Error('salesmen not a list');
});

console.log('Reports');
await check('profit', async () => has(ok(await call('GET', '/reports/profit'), 'profit'), ['revenue', 'cost', 'profit', 'margin_pct', 'unknown_cost_lines'], 'profit'));
await check('outstanding', async () => {
  const o = ok(await call('GET', '/reports/outstanding'), 'outstanding');
  if (o.length) has(o[0], ['name', 'type', 'route_name', 'phone', 'credit_limit', 'balance'], 'outstanding row');
});
await check('expiry', async () => {
  const x = ok(await call('GET', '/reports/expiry?days=180'), 'expiry');
  if (x.length) has(x[0], ['item_name', 'batch_no', 'exp_date', 'days_left', 'qty', 'stock_value'], 'expiry row');
});

console.log('Payments from a list');
await check('parse a list and save it', async () => {
  const c = customers[0];
  const p = ok(await call('POST', '/receipts/sheet/parse', { text: `${c.name} 150` }), 'parse');
  has(p, ['rows', 'lines', 'ready', 'total'], 'parse');
  has(p.rows[0], ['text', 'party_id', 'candidates', 'bills', 'amount', 'reference', 'problems'], 'parse row');
  const s = ok(await call('POST', '/receipts/sheet', { mode: 'CASH', rows: [{ party_id: c.id, amount: 150, reference: p.rows[0].reference }] }), 'save');
  has(s, ['count', 'total', 'saved'], 'save');
});

console.log('Stock tools');
await check('set stock, mrp table, set-prices preview, clean preview, auto-pack', async () => {
  const it = items[items.length - 1];
  has(ok(await call('POST', `/items/${it.id}/set-stock`, { qty: Math.max(0, Math.round(Number(it.stock))) }), 'set-stock'), ['stock'], 'set-stock');
  const mt = ok(await call('GET', '/items/mrp-table'), 'mrp-table');
  if (mt.length) {
    has(mt[0], ['mrp', 'items', 'boxes', 'retail_box', 'wholesale_box', 'retail_piece', 'wholesale_piece'], 'mrp-table row');
    const sp = ok(await call('POST', '/items/set-prices', { mode: 'table', per: 'box', include_gst: true, tiers: [{ mrp: mt[0].mrp, retail: Number(mt[0].retail_box) || 100 }], preview: true }), 'set-prices');
    has(sp, ['would_update', 'items'], 'set-prices');
  }
  const cp = ok(await call('GET', '/items/clean-preview?case=keep&match=similar'), 'clean-preview');
  has(cp, ['items', 'renames', 'groups'], 'clean-preview');
  has(ok(await call('POST', '/items/auto-pack', {}), 'auto-pack'), ['checked', 'changed'], 'auto-pack');
});
await check('merge two items', async () => {
  const a = ok(await call('POST', '/items', { name: 'CI Duplicate Soap 100g', gst_rate: 18, mrp: 40 }), 'add');
  const b = ok(await call('POST', '/items', { name: 'CI Duplicate Soap 100 g', gst_rate: 18, mrp: 40 }), 'add');
  const m = ok(await call('POST', '/items/merge', { keep_id: a.id, merge_ids: [b.id] }), 'merge');
  has(m, ['kept', 'name', 'merged', 'moved'], 'merge');
});
await check('items from a pasted list, then bulk add', async () => {
  const x = ok(await call('POST', '/items/online/extract', { text: 'CI Pasted Shampoo 180ml MRP 120\nCI Pasted Talc 100g MRP 85', case: 'title' }), 'extract');
  has(x, ['items', 'found', 'new'], 'extract');
  const add = ok(await call('POST', '/items/bulk-add', { items: [{ name: 'CI Bulk Item One', mrp: 10 }], gst_rate: 18 }), 'bulk-add');
  has(add, ['added', 'skipped'], 'bulk-add');
});

console.log('Marg import');
await check('a folder that is not a Marg backup gets a readable answer', async () => {
  const r = await call('POST', '/import/marg/preview', { path: '/tmp' });
  if (r.status !== 400 || !r.json?.error) throw new Error(`HTTP ${r.status}`);
});

console.log('A new year\'s books');
await check('carried-forward year file, then back to the main books', async () => {
  const cs = ok(await call('GET', '/companies'), 'companies');
  const main = cs.companies.find((c) => !c.fy) || cs.companies[0];
  const y = ok(await call('POST', `/companies/${main.id}/years`, { fy: '2030-31', carry: true }), 'years');
  has(y, ['id', 'name', 'fy', 'carried'], 'years');
  const again = await call('POST', `/companies/${main.id}/years`, { fy: '2030-31', carry: true });
  if (again.status !== 409 || again.json?.code !== 'YEAR_EXISTS') throw new Error(`second time: HTTP ${again.status} ${again.json?.code}`);
  ok(await call('POST', `/companies/${main.id}/activate`, {}), 'activate');
});

console.log('Error replies');
await check('errors carry message and code', async () => {
  const r = await call('GET', '/debit-notes/999999');
  if (r.status !== 404) throw new Error(`HTTP ${r.status}`);
  has(r.json, ['error', 'message', 'code'], 'error');
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
