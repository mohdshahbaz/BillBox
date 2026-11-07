/**
 * Licence and subscription (Settings › Licence). Every BillBox app runs this same code (Mac, Linux, Windows, Android; the
 * iPhone has the Swift copy in BillBoxCore/License.swift).
 *
 * Editions (set by the app that starts the engine, BILLBOX_EDITION):
 *   public  the apps on the website: live licence keys, real payments (Razorpay live), licence server /api/live
 *   admin   the owner's test build: test keys, Razorpay test mode, licence server /api/test, plus "reset trial"
 *   (none)  developer runs and the automatic checks: no licence needed, nothing is limited
 *
 * A licence key (bought on the website, or issued by the owner for a UPI or cash sale) is turned into an activation for
 * this device by the licence server. Both are signed with Ed25519 and checked here without the internet; the activation
 * is renewed online every few weeks (BillBox keeps working offline until it runs out). Without a licence the first
 * 15 days are a full trial; after that BillBox opens read-only: everything can be seen, printed, exported and backed up,
 * but nothing new is saved until a licence is entered.
 *
 * Token: "BB1." + base64url(JSON payload) + "." + base64url(signature of the text before the second dot).
 */
'use strict';
const db = require('../db');
const { HttpError } = require('../utils/misc');
const ed = require('./ed25519');

const SITE = 'https://billbox-app.pages.dev';
const KEYS = {
  live: 'n5iJULtiUQmzWASMw96LVf9kQ6y5z77934tbchjqhpE',
  test: 'pL2sd4UksOSqnzAlNDcYtgcquKYTxZYu9fR0c0vbHVY',
};
const TRIAL_DAYS = 15;
const DAY = 86400000;
const RENEW_BEFORE = 20 * DAY;              // renew the activation online when it has less than this left

const reg = db.registry;
const get = (k) => { const r = reg.prepare('SELECT value FROM app_settings WHERE key=?').get(k); return r && r.value ? String(r.value) : ''; };
const set = (k, v) => reg.prepare('INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run(k, String(v));
const del = (k) => reg.prepare('DELETE FROM app_settings WHERE key=?').run(k);

/** 'public', 'admin' or '' (no licence needed). Settable once by an app whose engine has no environment (Android). */
let editionOverride = '';
function edition() {
  const e = String((typeof process !== 'undefined' && process.env && process.env.BILLBOX_EDITION) || editionOverride || '').toLowerCase();
  return e === 'public' || e === 'admin' ? e : '';
}
function setEdition(e) { if (!editionOverride && (e === 'public' || e === 'admin')) editionOverride = e; }
const env = () => (edition() === 'public' ? 'live' : 'test');
const server = () => `${SITE}/api/${env()}`;

// ---------------------------------------------------------------- tokens
function b64urlToBytes(s) {
  const b = String(s).replace(/-/g, '+').replace(/_/g, '/');
  const bin = typeof atob === 'function' ? atob(b + '='.repeat((4 - (b.length % 4)) % 4)) : Buffer.from(b, 'base64').toString('binary');
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
const utf8 = (s) => new TextEncoder().encode(s);
const fromUtf8 = (b) => new TextDecoder().decode(b);

/** The payload of a token signed with this edition's key, or null. */
function readToken(token, keyEnv = env()) {
  const t = String(token || '').trim().replace(/\s+/g, '');
  const parts = t.split('.');
  if (parts.length !== 3 || parts[0] !== 'BB1') return null;
  let payload;
  try { payload = JSON.parse(fromUtf8(b64urlToBytes(parts[1]))); } catch (_) { return null; }
  if (!payload || typeof payload !== 'object' || payload.env !== keyEnv) return null;
  if (!ed.verify(b64urlToBytes(parts[2]), utf8(`${parts[0]}.${parts[1]}`), b64urlToBytes(KEYS[keyEnv]))) return null;
  return payload;
}

// ---------------------------------------------------------------- this device
function device() {
  let d = get('license_device');
  if (!d) {
    const rnd = typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : require('crypto').randomUUID();
    d = rnd.replace(/-/g, '').slice(0, 20).toUpperCase();
    set('license_device', d);
  }
  return d;
}

function trialStart() {
  let t = Number(get('license_trial_start') || 0);
  if (!t) { t = Date.now(); set('license_trial_start', t); }
  return t;
}

function activation() {
  const a = readToken(get('license_activation'));
  return a && a.t === 'act' && a.dev === device() ? a : null;
}

function status() {
  const ed_ = edition();
  if (!ed_) return { edition: '', state: 'unlimited', writable: true };
  const now = Date.now();
  const a = activation();
  const base = { edition: ed_, env: env(), device: device(), site: SITE, buy_url: `${SITE}/buy.html?device=${device()}${ed_ === 'admin' ? '&test=1' : ''}` };
  if (a && (a.lexp == null || a.lexp > now) && a.exp > now) {
    return { ...base, state: 'licensed', writable: true, plan: a.plan, email: a.email || '', name: a.name || '', licence_id: a.lic,
      expires: a.lexp ? new Date(a.lexp).toISOString().slice(0, 10) : null, renew_by: new Date(a.exp).toISOString().slice(0, 10),
      needs_renewal: a.exp - now < RENEW_BEFORE, last_check: get('license_checked') };
  }
  const left = Math.min(TRIAL_DAYS, Math.max(0, Math.ceil((trialStart() + TRIAL_DAYS * DAY - now) / DAY)));
  const why = a ? (a.lexp != null && a.lexp <= now ? 'The licence ran out' : 'The licence needs to be checked online') : '';
  return { ...base, state: left > 0 ? 'trial' : 'expired', writable: left > 0, trial_days: TRIAL_DAYS, trial_days_left: left, reason: why,
    has_key: get('license_key') !== '' };
}

async function call(path, body) {
  let r;
  try {
    r = await fetch(`${server()}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  } catch (_) { throw new HttpError(503, 'Could not reach the BillBox licence server. Check the internet connection and try again.', 'OFFLINE'); }
  let j = {};
  try { j = JSON.parse(await r.text()); } catch (_) { /* not JSON */ }
  if (r.status !== 200) throw new HttpError(r.status === 404 ? 400 : r.status >= 500 ? 502 : r.status, j.error || `The licence server said no (${r.status}).`, j.code);
  return j;
}

/** Enter a licence key: the licence server makes an activation for this device. */
async function activate(b = {}) {
  if (!edition()) return status();
  const key = String(b.key || get('license_key')).trim().replace(/\s+/g, '');
  const lic = readToken(key);
  if (!lic || lic.t !== 'lic') {
    const other = readToken(key, env() === 'live' ? 'test' : 'live');
    throw new HttpError(400, other ? (env() === 'live' ? 'That is a test licence key: it works only in the admin (test) BillBox.' : 'That is a live licence key: it works only in the BillBox from the website.')
      : 'That is not a BillBox licence key. Copy the whole key from the e-mail or the website (it starts with BB1.).');
  }
  if (lic.exp != null && lic.exp <= Date.now()) throw new HttpError(400, `This licence ran out on ${new Date(lic.exp).toISOString().slice(0, 10)}. Renew it on ${SITE}.`);
  const r = await call('/activate', { key, device: device(), name: String(b.device_name || '').slice(0, 60) });
  const a = readToken(r.activation);
  if (!a || a.t !== 'act' || a.dev !== device()) throw new HttpError(502, 'The licence server gave an activation that does not check out. Try again.');
  set('license_key', key);
  set('license_activation', r.activation);
  set('license_checked', new Date().toISOString());
  return status();
}

/** Renews the activation online when it is near its end (called when the app opens; failures are kept quiet). */
async function renew() {
  const s = status();
  if (!edition() || !get('license_key') || (s.state === 'licensed' && !s.needs_renewal)) return s;
  try { return await activate({}); } catch (e) { return { ...status(), renew_error: e.message }; }
}

/** Removes the licence from this device (frees its place for another device). */
async function deactivate() {
  const key = get('license_key');
  if (key) { try { await call('/deactivate', { key, device: device() }); } catch (_) { /* freed on the server later */ } }
  for (const k of ['license_key', 'license_activation', 'license_checked']) del(k);
  return status();
}

/** Admin (test) edition only: start the trial again, to test the purchase steps. */
function resetTrial() {
  if (edition() !== 'admin') throw new HttpError(403, 'Only the admin (test) BillBox can reset the trial.');
  for (const k of ['license_key', 'license_activation', 'license_checked', 'license_trial_start']) del(k);
  return status();
}

/** Whether a request may change the books. Reading, printing, exports, backups and the licence itself always work. */
const ALWAYS = /^\/(license|backup|sync|update|companies\/\d+\/activate)(\/|$)/;
function allows(method, path) {
  if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') return true;
  const p = String(path).replace(/^\/api/, '');
  if (ALWAYS.test(p) || /^\/invoices\/[^/]+\/printed$/.test(p) || /\/preview$/.test(p)) return true;
  return status().writable;
}
const blocked = () => new HttpError(402, `Your ${TRIAL_DAYS}-day BillBox trial has ended. Your books are safe and can still be seen, printed and backed up; to add or change anything, buy a licence (Settings › Licence) or enter your licence key.`, 'LICENSE');

module.exports = { status, activate, renew, deactivate, resetTrial, allows, blocked, edition, setEdition, readToken, device, KEYS, SITE };
