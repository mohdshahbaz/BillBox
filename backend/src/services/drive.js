/**
 * Backups to Google Drive (Settings › Backup › Google Drive). Sign-in is Google's "TV and limited input" flow: BillBox
 * shows a short code, the user opens google.com/device on any phone or computer and enters it, BillBox picks up the
 * permission by asking Google every few seconds. The permission is drive.file: BillBox sees only what it made itself.
 * Each backup folder becomes a folder inside "BillBox Backups" in the user's Drive. The Google keys (a Client ID and
 * secret of type "TVs and Limited Input devices") are the user's own, from Google Cloud (docs/GOOGLE_DRIVE.md).
 * Settings live in the registry (app_settings), so they cover every company.
 */
const fs = require('fs');
const path = require('path');
const db = require('../db');
const { HttpError } = require('../utils/misc');
const B = require('./backup');

const reg = db.registry;
const get = (k) => { const r = reg.prepare('SELECT value FROM app_settings WHERE key=?').get(k); return r && r.value ? String(r.value) : ''; };
const set = (k, v) => reg.prepare('INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run(k, String(v));
const del = (k) => reg.prepare('DELETE FROM app_settings WHERE key=?').run(k);

const SCOPE = 'https://www.googleapis.com/auth/drive.file';
const FOLDER = 'BillBox Backups';
const FOLDER_TYPE = 'application/vnd.google-apps.folder';
const offline = () => new HttpError(503, 'Could not reach Google. Check the internet connection and try again.', 'OFFLINE');
const form = (o) => Object.entries(o).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
const FORM = { 'content-type': 'application/x-www-form-urlencoded' };

async function call(url, opts) {
  let r;
  try { r = await fetch(url, opts); } catch (_) { throw offline(); }
  const text = await r.text();
  let json = {};
  try { json = JSON.parse(text); } catch (_) { /* not JSON */ }
  return { status: r.status, json: json && typeof json === 'object' ? json : {} };
}

function status() {
  return {
    client_id: get('drive_client_id'), has_secret: get('drive_client_secret') !== '', connected: get('drive_refresh') !== '',
    waiting: get('drive_device') !== '', folder: get('drive_folder_id') ? FOLDER : '',
    last_upload: get('drive_last_upload'), last_status: get('drive_last_status'),
  };
}

/** The keys from the file Google Cloud downloads (client_secret_….json): {"installed": {client_id, client_secret, …}}. */
function keysFromJson(text) {
  let j;
  try { j = JSON.parse(String(text)); } catch (_) { throw new HttpError(400, 'That file is not the JSON file downloaded from Google Cloud (client_secret_….json).'); }
  if (j && j.web && !j.installed) throw new HttpError(400, 'That file is for a “Web application” client. In Google Cloud make an OAuth client of type “TVs and Limited Input devices” and download its JSON.');
  const k = (j && (j.installed || j.web)) || j || {};
  if (!k.client_id || !k.client_secret) throw new HttpError(400, 'That file has no client ID and secret in it. Download the JSON of the OAuth client (Credentials › your client › Download JSON).');
  return { client_id: k.client_id, client_secret: k.client_secret };
}

/** What Google's error means, in plain words. */
function explain(j, status) {
  const e = j.error || '';
  if (e === 'invalid_client') return 'Google does not know this Client ID. Check it was copied in full (or import the downloaded JSON file), that the client is of type “TVs and Limited Input devices”, and if you made it just now wait a few minutes and try again';
  if (e === 'unauthorized_client') return 'this client cannot use code sign-in: make an OAuth client of type “TVs and Limited Input devices”';
  if (e === 'invalid_scope') return 'the Google Drive API is not allowed for this client: turn on the Google Drive API in your Google Cloud project';
  if (e === 'access_denied' || e === 'org_internal') return 'Google refused: add your Gmail as a test user on the consent screen (Audience › Test users)';
  return j.error_description || e || String(status);
}

function saveClient(b = {}) {
  if (b.json) b = keysFromJson(b.json);
  const id = String(b.client_id || '').trim(), secret = String(b.client_secret || '').trim();
  if (!/\.apps\.googleusercontent\.com$/.test(id)) throw new HttpError(400, 'Paste the Client ID from Google Cloud (it ends in .apps.googleusercontent.com).');
  if (!secret) throw new HttpError(400, 'Paste the client secret too.');
  if (id !== get('drive_client_id')) for (const k of ['drive_refresh', 'drive_folder_id', 'drive_device']) del(k);
  set('drive_client_id', id);
  set('drive_client_secret', secret);
  return status();
}

/** Step 1: a code for the user to enter at google.com/device. */
async function connect() {
  const id = get('drive_client_id');
  if (!id) throw new HttpError(400, 'Add the Google Client ID and secret first.');
  const r = await call('https://oauth2.googleapis.com/device/code', { method: 'POST', headers: FORM, body: form({ client_id: id, scope: SCOPE }) });
  if (r.status !== 200) throw new HttpError(r.json.error ? 400 : 502, `Google did not give a code: ${explain(r.json, r.status)}.`);
  set('drive_device', r.json.device_code);
  return { user_code: r.json.user_code, verification_url: r.json.verification_url || r.json.verification_uri || 'https://www.google.com/device',
    interval: r.json.interval || 5, expires_in: r.json.expires_in || 1800 };
}

/** Step 2, every few seconds: has the user approved yet? Once they have, the BillBox Backups folder is made. */
async function poll() {
  const dev = get('drive_device');
  if (!dev) throw new HttpError(400, 'Press Connect first.');
  const r = await call('https://oauth2.googleapis.com/token', { method: 'POST', headers: FORM,
    body: form({ client_id: get('drive_client_id'), client_secret: get('drive_client_secret'), device_code: dev, grant_type: 'urn:ietf:params:oauth:grant-type:device_code' }) });
  if (r.json.error === 'authorization_pending' || r.json.error === 'slow_down') return { connected: false, waiting: true };
  del('drive_device');
  if (r.status !== 200 || !r.json.refresh_token) {
    throw new HttpError(400, r.json.error === 'access_denied' ? 'Google sign-in was declined.' : r.json.error === 'expired_token' ? 'The code ran out. Press Connect again.'
      : `Google did not connect: ${explain(r.json, r.status)}.`);
  }
  set('drive_refresh', r.json.refresh_token);
  await folder(r.json.access_token);
  return { connected: true, waiting: false, folder: FOLDER };
}

function disconnect() {
  for (const k of ['drive_refresh', 'drive_folder_id', 'drive_device', 'drive_last_upload', 'drive_last_status']) del(k);
  return status();
}

async function token() {
  if (!get('drive_refresh')) throw new HttpError(400, 'Google Drive is not connected.');
  const r = await call('https://oauth2.googleapis.com/token', { method: 'POST', headers: FORM,
    body: form({ client_id: get('drive_client_id'), client_secret: get('drive_client_secret'), refresh_token: get('drive_refresh'), grant_type: 'refresh_token' }) });
  if (r.status !== 200 || !r.json.access_token) {
    if (r.json.error === 'invalid_grant') { del('drive_refresh'); del('drive_folder_id'); throw new HttpError(401, 'Google Drive was disconnected (the permission was removed or ran out). Connect again.'); }
    throw new HttpError(502, `Google did not answer (${r.json.error_description || r.json.error || r.status}).`);
  }
  return r.json.access_token;
}

async function makeFolder(tok, name, parent) {
  const r = await call('https://www.googleapis.com/drive/v3/files?fields=id', { method: 'POST', headers: { authorization: `Bearer ${tok}`, 'content-type': 'application/json' },
    body: JSON.stringify(parent ? { name, mimeType: FOLDER_TYPE, parents: [parent] } : { name, mimeType: FOLDER_TYPE }) });
  if (r.status !== 200 || !r.json.id) throw new HttpError(502, `Google Drive did not make the folder "${name}" (${(r.json.error && r.json.error.message) || r.status}).`);
  return r.json.id;
}

/** Every file or folder BillBox can see in Drive matching a query (drive.file: only what BillBox made with these keys). */
async function search(tok, q, fields = 'id,name,createdTime,size') {
  const out = [];
  let page = '';
  do {
    const u = `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(q)}&fields=${encodeURIComponent(`nextPageToken,files(${fields})`)}&orderBy=createdTime%20desc&pageSize=200${page ? `&pageToken=${encodeURIComponent(page)}` : ''}`;
    const r = await call(u, { headers: { authorization: `Bearer ${tok}` } });
    if (r.status !== 200 || !Array.isArray(r.json.files)) break;
    out.push(...r.json.files);
    page = r.json.nextPageToken || '';
  } while (page);
  return out;
}

/** The "BillBox Backups" folders in Drive (one normally; a reinstall used to make another). */
const findFolders = (tok) => search(tok, `name='${FOLDER}' and mimeType='${FOLDER_TYPE}' and trashed=false`, 'id,name,createdTime');

/** The "BillBox Backups" folder: the one already in Drive (after a reinstall or on another device), else made. */
async function folder(tok) {
  const id = get('drive_folder_id');
  if (id) {
    const r = await call(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(id)}?fields=id,trashed`, { headers: { authorization: `Bearer ${tok}` } });
    if (r.status === 200 && !r.json.trashed) return id;
  }
  const found = await findFolders(tok);
  if (found.length) { set('drive_folder_id', found[found.length - 1].id); return found[found.length - 1].id; }
  const made = await makeFolder(tok, FOLDER, null);
  set('drive_folder_id', made);
  return made;
}

/** Uploads one backup folder (the newest when none is named) into BillBox Backups in Drive. */
async function upload(b = {}) {
  const list = B.listBackups();
  const name = b.folder ? String(b.folder) : (list[0] && list[0].name);
  if (!name) throw new HttpError(400, 'There is no backup to upload yet. Press Back up now first.');
  const dir = path.join(B.config().dir, path.basename(name));
  if (!fs.existsSync(dir)) throw new HttpError(404, `Backup ${name} not found.`);
  const tok = await token();
  const parent = await folder(tok);
  const sub = await makeFolder(tok, path.basename(name), parent);
  const files = fs.readdirSync(dir).filter((f) => fs.statSync(path.join(dir, f)).isFile()).sort();
  let bytes = 0;
  for (const f of files) {
    const data = fs.readFileSync(path.join(dir, f));
    const boundary = 'billbox' + Date.now().toString(36);
    const meta = JSON.stringify({ name: f, parents: [sub] });
    const body = Buffer.concat([
      Buffer.from(`--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n--${boundary}\r\ncontent-type: application/octet-stream\r\n\r\n`),
      data, Buffer.from(`\r\n--${boundary}--\r\n`)]);
    const r = await call('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id', { method: 'POST',
      headers: { authorization: `Bearer ${tok}`, 'content-type': `multipart/related; boundary=${boundary}` }, body });
    if (r.status !== 200) {
      set('drive_last_status', `failed: ${f}`);
      throw new HttpError(502, `Google Drive did not take ${f} (${(r.json.error && r.json.error.message) || r.status}).`);
    }
    bytes += data.length;
  }
  set('drive_last_upload', `${name}`);
  set('drive_last_status', 'ok');
  return { folder: name, files: files.length, bytes, drive_folder: FOLDER };
}

/** The backups in Drive › BillBox Backups, newest first: [{id, name, created}]. */
async function list() {
  const tok = await token();
  const parents = await findFolders(tok);
  const own = get('drive_folder_id');
  if (own && !parents.some((p) => p.id === own)) parents.push({ id: own });
  const seen = new Set(), out = [];
  for (const p of parents) {
    for (const f of await search(tok, `'${p.id}' in parents and mimeType='${FOLDER_TYPE}' and trashed=false`, 'id,name,createdTime')) {
      if (seen.has(f.name)) continue;
      seen.add(f.name);
      out.push({ id: f.id, name: f.name, created: f.createdTime || '' });
    }
  }
  out.sort((a, b) => (a.name < b.name ? 1 : a.name > b.name ? -1 : 0));
  const local = new Set(B.listBackups().map((b) => b.name));
  return out.map((b) => ({ ...b, on_device: local.has(b.name) }));
}

/** Downloads one backup from Drive into the backup folder on this device (kept as it is when already there); the usual
 *  restore (POST /backup/restore {name}) then checks and restores it. */
async function download(b = {}) {
  const id = String(b.id || ''), name = path.basename(String(b.name || ''));
  if (!id || !/^FMCG_Backup_|^[\w .()-]+$/.test(name)) throw new HttpError(400, 'Choose a backup from Google Drive.');
  const dir = path.join(B.config().dir, name);
  if (B.listBackups().some((x) => x.name === name)) return { name, downloaded: 0, on_device: true };
  const tok = await token();
  const files = await search(tok, `'${id}' in parents and trashed=false and mimeType!='${FOLDER_TYPE}'`, 'id,name,size');
  if (!files.length) throw new HttpError(404, `The backup ${name} in Google Drive is empty.`);
  const tmp = `${dir}.part`;
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.mkdirSync(tmp, { recursive: true });
  let bytes = 0;
  try {
    for (const f of files) {
      let r;
      try { r = await fetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(f.id)}?alt=media`, { headers: { authorization: `Bearer ${tok}` } }); } catch (_) { throw offline(); }
      if (r.status !== 200) throw new HttpError(502, `Google Drive did not give ${f.name} (${r.status}).`);
      const data = Buffer.from(await r.arrayBuffer());
      fs.writeFileSync(path.join(tmp, path.basename(f.name)), data);
      bytes += data.length;
    }
    fs.renameSync(tmp, dir);
  } catch (e) { fs.rmSync(tmp, { recursive: true, force: true }); throw e; }
  return { name, downloaded: files.length, bytes, on_device: true };
}

/** After an automatic backup: upload it too when Drive is connected; a failure is only recorded. */
async function afterBackup(folderName) {
  if (!get('drive_refresh')) return null;
  try { return await upload({ folder: folderName }); } catch (e) { set('drive_last_status', `failed: ${e.message}`); return null; }
}

module.exports = { status, saveClient, connect, poll, disconnect, upload, list, download, afterBackup };
