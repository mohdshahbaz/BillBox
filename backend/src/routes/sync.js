const router = require('express').Router();
const { h, ha } = require('../utils/misc');
const S = require('../services/sync');
const db = require('../db');

// Settings › Sync (services/sync.js). The company is the one in X-Company-Id (the open one).
const cid = (req) => Number(req.get('x-company-id')) || db.firstCompanyId();
router.get('/sync', h((req, res) => res.json(S.status(cid(req)))));
router.get('/sync/tick', ha(async (req, res) => res.json(await S.tick())));
router.post('/sync/signin', ha(async (req, res) => { await S.signIn(req.body || {}); res.json(S.status(cid(req))); }));
router.post('/sync/signout', h((req, res) => { S.signOut(); res.json(S.status(cid(req))); }));
router.post('/sync/on', ha(async (req, res) => res.json(await S.turnOn(cid(req)))));
router.post('/sync/off', h((req, res) => res.json(S.turnOff(cid(req)))));
router.post('/sync/now', ha(async (req, res) => { await S.tick(); res.json(S.status(cid(req))); }));
router.get('/sync/remote', ha(async (req, res) => res.json(await S.remote(cid(req)))));
router.post('/sync/merge', ha(async (req, res) => res.json(await S.merge(cid(req), String((req.body || {}).key || '')))));
router.post('/sync/join', ha(async (req, res) => res.json(await S.join(String((req.body || {}).key || '')))));

module.exports = router;
