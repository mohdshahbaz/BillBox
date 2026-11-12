// Auto-assign outlets to routes by the party's name and address: node test/route_match.js
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'routematch-'));
const db = require('../src/db');
const { autoAssignRoutes, routeKey } = require('../src/utils/routematch');
let passed = 0;
const ok = (name, fn) => { db.withCompany(db.firstCompanyId(), fn); passed++; console.log('  ok  ', name); };
const route = (name) => Number(db.prepare('INSERT INTO routes(name) VALUES(?)').run(name).lastInsertRowid);
const party = (name, address, type = 'RETAILER', route_id = null) =>
  Number(db.prepare('INSERT INTO parties(name,address,type,route_id) VALUES(?,?,?,?)').run(name, address, type, route_id).lastInsertRowid);
const routeOf = (id) => db.prepare('SELECT route_id FROM parties WHERE id=?').get(id).route_id;

ok('route names: filler words and weekdays ignored, too-short names skipped', () => {
  assert.strictEqual(routeKey('Khajrana Route (Mon)'), ' KHAJRANA ');
  assert.strictEqual(routeKey('MONDAY BEAT - New Palasia'), ' NEW PALASIA ');
  assert.strictEqual(routeKey('A1'), null);
  assert.strictEqual(routeKey('Route'), ' ROUTE ', 'a name made only of filler is kept as it is');
});
ok('matches by name or address, whole words, longest route wins; suppliers and assigned parties left alone', () => {
  const kh = route('KHAJRANA ROUTE'), pal = route('Palasia'), npal = route('New Palasia'), mhow = route('MHOW');
  const a = party('SHARMA STORE KHAJRANA', '');
  const b = party('GUPTA KIRANA', 'Shop 4, near temple, khajrana, Indore');
  const c = party('JAIN TRADERS', '12 New Palasia, Indore');
  const d = party('VERMA GENERAL', 'Palasia square');
  const e = party('MHOWKAR STORES', 'Rau');                     // MHOW only inside a word: no match
  const f = party('SUPPLIER KHAJRANA', '', 'SUPPLIER');
  const g = party('ALREADY SET KHAJRANA', '', 'RETAILER', mhow);
  const prev = autoAssignRoutes(db, {});
  const got = Object.fromEntries(prev.matches.map((m) => [m.party_id, m.route_id]));
  assert.deepStrictEqual(got, { [a]: kh, [b]: kh, [c]: npal, [d]: pal });
  assert.strictEqual(prev.unmatched, 1); assert.strictEqual(prev.assigned, 0);
  assert.strictEqual(routeOf(a), null, 'preview changes nothing');
  const done = autoAssignRoutes(db, { apply: true, party_ids: [a, c] });
  assert.strictEqual(done.assigned, 2);
  assert.strictEqual(routeOf(a), kh); assert.strictEqual(routeOf(c), npal); assert.strictEqual(routeOf(b), null);
  assert.strictEqual(routeOf(f), null); assert.strictEqual(routeOf(g), mhow);
  assert.strictEqual(autoAssignRoutes(db, { apply: true }).assigned, 2, 'the rest');
  assert.strictEqual(routeOf(b), kh); assert.strictEqual(routeOf(d), pal);
});
ok('two routes with the same name: unclear, skipped', () => {
  route('RAJWADA'); route('Rajwada');
  const p = party('SONI STORE', 'Rajwada');
  const r = autoAssignRoutes(db, { apply: true });
  assert.strictEqual(r.unclear, 1); assert.strictEqual(routeOf(p), null);
});
console.log(`${passed} route matching checks passed`);
