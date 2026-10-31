// fetch() for the engine's internet look-ups (category guesses, price lists), through the app (AndroidNet), so pages from
// any site can be read (a web page's own fetch would be blocked by the sites' cross-origin rules).
'use strict';
function fetchShim(url, opts = {}) {
  return new Promise((ok, no) => {
    setTimeout(() => {
      try {
        const net = globalThis.AndroidNet;
        if (!net) return no(new TypeError('fetch failed'));
        const r = JSON.parse(net.request(String(url), JSON.stringify({ method: opts.method || 'GET', headers: opts.headers || {}, timeoutMs: 20000 })));
        if (r.error) return no(new TypeError(r.error));
        const body = Buffer.from(r.b64 || '', 'base64');
        const headers = new Map(Object.entries(r.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
        ok({ ok: r.status >= 200 && r.status < 300, status: r.status, headers: { get: (k) => headers.get(String(k).toLowerCase()) || null },
          arrayBuffer: async () => body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength),
          text: async () => body.toString('utf8'), json: async () => JSON.parse(body.toString('utf8')) });
      } catch (e) { no(new TypeError(String(e && e.message || e))); }
    }, 0);
  });
}
module.exports = { fetchShim };
