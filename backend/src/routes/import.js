const router = require('express').Router();
const { h } = require('../utils/misc');
const { previewMarg, importMarg, correctPrices } = require('../services/margImport');

// body: { path } = the Marg CSV backup folder or .zip on this computer
router.post('/import/marg/preview', h((req, res) => res.json(previewMarg((req.body || {}).path))));
router.post('/import/marg', h((req, res) => res.json(importMarg((req.body || {}).path))));
router.post('/import/marg/prices', h((req, res) => res.json(correctPrices((req.body || {}).path, !!(req.body || {}).apply))));

module.exports = router;
