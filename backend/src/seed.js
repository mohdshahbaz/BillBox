const db = require('./db');
const companyId = Number(process.argv[2]) || db.firstCompanyId();
const { today } = require('./utils/misc');

db.withCompany(companyId, () => {
if (db.prepare('SELECT COUNT(*) n FROM items').get().n > 0) { console.log('This company already has data; skipping seed.'); return; }

const plus = (days) => { const d = new Date(); d.setDate(d.getDate() + days); return d.toLocaleDateString('en-CA'); };
const run = (sql, ...a) => Number(db.prepare(sql).run(...a).lastInsertRowid);

db.transaction(() => {
  const cat = {};
  for (const c of ['Beverages', 'Packaged Foods', 'Personal Care', 'Home Care']) cat[c] = run('INSERT INTO categories(name) VALUES(?)', c);

  // sku, barcode, name, category, hsn, gst, mrp, retail, wholesale, purchase, reorder
  const items = [
    ['BEV001', '8901000000011', 'Cola 750ml', 'Beverages', '2202', 28, 40, 29.5, 28, 25, 48],
    ['BEV002', '8901000000028', 'Orange Juice 1L', 'Beverages', '2009', 12, 110, 88, 84, 76, 24],
    ['BEV003', '8901000000035', 'Packaged Water 1L', 'Beverages', '2201', 18, 20, 14.8, 14, 12, 120],
    ['FOD001', '8901000000042', 'Instant Noodles 70g', 'Packaged Foods', '1902', 18, 14, 10.2, 9.8, 8.6, 200],
    ['FOD002', '8901000000059', 'Salted Biscuits 200g', 'Packaged Foods', '1905', 18, 30, 22.5, 21.5, 19, 100],
    ['FOD003', '8901000000066', 'Basmati Rice 5kg', 'Packaged Foods', '1006', 5, 650, 560, 545, 520, 20],
    ['FOD004', '8901000000073', 'Refined Oil 1L', 'Packaged Foods', '1512', 5, 165, 148, 145, 140, 36],
    ['PRC001', '8901000000080', 'Toothpaste 150g', 'Personal Care', '3306', 18, 95, 70, 67, 60, 60],
    ['PRC002', '8901000000097', 'Bathing Soap 100g', 'Personal Care', '3401', 18, 40, 29, 27.5, 24, 120],
    ['PRC003', '8901000000103', 'Shampoo Sachet 6ml', 'Personal Care', '3305', 18, 2, 1.4, 1.3, 1.1, 1000],
    ['HOM001', '8901000000110', 'Detergent Powder 1kg', 'Home Care', '3402', 18, 135, 105, 100, 90, 40],
    ['HOM002', '8901000000127', 'Dishwash Liquid 500ml', 'Home Care', '3402', 18, 115, 88, 84, 74, 30],
  ];
  const id = {};
  for (const [sku, bc, name, c, hsn, gst, mrp, rt, ws, pp, rl] of items)
    id[sku] = run(`INSERT INTO items(name,category_id,hsn,gst_rate,mrp,retail_price,wholesale_price,purchase_price)
                   VALUES(?,?,?,?,?,?,?,?)`, name, cat[c], hsn, gst, mrp, rt, ws, pp);

  const bt = (sku, no, mfgAgo, expIn, qty) => run(
    'INSERT INTO batches(item_id,batch_no,mfg_date,exp_date,qty,purchase_price) VALUES(?,?,?,?,?,(SELECT purchase_price FROM items WHERE id=?))',
    id[sku], no, plus(-mfgAgo), plus(expIn), qty, id[sku]);
  bt('BEV001', 'CL-2406', 120, 60, 96);  bt('BEV001', 'CL-2410', 20, 240, 240);
  bt('BEV002', 'OJ-2409', 40, 20, 36);   bt('BEV002', 'OJ-2410', 10, 170, 60);
  bt('BEV003', 'WT-2410', 15, 330, 480);
  bt('FOD001', 'NN-2408', 60, 25, 120);  bt('FOD001', 'NN-2410', 12, 200, 600);
  bt('FOD002', 'SB-2409', 45, 70, 150);
  bt('FOD003', 'RC-2407', 90, 270, 40);
  bt('FOD004', 'RO-2409', 50, 300, 72);
  bt('PRC001', 'TP-2407', 100, 500, 90); bt('PRC002', 'SP-2408', 80, 600, 200);
  bt('PRC003', 'SH-2409', 30, 400, 2000);
  bt('HOM001', 'DT-2408', 70, 450, 80);  bt('HOM002', 'DW-2409', 40, 380, 8);

  // Schemes: Buy 10 get 1 free on noodles; 5% off on 12+ colas; 3% off on 6+ detergent
  run("INSERT INTO schemes(item_id,type,buy_qty,free_qty) VALUES(?,'FREE_QTY',10,1)", id.FOD001);
  run("INSERT INTO schemes(item_id,type,buy_qty,percent) VALUES(?,'PERCENT',12,5)", id.BEV001);
  run("INSERT INTO schemes(item_id,type,buy_qty,percent) VALUES(?,'PERCENT',6,3)", id.HOM001);

  const s1 = run("INSERT INTO salesmen(name,phone,monthly_target) VALUES('Rahul Verma','9810000001',250000)");
  const s2 = run("INSERT INTO salesmen(name,phone,monthly_target) VALUES('Imran Khan','9810000002',180000)");
  const r1 = run('INSERT INTO routes(name,salesman_id,day_of_week) VALUES(?,?,?)', 'Civil Lines Beat', s1, 1);
  const r2_ = run('INSERT INTO routes(name,salesman_id,day_of_week) VALUES(?,?,?)', 'Nagina Road Beat', s2, 1);
  const r3 = run('INSERT INTO routes(name,salesman_id,day_of_week) VALUES(?,?,?)', 'Station Market Beat', s1, 3);

  const party = (name, gstin, st, tier, limit, route, opening) => {
    const p = run('INSERT INTO parties(name,gstin,state_code,phone,address,type,price_tier,credit_limit,credit_days,route_id) VALUES(?,?,?,?,?,?,?,?,?,?)',
      name, gstin, st, '98' + Math.floor(10000000 + Math.random() * 89999999), 'Bijnor', tier === 'WHOLESALE' ? 'WHOLESALER' : 'RETAILER', tier, limit, 15, route);
    if (opening) run("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,'OPENING','OPENING',?,0,'Opening balance')", p, today(), opening);
  };
  party('Gupta General Store', '09AAAPG1111A1Z1', '09', 'RETAIL', 25000, r1, 4200);
  party('Singh Kirana', null, '09', 'RETAIL', 15000, r1, 0);
  party('City Mart Wholesale', '09AAACC2222B1Z2', '09', 'WHOLESALE', 100000, r2_, 18500);
  party('Delhi Traders', '07AAADT3333C1Z3', '07', 'WHOLESALE', 150000, r3, 0);
  run("INSERT INTO parties(name,gstin,state_code,phone,address,type,price_tier) VALUES('Hind Beverages Pvt Ltd','09AAACH5555D1Z5','09','9810000099','Meerut','SUPPLIER','WHOLESALE')");
  run("INSERT INTO parties(name,gstin,state_code,phone,address,type,price_tier) VALUES('Northern FMCG Agencies','07AAACN6666E1Z6','07','9810000098','Delhi','SUPPLIER','WHOLESALE')");

  // Dual-unit billing: pieces per box
  for (const [sku, n] of [['BEV001', 24], ['BEV002', 12], ['BEV003', 12], ['FOD001', 48], ['FOD002', 36], ['FOD003', 4], ['FOD004', 12],
                          ['PRC001', 72], ['PRC002', 96], ['PRC003', 1000], ['HOM001', 20], ['HOM002', 24]])
    db.prepare('UPDATE items SET pcs_per_box=? WHERE id=?').run(n, id[sku]);
})();

console.log('Seeded demo data. Company state code = 09 (Uttar Pradesh); "Delhi Traders" (07) gets IGST.');
});
