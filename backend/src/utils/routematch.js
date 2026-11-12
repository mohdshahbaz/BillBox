/**
 * Auto-assign outlets to routes. A route's name lists its places, separated by commas ("Qazipara, Mandi, Mandawar Road";
 * ; / & + | separate too). A customer goes on every route that has one of its places written in the customer's name or
 * address: whole words, case and punctuation ignored, a place of several words as that run of words ("Mandawar Road"
 * is in "12 Mandawar Road, Bijnor", not in "Mandawar" or "Station Road"). So one customer can get several routes.
 * ROUTE, BEAT and weekday words in a place are ignored ("Civil Lines Beat" is the place "Civil Lines"); a place that is
 * only a common word (ROAD, MARKET, NEAR…) or under 3 letters is not used.
 * Ported to ios/BillBoxCore/Sources/BillBoxCore/PartiesAPI.swift (autoAssignRoutes).
 */
const { addPartyRoute } = require('./partyroutes');
const FILLER = new Set(['ROUTE', 'ROUTES', 'BEAT', 'MON', 'TUE', 'TUES', 'WED', 'THU', 'THUR', 'THURS', 'FRI', 'SAT', 'SUN',
  'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']);
const GENERIC = new Set(['ROAD', 'NAGAR', 'MARG', 'CHOWK', 'CHAURAHA', 'BAZAR', 'BAZAAR', 'MARKET', 'COLONY', 'STREET',
  'NEAR', 'MAIN', 'GALI', 'LANE', 'SECTOR', 'AREA', 'SIDE', 'THE', 'AND', 'OPP', 'OPPOSITE', 'BEHIND', 'SHOP', 'STORE', 'STORES']);   // not MANDI: beats are named after it
const words = (s) => String(s || '').toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim().split(' ').filter(Boolean);

/** A place as " A B " (ROUTE / BEAT / weekdays dropped); null if under 3 letters or only one common word. */
function routeKey(name) {
  const all = words(name);
  const kept = all.filter((w) => !FILLER.has(w));
  const list = kept.length ? kept : all;
  const k = list.join(' ');
  if (k.length < 3 || (list.length === 1 && GENERIC.has(list[0]))) return null;
  return ` ${k} `;
}
/** Every place a route lists: "Khajrana, New Palasia / Rajwada" → [" KHAJRANA ", " NEW PALASIA ", " RAJWADA "]. */
const routeKeys = (name) => [...new Set(String(name || '').split(/[,;/&+|]+/).map(routeKey).filter(Boolean))];

/**
 * {matches: [{party_id, party_name, address, route_id, route_name}], unmatched, assigned}: one match per customer and
 * route it is not on yet (a customer can be in several). unmatched = customers with no route and no match.
 * apply → adds the routes: only `assignments` [{party_id, route_id}] when given, else only `party_ids` when given, else all.
 * (choices and unclear stay in the reply, empty, for apps that still read them.)
 */
function autoAssignRoutes(db, { apply = false, party_ids, assignments } = {}) {
  const routes = db.prepare('SELECT id, name FROM routes ORDER BY name, id').all()
    .map((r) => ({ id: Number(r.id), name: r.name, keys: routeKeys(r.name) })).filter((r) => r.keys.length);
  const parties = db.prepare("SELECT id, name, address, route_id FROM parties WHERE active=1 AND type <> 'SUPPLIER' ORDER BY name, id").all();
  const on = new Map();   // party → routes it is on
  for (const x of db.prepare('SELECT party_id, route_id FROM party_routes').all()) {
    if (!on.has(Number(x.party_id))) on.set(Number(x.party_id), new Set());
    on.get(Number(x.party_id)).add(Number(x.route_id));
  }
  const only = Array.isArray(party_ids) ? new Set(party_ids.map(Number)) : null;
  const matches = [];
  let unmatched = 0;
  for (const p of parties) {
    if (only && !only.has(Number(p.id))) continue;
    const has = on.get(Number(p.id)) || new Set();
    if (p.route_id != null) has.add(Number(p.route_id));
    const text = ` ${words(p.name).join(' ')} | ${words(p.address).join(' ')} `;
    let n = 0;
    for (const r of routes) {
      if (has.has(r.id) || !r.keys.some((k) => text.includes(k))) continue;
      matches.push({ party_id: p.id, party_name: p.name, address: p.address || '', route_id: r.id, route_name: r.name });
      n++;
    }
    if (!n && !has.size) unmatched++;
  }
  let assigned = 0;
  if (apply) {
    const ok = new Set(db.prepare('SELECT id FROM routes').all().map((r) => Number(r.id)));
    const pairs = Array.isArray(assignments)
      ? assignments.map((a) => ({ party_id: Number(a && a.party_id), route_id: Number(a && a.route_id) })).filter((a) => a.party_id > 0 && ok.has(a.route_id))
      : matches;
    const live = db.prepare("SELECT 1 x FROM parties WHERE id=? AND active=1 AND type <> 'SUPPLIER'");
    db.transaction(() => { for (const m of pairs) if (live.get(m.party_id) && addPartyRoute(db, m.party_id, m.route_id)) assigned++; })();
  }
  return { matches, choices: [], unclear: 0, unmatched, assigned };
}

module.exports = { autoAssignRoutes, routeKey, routeKeys };
