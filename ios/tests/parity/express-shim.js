// Just enough of Express for the Mac app's route files (Router + get/post/put/delete), so they run without npm packages.
function Router() {
  const routes = [];
  const r = { routes };
  for (const m of ['get', 'post', 'put', 'delete']) r[m] = (p, ...hs) => { routes.push({ m: m.toUpperCase(), p, hs }); return r; };
  r.use = () => r;
  return r;
}
module.exports = Object.assign(() => ({}), { Router, json: () => (q, s, n) => n() });
