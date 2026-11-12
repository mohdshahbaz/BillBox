/**
 * A party can be on several routes: parties.route_id is the first one (what older versions read), party_routes holds
 * the others. Ported to ios/BillBoxCore/Sources/BillBoxCore/PartiesAPI.swift.
 */
// SQL for "party p is on route r"
const ON_ROUTE = `(r.id=p.route_id OR r.id IN (SELECT x.route_id FROM party_routes x WHERE x.party_id=p.id))`;
// both in route-name order ("; " between names, as a route's own name has commas; ids as "3,7")
const ROUTE_NAMES = `(SELECT group_concat(name, '; ') FROM (SELECT r.name FROM routes r WHERE ${ON_ROUTE} ORDER BY r.name, r.id))`;
const ROUTE_IDS = `(SELECT group_concat(id) FROM (SELECT r.id FROM routes r WHERE ${ON_ROUTE} ORDER BY r.name, r.id))`;

/** [3, 7] from [3, "7"], "3,7" or 3: whole numbers, no repeats, in the order given. */
function idList(v) {
  const list = Array.isArray(v) ? v : String(v ?? '').split(',');
  return [...new Set(list.map((x) => Number(String(x).trim())).filter((n) => Number.isInteger(n) && n > 0))];
}

/** A party's routes become `ids` (those that exist): the first stays in parties.route_id (the one it has now, if kept), the rest in party_routes. */
function setPartyRoutes(d, pid, ids) {
  const have = new Set(d.prepare('SELECT id FROM routes').all().map((r) => Number(r.id)));
  ids = idList(ids).filter((id) => have.has(id));
  const cur = d.prepare('SELECT route_id FROM parties WHERE id=?').get(pid);
  if (!cur) return [];
  const first = ids.includes(Number(cur.route_id)) ? Number(cur.route_id) : (ids.length ? ids[0] : null);
  if ((cur.route_id == null ? null : Number(cur.route_id)) !== first) d.prepare('UPDATE parties SET route_id=? WHERE id=?').run(first, pid);
  const rest = new Set(ids.filter((id) => id !== first)), kept = new Set();
  for (const x of d.prepare('SELECT id, route_id FROM party_routes WHERE party_id=? ORDER BY id').all(pid)) {
    const rid = Number(x.route_id);
    if (rest.has(rid) && !kept.has(rid)) kept.add(rid); else d.prepare('DELETE FROM party_routes WHERE id=?').run(x.id);
  }
  for (const rid of rest) if (!kept.has(rid)) d.prepare('INSERT INTO party_routes(party_id,route_id) VALUES(?,?)').run(pid, rid);
  return ids;
}
/** One more route for a party (its first when it has none). false: it is on that route already. */
function addPartyRoute(d, pid, rid) {
  const p = d.prepare('SELECT route_id FROM parties WHERE id=?').get(pid);
  if (!p) return false;
  if (p.route_id == null) { d.prepare('UPDATE parties SET route_id=? WHERE id=?').run(rid, pid); return true; }
  if (Number(p.route_id) === Number(rid) || d.prepare('SELECT 1 x FROM party_routes WHERE party_id=? AND route_id=?').get(pid, rid)) return false;
  d.prepare('INSERT INTO party_routes(party_id,route_id) VALUES(?,?)').run(pid, rid);
  return true;
}
/** Every route of a party, the first one first. */
function partyRoutes(d, pid) {
  const p = d.prepare('SELECT route_id FROM parties WHERE id=?').get(pid);
  const ids = p && p.route_id != null ? [Number(p.route_id)] : [];
  for (const x of d.prepare('SELECT route_id FROM party_routes WHERE party_id=? ORDER BY id').all(pid)) if (!ids.includes(Number(x.route_id))) ids.push(Number(x.route_id));
  return ids;
}

module.exports = { ON_ROUTE, ROUTE_NAMES, ROUTE_IDS, idList, setPartyRoutes, addPartyRoute, partyRoutes };
