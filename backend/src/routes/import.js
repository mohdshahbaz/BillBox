const router = require('express').Router();
const { h } = require('../utils/misc');
const { previewMarg, importMarg } = require('../services/margImport');

// body: { path } = the Marg CSV backup folder or .zip on this computer
router.post('/import/marg/preview', h((req, res) => res.json(previewMarg((req.body || {}).path))));
router.post('/import/marg', h((req, res) => res.json(importMarg((req.body || {}).path))));

module.exports = router;
