/**
 * Updates from inside the app (Settings › Updates): the newest GitHub release of this edition and its file for the
 * platform asking. Public builds follow the public releases (v16.3.0), admin builds the admin ones (v16.3.0-admin).
 * The app downloads and installs the file itself (Android: the APK; Mac: the zip, swapped in; Windows: the setup;
 * Linux: the .deb); the iPhone build is unsigned, so it only opens the download page.
 */
const { HttpError } = require('../utils/misc');

const REPO = process.env.BILLBOX_REPO || 'mohdshahbaz/BillBox';
const API = process.env.BILLBOX_RELEASES_API || `https://api.github.com/repos/${REPO}/releases?per_page=30`;
const FILES = {
  android: /^BillBox-android-.*\.apk$/, mac: /^BillBox-mac-.*\.zip$/, windows: /^BillBox-windows-.*-setup\.exe$/,
  linux: /^BillBox-linux-.*\.deb$/, 'linux-tar': /^BillBox-linux-.*\.tar\.gz$/, iphone: /^BillBox-iphone-.*\.ipa$/,
};

/** "16.2.12-admin" → [16, 2, 12]; newer(a, b) is true when a comes after b. */
const parts = (v) => String(v || '').replace(/^v/, '').split('-')[0].split('.').map((x) => parseInt(x, 10) || 0);
function newer(a, b) {
  const x = parts(a), y = parts(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); }
  return false;
}

async function check({ version, edition, platform } = {}) {
  const admin = String(edition || '') === 'admin';
  let r;
  try { r = await fetch(API, { headers: { accept: 'application/vnd.github+json', 'user-agent': 'BillBox' }, timeoutMs: 10000 }); }
  catch (_) { throw new HttpError(503, 'No internet: could not look for a new version.'); }
  if (!r.ok) throw new HttpError(502, `GitHub answered ${r.status} while looking for a new version.`);
  const list = (await r.json()) || [];
  const rel = list.filter((x) => !x.draft && /-admin$/.test(x.tag_name) === admin && (admin || !x.prerelease))
    .sort((a, b) => (newer(a.tag_name, b.tag_name) ? -1 : newer(b.tag_name, a.tag_name) ? 1 : 0))[0];
  if (!rel) return { available: false, current: version || '', latest: null };
  const want = FILES[platform] || null;
  const asset = want ? (rel.assets || []).find((a) => want.test(a.name)) : null;
  const latest = rel.tag_name.replace(/^v/, '');
  return {
    available: !!version && newer(latest, version), current: version || '', latest, page: rel.html_url,
    published: rel.published_at, notes: String(rel.body || '').split('\n## Install')[0].trim().slice(0, 1500),
    file: asset ? { name: asset.name, url: asset.browser_download_url, size: asset.size } : null,
  };
}

module.exports = { check, newer };
