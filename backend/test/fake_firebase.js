// A fake Firebase for the sync tests: e-mail sign-in, token refresh and the Realtime Database REST calls BillBox makes.
const http = require('http');
const tree = {};
const users = {};
let pushN = 0, lastMs = 0;
const PUSH = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';
function pushId() {
  let ms = Math.max(Date.now(), lastMs); lastMs = ms; let s = '';
  for (let i = 0; i < 8; i++) { s = PUSH[ms % 64] + s; ms = Math.floor(ms / 64); }
  const n = String(pushN++).padStart(12, '0'); return s + n;
}
const at = (parts, make) => { let o = tree; for (const p of parts) { if (o[p] === undefined || o[p] === null || typeof o[p] !== 'object') { if (!make) return undefined; o[p] = {}; } o = o[p]; } return o; };
const strip = (v) => {
  if (v && typeof v === 'object' && v['.sv'] === 'timestamp') return Date.now();
  if (Array.isArray(v)) return v.map(strip);
  if (v && typeof v === 'object') { const o = {}; for (const [k, x] of Object.entries(v)) if (x !== null) o[k] = strip(x); return o; }
  return v;
};
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const u = new URL(req.url, 'http://x');
    const send = (st, o) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (u.pathname.startsWith('/v1/accounts:')) {
      const b = JSON.parse(body), kind = u.pathname.split(':')[1];
      if (kind === 'signUp') { if (users[b.email]) return send(400, { error: { message: 'EMAIL_EXISTS' } }); users[b.email] = { pw: b.password, uid: 'U' + Object.keys(users).length }; }
      const x = users[b.email];
      if (!x || x.pw !== b.password) return send(400, { error: { message: 'INVALID_LOGIN_CREDENTIALS' } });
      return send(200, { idToken: 'T:' + x.uid, refreshToken: 'R:' + x.uid, localId: x.uid, expiresIn: '3600' });
    }
    if (u.pathname === '/token') { const p = new URLSearchParams(body); const uid = p.get('refresh_token').slice(2); return send(200, { id_token: 'T:' + uid, refresh_token: 'R:' + uid, expires_in: '3600' }); }
    const m = /^\/users\/([^/]+)\/(.*)\.json$/.exec(u.pathname);
    if (!m) return send(404, { error: 'nope' });
    if (u.searchParams.get('auth') !== 'T:' + m[1]) return send(401, { error: 'Permission denied' });
    const parts = ['users', m[1], ...m[2].split('/')];
    if (req.method === 'PUT') { const parent = at(parts.slice(0, -1), true); parent[parts[parts.length - 1]] = strip(JSON.parse(body)); return send(200, JSON.parse(body)); }
    if (req.method === 'POST') { const o = at(parts, true); const k = pushId(); o[k] = strip(JSON.parse(body)); return send(200, { name: k }); }
    let v = parts.reduce((o, p) => (o && typeof o === 'object' ? o[p] : undefined), tree);
    if (v === undefined) return send(200, null);
    if (u.searchParams.get('shallow') === 'true' && v && typeof v === 'object') return send(200, Object.fromEntries(Object.keys(v).map((k) => [k, true])));
    if (u.searchParams.get('orderBy') === '"$key"') {
      let keys = Object.keys(v).sort();
      if (u.searchParams.has('startAt')) { const s = JSON.parse(u.searchParams.get('startAt')); keys = keys.filter((k) => k >= s); }
      if (u.searchParams.has('limitToFirst')) keys = keys.slice(0, Number(u.searchParams.get('limitToFirst')));
      v = Object.fromEntries(keys.map((k) => [k, v[k]]));
    }
    send(200, v);
  });
});

module.exports = { server, tree };
