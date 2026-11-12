/**
 * Auto-assign outlets to routes: a party with no route gets the route that shares a word with the party's name or
 * address (whole words, case and punctuation ignored), so route "Civil Lines Beat" takes "Gupta Store, Civil Hospital".
 * Words that say nothing about the place are not used: ROUTE, BEAT, weekdays, ROAD, NAGAR, MARKET, NEAR, MAIN… and
 * words under 3 letters or only digits.
 *
 * When several routes share words, the best is the one with
 *   1. more of its words in the party's name, then
 *   2. more of its words in the address, then
 *   3. its whole name written in the name or address, the longest such name first ("New Palasia" over "Palasia").
 * Routes still level after that are skipped as unclear (the owner picks by hand).
 * Ported to ios/BillBoxCore/Sources/BillBoxCore/PartiesAPI.swift (autoAssignRoutes).
 */
const FILLER = new Set(['ROUTE', 'ROUTES', 'BEAT', 'MON', 'TUE', 'TUES', 'WED', 'THU', 'THUR', 'THURS', 'FRI', 'SAT', 'SUN',
  'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']);
const GENERIC = new Set(['ROAD', 'NAGAR', 'MARG', 'CHOWK', 'CHAURAHA', 'BAZAR', 'BAZAAR', 'MARKET', 'MANDI', 'COLONY', 'STREET',
  'NEAR', 'MAIN', 'GALI', 'LANE', 'SECTOR', 'AREA', 'SIDE', 'THE', 'AND', 'OPP', 'OPPOSITE', 'BEHIND', 'SHOP', 'STORE', 'STORES']);
const words = (s) => String(s || '').toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim().split(' ').filter(Boolean);
const placeWords = (name) => [...new Set(words(name).filter((w) => w.length >= 3 && !/^\d+$/.test(w) && !FILLER.has(w) && !GENERIC.has(w)))];

/** The route's whole name without ROUTE / BEAT / weekdays, as " A B " (for rule 3); null if under 3 letters. */
function routeKey(name) {
  const all = words(name);
  const kept = all.filter((w) => !FILLER.has(w));
  const k = (kept.length ? kept : all).join(' ');
  return k.length >= 3 ? ` ${k} ` : null;
}

/** {matches: [{party_id, party_name, address, route_id, route_name}], unclear, unmatched}; apply → also assigns them. */
function autoAssignRoutes(db, { apply = false, party_ids } = {}) {
  const routes = db.prepare('SELECT id, name FROM routes').all()
    .map((r) => ({ id: r.id, name: r.name, words: placeWords(r.name), key: routeKey(r.name) })).filter((r) => r.words.length);
  const parties = db.prepare("SELECT id, name, address FROM parties WHERE active=1 AND route_id IS NULL AND type <> 'SUPPLIER' ORDER BY name").all();
  const only = Array.isArray(party_ids) ? new Set(party_ids.map(Number)) : null;
  const matches = [];
  let unclear = 0, unmatched = 0;
  for (const p of parties) {
    if (only && !only.has(Number(p.id))) continue;
    const nameW = new Set(words(p.name)), addrW = new Set(words(p.address));
    const text = ` ${words(p.name).join(' ')} | ${words(p.address).join(' ')} `;
    const scored = routes.map((r) => {
      const inName = r.words.filter((w) => nameW.has(w)).length;
      const inAddr = r.words.filter((w) => !nameW.has(w) && addrW.has(w)).length;
      return { r, s: [inName, inAddr, r.key && text.includes(r.key) ? r.key.length : 0] };
    }).filter((x) => x.s[0] + x.s[1] > 0);
    if (!scored.length) { unmatched++; continue; }
    const cmp = (a, b) => a.s[0] - b.s[0] || a.s[1] - b.s[1] || a.s[2] - b.s[2];
    scored.sort((a, b) => cmp(b, a));
    if (scored.length > 1 && cmp(scored[0], scored[1]) === 0) { unclear++; continue; }
    const best = scored[0].r;
    matches.push({ party_id: p.id, party_name: p.name, address: p.address || '', route_id: best.id, route_name: best.name });
  }
  if (apply && matches.length) {
    const up = db.prepare('UPDATE parties SET route_id=? WHERE id=? AND route_id IS NULL');
    db.transaction(() => { for (const m of matches) up.run(m.route_id, m.party_id); })();
  }
  return { matches, unclear, unmatched, assigned: apply ? matches.length : 0 };
}

module.exports = { autoAssignRoutes, routeKey, placeWords };
