const router = require('express').Router();
const { h, ha } = require('../utils/misc');
const L = require('../services/license');

// Settings › Licence (services/license.js)
router.get('/license', h((req, res) => res.json(L.status())));
router.post('/license/activate', ha(async (req, res) => res.json(await L.activate(req.body || {}))));
router.post('/license/renew', ha(async (req, res) => res.json(await L.renew())));
router.post('/license/deactivate', ha(async (req, res) => res.json(await L.deactivate())));
router.post('/license/reset-trial', h((req, res) => res.json(L.resetTrial())));
router.post('/license/edition', h((req, res) => { L.setEdition(String((req.body || {}).edition || '')); res.json(L.status()); }));

module.exports = router;
