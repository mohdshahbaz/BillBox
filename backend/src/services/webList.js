const { HttpError } = require('../utils/misc');
const T = require('./itemTools');

/**
 * Finding a company's price list on the internet: a web search (DuckDuckGo's plain HTML page, no account or key),
 * then the chosen page or PDF is read into items by itemTools.extractList.
 */
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
const OFFLINE = () => new HttpError(503, 'Could not reach the internet. Check the connection and try again.', 'OFFLINE');

async function get(url, ms) {
  if (typeof fetch !== 'function') throw OFFLINE();
  let r;
  try {
    r = await fetch(url, { signal: AbortSignal.timeout(ms), redirect: 'follow', headers: { 'User-Agent': UA, Accept: 'text/html,application/pdf,*/*' } });
  } catch (_) { throw OFFLINE(); }
  if (!r.ok) throw new HttpError(502, `That page answered with an error (${r.status}).`);
  const buf = Buffer.from(await r.arrayBuffer());
  if (buf.length > 12 * 1024 * 1024) throw new HttpError(413, 'That file is too large to read (12 MB at most).');
  return { buf, type: String(r.headers.get('content-type') || '').toLowerCase() };
}

const between = (s, a, b, from = 0) => {
  const i = s.indexOf(a, from);
  if (i < 0) return null;
  const j = s.indexOf(b, i + a.length);
  return j < 0 ? null : s.slice(i + a.length, j);
};

/** Search results as { title, url }. */
async function search(b) {
  const q = String((b && b.q) || [b && b.company, b && b.category, 'price list MRP'].filter(Boolean).join(' ')).trim();
  if (!q || q === 'price list MRP') throw new HttpError(400, 'Type the company (and category) to search for');
  const { buf } = await get('https://html.duckduckgo.com/html/?q=' + encodeURIComponent(q), 12000);
  const html = buf.toString('utf8');
  const results = [];
  for (const chunk of html.split('class="result__a"').slice(1)) {
    let href = between(chunk, 'href="', '"');
    if (!href) continue;
    href = href.split('&amp;').join('&');
    if (href.includes('uddg=')) { try { href = decodeURIComponent(href.split('uddg=')[1].split('&')[0]); } catch (_) { continue; } }
    if (href.startsWith('//')) href = 'https:' + href;
    if (!/^https?:\/\//i.test(href) || href.includes('duckduckgo.com/y.js')) continue;
    const a = chunk.indexOf('>'), z = chunk.indexOf('</a>');
    const title = a >= 0 && z > a ? T.htmlLines(chunk.slice(a + 1, z)).join(' ') : href;
    if (results.some((r) => r.url === href)) continue;
    results.push({ title: title || href, url: href, pdf: /\.pdf($|\?)/i.test(href) });
    if (results.length >= 10) break;
  }
  return { query: q, results };
}

/** Reads the items on one page or PDF. */
async function fetchList(b) {
  const url = String((b && b.url) || '').trim();
  if (!/^https?:\/\//i.test(url)) throw new HttpError(400, 'Paste a web address starting with http:// or https://');
  const { buf, type } = await get(url, 20000);
  const isPdf = type.includes('pdf') || buf.slice(0, 5).toString('latin1') === '%PDF-';
  if (isPdf) {
    const { extractText } = require('./pdfExtract');
    const { pages } = await extractText(buf);
    return { url, source: 'pdf', ...T.extractList({ text: pages.join('\n'), company: b.company, case: b.case }) };
  }
  return { url, source: 'page', ...T.extractList({ html: buf.toString('utf8'), company: b.company, case: b.case }) };
}

module.exports = { search, fetchList };
