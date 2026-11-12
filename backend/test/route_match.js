// Auto-assign outlets to routes by the party's name and address: node test/route_match.js
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'routematch-'));
const db = require('../src/db');
const { autoAssignRoutes, routeKey, routeKeys, placeWords } = require('../src/utils/routematch');
let passed = 0;
const ok = (name, fn) => { db.withCompany(db.firstCompanyId(), fn); passed++; console.log('  ok  ', name); };
const route = (name) => Number(db.prepare('INSERT INTO routes(name) VALUES(?)').run(name).lastInsertRowid);
const party = (name, address, type = 'RETAILER', route_id = null) =>
  Number(db.prepare('INSERT INTO parties(name,address,type,route_id) VALUES(?,?,?,?)').run(name, address, type, route_id).lastInsertRowid);
const routeOf = (id) => db.prepare('SELECT route_id FROM parties WHERE id=?').get(id).route_id;

ok('route words: ROUTE, BEAT, weekdays, ROAD, NAGAR… and short or digit-only words are not used', () => {
  assert.deepStrictEqual(placeWords('Civil Lines Route (Mon)'), ['CIVIL', 'LINES']);
  assert.deepStrictEqual(placeWords('Main Road Sector 4'), []);
  assert.strictEqual(routeKey('Khajrana Route (Mon)'), ' KHAJRANA ');
  assert.strictEqual(routeKey('MONDAY BEAT - New Palasia'), ' NEW PALASIA ');
  assert.strictEqual(routeKey('A1'), null);
});
ok('whole words in name or address; the longer whole route name breaks a tie; suppliers and assigned parties left alone', () => {
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
  assert.strictEqual(autoAssignRoutes(db, { apply: true, party_ids: [a, c] }).assigned, 2);
  assert.strictEqual(routeOf(a), kh); assert.strictEqual(routeOf(c), npal); assert.strictEqual(routeOf(b), null);
  assert.strictEqual(routeOf(f), null); assert.strictEqual(routeOf(g), mhow);
  assert.strictEqual(autoAssignRoutes(db, { apply: true }).assigned, 2, 'the rest');
  assert.strictEqual(routeOf(b), kh); assert.strictEqual(routeOf(d), pal);
});
ok('any word of the route counts; the name counts before the address; ROAD alone does not', () => {
  const ng = route('Nagina Road'), cl = route('Civil Lines Beat');
  const n = party('NAGINA ROAD AGENCY', 'near Civil Lines');            // name beats address
  const both = party('PATEL STORES', 'Nagina Road, near Civil Lines');   // address: Civil + Lines beat Nagina
  const one = party('GUPTA MEDICAL', 'Opp. Civil Hospital');             // one word is enough
  const road = party('YADAV DAIRY', 'Station Road');
  autoAssignRoutes(db, { apply: true });
  assert.strictEqual(routeOf(n), ng); assert.strictEqual(routeOf(both), cl); assert.strictEqual(routeOf(one), cl); assert.strictEqual(routeOf(road), null);
});
ok('a beat listing several places, comma separated: each place counts', () => {
  assert.deepStrictEqual(routeKeys('Mon - Sukhliya, New Palasia / Vijay Nagar & A1'), [' SUKHLIYA ', ' NEW PALASIA ', ' VIJAY NAGAR ']);
  const a = route('Sukhliya, New Rani Bagh, Vijay Nagar'), b = route('Rani Bagh, Bhawarkua');
  const p1 = party('SAINI KIRANA', 'Sukhliya main road');
  const p2 = party('RAO STORE', 'Vijay Nagar sq.');
  const p3 = party('AHUJA MART', '5 New Rani Bagh');                // A: NEW RANI BAGH beats B: RANI BAGH
  const p4 = party('KHAN GENERAL', 'Rani Bagh');                    // level on words; B lists Rani Bagh whole
  const p5 = party('DUBEY DAIRY', 'Bhawarkua');
  autoAssignRoutes(db, { apply: true });
  assert.deepStrictEqual([p1, p2, p3, p4, p5].map(routeOf), [a, a, a, b, b]);
});
ok('two beats level on every rule: listed as a choice, the owner picks', () => {
  const r1 = route('Qazipara, Mandi, Mandawar Road'), r2 = route('Qazipara, Mandi, Bairaj Road, Mandawar Road');
  const p = party('A-One Trader', 'Sabzi Mandi, BIJNOR');            // MANDI counts (it names beats)
  const r = autoAssignRoutes(db, { apply: true });
  assert.strictEqual(r.unclear, 1); assert.strictEqual(routeOf(p), null);
  const c = r.choices.find((x) => x.party_id === p);
  assert.deepStrictEqual(c.routes.map((x) => x.route_id).sort(), [r1, r2].sort());
  const done = autoAssignRoutes(db, { apply: true, party_ids: [], assignments: [{ party_id: p, route_id: r2 }, { party_id: p, route_id: 9999 }] });
  assert.strictEqual(done.assigned, 1); assert.strictEqual(routeOf(p), r2);
});
console.log(`${passed} route matching checks passed`);
