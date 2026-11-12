/**
 * Auto-assign outlets to routes: a party with no route gets the route that shares a word with the party's name or
 * address (whole words, case and punctuation ignored), so route "Civil Lines Beat" takes "Gupta Store, Civil Hospital".
 * A beat may list several places, "Khajrana, New Palasia / Rajwada": each place counts (split at , ; / & + |).
 * Words that say nothing about the place are not used: ROUTE, BEAT, weekdays, ROAD, NAGAR, MARKET, NEAR, MAIN… and
 * words under 3 letters or only digits.
 *
 * When several routes share words, the best is the one with
 *   1. more of its words in the party's name, then
 *   2. more of its words in the address, then
 *   3. one of its places written whole in the name or address, the longest such place first ("New Palasia" over "Palasia").
 * Routes still level after that are unclear: listed in `choices` with the level routes, for the owner to pick from;
 * the picks come back as `assignments: [{party_id, route_id}]`.
 * Ported to ios/BillBoxCore/Sources/BillBoxCore/PartiesAPI.swift (autoAssignRoutes).
 */
const FILLER = new Set(['ROUTE', 'ROUTES', 'BEAT', 'MON', 'TUE', 'TUES', 'WED', 'THU', 'THUR', 'THURS', 'FRI', 'SAT', 'SUN',
  'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']);
const GENERIC = new Set(['ROAD', 'NAGAR', 'MARG', 'CHOWK', 'CHAURAHA', 'BAZAR', 'BAZAAR', 'MARKET', 'COLONY', 'STREET',
  'NEAR', 'MAIN', 'GALI', 'LANE', 'SECTOR', 'AREA', 'SIDE', 'THE', 'AND', 'OPP', 'OPPOSITE', 'BEHIND', 'SHOP', 'STORE', 'STORES']);   // not MANDI: beats are named after it
const words = (s) => String(s || '').toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim().split(' ').filter(Boolean);
const placeWords = (name) => [...new Set(words(name).filter((w) => w.length >= 3 && !/^\d+$/.test(w) && !FILLER.has(w) && !GENERIC.has(w)))];

/** A place's whole name without ROUTE / BEAT / weekdays, as " A B " (for rule 3); null if under 3 letters. */
function routeKey(name) {
  const all = words(name);
  const kept = all.filter((w) => !FILLER.has(w));
  const k = (kept.length ? kept : all).join(' ');
  return k.length >= 3 ? ` ${k} ` : null;
}
/** Every place a beat lists: "Khajrana, New Palasia / Rajwada" → [" KHAJRANA ", " NEW PALASIA ", " RAJWADA "]. */
const routeKeys = (name) => String(name || '').split(/[,;/&+|]+/).map(routeKey).filter(Boolean);

/** {matches: [{party_id, party_name, address, route_id, route_name}], choices: [{party_id, party_name, address, routes: [{route_id,
 *  route_name}]}], unclear, unmatched}; apply → assigns the matches (only party_ids, when given) and the owner's assignments. */
function autoAssignRoutes(db, { apply = false, party_ids, assignments } = {}) {
  const routes = db.prepare('SELECT id, name FROM routes').all()
    .map((r) => ({ id: r.id, name: r.name, words: placeWords(r.name), keys: routeKeys(r.name) })).filter((r) => r.words.length);
  const parties = db.prepare("SELECT id, name, address FROM parties WHERE active=1 AND route_id IS NULL AND type <> 'SUPPLIER' ORDER BY name").all();
  const only = Array.isArray(party_ids) ? new Set(party_ids.map(Number)) : null;
  const matches = [], choices = [];
  let unclear = 0, unmatched = 0;
  for (const p of parties) {
    if (only && !only.has(Number(p.id))) continue;
    const nameW = new Set(words(p.name)), addrW = new Set(words(p.address));
    const text = ` ${words(p.name).join(' ')} | ${words(p.address).join(' ')} `;
    const scored = routes.map((r) => {
      const inName = r.words.filter((w) => nameW.has(w)).length;
      const inAddr = r.words.filter((w) => !nameW.has(w) && addrW.has(w)).length;
      return { r, s: [inName, inAddr, Math.max(0, ...r.keys.filter((k) => text.includes(k)).map((k) => k.length))] };
    }).filter((x) => x.s[0] + x.s[1] > 0);
    if (!scored.length) { unmatched++; continue; }
    const cmp = (a, b) => a.s[0] - b.s[0] || a.s[1] - b.s[1] || a.s[2] - b.s[2];
    scored.sort((a, b) => cmp(b, a));
    if (scored.length > 1 && cmp(scored[0], scored[1]) === 0) {
      unclear++;
      choices.push({ party_id: p.id, party_name: p.name, address: p.address || '',
        routes: scored.filter((x) => cmp(x, scored[0]) === 0).map((x) => ({ route_id: x.r.id, route_name: x.r.name })) });
      continue;
    }
    const best = scored[0].r;
    matches.push({ party_id: p.id, party_name: p.name, address: p.address || '', route_id: best.id, route_name: best.name });
  }
  let assigned = 0;
  if (apply) {
    const picks = (Array.isArray(assignments) ? assignments : [])
      .map((a) => ({ party_id: Number(a && a.party_id), route_id: Number(a && a.route_id) })).filter((a) => a.party_id > 0 && a.route_id > 0);
    const up = db.prepare('UPDATE parties SET route_id=@route_id WHERE id=@party_id AND route_id IS NULL AND active=1 AND EXISTS (SELECT 1 FROM routes WHERE id=@route_id)');
    db.transaction(() => { for (const m of [...matches, ...picks]) assigned += up.run({ route_id: m.route_id, party_id: m.party_id }).changes; })();
  }
  return { matches, choices, unclear, unmatched, assigned };
}

module.exports = { autoAssignRoutes, routeKey, routeKeys, placeWords };
