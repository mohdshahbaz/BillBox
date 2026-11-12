/**
 * Auto-assign outlets to routes: a party with no route gets the route whose name appears in the party's name or
 * address (whole words, case and punctuation ignored). "ROUTE", "BEAT" and weekday words in a route name are ignored
 * ("KHAJRANA ROUTE (MON)" matches "SHARMA STORE, KHAJRANA"). When several routes match, the longest name wins
 * ("PALASIA" vs "NEW PALASIA"); two different routes with the same longest name are skipped as unclear.
 * Ported to ios/BillBoxCore/Sources/BillBoxCore/PartiesAPI.swift (autoAssignRoutes).
 */
const FILLER = new Set(['ROUTE', 'ROUTES', 'BEAT', 'MON', 'TUE', 'TUES', 'WED', 'THU', 'THUR', 'THURS', 'FRI', 'SAT', 'SUN',
  'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']);
const words = (s) => String(s || '').toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim().split(' ').filter(Boolean);

function routeKey(name) {
  const all = words(name);
  const kept = all.filter((w) => !FILLER.has(w));
  const k = (kept.length ? kept : all).join(' ');
  return k.length >= 3 ? ` ${k} ` : null;
}

/** {matches: [{party_id, party_name, address, route_id, route_name}], unclear, unmatched}; apply → also assigns them. */
function autoAssignRoutes(db, { apply = false, party_ids } = {}) {
  const routes = db.prepare('SELECT id, name FROM routes').all()
    .map((r) => ({ id: r.id, name: r.name, key: routeKey(r.name) })).filter((r) => r.key);
  const parties = db.prepare("SELECT id, name, address FROM parties WHERE active=1 AND route_id IS NULL AND type <> 'SUPPLIER' ORDER BY name").all();
  const only = Array.isArray(party_ids) ? new Set(party_ids.map(Number)) : null;
  const matches = [];
  let unclear = 0, unmatched = 0;
  for (const p of parties) {
    if (only && !only.has(Number(p.id))) continue;
    const text = ` ${words(`${p.name} ${p.address || ''}`).join(' ')} `;
    const hit = routes.filter((r) => text.includes(r.key));
    if (!hit.length) { unmatched++; continue; }
    const len = Math.max(...hit.map((r) => r.key.length));
    const best = hit.filter((r) => r.key.length === len);
    if (best.length > 1) { unclear++; continue; }
    matches.push({ party_id: p.id, party_name: p.name, address: p.address || '', route_id: best[0].id, route_name: best[0].name });
  }
  if (apply && matches.length) {
    const up = db.prepare('UPDATE parties SET route_id=? WHERE id=? AND route_id IS NULL');
    db.transaction(() => { for (const m of matches) up.run(m.route_id, m.party_id); })();
  }
  return { matches, unclear, unmatched, assigned: apply ? matches.length : 0 };
}

module.exports = { autoAssignRoutes, routeKey };
