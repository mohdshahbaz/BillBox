// Routes of a party (several) and auto-assign by the places in a route's name: node test/route_match.js
const os = require('os'), fs = require('fs'), path = require('path'), assert = require('assert');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'routematch-'));
const db = require('../src/db');
const { autoAssignRoutes, routeKey, routeKeys } = require('../src/utils/routematch');
const { setPartyRoutes, partyRoutes, addPartyRoute, idList } = require('../src/utils/partyroutes');
let passed = 0;
const ok = (name, fn) => { db.withCompany(db.firstCompanyId(), fn); passed++; console.log('  ok  ', name); };
const route = (name) => Number(db.prepare('INSERT INTO routes(name) VALUES(?)').run(name).lastInsertRowid);
const party = (name, address, type = 'RETAILER', route_id = null) =>
  Number(db.prepare('INSERT INTO parties(name,address,type,route_id) VALUES(?,?,?,?)').run(name, address, type, route_id).lastInsertRowid);
const routesOf = (id) => partyRoutes(db, id);
const clear = () => { db.exec('DELETE FROM party_routes; UPDATE parties SET active=0, route_id=NULL; DELETE FROM routes'); };

// the endpoints, with express stubbed (as test/smoke.js does)
const Module = require('module'); const recorded = [];
const fake = () => { const r = {}; for (const m of ['get', 'post', 'put', 'delete', 'use']) r[m] = (pth, ...hs) => { recorded.push({ m, pth, h: hs[hs.length - 1] }); return r; }; return r; };
const orig = Module._load;
Module._load = function (rq, ...a) { if (rq === 'express') { const e = () => fake(); e.Router = fake; e.json = () => () => {}; return e; } return orig.call(this, rq, ...a); };
try { for (const r of ['parties', 'salesmen', 'reports']) require('../src/routes/' + r); } finally { Module._load = orig; }
const call = (m, pth, o = {}) => {
  const l = recorded.filter((x) => x.m === m && x.pth === pth).pop(); assert.ok(l, pth + ' route');
  let out; const res = { json: (v) => { out = v; return res; }, status() { return res; } };
  l.h({ body: o.body || {}, query: o.query || {}, params: o.params || {} }, res, (e) => { throw e; });
  return out;
};

ok('places of a route: split at commas, ROUTE / BEAT / weekdays dropped, a lone common word or a short one not used', () => {
  assert.deepStrictEqual(routeKeys('Qazipara, Mandi, Bairaj Road, Mandawar Road'), [' QAZIPARA ', ' MANDI ', ' BAIRAJ ROAD ', ' MANDAWAR ROAD ']);
  assert.deepStrictEqual(routeKeys('Khajrana, New Palasia / Rajwada'), [' KHAJRANA ', ' NEW PALASIA ', ' RAJWADA ']);
  assert.strictEqual(routeKey('Khajrana Route (Mon)'), ' KHAJRANA ');
  assert.strictEqual(routeKey('MONDAY BEAT - New Palasia'), ' NEW PALASIA ');
  assert.strictEqual(routeKey('A1'), null);
  assert.deepStrictEqual(routeKeys('Road, Main Market, Market, Qazipara, qazipara'), [' MAIN MARKET ', ' QAZIPARA ']);
  assert.deepStrictEqual(idList('3, 7,3,x,0'), [3, 7]); assert.deepStrictEqual(idList([4, '5']), [4, 5]); assert.deepStrictEqual(idList(null), []);
});

ok('a customer goes on every route listing a place found in its name or address (whole words, whole place)', () => {
  const r1 = route('Qazipara, Mandi, Bairaj Road, Mandawar Road'), r2 = route('Qazipara, Mandi, Mandawar Road'), r3 = route('Civil Lines Beat (Mon)');
  const a = party('A-One National Dairy', 'Qazipara, BIJNOR');
  const b = party('A-One Traders', 'Sabzi Mandi, Bijnor');
  const c = party('ARUN GENERAL STORE', 'MANDAWAR ROAD, BIJNOR');
  const d = party('BAIRAJ KIRANA', 'Station Road');                 // "Bairaj" and "Road" apart are not the place "Bairaj Road"
  const e = party('QAZIPARAWALA STORE', 'Mandawar');                // inside a word / half a place: no match
  const f = party('GUPTA STORE', 'Near Civil Lines, Bijnor');
  const g = party('SUPPLIER QAZIPARA', '', 'SUPPLIER');
  const h = party('RAM STORE', '4 bairaj   road');
  const prev = autoAssignRoutes(db, {});
  const got = {}; for (const m of prev.matches) (got[m.party_id] = got[m.party_id] || []).push(m.route_id);
  assert.deepStrictEqual(got, { [a]: [r1, r2], [b]: [r1, r2], [c]: [r1, r2], [f]: [r3], [h]: [r1] });
  assert.strictEqual(prev.unmatched, 2); assert.strictEqual(prev.assigned, 0); assert.deepStrictEqual(prev.choices, []);
  assert.deepStrictEqual(routesOf(a), [], 'a preview changes nothing');
  assert.ok(prev.matches[0].party_name && prev.matches[0].route_name && 'address' in prev.matches[0]);

  // only the ticked pairs
  assert.strictEqual(autoAssignRoutes(db, { apply: true, assignments: [{ party_id: a, route_id: r2 }, { party_id: a, route_id: 9999 }, { party_id: g, route_id: 0 }] }).assigned, 1);
  assert.deepStrictEqual(routesOf(a), [r2]);
  // only some parties
  assert.strictEqual(autoAssignRoutes(db, { apply: true, party_ids: [b] }).assigned, 2);
  assert.deepStrictEqual(routesOf(b), [r1, r2]);
  // the rest: a already on r2 gets r1 too
  const rest = autoAssignRoutes(db, { apply: true });
  assert.strictEqual(rest.assigned, 5);
  assert.deepStrictEqual(routesOf(a), [r2, r1]); assert.deepStrictEqual(routesOf(c), [r1, r2]); assert.deepStrictEqual(routesOf(h), [r1]);
  assert.deepStrictEqual(routesOf(d), []); assert.deepStrictEqual(routesOf(e), []); assert.deepStrictEqual(routesOf(g), []);
  const again = autoAssignRoutes(db, { apply: true });
  assert.strictEqual(again.matches.length, 0); assert.strictEqual(again.assigned, 0); assert.strictEqual(again.unmatched, 2);
  assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM party_routes').get().n, 3, 'the first route sits in parties.route_id, the others in party_routes');
});

ok('saving a party: route_ids sets all its routes, route_id alone changes the first, new_route is added', () => {
  clear();
  const r1 = route('North'), r2 = route('South'), r3 = route('East');
  const id = call('post', '/parties', { body: { name: 'Multi Store', route_ids: [r2, r1, r2, 9999] } }).id;
  assert.deepStrictEqual(routesOf(id), [r2, r1]);
  const row = () => call('get', '/parties', { query: { q: 'Multi Store' } })[0];
  assert.strictEqual(row().route_ids, `${r1},${r2}`); assert.strictEqual(row().route_name, 'North; South'); assert.strictEqual(row().route_id, r2);
  call('put', '/parties/:id', { params: { id }, body: { name: 'Multi Store', route_ids: `${r1},${r3}` } });
  assert.deepStrictEqual(routesOf(id), [r1, r3]);
  call('put', '/parties/:id', { params: { id }, body: { name: 'Multi Store' } });                 // routes not sent: kept
  assert.deepStrictEqual(routesOf(id), [r1, r3]);
  call('put', '/parties/:id', { params: { id }, body: { name: 'Multi Store', route_id: r2 } });   // an older app: the first changes
  assert.deepStrictEqual(routesOf(id), [r2, r3]);
  call('put', '/parties/:id', { params: { id }, body: { name: 'Multi Store', route_ids: [r3], new_route: { name: 'West' } } });
  const west = db.prepare("SELECT id FROM routes WHERE name='West'").get().id;
  assert.deepStrictEqual(routesOf(id), [r3, west]);
  call('put', '/parties/:id', { params: { id }, body: { name: 'Multi Store', route_ids: [] } });
  assert.deepStrictEqual(routesOf(id), []); assert.strictEqual(row().route_ids, null);
  const one = call('post', '/parties', { body: { name: 'Single Store', route_id: r1 } }).id;
  assert.deepStrictEqual(routesOf(one), [r1]);
  assert.strictEqual(addPartyRoute(db, one, r1), false); assert.strictEqual(addPartyRoute(db, one, r2), true); assert.strictEqual(addPartyRoute(db, one, r2), false);
  assert.deepStrictEqual(setPartyRoutes(db, one, [r2]), [r2]); assert.deepStrictEqual(routesOf(one), [r2]);
});

ok('outlet counts, the beat plan and deleting a route follow every route of a party', () => {
  clear();
  const sm = Number(db.prepare("INSERT INTO salesmen(name) VALUES('Ravi')").run().lastInsertRowid);
  const mk = (name) => Number(db.prepare("INSERT INTO routes(name,salesman_id,day_of_week,days) VALUES(?,?,1,'1')").run(name, sm).lastInsertRowid);
  const r1 = mk('Alpha'), r2 = mk('Beta');
  const a = call('post', '/parties', { body: { name: 'Both Routes', route_ids: [r1, r2] } }).id;
  const b = call('post', '/parties', { body: { name: 'Beta Only', route_ids: [r2] } }).id;
  const outlets = () => Object.fromEntries(call('get', '/routes').map((r) => [r.id, r.outlets]));
  assert.deepStrictEqual(outlets(), { [r1]: 1, [r2]: 2 });
  const beat = call('get', '/salesmen/:id/beat', { params: { id: sm }, query: { day: '1' } });
  assert.deepStrictEqual(beat.outlets.map((o) => [o.name, o.route_name]), [['Both Routes', 'Alpha; Beta'], ['Beta Only', 'Beta']]);   // once, though on two routes of the day
  call('delete', '/routes/:id', { params: { id: r1 } });
  assert.deepStrictEqual(routesOf(a), [r2], 'its other route becomes the first'); assert.deepStrictEqual(routesOf(b), [r2]);
  assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM party_routes').get().n, 0);
  call('delete', '/routes/:id', { params: { id: r2 } });
  assert.deepStrictEqual(routesOf(a), []); assert.deepStrictEqual(routesOf(b), []);
  const r3 = mk('Gamma'), r4 = mk('Delta');
  const c = call('post', '/parties', { body: { name: 'Unused Party', route_ids: [r3, r4] } }).id;
  assert.strictEqual(call('delete', '/parties/:id', { params: { id: c } }).result, 'deleted');
  assert.strictEqual(db.prepare('SELECT COUNT(*) n FROM party_routes').get().n, 0);
});

ok('editing a route: name (trimmed), salesman and days change; its outlets stay; a blank name is refused', () => {
  clear();
  const sm = Number(db.prepare("INSERT INTO salesmen(name) VALUES('Edit Sm')").run().lastInsertRowid);
  const r = Number(db.prepare("INSERT INTO routes(name,days,day_of_week) VALUES('Old Name','1',1)").run().lastInsertRowid);
  const p = call('post', '/parties', { body: { name: 'Edit Route Store', route_ids: [r] } }).id;
  call('put', '/routes/:id', { params: { id: r }, body: { name: '  New Name ', salesman_id: sm, days: [3, 5] } });
  const row = () => db.prepare('SELECT * FROM routes WHERE id=?').get(r);
  assert.deepStrictEqual([row().name, row().salesman_id, row().days, row().day_of_week], ['New Name', sm, '3,5', 3]);
  assert.deepStrictEqual(routesOf(p), [r]);
  assert.throws(() => call('put', '/routes/:id', { params: { id: r }, body: { name: '  ' } }), /Route name is required/);
  call('put', '/routes/:id', { params: { id: r }, body: { salesman_id: '' } });
  assert.deepStrictEqual([row().name, row().salesman_id, row().days], ['New Name', null, '3,5']);
});

console.log(`\n${passed} route tests passed`);
